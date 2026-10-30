#!/usr/bin/python3
"""Two-row screenshot diagnostic tests; never qualifies the live IME gate."""
import unittest
from pathlib import Path

from PIL import Image, ImageDraw
import candidate_pixels as pixels
import replay_candidate_pixels as replay


FIXTURES = Path(__file__).parent / 'tests/candidate-pixels'
BEFORE_BOXES = [[190, 286, 242, 310], [190, 313, 242, 337]]
AFTER_BOXES = [[190, 245, 242, 269], [190, 273, 242, 297]]


def table(selection, first='日本', second='にほん'):
    return {'visible': True, 'cursor_visible': True, 'rows': [
        {'text': first, 'selected': selection == 0},
        {'text': second, 'selected': selection == 1}]}


class CandidatePixelTests(unittest.TestCase):
    def setUp(self):
        self.before = Image.open(FIXTURES / 'row2-selected.png').convert('RGB')
        self.after = Image.open(FIXTURES / 'row1-selected.png').convert('RGB')

    def compare(self, *, before=None, after=None, before_boxes=None, after_boxes=None,
                before_lookup=None, after_lookup=None, output=('日本', 'にほん')):
        observed = iter(output)
        return pixels.compare_two_rows(before or self.before, after or self.after,
            before_boxes or BEFORE_BOXES, after_boxes or AFTER_BOXES,
            before_lookup or table(1), after_lookup or table(0), lambda _png: next(observed))

    def test_two_row_pixel_check_is_never_gate_pass(self):
        result = self.compare()
        self.assertEqual(result['status'], 'partial')
        self.assertFalse(result['candidate_table_verified'])
        self.assertEqual(result['rows_checked'], 2)
        self.assertEqual(result['observed'], ['日本', 'にほん'])

    def test_swapped_images_or_hidden_highlight_fail(self):
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before=self.after, after=self.before)
        modified = self.before.copy()
        ImageDraw.Draw(modified).rectangle(BEFORE_BOXES[1], fill='white')
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before=modified)

    def test_highlight_in_both_rows_fails(self):
        modified = self.before.copy()
        ImageDraw.Draw(modified).rectangle(BEFORE_BOXES[0], fill=(53, 132, 228))
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before=modified)

    def test_wrong_text_and_changed_lookup_fail(self):
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(output=('日本', '偽'))
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(after_lookup=table(0, second='偽'))
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before_lookup=table(1, second='に ほん'),
                         after_lookup=table(0, second='に ほん'))
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before_lookup=table(1, first='Ａ'),
                         after_lookup=table(0, first='Ａ'), output=('A', 'にほん'))

    def test_selection_and_hidden_state_fail(self):
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before_lookup=table(0))
        hidden = table(1)
        hidden['visible'] = False
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before_lookup=hidden)

    def test_bad_bounds_and_size_fail(self):
        for boxes in ([[0, 0, 2000, 25], [0, 26, 52, 50]],
                      [[190, 286, 242, 320], [190, 313, 242, 337]],
                      [[True, 286, 242, 310], [190, 313, 242, 337]]):
            with self.subTest(boxes=boxes), self.assertRaises(pixels.PixelEvidenceError):
                self.compare(before_boxes=boxes)
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before=Image.new('RGB', (1, 1)))

    def test_blank_unselected_row_fails_before_ocr(self):
        modified = self.before.copy()
        ImageDraw.Draw(modified).rectangle(BEFORE_BOXES[0], fill='white')
        with self.assertRaises(pixels.PixelEvidenceError):
            self.compare(before=modified)

    def test_replay_requires_an_ordered_lookup_body_line(self):
        lines = ['header'] * 11 + ['Body: bogus']
        with self.assertRaises(ValueError):
            replay.table_at(lines, 12)
        with self.assertRaises(ValueError):
            replay.table_at(lines, 0)

    def test_selected_region_returns_to_assumed_background_only(self):
        commit = Image.open(FIXTURES / 'after-commit.png').convert('RGB')
        cancel = Image.open(FIXTURES / 'after-cancel.png').convert('RGB')
        box = [142, 350, 248, 480]
        result = pixels.compare_cleared_region(self.before, commit, cancel, box, [255, 255, 255])
        self.assertFalse(result['candidate_table_verified'])
        self.assertGreater(result['shown_pixels_differing'], 1000)
        for changed_commit, changed_cancel in ((self.before, cancel), (commit, self.before)):
            with self.subTest(commit=changed_commit is self.before), self.assertRaises(pixels.PixelEvidenceError):
                pixels.compare_cleared_region(self.before, changed_commit, changed_cancel, box, [255, 255, 255])
        with self.assertRaises(pixels.PixelEvidenceError):
            pixels.compare_cleared_region(commit, commit, cancel, box, [255, 255, 255])


if __name__ == '__main__':
    unittest.main()
