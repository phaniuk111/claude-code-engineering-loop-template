#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Engineering loop reminder for non-trivial repository changes:
- Prefer /engineering-loop to start the workflow.
- Run .claude/skills/engineering-loop/scripts/start-engineering-loop.sh before collecting loop evidence.
- Use exact named subagents: @Explore, @architect-reviewer, @python-pro when applicable, @test-automator, @code-reviewer, @devops-engineer.
- Pass architect-reviewer decisions into the implementation agent prompt.
- After tests, run independent reviewers in parallel when possible; include @security-auditor for sensitive paths.
- Generic Agent(...) calls do not count for required stages.
- Planning evidence must match the active loop run id; implementation/review/test evidence must match the run id and final fingerprint.
- Run .claude/skills/engineering-loop/scripts/update-review-disposition-template.sh after reviewers, then fill .claude/engineering-loop-review-disposition.json.
- Every required reviewer needs a disposition entry: fixed, accepted_risk, or not_applicable, with evidence.
- Run relevant tests after the final edit.
- Run .claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh, then .claude/skills/engineering-loop/scripts/loop-status.sh.
- Do not finish until .claude/hooks/engineering-loop-stop.sh exits 0.
EOF
