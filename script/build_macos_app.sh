#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPUI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: build_macos_app.sh --root DIR --name APP --bundle-id ID --package PKG
                          [--target-dir DIR] [--build|--run|--verify|--smoke]
                          [--test-hooks] [--native-source FILE]... [--framework NAME]...
                          [-- APP_ARGS...]

Builds a MoonBit package from a local gpui.mbt workspace member and packages it
as a macOS .app bundle. The app root must contain a moon.work that includes the
gpui.mbt checkout (normally "../gpui.mbt").
USAGE
  exit 2
}

ROOT=""
NAME=""
BUNDLE_ID=""
PACKAGE=""
TARGET_DIR=""
MODE="run"
TEST_HOOKS=0
EXTRA_SOURCES=()
EXTRA_FRAMEWORKS=()
APP_ARGS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --root)
      [[ "$#" -ge 2 ]] || usage
      ROOT="$2"
      shift 2
      ;;
    --name)
      [[ "$#" -ge 2 ]] || usage
      NAME="$2"
      shift 2
      ;;
    --bundle-id)
      [[ "$#" -ge 2 ]] || usage
      BUNDLE_ID="$2"
      shift 2
      ;;
    --package)
      [[ "$#" -ge 2 ]] || usage
      PACKAGE="$2"
      shift 2
      ;;
    --target-dir)
      [[ "$#" -ge 2 ]] || usage
      TARGET_DIR="$2"
      shift 2
      ;;
    --build|--run|--verify|--smoke)
      MODE="${1#--}"
      shift
      ;;
    --test-hooks)
      TEST_HOOKS=1
      shift
      ;;
    --native-source)
      [[ "$#" -ge 2 ]] || usage
      EXTRA_SOURCES+=("$2")
      shift 2
      ;;
    --framework)
      [[ "$#" -ge 2 ]] || usage
      EXTRA_FRAMEWORKS+=("$2")
      shift 2
      ;;
    --)
      shift
      APP_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$ROOT" && -n "$NAME" && -n "$BUNDLE_ID" && -n "$PACKAGE" ]] || usage
