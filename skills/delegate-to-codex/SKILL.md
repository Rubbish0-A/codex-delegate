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
version: 1.3.0
---

# Delegate to Codex

## Purpose

Enable intelligent, on-demand task delegation from Claude to OpenAI Codex CLI. Claude remains the primary controller — understanding requirements, planning architecture, reviewing results, and communicating with the user. Codex serves as a specialized coding executor, invoked only when it adds clear value.

## Judgment Criteria

### When to Delegate (at least one condition met)

1. **User explicitly requests** — Any variation of "交给codex", "let codex do this", "用codex改"
2. **Precise code micro-adjustments** — Claude provides direction, Codex executes surgical edits with higher precision
3. **Batch/repetitive modifications** — Same pattern across 5+ files (rename, refactor, format)
4. **Design-phase prototyping** — Quick code spike to validate a design hypothesis during planning
5. **Iterative test-fix cycles** — Run tests, read errors, fix code, repeat — Codex handles the loop
6. **Claude identifies Codex advantage** — Specific task where Codex's code generation would be more precise

### When NOT to Delegate

- Architecture and design discussions — Claude's strength
- Tasks requiring deep cross-file context understanding
- Simple changes Claude handles directly in one edit
- User has not expressed interest in using Codex for this session
- Tasks requiring interactive user feedback during execution
- Anything involving secrets, credentials, or deployment

## Conflict Prevention (CRITICAL)

Claude and Codex operate on the **same filesystem**. Prevent conflicts with these mandatory steps:

### Before Delegation

1. **Finish all pending edits** — Write any in-progress file changes to disk before delegating
2. **Do NOT hold uncommitted mental state** — If Claude has a plan to edit files A, B, C and wants to delegate B to Codex, write A first, then delegate B
3. **Let the script handle git safety** — The `run-codex-task.sh` script auto-stashes uncommitted changes

### After Delegation

1. **Re-read any files Claude was working on** — Codex may have modified them
2. **Check the diff output** — The script prints `FILES CHANGED BY CODEX` automatically
3. **If Codex broke something** — Use rollback info from script output: `git checkout -- . && git clean -fd`
4. **If stash was created** — Review Codex changes before running `git stash pop` to restore Claude's prior work

### Scope Isolation

Minimize conflict by giving Codex a **narrow, non-overlapping scope**:
- Specify exact files for Codex to modify
- Avoid delegating files Claude is actively editing
- Prefer delegating self-contained subtasks (one module, one test file)

## Development Workflow Patterns

Codex integrates into development at key checkpoints. Consult **`references/workflow-patterns.md`** for detailed prompt templates.

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

### Proactive Suggestion

After completing significant implementations, suggest:
> "代码写完了，要不要让 Codex 做个交叉审查？"

## Suggesting Codex to the User

When a task matches delegation criteria but the user hasn't explicitly requested Codex, suggest naturally:

> "这个批量重构涉及 12 个文件的同一模式替换，Codex 很擅长这类精确批量改动。要不要我委派给 Codex？"

Always let the user decide. Never auto-delegate without the user's awareness and consent.

## Execution Workflow

### Step 1: Prepare a Scoped Prompt

Write a clear, self-contained prompt for Codex: specific files, exact changes, constraints, what NOT to change. See **`references/workflow-patterns.md`** for prompt templates per pattern.

### Step 2: Choose Execution Mode

| Task Type | Mode | When |
|-----------|------|------|
| Standard implementation/fix | `full-auto` | Most tasks — Codex writes files freely within project |
| Analysis / read-only check | `read-only` | When Codex should only read and report, not modify |

### Step 3: Execute via Bash

For implementation, fix, or refactor tasks:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "<mode>" "<working_dir>" "<prompt>"
```

Parameters:
- `mode`: `full-auto` (default) or `read-only`
- `working_dir`: Absolute path to the project root
- `prompt`: The scoped task description

For code review tasks:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh "<working_dir>" "<review_instructions>"
```

### Step 4: Review Results

The script output contains structured sections. After Codex completes:

1. **Read `CODEX FINAL RESPONSE`** — Codex's own summary of what it did
2. **Read `FILES CHANGED BY CODEX`** — Auto-generated git diff stat
3. **If changes exist** — Run `git diff` for detailed review of specific files
4. **If stash was created** — Decide whether to restore Claude's prior work with `git stash pop`
5. **Verify quality** — Confirm changes match the original requirements

### Step 5: Report to User

Communicate results in the user's language. Include:
- What Codex changed (brief summary)
- Whether the changes look correct
- Any issues found or follow-up needed
- If rollback is recommended

## Error Handling

If Codex fails (non-zero exit code):
1. Read the error output
2. Diagnose whether it's a Codex limitation or a task scope issue
3. Either fix and retry with a better prompt, or fall back to Claude handling directly
4. Inform the user of what happened

If Codex produces incorrect changes:
1. Use rollback: `git checkout -- . && git clean -fd` in the working directory
2. Re-attempt with a clearer, more constrained prompt, or handle directly
3. Explain to the user what went wrong

## Additional Resources

### Reference Files
- **`references/workflow-patterns.md`** — Detailed workflow patterns with prompt templates, decision trees, and examples
- **`references/codex-cli-reference.md`** — Detailed Codex CLI flags, modes, and usage patterns
- **`references/setup-guide.md`** — Installation and API key configuration for new users
