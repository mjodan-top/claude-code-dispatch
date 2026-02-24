#!/bin/bash
# dispatch.sh — Dispatch a task to Claude Code with auto-callback
#
# Usage:
#   dispatch.sh [OPTIONS] -p "your prompt here"
#
# Options:
#   -p, --prompt TEXT        Task prompt (required)
#   -n, --name NAME          Task name (for tracking)
#   -g, --group ID           Telegram group ID for result delivery
#   -s, --session KEY        Callback session key (AGI session to notify)
#   -w, --workdir DIR        Working directory for Claude Code
#   --agent-teams            Enable Agent Teams (lead + sub-agents)
#   --teammate-mode MODE     Agent Teams display mode (auto/in-process/tmux)
#   --permission-mode MODE   Claude Code permission mode
#   --allowed-tools TOOLS    Allowed tools string
#   --model MODEL            Model override
#   --ali                    Use Aliyun environment (same as cfa alias)
#   --callback-group ID      Telegram group for callback (dispatching agent's group)
#   --callback-dm ID         Telegram user ID for DM callback
#   --callback-account NAME  Telegram bot account name for DM callback
#
# Environment variables:
#   RESULT_DIR               Where to store results (default: ./data/claude-code-results)
#   OPENCLAW_BIN             Path to openclaw CLI (default: auto-detect)
#   OPENCLAW_GATEWAY_TOKEN   Gateway auth token
#   OPENCLAW_GATEWAY         Gateway URL (default: http://127.0.0.1:18789)
#   OPENCLAW_GATEWAY_PORT    Gateway port for webhook (default: 18789)

set -euo pipefail

# ---- Configuration (override via env vars) ----
RESULT_DIR="${RESULT_DIR:-$(pwd)/data/claude-code-results}"

# Auto-detect openclaw binary
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw 2>/dev/null || echo "")}"

# Auto-detect claude binary
CLAUDE_BIN="${CLAUDE_CODE_BIN:-}"
if [ -z "$CLAUDE_BIN" ]; then
    # Try to find claude binary (skip shell function)
    for loc in "$HOME/.local/bin/claude" "/opt/homebrew/bin/claude" "/usr/local/bin/claude"; do
        if [ -f "$loc" ]; then
            CLAUDE_BIN="$loc"
            break
        fi
    done
fi
if [ -z "$CLAUDE_BIN" ]; then
    CLAUDE_BIN="claude"
fi

# Defaults
PROMPT=""
TASK_NAME="adhoc-$(date +%s)"
TASK_ID=""
TELEGRAM_GROUP=""
CALLBACK_GROUP=""
CALLBACK_DM=""
CALLBACK_ACCOUNT=""
CALLBACK_SESSION="${OPENCLAW_SESSION_KEY:-}"
WORKDIR="$(pwd)"
AGENT_TEAMS=""
TEAMMATE_MODE=""
PERMISSION_MODE=""
ALLOWED_TOOLS=""
MODEL=""
ALI_ENV=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--prompt) PROMPT="$2"; shift 2;;
        -n|--name) TASK_NAME="$2"; shift 2;;
        -g|--group) TELEGRAM_GROUP="$2"; shift 2;;
        -s|--session) CALLBACK_SESSION="$2"; shift 2;;
        --callback-group) CALLBACK_GROUP="$2"; shift 2;;
        --callback-dm) CALLBACK_DM="$2"; shift 2;;
        --callback-account) CALLBACK_ACCOUNT="$2"; shift 2;;
        -w|--workdir) WORKDIR="$2"; shift 2;;
        --agent-teams) AGENT_TEAMS="1"; shift;;
        --teammate-mode) TEAMMATE_MODE="$2"; shift 2;;
        --permission-mode) PERMISSION_MODE="$2"; shift 2;;
        --allowed-tools) ALLOWED_TOOLS="$2"; shift 2;;
        --model) MODEL="$2"; shift 2;;
        --ali) ALI_ENV="1"; shift;;
        *) echo "Unknown option: $1" >&2; exit 1;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "Error: --prompt is required" >&2
    exit 1
