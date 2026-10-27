"""Lexical padding only: exact queue/surface/callback/order constraints remain."""
import unittest
import evidence
import gpui_evidence as gpui
from test_gpui_probe import state, line


class WaylandTimestampTests(unittest.TestCase):
    def log(self):
        # Actual attempt-6 timestamp/ID layout, with its unrelated Mesa frame.
        return (
            '[ 689414.925] {Default Queue}  -> xdg_wm_base#11.get_xdg_surface(new id xdg_surface#16, wl_surface#15)\n'
            '[ 689613.563] {Default Queue}  -> wl_surface#15.frame(new id wl_callback#25)\n'
            '[ 689613.601] {mesa egl surface queue}  -> wl_surface#15.frame(new id wl_callback#26)\n'
            '[ 689615.461] {mesa egl surface queue}  -> wl_surface#15.commit()\n'
            + line(state())+'\n'
            '[ 689625.318] {Default Queue} wl_callback#25.done(160955)\n')

    def test_padded_capture_correlates_same_exact_frame(self):
        padded = gpui.presentation_frame_ready(self.log(), 1)
        unpadded = gpui.presentation_frame_ready(self.log().replace('[ ', '['), 1)
        self.assertEqual(padded, unpadded)
        self.assertTrue(padded['ready'])
        self.assertEqual(padded['requested_callbacks'], [25])

    def test_wrong_queue_surface_callback_and_early_done_rejected(self):
        log = self.log()
        done = '[ 689625.318] {Default Queue} wl_callback#25.done(160955)\n'
        mutations = [
            log.replace('{Default Queue}  -> wl_surface#15.frame', '{mesa egl surface queue}  -> wl_surface#15.frame'),
            log.replace('wl_surface#15.frame(new id wl_callback#25)', 'wl_surface#14.frame(new id wl_callback#25)'),
            log.replace('wl_callback#25.done', 'wl_callback#26.done'),
            log.replace('{Default Queue} wl_callback#25.done', '{mesa egl surface queue} wl_callback#25.done'),
            done + log.replace(done, ''),
        ]
        for value in mutations:
            with self.subTest(value=value):
                self.assertFalse(gpui.presentation_frame_ready(value, 1)['ready'])

    def test_bounded_ascii_padding_not_arbitrary_whitespace(self):
        for padding in ('', ' ', ' '*6):
            text='['+padding+'1.000] {Default Queue} wl_callback#25.done(1)\n'
            self.assertIsNotNone(evidence.WAYLAND_LINE.fullmatch(text))
        for padding in (' '*7, '\t', '\n', '\r', '\u00a0', 'x', '-'):
            text='['+padding+'1.000] {Default Queue} wl_callback#25.done(1)\n'
            with self.subTest(padding=repr(padding)):
                self.assertIsNone(evidence.WAYLAND_LINE.fullmatch(text))
                self.assertFalse(gpui.presentation_frame_ready(self.log().replace('[ ', '['+padding), 1)['ready'])

    def test_protocol_text_events_accept_padding_but_reject_malformed(self):
        text='[ 689613.563] {Default Queue} zwp_text_input_v1#7.commit_string(1, "日本")\n'
        records=evidence.text_events(text, 'zwp_text_input_v1', False)
        self.assertEqual(records[0]['text'], '日本')
        for padding in ('\t', ' '*7, '\n'):
            with self.assertRaises(evidence.EvidenceError):
                evidence.text_events(text.replace('[ ', '['+padding), 'zwp_text_input_v1', False)


if __name__ == '__main__':
    unittest.main()
