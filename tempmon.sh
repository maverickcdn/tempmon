#!/bin/sh
# Asus HND Temperature Logging Script
log_interval=6   # interval in mins to log avg temp to router log 0-59m or 0-23h or 0-364
log_interval_unit=h   # lowercase m (minutes) or h (hours) or d (days) are valid
poll_freq=20   # polling frequency of cpu temp in seconds (min 2)
max_avg=10000	# max num of averages to save to ram		v1.01
#######################################################################################################################
script_name="$(basename "$0")"   # script name should be tempmon.sh but anything will work
script_ver='1.10'
trap '' SIGHUP
temp_log="/tmp/${script_name}_temps.tmp"   # log to record temps used to calc avg
ath_log="/tmp/${script_name}_ath.tmp"   # alltimehigh log
atl_log="/tmp/${script_name}_atl.tmp"   # alltimelow log
ath_time_log="/tmp/${script_name}_ath_time.tmp"			# v1.02
atl_time_log="/tmp/${script_name}_atl_time.tmp"			# v1.02
temp_start_log="/tmp/${script_name}_start.tmp"   # epoch start of monitor log for calc monitor uptime	# v1.01
temp_avg_log="/tmp/${script_name}_avg.tmp"   # avg of averages log   # v1.01
temp_start_date="/tmp/${script_name}_start_date.tmp"
[ -f $temp_start_log ] && started_epoch=$(head -n1 < $temp_start_log)	# print out start epoch from temp file			# v1.01
[ "$log_interval_unit" = 'm' ] && log_time=$((log_interval * 60 / poll_freq))   # log interval time converted to log entry count
[ "$log_interval_unit" = 'h' ] && log_time=$((log_interval * 3600 / poll_freq))
[ "$log_interval_unit" = 'd' ] && log_time=$((log_interval * 86400 / poll_freq))
[ ! -x /jffs/scripts/"$script_name" ] && chmod a+rx /jffs/scripts/"$script_name"
#[ ! -f $ath_log ] && touch $ath_log
#[ ! -f $atl_log ] && touch $atl_log
[ ! -f $temp_log ] && touch $temp_log
[ ! -f $temp_avg_log ] && touch $temp_avg_log			# v1.01
[ ! -f $ath_time_log ] && touch $ath_time_log			# v1.02
[ ! -f $atl_time_log ] && touch $atl_time_log			# v1.02
ath_time="$(cat "$ath_time_log")"						# v1.02
atl_time="$(cat "$atl_time_log")"						# v1.02
F_printf() { printf '%s\n' "$1" ;}						# v1.03
F_log_print() { logger -t "tempmon[$$]" "$1" ; F_printf "$1" ;}
F_totallinecount() { wc -l < $temp_log ;}  # function to be able to refresh counts
F_cputemp() { cut -c -3 < /sys/class/thermal/thermal_zone0/temp ;}   # function to check current CPU temp
F_format() { sed 's/../&./g' | sed 's/$/&C/g' ;}   # add the decimal formatting
monitor_pid=$(ps -w | grep -v 'grep' | grep "$script_name monitor" | awk '{print $1}')
run_epoch="$(date +"%s")"			# v1.01  should be correct if monitor is already running and checked ntp state
run_date="$(date +"%c")"			

#######################################################################################################################
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
#######################################################################################################################
F_load_tempmon() {
	[ -f "$temp_log" ] && rm -f $temp_log   # remove old logs if starting new monitor
	[ -f "$temp_start_log" ] && rm -f $temp_start_log			# v1.01
	
	F_printf "Initializing..."
	
	F_ntp_wait			# v1.01 ntp wait to set epoch
	
	run_epoch="$(date +"%s")"		# v1.01 set correct time for first run
	run_date="$(date +"%c")"		# v1.02
	
	started() {
		F_printf "Started $script_name w/ PID $background_pid Current CPUtemp:$(F_cputemp | F_format) Log Interval:${log_interval}${log_interval_unit} PollFreq:${poll_freq}s"
	}
	
	(sh /jffs/scripts/"$script_name" monitor) & background_pid=$!   # call script as monitor in background
	
	F_log_print "$(started)"
	F_printf "$run_epoch" > $temp_start_log			# v1.01
	F_printf "$(date -R)" > $temp_start_date
	exit 0   # exit dont continue to logging if called by cron and found no monitor running
} ### load_tempmon

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
	cpuavg=$(F_printf "$calcavg" | F_format)   # cpu avg temp calc'd and formatted
	[ "$1" = 'logging' ] && F_printf "$calcavg" >> $temp_avg_log			# only log avg at log intervals    v1.01
} ### calc_avg

