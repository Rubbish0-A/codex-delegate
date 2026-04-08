# Codex Delegate Plugin — Setup Guide

## Prerequisites

### 1. Claude Code CLI

Install Claude Code CLI (the host environment for this plugin):
- See https://docs.anthropic.com/en/docs/claude-code for installation

### 2. Codex CLI

Install OpenAI Codex CLI:

```bash
# Via npm (recommended)
npm install -g @openai/codex

# Verify installation
codex --version
```

### 3. OpenAI API Key

Codex CLI requires an OpenAI API key.

**Option A: Environment variable (recommended)**

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export OPENAI_API_KEY="sk-your-key-here"
```

**Option B: Codex config file**

```bash
# Create/edit ~/.codex/config.toml
[auth]
api_key = "sk-your-key-here"
```

**Option C: Login command**

```bash
codex login
```

### 4. Verify Codex Works

```bash
# Quick test — should respond without errors
codex exec --full-auto --ephemeral "echo hello world"
```

## Plugin Installation

### Step 1: Copy Plugin Files

Copy the `codex-delegate/` directory to your Claude Code plugins directory:

```bash
cp -r codex-delegate/ ~/.claude/plugins/codex-delegate/
```

### Step 2: Make Scripts Executable

```bash
chmod +x ~/.claude/plugins/codex-delegate/scripts/run-codex-task.sh
chmod +x ~/.claude/plugins/codex-delegate/scripts/run-codex-review.sh
```

### Step 3: Register Plugin

Add to `~/.claude/plugins/installed_plugins.json` inside the `"plugins"` object:

```json
"codex-delegate@local": [
  {
    "scope": "user",
    "installPath": "ABSOLUTE_PATH_TO/.claude/plugins/codex-delegate",
    "version": "1.1.0",
    "installedAt": "2026-04-08T00:00:00.000Z",
    "lastUpdated": "2026-04-08T00:00:00.000Z"
  }
]
```

Replace `ABSOLUTE_PATH_TO` with your actual home directory path (e.g., `C:\\Users\\yourname` on Windows, `/home/yourname` on Linux).

### Step 4: Enable Plugin

Add to `~/.claude/settings.json` inside `"enabledPlugins"`:

```json
"codex-delegate@local": true
```

### Step 5: Restart Claude Code

Start a new Claude Code session. The plugin will auto-discover skills and commands.

## Verification

In a new Claude Code session:
- Type `/codex test` — should trigger the codex command
- Say "让 codex 帮我检查当前目录" — should trigger the skill

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `codex: command not found` | Install Codex CLI: `npm install -g @openai/codex` |
| `401 Unauthorized` | Set `OPENAI_API_KEY` environment variable |
| Plugin not loading | Check `installed_plugins.json` path is correct and absolute |
| `/codex` command not recognized | Verify `commands/codex.md` exists and restart Claude Code |
| Scripts fail with permission error | Run `chmod +x` on both scripts |

## Model Selection

By default, Codex uses the model configured in `~/.codex/config.toml`. Override per-task:

```bash
# In the script invocation, add -m flag
codex exec --full-auto -m o3 "task"
```

To make this configurable through the plugin, edit the script or ask Claude to pass the `-m` flag.
