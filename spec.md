# Reliable Agentic Engineering Loop Specification

**Repository:** `devops`  
**Purpose:** Define enhancements to the existing Claude Code mandatory engineering loop to achieve higher reliability, safety, determinism, and Python development quality.  
**Status:** Proposed Specification (v1)  
**Date:** 2026-06-27

## 1. Executive Summary

The current setup (documented in [CLAUDE.md](./CLAUDE.md) and `.claude/`) implements one of the strongest evidence-based engineering loops available in Claude Code. It enforces a full SDLC using named subagents, runtime evidence (JSONL logs), change fingerprinting, state tracking, and a hard Stop hook gate.

This specification proposes targeted, battle-tested extensions drawn from leading community patterns to close remaining gaps in **active prevention**, **specialized quality review**, **Python tooling enforcement**, and **deterministic guardrails**.

**Core Goals**
- Move from "post-facto validation" to "prevention + continuous enforcement".
- Add security and performance as first-class, required (or strongly gated) stages.
- Guarantee Python code quality (lint, format, types) via hooks instead of agent memory.
- Support parallel specialized reviews.
- Maintain full compatibility with the existing mandatory loop, evidence system, and `/engineering-loop` command.

## 2. Current State Assessment

### Strengths (Already Best-in-Class)
- Mandatory ordered loop with exact named subagents (`@Explore`, `@architect-reviewer`, `@python-pro`, `@test-automator`, `@code-reviewer`, `@devops-engineer`).
- Hard evidence requirements via hooks:
  - `engineering-loop-events.jsonl` (SubagentStop)
  - `engineering-loop-commands.jsonl` (Bash + test detection)
  - `engineering-loop-edits.jsonl`
- Change fingerprinting + baseline comparison (`engineering-loop-stop.sh`).
- Iteration cap (max 3) and state machine in `engineering-loop-state.json`.
- Dedicated skill + command for the loop.
- Strong `python-pro` agent definition covering types, patterns, testing, security, async, etc.

### Gaps for Production-Grade Reliability
- No **PreToolUse** active blocking (current hooks are mostly logging via PostToolUse).
- No dedicated security or performance review agents.
- No automated Python quality tooling (Ruff, mypy/ty, coverage) enforced at the hook level.
- Mostly serial execution; parallel subagent patterns are under-utilized.
- Python development relies heavily on agent instructions rather than deterministic enforcement.

## 3. Proposed Enhancements

### 3.1 Active Guardrails via PreToolUse Hooks
**Priority:** Highest (safety & determinism)

Add `PreToolUse` hooks that can **block** operations before they execute.

**Recommended Hooks**
- Block dangerous shell commands (`rm -rf`, force pushes to main, `curl | sh`, fork bombs, `git reset --hard`, etc.).
- Protect sensitive files (`.env*`, secrets, SSH keys, `.claude/engineering-loop-*` state files).
- Python-specific hygiene (e.g., discourage bare `python`/`pip` in favor of `uv` when applicable).
- Secret leakage prevention on Edit/Write (detect common secret patterns).

**Example from Community (adapted from karanb192/claude-code-hooks)**

```javascript
// .claude/hooks/pre-tool-use/block-dangerous-commands.js
// (See full original: https://github.com/karanb192/claude-code-hooks/blob/main/hook-scripts/pre-tool-use/block-dangerous-commands.js)
const SAFETY_LEVEL = 'high'; // critical | high | strict

// Patterns for rm ~, force-push main, curl|sh, chmod 777, reading .env, etc.
// On match → return permissionDecision: "deny" with clear reason (exit code 2 semantics)
```

