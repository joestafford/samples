#! /bin/bash

# This script depends on ubuntu aws cli tools ( sudo apt-get install awscli ) and must
# be configured via "aws configure" command (http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)

# To set this script in maintenance mode, create an empty file at the location defined by maint_file, i.e. "touch /aras/healthcheck/maintenance.mode"
# Aliases exist for .bash_aliases to easily enable and disable maintenance mode.
# Maintenance Mode will terminate all checks performed by the healthcheck script but will send an email to email_to alerting that maintenance is in progress.

# Variables
zabbix_pri="zabbix-primary" #primary zabbix dns name in /etc/hosts
zabbix_pri_id="aws-id" #primary zabbix ec2 instance id
zabbix_backup="zabbix-backup" #backup zabbix dns name in /etc/hosts
zabbix_backup_id="aws-id" #backup zabbix ec2 instance id
i="0" #integer variable used by script
email_from="From User <from@anon.com>" #origin email address
email_to="to@anon.com" #destination email address
maint_file="/ect/healthcheck/maintenance.mode" #if this file exists, maintenance mode is enabled

# Functions

# maintenance mode check
maintenance_status() {
		test -f $maint_file
			if [ $? -eq 0 ]; then
				maint_start=$(date -r $maint_file)
				subject="Monitoring is in maintenance mode on $zabbix_backup"
				body="Monitoring is in maintenance mode on $zabbix_backup since $maint_start"
				echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
				exit
			fi
}

# start local services
start_local_services() {
		sudo service apache2 start > /dev/null
		sudo service zabbix-server start > /dev/null
}

# stop local services
stop_local_services() {
		sudo service apache2 stop > /dev/null
		sudo service zabbix-server stop > /dev/null
}

# reboot primary zabbix server
fix_server() {
		result=$(aws ec2 reboot-instances --instance-ids $zabbix_pri_id)
		start_local_services
		subject="Monitoring Errors"
		body="Monitoring Primary Server $zabbix_pri was rebooted."
		echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
		exit
}

# start instance
start_instance() {
		result=$(aws ec2 start-instances --instance-ids $zabbix_pri_id)
}

# test aws instance state
ping_instance_state() {
		instance_status=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Code]' --output text --instance-ids $zabbix_pri_id)
			if [ $instance_status -eq 16 ]; then # Instance Running
				i=$((i+1))
			elif [ $instance_status -eq 80 ]; then #Instance Stopped
				i=$((i+2))
			elif [ $instance_status -eq 32 ]; then #Instance Shutting Down
				i=$((i+4))
			elif [ $instance_status -eq 48 ]; then #Instance Terminated
				i=$((i+8))
			elif [ $instance_status -eq 64 ]; then #Instance Stopping
				i=$((i+16))
			else #Instance status unknown or AWS error
				i=$((i+32))
			fi
}

# test local services
ping_local_services() {
		sudo service zabbix-server status > /dev/null
			if [ $? -eq 0 ]; then # Local zabbix server is running
				i=$((i+256))
			else # Local zabbix server isn't running
				i=$((i+64))
			fi
		sudo service apache2 status > /dev/null
			if [ $? -eq 0 ]; then # Local apache server is running
				i=$((i+512))
			else # Local zabbix server isn't running
				i=$((i+128))
			fi
}

# test ssh
ping_ssh() {
		ssh -q -o ConnectTimeout=3 $zabbix_pri 'date' > /dev/null
			if [ $? -eq 0 ]; then # SSH successful
				i=$((i+1024))
			else # SSH unsuccessful
				i=$((i+2048))
			fi
}

# test zabbix port
ping_zabbix() {
		nc -w 5 -z $zabbix_pri 10051 > /dev/null
		if [ $? -eq 0 ]; then # If ping is successful
			i=$((i+4096))
		else				# Ping is not successful
			i=$((i+8192))
		fi
}

# test http port
ping_http() {
		nc -w 5 -z $zabbix_pri 80 > /dev/null
		if [ $? -eq 0 ]; then # If ping is successful
			i=$((i+16384))
		else				# Ping is not successful
			i=$((i+32768))
		fi
}

# restart zabbix server service
fix_zabbix() {
		ssh $zabbix_pri 'sudo service zabbix-server restart'
		sleep 5s
		nc -w 5 -z $zabbix_pri 10051 > /dev/null
		if [ $? -ne 0 ]; then # If ping is not successful
			fix_server
		fi
}

# restart http service
fix_http() {
		ssh $zabbix_pri 'sudo service apache2 restart'
		sleep 5s
		nc -w 5 -z $zabbix_pri 80 > /dev/null
		if [ $? -ne 0 ]; then # If ping is not successful
			fix_server
		fi
}

# Main

## Maintenance Mode?

maintenance_status

## run tests
ping_instance_state
ping_local_services
ping_ssh
ping_zabbix
ping_http

## decision tree
	## is primary zabbix server services running?  exit if true
	([[ $((4096 & $i)) -ne 0 ]] && [[ $((16384 & $i)) -ne 0 ]]) && true
		if [ $? -eq 0 ]; then
			exit
		fi	

	## check instance status
	[[ $((2 & $i)) -ne 0 ]] && true ## instance stopped
		if [ $? -eq 0 ]; then
			start_local_services
			start_instance
			subject="Monitoring Errors"
			body="Monitoring Primary Server $zabbix_pri was stopped.  Instance has been started with the result: $result"
			send_email $subject $body
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((4 & $i)) -ne 0 ]] && true ## instance shutting down
		if [ $? -eq 0 ]; then
			start_local_services
			subject="Monitoring Errors"
			body="Monitoring Primary Server instance $zabbix_pri is shutting down."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((8 & $i)) -ne 0 ]] && true ## instance terminated
		if [ $? -eq 0 ]; then
			start_local_services
			subject="Monitoring Errors"
			body="Monitoring Primary Server instance $zabbix_pri has been terminated."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((16 & $i)) -ne 0 ]] && true ## instance stopping
		if [ $? -eq 0 ]; then
			start_local_services
			subject="Monitoring Errors"
			body="Monitoring Primary Server $zabbix_pri is stopping."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	

	[[ $((32 & $i)) -ne 0 ]] && true ## instance status unknown
		if [ $? -eq 0 ]; then
			start_local_services
			subject="Monitoring Errors"
			body="Monitoring Primary Server $zabbix_pri instance status is in an unknown state."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
		
	## one or both server services are down!  check ssh.  if up try to fix zabbix and http.  if successful then exit.  if service restart fails then invoke fix_server
	[[ $((1024 & $i)) -ne 0 ]] && true
		if [ $? -eq 0 ]; then
			([[ $((256 & $i)) -ne 0 ]] || [[ $((512 & $i)) -ne 0 ]]) && true
				if [ $? -eq 0 ]; then
					stop_local_services
					fix_zabbix
					fix_http
					exit
				else
					fix_zabbix
					fix_http
					exit
				fi
		else
			fix_server
			start_local_services
			exit
		fi
exit