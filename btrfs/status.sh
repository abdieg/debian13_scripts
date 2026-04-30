#!/bin/bash
# =============================================================================
# BTRFS Filesystem Discord Notifier
# Monitors btrfs device/filesystem health and sends Discord alerts
# =============================================================================

# --- Configuration -----------------------------------------------------------
# Set these in .env.btrfsstatus in the same directory as this script:
#   MONITOR_WEBHOOK_URL="https://discord.com/api/webhooks/..."
#   MONITOR_DISCORD_USER_ID="123456789012345678"
#   MONITOR_BTRFS_DEVICE="/dev/sdc"
#   MONITOR_BTRFS_MOUNT="/mnt/oldhdd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env.btrfsstatus"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

WEBHOOK_URL="${MONITOR_WEBHOOK_URL:?MONITOR_WEBHOOK_URL is not set. Define it in ${SCRIPT_DIR}/.env.btrfsstatus}"
DISCORD_USER_ID="${MONITOR_DISCORD_USER_ID:?MONITOR_DISCORD_USER_ID is not set. Define it in ${SCRIPT_DIR}/.env.btrfsstatus}"

# The block device (used for stats)
BTRFS_DEVICE="${MONITOR_BTRFS_DEVICE:-/dev/sdc}"

# The mount point (used for device stats)
BTRFS_MOUNT="${MONITOR_BTRFS_MOUNT:-/mnt/oldhdd}"

TMP_STATS="${SCRIPT_DIR}/btrfs-stats-current.txt"

# Set to 1 to always send a Discord message on every run (healthy or not)
# Set to 0 to only notify when something is wrong
# When healthy: no ping. When something is wrong: user is always pinged.
NOTIFY_ALWAYS=1
# -----------------------------------------------------------------------------

# --- Verify the device/mount exists ------------------------------------------
if ! lsblk "$BTRFS_DEVICE" &>/dev/null; then
    # Device missing entirely — this is itself an alert
    MISSING_DEVICE_MSG="Device \`${BTRFS_DEVICE}\` not found on \`$(hostname)\`."

    if command -v jq &>/dev/null; then
        PAYLOAD=$(jq -n --arg msg "<@${DISCORD_USER_ID}> :red_circle: **BTRFS alert on \`$(hostname)\`** — $(date '+%Y-%m-%d %H:%M:%S %Z') - ${MISSING_DEVICE_MSG}" '{"content": $msg}')
    else
        PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'content': sys.argv[1]}))" \
            "<@${DISCORD_USER_ID}> :red_circle: **BTRFS alert on \`$(hostname)\`** — $(date '+%Y-%m-%d %H:%M:%S %Z') - ${MISSING_DEVICE_MSG}")
    fi

    curl -s -o /dev/null \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$PAYLOAD" \
        "$WEBHOOK_URL"
    exit 1
fi

# --- Capture btrfs device stats (error counters) -----------------------------
# btrfs device stats prints per-device counters for:
#   read/write/flush errors, corruption errors, generation errors
btrfs device stats "$BTRFS_MOUNT" > "$TMP_STATS" 2>&1
STATS_EXIT=$?

# --- Parse error counters ----------------------------------------------------
# Any non-zero counter is a problem
ERRORS_FOUND=""
while IFS= read -r line; do
    # Lines look like: [/dev/sdc].write_io_errs    0
    count=$(echo "$line" | awk '{print $NF}')
    if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]; then
        ERRORS_FOUND="${ERRORS_FOUND}${line}"
    fi
done < "$TMP_STATS"

# Also flag if btrfs command itself failed (e.g. filesystem not mounted)
if [ "$STATS_EXIT" -ne 0 ]; then
    ERRORS_FOUND="${ERRORS_FOUND}btrfs device stats command failed (exit ${STATS_EXIT}) — filesystem may not be mounted"
fi

# --- Determine health --------------------------------------------------------
ALL_HEALTHY=$([ -z "$ERRORS_FOUND" ] && echo 1 || echo 0)

# Skip entirely if nothing is wrong and NOTIFY_ALWAYS is off
if [ "$ALL_HEALTHY" = "1" ] && [ "$NOTIFY_ALWAYS" = "0" ]; then
    rm -f "$TMP_STATS"
    exit 0
fi

# --- Build the Discord message -----------------------------------------------
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Show full stats block (it's compact — typically 5 lines)
STATS_CONTENT=$(cat "$TMP_STATS")
if [ ${#STATS_CONTENT} -gt 800 ]; then
    STATS_CONTENT="${STATS_CONTENT:0:800}... (truncated)"
fi

if [ "$ALL_HEALTHY" = "1" ]; then
    ICON=":white_check_mark:"
    TITLE="BTRFS check-in on \`${HOSTNAME}\`"
    PREFIX=""
    ALERT_BODY="Device \`${BTRFS_DEVICE}\` is healthy — all error counters are zero."
else
    ICON=":warning:"
    TITLE="BTRFS alert on \`${HOSTNAME}\`"
    PREFIX="<@${DISCORD_USER_ID}> "
    ALERT_BODY="**Errors detected on \`${BTRFS_DEVICE}\`:**\`\`\`${ERRORS_FOUND}\`\`\`"
fi

ALERT_BODY="${ALERT_BODY}** Device stats (\`${BTRFS_DEVICE}\`):**\`\`\`${STATS_CONTENT}\`\`\`"

MESSAGE="${PREFIX}${ICON} **${TITLE}** — ${TIMESTAMP} - ${ALERT_BODY}"

# --- Send to Discord ---------------------------------------------------------
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
rm -f "$TMP_STATS"
