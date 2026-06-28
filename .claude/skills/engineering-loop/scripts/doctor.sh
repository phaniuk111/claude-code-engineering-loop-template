#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

failures=0

pass() {
  printf 'PASS %s\n' "$1"
}

warn() {
  printf 'WARN %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

check_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    pass "$path exists"
  else
    fail "$path is missing"
  fi
}

check_executable() {
  local path="$1"
  check_file "$path"
  if [[ -x "$path" ]]; then
    pass "$path is executable"
  else
    fail "$path is not executable"
  fi
}

check_ignored() {
  local path="$1"
  if git check-ignore -q "$path" 2>/dev/null; then
    pass "$path is ignored"
  else
    fail "$path should be ignored"
  fi
}

echo "Engineering loop doctor"
echo "Repo: $repo_root"
echo

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  pass "inside a Git repository"
else
  fail "not inside a Git repository"
fi

if command -v jq >/dev/null 2>&1; then
  pass "jq is installed"
else
  fail "jq is required"
fi

check_file ".claude/settings.json"
check_file ".claude/engineering-loop-config.json"
check_file ".claude/settings.local.example.json"
check_file ".claude/commands/engineering-loop.md"
check_file ".claude/skills/engineering-loop/SKILL.md"
check_file "CLAUDE.md"

for agent in Explore architect-reviewer python-pro test-automator code-reviewer security-auditor devops-engineer; do
  if [[ "$agent" == "Explore" ]]; then
    pass "Explore is built in"
  else
    check_file ".claude/agents/$agent.md"
  fi
done

while IFS= read -r script; do
  check_executable "$script"
  if bash -n "$script"; then
    pass "$script parses"
  else
    fail "$script has a syntax error"
  fi
done < <(find .claude/hooks .claude/skills/engineering-loop/scripts -type f -name '*.sh' | sort)

if jq empty .claude/settings.json .claude/settings.local.example.json .claude/engineering-loop-config.json >/dev/null; then
  pass "Claude settings/config JSON parses"
else
  fail "Claude settings/config JSON failed to parse"
fi

check_ignored ".claude/settings.local.json"
check_ignored ".claude/engineering-loop-baseline.sha"
check_ignored ".claude/engineering-loop-commands.jsonl"
check_ignored ".claude/engineering-loop-edits.jsonl"
check_ignored ".claude/engineering-loop-events.jsonl"
check_ignored ".claude/engineering-loop-mode"
check_ignored ".claude/engineering-loop-review-disposition.json"
check_ignored ".claude/engineering-loop-run-id"
check_ignored ".claude/engineering-loop-state.json"

if [[ -f ".claude/engineering-loop-baseline.sha" ]]; then
  pass "local baseline exists"
else
  warn "local baseline missing; seed it with: printf 'placeholder\\n' > .claude/engineering-loop-baseline.sha; .claude/hooks/engineering-loop-stop.sh --fingerprint > .claude/engineering-loop-baseline.sha"
fi

if [[ -f ".claude/engineering-loop-baseline.sha" ]]; then
  if .claude/hooks/engineering-loop-stop.sh >/dev/null 2>&1; then
    pass "Stop hook exits 0 for current repository state"
  else
    warn "Stop hook currently reports missing loop evidence; this is expected during an active loop or after local changes"
  fi
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "Doctor result: $failures failure(s)"
  exit 2
fi

echo "Doctor result: OK"
