#!/bin/bash

LOG=/home/diego/scripts/smart/logs/smart-alerts.log

# Warn if ZFS scrub is running concurrently
if zpool status | grep -q "scrub in progress"; then
    echo "------------------------------------------------------------" >> $LOG
    echo "Date:    $(date '+%Y-%m-%d %H:%M:%S')"                        >> $LOG
    echo "WARNING: SMART alert fired while ZFS scrub is in progress"    >> $LOG
    echo "Device:  $SMARTD_DEVICE ($SMARTD_DEVICESTRING)"               >> $LOG
fi

echo "------------------------------------------------------------" >> $LOG
echo "Date:    $(date '+%Y-%m-%d %H:%M:%S')"                        >> $LOG
echo "Host:    $SMARTD_HOSTNAME"                                    >> $LOG
echo "Device:  $SMARTD_DEVICE ($SMARTD_DEVICESTRING)"               >> $LOG
echo "Type:    $SMARTD_FAILTYPE"                                    >> $LOG
echo "Message: $SMARTD_MESSAGE"                                     >> $LOG