[[ "$(uname -s)" == Darwin ]] || {
  echo 'The macOS application builder requires macOS and Xcode command-line tools.' >&2
  exit 2
}
ROOT="$(cd "$ROOT" && pwd)"
case "$NAME" in
  */*|.|..) echo 'The app name must be a single filename.' >&2; exit 2 ;;
esac
case "$PACKAGE" in
  /*) PACKAGE_ROOT="$(cd "$PACKAGE" && pwd)" ;;
  *) PACKAGE_ROOT="$(cd "$ROOT/$PACKAGE" && pwd)" ;;
esac
PACKAGE_KEY="$(python3 -c 'import hashlib, os, sys; print(hashlib.sha256(os.fsencode(sys.argv[1])).hexdigest())' "$PACKAGE_ROOT")"
[[ -f "$ROOT/moon.work" ]] || {
  echo "missing $ROOT/moon.work; the app must include the gpui.mbt checkout as a workspace member" >&2
  exit 2
}
[[ -d "$GPUI_ROOT/platform/macos" ]] || {
  echo "cannot find the gpui.mbt platform/macos sources at $GPUI_ROOT" >&2
  exit 2
}

if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$ROOT/build"
fi
case "$TARGET_DIR" in
  /*) ;;
  *) TARGET_DIR="$ROOT/$TARGET_DIR" ;;
esac
APP_BUNDLE="$TARGET_DIR/$NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$NAME"
APP_LIBRARY="$APP_BUNDLE/Contents/Frameworks/libgpui_macos.dylib"
PID_FILE="$TARGET_DIR/$NAME.pid"
LOG_FILE="$TARGET_DIR/$NAME.log"
MOON_TARGET_DIR="$TARGET_DIR/moon/$PACKAGE_KEY"
SMOKE_DIR="$TARGET_DIR/smoke"

mkdir -p "$TARGET_DIR"
if [[ -f "$PID_FILE" ]]; then
  PREVIOUS_PID="$(cat "$PID_FILE" || true)"
  if [[ "${PREVIOUS_PID:-}" =~ ^[0-9]+$ ]] &&
    ps -p "$PREVIOUS_PID" -o command= 2>/dev/null | grep -F "$APP_BINARY" >/dev/null; then
    kill "$PREVIOUS_PID" || true
  fi
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Frameworks"

CLANG_ARGS=(
  -dynamiclib
  -fobjc-arc
  -Wall -Wextra -Werror
)
if [[ "$MODE" == smoke || "$TEST_HOOKS" == 1 ]]; then
  CLANG_ARGS+=(-DGPUI_TESTING)
fi

SOURCES=(
  "$GPUI_ROOT/platform/macos/native.m"
  "$GPUI_ROOT/platform/macos/accessibility.m"
  "$GPUI_ROOT/platform/macos_text/core_text.c"
)
# Bash 3.2 treats an empty array as unset under nounset. The guarded expansion
# keeps zero arguments empty and preserves every argument when the array is set.
for source in ${EXTRA_SOURCES[@]+"${EXTRA_SOURCES[@]}"}; do
  SOURCES+=("$source")
done

FRAMEWORKS=(
  AppKit QuartzCore Metal CoreText CoreGraphics CoreFoundation
)
for framework in ${EXTRA_FRAMEWORKS[@]+"${EXTRA_FRAMEWORKS[@]}"}; do
  FRAMEWORKS+=("$framework")
done

FRAMEWORK_ARGS=()
for framework in "${FRAMEWORKS[@]}"; do
  FRAMEWORK_ARGS+=(-framework "$framework")
done

xcrun clang "${CLANG_ARGS[@]}" "${SOURCES[@]}" "${FRAMEWORK_ARGS[@]}" -o "$APP_LIBRARY"

cd "$ROOT"
# A package can stop being executable while Moon leaves its previous binary
# in the cache. Require this build to produce the executable being packaged.
if [[ -d "$MOON_TARGET_DIR/native/debug/build" ]]; then
  find "$MOON_TARGET_DIR/native/debug/build" -type f -name '*.exe' \
    -not -path '*.dSYM/*' -delete
fi
moon build --target native --deny-warn --target-dir "$MOON_TARGET_DIR" "$PACKAGE_ROOT"
EXECUTABLES=()
EXECUTABLE_COUNT=0
while IFS= read -r -d '' executable; do
  EXECUTABLES+=("$executable")
  EXECUTABLE_COUNT=$((EXECUTABLE_COUNT + 1))
done < <(find "$MOON_TARGET_DIR/native/debug/build" -type f -name '*.exe' -not -path '*.dSYM/*' -print0)
[[ "$EXECUTABLE_COUNT" == 1 ]] || {
  echo "expected exactly one built executable for package $PACKAGE under $MOON_TARGET_DIR" >&2
  exit 1
}
cp "${EXECUTABLES[0]}" "$APP_BINARY"

python3 - "$APP_BUNDLE/Contents/Info.plist" "$NAME" "$BUNDLE_ID" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as stream:
    plistlib.dump({
        "CFBundleExecutable": sys.argv[2],
        "CFBundleIdentifier": sys.argv[3],
        "CFBundleName": sys.argv[2],
        "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "13.0",
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
    }, stream)
PY

case "$MODE" in
  build)
    echo "$APP_BUNDLE"
    ;;
  run)
    GPUI_MACOS_LIBRARY="$APP_LIBRARY" "$APP_BINARY" ${APP_ARGS[@]+"${APP_ARGS[@]}"} >"$LOG_FILE" 2>&1 &
    APP_PID="$!"
    echo "$APP_PID" > "$PID_FILE"
    echo "Launched $APP_BUNDLE (pid $APP_PID); log: $LOG_FILE"
    ;;
  verify)
    GPUI_MACOS_LIBRARY="$APP_LIBRARY" "$APP_BINARY" ${APP_ARGS[@]+"${APP_ARGS[@]}"} >"$LOG_FILE" 2>&1 &
    APP_PID="$!"
    echo "$APP_PID" > "$PID_FILE"
    sleep 1
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill "$APP_PID" 2>/dev/null || true
      sleep 0.2
      echo "Verified $APP_BUNDLE launches and stays alive"
    else
      echo "App exited during verify; log: $LOG_FILE" >&2
      cat "$LOG_FILE" >&2 || true
      exit 1
    fi
    ;;
  smoke)
    rm -rf "$SMOKE_DIR"
    mkdir -p "$SMOKE_DIR"
    set +e
    GPUI_SMOKE_DIR="$SMOKE_DIR/" GPUI_NATIVE_E2E=1 GPUI_MACOS_LIBRARY="$APP_LIBRARY" \
      "$APP_BINARY" --smoke ${APP_ARGS[@]+"${APP_ARGS[@]}"} >"$LOG_FILE" 2>&1
    status=$?
    set -e
    for ppm in "$SMOKE_DIR"/*.ppm; do
      [[ -e "$ppm" ]] || continue
      if command -v sips >/dev/null 2>&1; then
        sips -s format png "$ppm" --out "${ppm%.ppm}.png" >/dev/null 2>&1 || true
      fi
    done
    if [[ $status -ne 0 ]]; then
      echo "Smoke flow failed (exit $status); log: $LOG_FILE" >&2
      cat "$LOG_FILE" >&2 || true
      exit "$status"
    fi
    echo "Smoke artifacts: $SMOKE_DIR"
    ;;
esac
