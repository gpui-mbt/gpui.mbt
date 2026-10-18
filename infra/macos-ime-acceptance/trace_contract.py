#!/usr/bin/env python3
"""Evaluate independent native witnesses; artifact validation also checks PNG bytes."""
import argparse
import json
import math
from pathlib import Path
from diagnostics import collect_log


class TraceError(ValueError):
    pass


def read_log(path):
    records, errors, failures = collect_log(path)
    events = [r['data'] for r in records if r['kind'] == 'native']
    previous_index, previous_time = -1, -1
    for event in events:
        index, tick = event.get('index'), event.get('uptime_ms')
        if (event.get('schema_version') != 1 or type(index) is not int or index <= previous_index or
                type(tick) not in (int, float) or not math.isfinite(tick) or tick < previous_time or
                not isinstance(event.get('phase'), str) or event['phase'].startswith('truncated')):
            errors.append('invalid, truncated or non-monotonic native chronology')
            break
        previous_index, previous_time = index, tick
    aborted = [r['data'] for r in records if r['kind'] == 'abort']
    return events, aborted, failures, errors


def evaluate(summary, events, aborted=(), failed=(), errors=()):
    final = summary.get('final_acceptance') or {}
    owner = final or (summary.get('initial_checkpoint') or {}).get('frame_identity') or summary.get('initial_state') or {}
    identity = tuple(owner.get(k) for k in ('window_id', 'host_epoch', 'session_epoch'))
    owner_known = all(type(v) is int and v > 0 for v in identity)

    def owned(e):
        return owner_known and tuple(e.get(k) for k in ('window_id', 'host_epoch', 'session_epoch')) == identity

    def find(phase, after=-1, **fields):
        return next((i for i, e in enumerate(events) if i > after and owned(e) and
                     e.get('phase') == phase and all(e.get(k) == v for k, v in fields.items())), None)

    gates = {}

    def gate(name, passed, reached, detail):
        gates[name] = {'status': 'PASS' if passed else 'FAIL' if reached else 'UNRUN', 'detail': detail}

    return_seen = any(e.get('key_code') == 36 for e in events)
    down = find('key_down_entry', key_code=36, dispatch_id=9)
    begin = find('route_begin', down if down is not None else len(events), key_code=36, dispatch_id=9)
    route = find('route_result', begin if begin is not None else len(events), key_code=36, dispatch_id=9)
    up = find('key_up_done', route if route is not None else len(events), key_code=36, dispatch_id=9)
    route_ok = route is not None and up is not None and type(events[route].get('handled')) is bool and (
        events[route].get('handled') is True or events[route].get('fallback_invoked') is True)
    gate('appkit_return_route', route_ok, return_seen, 'owned Return 9 down, input-context route and key-up')

    # A later ACK from another batch cannot attest this callback's ownership.
    def callback_chain(kind, dispatch, key):
        start = find('key_down_entry', dispatch_id=dispatch, key_code=key)
        if start is None:
            return False
        queued = find('callback_enqueued_' + kind, start, dispatch_id=dispatch)
        if queued is None:
            return False
        if kind == 'commit' and not any(owned(e) and e.get('phase') in ('callback_insert', 'callback_unmark') and
                e.get('suppress_callbacks') is False for e in events[start + 1:queued]):
            return False
        batch = find('batch_enqueued', queued)
        if batch is None:
            return False
        batch_event = events[batch]
        sequence = batch_event.get('last_batch_sequence')
        revision = batch_event.get('owner_revision')
        if type(sequence) is not int or sequence <= 0 or batch_event.get('awaiting_sequence') != sequence:
            return False
        delivered = find('batch_delivered', batch, last_batch_sequence=sequence, awaiting_sequence=sequence)
        ack = find('batch_acknowledged', delivered if delivered is not None else len(events),
                   last_presented_batch_sequence=sequence)
        rows = [b for b in final.get('batches', []) if b.get('sequence') == sequence]
        if ack is None or len(rows) != 1:
            return False
        row = rows[0]
        return (row.get('epoch') == identity[2] and row.get('owner_revision') == revision and
                row.get('acknowledged') is True and row.get(kind + '_callbacks' if kind == 'commit' else 'cancel_callbacks', 0) >= 1 and
                events[ack].get('last_presented_owner_revision') == row.get('accepted_revision') and
                events[ack].get('awaiting_ack') is False)

    commit = callback_chain('commit', 9, 36)
    gate('return_commit', route_ok and commit and final.get('commit_callbacks') == 1 and final.get('commit_count') == 1,
         return_seen, 'unsuppressed client callback, commit queue and matching owner/batch ACK')
    gate('revision_ack', commit, return_seen, 'commit batch delivered and ACKed at its accepted revision')
    escape_seen = any(e.get('key_code') == 53 for e in events)
    gate('escape_cancel', callback_chain('cancelled', 11, 53) and final.get('cancel_callbacks', 0) >= 1,
         escape_seen, 'Escape 11 owns cancellation and its batch ACK')

    frame = final.get('final_frame_identity') or {}
    last_ack = max((i for i, e in enumerate(events) if owned(e) and
                    e.get('phase') == 'batch_acknowledged'), default=-1)
    closed = find('session_closed', last_ack)
    presented = next((i for i, e in enumerate(events) if closed is not None and i > closed and
                      owned(e) and e.get('phase') == 'frame_presented' and
                      e.get('frame_revision') == frame.get('frame_revision') and
                      e.get('frame_sha256') == frame.get('frame_sha256') and
                      e.get('last_presented_batch_sequence') == frame.get('batch_sequence') and
                      e.get('last_presented_owner_revision') == frame.get('accepted_revision')), None)
    comp = (summary.get('composition_checkpoint') or {}).get('frame_identity') or {}
    last_batch_frame = max((b.get('frame_identity', {}).get('frame_revision', 0) for b in final.get('batches', [])), default=0)
    blur_ok = (presented is not None and final.get('focused') is False and final.get('composing') is False and
               type(frame.get('frame_revision')) is int and frame['frame_revision'] > max(comp.get('frame_revision', 0), last_batch_frame))
    gate('final_blur_frame', blur_ok, bool(final), 'native frame hash/revision and presenter ACK match newer blurred final identity')
    restored = find('source_restore_result', presented if presented is not None else len(events), handled=True)
    restored_abort = any(a.get('restored') is True and a.get('session_closed') is True and
                         a.get('host_epoch') == identity[1] and a.get('session_epoch') == identity[2]
                         for a in aborted) if owner_known else False
    gate('input_source_restoration', restored is not None or restored_abort,
         bool(aborted) or any(e.get('phase', '').startswith('source_restore') for e in events),
         'explicit owned app-context restoration or verified abort receipt')
    cleanup_ok = (restored is not None and closed is not None and summary.get('app_exit_code') == 0 and
                  type(summary.get('app_exit_code')) is int and summary.get('status') == 'passed' and not aborted and not failed)
    gate('normal_cleanup', cleanup_ok, bool(summary.get('cleanup')) or bool(final) or bool(aborted) or bool(failed),
         'session closed, input context restored and process exited normally without abort')
    pixels = (set(summary.get('screenshots') or {}) == {'initial', 'composition', 'final'} and
              set(summary.get('text_roi_differences') or {}) == {'initial_to_composition', 'composition_to_final', 'initial_to_final'} and
              summary.get('status') == 'passed')
    gate('window_pixel_frames', pixels, bool(final), 'three capture/ROI records; validate_summary independently rechecks retained bytes')
    gate('trace_integrity', not errors and bool(events), bool(events) or bool(errors), 'bounded native chronology has monotonic indices/time')
    diagnostic = summary.get('diagnostic_immediate_preview') is True
    if diagnostic:
        for item in gates.values():
            if item['status'] == 'PASS':
                item['status'] = 'DIAGNOSTIC_ONLY'
    qualification = ('DIAGNOSTIC_ONLY' if diagnostic else
                     'PASS' if all(g['status'] == 'PASS' for g in gates.values()) else
                     'FAIL' if any(g['status'] == 'FAIL' for g in gates.values()) else 'UNRUN')
    return {'schema_version': 1, 'qualification': qualification, 'gates': gates,
            'source': summary.get('source_before'), 'errors': list(errors), 'historical_pr45_result': 'FAIL_NOT_REUSED'}


def summarize(summary, log_path):
    return evaluate(summary, *read_log(log_path))


def require_native_trace(log_path, summary):
    result = summarize(summary, log_path)
    if result['qualification'] != 'PASS':
        raise TraceError('native trace gates incomplete: ' + ', '.join(
            name for name, gate in result['gates'].items() if gate['status'] != 'PASS'))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summary', type=Path, required=True)
    args = parser.parse_args()
    from diagnostics import strict_json
    report = summarize(strict_json(args.summary.read_text()), args.summary.parent / 'app.stdout.log')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['qualification'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