fi

# Generate unique task ID
TASK_ID="${TASK_NAME}-$(date +%s)"

# ---- Task-specific result directory (multi-session support) ----
# Each task gets its own directory to avoid conflicts
TASK_RESULT_DIR="${RESULT_DIR}/${TASK_ID}"
META_FILE="${TASK_RESULT_DIR}/task-meta.json"
TASK_OUTPUT="${TASK_RESULT_DIR}/task-output.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="${SCRIPT_DIR}/claude_code_run.py"

mkdir -p "$TASK_RESULT_DIR"

# ---- Auto-setup workspace trust for Claude Code ----
# This allows Claude Code to access the workdir without interactive prompts
WORKDIR_CLAUDE="${WORKDIR}/.claude"
if [ ! -d "$WORKDIR_CLAUDE" ]; then
    mkdir -p "$WORKDIR_CLAUDE"
    cat > "$WORKDIR_CLAUDE/settings.local.json" << 'TRUSTEOF'
{
  "workspaceTrust": {
    "enabled": false
  }
}
TRUSTEOF
    echo "🔓 Workspace trust configured for: $WORKDIR"
fi

# ---- Auto-detect callback from workspace config ----
if [ -z "$CALLBACK_GROUP" ] && [ -z "$CALLBACK_DM" ]; then
    for SEARCH_DIR in "$(pwd)" "$WORKDIR" "${OPENCLAW_AGENT_DIR:-}"; do
        CALLBACK_CONFIG="${SEARCH_DIR}/dispatch-callback.json"
        if [ -f "$CALLBACK_CONFIG" ] 2>/dev/null; then
            CB_TYPE=$(jq -r '.type // ""' "$CALLBACK_CONFIG" 2>/dev/null || echo "")
            case "$CB_TYPE" in
                group)
                    CALLBACK_GROUP=$(jq -r '.group // ""' "$CALLBACK_CONFIG" 2>/dev/null || echo "")
                    [ -n "$CALLBACK_GROUP" ] && echo "📡 Auto-detected callback: group $CALLBACK_GROUP"
                    ;;
                dm)
                    CALLBACK_DM=$(jq -r '.dm // ""' "$CALLBACK_CONFIG" 2>/dev/null || echo "")
                    CALLBACK_ACCOUNT=$(jq -r '.account // ""' "$CALLBACK_CONFIG" 2>/dev/null || echo "")
                    [ -n "$CALLBACK_DM" ] && echo "📡 Auto-detected callback: DM $CALLBACK_DM via ${CALLBACK_ACCOUNT:-default}"
                    ;;
            esac
            break
        fi
    done
fi

# ---- 1. Write task metadata ----
mkdir -p "$RESULT_DIR"

jq -n \
    --arg name "$TASK_NAME" \
    --arg group "$TELEGRAM_GROUP" \
    --arg callback_group "$CALLBACK_GROUP" \
    --arg callback_dm "$CALLBACK_DM" \
    --arg callback_account "$CALLBACK_ACCOUNT" \
    --arg session "$CALLBACK_SESSION" \
    --arg prompt "$PROMPT" \
    --arg workdir "$WORKDIR" \
    --arg ts "$(date -Iseconds)" \
    --arg agent_teams "${AGENT_TEAMS:-0}" \
    '{task_name: $name, telegram_group: $group, callback_group: $callback_group, callback_dm: $callback_dm, callback_account: $callback_account, callback_session: $session, prompt: $prompt, workdir: $workdir, started_at: $ts, agent_teams: ($agent_teams == "1"), status: "running"}' \
    > "$META_FILE"

echo "📋 Task metadata written: $META_FILE"
echo "   Task: $TASK_NAME"
echo "   Group: ${TELEGRAM_GROUP:-none}"
echo "   Agent Teams: ${AGENT_TEAMS:-no}"

# ---- 2. Clear previous output ----
> "$TASK_OUTPUT"

# ---- 3. Build runner command ----
if [ -n "$AGENT_TEAMS" ]; then
    PROMPT="${PROMPT}

