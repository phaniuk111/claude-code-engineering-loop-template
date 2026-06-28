#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

state_file=".claude/engineering-loop-state.json"
subagent_log=".claude/engineering-loop-events.jsonl"
command_log=".claude/engineering-loop-commands.jsonl"
edit_log=".claude/engineering-loop-edits.jsonl"
stop_hook=".claude/hooks/engineering-loop-stop.sh"
run_id_file=".claude/engineering-loop-run-id"
mode_file=".claude/engineering-loop-mode"
review_disposition_file=".claude/engineering-loop-review-disposition.json"

current="$("$stop_hook" --fingerprint)"
loop_run_id=""
loop_mode="${ENGINEERING_LOOP_MODE:-}"
quiet=false

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

if [[ -z "$loop_run_id" && -f "$state_file" ]]; then
  loop_run_id="$(jq -r '.loop_run_id // empty' "$state_file" 2>/dev/null || true)"
fi

if [[ -z "$loop_mode" && -f "$mode_file" ]]; then
  loop_mode="$(cat "$mode_file")"
fi

if [[ -z "$loop_mode" && -f "$state_file" ]]; then
  loop_mode="$(jq -r '.mode // empty' "$state_file" 2>/dev/null || true)"
fi

case "$loop_mode" in
  analysis|validation|plan|planning) loop_mode="analysis" ;;
  code|implementation|"") loop_mode="code" ;;
  *) loop_mode="code" ;;
esac

if [[ "${1:-}" == "--quiet" ]]; then
  quiet=true
fi

missing=()
passed=()
next_actions=()

add_passed() {
  passed+=("$1")
}

add_missing() {
  missing+=("$1")
}

add_action() {
  next_actions+=("$1")
}

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

has_any_subagent_for_run() {
  local jq_expr='select(.event == "SubagentStop" and ('
  local sep=""
  local agent_type

  [[ -f "$subagent_log" ]] || return 1

  if [[ -z "$loop_run_id" ]]; then
    has_any_subagent_for_current "$@"
    return
  fi

  for agent_type in "$@"; do
    jq_expr="${jq_expr}${sep}.agent_type == \"${agent_type}\""
    sep=" or "
  done
  jq_expr="${jq_expr}) and .loop_run_id == \$loop_run_id)"

  jq -e --arg loop_run_id "$loop_run_id" "$jq_expr" "$subagent_log" >/dev/null
}

requires_security_review() {
  local raw path
  while IFS= read -r raw; do
    path="${raw#?? }"
    case "$path" in
      .claude/engineering-loop-baseline.sha|.claude/engineering-loop-state.json|.claude/engineering-loop-events.jsonl|.claude/engineering-loop-commands.jsonl|.claude/engineering-loop-edits.jsonl|.claude/engineering-loop-run-id|.claude/engineering-loop-mode|.claude/engineering-loop-review-disposition.json)
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
      ':(exclude).claude/engineering-loop-mode' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git diff --name-only -- . \
      ':(exclude).claude/engineering-loop-baseline.sha' \
      ':(exclude).claude/engineering-loop-state.json' \
      ':(exclude).claude/engineering-loop-events.jsonl' \
      ':(exclude).claude/engineering-loop-commands.jsonl' \
      ':(exclude).claude/engineering-loop-edits.jsonl' \
      ':(exclude).claude/engineering-loop-run-id' \
      ':(exclude).claude/engineering-loop-mode' \
      ':(exclude).claude/engineering-loop-review-disposition.json' 2>/dev/null || true
    git ls-files --others --exclude-standard -- . 2>/dev/null || true
  )
  return 1
}

tests_not_applicable() {
  [[ "$loop_mode" == "analysis" ]] && return 0
  [[ -f "$state_file" ]] && jq -e '.tests.status == "not_applicable"' "$state_file" >/dev/null
}

