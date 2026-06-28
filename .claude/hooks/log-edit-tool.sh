#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"
log_file=".claude/engineering-loop-edits.jsonl"
fingerprint="$(".claude/hooks/engineering-loop-stop.sh" --fingerprint 2>/dev/null || true)"
run_id_file=".claude/engineering-loop-run-id"
loop_run_id=""

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

mkdir -p "$(dirname "$log_file")"

jq -c --arg fingerprint "$fingerprint" --arg loop_run_id "$loop_run_id" '
  def tool_input:
    .tool_input
    // .toolInput
    // .input
    // {};

  def file_path:
    tool_input.file_path
    // tool_input.filePath
    // tool_input.path
    // null;

  {
    event: (.hook_event_name // .hookEventName // "PostToolUse"),
    timestamp: (now | todateiso8601),
    timestamp_epoch: now,
    loop_run_id: ($loop_run_id | select(length > 0) // null),
    session_id: (.session_id // .sessionId // null),
    transcript_path: (.transcript_path // .transcriptPath // null),
    tool_name: (.tool_name // .toolName // "Edit"),
    file_path: file_path,
    change_fingerprint: $fingerprint
  }
' <<<"$input" >> "$log_file"
