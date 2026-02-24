#!/bin/bash
# notify-hook.sh — Claude Code Stop/SessionEnd hook for auto-notification
#
# Install: Copy to ~/.claude/hooks/ and configure in ~/.claude/settings.json
#
# This script:
#   1. Reads task metadata from RESULT_DIR/task-meta.json
#   2. Collects Claude Code output from task-output.txt
#   3. Sends rich Telegram notifications via OpenClaw CLI
#   4. Sends callback to dispatching agent (group or DM)
#   5. Wakes AGI main session via /hooks/wake webhook
#   6. Writes pending-wake.json as heartbeat fallback
#
# Environment variables:
#   RESULT_DIR               Where results are stored (default: ./data/claude-code-results)
#   OPENCLAW_BIN             Path to openclaw CLI (default: auto-detect)
#   OPENCLAW_CONFIG          Path to openclaw config (default: ~/.openclaw/openclaw.json)
#   OPENCLAW_GATEWAY_PORT    Gateway port (default: 18789)

set -uo pipefail

RESULT_DIR="${RESULT_DIR:-$(pwd)/data/claude-code-results}"
LOG="${RESULT_DIR}/hook.log"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw 2>/dev/null || echo "")}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

mkdir -p "$RESULT_DIR"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

log "=== Hook fired ==="

# ---- Read stdin (Claude Code hook protocol) ----
INPUT=""
if [ -t 0 ]; then
    log "stdin is tty, skip"
elif [ -e /dev/stdin ]; then
    INPUT=$(timeout 2 cat /dev/stdin 2>/dev/null || true)
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")

log "session=$SESSION_ID cwd=$CWD event=$EVENT"

# ---- Find task directory (support multi-session) ----
# Search for the most recent task-meta.json in subdirectories
TASK_DIR=""
META_FILE=""
TASK_OUTPUT=""

# First try: use CWD if it contains task-meta.json
if [ -n "$CWD" ] && [ -f "${CWD}/data/claude-code-results/task-meta.json" ]; then
    TASK_DIR="${CWD}/data/claude-code-results"
elif [ -d "$CWD" ]; then
    # Search for task-meta.json in CWD's subdirectories
    FOUND_DIR=$(find "$CWD" -maxdepth 3 -name "task-meta.json" -type f 2>/dev/null | head -1 | xargs -I {} dirname {})
    if [ -n "$FOUND_DIR" ]; then
        TASK_DIR="$FOUND_DIR"
    fi
fi

# Fallback: search in default RESULT_DIR
if [ -z "$TASK_DIR" ]; then
    # Find the most recently modified task-meta.json
    FOUND_DIR=$(find "$RESULT_DIR" -maxdepth 2 -name "task-meta.json" -type f 2>/dev/null | xargs -I {} dirname {} | head -1)
    if [ -n "$FOUND_DIR" ]; then
        TASK_DIR="$FOUND_DIR"
    fi
fi

if [ -n "$TASK_DIR" ]; then
    META_FILE="${TASK_DIR}/task-meta.json"
    TASK_OUTPUT="${TASK_DIR}/task-output.txt"
    log "Found task directory: $TASK_DIR"
else
    log "ERROR: Could not find task directory"
    META_FILE=""
    TASK_OUTPUT=""
fi

# ---- Deduplication: Only process first event (Stop), skip SessionEnd ----
# Use task-specific lock file to support multi-session
LOCK_FILE=""
if [ -n "$TASK_DIR" ]; then
    LOCK_FILE="${TASK_DIR}/.hook-lock"
else
    LOCK_FILE="${RESULT_DIR}/.hook-lock-global"
fi
LOCK_AGE_LIMIT=30

if [ -f "$LOCK_FILE" ]; then
    # macOS compatible stat: use -f %m instead of -c %Y
    LOCK_TIME=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$(( NOW - LOCK_TIME ))
    if [ "$AGE" -lt "$LOCK_AGE_LIMIT" ]; then
        log "Duplicate hook within ${AGE}s, skipping"
        exit 0
    fi
fi
touch "$LOCK_FILE"

# ---- Collect output ----
OUTPUT=""
sleep 1  # Wait for tee pipe flush

if [ -f "$TASK_OUTPUT" ] && [ -s "$TASK_OUTPUT" ]; then
    # Read output and strip ANSI escape codes
    OUTPUT=$(cat "$TASK_OUTPUT" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tail -c 4000)
    log "Output from task-output.txt (${#OUTPUT} chars)"
fi

