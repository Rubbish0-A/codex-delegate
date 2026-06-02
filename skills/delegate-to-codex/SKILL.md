---
name: delegate-to-codex
description: >-
  Use when the user explicitly asks for Codex ("交给 codex", "用 codex 改",
  "codex review", "delegate to codex", "let codex handle this"), or when
  Claude identifies clear value in offloading to Codex CLI: precise
  micro-edits, batch refactors across 5+ files, iterative test-fix cycles,
  post-implementation cross review, or read-only bug diagnosis. Codex runs
  as a subprocess; its reasoning stays out of Claude's context window.
version: 1.6.3
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

### When Codex Is Likely Not the Right Tool

These are **hints**, not blockers. If the user explicitly asks for Codex, **delegate anyway** — they own the decision.

- Architecture/design discussions where reasoning > execution → Claude is usually faster
- Single-line edits Claude can do in one Edit call → no value in spinning up subprocess
- Tasks involving raw credentials/secrets handling → keep in Claude's controlled context
- User hasn't mentioned Codex and the change is trivial → suggest Codex only when value is clear

If unsure, **delegate**. The token cost is bounded (see Prompt Economy section), and Claude reviews the diff afterward.

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

#### Prompt Economy (token-cost awareness)

The whole value proposition of this plugin is **Codex's internal reasoning does not occupy Claude's context window** — only the `-o FILE` final response flows back. As of v1.5.0 the scripts already enforce this at the IO layer (stdout/stderr redirected, silent on success, tail-dumped on failure).

But the `-o FILE` payload is shaped by **your prompt**. Default the prompt toward concise, structured output:

- **Bad**: `"Refactor the auth module."` → Codex writes multi-paragraph narrative of every change.
- **Good**: `"Refactor auth module per the plan in step 1. Final report: file:line of each change + one-sentence rationale. No per-file narration."`
- **Also good**: `"Find all callers of deprecated func X. Report only: file path + line number + calling expression. Under 200 words total."`

The `run-codex-task.sh` script already appends a generic "under 300 words" constraint, but your task-specific shape beats that every time. For reviews, force `[SEVERITY] file:line — issue (fix)` format. For diagnosis, force "root cause in ≤3 sentences + suggested fix location." For test-fix, the script already enforces the final-report schema.

#### When to ask for more verbosity

Override the default terseness when:
- User explicitly asked for a detailed walkthrough ("explain what Codex did")
- Task is a novel analysis where the reasoning chain is the deliverable
- Set `CODEX_VERBOSE=1` env var to also dump the full stdout event stream (normally suppressed)

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

## Model & Effort Configuration (v1.6.0+)

All three scripts now **explicitly lock the model and effort level** at invocation time. The values are no longer silently inherited from `~/.codex/config.toml`.

### Defaults

| Script | Model | Effort | Rationale |
|--------|-------|--------|-----------|
| `run-codex-task.sh` | `gpt-5.5` | `xhigh` | Standard execution baseline |
| `run-codex-review.sh` | `gpt-5.5` | `xhigh` | Diagnostic depth > speed (codex has NO `max` effort — that is Claude-only) |
| `run-codex-testfix.sh` | `gpt-5.5` | `xhigh` | Multiple iteration rounds, balance depth and time |

### Environment Variable Overrides

```bash
CODEX_MODEL="gpt-5.5"       # Override the model (default: gpt-5.5)
CODEX_EFFORT="xhigh"        # Override reasoning effort (default per-script)
CODEX_PROFILE="<name>"      # Use a profile from ~/.codex/config.toml
CODEX_ADD_DIR="<path>"      # Additional writable directory (monorepo)
CODEX_TIMEOUT=300           # Seconds before timeout (default: 300/600)
CODEX_VERBOSE=1             # Dump suppressed stdout event stream
CODEX_BYPASS_SANDBOX=1      # Force sandbox bypass (default: 1 on Windows, 0 elsewhere)
```

### Windows Sandbox Bypass (v1.6.1+)

**Problem**: codex-cli 0.128.0+ has a Windows-specific bug where every PowerShell subprocess spawn fails with:

```
ERROR codex_core::exec: exec error: windows sandbox: spawn setup refresh
```

Codex falls back to `apply patch` for writes (so files do get created), but every verification step retries the broken sandbox spawn — accumulating timeouts until the script hits its 300s deadline with EXIT 124. The bug is identical to the V1.3-era report and has not been fixed upstream.

**Fix (automatic on Windows)**: scripts detect `OSTYPE=msys*|cygwin*|win32*` or `OS=Windows_NT` and replace `-s workspace-write` with `--dangerously-bypass-approvals-and-sandbox`. Codex runs PowerShell directly without the broken sandbox layer.

**Safety net retained**: 
- Claude's git auto-stash + `HEAD_BEFORE` rollback still applies — Codex misbehavior is recoverable.
- All delegations still go through Cautious Mode (read-only proposal → Claude review → execute) by default.
- The "danger" of `--dangerously-bypass-approvals-and-sandbox` on Windows is largely nominal since the sandbox it bypasses was broken anyway.

**Override the default**:
```bash
CODEX_BYPASS_SANDBOX=0 bash run-codex-task.sh ...  # Force workspace-write on Windows
CODEX_BYPASS_SANDBOX=1 bash run-codex-task.sh ...  # Force bypass on Linux/macOS
```

**Other platforms (Linux/macOS)**: sandbox works correctly; bypass stays off by default. Don't enable unless you have a specific reason.

### Banner Output (verifiability)

Every invocation now prints a banner before execution:

```
=== CODEX DELEGATION ===
Model:    gpt-5.5
Effort:   xhigh
Mode:     full-auto
Timeout:  300s
Workdir:  /path/to/project
```

If you don't see the banner, the script didn't run. If the model shown is wrong, the env var or script is being overridden somewhere — investigate before proceeding.

## Diagnosis Mode Prompt Template

When delegating a read-only bug analysis (Diagnosis Mode), use this template to constrain the output shape:

```
<!-- TODO: User fills in their preferred diagnosis prompt template here -->
<!-- Suggested structure (you decide the exact wording):
     - What the bug looks like (symptom)
     - Reproduction context (when it happens)
     - What output format you want back (root cause? affected files? fix suggestion?)
     - Response length constraint
-->
```

Until you customize this, the script falls back to your raw prompt + the auto-appended "under 300 words" constraint.

## Additional Resources

### Reference Files
- **`references/workflow-patterns.md`** — Detailed workflow patterns with prompt templates
- **`references/setup-guide.md`** — Installation, API proxy configuration, and troubleshooting
