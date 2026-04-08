# Codex CLI Reference

## Commands

### codex exec (Non-Interactive Execution)

Primary command for automated task delegation.

```bash
codex exec [OPTIONS] [PROMPT]
```

Key flags:
- `--full-auto` — Auto-approve actions, workspace-write sandbox (recommended default)
- `-s, --sandbox <MODE>` — Sandbox policy: `read-only`, `workspace-write`, `danger-full-access`
- `-C, --cd <DIR>` — Working directory for Codex
- `--ephemeral` — Don't persist session files (clean execution)
- `-o, --output-last-message <FILE>` — Write Codex's final response to a file
- `-m, --model <MODEL>` — Override the model (e.g., `o3`, `o4-mini`)
- `-i, --image <FILE>` — Attach image(s) to the prompt
- `--json` — Output events as JSONL
- `--skip-git-repo-check` — Allow running outside a git repo
- `--add-dir <DIR>` — Additional writable directories

### codex review (Code Review)

Dedicated code review command.

```bash
codex review [OPTIONS] [PROMPT]
```

Key flags:
- `--uncommitted` — Review staged, unstaged, and untracked changes
- `--base <BRANCH>` — Review changes against a base branch
- `--commit <SHA>` — Review a specific commit
- `--title <TITLE>` — Optional commit title for context

### codex (Interactive)

Standard interactive mode. Not used for delegation (requires terminal interaction).

## Sandbox Modes

| Mode | Permissions | Use Case |
|------|-------------|----------|
| `read-only` | Read files only, no writes | Analysis, review, audit |
| `workspace-write` | Read + write within project | Standard implementation (default with `--full-auto`) |
| `danger-full-access` | Full system access | Avoid unless absolutely necessary |

## Output Capture

The `-o` flag writes Codex's final message to a file. Combined with stdout capture, this provides two channels:
- **stdout**: Real-time execution output (tool calls, progress)
- **-o file**: Clean final response from Codex

## Configuration

Codex reads from `~/.codex/config.toml`. Override with `-c key=value`:

```bash
codex exec -c model="o3" --full-auto "task"
codex exec -c 'sandbox_permissions=["disk-full-read-access"]' "task"
```

## Session Management

- `codex resume` — Resume a previous session
- `codex fork` — Fork a previous session
- `--ephemeral` — Prevent session persistence (recommended for delegation)

## Integration Notes

When called from Claude's Bash tool:
1. Always use `codex exec` (non-interactive mode)
2. Always include `--ephemeral` to avoid session clutter
3. Use `-o` for clean output capture
4. Set `-C` to the correct project directory
5. Prefer `--full-auto` for standard tasks
6. Override model with `-m` only if the user requests a specific model