**Configuration** (add to `.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/pre-tool-use/block-dangerous-commands.js" }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/pre-tool-use/protect-secrets.js" }
        ]
      }
    ]
  }
}
```

**Sources**:
- Official Claude Code Hooks docs (example `block-rm.sh`): https://code.claude.com/docs/en/hooks
- karanb192/claude-code-hooks: https://github.com/karanb192/claude-code-hooks
- Multiple community implementations (elertan/claude-code-rm-guard, various gists for project-dir protection).

### 3.2 New Specialized Subagents
Add agents following the style and format of existing ones (`python-pro.md`, `code-reviewer.md`, etc.).

**Primary Additions**
- `security-auditor.md`
- `performance-engineer.md` (or lightweight variant)

**security-auditor Example (directly from VoltAgent collection)**

```markdown
---
name: security-auditor
description: "Use this agent when conducting comprehensive security audits... "
tools: Read, Grep, Glob
model: inherit
---

You are a senior security auditor...
# (full detailed checklist for OWASP, compliance frameworks, access control, data security, application security, risk assessment, etc.)
```

Full file: https://github.com/VoltAgent/awesome-claude-code-subagents/blob/main/categories/04-quality-security/security-auditor.md

**Integration with Loop**
Update the mandatory loop (CLAUDE.md + engineering-loop skill + `loop-status.sh`) to include security review, either as a required step or as a parallel review after implementation/tests.

### 3.3 Python Quality Enforcement (Ruff, Formatting, Type Checking)
**Priority:** High for Python development.

Replace reliance on `python-pro` instructions with deterministic PostToolUse (and optionally PreToolUse) validators.

**Recommended Pattern (from pydevtools + disler)**
- `PostToolUse` matcher on `Write|Edit` for `*.py` files.
- Run `ruff check --fix` + `ruff format`.
- Run type checker (`mypy` or `ty`).
- On errors: feed output back to agent (or block in strict mode).

**Example Configuration (in agent or global settings)**

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        { "type": "command", "command": "uv run .claude/hooks/validators/ruff_validator.py" },
        { "type": "command", "command": "uv run .claude/hooks/validators/ty_validator.py" }
      ]
    }
  ]
}
```

**Additional Ideas**
- PreToolUse before `git commit` to run full lint suite.
- Hook to enforce `uv run` / `uv add` instead of bare Python tools.

**Key Sources**
- pydevtools "How to configure Ruff with Claude Code": PostToolUse auto-fix + format on every Python edit.
- disler/claude-code-hooks-mastery: `ruff_validator.py` + `ty_validator.py` + ruff.toml. Used inside agent frontmatter (e.g. "builder" agent).
- Similar patterns in multiple production setups.

### 3.4 Parallel Subagent Execution
Official support exists and is explicitly recommended.

**Pattern (from docs)**
```
Research the authentication, database, and API modules in parallel using separate subagents
```

**Benefits for This Repo**
- After implementation: spawn `code-reviewer` + `security-auditor` + `devops-engineer` (or `performance-engineer`) in parallel.
- Faster feedback, multi-angle review.
- Update `loop-status.sh` / evidence collection to handle multiple agents per phase.

**Source**: Official Claude Code Subagents docs — "Run parallel research" example: https://code.claude.com/docs/en/sub-agents

### 3.5 Additional Reliability Improvements
- Attach hooks directly inside subagent frontmatter (newer capability) for per-agent guarantees (e.g., builder always runs Ruff).
- Enhance observability (more structured output from validators logged to commands.jsonl).
- Consider a lightweight "verifier" or self-critique stage.
- Add Python agentic code patterns (retry loops, structured output validation, sandboxing) as first-class examples in the repo, developed using the engineering loop itself.

## 4. Implementation Roadmap

1. **Phase 1 (Safety)**: Add PreToolUse block-dangerous + protect-secrets hooks + update settings.json.
2. **Phase 2 (Specialized Review)**: Create `.claude/agents/security-auditor.md` (and performance if desired). Wire into loop.
3. **Phase 3 (Python Quality)**: Implement Ruff + type validator hooks. Add `ruff.toml` / project config if missing. Update `python-pro` and `test-automator` guidance.
4. **Phase 4 (Parallelism + Polish)**: Update engineering loop docs, `loop-status.sh`, state schema, and skill to support parallel reviews. Add examples of parallel dispatch.
5. **Phase 5 (Dogfood)**: Use the enhanced loop to develop the above changes.

All changes must be made **through the existing engineering loop** (with full evidence).

## 5. References & Citations

### Primary GitHub Repositories
- **VoltAgent/awesome-claude-code-subagents** (100+ high-quality subagent definitions)  
  https://github.com/VoltAgent/awesome-claude-code-subagents  
  - security-auditor.md: https://github.com/VoltAgent/awesome-claude-code-subagents/blob/main/categories/04-quality-security/security-auditor.md
  - performance-engineer.md and code-reviewer.md also in the quality-security category.

- **karanb192/claude-code-hooks** (ready-to-use PreToolUse guardrails)  
  https://github.com/karanb192/claude-code-hooks  
  - block-dangerous-commands.js (full source used as base for examples above).

- **disler/claude-code-hooks-mastery** (deterministic hooks, validators, multi-agent patterns)  
  https://github.com/disler/claude-code-hooks-mastery  
  - Includes ruff_validator.py, ty_validator.py, ruff.toml. Demonstrates attaching validators inside agent frontmatter.

- Official Claude Code Documentation
  - Hooks: https://code.claude.com/docs/en/hooks (PreToolUse blocking examples)
  - Subagents: https://code.claude.com/docs/en/sub-agents (parallel execution guidance)

### Python + Hooks Specific
- pydevtools guides on Ruff + Claude Code hooks (PostToolUse auto-format/lint):  
  https://pydevtools.com/handbook/how-to/how-to-configure-ruff-with-claude-code/

### Discussions & Patterns (X / Community)
- Widespread emphasis on "Hooks as guarantees" vs CLAUDE.md as suggestions (multiple high-engagement posts).
- PreToolUse described as "firewall" or "middleware" for AI agents.
- Parallel subagents + hook-driven handoffs praised in production setups.

## 6. Next Steps

- Review this spec with the current `@architect-reviewer`.
- Create the new hook scripts and agents using the engineering loop.
- Update `CLAUDE.md`, the engineering-loop skill, `settings.json`, and `loop-status.sh` as needed.
- Add a `spec.md` reference or summary into CLAUDE.md once approved.

This specification is intended to be living — update it as new patterns from the community are validated inside this repo's loop.

---

*All proposals are grounded in publicly available, widely adopted patterns from the Claude Code community as of June 2026.*