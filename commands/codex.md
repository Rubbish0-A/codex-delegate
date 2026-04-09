---
name: codex
description: Delegate a coding task to Codex CLI for execution
arguments:
  - name: task
    description: The task description or 'review' for code review mode
    required: true
---

# /codex — Delegate Task to Codex

Delegate a coding task to OpenAI Codex CLI. Codex executes the task non-interactively and returns results for review.

## Usage Patterns

### Implementation / Fix / Refactor

```
/codex <task description>
```

Examples:
- `/codex implement user registration endpoint with input validation`
- `/codex fix the failing tests in src/auth/`
- `/codex refactor all API handlers to use the new error handling pattern`
- `/codex rename all instances of userId to user_id in the models directory`

### Code Review

```
/codex review [instructions]
```

Examples:
- `/codex review` — Review uncommitted changes
- `/codex review check for security vulnerabilities and SQL injection`

## Execution Steps

1. **Parse the task** — Determine if this is an implementation task or review
2. **Prepare prompt** — Enhance the user's task with current project context (working directory, relevant files)
3. **Execute Codex** — Run via helper script:
   - Implementation: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh "full-auto" "<cwd>" "<prompt>"`
   - Review: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh "<cwd>" "<review_prompt>"`
4. **Review results** — Check Codex output and `git diff` for changes
5. **Report back** — Summarize results in the user's language, highlight any issues

## Important

- Always review Codex output before reporting success
- If Codex fails, diagnose and either retry with a better prompt or handle directly
- Communicate results in the user's language (auto-detect from conversation context)
