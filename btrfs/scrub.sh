#!/bin/bash
# =============================================================================
# BTRFS Monthly Scrub + Discord Notifier
# Starts a btrfs scrub, waits for it to finish, and reports both events
# to Discord. Intended to run on the 28th of each month via root crontab.
#
# Crontab entry (sudo crontab -e):
#   0 2 28 * * /opt/btrfs-monitor/btrfs-scrub-notify.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
# Reads from the same .env.btrfsstatus used by btrfs-discord-notify.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env.btrfsstatus"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

WEBHOOK_URL="${MONITOR_WEBHOOK_URL:?MONITOR_WEBHOOK_URL is not set. Define it in ${SCRIPT_DIR}/.env.btrfsstatus}"
DISCORD_USER_ID="${MONITOR_DISCORD_USER_ID:?MONITOR_DISCORD_USER_ID is not set. Define it in ${SCRIPT_DIR}/.env.btrfsstatus}"
BTRFS_MOUNT="${MONITOR_BTRFS_MOUNT:-/mnt/oldhdd}"
BTRFS_DEVICE="${MONITOR_BTRFS_DEVICE:-/dev/sdc}"
# -----------------------------------------------------------------------------

HOSTNAME=$(hostname)

# --- Helper: send a Discord message ------------------------------------------
send_discord() {
    local message="$1"

    if command -v jq &>/dev/null; then
        PAYLOAD=$(jq -n --arg msg "$message" '{"content": $msg}')
    else
        PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'content': sys.argv[1]}))" "$message")
    fi

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$PAYLOAD" \
        "$WEBHOOK_URL")

    if [ "$HTTP_STATUS" != "204" ]; then
        echo "Warning: Discord webhook returned HTTP $HTTP_STATUS" >&2
    fi
}

# --- Verify mount point is accessible ----------------------------------------
if ! btrfs filesystem show "$BTRFS_MOUNT" &>/dev/null; then
    send_discord "<@${DISCORD_USER_ID}> :red_circle: **BTRFS scrub failed to start on \`${HOSTNAME}\`** — $(date '+%Y-%m-%d %H:%M:%S %Z')

\`${BTRFS_MOUNT}\` is not accessible. Scrub aborted."
    exit 1
fi

# --- Notify: scrub starting --------------------------------------------------
START_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

send_discord ":broom: **BTRFS scrub started on \`${HOSTNAME}\`** — ${START_TIME}

Device: \`${BTRFS_DEVICE}\`
Mount:  \`${BTRFS_MOUNT}\`

Scrub is running — you'll get another notification when it finishes."

# --- Start the scrub and wait for it to complete -----------------------------
# -B flag = run in foreground (blocks until done)
btrfs scrub start -B "$BTRFS_MOUNT" &>/dev/null
SCRUB_EXIT=$?

END_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

# --- Get the scrub result status ---------------------------------------------
SCRUB_STATUS=$(btrfs scrub status "$BTRFS_MOUNT" 2>&1)

# Parse key fields from scrub status output
DURATION=$(echo    "$SCRUB_STATUS" | grep -i "duration"      | awk -F: '{print $2}' | xargs)
DATA_SCRUBBED=$(echo "$SCRUB_STATUS" | grep -i "data_scrubbed\|bytes scrubbed" | awk -F: '{print $2}' | xargs)
ERROR_SUMMARY=$(echo "$SCRUB_STATUS" | grep -i "error\|no errors" | head -1 | xargs)

# Truncate full status if very long
if [ ${#SCRUB_STATUS} -gt 800 ]; then
    SCRUB_STATUS="${SCRUB_STATUS:0:800}... (truncated)"
fi

# --- Determine outcome -------------------------------------------------------
# btrfs scrub start -B exits 0 on success, non-zero on errors found
if [ "$SCRUB_EXIT" -eq 0 ]; then
    ICON=":white_check_mark:"
    TITLE="BTRFS scrub finished cleanly on \`${HOSTNAME}\`"
    PREFIX=""
    RESULT_LINE="No errors found."
else
    ICON=":warning:"
    TITLE="BTRFS scrub finished WITH ERRORS on \`${HOSTNAME}\`"
    PREFIX="<@${DISCORD_USER_ID}> "
    RESULT_LINE="Errors were detected — check the status below."
fi

# --- Notify: scrub finished --------------------------------------------------
send_discord "${PREFIX}${ICON} **${TITLE}** — ${END_TIME}

Device: \`${BTRFS_DEVICE}\`
Mount:  \`${BTRFS_MOUNT}\`
Started: ${START_TIME}
Finished: ${END_TIME}

**Result:** ${RESULT_LINE}

**Full scrub status:**\`\`\`
${SCRUB_STATUS}
\`\`\`"
