#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

state_file=".claude/engineering-loop-state.json"
subagent_log=".claude/engineering-loop-events.jsonl"
command_log=".claude/engineering-loop-commands.jsonl"
stop_hook=".claude/hooks/engineering-loop-stop.sh"
run_id_file=".claude/engineering-loop-run-id"
review_disposition_file=".claude/engineering-loop-review-disposition.json"

current="$("$stop_hook" --fingerprint)"
loop_run_id=""
iteration="${ENGINEERING_LOOP_ITERATION:-1}"
note="${ENGINEERING_LOOP_NOTE:-State generated from current hook evidence. Pending means the required runtime evidence is not present yet.}"

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

has_subagent_for_current() {
  local agent_type="$1"
  [[ -f "$subagent_log" ]] && jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" --arg agent_type "$agent_type" '
    select(
      .change_fingerprint == $current
      and .event == "SubagentStop"
      and .agent_type == $agent_type
      and (if ($loop_run_id | length) > 0 then .loop_run_id == $loop_run_id else true end)
    )
  ' "$subagent_log" >/dev/null
}

has_subagent_for_run() {
  local agent_type="$1"
  if [[ -n "$loop_run_id" ]]; then
    [[ -f "$subagent_log" ]] && jq -e --arg loop_run_id "$loop_run_id" --arg agent_type "$agent_type" '
      select(.loop_run_id == $loop_run_id and .event == "SubagentStop" and .agent_type == $agent_type)
    ' "$subagent_log" >/dev/null
    return
  fi

  has_subagent_for_current "$agent_type"
}

has_any_subagent_for_current() {
  local jq_expr='select(.change_fingerprint == $current and .event == "SubagentStop" and ('
  local sep=""
  local agent_type

  [[ -f "$subagent_log" ]] || return 1

  for agent_type in "$@"; do
    jq_expr="${jq_expr}${sep}.agent_type == \"${agent_type}\""
    sep=" or "
  done
  jq_expr="${jq_expr}) and (if (\$loop_run_id | length) > 0 then .loop_run_id == \$loop_run_id else true end))"

  jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" "$jq_expr" "$subagent_log" >/dev/null
}

requires_security_review() {
  local raw path
  while IFS= read -r raw; do
    path="${raw#?? }"
    case "$path" in
      .claude/engineering-loop-baseline.sha|.claude/engineering-loop-state.json|.claude/engineering-loop-events.jsonl|.claude/engineering-loop-commands.jsonl|.claude/engineering-loop-edits.jsonl|.claude/engineering-loop-run-id|.claude/engineering-loop-review-disposition.json)
        continue
        ;;
    esac
    case "$path" in
      .claude/*|.github/workflows/*|*.sh|*.py|Dockerfile|*/Dockerfile|docker-compose.yml|*/docker-compose.yml|docker-compose.yaml|*/docker-compose.yaml|requirements*.txt|*/requirements*.txt|pyproject.toml|*/pyproject.toml|poetry.lock|*/poetry.lock|uv.lock|*/uv.lock|setup.py|*/setup.py|setup.cfg|*/setup.cfg)
        return 0
        ;;
    esac
  done < <(
    git status --short -- . \
      ':(exclude).claude/engineering-loop-baseline.sha' \
      ':(exclude).claude/engineering-loop-state.json' \
      ':(exclude).claude/engineering-loop-events.jsonl' \
      ':(exclude).claude/engineering-loop-commands.jsonl' \
      ':(exclude).claude/engineering-loop-edits.jsonl' \
      ':(exclude).claude/engineering-loop-run-id' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git diff --name-only -- . \
      ':(exclude).claude/engineering-loop-baseline.sha' \
      ':(exclude).claude/engineering-loop-state.json' \
      ':(exclude).claude/engineering-loop-events.jsonl' \
      ':(exclude).claude/engineering-loop-commands.jsonl' \
      ':(exclude).claude/engineering-loop-edits.jsonl' \
      ':(exclude).claude/engineering-loop-run-id' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git ls-files --others --exclude-standard -- . 2>/dev/null || true
  )
  return 1
}

