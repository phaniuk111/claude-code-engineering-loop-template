## Mandatory Engineering Loop

For non-trivial repository changes, do not finish until this loop is complete:

Start non-trivial work through `/engineering-loop` when possible. The command uses the `engineering-loop` skill and the same hook evidence that the Stop hook validates.

1. Run `.claude/skills/engineering-loop/scripts/start-engineering-loop.sh` to create the active loop run id.
2. Explore the codebase, current behavior, existing tests, and relevant documentation with the exact named subagent `@Explore`.
3. Use the exact named subagent `@architect-reviewer` before implementation for design, workflow, and tradeoff review.
4. Before implementation, summarize the architect-reviewer decisions and pass them into the implementation agent prompt.
5. Use the right exact named implementation agent for the code change. Use `@python-pro` for Python work.
6. Use the exact named subagent `@test-automator` to add, improve, or run the relevant tests.
7. After implementation and tests, run independent reviewers in parallel when possible: `@code-reviewer`, `@devops-engineer`, and `@security-auditor` when the change touches `.claude/`, GitHub workflows, shell scripts, Python files, dependency/config files, Docker files, secrets, auth, networking, or other sensitive areas.
8. Run `.claude/skills/engineering-loop/scripts/update-review-disposition-template.sh`, then update `.claude/engineering-loop-review-disposition.json` with every reviewer finding.
9. Fix any findings, rerun relevant tests, and repeat the review/test loop up to 3 times.

Generic `Agent(...)` calls do not count for required stages. Runtime evidence must show the exact required agent names.

Run `.claude/skills/engineering-loop/scripts/loop-status.sh` whenever the loop state is unclear. It prints the current fingerprint, completed evidence, and missing evidence.

Maintain `.claude/engineering-loop-state.json` during non-trivial repository work by running `.claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh`. Mark each required step as `complete` only after the work is actually done:

```json
{
  "loop_run_id": "output stored in .claude/engineering-loop-run-id",
  "change_fingerprint": "output of .claude/hooks/engineering-loop-stop.sh --fingerprint",
  "iteration": 1,
  "steps": {
    "explore": "complete",
    "architect": "complete",
    "implementation": "complete",
    "tests": "complete",
    "code_review": "complete",
    "security_review": "complete",
    "devops": "complete",
    "fixes": "complete"
  },
  "tests": {
    "status": "passed",
    "commands": []
  },
  "notes": []
}
```

Use `"not_applicable"` only when a step genuinely does not apply, and explain why in `notes`.
Before marking the loop complete, run `.claude/skills/engineering-loop/scripts/update-engineering-loop-state.sh` and then `.claude/skills/engineering-loop/scripts/loop-status.sh`.

Maintain `.claude/engineering-loop-review-disposition.json` after reviewer agents run. Every required reviewer must have at least one entry. Use `fixed`, `accepted_risk`, or `not_applicable`; include non-empty evidence for each entry.

```json
{
  "loop_run_id": "output stored in .claude/engineering-loop-run-id",
  "change_fingerprint": "output of .claude/hooks/engineering-loop-stop.sh --fingerprint",
  "findings": [
    {
      "agent": "code-reviewer",
      "severity": "medium",
      "finding": "Missing mixed-sign test",
      "disposition": "fixed",
      "evidence": "Added test_add_mixed_signs"
    }
  ]
}
```

Runtime evidence is required. Claude Code hooks write proof files automatically:

- `.claude/engineering-loop-run-id` records the active loop run id.
- `.claude/engineering-loop-events.jsonl` records actual `SubagentStop` events.
- `.claude/engineering-loop-commands.jsonl` records Bash commands and detects test commands.
- `.claude/engineering-loop-edits.jsonl` records Edit/Write/MultiEdit/NotebookEdit tool usage.
- `.claude/engineering-loop-review-disposition.json` records how reviewer findings were fixed or accepted.

The Stop hook validates both the state file and the runtime evidence. Early planning evidence must match the active loop run id; implementation, test, review, command, and edit evidence must match the active loop run id and final change fingerprint. Review dispositions must match the active loop run id and final change fingerprint. Do not mark a step complete unless the corresponding agent or test evidence exists, or the step is genuinely `not_applicable`. If code changes after tests run, rerun the relevant tests so the latest passing test is newer than the latest edit.

Before the final response, run `.claude/hooks/engineering-loop-stop.sh`. If it exits non-zero, fix the missing items reported by `.claude/skills/engineering-loop/scripts/loop-status.sh` before trying to finish.

The final response for non-trivial repo changes must include:

- Agents used
- Tests run
- Reviewer findings resolved
- Remaining risks, if any

If a step is not applicable, state why briefly and continue with the remaining loop.