has_passing_test_command() {
  tests_not_applicable && return 0

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

latest_edit_epoch() {
  if [[ ! -f "$edit_log" ]]; then
    return 0
  fi

  jq -s -r --arg current "$current" --arg loop_run_id "$loop_run_id" '
    [
      .[]
      | select(
        .change_fingerprint == $current
        and (.event == "PostToolUse" or .event == "PostToolUseFailure")
        and (.tool_name | IN("Edit", "Write", "MultiEdit", "NotebookEdit"))
        and (if ($loop_run_id | length) > 0 then .loop_run_id == $loop_run_id else true end)
        and ((.file_path // "") | test("/\\.claude/engineering-loop-[^/]+$") | not)
      )
      | .timestamp_epoch
      | select(type == "number")
    ]
    | max // empty
  ' "$edit_log"
}

has_test_after_latest_edit() {
  tests_not_applicable && return 0

  local latest_edit
  latest_edit="$(latest_edit_epoch)"

  if [[ -z "$latest_edit" ]]; then
    return 0
  fi

  [[ -f "$command_log" ]] && jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" --argjson latest_edit_epoch "$latest_edit" '
    select(
      .change_fingerprint == $current
      and .event == "PostToolUse"
      and .tool_name == "Bash"
      and (.is_test_command == true)
      and (.exit_code == 0 or .exit_code == null)
      and (if ($loop_run_id | length) > 0 then .loop_run_id == $loop_run_id else true end)
      and ((.timestamp_epoch // 0) > $latest_edit_epoch)
    )
  ' "$command_log" >/dev/null
}

has_valid_state() {
  local security_required=false
  if requires_security_review; then
    security_required=true
  fi

  [[ -f "$state_file" ]] && jq -e --arg current "$current" --arg loop_run_id "$loop_run_id" --argjson security_required "$security_required" '
    def done: . == "complete" or . == "not_applicable";
    (.change_fingerprint == $current)
    and (.loop_run_id == $loop_run_id and ($loop_run_id | length) > 0)
    and (.iteration | type == "number" and . >= 1 and . <= 3)
    and (.steps.explore | done)
    and (.steps.architect | done)
    and (.steps.implementation | done)
    and (.steps.tests | done)
    and (.steps.code_review | done)
    and (if $security_required then .steps.security_review == "complete" else (.steps.security_review // "not_applicable" | done) end)
    and (.steps.devops | done)
    and (.steps.fixes | done)
    and (.tests.status == "passed" or .tests.status == "not_applicable")
  ' "$state_file" >/dev/null
}

required_review_agents_json() {
  if [[ "$loop_mode" == "analysis" ]]; then
    printf '%s\n' '["code-reviewer","security-auditor","devops-engineer"]'
    return
  fi

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

if [[ -f "$state_file" ]]; then
  add_passed "state file exists"
else
  add_missing "$state_file is missing"
  add_action "Run .claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh after required agent/review evidence exists."
fi

if has_valid_state; then
  add_passed "state file matches current fingerprint and required schema"
else
  add_missing "$state_file must match fingerprint $current and mark required steps complete/not_applicable"
  add_action "Regenerate state with .claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh, then inspect pending steps."
fi

if [[ -f "$review_disposition_file" ]]; then
  add_passed "review disposition file exists"
else
  add_missing "$review_disposition_file is missing"
  add_action "Run .claude/skills/engineering-loop/scripts/update-review-disposition-template.sh after reviewers run."
fi

if has_valid_review_disposition; then
  add_passed "review findings have explicit dispositions"
else
  add_missing "$review_disposition_file must match current run/fingerprint and disposition every required reviewer finding"
  add_action "Fill .claude/engineering-loop-review-disposition.json with fixed, accepted_risk, or not_applicable plus evidence for every reviewer finding."
fi

if [[ -n "$loop_run_id" ]]; then add_passed "loop run id $loop_run_id"; else add_missing "active loop run id"; add_action "Start the loop with .claude/skills/engineering-loop/scripts/start-engineering-loop.sh, or use --mode analysis for validation-only work."; fi
if has_subagent_for_run "Explore"; then add_passed "Explore evidence for loop run"; else add_missing "SubagentStop evidence for Explore in current loop run"; add_action "Run @Explore for the current task."; fi
if has_subagent_for_run "architect-reviewer"; then add_passed "architect-reviewer evidence for loop run"; else add_missing "SubagentStop evidence for architect-reviewer in current loop run"; add_action "Run @architect-reviewer and carry its decisions into the next stage."; fi
if [[ "$loop_mode" == "analysis" ]]; then
  add_passed "implementation not applicable for analysis mode"
elif has_any_subagent_for_current "python-pro" "backend-developer" "frontend-developer" "fullstack-developer" "devops-engineer"; then
  add_passed "implementation agent evidence"
else
  add_missing "SubagentStop evidence for an implementation agent such as python-pro"
  add_action "Run the appropriate implementation subagent, usually @python-pro for Python work."
fi
if [[ "$loop_mode" == "analysis" ]]; then
  add_passed "test-automator not applicable for analysis mode"
elif has_subagent_for_current "test-automator"; then add_passed "test-automator evidence"; else add_missing "SubagentStop evidence for test-automator"; add_action "Run @test-automator before the final test command."; fi
if has_subagent_for_current "code-reviewer"; then add_passed "code-reviewer evidence"; else add_missing "SubagentStop evidence for code-reviewer"; add_action "Run @code-reviewer against the final diff or analysis findings."; fi
if requires_security_review; then
  if has_subagent_for_current "security-auditor"; then
    add_passed "security-auditor evidence"
  else
    add_missing "SubagentStop evidence for security-auditor"
    add_action "Run @security-auditor because this task touches sensitive paths or analysis mode requires it."
  fi
else
  add_passed "security review not applicable for current changed paths"
fi
if has_subagent_for_current "devops-engineer"; then add_passed "devops-engineer evidence"; else add_missing "SubagentStop evidence for devops-engineer"; add_action "Run @devops-engineer for CI/CD, deployability, and operations review."; fi

if [[ "$loop_mode" == "analysis" ]]; then
  add_passed "test command not applicable for analysis mode"
elif has_passing_test_command; then
  add_passed "passing Bash test command evidence"
else
  add_missing "passing Bash test command evidence after current changes"
  add_action "Run the relevant test command after the final edit, for example python -m pytest or uv run pytest."
fi

if has_test_after_latest_edit; then
  add_passed "latest passing test is newer than latest edit, or no edit log exists"
else
  add_missing "rerun relevant tests after the latest edit"
  add_action "Rerun tests because files changed after the last passing test command."
fi

if [[ "$quiet" == false ]]; then
  echo "Engineering loop status"
  echo "Fingerprint: $current"
  echo

  echo "Complete:"
  if [[ "${#passed[@]}" -eq 0 ]]; then
    echo "- none"
  else
    printf -- '- %s\n' "${passed[@]}"
  fi
  echo

  echo "Missing:"
  if [[ "${#missing[@]}" -eq 0 ]]; then
    echo "- none"
  else
    printf -- '- %s\n' "${missing[@]}"
  fi
  echo

  echo "Next actions:"
  if [[ "${#next_actions[@]}" -eq 0 ]]; then
    echo "- none"
  else
    printf '%s\n' "${next_actions[@]}" | awk '!seen[$0]++ { print "- " $0 }'
  fi
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  exit 2
fi

exit 0
