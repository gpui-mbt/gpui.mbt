#!/usr/bin/python3
"""Fail-closed ordering diagnostics; these tests do not exercise a live IME."""
import copy
import unittest

import candidate_lookup_trace as trace
from test_lookup_table import update

CONTEXT = '/org/freedesktop/IBus/InputContext_2'


def sequence(cancel=False):
    frames = []
    pattern = (trace.SPACE, trace.ESCAPE, trace.ESCAPE) if cancel else (trace.SPACE, trace.UP, trace.ENTER)
    for i, (keyval, keycode) in enumerate(pattern):
        frames.append({'category': 'sent_process_key_event', 'path': CONTEXT, 'keyval': keyval,
                       'keycode': keycode, 'state': 0})
        event = {'path': trace.PANEL, 'interface': trace.INTERFACE,
                 'direction': 'RECEIVED', 'type': 'method-call'}
        if i == 2:
            event.update(member='HideLookupTable', signature='', body='()')
        else:
            body = update(['日本', 'にほん'], cursor=1 if i == 0 else 0,
                          cursor_visible=not (cancel and i == 1))
            event.update(member='UpdateLookupTable', signature='vb', body=body.print_(True))
        frames.append(event)
        frames.append({'category': 'sent_process_key_event', 'path': CONTEXT, 'keyval': keyval,
                       'keycode': keycode, 'state': trace.RELEASE})
    return renumber(frames)


def renumber(frames):
    for i, frame in enumerate(frames):
        frame['frame'] = i + 1
    return frames


class CandidateTraceTests(unittest.TestCase):
    def test_selection_and_cancel_are_diagnostic_only(self):
        result = trace.extract(renumber(sequence() + sequence(True)), CONTEXT)
        self.assertIsNotNone(result['selection'])
        self.assertIsNotNone(result['cancellation'])
        self.assertFalse(result['cancellation']['second_update']['cursor_visible'])
        self.assertFalse(result['candidate_table_verified'])
        self.assertFalse(result['pixels_synchronized'])
        self.assertFalse(result['panel_sender_authenticated'])
        self.assertFalse(result['input_context_independently_verified'])

    def test_ambiguous_sequences_do_not_match(self):
        self.assertIsNone(trace.extract(renumber(sequence() + sequence()), CONTEXT)['selection'])

    def test_wrong_owner_and_intervening_input_do_not_match(self):
        frames = sequence()
        frames[3]['path'] = '/org/freedesktop/IBus/InputContext_3'
        self.assertIsNone(trace.extract(frames, CONTEXT)['selection'])
        frames = sequence()
        frames.insert(4, {'category': 'sent_process_key_event', 'path': CONTEXT,
                          'keyval': 65, 'keycode': 30, 'state': 0})
        self.assertIsNone(trace.extract(renumber(frames), CONTEXT)['selection'])

    def test_extra_panel_message_bad_signature_and_missing_hide_fail(self):
        frames = sequence()
        frames.insert(3, copy.deepcopy(frames[1]))
        self.assertIsNone(trace.extract(renumber(frames), CONTEXT)['selection'])
        for change in ({'signature': 's'}, {'direction': 'SENT'}):
            frames = sequence()
            frames[1].update(change)
            self.assertIsNone(trace.extract(frames, CONTEXT)['selection'])
        frames = sequence(True)
        frames[-2]['member'] = 'ShowLookupTable'
        self.assertIsNone(trace.extract(frames, CONTEXT)['cancellation'])

    def test_changed_rows_and_unselected_highlight_fail(self):
        frames = sequence()
        frames[4]['body'] = update(['違う', 'にほん'], cursor=0).print_(True)
        self.assertIsNone(trace.extract(frames, CONTEXT)['selection'])
        frames = sequence()
        frames[4]['body'] = update(['日本', 'にほん'], cursor=0, cursor_visible=False).print_(True)
        self.assertIsNone(trace.extract(frames, CONTEXT)['selection'])

    def test_invalid_context_and_frame_order_fail(self):
        with self.assertRaises(ValueError):
            trace.extract(sequence(), '../invalid')
        frames = sequence()
        frames[1]['frame'] = frames[0]['frame']
        with self.assertRaises(ValueError):
            trace.extract(frames, CONTEXT)


if __name__ == '__main__':
    unittest.main()
