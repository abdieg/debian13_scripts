# ZFS zed scrub configuration 

Check if timer exists as unit file:

```bash
systemctl list-unit-files | grep zfs-scrub
```

Something like this will be displayed:

```bash
zfs-scrub@.service                                                            static          -
zfs-scrub-monthly@.timer                                                      disabled        enabled
zfs-scrub-weekly@.timer                                                       disabled        enabled
```

Enable the monthly scrub:

```bash
sudo systemctl enable zfs-scrub-monthly@tank.timer
```

Start the monthly scrub:

```bash
sudo systemctl start zfs-scrub-monthly@tank.timer
```

You should see the next timed scrub execution:

```bash
systemctl list-timers | grep zfs
```
