#!/bin/sh
# Headless kiosk-shell retains a freed active surface tree when there is no seat.
# See docs/ubuntu.md; keep ordinary E2E and failure diagnostics on one profile.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec weston --backend=headless-backend.so --use-gl --shell=desktop-shell.so \
  --config="$root/tests/ubuntu/weston.ini" --idle-time=0 "$@"
