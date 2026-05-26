---
name: codex
description: Delegate a coding task to Codex CLI for execution (entry point — routes through delegate-to-codex skill)
arguments:
  - name: task
    description: The task description or 'review' for code review mode
    required: true
---

# /codex — Delegate Task to Codex

This slash command is an **explicit entry point** to the `delegate-to-codex` skill. All execution logic — collaboration modes, prompt economy, banner output, git safety, model/effort locking — lives in the skill, not here.

When invoked, Claude should:

1. **Load the skill**: read `${CLAUDE_PLUGIN_ROOT}/skills/delegate-to-codex/SKILL.md` and follow its workflow.
2. **Determine the task type** from `$ARGUMENTS`:
   - Starts with `review` → use `run-codex-review.sh` (Cross Review pattern)
   - Anything else → use `run-codex-task.sh` (Cautious or Quick Mode per user's phrasing)
3. **Pick collaboration mode** per skill guidance:
   - User said "直接做" / "快速模式" → Quick Mode
   - User said "查一下" / "分析" → Diagnosis Mode (read-only)
   - Default → Cautious Mode (read-only proposal → review → full-auto execute)
4. **Use the banner output** (printed by every script) to verify model/effort/mode before proceeding.
5. **Report results** in the user's language, summarizing what changed and Claude's verdict.

## Usage Examples

```
/codex implement user registration endpoint with input validation
/codex fix the failing tests in src/auth/
/codex refactor all API handlers to use the new error handling pattern
/codex review                                  # uncommitted changes
/codex review check for SQL injection         # custom review focus
```

## Why This Indirection

Prior versions had two parallel routing paths (`/codex` and the skill) with subtly different behavior. v1.6.0 consolidates: the skill is the single source of truth; `/codex` is just an explicit user-facing entry, useful when the user wants to **force** delegation rather than let Claude judge.

For the full collaboration model, prompt economy guidance, and decision tree, see the skill at `${CLAUDE_PLUGIN_ROOT}/skills/delegate-to-codex/SKILL.md`.
