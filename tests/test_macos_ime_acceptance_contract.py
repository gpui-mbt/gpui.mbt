"""Contract tests: Return, Escape, frame, ACK and cleanup are distinct gates."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "infra" / "macos-ime-acceptance"
sys.path.insert(0, str(HERE))


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


acceptance = load("gpui_exact_head_ime_acceptance", "ime-acceptance.py")
diagnostics = load("gpui_exact_head_diagnostics", "diagnostics.py")
profile = load("gpui_exact_head_profile", "profile.py")
SOURCE = {"commit": "1" * 40, "tree": "2" * 40}
BINARY = "3" * 64
RECT = {"x": 24, "y": 40, "width": 512, "height": 48}
CANDIDATE = {"x": 620.0, "y": 400.0, "width": 1.0, "height": 24.0}
KOTOERI = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"


def frame(revision, session_epoch, frame_revision):
    return {
        "schema_version": 1, "window_id": 1, "host_epoch": 1,
        "session_epoch": session_epoch, "batch_sequence": 1,
        "accepted_revision": revision, "frame_revision": frame_revision,
        "frame_sha256": "4" * 64, "text": "Hello 日本語",
    }


def valid_final():
    batch = {
        "sequence": 1, "owner_revision": 1, "epoch": 1,
        "accepted_revision": 2, "acknowledged": True,
        "preedit_callbacks": 1, "commit_callbacks": 1,
        "cancel_callbacks": 1, "frame_identity": frame(2, 1, 9),
        "candidate_screen_rect": dict(CANDIDATE),
    }
    receipts = [
        {"schema_version": 1, "dispatch_id": i + 1, "key_code": key,
         "down_posted": True, "up_posted": True,
         "down_dispatched": True, "up_dispatched": True,
         "host_epoch": 1, "session_epoch": 1, "batch_sequence": 1,
         "window_sequence": i + 1}
        for i, key in enumerate(acceptance.EXPECTED_KEYS)
    ]
    return {
        "schema_version": 1, "window_id": 1, "host_epoch": 1,
        "session_epoch": 1, "final_session_epoch": 2,
        "input_source": KOTOERI, "preedit_callbacks": 1,
        "commit_callbacks": 1, "cancel_callbacks": 1,
        "committed_text": "Hello 日本語", "composing": False,
        "focused": False, "commit_count": 1, "batches": [batch],
        "receipts": receipts, "candidate_screen_rect": dict(CANDIDATE),
        "final_frame_identity": frame(2, 2, 10),
        "final_frame_revision": 10, "field_bounds": dict(RECT),
        "source_revision": SOURCE["commit"], "source_tree": SOURCE["tree"],
        "binary_sha256": BINARY,
    }


class FiniteKotoeriContractTests(unittest.TestCase):
    def validate(self, record):
        return acceptance.validate_final(
            record, SOURCE, BINARY, initial_revision=1, initial_frame_revision=4
        )

    def test_complete_synthetic_contract_is_admitted(self):
        self.assertEqual(self.validate(valid_final())["commit_callbacks"], 1)

    def test_return_commit_callback_is_required(self):
        value = valid_final()
        value["commit_callbacks"] = 0
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_escape_cancellation_is_required(self):
        value = valid_final()
        value["cancel_callbacks"] = 0
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_final_blur_frame_must_be_newer_than_acked_batch(self):
        value = valid_final()
        value["final_frame_revision"] = 9
        value["final_frame_identity"]["frame_revision"] = 9
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_revision_ack_and_owner_chain_must_be_current(self):
        value = valid_final()
        value["batches"][0]["acknowledged"] = False
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)
        value = valid_final()
        value["batches"][0]["owner_revision"] = 0
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_exact_return_key_dispatch_receipts_are_required(self):
        value = valid_final()
        value["receipts"][8]["up_dispatched"] = False
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_source_and_binary_must_match(self):
        value = valid_final()
        value["source_tree"] = "5" * 40
        with self.assertRaises(acceptance.AcceptanceError):
            self.validate(value)

    def test_cleanup_restoration_ack_must_be_complete(self):
        receipt = {"schema_version": 1, "restored": True, "session_closed": True,
                   "host_epoch": 1, "session_epoch": 1}
        self.assertEqual(acceptance.validate_abort_receipt(receipt, 1, 1), receipt)
        for broken_key in ("restored", "session_closed"):
            broken = dict(receipt)
            broken[broken_key] = False
            with self.assertRaises(acceptance.AcceptanceError):
                acceptance.validate_abort_receipt(broken, 1, 1)


class DiagnosticEvidenceTests(unittest.TestCase):
    def log(self, entries):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "app.stdout.log"
        path.write_text("\n".join(entries) + "\n", encoding="utf-8")
        return path

    def test_historical_return_delivered_but_commit_missing_stays_failed(self):
        # WHAT: replay the independently archived failure fields, not its success.
        rows = [
            ("GPUI_MACOS_IME_DIAGNOSTIC_TRACE ", {
                "phase": "return_route_begin", "key_code": 36, "session_epoch": 1, "dispatch_id": 9}),
            ("GPUI_MACOS_IME_DIAGNOSTIC_TRACE ", {
                "phase": "return_route_result", "key_code": 36, "session_epoch": 1,
                "dispatch_id": 9, "input_context_handled": True, "interpret_fallback_invoked": False}),
            ("GPUI_MACOS_IME_DISPATCH_TRACE ", {
                "phase": "dispatch", "key_code": 36, "dispatch_id": 9, "up_dispatched": True}),
            ("GPUI_MACOS_IME_DIAGNOSTIC_TRACE ", {
                "phase": "operation_timeout", "key_code": 36,
                "loop_iterations": 200, "iteration_limit": 200, "commit_callbacks": 0}),
            ("GPUI_MACOS_IME_ABORTED ", {
                "schema_version": 1, "restored": True, "session_closed": True,
                "host_epoch": 1, "session_epoch": 1}),
        ]
        lines = [prefix + json.dumps(record) for prefix, record in rows]
        lines.insert(4, "GPUI_MACOS_IME_ACCEPTANCE_FAIL timed out waiting for the accepted IME operation observation")
        result = diagnostics.analyze_log(self.log(lines))
        self.assertEqual(result["integrity"], "PASS")
        self.assertTrue(result["return_dispatched_without_commit"])
        self.assertTrue(result["return_timed_out"])
        self.assertTrue(result["source_restored_observed"])
        self.assertFalse(result["final_acceptance_observed"])
        self.assertEqual(result["operation_loop_iterations"], 200)
        self.assertEqual(result["root_cause"], "undetermined")

    def test_current_trace_keeps_client_callback_before_ACK(self):
        observations = [
            ("route_begin", 36, None),
            ("callback_marked", 36, None),
            ("route_result", 36, True),
            ("callback_insert", 36, None),
            ("key_up_done", 36, None),
            ("batch_enqueued", -1, None),
            ("batch_delivered", -1, None),
            ("batch_acknowledged", -1, None),
            ("source_restored", -1, None),
        ]
        lines = [
            "GPUI_MACOS_IME_TRACE " + json.dumps(
                {"schema_version": 1, "index": i, "phase": phase,
                 "key_code": key, "session_epoch": 1, "dispatch_id": 9,
                 "handled": handled, "awaiting_ack": phase == "batch_enqueued"})
            for i, (phase, key, handled) in enumerate(observations)
        ]
        result = diagnostics.analyze_log(self.log(lines))
        self.assertEqual(result["integrity"], "PASS")
        self.assertTrue(result["return_route_observed"])
        self.assertEqual(result["return_callback_observations"], 1)
        self.assertEqual(result["ack_count"], 1)
        self.assertFalse(result["return_dispatched_without_commit"])
        self.assertTrue(result["source_restored_observed"])

    def test_duplicate_trace_index_and_nonfinite_payload_are_invalid(self):
        native = "GPUI_MACOS_IME_TRACE "
        lines = [
            native + json.dumps({"index": 1, "phase": "route_begin"}),
            native + json.dumps({"index": 1, "phase": "route_result"}),
            native + '{"index":NaN,"phase":"route_result"}',
        ]
        result = diagnostics.analyze_log(self.log(lines))
        self.assertEqual(result["integrity"], "FAIL")
        self.assertGreaterEqual(len(result["errors"]), 2)

    def test_truncated_trace_cannot_qualify_native_evidence(self):
        result = diagnostics.analyze_log(self.log([
            "GPUI_MACOS_IME_TRACE " + json.dumps({
                "schema_version": 1, "index": 0,
                "phase": "truncated_ordinary", "limit": 180,
            })
        ]))
        self.assertEqual(result["integrity"], "FAIL")

    def test_callback_observation_is_not_e2e_pass(self):
        result = diagnostics.analyze_log(self.log([
            "GPUI_MACOS_IME_TRACE " + json.dumps({
                "index": 0, "phase": "callback_insert", "key_code": 36,
                "session_epoch": 1, "dispatch_id": 9}),
        ]))
        self.assertFalse(result["final_acceptance_observed"])
        self.assertFalse(result["return_dispatched_without_commit"])


class LocalStaticTests(unittest.TestCase):
    def test_runner_profile_and_diagnostics_parse(self):
        for name in ("profile.py", "ime-acceptance.py", "diagnostics.py"):
            compile((HERE / name).read_text(encoding="utf-8"), name, "exec")

    def test_test_hooks_are_separate_from_release_behavior(self):
        native = (ROOT / "platform/macos/native.m").read_text()
        self.assertIn("#ifdef GPUI_TESTING\n#include \"../../tests/native/macos_ime_trace.inc\"", native)
        self.assertIn("#define GPUI_IME_TRACE(W, P, K, H, F) ((void)0)", native)
        trace = (ROOT / "tests/native/macos_ime_trace.inc").read_text()
        for phase in ("awaiting_ack", "last_presented_batch_sequence", "source_restored"):
            self.assertIn(phase, trace if phase != "source_restored" else native)
        self.assertNotIn('@"text":', trace)

    def test_shell_entrypoint_parses_under_bash(self):
        outcome = subprocess.run(["bash", "-n", str(HERE / "run.sh")],
                                 text=True, capture_output=True, check=False)
        self.assertEqual(outcome.returncode, 0, outcome.stderr)

    def test_immediate_preview_mode_cannot_claim_pixel_acceptance(self):
        source = (HERE / "ime-acceptance.py").read_text(encoding="utf-8")
        self.assertIn("if diagnostic_immediate_preview:", source)
        self.assertIn('raise AcceptanceError(\n                "DIAGNOSTIC ONLY:', source)
        self.assertIn('parser.add_argument("--diagnostic-immediate-preview", action="store_true"', source)

    def test_profile_refuses_non_arm64_os(self):
        with mock.patch.object(profile.platform, "system", return_value="Linux"):
            with self.assertRaises(profile.ProfileError):
                profile.host_identity()


if __name__ == "__main__":
    unittest.main()
