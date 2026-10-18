#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$#" -ne 0 && "$#" -ne 2 ]]; then
    printf 'Usage: %s [RELEASE_DIRECTORY TAG]\n' "$0" >&2
    exit 1
fi
# Do not leave Python bytecode beside sources (release packaging requires a clean tree).
export PYTHONDONTWRITEBYTECODE=1
python3 "$project_dir/DeepWorkTests/Release/test_release_tools.py"
if [[ "$#" -eq 2 ]]; then
    python3 "$project_dir/DeepWorkTests/Release/test_release_artifact.py" "$1" "$2"
fi
