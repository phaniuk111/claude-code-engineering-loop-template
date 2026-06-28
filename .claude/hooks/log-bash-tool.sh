#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

input="$(cat)"
log_file=".claude/engineering-loop-commands.jsonl"
config_file=".claude/engineering-loop-config.json"
fingerprint="$(".claude/hooks/engineering-loop-stop.sh" --fingerprint 2>/dev/null || true)"
run_id_file=".claude/engineering-loop-run-id"
loop_run_id=""
test_patterns_json="[]"

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

if [[ -f "$config_file" ]]; then
  test_patterns_json="$(jq -c '.test_command_patterns // []' "$config_file" 2>/dev/null || echo '[]')"
fi

mkdir -p "$(dirname "$log_file")"

jq -c --arg fingerprint "$fingerprint" --arg loop_run_id "$loop_run_id" --argjson test_patterns "$test_patterns_json" '
  def command_text:
    .tool_input.command
    // .toolInput.command
    // .input.command
    // .command
    // "";

  def exit_code:
    .tool_response.exit_code
    // .toolResponse.exit_code
    // .response.exit_code
    // .exit_code
    // null;

  def is_test_command($patterns):
    (command_text | ascii_downcase) as $cmd
    | (
        ($cmd | test("(^|[;&|[:space:]])((python3?|uv run|poetry run)[[:space:]]+(-m[[:space:]]+)?pytest|pytest|tox|nox|make[[:space:]]+test|python3?[[:space:]]+-m[[:space:]]+unittest)([[:space:]]|$)"))
        and ($cmd | test("\\b(find|grep|rg|cat|sed|awk|ls|head|tail|less|more)\\b.*\\b(pytest\\.(ini|toml|cfg|yaml|yml)|conftest\\.py)\\b") | not)
      );

  {
    event: (.hook_event_name // .hookEventName // "PostToolUse"),
    timestamp: (now | todateiso8601),
    timestamp_epoch: now,
    loop_run_id: ($loop_run_id | select(length > 0) // null),
    session_id: (.session_id // .sessionId // null),
    transcript_path: (.transcript_path // .transcriptPath // null),
    tool_name: (.tool_name // .toolName // "Bash"),
    command: command_text,
    exit_code: exit_code,
    is_test_command: is_test_command($test_patterns),
    change_fingerprint: $fingerprint
  }
' <<<"$input" >> "$log_file"
