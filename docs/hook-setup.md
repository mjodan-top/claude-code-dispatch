# Hook Setup Guide

## Claude Code Settings

File: `~/.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-code-dispatch/scripts/notify-hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-code-dispatch/scripts/notify-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

> Replace `/path/to/claude-code-dispatch` with the actual path where you cloned this repo.

## Hook Events

| Event | When | Purpose |
|-------|------|---------|
| `Stop` | Claude Code stops generating | Primary callback |
| `SessionEnd` | Session fully ends | Backup (deduped by 30s lock) |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RESULT_DIR` | `./data/claude-code-results` | Where results are stored |
| `OPENCLAW_BIN` | auto-detect | Path to `openclaw` CLI |
| `OPENCLAW_CONFIG` | `~/.openclaw/openclaw.json` | Config file for webhook token |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway port for webhook |

## Result Directory

Create if needed:
```bash
mkdir -p data/claude-code-results
```

## Telegram Group Setup (OpenClaw)

For notification delivery, the target group needs:
1. Bot added as member
2. Whitelist entry in OpenClaw config:

```json
{
  "channels": {
    "telegram": {
      "groups": {
        "<your-group-id>": {
          "requireMention": false,
          "enabled": true
        }
      }
    }
  }
}
```

No agent or binding needed — notification only.
