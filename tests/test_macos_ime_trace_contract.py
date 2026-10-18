"""What: native evidence must prove causal ownership, never only a later ACK."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1] / 'infra/macos-ime-acceptance'
sys.path.insert(0, str(HERE))
import trace_contract as trace


def fixture():
    owner = {'window_id': 1, 'host_epoch': 2, 'session_epoch': 3}
    events = []

    def event(phase, **fields):
        events.append(dict(owner, schema_version=1, index=len(events), uptime_ms=len(events),
                           phase=phase, **fields))

    rows = []
    for dispatch, key, kind, sequence in ((9, 36, 'commit', 10), (11, 53, 'cancelled', 12)):
        event('key_down_entry', key_code=key, dispatch_id=dispatch)
        if key == 36:
            event('route_begin', key_code=key, dispatch_id=dispatch)
            event('callback_insert', suppress_callbacks=False)
        event('callback_enqueued_' + kind, dispatch_id=dispatch)
        event('route_result', key_code=key, dispatch_id=dispatch, handled=True)
        event('key_up_done', key_code=key, dispatch_id=dispatch)
        event('batch_enqueued', last_batch_sequence=sequence, awaiting_sequence=sequence, owner_revision=sequence)
        event('batch_delivered', last_batch_sequence=sequence, awaiting_sequence=sequence)
        event('batch_acknowledged', last_presented_batch_sequence=sequence,
              last_presented_owner_revision=sequence + 1, awaiting_ack=False)
        rows.append({'sequence': sequence, 'epoch': 3, 'owner_revision': sequence,
                     'accepted_revision': sequence + 1, 'acknowledged': True,
                     'commit_callbacks': int(key == 36), 'cancel_callbacks': int(key == 53),
                     'frame_identity': {'frame_revision': sequence + 1}})
    frame = dict(owner, frame_revision=20, frame_sha256='a' * 64, batch_sequence=12, accepted_revision=13)
    event('session_closed')
    event('frame_presented', frame_revision=20, frame_sha256='a' * 64,
          last_presented_batch_sequence=12, last_presented_owner_revision=13)
    event('source_restore_result', handled=True)
    final = dict(owner, commit_callbacks=1, commit_count=1, cancel_callbacks=1,
                 focused=False, composing=False, batches=rows, final_frame_identity=frame)
    summary = {'status': 'passed', 'app_exit_code': 0, 'final_acceptance': final,
               'composition_checkpoint': {'frame_identity': {'frame_revision': 8}},
               'screenshots': dict.fromkeys(('initial', 'composition', 'final'), {}),
               'text_roi_differences': dict.fromkeys(('initial_to_composition', 'composition_to_final', 'initial_to_final'), {})}
    return summary, events


class NativeTraceContractTests(unittest.TestCase):
    def test_complete_native_chain_passes_trace_gates(self):
        self.assertEqual(trace.evaluate(*fixture())['qualification'], 'PASS')

    def test_each_missing_native_boundary_blocks_pass(self):
        for phase in ('key_down_entry', 'route_begin', 'route_result', 'key_up_done', 'callback_insert',
                      'callback_enqueued_commit', 'batch_enqueued', 'batch_delivered', 'batch_acknowledged',
                      'callback_enqueued_cancelled', 'frame_presented', 'session_closed', 'source_restore_result'):
            with self.subTest(phase=phase):
                summary, events = fixture()
                events = [e for e in events if e['phase'] != phase]
                self.assertNotEqual(trace.evaluate(summary, events)['qualification'], 'PASS')

    def test_foreign_session_window_host_or_batch_ACK_cannot_attest_commit(self):
        for key in ('window_id', 'host_epoch', 'session_epoch', 'last_presented_batch_sequence',
                    'last_presented_owner_revision'):
            with self.subTest(key=key):
                summary, events = fixture()
                ack = next(e for e in events if e['phase'] == 'batch_acknowledged')
                ack[key] += 1
                self.assertEqual(trace.evaluate(summary, events)['gates']['return_commit']['status'], 'FAIL')

    def test_cancel_from_another_dispatch_is_not_escape(self):
        summary, events = fixture()
        next(e for e in events if e['phase'] == 'callback_enqueued_cancelled')['dispatch_id'] = 10
        self.assertEqual(trace.evaluate(summary, events)['gates']['escape_cancel']['status'], 'FAIL')

    def test_suppressed_client_entry_does_not_prove_Return_commit(self):
        summary, events = fixture()
        next(e for e in events if e['phase'] == 'callback_insert')['suppress_callbacks'] = True
        self.assertEqual(trace.evaluate(summary, events)['gates']['return_commit']['status'], 'FAIL')

    def test_final_frame_hash_must_match_presented_frame(self):
        summary, events = fixture()
        next(e for e in events if e['phase'] == 'frame_presented')['frame_sha256'] = 'b' * 64
        self.assertEqual(trace.evaluate(summary, events)['gates']['final_blur_frame']['status'], 'FAIL')

    def test_aborted_cleanup_never_becomes_normal_exit(self):
        summary, events = fixture()
        summary['status'] = 'failed'
        summary['app_exit_code'] = -6
        result = trace.evaluate(summary, events, [{'host_epoch': 2, 'session_epoch': 3,
                                                  'restored': True, 'session_closed': True}])
        self.assertEqual(result['gates']['input_source_restoration']['status'], 'PASS')
        self.assertEqual(result['gates']['normal_cleanup']['status'], 'FAIL')

    def test_failed_Return_can_prove_owned_abort_restore_without_qualifying_cleanup(self):
        summary, events = fixture()
        summary['initial_checkpoint'] = {'frame_identity': {'window_id': 1, 'host_epoch': 2, 'session_epoch': 3}}
        summary.pop('final_acceptance')
        summary.update(status='failed', app_exit_code=-6)
        abort = {'host_epoch': 2, 'session_epoch': 3, 'restored': True, 'session_closed': True}
        result = trace.evaluate(summary, events[:3], [abort])
        self.assertEqual(result['gates']['input_source_restoration']['status'], 'PASS')
        self.assertEqual(result['gates']['normal_cleanup']['status'], 'FAIL')

    def test_failed_restore_cannot_borrow_final_acceptance(self):
        summary, events = fixture()
        next(e for e in events if e['phase'] == 'source_restore_result')['handled'] = False
        self.assertEqual(trace.evaluate(summary, events)['gates']['input_source_restoration']['status'], 'FAIL')

    def test_stale_frame_closure_and_restore_before_Return_are_rejected(self):
        for phase in ('frame_presented', 'session_closed', 'source_restore_result'):
            with self.subTest(phase=phase):
                summary, events = fixture()
                event = next(e for e in events if e['phase'] == phase)
                events.remove(event)
                events.insert(0, event)
                for i, e in enumerate(events):
                    e.update(index=i, uptime_ms=i)
                self.assertNotEqual(trace.evaluate(summary, events)['qualification'], 'PASS')

    def test_no_hardware_evidence_remains_unrun(self):
        result = trace.evaluate({}, [])
        self.assertEqual(result['qualification'], 'UNRUN')
        self.assertTrue(all(g['status'] == 'UNRUN' for g in result['gates'].values()))

    def test_diagnostic_mode_cannot_qualify_any_gate(self):
        summary, events = fixture()
        summary['diagnostic_immediate_preview'] = True
        result = trace.evaluate(summary, events)
        self.assertEqual(result['qualification'], 'DIAGNOSTIC_ONLY')
        self.assertNotIn('PASS', [g['status'] for g in result['gates'].values()])

    def test_malformed_truncated_or_backward_clock_fails_closed(self):
        _, events = fixture()
        for change in ('duplicate', 'time', 'truncated', 'nonfinite'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as d:
                rows = copy.deepcopy(events)
                if change == 'duplicate':
                    rows[1]['index'] = rows[0]['index']
                elif change == 'time':
                    rows[1]['uptime_ms'] = -1
                elif change == 'truncated':
                    rows[1]['phase'] = 'truncated_ordinary'
                else:
                    rows[1]['uptime_ms'] = float('inf')
                path = Path(d) / 'app.stdout.log'
                path.write_text(''.join('GPUI_MACOS_IME_TRACE ' + json.dumps(e) + '\n' for e in rows))
                self.assertTrue(trace.read_log(path)[3])

    def test_retained_validator_rejects_missing_trace_without_trusting_cached_gates(self):
        summary, _ = fixture()
        summary['native_gates'] = {'qualification': 'PASS'}
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'app.stdout.log'
            path.write_text('')
            with self.assertRaises(trace.TraceError):
                trace.require_native_trace(path, summary)


if __name__ == '__main__':
    unittest.main()