F_averages() {					# v1.01  alltime avg
	totalavgtemp=0
	avg_count=$(wc -l < $temp_avg_log)
	if [ "$avg_count" -ge 2 ] ; then
		while read -r readavg ; do
			totalavgtemp=$((totalavgtemp + readavg))
		done < $temp_avg_log
		cpu_log_avg=$((totalavgtemp / avg_count))
		uptime_avg=$(F_printf "$cpu_log_avg" |  F_format)
	fi
	[ -z "$uptime_avg" ] && uptime_avg="N/A"		# no logging done yet no avg to display
	[ "$(wc -l < $temp_avg_log)" -ge "$max_avg" ] && rm -f $temp_avg_log && touch $temp_avg_log && F_log_print "Reset logged averages, log reached $max_avg entries"
} ### averages

F_high_low() {
	alltimehigh=$(head -n1 < $ath_log | F_format)
	alltimelow=$(head -n1 < $atl_log | F_format)
	cpuhigh=$(sort < $temp_log | tail -n1 | F_format)   # formatted cpuhigh
	cpulow=$(sort < $temp_log | head -n1 | F_format)
} ### high_Low

F_log_temp() {   # for logging avg/high/low cpu temp
	[ ! -s $temp_log ] && F_log_print "Critical error, nothing in log file to calculate" && exit 0

	F_high_low

	# calc total of temps in log
	sleep $poll_freq   # dont miss last temp check
	F_calc_avg logging # calculate the average temp function
	F_averages 	# calc average of averages		v1.01

	# send logged info to router log
	F_log_print "Log Period  - ${log_interval}${log_interval_unit} PollFreq - ${poll_freq}s Logged/Expected - ${count_calc}/${log_time}"
	F_log_print "Log Period  - CPUnow  - $(F_cputemp | F_format) CPUavg - ${cpuavg} CPUhigh - ${cpuhigh} CPUlow - ${cpulow}"
	F_log_print "Alltime     - CPUhigh - ${alltimehigh} recorded ${ath_time}"
	F_log_print "Alltime     - CPUlow  - ${alltimelow} recorded ${atl_time}"
	F_log_print "Alltime     - CPUavg  - ${uptime_avg} of last ${avg_count} recorded averages"
	F_log_print "Current Monitor PID - ${monitor_pid} Monitor Uptime - $(F_calc_uptime)"			# v1.01

	# clear temps log and start over again
	rm $temp_log ; touch $temp_log ; return 0
} ### log_temp

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
			exit 0			# v1.02
		fi
	fi
	TZ="$(cat /etc/TZ)"			# v1.02
	export TZ					# v1.02
} ### ntp_wait

F_purge() {
	temp_files=$(F_printf "$temp_log $ath_log $atl_log $ath_time_log $atl_time_log $temp_avg_log $temp_start_log $temp_start_date")

	for filename in $temp_files ; do
		F_printf "Removing $filename"
		rm -f "$filename"
	done
	exit 0
}

# START ###############################################################################################################
# first manual run, create monitor background task, cron runs will restart monitor if it died
if [ "$1" = 'purge' ] ; then
	F_purge
fi

if [ -z "$monitor_pid"  ] ; then   # monitor running check
	F_load_tempmon
fi

if [ "$1" = '' ] ; then
	F_calc_avg
	F_averages
	F_high_low
	F_printf
	F_printf "*** $script_name appears to be already monitoring with PID $monitor_pid ***" # only terminal print if manually run
	F_printf "---Current---"
	F_printf "CPU Temp - $(F_cputemp | F_format)"
	F_printf
	F_printf "---Log Period ${log_interval}${log_interval_unit}---"
	F_printf "High     - $cpuhigh"
	F_printf "Low      - $cpulow"
	F_printf "Average  - $cpuavg of $count_calc polled temps at $poll_freq second polling"
	F_printf
	F_printf "---Alltime---"
	F_printf "High     - $(F_printf $alltimehigh) recorded $ath_time"
	F_printf "Low      - $(F_printf $alltimelow) recorded $atl_time"
	F_printf "Average  - $uptime_avg of last $avg_count recorded averages"
	F_printf
	F_printf "---Monitor---"
	F_printf "Started  - $(head -n1 < $temp_start_date)"
	F_printf "Uptime   - $(F_calc_uptime)"			# v1.01
	F_printf
elif [ "$1" = 'logging' ] ; then
	F_log_temp   # logging call
elif [ "$1" = 'monitor' ] ; then  # called as background monitor
	while true
	do
		current_temp="$(F_cputemp)"										# v1.03
		F_printf "$current_temp" >> $temp_log

		if [ ! -f "$ath_log" ] || [ "$current_temp" -gt "$(head -n1 < $ath_log)" ] ; then
			F_printf "$current_temp" > $ath_log
			F_printf "$(/bin/date -R)" > $ath_time_log
		fi

		if [ ! -f "$atl_log" ] || [ "$current_temp" -lt "$(head -n1 < $atl_log)" ] ; then
			F_printf "$current_temp" > $atl_log
			F_printf "$(/bin/date -R)" > $atl_time_log
		fi																#

		sleep $poll_freq
	done   # write temp sleep, repeat
fi
exit 0
# END #################################################################################################################
