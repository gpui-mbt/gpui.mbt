#!/usr/bin/env bash
# Controlled protocol-mock harness. No source tree is patched; the wrapper is
# installed only in a temporary archive of the exact requested framework SHA.
set -euo pipefail
fixture_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(git -C "$fixture_dir" rev-parse --show-toplevel)
framework=${1:-aa629d20318f9792ff27f68f38ede136427de2c3}
actual=$(git -C "$repo_dir" rev-parse "${framework}^{commit}")
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/gpui-geometry-public.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
printf 'FRAMEWORK_SHA=%s\n' "$actual"
printf 'HARNESS_SHA=%s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
git -C "$repo_dir" archive "$actual" | tar -x -C "$work_dir"
cp "$work_dir/ubuntu/backend.c" "$work_dir/ubuntu/review207_backend_original.inc.c"
cp "$fixture_dir/backend_wrapper.c" "$work_dir/ubuntu/backend.c"
cp "$fixture_dir/fixture.c" "$work_dir/ubuntu/review207_fixture.inc.c"
cp "$fixture_dir/route_test.mbt" "$work_dir/ubuntu/review207_public_wbtest.mbt"
cd "$work_dir"
sh scripts/prepare_ubuntu.sh
moon test ubuntu --target native --deny-warn --no-parallelize --target-dir "$work_dir/build"
