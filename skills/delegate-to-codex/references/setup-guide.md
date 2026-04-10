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
chmod +x ~/.claude/plugins/codex-delegate/scripts/*.sh
```

### Step 3: Register Plugin

Add to `~/.claude/plugins/installed_plugins.json` inside the `"plugins"` object:

```json
"codex-delegate@local": [
  {
    "scope": "user",
    "installPath": "ABSOLUTE_PATH_TO/.claude/plugins/codex-delegate",
    "version": "1.2.1",
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

## Using an API Proxy (instead of direct OpenAI)

If you connect through a proxy instead of directly to `api.openai.com`, configure `~/.codex/config.toml`:

```toml
model_provider = "crs"
model = "gpt-5.4"
disable_response_storage = true
preferred_auth_method = "apikey"

[model_providers.crs]
name = "crs"
base_url = "http://YOUR_PROXY_HOST:PORT/openai"
wire_api = "responses"
requires_openai_auth = true

[windows]
sandbox = "elevated"
```

**Common proxy mistakes:**

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `base_url` missing `/openai` suffix | 404 on `/api/responses` | Add `/openai` to the URL |
| `wire_api = "chat"` | Codex v0.118+ rejects it | Must be `"responses"` |
| `model_provider = "anthropic"` | "not found" error | Codex only supports OpenAI-compatible providers |
| Chinese characters in project path | HTTP header UTF-8 encoding error | Move project to an ASCII-only path (e.g., `D:\projects\`) |

Set API key via environment variable:

```bash
export OPENAI_API_KEY="your-key-here"
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `codex: command not found` | Install Codex CLI: `npm install -g @openai/codex` |
| `401 Unauthorized` | Set `OPENAI_API_KEY` environment variable |
| 404 `/api/responses` | Check `base_url` has correct path suffix; ensure `wire_api = "responses"` |
| `model_provider not found` | Use a custom provider name with `[model_providers.xxx]` section |
| Chinese path UTF-8 error | Move project to ASCII-only path |
| Plugin not loading | Check `installed_plugins.json` path is correct and absolute |
| `/codex` command not recognized | Verify `commands/codex.md` exists and restart Claude Code |
| Scripts fail with permission error | Run `chmod +x ~/.claude/plugins/codex-delegate/scripts/*.sh` |

## Model Selection

By default, Codex uses the model configured in `~/.codex/config.toml`. Override per-task:

```bash
# In the script invocation, add -m flag
codex exec --full-auto -m o3 "task"
```

To make this configurable through the plugin, edit the script or ask Claude to pass the `-m` flag.
