# zfs/status.sh
Monitors the health of your ZFS pools and sends notifications to a Discord channel. On each run, it captures the output of `zpool status`, compares it against a stored baseline, and checks whether all pools are in an `ONLINE` state.
If something looks wrong — a pool degraded, a diff from the baseline, or any unexpected state change — it sends a Discord message that pings you directly. If everything is healthy and `NOTIFY_ALWAYS` is enabled, it still sends a quiet check-in message without pinging anyone.

How it works:

- On the first run it creates a baseline snapshot of your pool status. Subsequent runs diff against that baseline to detect changes.
- Lines that change on every run (scan progress, scrub timestamps) are stripped before diffing to avoid false positives.
- Credentials are kept out of the script itself and loaded from a `.env.zfsstatus` file sitting next to the script.
- Designed to run unattended via cron.

Configuration (`MONITOR_WEBHOOK_URL`, `MONITOR_DISCORD_USER_ID`) is set in `.env.zfsstatus`. Two flags control behavior: `ALERT_ON_UNHEALTHY` to catch pools that aren't `ONLINE`, and `NOTIFY_ALWAYS` to control whether healthy runs also send a message.

Use `crontab -e` to add a register for the user and `crontab -l` to validate.

```bash
# Example:
0 8 * * * /path to file/zfs/status.sh
```
