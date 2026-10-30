#!/usr/bin/python3
"""Diagnostic only: extract candidate input/panel ordering from one D-Bus log.

Frame order is log order, not proof of UI dispatch, sender identity, or pixels.
This tool does not alter the candidate-table acceptance gate.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import evidence
import lookup_table

PANEL = '/org/freedesktop/IBus/Panel'
INTERFACE = 'org.freedesktop.IBus.Panel'
RELEASE = 1 << 30
SPACE, UP, ENTER, ESCAPE = (32, 57), (65362, 103), (65293, 28), (65307, 1)
MEMBERS = {'UpdateLookupTable', 'ShowLookupTable', 'HideLookupTable'}


def extract(frames, context):
    """Find unique selection and cancellation sequences in strict parser output.

    Extra key calls, panel state messages, or multiple possible matches make a
    sequence unavailable. Caller must independently validate the input context.
    """
    if not re.fullmatch(r'/org/freedesktop/IBus/InputContext_[0-9]+', context):
        raise ValueError('invalid input context path')
    if any(type(f.get('frame')) is not int for f in frames) or any(
            a['frame'] >= b['frame'] for a, b in zip(frames, frames[1:])):
        raise ValueError('frames must be strictly ordered')
    keys = [f for f in frames if f.get('category') == 'sent_process_key_event']
    panels = [f for f in frames if f.get('path') == PANEL and
              f.get('interface') == INTERFACE and f.get('member') in MEMBERS]

    def match(pattern, cancel):
        matches = []
        expected_keys = [(v, c, state) for v, c in pattern for state in (0, RELEASE)]
        for i in range(len(keys) - 5):
            window = keys[i:i + 6]
            if any(k.get('path') != context for k in window):
                continue
            if [(k.get('keyval'), k.get('keycode'), k.get('state')) for k in window] != expected_keys:
                continue
            events = []
            for j in (0, 2, 4):
                found = [p for p in panels if window[j]['frame'] < p['frame'] < window[j + 1]['frame']]
                if len(found) != 1:
                    break
                events.append(found[0])
            if len(events) != 3 or any(p.get('direction') != 'RECEIVED' or
                                       p.get('type') != 'method-call' for p in events):
                continue
            if len([p for p in panels if window[0]['frame'] < p['frame'] < window[-1]['frame']]) != 3:
                continue
            if any(p.get('member') != 'UpdateLookupTable' or p.get('signature') != 'vb'
                   for p in events[:2]):
                continue
            if (events[2].get('member'), events[2].get('signature'), events[2].get('body')) != (
                    'HideLookupTable', '', '()'):
                continue
            try:
                first, second = [lookup_table.decode_gdbus_body(p['body']) for p in events[:2]]
            except (KeyError, lookup_table.LookupEvidenceError):
                continue
            if not (first['visible'] and first['cursor_visible'] and first['cursor'] == 1 and
                    second['visible'] and second['cursor'] == 0 and
                    len(first['rows']) >= 2 and len(second['rows']) >= 1):
                continue
            if not cancel and (not second['cursor_visible'] or
                    [r['text'] for r in first['rows']] != [r['text'] for r in second['rows']]):
                continue
            matches.append({'key_frames': [k['frame'] for k in window],
                            'panel_frames': [p['frame'] for p in events],
                            'first_update': first, 'second_update': second})
        return matches[0] if len(matches) == 1 else None

    return {'selection': match((SPACE, UP, ENTER), False),
            'cancellation': match((SPACE, ESCAPE, ESCAPE), True),
            'input_context_independently_verified': False,
            'panel_sender_authenticated': False,
            'pixels_synchronized': False,
            'candidate_table_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--context', required=True)
    args = parser.parse_args()
    raw = args.log.read_bytes()
    frames, _ = evidence.strict_dbus_frames(raw.decode('utf-8'),
        Path(__file__).parent / 'recovery/transport_diagnostics.py')
    result = extract(frames, args.context)
    result['log_sha256'] = hashlib.sha256(raw).hexdigest()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
