"""Fail-closed fixture/trace checks; no control behavior is modeled here."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("button_audit", ROOT / "scripts/audit_shared_ui_buttons.py")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class ButtonAuditTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads((Path(__file__).parent / "button-fixtures.json").read_text())

    def test_full_fixture_set(self):
        fixtures = audit.validate_fixtures(self.document)
        self.assertEqual(len(fixtures), 24)
        self.assertEqual(len(audit.expected_trace(fixtures)), 186)

    def test_missing_expectation_fails(self):
        self.document["fixtures"][0]["expected"]["gpui"].pop()
        with self.assertRaises(ValueError):
            audit.validate_fixtures(self.document)

    def test_duplicate_fixture_fails(self):
        self.document["fixtures"].append(copy.deepcopy(self.document["fixtures"][0]))
        with self.assertRaises(ValueError):
            audit.validate_fixtures(self.document)

    def test_nonfinite_bounds_fail(self):
        self.document["fixtures"][0]["bounds"][0] = float("nan")
        with self.assertRaises(ValueError):
            audit.validate_fixtures(self.document)

    def test_unknown_operation_fails(self):
        self.document["fixtures"][0]["steps"][0]["op"] = "third-state-machine"
        with self.assertRaises(ValueError):
            audit.validate_fixtures(self.document)

    def test_false_is_not_missing_capability(self):
        row = audit.parse_trace("loading|yami|0|false|false|unsupported|unowned")[0]
        self.assertFalse(row["activated"])
        self.assertEqual(row["status"], "unsupported")
        self.assertIsNone(row["focused"])

    def test_malformed_trace_fails(self):
        for text in ("", "x|gpui|0|maybe|false|ok|true", "x|other|0|false|false|ok|true", "not a trace"):
            if not text:
                self.assertNotEqual(audit.parse_trace(text), audit.expected_trace(self.document["fixtures"]))
            else:
                with self.assertRaises(ValueError):
                    audit.parse_trace(text)

    def test_unknown_trace_change_does_not_pass(self):
        expected = audit.expected_trace(self.document["fixtures"])
        mutated = copy.deepcopy(expected)
        mutated[0]["activated"] = not mutated[0]["activated"]
        self.assertNotEqual(expected, mutated)


if __name__ == "__main__":
    unittest.main()
