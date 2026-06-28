#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: Block dangerous shell commands
# Reads JSON from stdin (Claude Code hook format)
# Outputs permissionDecision deny on match (exit 2 semantics via the JSON response)

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"

# Extract command (handle different payload shapes)
cmd=$(echo "$input" | jq -r '
  .tool_input.command //
  .toolInput.command //
  .input.command //
  .command //
  ""
' 2>/dev/null || echo "")

tool_name=$(echo "$input" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || echo "")

if [[ "$tool_name" != "Bash" || -z "$cmd" ]]; then
  echo '{}'
  exit 0
fi

# Safety level: critical | high | strict (default high)
SAFETY_LEVEL="${CLAUDE_SAFETY_LEVEL:-high}"

declare -a BLOCKED=()

check_pattern() {
  local level="$1" pattern="$2" reason="$3"
  if echo "$cmd" | grep -qiE "$pattern"; then
    BLOCKED+=("$level|$reason")
  fi
}

# CRITICAL patterns
if [[ "$SAFETY_LEVEL" == "critical" || "$SAFETY_LEVEL" == "high" || "$SAFETY_LEVEL" == "strict" ]]; then
  check_pattern "CRITICAL" 'rm\s+.*(~|/\$HOME|\$HOME|/[^ ]*[^/ ]/[* ]|\*.*\s*$|/etc|/usr|/var|/bin|/sbin)' "Destructive rm targeting home, root, or system paths"
  check_pattern "CRITICAL" 'rm\s+-.*[rf].*\s+/\s*$' "rm -rf / or similar root deletion"
  check_pattern "CRITICAL" 'dd\b.*of=/dev/(sd|nvme|hd|vd|xvd)' "dd writing directly to disk device"
  check_pattern "CRITICAL" 'mkfs.*\s+/dev/' "Formatting disk with mkfs"
  check_pattern "CRITICAL" ':\(\)\s*\{.*:\s*\|\s*:.*&' "Fork bomb pattern"
fi

# HIGH risk patterns
if [[ "$SAFETY_LEVEL" == "high" || "$SAFETY_LEVEL" == "strict" ]]; then
  check_pattern "HIGH" '(curl|wget)\s+.*\|\s*(ba)?sh' "Piping downloaded content to shell (RCE risk)"
  if echo "$cmd" | grep -qiE 'git\s+push.*--force.*\b(main|master)\b' \
    && ! echo "$cmd" | grep -qi -- '--force-with-lease'; then
    BLOCKED+=("HIGH|Force push to main/master without --force-with-lease")
  fi
  check_pattern "HIGH" 'git\s+reset\s+--hard' "git reset --hard (destructive)"
  check_pattern "HIGH" 'git\s+clean\s+-.*f' "git clean -f (deletes untracked files)"
  check_pattern "HIGH" 'chmod\s+.*777' "chmod 777 (overly permissive)"
  check_pattern "HIGH" '(cat|less|head|tail|more)\s+.*\.env' "Reading .env file (secrets exposure)"
  check_pattern "HIGH" '(cat|less|head|tail|more)\s+.*(id_rsa|id_ed25519|\.pem|credentials|secrets)' "Reading private key or secrets file"
  check_pattern "HIGH" '(printenv|env)\s*$' "Dumping environment (may leak secrets)"
  check_pattern "HIGH" 'echo\s+.*\$(SECRET|KEY|TOKEN|PASSWORD|API_|PRIVATE)' "Echoing secret variable"
  check_pattern "HIGH" 'docker\s+volume\s+(rm|prune)' "Deleting Docker volumes"
  check_pattern "HIGH" 'rm\s+.*\.ssh/' "Removing SSH keys or authorized_keys"
fi

# STRICT (cautionary)
if [[ "$SAFETY_LEVEL" == "strict" ]]; then
  check_pattern "STRICT" 'git\s+push.*--force' "Any force push (prefer --force-with-lease)"
  check_pattern "STRICT" 'git\s+checkout\s+\.' "git checkout . discards changes"
  check_pattern "STRICT" 'sudo\s+rm\b' "sudo rm (elevated destructive command)"
  check_pattern "STRICT" 'docker\s+(system|image)\s+prune' "Docker prune (removes images/containers)"
  check_pattern "STRICT" 'crontab\s+-r' "crontab -r removes all jobs"
fi

if [[ ${#BLOCKED[@]} -gt 0 ]]; then
  # Take the first (most severe) block
  IFS='|' read -r sev reason <<< "${BLOCKED[0]}"
  echo "Blocked dangerous command: [$sev] $reason" >&2

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED [$sev] $reason\nCommand: $cmd"
  }
}
EOF
  exit 0
fi

# Allow
echo '{}'
exit 0
