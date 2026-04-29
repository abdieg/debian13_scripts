#!/bin/bash

CURRENT_MINUTE=$(date +%M)
CURRENT_TIME=$(date +%H:%M)
STATUS="GOOD"

function check_zfs {
        local LOCAL_STATUS=$(/sbin/zpool status | sed '/.*[Ss]tate.*: */!d; s///; s/^[[:space:]]*//; s/[[:space:]]*$//;')
        if [ "$LOCAL_STATUS" == "ONLINE" ]
        then
                return 0
        else
                STATUS="ZPOOL ERROR"
                return 1
        fi
}

function check_md0 {
        local LOCAL_STATUS=$(/sbin/mdadm --detail /dev/md0 | sed '/.*[Ss]tate.*: */!d; s///; s/^[[:space:]]*//; s/[[:space:]]*$//;')
        if [ "$LOCAL_STATUS" == "clean" ] || [ "$LOCAL_STATUS" == "active" ]
        then
                return 0
        else
                #echo -n "$LOCAL_STATUS" | xxd
                STATUS="MD0 ERROR"
                return 1
        fi
}

function check_boot_array_writable {
        echo "WRITABLE" > /tmp/delete_test
        local LOCAL_STATUS=$(cat /tmp/delete_test | sed 's/^[[:space:]]*//; s/[[:space:]]*$//;')
        rm /tmp/delete_test
        if [ "$LOCAL_STATUS" == "WRITABLE" ]
        then
                return 0
        else
                STATUS="BOOT ARRAY WRITABLE ERROR"
                return 1
        fi
}

function check_bonds {
        local LOCAL_STATUS=$(cat /proc/net/bonding/bond0 /proc/net/bonding/bond1 | grep "MII Status: up" | wc -l)
        if [ "$LOCAL_STATUS" -eq 6 ]
        then
                return 0
        else
                STATUS="BOND ERROR"
                return 1
        fi
}

function mail_status {
        /usr/bin/mail -aFrom:zfs-server@mydomain.com -s "$STATUS" notify <<< "$({ \

        (echo "#####"); \
        (echo "############################# Boot Disk Mirror Status ########################"); \
        (/sbin/mdadm --detail /dev/md0); \
        (echo); \
        (echo); \
        (echo "############################# Boot Disk Writable Status ########################"); \
        (echo); \
        (echo "Boot array is writable." > /tmp/delete_test); \
        (cat /tmp/delete_test); \
        (rm /tmp/delete_test); \
        (echo); \
        (echo); \
        (echo "############################# ZFS Pool Status ########################"); \
        (/sbin/zpool status); \
        (echo); \
        (echo); \
        (echo "############################# ZFS List ########################"); \
        (/sbin/zfs list); \
        (echo); \
        (echo); \
        (echo "############################# Bond Status ########################"); \
        (echo); \
        (cat /proc/net/bonding/bond0);\
        (cat /proc/net/bonding/bond1);\
        } 2>&1)"
}

check_zfs
check_md0
check_boot_array_writable
check_bonds

#if [[ "$CURRENT_TIME" == "02:00" ]] || [[ "$CURRENT_TIME" == "08:00" ]] || [[ "$CURRENT_TIME" == "16:00" ]] || [[ "$STATUS" != "GOOD" ]]; then
if [[ "$CURRENT_MINUTE" == "00" ]] || [[ "$STATUS" != "GOOD" ]]; then
        mail_status
fi
