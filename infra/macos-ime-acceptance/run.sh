#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT_DIR"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'UNRUN: live Kotoeri acceptance requires a logged-in Apple Silicon macOS desktop.' >&2
  exit 2
fi
if (($# != 1)); then
  echo "usage: $0 /absolute/new/external/evidence-directory" >&2
  exit 2
fi
RUN_DIR="$(python3 - "$1" "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
directory = Path(sys.argv[1]).expanduser()
if not directory.is_absolute():
    raise SystemExit("evidence directory must be absolute")
directory = directory.resolve(strict=False)
root = Path(sys.argv[2]).resolve(strict=True)
if not directory.is_absolute() or directory == Path("/") or root == directory or root in directory.parents:
    raise SystemExit("evidence directory must be external to the repository")
if directory.is_symlink() or directory.exists():
    raise SystemExit("evidence directory must be a new, non-symlink path")
directory.mkdir(parents=True, exist_ok=False)
print(directory.resolve(strict=True))
PY
)"
mkdir -p "$RUN_DIR/profile"
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo 'FAIL: exact-source Kotoeri evidence requires a clean worktree.' >&2
  exit 1
fi
HEAD_SHA="$(git rev-parse HEAD)"
BASE_SHA="451ead8fce495a4ad471b577b06c3442d8165011"
if [[ "$(git merge-base "$BASE_SHA" "$HEAD_SHA")" != "$BASE_SHA" ]]; then
  echo 'FAIL: this test-only revision does not descend from the inspected PR #89 source.' >&2
  exit 1
fi

printf '%s\n' "$HEAD_SHA" > "$RUN_DIR/inspected-source-head.txt"
printf '%s\n' "$BASE_SHA" > "$RUN_DIR/pr89-initial-parent.txt"
./script/test_macos.sh --text-field --target-dir "$RUN_DIR/checks" 2>&1 | tee "$RUN_DIR/build-and-contracts.log"
APP="$RUN_DIR/checks/text-field/build/macos/GpuiTextField.app"
if [[ ! -x "$APP/Contents/MacOS/GpuiTextField" ]]; then
  echo 'FAIL: no fresh test-hook GpuiTextField.app was produced.' >&2
  exit 1
fi
export PYTHONDONTWRITEBYTECODE=1
export GPUI_FIELD_MACOS_IME_DISPATCH_TRACE=1
python3 infra/macos-ime-acceptance/ime-acceptance.py \
  --repo "$ROOT_DIR" \
  --profile "$RUN_DIR/profile" \
  --app "$APP" \
  --output "$RUN_DIR/acceptance" \
  --timeout 120 2>&1 | tee "$RUN_DIR/acceptance-driver.log"
