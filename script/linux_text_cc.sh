#!/bin/sh
# Compile Linux text FFI files with distro pkg-config discovery.
#
# Compiler: GPUI_LINUX_TEXT_CC, then CC, then cc. A value that names an
# existing file is one word, so paths with spaces keep working; any other value
# is split on whitespace, which keeps the conventional `ccache cc` form.
# Discovery: PKG_CONFIG, then pkg-config. Same word rules.
set -u
set -f

compiler=${GPUI_LINUX_TEXT_CC-${CC-cc}}
discovery=${PKG_CONFIG-pkg-config}

if [ -z "$compiler" ]; then
  printf '%s\n' "GPUI_LINUX_TEXT_CC must name a compiler" >&2
  exit 2
fi

discovery_missing() {
  printf '%s\n' "Linux text measurement requires pkg-config metadata for pangoft2 and fontconfig. Install the development packages first." >&2
  exit 2
}

if [ -z "$discovery" ]; then
  discovery_missing
fi

command_exists() {
  if [ -f "$1" ]; then
    return 0
  fi
  command -v "${1%% *}" >/dev/null 2>&1
}

run_discovery() {
  if [ -f "$discovery" ]; then
    "$discovery" "$@"
  else
    $discovery "$@"
  fi
}

command_exists "$discovery" || discovery_missing

version_stderr=$(run_discovery --atleast-version=1.50 pangoft2 2>&1 >/dev/null)
version_status=$?
if [ "$version_status" -ne 0 ]; then
  printf '%s\n' "Linux grayscale text requires PangoFT2 1.50 or newer (for shaped glyph color metadata)." >&2
  if [ -n "$version_stderr" ]; then
    printf '%s\n' "$version_stderr" >&2
  fi
  exit 2
fi

cflags=$(run_discovery --cflags pangoft2 fontconfig)
cflags_status=$?
if [ "$cflags_status" -ne 0 ]; then
  printf '%s\n' "Linux text measurement requires pkg-config metadata for pangoft2 and fontconfig. Install the development packages first." >&2
  run_discovery --cflags pangoft2 fontconfig >/dev/null
  exit 2
fi
libs=$(run_discovery --libs pangoft2 fontconfig)

# Keep the argument order the previous wrapper used: discovered cflags, the
# caller's flags, then the project's CFLAGS/LDFLAGS and the discovered libs.
main() {
  set -- $cflags ${CPPFLAGS:-} "$@" ${CFLAGS:-} ${LDFLAGS:-} $libs
  if [ -f "$compiler" ]; then
    exec "$compiler" "$@"
  else
    exec $compiler "$@"
  fi
}

main "$@"
