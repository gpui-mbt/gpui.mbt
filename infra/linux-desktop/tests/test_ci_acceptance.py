import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_acceptance', HERE / 'ci-acceptance.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class AcceptanceReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cases = ci.input_cases.catalog()

    def fixture(self, status='passed'):
        rows = []
        for case in self.cases:
            if not ci.input_cases.runnable(case):
                rows.append({'case_id': case['id'], 'status': 'skipped-' + case['disposition']})
                continue
            base = self.root / 'cases' / case['id']
            base.mkdir(parents=True)
            names = ['case.json', 'result.json', 'focused.png', 'final.png', 'app.log',
                     'weston.log', 'xvfb.log', 'events.jsonl']
            names += ['step-' + step['id'] + '.png' for step in case['steps']]
            for name in names:
                (base / name).write_text('fixture')
            rows.append({'case_id': case['id'], 'status': status})
        (self.root / 'cases' / 'summary.json').write_text(json.dumps({'results': rows}))

    def report(self, stages=None):
        return ci.summarize(self.cases, self.root, stages or [])

    def test_missing_execution_is_not_run_and_not_green(self):
        result = self.report([{'name': 'doctor', 'returncode': 1}])
        self.assertEqual(result['status'], 'NOT_RUN')
        self.assertEqual(result['not_run'], 9)
        self.assertFalse(result['all_coverage_passed'])

    def test_successful_keyboard_catalog_keeps_ime_repeat_not_run(self):
        self.fixture()
        result = self.report()
        self.assertEqual((result['status'], result['passed'], result['not_run']), ('PASS', 7, 2))
        self.assertFalse(result['all_coverage_passed'])
        ime = next(row for row in result['cases'] if row['case_id'] == 'ime-composition')
        self.assertEqual(ime['status'], 'NOT_RUN')
        self.assertIn('experimental text-input-v1', ime['reason'])
        self.assertNotIn('unimplemented', ime['reason'])
        basic = next(row for row in result['cases'] if row['case_id'] == 'basic-text-shift')
        self.assertIn('RGBA', basic['pixel_coverage'])

    def test_failed_case_or_expected_failure_is_not_success(self):
        self.fixture('expected-failure')
        self.assertEqual(self.report()['status'], 'FAIL')
        self.assertEqual(self.report()['passed'], 0)

    def test_missing_pixel_or_input_evidence_fails(self):
        self.fixture()
        for name in ['final.png', 'events.jsonl']:
            path = self.root / 'cases' / 'basic-text-shift' / name
            original = path.read_bytes()
            path.unlink()
            result = self.report()
            self.assertEqual(result['status'], 'FAIL')
            self.assertEqual(result['failed'], 1)
            path.write_bytes(original)

    def test_quiet_xvfb_log_is_retained_but_need_not_be_nonempty(self):
        self.fixture()
        path = self.root / 'cases' / 'basic-text-shift' / 'xvfb.log'
        path.write_bytes(b'')
        self.assertEqual(self.report()['status'], 'PASS')
        path.unlink()
        self.assertEqual(self.report()['status'], 'FAIL')

    def test_empty_pixel_or_delivery_evidence_still_fails(self):
        self.fixture()
        for name in ['final.png', 'events.jsonl']:
            path = self.root / 'cases' / 'basic-text-shift' / name
            original = path.read_bytes()
            path.write_bytes(b'')
            self.assertEqual(self.report()['status'], 'FAIL')
            path.write_bytes(original)

    def test_failed_stage_cannot_be_overruled_by_case_success(self):
        self.fixture()
        self.assertEqual(self.report([{'name': 'input-e2e', 'returncode': 2}])['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
