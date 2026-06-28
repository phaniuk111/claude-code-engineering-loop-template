#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"
log_file=".claude/engineering-loop-events.jsonl"
fingerprint="$(".claude/hooks/engineering-loop-stop.sh" --fingerprint 2>/dev/null || true)"
run_id_file=".claude/engineering-loop-run-id"
loop_run_id=""

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

mkdir -p "$(dirname "$log_file")"

jq -c --arg fingerprint "$fingerprint" --arg loop_run_id "$loop_run_id" '
  {
    event: "SubagentStart",
    timestamp: (now | todateiso8601),
    loop_run_id: ($loop_run_id | select(length > 0) // null),
    session_id: (.session_id // .sessionId // null),
    transcript_path: (.transcript_path // .transcriptPath // null),
    agent_id: (.agent_id // .agentId // null),
    agent_type: (.agent_type // .agentType // null),
    agent_name: (.agent_name // .agentName // null),
    description: (.description // null),
    prompt: (.prompt // .task // .message // null),
    change_fingerprint: $fingerprint
  }
' <<<"$input" >> "$log_file"
