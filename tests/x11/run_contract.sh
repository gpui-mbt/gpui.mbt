#!/bin/sh
# Headless contract checks. Never create an X server or connect to a display.
set -eu
cd "$(dirname "$0")/../.."
build_dir=${GPUI_X11_CONTRACT_BUILD_DIR:-_build/x11-contract}
mkdir -p "$build_dir"
script/linux_text_cc.sh -std=c11 -Wall -Wextra -Werror ${GPUI_TEST_CFLAGS:-} \
  tests/x11/contract_test.c platform/linux_text/linux_text.c \
  -o "$build_dir/contract-test" \
  $(pkg-config --cflags --libs x11 egl glesv2 xkbcommon) \
  -lpthread -lm
env -u DISPLAY -u WAYLAND_DISPLAY "$build_dir/contract-test"
