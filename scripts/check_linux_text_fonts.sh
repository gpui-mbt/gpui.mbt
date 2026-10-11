#!/bin/sh
# Verify the historical geometry fixture before running font-dependent tests.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export FONTCONFIG_FILE=${FONTCONFIG_FILE:-"$root/tests/linux_text/fonts.conf"}
export FONTCONFIG_PATH=${FONTCONFIG_PATH:-"$(dirname "$FONTCONFIG_FILE")"}
if ! command -v fc-match >/dev/null 2>&1; then
  echo "fontconfig's fc-match utility is required to verify test fixtures" >&2
  exit 1
fi
if [ ! -r "$FONTCONFIG_FILE" ]; then
  echo "Fontconfig fixture configuration is not readable: $FONTCONFIG_FILE" >&2
  exit 1
fi

check_font() {
  requested=$1
  expected_family=$2
  actual=$(fc-match -f '%{family}|%{file}\n' "$requested")
  actual_family=${actual%%|*}
  actual_file=${actual#*|}
  case "$actual_family" in
    "$expected_family"|"$expected_family,"*) ;;
    *)
      echo "Font fixture mismatch for '$requested': expected family '$expected_family', got '$actual_family' ($actual_file)" >&2
      echo "Install fonts-dejavu-core, fonts-dejavu-extra, fonts-noto-cjk and fonts-noto-color-emoji; use the fixture Fontconfig configuration." >&2
      exit 1
      ;;
  esac
  if [ ! -r "$actual_file" ]; then
    echo "Font fixture file is not readable for '$requested': $actual_file" >&2
    exit 1
  fi
  printf 'font fixture: %s -> %s [%s]\n' "$requested" "$actual_family" "$actual_file"
  sha256sum "$actual_file"
}

check_font sans 'DejaVu Math TeX Gyre'
check_font 'sans:charset=65e5' 'Noto Sans CJK JP'
check_font 'DejaVu Sans' 'DejaVu Sans'
check_font 'Noto Sans CJK JP' 'Noto Sans CJK JP'
check_font 'Noto Color Emoji' 'Noto Color Emoji'
