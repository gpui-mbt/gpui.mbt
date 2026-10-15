#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$repo/_build/background-policy"
mkdir -p "$out"
xcrun clang -fobjc-arc -Wall -Wextra -Werror \
  "$repo/tests/macos_background_policy_test.m" \
  "$repo/platform/macos/accessibility.m" \
  "$repo/platform/macos_text/core_text.c" \
  -framework AppKit -framework QuartzCore -framework Metal -framework CoreText \
  -framework CoreGraphics -framework CoreFoundation -o "$out/policy-test"
"$out/policy-test"
