#!/usr/bin/env bash
set -euo pipefail

# What: invoke the restored #40 collector against THIS checkout, never #45's binary.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_ROOT=""
EXPECTED_HEAD=""
DIAGNOSTIC=0
while (($#)); do
  case "$1" in
    --output-root)
      if (($# < 2)); then echo '--output-root requires a path' >&2; exit 2; fi
      OUTPUT_ROOT="$2"; shift 2 ;;
    --expected-head)
      if (($# < 2)); then echo '--expected-head requires a SHA' >&2; exit 2; fi
      EXPECTED_HEAD="$2"; shift 2 ;;
    --diagnostic-preview-first)
      DIAGNOSTIC=1; shift ;;
    *)
      echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "UNRUN: real Kotoeri IME acceptance needs a logged-in Apple Silicon Mac." >&2
  exit 2
fi
if [[ -z "$OUTPUT_ROOT" ]]; then
  echo "usage: $0 --output-root /absolute/new/external/dir [--expected-head SHA] [--diagnostic-preview-first]" >&2
  exit 2
fi
cd "$REPO"
HEAD_SHA="$(git rev-parse HEAD)"
if [[ -n "$EXPECTED_HEAD" && "$EXPECTED_HEAD" != "$HEAD_SHA" ]]; then
  echo "FAIL: HEAD $HEAD_SHA differs from expected $EXPECTED_HEAD" >&2
  exit 2
fi
python3 - "$REPO" "$OUTPUT_ROOT" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1]).resolve(strict=True)
raw = Path(sys.argv[2]).expanduser()
if not raw.is_absolute():
    raise SystemExit("FAIL: output root must be absolute")
if raw.is_symlink() or raw.exists():
    raise SystemExit("FAIL: output root must be a new path, with no existing data")
parent = raw.parent.resolve(strict=True)
if parent == repo or repo in parent.parents or raw == repo or str(raw) == "/":
    raise SystemExit("FAIL: output must be outside the source checkout")
raw.mkdir(mode=0o700)
(raw / "host").mkdir(mode=0o700)
PY
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd -P)"
python3 -m unittest discover -s infra/macos-desktop/tests -p 'test_*.py' \
  > "$OUTPUT_ROOT/contracts.log" 2>&1
./script/test_macos.sh --text-field --target-dir "$OUTPUT_ROOT/model" \
  > "$OUTPUT_ROOT/native-tests.log" 2>&1
./script/build_and_run.sh --demo text-field --test-hooks --build \
  --target-dir "$OUTPUT_ROOT/build" > "$OUTPUT_ROOT/build.log" 2>&1

ARGV=(--repo "$REPO" --profile "$OUTPUT_ROOT/host"
      --app "$OUTPUT_ROOT/build/macos/GpuiTextField.app"
      --output "$OUTPUT_ROOT/acceptance")
if [[ "$DIAGNOSTIC" == 1 ]]; then ARGV+=(--diagnostic-preview-first); fi
set +e
python3 infra/macos-desktop/ime-acceptance.py "${ARGV[@]}" \
  > "$OUTPUT_ROOT/runner.log" 2>&1
RUN_STATUS=$?
if [[ -f "$OUTPUT_ROOT/acceptance/summary.json" ]]; then
  python3 infra/macos-desktop/trace_contract.py \
    --summary "$OUTPUT_ROOT/acceptance/summary.json" \
    --output "$OUTPUT_ROOT/acceptance/gates.json" \
    > "$OUTPUT_ROOT/gates.log" 2>&1
  GATES_STATUS=$?
else
  GATES_STATUS=2
fi
set -e
echo "source=$HEAD_SHA native_runner_exit=$RUN_STATUS gates_exit=$GATES_STATUS"
echo "evidence=$OUTPUT_ROOT"
if [[ "$DIAGNOSTIC" == 1 ]]; then
  echo "DIAGNOSTIC_ONLY: preview-first is never live/pixel E2E PASS."
  exit 1
fi
if [[ "$RUN_STATUS" != 0 || "$GATES_STATUS" != 0 ]]; then exit 1; fi
echo "PASS: exact-HEAD native Kotoeri, callback, ACK, pixels and cleanup."
