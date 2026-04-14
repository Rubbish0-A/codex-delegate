---
name: delegate-to-codex
description: >-
  This skill should be used when the user asks to "delegate to codex",
  "let codex handle this", "交给codex", "让codex做", "让codex改",
  "让codex实现", "codex来处理", "用codex修", "codex review", "让codex跑测试",
  "codex查一下这个bug", "交叉审查", or when Claude identifies a task where
  Codex CLI would provide clear value — such as post-development cross review,
  test-fix cycles, bug diagnosis, batch file modifications, or precise
  code micro-adjustments during design discussions.
version: 1.4.1
---

# Delegate to Codex

## Purpose

Enable intelligent, on-demand task delegation from Claude to OpenAI Codex CLI. Claude remains the primary controller — understanding requirements, planning architecture, reviewing results, and communicating with the user. Codex serves as a specialized coding executor, invoked only when it adds clear value.

## Collaboration Modes

**Default: Cautious Mode.** All tasks go through plan-then-execute unless user explicitly says "直接做" or "快速模式".

### Cautious Mode (default)

Two-step collaboration with Claude review checkpoint:

```
Step 1 — Codex proposes (read-only):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "read-only" "<dir>" "Analyze <task>. Propose specific changes for each file. Do NOT modify any files."

  Claude reviews the proposal, adjusts if needed, presents to user.

Step 2 — Codex executes (full-auto, only after approval):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "full-auto" "<dir>" "Execute the following plan: <refined plan from step 1>"

  Claude reviews git diff, verifies changes match the approved plan, reports to user.
```

When to use: All tasks by default. Especially important for:
- Multi-file changes
- Unfamiliar code areas
- Anything touching business logic, auth, or payments

### Quick Mode (user must explicitly request)

Single-step, Codex executes directly:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "full-auto" "<dir>" "<prompt>"
```

Trigger phrases: "直接做", "快速模式", "不用审", "codex 直接改"

When appropriate: Simple renames, formatting, adding imports, trivial fixes.

### Diagnosis Mode (read-only only)

Codex analyzes, never modifies. Claude decides next steps.

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "read-only" "<dir>" "<diagnosis prompt>"
```

## Judgment Criteria

### When to Delegate (at least one condition met)

1. **User explicitly requests** — "交给codex", "let codex do this", "用codex改"
2. **Precise code micro-adjustments** — Claude provides direction, Codex executes surgical edits
3. **Batch/repetitive modifications** — Same pattern across 5+ files
4. **Design-phase prototyping** — Quick code spike to validate a hypothesis
5. **Iterative test-fix cycles** — Run tests, read errors, fix code, repeat
6. **Claude identifies Codex advantage** — Task where Codex would be more precise

### When NOT to Delegate

- Architecture and design discussions — Claude's strength
- Tasks requiring deep cross-file context understanding
- Simple changes Claude handles directly in one edit
- User has not expressed interest in using Codex
- Anything involving secrets, credentials, or deployment

## Conflict Prevention (CRITICAL)

Claude and Codex operate on the **same filesystem**.

### Before Delegation

1. **Finish all pending edits** — Write in-progress changes to disk first
2. **Do NOT hold uncommitted mental state** — Write file A before delegating file B
3. **Let the script handle git safety** — Auto-stashes uncommitted changes

### After Delegation

1. **Re-read any files Claude was working on** — Codex may have modified them
2. **Check the diff output** — Script prints `FILES CHANGED BY CODEX`
3. **Rollback if needed** — `git checkout -- . && git clean -fd`
4. **Restore stash if created** — `git stash pop` after reviewing changes

### Scope Isolation

- Specify exact files for Codex to modify
- Avoid delegating files Claude is actively editing
- Prefer self-contained subtasks (one module, one test file)

## Development Workflow Patterns

Consult **`references/workflow-patterns.md`** for detailed prompt templates.

| Pattern | When | Codex Role | Script |
|---------|------|-----------|--------|
| **Cross Review** | Claude writes 50+ lines, or before commit | Report findings only, NO auto-fix | `run-codex-review.sh` |
| **Test-Fix Cycle** | Tests failing after implementation | Run tests → fix → re-run (max 3 rounds) | `run-codex-testfix.sh` |
| **Bug Diagnosis** | Bug reported, root cause unclear | Read-only analysis, suggest fixes | `run-codex-task.sh "read-only"` |
| **Verification** | Before marking feature complete | Cross Review + Test-Fix sequentially | Both scripts |

### Decision Tree

```
Claude finished writing code?
├── Significant (50+ lines) → Cross Review, then Test-Fix if tests exist
├── Simple → Claude self-reviews
Bug reported? Complex → Bug Diagnosis (read-only)
Tests failing? Multiple → Test-Fix Cycle (max 3 rounds)
About to commit? → Verification (Review + Test)
```

### Suggesting Codex

After completing significant implementations, suggest:
> "代码写完了，要不要让 Codex 做个交叉审查？"

Always let the user decide. Never auto-delegate without awareness and consent.

## Execution Workflow

### Step 1: Prepare a Scoped Prompt

Write a clear, self-contained prompt: specific files, exact changes, constraints, what NOT to change. See **`references/workflow-patterns.md`** for templates.

### Step 2: Choose Collaboration Mode

| User said | Mode | Steps |
|-----------|------|-------|
| (default, nothing specific) | Cautious | read-only proposal → Claude review → full-auto execute → Claude verify |
| "直接做" / "快速模式" | Quick | full-auto execute → Claude verify |
| "查一下" / "分析" | Diagnosis | read-only only → Claude decides |

### Step 3: Execute and Review

For Cautious Mode, always run **two rounds**:

Round 1 (proposal): `run-codex-task.sh "read-only" ...`
→ Claude reviews, adjusts plan, asks user to confirm

Round 2 (execution): `run-codex-task.sh "full-auto" ...`
→ Claude reviews git diff, confirms changes match plan

For review tasks:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh "<working_dir>" "<instructions>"
```

For test-fix:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-testfix.sh "<working_dir>" "<test_cmd>" 3
```

### Step 4: Report to User

Communicate results in the user's language. Include:
- What Codex proposed / changed (brief summary)
- Whether Claude agrees with the approach / changes
- Any issues found or adjustments needed

## Error Handling

If Codex fails (non-zero exit code):
1. Read error output, diagnose the issue
2. Fix and retry with better prompt, or fall back to Claude handling directly
3. Inform user of what happened

If Codex produces incorrect changes:
1. Rollback: `git checkout -- . && git clean -fd`
2. Re-attempt with clearer prompt, or handle directly

## Additional Resources

### Reference Files
- **`references/workflow-patterns.md`** — Detailed workflow patterns with prompt templates
- **`references/setup-guide.md`** — Installation, API proxy configuration, and troubleshooting