if [ -z "$OUTPUT" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
    FILES=$(ls -1t "$CWD" 2>/dev/null | head -20 | tr '\n' ', ')
    OUTPUT="Working dir: ${CWD}\nFiles: ${FILES}"
    log "Output from dir listing"
fi

# ---- Read task metadata (only if recent) ----
TASK_NAME="unknown"
TELEGRAM_GROUP=""
CALLBACK_GROUP=""
CALLBACK_DM=""
CALLBACK_ACCOUNT=""

if [ -f "$META_FILE" ]; then
    # macOS compatible stat: use -f %m instead of -c %Y
    META_MTIME=$(stat -f %m "$META_FILE" 2>/dev/null || echo 0)
    META_AGE=$(( $(date +%s) - META_MTIME ))
    if [ "$META_AGE" -gt 7200 ]; then
        log "Meta file is ${META_AGE}s old (>2h), ignoring stale meta"
    else
        TASK_NAME=$(jq -r '.task_name // "unknown"' "$META_FILE" 2>/dev/null || echo "unknown")
        TELEGRAM_GROUP=$(jq -r '.telegram_group // ""' "$META_FILE" 2>/dev/null || echo "")
        CALLBACK_GROUP=$(jq -r '.callback_group // ""' "$META_FILE" 2>/dev/null || echo "")
        CALLBACK_DM=$(jq -r '.callback_dm // ""' "$META_FILE" 2>/dev/null || echo "")
        CALLBACK_ACCOUNT=$(jq -r '.callback_account // ""' "$META_FILE" 2>/dev/null || echo "")
        log "Meta: task=$TASK_NAME group=$TELEGRAM_GROUP age=${META_AGE}s"
    fi
fi

# ---- Write result JSON ----
jq -n \
    --arg sid "$SESSION_ID" \
    --arg ts "$(date -Iseconds)" \
    --arg cwd "$CWD" \
    --arg event "$EVENT" \
    --arg output "$OUTPUT" \
    --arg task "$TASK_NAME" \
    --arg group "$TELEGRAM_GROUP" \
    '{session_id: $sid, timestamp: $ts, cwd: $cwd, event: $event, output: $output, task_name: $task, telegram_group: $group, status: "done"}' \
    > "${RESULT_DIR}/latest.json" 2>/dev/null

log "Wrote latest.json"

# ---- Send Telegram notification ----
if [ -n "$TELEGRAM_GROUP" ] && [ -n "$OPENCLAW_BIN" ]; then

    PROJECT_DIR=""
    DURATION=""
    AGENT_TEAMS_ENABLED="false"
    EXIT_CODE_VAL="0"

    if [ -f "$META_FILE" ]; then
        PROJECT_DIR=$(jq -r '.workdir // ""' "$META_FILE" 2>/dev/null || echo "")
        AGENT_TEAMS_ENABLED=$(jq -r '.agent_teams // false' "$META_FILE" 2>/dev/null || echo "false")
        EXIT_CODE_VAL=$(jq -r '.exit_code // 0' "$META_FILE" 2>/dev/null || echo "0")

        STARTED=$(jq -r '.started_at // ""' "$META_FILE" 2>/dev/null || echo "")
        COMPLETED=$(jq -r '.completed_at // ""' "$META_FILE" 2>/dev/null || echo "")
        if [ -n "$STARTED" ] && [ -n "$COMPLETED" ]; then
            # macOS compatible: convert ISO date to epoch
            START_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$STARTED" +%s 2>/dev/null || echo 0)
            END_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$COMPLETED" +%s 2>/dev/null || echo 0)
            if [ "$START_TS" -gt 0 ] && [ "$END_TS" -gt 0 ]; then
                ELAPSED=$(( END_TS - START_TS ))
                MINS=$(( ELAPSED / 60 ))
                SECS=$(( ELAPSED % 60 ))
                DURATION="${MINS}m${SECS}s"
            fi
        fi
    fi

    STATUS_EMOJI="✅"
    [ "$EXIT_CODE_VAL" != "0" ] && STATUS_EMOJI="❌"

    MSG="${STATUS_EMOJI} *Claude Code Task Complete*
📋 *Task:* \`${TASK_NAME}\`"
    [ -n "$PROJECT_DIR" ] && MSG="${MSG}
📂 *Path:* \`${PROJECT_DIR}\`"
    [ -n "$DURATION" ] && MSG="${MSG}
⏱ *Duration:* ${DURATION}"
    [ "$EXIT_CODE_VAL" != "0" ] && MSG="${MSG}
⚠️ *Exit Code:* ${EXIT_CODE_VAL}"
    [ "$AGENT_TEAMS_ENABLED" = "true" ] && MSG="${MSG}
👥 *Agent Teams:* enabled"

    # Add output summary (first 500 chars, stripped of ANSI codes)
    if [ -f "$TASK_OUTPUT" ] && [ -s "$TASK_OUTPUT" ]; then
        CLEAN_OUTPUT=$(cat "$TASK_OUTPUT" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | head -c 500 | tr '\n' ' ')
        [ -n "$CLEAN_OUTPUT" ] && MSG="${MSG}

📝 *Output:* ${CLEAN_OUTPUT}"
    fi

    # File listing - only show new/modified files
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        FILE_TREE=$(find "$PROJECT_DIR" -maxdepth 2 -type f -mmin -30 \
            ! -path '*/venv/*' ! -path '*/__pycache__/*' ! -path '*/.git/*' ! -path '*.pyc' \
            ! -path '*/data/claude-code-results/*' \
            2>/dev/null | sort | sed "s|${PROJECT_DIR}/||" | head -10 | while IFS= read -r f; do echo "  📄 $f"; done)
        [ -n "$FILE_TREE" ] && MSG="${MSG}

📁 *Recent Files:*
${FILE_TREE}"
    fi

    "$OPENCLAW_BIN" message send \
        --channel telegram \
        --target "$TELEGRAM_GROUP" \
        --message "$MSG" 2>/dev/null && log "Sent Telegram notification" || log "Telegram send failed"

    # Callback to dispatching agent's group
    if [ -n "$CALLBACK_GROUP" ] && [ "$CALLBACK_GROUP" != "$TELEGRAM_GROUP" ]; then
        CALLBACK_MSG="🔔 *Task Complete*: \`${TASK_NAME}\` ${STATUS_EMOJI}"
        [ -n "$DURATION" ] && CALLBACK_MSG="${CALLBACK_MSG} (${DURATION})"
        SUMMARY=$(echo "$OUTPUT" | head -c 500 | tr '\n' ' ')
        [ -n "$SUMMARY" ] && CALLBACK_MSG="${CALLBACK_MSG}
📝 ${SUMMARY}"

        "$OPENCLAW_BIN" message send \
            --channel telegram --target "$CALLBACK_GROUP" \
            --message "$CALLBACK_MSG" 2>/dev/null && log "Sent callback to $CALLBACK_GROUP" || log "Callback failed"
    fi

    # DM callback
    if [ -n "$CALLBACK_DM" ]; then
        CALLBACK_MSG="🔔 *Task Complete*: \`${TASK_NAME}\` ${STATUS_EMOJI}"
        [ -n "$DURATION" ] && CALLBACK_MSG="${CALLBACK_MSG} (${DURATION})"
        DM_CMD=("$OPENCLAW_BIN" message send --channel telegram --target "$CALLBACK_DM" --message "$CALLBACK_MSG")
        [ -n "$CALLBACK_ACCOUNT" ] && DM_CMD+=(--account "$CALLBACK_ACCOUNT")
        "${DM_CMD[@]}" 2>/dev/null && log "Sent DM to $CALLBACK_DM" || log "DM failed"
    fi
fi

# ---- Write heartbeat fallback ----
jq -n \
    --arg task "$TASK_NAME" \
    --arg group "$TELEGRAM_GROUP" \
    --arg ts "$(date -Iseconds)" \
    --arg summary "$(echo "$OUTPUT" | head -c 500 | tr '\n' ' ')" \
    '{task_name: $task, telegram_group: $group, timestamp: $ts, summary: $summary, processed: false}' \
    > "${RESULT_DIR}/pending-wake.json" 2>/dev/null

# ---- Wake AGI via webhook ----
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
HOOK_TOKEN=""

if [ -f "$OPENCLAW_CONFIG" ]; then
    HOOK_TOKEN=$(jq -r '.hooks.token // ""' "$OPENCLAW_CONFIG" 2>/dev/null || echo "")
fi

WAKE_TEXT="[CLAUDE_CODE_DONE] task=${TASK_NAME} status=done group=${TELEGRAM_GROUP:-none} ts=$(date -Iseconds)"

if [ -n "$HOOK_TOKEN" ]; then
    (
      curl -s -o /dev/null -w "" -X POST \
          "http://localhost:${GATEWAY_PORT}/hooks/wake" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${HOOK_TOKEN}" \
          -d "{\"text\":\"${WAKE_TEXT}\",\"mode\":\"now\"}" 2>/dev/null && \
          log "Wake event sent" || log "Wake failed"
    ) &
fi

log "=== Hook completed ==="
exit 0
