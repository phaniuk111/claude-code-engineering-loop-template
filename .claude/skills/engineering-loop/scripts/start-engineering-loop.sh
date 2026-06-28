#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

run_id_file=".claude/engineering-loop-run-id"
mode_file=".claude/engineering-loop-mode"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
mode="code"

case "${1:-}" in
  --mode)
    mode="${2:-code}"
    ;;
  --mode=*)
    mode="${1#--mode=}"
    ;;
  analysis|validation|plan|planning)
    mode="analysis"
    ;;
  code|implementation|"")
    mode="code"
    ;;
  *)
    echo "Unknown engineering loop mode: $1" >&2
    echo "Use code or analysis." >&2
    exit 2
    ;;
esac

case "$mode" in
  code|analysis) ;;
  validation|plan|planning) mode="analysis" ;;
  *)
    echo "Unknown engineering loop mode: $mode" >&2
    echo "Use code or analysis." >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$run_id_file")"
printf '%s\n' "$run_id" > "$run_id_file"
printf '%s\n' "$mode" > "$mode_file"

echo "Started engineering loop run $run_id ($mode mode)"
