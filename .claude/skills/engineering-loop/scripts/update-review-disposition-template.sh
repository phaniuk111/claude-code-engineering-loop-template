#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

review_disposition_file=".claude/engineering-loop-review-disposition.json"
run_id_file=".claude/engineering-loop-run-id"
stop_hook=".claude/hooks/engineering-loop-stop.sh"

current="$("$stop_hook" --fingerprint)"
loop_run_id=""

if [[ -f "$run_id_file" ]]; then
  loop_run_id="$(cat "$run_id_file")"
fi

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

mkdir -p "$(dirname "$review_disposition_file")"

if requires_security_review; then
  required_agents='["code-reviewer","security-auditor","devops-engineer"]'
else
  required_agents='["code-reviewer","devops-engineer"]'
fi

jq -n \
  --arg loop_run_id "$loop_run_id" \
  --arg fingerprint "$current" \
  --argjson required_agents "$required_agents" \
  '{
    loop_run_id: $loop_run_id,
    change_fingerprint: $fingerprint,
    findings: [
      $required_agents[]
      | {
          agent: .,
          severity: "pending",
          finding: "Summarize this reviewer output. Use \"No findings\" only if the reviewer reported no actionable issues.",
          disposition: "pending",
          evidence: ""
        }
    ]
  }' > "$review_disposition_file"

echo "Wrote review disposition template to $review_disposition_file"
