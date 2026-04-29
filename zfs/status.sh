#!/bin/bash
# =============================================================================
# ZFS Pool Discord Notifier
# Monitors zpool status against a baseline and sends Discord alerts with diffs
# =============================================================================

# --- Configuration -----------------------------------------------------------
# Set these in .env.zfsstatus in the same directory as this script:
#   MONITOR_WEBHOOK_URL="https://discord.com/api/webhooks/..."
#   MONITOR_DISCORD_USER_ID="123456789012345678"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env.zfsstatus"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

WEBHOOK_URL="${MONITOR_WEBHOOK_URL:?MONITOR_WEBHOOK_URL is not set. Define it in ${SCRIPT_DIR}/.env.zfsstatus}"
DISCORD_USER_ID="${MONITOR_DISCORD_USER_ID:?MONITOR_DISCORD_USER_ID is not set. Define it in ${SCRIPT_DIR}/.env.zfsstatus}"

BASELINE_FILE="${SCRIPT_DIR}/baseline-zpool-status.txt"
TMP_STATUS="${SCRIPT_DIR}/zpool-status-current.txt"
TMP_DIFF="${SCRIPT_DIR}/zpool-status-diff.txt"

# Set to 1 to alert whenever any pool is not ONLINE (recommended)
ALERT_ON_UNHEALTHY=1

# Set to 1 to always send a Discord message on every run (healthy or not)
# Set to 0 to only notify when something is wrong
# When healthy: no ping. When something is wrong: user is always pinged.
NOTIFY_ALWAYS=1
# -----------------------------------------------------------------------------

# Capture current zpool status, stripping lines that change every run
/sbin/zpool status \
    | grep -v "^\s*scan:" \
    | grep -v "repaired" \
    | grep -v "^\s*scrub" \
    > "$TMP_STATUS"

# --- First run: create baseline and exit -------------------------------------
if [ ! -f "$BASELINE_FILE" ]; then
    cp "$TMP_STATUS" "$BASELINE_FILE"
    echo "Baseline created at $BASELINE_FILE — run this script again to start monitoring."
    exit 0
fi

# --- Check for diffs against baseline ----------------------------------------
diff "$BASELINE_FILE" "$TMP_STATUS" > "$TMP_DIFF"
DIFF_FOUND=$(test -s "$TMP_DIFF" && echo 1 || echo 0)

# --- Check for unhealthy pool state ------------------------------------------
UNHEALTHY_POOLS=""
if [ "$ALERT_ON_UNHEALTHY" = "1" ]; then
    UNHEALTHY_POOLS=$(zpool list -H -o name,health | awk '$2 != "ONLINE" {print $1 " -> " $2}')
fi

# --- Determine whether anything is wrong -------------------------------------
ALL_HEALTHY=$([ "$DIFF_FOUND" = "0" ] && [ -z "$UNHEALTHY_POOLS" ] && echo 1 || echo 0)

# Skip entirely if nothing is wrong and NOTIFY_ALWAYS is off
if [ "$ALL_HEALTHY" = "1" ] && [ "$NOTIFY_ALWAYS" = "0" ]; then
    rm -f "$TMP_STATUS" "$TMP_DIFF"
    exit 0
fi

# --- Build the Discord message -----------------------------------------------
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
ALERT_BODY=""

if [ "$ALL_HEALTHY" = "1" ]; then
    # Healthy: no ping, just a quiet check-in
    ICON=":white_check_mark:"
    TITLE="ZFS check-in on \`${HOSTNAME}\`"
    PREFIX=""
    ALERT_BODY="All pools are **ONLINE** and status matches baseline."
else
    # Something wrong: ping the user
    ICON=":warning:"
    TITLE="ZFS alert on \`${HOSTNAME}\`"
    PREFIX="<@${DISCORD_USER_ID}> "

    if [ -n "$UNHEALTHY_POOLS" ]; then
        ALERT_BODY="${ALERT_BODY}**Unhealthy pools:**\`\`\`${UNHEALTHY_POOLS}\`\`\`\n"
    fi

    if [ "$DIFF_FOUND" = "1" ]; then
        DIFF_CONTENT=$(cat "$TMP_DIFF")
        if [ ${#DIFF_CONTENT} -gt 1200 ]; then
            DIFF_CONTENT="${DIFF_CONTENT:0:1500}... (truncated)"
        fi
        ALERT_BODY="${ALERT_BODY}**Diff from baseline:**\`\`\`diff ${DIFF_CONTENT}\`\`\`\n"
    fi
fi

STATUS_CONTENT=$(cat "$TMP_STATUS")
if [ ${#STATUS_CONTENT} -gt 600 ]; then
    STATUS_CONTENT="${STATUS_CONTENT:0:600}... (truncated)"
fi
ALERT_BODY="${ALERT_BODY} **Current zpool status:**\`\`\`${STATUS_CONTENT}\`\`\`"

MESSAGE="${PREFIX}${ICON} **${TITLE}** - ${TIMESTAMP} - ${ALERT_BODY}"

# --- Send to Discord ---------------------------------------------------------
# Use jq if available, otherwise fall back to python3 for safe JSON escaping
if command -v jq &>/dev/null; then
    PAYLOAD=$(jq -n --arg msg "$MESSAGE" '{"content": $msg}')
else
    PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'content': sys.argv[1]}))" "$MESSAGE")
fi

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$PAYLOAD" \
    "$WEBHOOK_URL")

if [ "$HTTP_STATUS" != "204" ]; then
    echo "Warning: Discord webhook returned HTTP $HTTP_STATUS" >&2
fi

# --- Cleanup -----------------------------------------------------------------
rm -f "$TMP_STATUS" "$TMP_DIFF"
