#!/usr/bin/env python3
"""Fixed-receipt hosted IME execution proposal; missing review fails NOT_RUN."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
RECOVERY = HERE / 'wayland-ime/recovery'
sys.path.insert(0, str(RECOVERY))
import hosted_restore as gate

REPOSITORY = 'gpui-mbt/gpui.mbt'


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def checked_receipt():
    approved = gate.receipt()
    gate.require(approved is not None, 'review receipt is missing: NOT_RUN')
    gate.require(approved.get('repository') == REPOSITORY, 'foreign artifact repository')
    for name in ('review_artifact_id',):
        gate.require(type(approved.get(name)) is int and approved[name] > 0, 'missing review artifact ID')
    for name in ('review_artifact_digest', 'runtime_artifact_digest'):
        gate.require(__import__('re').fullmatch('sha256:[0-9a-f]{64}', approved.get(name, '')), 'missing API artifact digest')
    gate.require(__import__('re').fullmatch('[0-9a-f]{64}', approved.get('prepare_result_sha256', '')), 'missing preparation receipt digest')
    gate.require(os.environ.get('GPUI_CONTAINER_IMAGE') == gate.IMAGE, 'container identity mismatch')
    return approved


def verify_metadata(approved, run, review, runtime):
    gate.require(run.get('id') == approved['artifact_run_id'] and run.get('head_sha') == approved['artifact_head_sha'],
                 'preparation run/head mismatch')
    gate.require(run.get('repository', {}).get('full_name') == REPOSITORY and
                 run.get('repository', {}).get('private') is False, 'not the reviewed public repository')
    gate.require(run.get('status') == 'completed' and run.get('conclusion') == 'success', 'preparation did not succeed')
    for data, id_key, digest_key, prefix in (
            (review, 'review_artifact_id', 'review_artifact_digest', 'linux-ime-review-'),
            (runtime, 'artifact_id', 'runtime_artifact_digest', 'linux-ime-runtime-')):
        gate.require(data.get('id') == approved[id_key] and data.get('expired') is False and
                     data.get('digest') == approved[digest_key], 'artifact identity/digest mismatch')
        gate.require(data.get('name') == prefix + approved['artifact_head_sha'], 'artifact name mismatch')
        binding = data.get('workflow_run', {})
        gate.require(binding.get('id') == approved['artifact_run_id'] and
                     binding.get('head_sha') == approved['artifact_head_sha'], 'artifact belongs to another run/head')


def api(path):
    token = os.environ.get('GH_TOKEN')
    gate.require(bool(token), 'read-only Actions token missing')
    request = urllib.request.Request('https://api.github.com/repos/' + REPOSITORY + path,
                                    headers={'Authorization': 'Bearer ' + token,
                                             'Accept': 'application/vnd.github+json',
                                             'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def native_invocation(root, binding, overlay):
    env = os.environ.copy()
    env.pop('GH_TOKEN', None)
    lib = root/'profile/prefix/usr/lib/x86_64-linux-gnu'
    # Same locked LD/GI paths as prepare-gpui-launcher.py. Host python3-gi is
    # not assumed: use the profile module path from graphical_environment().
    env['LD_LIBRARY_PATH'] = str(lib) + ':' + str(lib/'weston')
    env['GI_TYPELIB_PATH'] = str(lib/'girepository-1.0')
    env['PYTHONPATH'] = str(root/'profile/prefix/usr/lib/python3/dist-packages')
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    native_output = binding/'runs/hosted-ime'
    diagnostic = binding/(native_output.name + '.launcher.log')
    command = ['/usr/bin/python3', HERE/'wayland-ime/gpui_probe.py', '--run-native',
               '--held-shortcuts', '--deployment', overlay, '--output', native_output,
               '--diagnostic-log', diagnostic, '--timeout-seconds', '60']
    return command, env, native_output


def execute(approved, review, runtime, evidence):
    gate.require(gate.digest(review/'prepare-result.json') == approved['prepare_result_sha256'], 'preparation metadata changed')
    prepared = json.loads((review/'prepare-result.json').read_text())
    gate.require(prepared.get('preparation_status') == 'PREPARED' and prepared.get('native_status') == 'NOT_RUN',
                 'invalid preparation result')
    gate.require(prepared.get('source') == {'sha': approved['candidate_source_sha'], 'tree': approved['candidate_source_tree']},
                 'preparation source mismatch')
    gate.require(prepared.get('exact_restore_root') == approved['exact_restore_root'] and
                 prepared.get('container_image') == gate.IMAGE, 'prepared path/image mismatch')
    gate.require(prepared['runtime_archive']['sha256'] == approved['runtime_sha256'] and
                 prepared['inventory_sha256'] == approved['inventory_sha256'], 'prepared archive/inventory mismatch')
    save(evidence/'parent-ownership.json', gate.create_owned_parent(approved))
    root = gate.restore(runtime/'runtime-closure.tar.gz', review/'closure-inventory.json', approved)
    stages = []
    child_env = os.environ.copy()
    child_env.pop('GH_TOKEN', None)

    def run(name, command, env=None):
        with (evidence/(name+'.log')).open('w') as stream:
            stream.write(repr(list(map(str, command)))+'\n'); stream.flush()
            result = subprocess.run(list(map(str, command)), stdout=stream, stderr=subprocess.STDOUT, env=child_env if env is None else env, timeout=180)
        stages.append({'stage': name, 'returncode': result.returncode})
        save(evidence/'stages.json', stages)
        return result.returncode

    binding = evidence/'binding'
    baseline, overlay = binding/'baseline.json', binding/'overlay.json'
    command = [sys.executable, RECOVERY/'prepare_deployment.py', '--recipe-variant', 'hosted',
               '--profile-root', root/'profile', '--mozc-build-root', root/'mozc-build',
               '--candidate-repo', root/'source', '--candidate-build-root', root/'app-build',
               '--candidate-manifest', root/'profile/field-build.json',
               '--output-root', binding, '--output', baseline]
    for name, value in approved['expected'].items():
        command += ['--expected-'+name.replace('_', '-')+'-sha256', value]
    gate.require(run('bind', command) == 0, 'recovery binding failed')
    gate.require(run('overlay', [sys.executable, HERE/'wayland-ime/prepare-gpui-deployment.py',
                 '--baseline', baseline, '--candidate-manifest', root/'profile/field-build.json', '--output', overlay]) == 0,
                 'candidate overlay failed')
    command, env, native_output = native_invocation(root, binding, overlay)
    # Write a conservative attempt marker before launching; exceptions cannot become PASS.
    save(evidence/'execution-status.json', {'native_status': 'INCOMPLETE', 'stage': 'native-attempt'})
    code = run('native', command, env)
    result = json.loads((native_output/'result.json').read_text())
    status = result.get('status', 'error')
    gate.require((code, status) in ((0, 'passed'), (2, 'qualified-partial')), 'native harness failed')
    # The harness, not a JSON-only wrapper oracle, validates input/frame/cleanup proof.
    gate.require(result.get('native_executed') is True, 'native execution proof missing')
    if status == 'passed':
        gate.require(result.get('full_suite_verified') is True and result.get('gpui_ime_verified') is True,
                     'complete native qualification flags missing')
    save(evidence/'execution-status.json', {'native_status': status, 'harness_returncode': code,
         'harness_result_sha256': gate.digest(native_output/'result.json'), 'stages': stages})
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('metadata', 'execute'))
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--review', type=Path)
    parser.add_argument('--runtime', type=Path)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    status = args.evidence/'execution-status.json'
    save(status, {'native_status': 'NOT_RUN', 'stage': args.phase})
    try:
        approved = checked_receipt()
        # Revalidate API identities in both phases, not just before download.
        run = api('/actions/runs/'+str(approved['artifact_run_id']))
        review = api('/actions/artifacts/'+str(approved['review_artifact_id']))
        runtime = api('/actions/artifacts/'+str(approved['artifact_id']))
        verify_metadata(approved, run, review, runtime)
        save(args.evidence/'artifact-metadata.json', {'run': run, 'review': review, 'runtime': runtime})
        if args.phase == 'metadata':
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                for key in ('artifact_run_id', 'review_artifact_id', 'artifact_id'):
                    output.write(key+'='+str(approved[key])+'\n')
            return 0
        gate.require(args.review is not None and args.runtime is not None, 'download directories required')
        return execute(approved, args.review, args.runtime, args.evidence)
    except Exception as error:
        current = json.loads(status.read_text())
        current['error'] = str(error)
        save(status, current)
        return 1


if __name__ == '__main__':
    sys.exit(main())
