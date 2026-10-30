#!/usr/bin/env python3
"""Compare a prepare-only OCI host candidate with retained baseline evidence."""
import hashlib, json, os, re, stat, subprocess
from pathlib import Path
root = Path(os.environ['REFERENCE_ROOT'])
if root.is_symlink() or not root.is_dir():
    raise SystemExit('invalid reference root')
def read(name):
    if name not in ('prepare-result.json', 'host.log', 'host-executables.json'):
        raise ValueError('unexpected name')
    p = root / name
    st = p.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_size > 1048576:
        raise ValueError('unsafe reference file')
    return p.read_bytes()
receipt = read('prepare-result.json')
if hashlib.sha256(receipt).hexdigest() != '6ef6331d926bf62e0b4d57344e2a4fba86a6fe76e8d98dafd06c004b3f4081a2':
    raise SystemExit('prepared reference receipt differs from reviewed digest')
result = json.loads(receipt)
if result.get('preparation_status') != 'PREPARED' or result.get('native_status') != 'NOT_RUN':
    raise SystemExit('reference is not a prepare-only result')
old = read('host.log')
exe = read('host-executables.json')
if hashlib.sha256(old).hexdigest() != result['host_inventory_sha256'] or hashlib.sha256(exe).hexdigest() != result['host_executables_sha256']:
    raise SystemExit('reference digest mismatch')
def packages(text):
    result = {}
    for line in text.splitlines():
        m = re.fullmatch(r'([a-z0-9][a-z0-9+.-]*(?::[a-z0-9]+)?)\s+([0-9][A-Za-z0-9.+:~_-]*)', line)
        if m:
            if m[1] in result: raise ValueError('duplicate package')
            result[m[1]] = m[2]
    return result
baseline = packages(old.decode('utf-8'))
if len(baseline) < 100: raise SystemExit('incomplete baseline inventory')
current = packages(subprocess.check_output(['dpkg-query', '-W'], text=True))
missing_or_changed = [(name, version, current.get(name)) for name, version in baseline.items() if current.get(name) != version]
for name, before, after in missing_or_changed:
    print('package drift:', name, before, after)
identities = json.loads(exe)['host_executables']
for name in ('/usr/bin/convert', '/usr/bin/dbus-daemon', '/usr/bin/python3'):
    expected = identities[name]['sha256']
    if not re.fullmatch('[0-9a-f]{64}', expected): raise ValueError('invalid executable hash')
    actual = hashlib.sha256(Path(name).read_bytes()).hexdigest()
    print('executable match:', name, actual == expected)
    if actual != expected: missing_or_changed.append((name, expected, actual))
print('baseline packages:', len(baseline), 'drift count:', len(missing_or_changed))
print('native_status: NOT_RUN; approved_for_execution: false')
if missing_or_changed: raise SystemExit('host snapshot differs from prepared inventory')
