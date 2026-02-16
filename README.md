# Claude Code Dispatch 🚀

**One-command dispatch of development tasks to Claude Code with automatic notification on completion.** Zero polling, zero token waste.

Fire-and-forget your coding tasks → Claude Code builds it in the background → you get a rich Telegram notification when it's done.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 📺 **YouTube**: [AISuperDomain](https://www.youtube.com/@AIsuperdomain) — AI coding tutorials and demos

## ✨ Features

- 🔥 **Fire-and-forget** — Dispatch a task and walk away. Get notified when done.
- 🤖 **Agent Teams** — Auto-split tasks into parallel Dev + Testing agents
- 📱 **Telegram notifications** — Rich completion reports with test results, file listings, duration
- 🔄 **Three-layer callback** — Telegram message → webhook wake → heartbeat fallback
- 🎯 **Auto-callback detection** — Place a `dispatch-callback.json` in your workspace, zero params needed
- 🛡️ **Battle-tested** — 100+ real-world tasks, all edge cases handled

## 📐 Architecture

```
dispatch.sh
  → write task-meta.json
  → launch Claude Code via claude_code_run.py (PTY wrapper)
  → [Agent Teams: Lead splits work → Dev + Testing Agents run in parallel]
  → Claude Code finishes → Stop Hook fires
    → notify-hook.sh reads meta + output
    → writes latest.json
    → sends Telegram notification
    → wakes AGI via webhook
    → writes pending-wake.json (fallback)
```

## 🚀 Quick Start

### 1. Install

```bash
git clone https://github.com/win4r/claude-code-dispatch.git
cd claude-code-dispatch
chmod +x scripts/*.sh scripts/*.py
```

### 2. Setup Hook

Copy the hook script path to Claude Code settings:

```bash
# Edit ~/.claude/settings.json
# See docs/hook-setup.md for full config
```

### 3. Dispatch a Task

```bash
# Simple task
bash scripts/dispatch.sh \
  -p "Build a Python CLI calculator with Click" \
  -n "calc-cli" \
  -w /path/to/project \
  --permission-mode bypassPermissions

# With Telegram notification
bash scripts/dispatch.sh \
  -p "Build a REST API with FastAPI" \
  -n "my-api" \
  -g "<your-telegram-group-id>" \
  -w /path/to/project \
  --permission-mode bypassPermissions

# Agent Teams (parallel dev + testing)
bash scripts/dispatch.sh \
  -p "Build a weather CLI with API, caching, and colored output" \
  -n "weather-cli" \
  -g "<your-telegram-group-id>" \
  --agent-teams \
  --permission-mode bypassPermissions \
  -w /path/to/project
```

## 📋 Parameters

| Param | Short | Required | Description |
|-------|-------|----------|-------------|
| `--prompt` | `-p` | ✅ | Task description |
| `--name` | `-n` | | Task name for tracking |
| `--group` | `-g` | | Telegram group ID for notifications |
| `--workdir` | `-w` | | Working directory (default: cwd) |
| `--agent-teams` | | | Enable Agent Teams (parallel dev+test) |
| `--teammate-mode` | | | Display: `auto` / `in-process` / `tmux` |
| `--permission-mode` | | | `bypassPermissions` / `plan` / `acceptEdits` |
| `--allowed-tools` | | | Tool whitelist (e.g. `"Read,Bash"`) |
| `--model` | | | Model override |
| `--callback-group` | | | Telegram group for callback |
| `--callback-dm` | | | Telegram user ID for DM callback |
| `--callback-account` | | | Telegram bot account name |

## 🤖 Agent Teams

When `--agent-teams` is enabled, the dispatch script injects instructions for the Lead to:

1. Split the task into parallel sub-agents
2. Assign a dedicated **Testing Agent** that writes and runs tests
3. Testing Agent runs in parallel with Dev Agent(s)
4. All tests must pass before task is considered done

Each sub-agent is an **independent Claude Code process** sharing the same filesystem.

### Proven Results

| Project | Agents | Tests | Duration |
|---------|--------|-------|----------|
| Weather CLI | 4 (api, formatter, testing, lead) | 42 passed | 5m34s |
| Calculator CLI | 3 (dev, testing, lead) | 18 passed | 3m12s |
| REST API | 4 (routes, db, testing, lead) | 31 passed | 7m45s |

## 🔄 Auto-Callback Detection

Place a `dispatch-callback.json` in your workspace root:

**For DM bots:**
```json
{
  "type": "dm",
  "dm": "<telegram-user-id>",
  "account": "<bot-account-name>"
}
```

**For group agents:**
```json
{
  "type": "group",
  "group": "<telegram-group-id>"
}
```

**For webhook wake only:**
```json
{
  "type": "wake"
}
```

Then dispatch without callback params — it auto-detects.

## 📁 Result Files

All results stored in `data/claude-code-results/`:

| File | Content |
|------|---------|
| `latest.json` | Full result (output, task name, group, timestamp) |
| `task-meta.json` | Task metadata (prompt, workdir, status, duration) |
| `task-output.txt` | Raw Claude Code stdout |
| `pending-wake.json` | Heartbeat fallback notification |
| `hook.log` | Hook execution log |

## ⚠️ Gotchas

1. **Must use PTY wrapper** — Direct `claude -p` hangs in non-TTY environments. `claude_code_run.py` handles this via `script(1)`.
2. **Hook fires on ALL Claude Code runs** — Not just dispatched ones. The hook validates meta file freshness (<2h) to avoid re-sending old notifications.
3. **Hook fires twice** — Stop + SessionEnd. Built-in `.hook-lock` deduplicates (30s window).
4. **tee pipe race condition** — Hook sleeps 1s to wait for pipe flush before reading output.
5. **Always set `-w` explicitly** — Missing workdir can drift into wrong cwd.
6. **Codex is different** — This tool is for Claude Code only. For OpenAI Codex CLI, see [codex-cli-dispatch](https://github.com/win4r/codex-cli-dispatch) (coming soon).

## 🔧 Integration with OpenClaw

This tool works standalone, but is designed to integrate with [OpenClaw](https://github.com/openclaw/openclaw):

- Telegram notifications via `openclaw message send`
- AGI wake via `/hooks/wake` webhook
- Multi-agent orchestration via OpenClaw's agent system

## 📖 Documentation

- [Hook Setup Guide](docs/hook-setup.md)
- [Prompt Guide for Agent Teams](docs/prompt-guide.md)

## 📺 More

- **YouTube**: [@AISuperDomain](https://www.youtube.com/@AIsuperdomain)
- **OpenClaw**: [openclaw.ai](https://docs.openclaw.ai)

## License

[MIT](LICENSE)
