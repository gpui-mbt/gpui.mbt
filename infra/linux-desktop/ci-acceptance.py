#!/usr/bin/env python3
"""Run the existing real OS-input catalog; never promote generated pixels to goldens."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import input_cases


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def summarize(cases, directory, stages):
    results = []
    raw = directory / 'cases' / 'summary.json'
    records = {}
    if raw.is_file():
        data = json.loads(raw.read_text())
        records = {item['case_id']: item for item in data['results']}
    for case in cases:
        row = {'case_id': case['id'], 'status': 'NOT_RUN', 'reason': case['reason']}
        if case['id'] == 'ime-composition':
            row['reason'] = 'This keyboard catalog does not exercise the separate experimental text-input-v1 IME adapter/harness; native IME acceptance NOT_RUN.'
        if input_cases.runnable(case):
            record = records.get(case['id'])
            if record is None:
                row['reason'] = 'No completed case result; consult stage logs.'
            else:
                base = directory / 'cases' / case['id']
                # Setup stopped before app launch and before any injected event.
                events = base / 'events.jsonl'
                if (record.get('status') == 'error' and
                        record.get('error') == 'RuntimeError: owned Xvfb exited before readiness' and
                        not (base / 'app.log').exists() and
                        (not events.exists() or events.stat().st_size == 0)):
                    row.update(reason=record['error'], runner_status='error', infrastructure_failure=True)
                    results.append(row)
                    continue
                required = {'case.json', 'result.json', 'focused.png', 'final.png',
                            'app.log', 'weston.log', 'xvfb.log', 'events.jsonl'}
                required.update('step-' + step['id'] + '.png' for step in case['steps'])
                # Xvfb stdout/stderr is a diagnostic log and may be empty on success.
                missing = sorted(name for name in required if not (base / name).is_file() or
                                 (name != 'xvfb.log' and (base / name).stat().st_size == 0))
                # A runner PASS alone cannot hide deleted input/pixel evidence.
                passed = record.get('status') == 'passed' and not missing
                row.update(status='PASS' if passed else 'FAIL', runner_status=record.get('status'),
                           missing_artifacts=missing, reason=record.get('error', 'Existing catalog oracle and retained input/pixel evidence.'))
                row['pixel_coverage'] = ('Exact reviewed RGBA golden plus ASCII OCR' if case['oracle']['kind'] == 'reviewed_pixels'
                                         else 'Presented-state checkpoints + completed compositor frame + nonblank captured pixels; no semantic pixel golden')
        results.append(row)
    passed = sum(row['status'] == 'PASS' for row in results)
    failed = sum(row['status'] == 'FAIL' for row in results)
    not_run = sum(row['status'] == 'NOT_RUN' for row in results)
    stage_failed = any(stage['returncode'] != 0 for stage in stages)
    runnable = sum(input_cases.runnable(case) for case in cases)
    status = 'PASS' if passed == runnable and runnable > 0 and not failed and not stage_failed else 'FAIL' if failed or passed else 'NOT_RUN'
    return {'version': 1, 'status': status, 'scope': 'Existing private XTest/Xvfb → Weston X11 → wl_keyboard → GPUI catalog',
            'passed': passed, 'failed': failed, 'not_run': not_run, 'all_coverage_passed': not_run == 0 and status == 'PASS',
            'stages': stages, 'cases': results,
            'limitations': ['Not a physical-device or pure-Wayland input-injection test.',
                            'Layout/unit results are not counted as real-input E2E.',
                            'IME adapter acceptance and held-repeat catalog gaps remain NOT_RUN.']}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    repo = HERE.parents[1]
    root, output = args.profile_root.resolve(), args.output.resolve()
    if root == repo or repo in root.parents or output == repo or repo in output.parents:
        parser.error('profile and evidence directories must be outside the source checkout')
    output.mkdir(parents=True, exist_ok=False)
    cases = input_cases.catalog(input_cases.CASES)
    stages = []
    write(output / 'acceptance.json', summarize(cases, output, stages))
    def run(name, command, env=None):
        with (output / (name + '.log')).open('w') as log:
            log.write('+ ' + repr(list(map(str, command))) + '\n'); log.flush()
            result = subprocess.run(list(map(str, command)), cwd=repo, stdout=log, stderr=subprocess.STDOUT, env=env)
        stages.append({'name': name, 'returncode': result.returncode})
        write(output / 'stages.json', stages)
        if result.returncode:
            raise RuntimeError(name + ' failed, see log')
    try:
        run('source', ['git', 'show', '--no-patch', '--format=fuller', 'HEAD'])
        run('source-archive', ['git', 'archive', '--format=tar', '-o', output / 'source.tar', 'HEAD'])
        run('host', ['sh', '-c', 'cat /etc/os-release; uname -a; dpkg-query -W'])
        run('bootstrap', [sys.executable, HERE / 'gpui-desktop.py', '--root', root, 'bootstrap'])
        run('doctor', [sys.executable, HERE / 'gpui-desktop.py', '--root', root, 'doctor', '--build-only', '--input-e2e', '--ipc'])
        run('build', [sys.executable, HERE / 'gpui-desktop.py', '--root', root, 'build', '--repo', repo])
        run('candidate', [sys.executable, HERE / 'candidate_bundle.py', 'prepare', '--profile-root', root, '--output', output / 'candidate'])
        spec = importlib.util.spec_from_file_location('desktop_profile', HERE / 'gpui-desktop.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        env = module.native_environment(root)
        run('input-e2e', [sys.executable, HERE / 'case_runner.py', '--candidate', output / 'candidate', '--all', '--output', output / 'cases'], env=env)
    except (OSError, RuntimeError) as error:
        write(output / 'blocked.json', {'error': str(error), 'unexecuted_coverage': 'NOT_RUN'})
        # Keep loader failures visible even when bootstrap captured child stderr.
        prefix = root / 'prefix'
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = str(prefix / 'usr/lib/x86_64-linux-gnu')
        with (output / 'link-diagnostics.log').open('w') as log:
            for relative in ('usr/lib/x86_64-linux-gnu/libgtk-3-0t64/gtk-query-immodules-3.0',
                             'usr/bin/weston', 'usr/bin/mousepad', 'usr/bin/ibus-daemon'):
                binary = prefix / relative
                if binary.is_file():
                    log.write(str(binary) + '\n'); log.flush()
                    subprocess.run(['ldd', str(binary)], env=env, stdout=log, stderr=subprocess.STDOUT)
    finally:
        for name in ('installed.json', 'field-build.json'):
            if (root / name).is_file():
                shutil.copyfile(root / name, output / name)
        shutil.copyfile(HERE / 'profile.lock.json', output / 'profile.lock.json')
        report = summarize(cases, output, stages)
        write(output / 'acceptance.json', report)
        manifest = {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(output.rglob('*')) if p.is_file() and not p.is_symlink()}
        write(output / 'sha256.json', manifest)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
