#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_tools="$project_root/builds/asset-tools"
mkdir -p "$project_root/builds"
touch "$project_root/builds/.gdignore"
python3 -m venv "$asset_tools"
"$asset_tools/bin/pip" install -r "$project_root/tools/asset-requirements.txt"