## Agent Teams Requirements (mandatory)
1. You are the Lead Agent. Split the task into parallel sub-agents.
2. Assign a dedicated Testing Agent:
   - Write unit tests for each module
   - Run all tests and ensure they pass
   - Check edge cases and error handling
   - Notify the dev agent if tests fail
3. Dev agents and Testing Agent work in parallel.
4. All tests must pass before the task is considered done.
5. Final output: feature list + test result summary"
fi

# Add Aliyun system prompt if --ali is set (same as cfa alias)
if [ -n "$ALI_ENV" ]; then
    PROMPT="${PROMPT}

## Environment: Aliyun Qwen3.5 Plus
- You are running on Aliyun cloud infrastructure using Qwen3.5 Plus model
- The ANTHROPIC_BASE_URL is set to dashscope.aliyuncs.com
- Leverage Aliyun services when appropriate (OSS, RDS, FC, etc.)
- Follow Aliyun best practices for security and performance"
fi

CMD=(python3 "$RUNNER" -p "$PROMPT" --cwd "$WORKDIR")

[ -n "$AGENT_TEAMS" ] && CMD+=(--agent-teams)
[ -n "$TEAMMATE_MODE" ] && CMD+=(--teammate-mode "$TEAMMATE_MODE")
[ -n "$PERMISSION_MODE" ] && CMD+=(--permission-mode "$PERMISSION_MODE")
[ -n "$ALLOWED_TOOLS" ] && CMD+=(--allowedTools "$ALLOWED_TOOLS")

# ---- 4. Set environment ----
if [ -n "$MODEL" ]; then
    export ANTHROPIC_MODEL="$MODEL"
fi

# Export CLAUDE_BIN for claude_code_run.py
if [ -n "$CLAUDE_BIN" ] && [ -f "$CLAUDE_BIN" ]; then
    export CLAUDE_CODE_BIN="$CLAUDE_BIN"
fi

# Set Aliyun environment if --ali is set (same as cfa alias)
if [ -n "$ALI_ENV" ]; then
    export ANTHROPIC_BASE_URL="https://coding.dashscope.aliyuncs.com/apps/anthropic"
    export ANTHROPIC_MODEL="qwen3.5-plus"
    export ANTHROPIC_SMALL_FAST_MODEL="qwen3.5-plus"
    export ANTHROPIC_API_KEY="sk-sp-dbc3eedc26184fb1b6bae82509addbd0"
    echo "☁️  Aliyun environment configured (Qwen3.5 Plus)"
fi

# Unset CLAUDECODE to allow running from within Claude Code
# This is required for dispatching tasks from within a Claude Code session
export CLAUDECODE=""

# ---- 5. Run Claude Code ----
echo "🚀 Launching Claude Code..."
echo "   Command: ${CMD[*]}"
echo ""

"${CMD[@]}" 2>&1 | tee "$TASK_OUTPUT"
EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "✅ Claude Code exited with code: $EXIT_CODE"
echo "   Results: ${RESULT_DIR}/latest.json"

# Update meta with completion
if [ -f "$META_FILE" ]; then
    jq --arg code "$EXIT_CODE" --arg ts "$(date -Iseconds)" \
        '. + {exit_code: ($code | tonumber), completed_at: $ts, status: "done"}' \
        "$META_FILE" > "${META_FILE}.tmp" && mv "${META_FILE}.tmp" "$META_FILE"
fi

# ---- 6. Trigger notification hook ----
# Since Claude Code runs in headless mode, it won't trigger ~/.claude/settings.json hooks
# We need to manually call the notify-hook.sh script
HOOK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/notify-hook.sh"
if [ -f "$HOOK_SCRIPT" ]; then
    echo "📢 Sending notification..."
    # Simulate Claude Code Stop hook event
    echo "{\"session_id\": \"${TASK_ID}\", \"cwd\": \"$(pwd)\", \"hook_event_name\": \"Stop\"}" | bash "$HOOK_SCRIPT"
fi

exit $EXIT_CODE
