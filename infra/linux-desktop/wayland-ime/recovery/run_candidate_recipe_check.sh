#!/usr/bin/env bash
# Run the prepare-only checker and preserve its result without hiding failures.
set -euo pipefail
python3 infra/linux-desktop/wayland-ime/recovery/check_candidate_recipe.py | tee candidate-recipe-result.json
