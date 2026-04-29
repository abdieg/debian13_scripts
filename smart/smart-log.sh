#!/bin/bash

LOG=/home/diego/scripts/smart/logs/smart-alerts.log

echo "------------------------------------------------------------" >> $LOG
echo "Date:    $(date '+%Y-%m-%d %H:%M:%S')"                        >> $LOG
echo "Host:    $SMARTD_HOSTNAME"                                    >> $LOG
echo "Device:  $SMARTD_DEVICE ($SMARTD_DEVICESTRING)"               >> $LOG
echo "Type:    $SMARTD_FAILTYPE"                                    >> $LOG
echo "Message: $SMARTD_MESSAGE"                                     >> $LOG
