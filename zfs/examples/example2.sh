#!/bin/sh

# Checks zpool status by seeing if the output of zpool status changes
# from the stored "normal" expected output.
# by Zorin

# Dirt simple but effective!

# Initial version - 30-Aug-2011
# Modified for linux - 19-Mar-2013

/sbin/zpool status |grep -v scan | grep -v repaired > /tmp/zpool-status.txt

diff /opt/zfs/normal-zpool-status-output.txt /tmp/zpool-status.txt > /tmp/zpool-diff.txt

test -s /tmp/zpool-diff.txt && (
echo "Possible zpool error on `hostname` -- 'zpool status' output differs"
echo "from baseline. Differences:"
echo " "
cat /tmp/zpool-diff.txt
echo " "
echo "zpool status output:"
echo " "
cat /tmp/zpool-status.txt
) | /bin/mail -r "email@address.org" -s "zpool status anomaly on `hostname` `date`" email@address.org

rm -f /tmp/zpool-status.txt /tmp/zpool-diff.txt
