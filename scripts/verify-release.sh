#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    printf 'Usage: %s RELEASE_DIRECTORY TAG [EXPECTED_COMMIT]\n' "$0" >&2
    exit 1
fi
exec python3 "$project_dir/scripts/release-tools.py" verify "$@"
