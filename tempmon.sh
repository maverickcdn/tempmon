#!/bin/sh
# Asus HND Temperature Logging Script
log_interval=4   # interval in mins to log avg temp to router log 0-59m or 0-23h or 0-364
log_interval_unit=h   # lowercase m (minutes) or h (hours) or d (days) are valid
poll_freq=5   # polling frequency of cpu temp in seconds (min 2)
max_avg=5000	# max num of averages to save to ram		v1.01
# ##################################################################################################################
script_name="$(basename "$0")"   # script name should be tempmon.sh but anything will work
script_ver='1.01'
trap '' SIGHUP
temp_log='/tmp/temps.tmp'   # log to record temps used to calc avg
ath_log='/tmp/temps_ath.tmp'   # alltimehigh log
atl_log='/tmp/temps_atl.tmp'   # alltimelow log
temp_start_log='/tmp/temps_start.tmp'   # epoch start of monitor log for calc monitor uptime	# v1.01
temp_avg_log='/tmp/temps_avg.tmp'   # avg of averages log   # v1.01
[ -f $temp_start_log ] && started_epoch=$(cat $temp_start_log)	# print out start epoch from temp file			# v1.01
[ "$log_interval_unit" = 'm' ] && log_time=$((log_interval * 60 / poll_freq))   # log interval time converted to log entry count
[ "$log_interval_unit" = 'h' ] && log_time=$((log_interval * 3600 / poll_freq))
[ "$log_interval_unit" = 'd' ] && log_time=$((log_interval * 86400 / poll_freq))
[ ! -x /jffs/scripts/"$script_name" ] && chmod a+rx /jffs/scripts/"$script_name"
[ ! -f $ath_log ] && touch $ath_log
[ ! -f $atl_log ] && touch $atl_log
[ ! -f $temp_log ] && touch $temp_log
[ ! -f $temp_avg_log ] && touch $temp_avg_log			# v1.01
F_log_print() { logger -t "tempmon[$$]" "$1" ;printf '%s \n' "$1" ;}
F_totallinecount() { wc -l < $temp_log ;}  # function to be able to refresh counts
F_cputemp() { cut -c -3 < /sys/class/thermal/thermal_zone0/temp ;}   # function to check current CPU temp
F_format() { sed 's/../&./g' | sed 's/$/&C/g' ;}   # add the decimal formatting
monitor_pid=$(ps | grep -v 'grep' | grep "$script_name monitor" | awk '{print $1}')
run_epoch="$(date +"%s")"			# v1.01  should be correct if monitor is already running and checked ntp state

F_ntp_wait() {			# v1.01
	if [ "$(nvram get ntp_ready)" -eq 0 ] ; then
		ntp_wait_time=0
		while [ "$(nvram get ntp_ready)" -eq 0 ] && [ "$ntp_wait_time" -lt 600 ] ; do
			ntp_wait_time="$((ntp_wait_time + 1))"
			if [ "$ntp_wait_time" -eq 300 ]; then
				F_log_print "Waiting for NTP to sync, 5 mins have passed, waiting 5 more mins"
			fi
			sleep 1
		done
		if [ "$ntp_wait_time" -ge 600 ] ; then
			F_log_print "NTP failed to sync and update router time after 10 mins"
			F_log_print "Please check your NTP date/time settings, tempmon cannot start"
			F_clean_exit
		fi
	fi
} ### ntp_wait

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
	[ -f "$temp_log" ] && rm -f $temp_log   # remove old logs if starting new monitor
	[ -f "$temp_start_log" ] && rm -f $temp_start_log			# v1.01
	printf "Initializing... \n"
	F_ntp_wait			# v1.01 ntp wait to set epoch
	run_epoch="$(date +"%s")"		# v1.01 set correct time for first run
	started() {
		echo "Started $script_name w/ PID $background_pid Current CPUtemp:$(F_cputemp | F_format) Log Interval:${log_interval}${log_interval_unit} PollFreq:${poll_freq}s"
	}
	(sh /jffs/scripts/"$script_name" monitor) & background_pid=$!   # call script as monitor in background
	F_log_print "$(started)"
	printf "%s \n" "$(started)"
	echo "$run_epoch" > $temp_start_log			# v1.01
	exit 0   # exit dont continue to logging if called by cron and found no monitor running
} ### load_tempmon
# ###################################################################################################################
F_calc_uptime() {					# v1.01
	uptime_years=0 ;uptime_days=0 ;uptime_hours=0 ;uptime_mins=0 ;uptime_secs=0   # set for output
	epoch_diff=$((run_epoch - started_epoch))
	if [ "$epoch_diff" -gt 31536000 ] ; then   # year
		uptime_years=$((epoch_diff / 31536000))
		epoch_diff=$((epoch_diff - (31536000 * uptime_years)))
	fi
	if [ "$epoch_diff" -gt 86400 ] ; then   # days
		uptime_days=$((epoch_diff / 86400))
		epoch_diff=$((epoch_diff - (86400 * uptime_days)))
	fi
	if [ "$epoch_diff" -gt 3600 ] ; then   # hours
		uptime_hours=$((epoch_diff / 3600))
		epoch_diff=$((epoch_diff - (3600 * uptime_hours)))
	fi
	if [ "$epoch_diff" -gt 60 ] ; then   # mins
		uptime_mins=$((epoch_diff / 60))
		epoch_diff=$((epoch_diff - (60 * uptime_mins)))
	fi
	uptime_secs=$epoch_diff   			# secs
	[ $uptime_years -gt 0 ] && printf "%s yr(s) " "$uptime_years"
	[ $uptime_days -gt 0 ] && printf "%s day(s) " "$uptime_days"
	[ $uptime_hours -gt 0 ] && printf "%s hr(s) " "$uptime_hours"
	[ $uptime_mins -gt 0 ] && printf "%s min(s) " "$uptime_mins"
	printf "%s sec(s) \n" "$uptime_secs"
} ### calc_uptime

