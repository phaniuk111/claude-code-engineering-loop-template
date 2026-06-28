#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

run_id_file=".claude/engineering-loop-run-id"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"

mkdir -p "$(dirname "$run_id_file")"
printf '%s\n' "$run_id" > "$run_id_file"

echo "Started engineering loop run $run_id"
