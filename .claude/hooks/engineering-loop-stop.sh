#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

baseline_file=".claude/engineering-loop-baseline.sha"
state_file=".claude/engineering-loop-state.json"
config_file=".claude/engineering-loop-config.json"
subagent_log=".claude/engineering-loop-events.jsonl"
command_log=".claude/engineering-loop-commands.jsonl"
edit_log=".claude/engineering-loop-edits.jsonl"
run_id_file=".claude/engineering-loop-run-id"
review_disposition_file=".claude/engineering-loop-review-disposition.json"

fingerprint() {
  {
    git status --short -- . \
      ':(exclude).claude/engineering-loop-baseline.sha' \
      ':(exclude).claude/engineering-loop-state.json' \
      ':(exclude).claude/engineering-loop-events.jsonl' \
      ':(exclude).claude/engineering-loop-commands.jsonl' \
      ':(exclude).claude/engineering-loop-edits.jsonl' \
      ':(exclude).claude/engineering-loop-run-id' \
      ':(exclude).claude/engineering-loop-mode' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git diff --binary -- . \
      ':(exclude).claude/engineering-loop-baseline.sha' \
      ':(exclude).claude/engineering-loop-state.json' \
      ':(exclude).claude/engineering-loop-events.jsonl' \
      ':(exclude).claude/engineering-loop-commands.jsonl' \
      ':(exclude).claude/engineering-loop-edits.jsonl' \
      ':(exclude).claude/engineering-loop-run-id' \
      ':(exclude).claude/engineering-loop-mode' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git ls-files --others --exclude-standard -- . 2>/dev/null | while IFS= read -r path; do
      case "$path" in
        .claude/engineering-loop-baseline.sha|.claude/engineering-loop-state.json|.claude/engineering-loop-events.jsonl|.claude/engineering-loop-commands.jsonl|.claude/engineering-loop-edits.jsonl|.claude/engineering-loop-run-id|.claude/engineering-loop-mode|.claude/engineering-loop-review-disposition.json|awesome-claude-code-subagents/*)
          continue
          ;;
      esac
      if [[ -f "$path" ]]; then
        printf 'UNTRACKED %s\n' "$path"
        shasum -a 256 "$path"
      fi
    done
  } | shasum -a 256 | awk '{print $1}'
}

if [[ ! -f "$baseline_file" ]]; then
  exit 0
fi

baseline="$(cat "$baseline_file")"
current="$(fingerprint)"

if [[ "${1:-}" == "--fingerprint" ]]; then
  echo "$current"
  exit 0
fi

if [[ "$current" == "$baseline" ]]; then
  exit 0
fi

exec .claude/skills/engineering-loop/scripts/loop-status.sh
