#!/bin/sh
# Asus HND Temperature Logging Script
log_interval=4   # interval in mins to log avg temp to router log 0-59m or 0-23h or 0-364
log_interval_unit=h   # lowercase m (minutes) or h (hours) or d (days) are valid
poll_freq=5   # polling frequency of cpu temp in seconds (min 2)
# ##################################################################################################################
script_name="$(basename "$0")"   # script name should be tempmon.sh but anything will work
script_ver='1.00'
trap '' SIGHUP
temp_log='/tmp/temps.tmp'   # log to record temps used to calc avg
ath_log='/tmp/temps_ath.tmp'   # alltimehigh log
atl_log='/tmp/temps_atl.tmp'   # alltimelow log
[ "$log_interval_unit" = 'm' ] && log_time=$((log_interval * 60 / poll_freq))   # log interval time converted to log entry count
[ "$log_interval_unit" = 'h' ] && log_time=$((log_interval * 3600 / poll_freq))
[ "$log_interval_unit" = 'd' ] && log_time=$((log_interval * 86400 / poll_freq))
[ ! -x /jffs/scripts/"$script_name" ] && chmod a+rx /jffs/scripts/"$script_name"
[ ! -f $ath_log ] && touch $ath_log
[ ! -f $atl_log ] && touch $atl_log
[ ! -f $temp_log ] && touch $temp_log
F_log_print() { logger -t "tempmon[$$]" "$1" ;}
F_totallinecount() { wc -l < $temp_log ;}  # function to be able to refresh counts
F_cputemp() { cut -c -3 < /sys/class/thermal/thermal_zone0/temp ;}   # function to check current CPU temp
monitor_pid=$(ps | grep -v 'grep' | grep "$script_name monitor" | awk '{print $1}')
# ##################################################################################################################
if [ "$log_interval_unit" = 'm' ] ; then   # add/check cron/cru entries for logging, delete potential old entires
	if ! cru l | grep -q "\*/$log_interval \* \* \* \* /jffs/scripts/$script_name" ; then
		cru d tempmon
		cru a tempmon "*/$log_interval * * * * /jffs/scripts/$script_name logging"
	fi
elif [ "$log_interval_unit" = 'h' ] ; then
	if ! cru l | grep -q "59 \*/$log_interval \* \* \* /jffs/scripts/$script_name" ; then
		cru d tempmon
		cru a tempmon "59 */$log_interval * * * /jffs/scripts/$script_name logging"
	fi
elif [ "$log_interval_unit" = 'd' ] ; then
	if ! cru l | grep -q "59 11 \*/$log_interval \* \* /jffs/scripts/$script_name" ; then
		cru d tempmon
		cru a tempmon "59 11 */$log_interval * * /jffs/scripts/$script_name logging"
	fi
fi
# ##################################################################################################################
# first manual run, create monitor background task, cron runs will restart monitor if it died
F_load_tempmon() {
	printf "Initializing... \n"
	[ -f "$temp_log" ] && rm $temp_log   # remove old logs if starting new monitor
	started() {
		echo "Started $script_name w/ PID $background_pid Current CPUtemp:$(F_cputemp | sed 's/../&./')C Log Interval:${log_interval}${log_interval_unit} PollFreq:${poll_freq}s"
	}
	(sh /jffs/scripts/"$script_name" monitor) & background_pid=$!   # call script as monitor in background
	F_log_print "$(started)"
	printf "%s \n" "$(started)"
	exit 0   # exit dont continue to logging if called by cron and found no monitor running
} ### load_tempmon
# ###################################################################################################################
F_log_temp() {   # for logging avg/high/low cpu temp
	[ ! -s $temp_log ] && F_log_print "Critical error, nothing in log file to calculate" && exit 0
	alltimehigh=$(head -n1 < $ath_log)
	alltimelow=$(head -n1 < $atl_log)   # read alltime high/low
	cpulowunf=$(sort < $temp_log | head -n1)
	cpuhighunf=$(sort < $temp_log | tail -n1)   # unformatted low/high
	cpuhigh=$(sort < $temp_log | tail -n1 | sed 's/../&./' | sed 's/$/&C/')   # formatted cpuhigh
	cpulow=$(sort < $temp_log | head -n1 | sed 's/../&./' | sed 's/$/&C/')
	if [ "$alltimehigh" = '' ] || [ $cpuhighunf -gt $alltimehigh ] ; then   # if alltimehigh is empty or temp log has higher, record new high
		rm $ath_log 2> /dev/null ;echo "$cpuhighunf" > $ath_log ;alltimehigh=$cpuhighunf
	fi
	if [ "$alltimelow" = '' ] || [ $cpulowunf -lt $alltimelow ] ; then
		rm $atl_log 2> /dev/null ;echo "$cpulowunf" > $atl_log ;alltimelow=$cpulowunf
	fi
	# calc total of temps in log
	totaltempcpu=0
	sleep $poll_freq   # dont miss last temp check
	count_calc=$(F_totallinecount)   # get updated count of logged temps
	while read -r readtemp ; do
		totaltempcpu=$((totaltempcpu + readtemp)) # read temps log and add together the readings
	done < $temp_log
	calcavg=$((totaltempcpu / count_calc)) ;cpuavg=$(echo "$calcavg" | sed 's/../&./' | sed 's/$/&C/')   # cpu avg temp calc'd and formatted
	# re-save below vars for formatting
	alltimehigh=$(echo "$alltimehigh" | sed 's/../&./' | sed 's/$/&C/') ;alltimelow=$(echo "$alltimelow" | sed 's/../&./' | sed 's/$/&C/')

	# send logged info to router log
	F_log_print "CPUnow: $(F_cputemp | sed 's/../&./')C CPUavg: ${cpuavg} CPUhigh: ${cpuhigh} CPUlow: ${cpulow} Uptime CPUhigh: ${alltimehigh} Uptime CPUlow: ${alltimelow}"
	F_log_print "LogPeriod: ${log_interval}${log_interval_unit} PollFreq: ${poll_freq}s Rec: ${count_calc}/${log_time} Current Monitor PID: ${monitor_pid}"

	# clear temps log and start over again
	rm $temp_log ;touch $temp_log ;return 0
} ### log_temp
# ####################################################################################################################
if [ -z "$monitor_pid"  ] ; then   # monitor running check
	F_load_tempmon
else
	[ "$1" = '' ] && printf "tempmon appears to be already monitoring with PID %s \n" "$monitor_pid"   # only terminal print if manually run
fi

if [ "$1" = 'logging' ] ; then F_log_temp   # logging call
elif [ "$1" = 'monitor' ] ; then  # called as background monitor
	while true
	do
		sleep $poll_freq   # polling frequency of temp in seconds, sleep first to keep received/expected more accurate at short logging times
		echo "$(F_cputemp)" >> $temp_log   # write current temp to log
	done   # write temp sleep, repeat
fi
exit 0
