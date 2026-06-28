#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: Automatically run ruff check --fix and ruff format on Python files after edits.
# This provides deterministic Python quality instead of relying solely on agent instructions.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"

# Only act on edit/write tools
tool_name=$(echo "$input" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || echo "")
if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" && "$tool_name" != "MultiEdit" ]]; then
  echo '{}'
  exit 0
fi

# Extract file path(s)
file_paths=$(echo "$input" | jq -r '
  [.tool_input.file_path, .toolInput.file_path, .input.file_path, .file_path] | map(select(. != null)) | .[]
' 2>/dev/null || echo "")

if [[ -z "$file_paths" ]]; then
  echo '{}'
  exit 0
fi

changed_py_files=()
while IFS= read -r fp; do
  if [[ -n "$fp" && "$fp" == *.py ]]; then
    if [[ -f "$fp" ]]; then
      changed_py_files+=("$fp")
    fi
  fi
done <<< "$file_paths"

if [[ ${#changed_py_files[@]} -eq 0 ]]; then
  echo '{}'
  exit 0
fi

# Run ruff if available
if command -v ruff >/dev/null 2>&1 || command -v uv >/dev/null 2>&1; then
  for f in "${changed_py_files[@]}"; do
    echo "Running ruff on $f" >&2
    if command -v uv >/dev/null 2>&1; then
      uv --quiet run ruff check --fix "$f" || true
      uv --quiet run ruff format "$f" || true
    else
      ruff check --fix "$f" || true
      ruff format "$f" || true
    fi
  done
else
  echo "ruff not found in PATH — skipping auto-format (install ruff or use uv)" >&2
fi

echo '{}'
exit 0