has_passing_test_command() {
  [[ -f "$command_log" ]] && jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" '
    select(
      .change_fingerprint == $current
      and .event == "PostToolUse"
      and .tool_name == "Bash"
      and (.is_test_command == true)
      and (.exit_code == 0 or .exit_code == null)
      and (if ($loop_run_id | length) > 0 then .loop_run_id == $loop_run_id else true end)
    )
  ' "$command_log" >/dev/null
}

required_review_agents_json() {
  if requires_security_review; then
    printf '%s\n' '["code-reviewer","security-auditor","devops-engineer"]'
  else
    printf '%s\n' '["code-reviewer","devops-engineer"]'
  fi
}

has_valid_review_disposition() {
  local required_agents
  required_agents="$(required_review_agents_json)"

  [[ -f "$review_disposition_file" ]] && jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" --argjson required_agents "$required_agents" '
    def allowed_disposition: . == "fixed" or . == "accepted_risk" or . == "not_applicable";
    def nonempty_string: type == "string" and (length > 0);

    . as $doc
    | (.loop_run_id == $loop_run_id and ($loop_run_id | length) > 0)
    and (.change_fingerprint == $current)
    and (.findings | type == "array")
    and (.findings | length >= ($required_agents | length))
    and (
      [
        .findings[]
        | select(
            (.agent | IN($required_agents[]))
            and (.severity | nonempty_string)
            and (.finding | nonempty_string)
            and (.disposition | allowed_disposition)
            and (.evidence | nonempty_string)
          )
      ]
      | length == ($doc.findings | length)
    )
    and (
      all($required_agents[]; . as $required_agent | any($doc.findings[]; .agent == $required_agent))
    )
  ' "$review_disposition_file" >/dev/null
}

step_status() {
  if "$@"; then
    echo "complete"
  else
    echo "pending"
  fi
}

explore_status="$(step_status has_subagent_for_run "Explore")"
architect_status="$(step_status has_subagent_for_run "architect-reviewer")"
implementation_status="$(step_status has_any_subagent_for_current "python-pro" "backend-developer" "frontend-developer" "fullstack-developer" "devops-engineer")"
tests_status="$(step_status has_subagent_for_current "test-automator")"
code_review_status="$(step_status has_subagent_for_current "code-reviewer")"
if requires_security_review; then
  security_review_status="$(step_status has_subagent_for_current "security-auditor")"
else
  security_review_status="not_applicable"
fi
devops_status="$(step_status has_subagent_for_current "devops-engineer")"
fixes_status="$(step_status has_valid_review_disposition)"

if has_passing_test_command; then
  test_result="passed"
else
  test_result="pending"
fi

mkdir -p "$(dirname "$state_file")"

jq -n \
  --arg fingerprint "$current" \
  --arg loop_run_id "$loop_run_id" \
  --argjson iteration "$iteration" \
  --arg explore "$explore_status" \
  --arg architect "$architect_status" \
  --arg implementation "$implementation_status" \
  --arg tests "$tests_status" \
  --arg code_review "$code_review_status" \
  --arg security_review "$security_review_status" \
  --arg devops "$devops_status" \
  --arg fixes "$fixes_status" \
  --arg test_result "$test_result" \
  --arg note "$note" \
  '{
    loop_run_id: $loop_run_id,
    change_fingerprint: $fingerprint,
    iteration: $iteration,
    steps: {
      explore: $explore,
      architect: $architect,
      implementation: $implementation,
      tests: $tests,
      code_review: $code_review,
      security_review: $security_review,
      devops: $devops,
      fixes: $fixes
    },
    tests: {
      status: $test_result,
      commands: []
    },
    notes: [$note]
  }' > "$state_file"

echo "Updated $state_file for fingerprint $current"
