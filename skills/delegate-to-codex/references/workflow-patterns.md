# Development Workflow Patterns

Codex integrates into Claude's development workflow at specific checkpoints. Each pattern defines: when it triggers, what Codex does, and how results flow back to Claude.

## Pattern 1: Post-Development Cross Review

**When:** Claude has finished writing or modifying code for a feature/fix.

**Trigger phrases:** "写完了让 codex review", "codex 检查一下", "交叉审查", or Claude proactively suggests after completing significant code changes.

**Flow:**

```
Claude finishes code → Suggest Codex review → Codex reviews → Report findings → Claude decides
```

**Codex role:** Inspector only. Report findings and suggestions. Do NOT auto-fix.

**Execution:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh "<working_dir>" "<review_instructions>"
```

**Prompt templates:**

For general review:
```
Review the uncommitted changes. Focus on:
1. Logic errors and potential bugs
2. Edge cases not handled
3. Security vulnerabilities (injection, XSS, auth bypass)
4. Performance concerns
5. Code style consistency with the rest of the codebase

For each finding, provide:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- File and line number
- Description of the issue
- Suggested fix (code snippet)
```

For targeted review:
```
Review the changes in src/auth/ module. This implements session-based authentication.
Focus on: token handling security, session expiration logic, and race conditions.
Report findings with severity levels and suggested fixes.
```

**After Codex returns:**

1. Parse findings by severity
2. Present to user: "Codex 发现了 X 个问题：2 个 HIGH，3 个 MEDIUM..."
3. For each finding, explain whether Claude agrees and recommend action
4. Let user decide which to fix

**When to proactively suggest this pattern:**

- After Claude writes 50+ lines of new code
- After modifying authentication, payment, or data-handling logic
- Before committing code the user plans to deploy
- When the user asks for a "second opinion"

## Pattern 2: Test-Fix Cycle

**When:** After code is written and needs testing, or when tests are failing.

**Trigger phrases:** "让 codex 跑测试修 bug", "codex 把测试跑通", "测试修复交给 codex", or Claude identifies failing tests after implementation.

**Flow:**

```
Claude/User identifies need → Codex runs tests → Fix failures → Re-run → (max 3 rounds) → Report
```

**Codex role:** Executor. Run tests, diagnose failures, fix source code, verify. Hand back if stuck.

**Execution:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-testfix.sh "<working_dir>" "<test_command>" 3 "<focus_hint>"
```

**Common test commands by language:**

| Language | Test Command |
|----------|-------------|
| Python | `pytest` or `python -m pytest` |
| JavaScript/TypeScript | `npm test` or `npx jest` |
| Go | `go test ./...` |
| Rust | `cargo test` |
| Java | `mvn test` or `gradle test` |

**After Codex returns:**

If all tests pass:
1. Review the fixes Codex made (git diff)
2. Verify fixes are correct (not just making tests pass with hacks)
3. Report to user: "Codex 修复了 X 个测试失败，改动如下..."

If some tests still fail after 3 rounds:
1. Read Codex's diagnosis
2. Claude analyzes the remaining failures
3. Decide: Claude fixes directly, or re-delegate with better context
4. Report to user: "Codex 修了 3 轮还有 N 个测试没过，我来分析一下原因..."

**When to proactively suggest this pattern:**

- After Claude implements a feature and tests exist
- When user reports "tests are failing"
- After a refactor that may have broken things

## Pattern 3: Bug Diagnosis

**When:** A specific bug is reported, or unexpected behavior is observed.

**Trigger phrases:** "让 codex 查一下这个 bug", "codex 分析一下原因", "交给 codex 诊断"

**Flow:**

```
Bug described → Codex analyzes in read-only → Report diagnosis + suggestions → Claude decides approach
```

**Codex role:** Analyst only. Read code, trace the bug, suggest fixes. Do NOT modify files.

**Execution:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "read-only" "<working_dir>" "<diagnosis_prompt>"
```

**Prompt template:**

```
Bug report: [description of the bug]

Analyze the codebase to find the root cause. Steps:
1. Identify the relevant code paths
2. Trace the data flow to find where the bug originates
3. Check for related issues (similar patterns elsewhere)
4. Suggest 1-3 fix approaches, ranked by confidence

For each fix approach, provide:
- What to change (file, function, line)
- The fix (code snippet)
- Risk assessment (could this break something else?)
- Confidence level (HIGH / MEDIUM / LOW)

Do NOT modify any files. Report only.
```

**After Codex returns:**

1. Review Codex's analysis
2. Claude validates the diagnosis against its own understanding
3. Present to user: "Codex 的诊断是...，建议的修复方案..."
4. If Claude agrees: propose implementing the fix
5. If Claude disagrees: explain the discrepancy and offer Claude's alternative analysis

## Pattern 4: Implementation Verification

**When:** Claude has finished implementing a feature and wants end-to-end verification.

**Flow:**

```
Claude completes feature → Codex reviews code → Codex runs tests → Combined report → User decides
```

This combines Pattern 1 + Pattern 2 sequentially:

```bash
# Step 1: Review
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh "<working_dir>" "Review the uncommitted changes for the [feature name] implementation. Check for bugs, security issues, and edge cases."

# Step 2: Test (if review passes)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-testfix.sh "<working_dir>" "<test_command>" 3
```

**When to proactively suggest this pattern:**

- When Claude is about to mark a significant task as complete
- Before creating a commit for a feature branch
- When the user says "做完了" or "搞定了"

## Workflow Integration Decision Tree

```
Claude just finished writing code?
├── Yes: Significant changes (50+ lines)?
│   ├── Yes → Suggest Pattern 1 (Cross Review)
│   │         Then Pattern 2 (Test-Fix) if tests exist
│   └── No  → Claude reviews own code, skip Codex
│
User reports a bug?
├── Yes: Complex / hard to trace?
│   ├── Yes → Pattern 3 (Bug Diagnosis) in read-only
│   └── No  → Claude fixes directly
│
Tests are failing?
├── Yes: Multiple failures?
│   ├── Yes → Pattern 2 (Test-Fix Cycle)
│   └── No  → Claude fixes the single failure
│
About to commit / deploy?
├── Yes → Pattern 4 (Implementation Verification)
```
