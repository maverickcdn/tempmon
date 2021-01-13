# tempmon.sh
AsusWRT-Merlin HND CPU Temperature Logging RT-AC86U, RT-AX86U, RT-AX88U

Install to /jffs/scripts/ as tempmon.sh (or whatever you prefer)

Script will send to router log average/high/low CPU temperatures for logging session at set logging interval

Set logging interval - edit log_interval (0-59 for minutes, 0-23 for hours, days) default: 1

Set logging interval unit - edit log_interval_unit (m for minutes, h for hours, d for days) default: d

Polling frequency in seconds of CPU temp - edit poll_freq default: 15 (secs) (min 2)

Monitor script does not survive reboots. If you wish, add an entry to /jffs/scripts/services-start and call this script to start a new monitor instance on reboot

All time high and low CPU temperatures do not survive reboots (ie. high/low of uptime)

To install

`curl --retry 3 "https://raw.githubusercontent.com/maverickcdn/tempmon/master/tempmon.sh" -o "/jffs/scripts/tempmon.sh" && chmod a+rx "/jffs/scripts/tempmon.sh"`

Run with 'sh /jffs/scripts/tempmon.sh' to start logging monitor in background, if monitor is running it will list its PID

To manually log currently recorded temps before log interval (cron), 'sh /jffs/scripts/tempmon.sh logging'

Thank you for using this script.
