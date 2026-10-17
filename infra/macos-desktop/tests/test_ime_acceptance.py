"""What: a native callback is required; receipts alone are never IME acceptance."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, HERE / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


trace = load("trace_contract.py", "mac_ime_trace_contract")
acceptance = load("ime-acceptance.py", "mac_ime_acceptance")


def event(i, phase, **kw):
    return {"schema_version": 1, "sequence": i, "monotonic_seconds": float(i),
            "phase": phase, **kw}


def fixture_events():
    return [
        event(1, "key_down_entry", key_code=36),
        event(2, "input_interpret_begin", key_code=36),
        event(3, "callback_entry", callback_kind="insertText"),
        event(4, "callback_enqueued", callback_kind="commit"),
        event(5, "input_interpret_result", key_code=36, handled=True),
        event(6, "key_up_entry", key_code=36),
        event(7, "batch_emitted", batch_sequence=10),
        event(8, "revision_ack", ack_sequence=10),
        event(9, "key_down_entry", key_code=53),
        event(10, "callback_enqueued", callback_kind="cancelled"),
        event(11, "input_source_restored", restored=True),
    ]


def fixture_summary():
    return {"schema_version": 1, "status": "passed", "app_exit_code": 0,
            "final_acceptance": {"commit_callbacks": 1, "commit_count": 1,
                                 "cancel_callbacks": 1, "composing": False,
                                 "focused": False, "final_frame_revision": 21,
                                 "final_frame_identity": {"frame_revision": 21}},
            "composition_checkpoint": {"frame_identity": {"frame_revision": 17}},
            "screenshots": {"initial": {}, "composition": {}, "final": {}},
            "text_roi_differences": {"initial_to_composition": {},
                                     "composition_to_final": {},
                                     "initial_to_final": {}}}


class TraceContractTests(unittest.TestCase):
    def test_all_independent_positive_witnesses(self):
        outcome = trace.evaluate(fixture_summary(), fixture_events(), [], [])
        self.assertEqual(outcome["qualification"], "PASS")
        self.assertTrue(all(v["status"] == "PASS" for v in outcome["gates"].values()))

    def test_return_handled_true_never_substitutes_for_commit_callback(self):
        events = [e for e in fixture_events() if e["phase"] not in
                  ("callback_entry", "callback_enqueued") or e.get("callback_kind") != "commit"]
        result = trace.evaluate(fixture_summary(), events, [], [])
        self.assertEqual(result["gates"]["appkit_return_route"]["status"], "PASS")
        self.assertEqual(result["gates"]["return_commit"]["status"], "FAIL")
        self.assertNotEqual(result["qualification"], "PASS")

    def test_callback_without_ack_is_not_commit(self):
        events = [e for e in fixture_events() if e["phase"] != "revision_ack"]
        result = trace.evaluate(fixture_summary(), events, [], [])
        self.assertEqual(result["gates"]["return_commit"]["status"], "FAIL")
        self.assertEqual(result["gates"]["revision_ack"]["status"], "FAIL")

    def test_missing_final_blur_not_a_pass(self):
        summary = fixture_summary()
        summary["final_acceptance"]["final_frame_revision"] = 17
        self.assertEqual(trace.evaluate(summary, fixture_events(), [], [])[
            "gates"]["final_blur_frame"]["status"], "FAIL")

    def test_abort_restores_source_but_not_normal_cleanup(self):
        summary = {"status": "failed", "cleanup": {"exit_code": -6}}
        events = [event(1, "key_down_entry", key_code=36)]
        aborted = [{"restored": True, "session_closed": True}]
        result = trace.evaluate(summary, events, aborted, ["GPUI_MACOS_IME_ACCEPTANCE_FAIL"])
        self.assertEqual(result["gates"]["input_source_restoration"]["status"], "PASS")
        self.assertEqual(result["gates"]["normal_cleanup"]["status"], "FAIL")

    def test_missing_hardware_remains_unrun(self):
        result = trace.evaluate({"status": "unrun"}, [], [], [])
        self.assertEqual(result["gates"]["return_commit"]["status"], "UNRUN")
        self.assertEqual(result["gates"]["escape_cancel"]["status"], "UNRUN")

    def test_diagnostic_mode_never_qualifies(self):
        summary = fixture_summary()
        summary["diagnostic_preview_first"] = True
        result = trace.evaluate(summary, fixture_events(), [], [])
        self.assertEqual(result["qualification"], "DIAGNOSTIC_ONLY")
        self.assertNotIn("PASS", [v["status"] for v in result["gates"].values()])

    def test_strict_trace_rejects_duplicate_property_and_out_of_order(self):
        with tempfile.TemporaryDirectory() as dirname:
            path = Path(dirname) / "log"
            path.write_text(trace.PREFIX + '{"schema_version":1,"sequence":1,"sequence":1,"phase":"x","monotonic_seconds":1}\n')
            with self.assertRaises(trace.TraceError):
                trace.read_log(path)
            path.write_text("".join(trace.PREFIX + json.dumps(row) + "\n"
                                    for row in [event(2, "x"), event(1, "y")]))
            with self.assertRaises(trace.TraceError):
                trace.read_log(path)

    def test_historical_kotoeri_source_is_exact_mode_not_bundle(self):
        good = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        self.assertTrue(acceptance.is_supported_kotoeri_japanese_romaji_source(good))
        self.assertFalse(acceptance.is_supported_kotoeri_japanese_romaji_source(good.removesuffix(".Japanese")))
        self.assertFalse(acceptance.is_supported_kotoeri_japanese_romaji_source("Kotoeri"))

    def test_failed_abort_receipt_does_not_prove_restoration(self):
        receipt = {"schema_version": 1, "restored": False, "session_closed": True,
                   "host_epoch": 4, "session_epoch": 3}
        with self.assertRaises(acceptance.AcceptanceError):
            acceptance.validate_abort_receipt(receipt, 4, 3)


if __name__ == "__main__":
    unittest.main()
