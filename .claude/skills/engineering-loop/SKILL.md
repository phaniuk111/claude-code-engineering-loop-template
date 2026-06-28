---
name: engineering-loop
description: Drive the mandatory repository engineering loop with exact Claude Code subagents, runtime evidence, state updates, tests, parallel review, and Stop-hook validation.
---

# Engineering Loop Skill

Use this skill for non-trivial repository changes, validation work, audits, and next-step planning in this project.

## Core Rule

The loop is not complete because the assistant says it is complete. The loop is complete only when `.claude/hooks/engineering-loop-stop.sh` exits 0.

## Required Flow

1. Run `.claude/skills/engineering-loop/scripts/start-engineering-loop.sh` to create the loop run id.
   - For implementation work, use the default code mode.
   - For validation-only, audit-only, planning, or next-step tasks with no code changes, run `.claude/skills/engineering-loop/scripts/start-engineering-loop.sh --mode analysis`.
2. Run `.claude/skills/engineering-loop/scripts/loop-status.sh`.
3. Invoke the exact named subagent `@Explore`.
4. Invoke the exact named subagent `@architect-reviewer`.
5. Summarize the architecture decisions.
   - In code mode, include them in the implementation subagent prompt.
   - In analysis mode, include them in the validation findings and next-step plan.
6. In code mode, invoke the exact named implementation subagent, normally `@python-pro` for Python. In analysis mode, implementation is `not_applicable`.
7. In code mode, invoke the exact named subagent `@test-automator`. In analysis mode, test changes and test execution are `not_applicable`.
8. In code mode, run the relevant tests after the final edit. In analysis mode, no test command is required unless the validation task changes files.
9. Run independent review agents in parallel when possible:
   - `@code-reviewer`
   - `@devops-engineer`
   - `@security-auditor` when the change touches `.claude/`, GitHub workflows, shell scripts, Python files, dependency/config files, Docker files, secrets, auth, networking, or other sensitive areas.
   - In analysis mode, run `@code-reviewer`, `@security-auditor`, and `@devops-engineer` against the validation findings and next-step plan.
10. Run `.claude/skills/engineering-loop/scripts/update-review-disposition-template.sh`.
11. Read every reviewer result and update `.claude/engineering-loop-review-disposition.json` so every reviewer finding is `fixed`, `accepted_risk`, or `not_applicable` with evidence.
12. Fix findings and rerun tests/reviews up to 3 iterations.
13. Run `.claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh`.
14. Run `.claude/skills/engineering-loop/scripts/loop-status.sh`.
15. Run `.claude/hooks/engineering-loop-stop.sh`.

## Serial And Parallel Rules

Run these stages serially because each stage depends on the previous result:

- `@Explore`
- `@architect-reviewer`
- implementation agent such as `@python-pro` in code mode
- `@test-automator` in code mode
- final test command in code mode

After implementation and tests in code mode, review agents may run in parallel because they inspect the same finished diff from different angles. In analysis mode, review agents may run in parallel after `@Explore` and `@architect-reviewer` because they inspect the same validation findings and next-step plan.

## Required Evidence

The Stop hook validates:

- `.claude/engineering-loop-run-id`
- `.claude/engineering-loop-mode`
- `.claude/engineering-loop-state.json`
- `.claude/engineering-loop-events.jsonl`
- `.claude/engineering-loop-commands.jsonl`
- `.claude/engineering-loop-edits.jsonl`
- `.claude/engineering-loop-review-disposition.json`

`@Explore` and `@architect-reviewer` must match the active loop run id. Implementation, test, review, command, and edit evidence must match the active loop run id and the final change fingerprint.

In analysis mode, implementation and test execution may be `not_applicable`, but reviewer evidence and review dispositions are still required.

Generic `Agent(...)` invocations do not count for required stages. Runtime evidence must contain the exact subagent names.

Every required reviewer must have at least one disposition entry. Use `not_applicable` with evidence when a reviewer reports no actionable findings. Use `accepted_risk` only when the finding is intentionally not fixed and the evidence explains why.

## Final Response

Only after the Stop hook exits 0, summarize:

- Agents used
- Files changed
- Tests run
- Review, security, and DevOps findings
- Remaining risks