F_calc_avg() {   # calculate avg CPU temp based on current log	
	totaltempcpu=0
	count_calc=$(F_totallinecount)   # get updated count of logged temps
	while read -r readtemp ; do
		totaltempcpu=$((totaltempcpu + readtemp)) # read temps log and add together the readings
	done < $temp_log
	calcavg=$((totaltempcpu / count_calc))
	cpuavg=$(echo "$calcavg" | F_format)   # cpu avg temp calc'd and formatted
	[ "$1" = 'logging' ] && echo "$calcavg" >> $temp_avg_log			# only log avg at log intervals    v1.01
} ### calc_avg

F_averages() {					# v1.01  alltime avg
	totalavgtemp=0
	avg_count=$(wc -l < $temp_avg_log)
	if [ "$avg_count" -ge 2 ] ; then
		while read -r readavg ; do
			totalavgtemp=$((totalavgtemp + readavg))
		done < $temp_avg_log
		cpu_log_avg=$((totalavgtemp / avg_count))
		uptime_avg=$(echo "$cpu_log_avg" |  F_format)
	fi
	[ -z "$uptime_avg" ] && uptime_avg="N/A"		# no logging done yet no avg to display
	[ "$(wc -l < $temp_avg_log)" -ge "$max_avg" ] && rm -f $temp_avg_log && touch $temp_avg_log && F_log_print "Reset logged averages, log reached $max_avg entries"
} ### averages

F_high_low() {
	alltimehigh=$(head -n1 < $ath_log)
	alltimelow=$(head -n1 < $atl_log)   # read alltime high/low
	cpulowunf=$(sort < $temp_log | head -n1)
	cpuhighunf=$(sort < $temp_log | tail -n1)   # unformatted low/high
	cpuhigh=$(sort < $temp_log | tail -n1 | F_format)   # formatted cpuhigh
	cpulow=$(sort < $temp_log | head -n1 | F_format)
} ### high_Low

F_log_temp() {   # for logging avg/high/low cpu temp
	[ ! -s $temp_log ] && F_log_print "Critical error, nothing in log file to calculate" && exit 0
	F_high_low

	if [ "$alltimehigh" = '' ] || [ $cpuhighunf -gt $alltimehigh ] ; then   # if alltimehigh is empty or temp log has higher, record new high
		rm $ath_log 2> /dev/null ;echo "$cpuhighunf" > $ath_log ;alltimehigh=$cpuhighunf
	fi
	if [ "$alltimelow" = '' ] || [ $cpulowunf -lt $alltimelow ] ; then
		rm $atl_log 2> /dev/null ;echo "$cpulowunf" > $atl_log ;alltimelow=$cpulowunf
	fi
	# calc total of temps in log
	sleep $poll_freq   # dont miss last temp check
	F_calc_avg logging # calculate the average temp function
	F_averages 	# calc average of averages		v1.01
	
	# re-save below vars for formatting
	alltimehigh=$(echo "$alltimehigh" | F_format) ;alltimelow=$(echo "$alltimelow" | F_format)

	# send logged info to router log
	F_log_print "Logperiod - CPUnow: $(F_cputemp | F_format) CPUavg: ${cpuavg} CPUhigh: ${cpuhigh} CPUlow: ${cpulow}"
	F_log_print "Alltime - CPUhigh: ${alltimehigh} CPUlow: ${alltimelow} Avg of last ${avg_count} averages: ${uptime_avg} "
	F_log_print "LogPeriod: ${log_interval}${log_interval_unit} PollFreq: ${poll_freq}s Logged/Expected: ${count_calc}/${log_time}"
	F_log_print "Current Monitor PID ${monitor_pid} Monitor Uptime: $(F_calc_uptime)"			# v1.01

	# clear temps log and start over again
	rm $temp_log ;touch $temp_log ;return 0
} ### log_temp
# ####################################################################################################################
if [ -z "$monitor_pid"  ] ; then   # monitor running check
	F_load_tempmon
else
	if [ "$1" = '' ] ; then
		F_calc_avg ;F_averages ;F_high_low
		printf "	tempmon appears to be already monitoring with PID %s \n" "$monitor_pid" # only terminal print if manually run
		printf "	Current: %s Current Avg: %s of %s polled temps at %s second polling \n" "$(F_cputemp | F_format)" "$cpuavg" "$count_calc" "$poll_freq"
		printf "	Logging period: ${log_interval}${log_interval_unit} CPUhigh: %s CPUlow: %s \n" "$cpuhigh" "$cpulow"
		printf "	Alltime: CPUhigh: %s CPUlow: %s Avg of last %s averages: %s \n" "$(echo $alltimehigh | F_format)" "$(echo $alltimelow | F_format)" "$avg_count" "$uptime_avg"
		printf "	Monitor uptime: %s \n" "$(F_calc_uptime)"			# v1.01
	fi
fi

if [ "$1" = 'logging' ] ; then F_log_temp   # logging call
elif [ "$1" = 'monitor' ] ; then  # called as background monitor
	while true
	do
		echo "$(F_cputemp)" >> $temp_log   # write current temp to log
		sleep $poll_freq
	done   # write temp sleep, repeat
fi
exit 0
