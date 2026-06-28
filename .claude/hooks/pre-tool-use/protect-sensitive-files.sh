#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: Protect sensitive files from being read or modified by the agent
# Targets: .env*, secrets, SSH keys, engineering loop state, etc.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"

tool_name=$(echo "$input" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || echo "")
file_path=$(echo "$input" | jq -r '
  .tool_input.file_path //
  .toolInput.file_path //
  .input.file_path //
  .file_path //
  .path //
  ""
' 2>/dev/null || echo "")

if [[ -z "$file_path" ]]; then
  echo '{}'
  exit 0
fi

# Normalize path
abs_path=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")

# Claude must be able to disposition reviewer findings as part of the loop.
# The Stop hook validates this file, so allowing edits here does not bypass the gate.
case "$abs_path" in
  "$repo_root/.claude/engineering-loop-review-disposition.json")
    echo '{}'
    exit 0
    ;;
esac

# Sensitive patterns (relative or absolute)
SENSITIVE_PATTERNS=(
  '\.env'
  '\.env\.'
  'secrets'
  '\.pem$'
  '\.key$'
  'id_rsa'
  'id_ed25519'
  'authorized_keys'
  '\.claude/engineering-loop-.*\.(json|jsonl|sha)'
  '\.claude/settings.*\.json'
  'credentials'
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  if echo "$abs_path" | grep -qiE "$pattern"; then
    # Allow read of some in specific contexts? For now, strong protection on write/edit.
    # For Read we are stricter on secrets.
    if [[ "$tool_name" == "Read" ]]; then
      if echo "$abs_path" | grep -qiE '(\.env|secrets|\.pem|\.key|id_rsa|id_ed25519|credentials)'; then
        reason="Reading sensitive file blocked: $abs_path"
        echo "BLOCKED: $reason" >&2
        cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED $reason\nAccess to secret material is not allowed."
  }
}
EOF
        exit 0
      fi
    else
      # Edit/Write/MultiEdit always blocked for these
      reason="Modification of sensitive/protected file blocked: $abs_path"
      echo "BLOCKED: $reason" >&2
      cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED $reason\nModifying engineering state or secret files is prohibited."
  }
}
EOF
      exit 0
    fi
  fi
done

# Default allow
echo '{}'
exit 0
