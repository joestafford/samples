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
				subject="Monitoring is in maintenance mode on $zabbix_pri"
				body="Monitoring is in maintenance mode on $zabbix_pri since $maint_start"
				echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
				exit
			fi
}

# reboot primary zabbix server
fix_server() {
		result=$(aws ec2 reboot-instances --instance-ids $zabbix_backup_id)
		subject="Monitoring Errors"
		body="Monitoring Backup Server $zabbix_backup was rebooted."
		echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
		exit
}

# start instance
start_instance() {
		result=$(aws ec2 start-instances --instance-ids $zabbix_backup_id)
}

# test aws instance state
ping_instance_state() {
		instance_status=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Code]' --output text --instance-ids $zabbix_backup_id)
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

# test ssh
ping_ssh() {
		ssh -q -o ConnectTimeout=3 $zabbix_backup 'date' > /dev/null
			if [ $? -eq 0 ]; then # SSH successful
				i=$((i+1024))
			else # SSH unsuccessful
				i=$((i+2048))
			fi
}

# Main

## Maintenance Mode?

maintenance_status

## run tests
ping_instance_state
ping_ssh

## decision tree
	## is backup zabbix server running?  exit if true
	[[ $((1024 & $i)) -ne 0 ]] && true
		if [ $? -eq 0 ]; then
			exit
		fi	

	## check instance status
	[[ $((2 & $i)) -ne 0 ]] && true ## instance stopped
		if [ $? -eq 0 ]; then
			start_instance
			subject="Monitoring Errors"
			body="Monitoring Backup Server $zabbix_backup was stopped.  Instance has been started with the result: $result"
			send_email $subject $body
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((4 & $i)) -ne 0 ]] && true ## instance shutting down
		if [ $? -eq 0 ]; then
			subject="Monitoring Errors"
			body="Monitoring Backup Server instance $zabbix_backup is shutting down."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((8 & $i)) -ne 0 ]] && true ## instance terminated
		if [ $? -eq 0 ]; then
			subject="Monitoring Errors"
			body="Monitoring Backup Server instance $zabbix_backup has been terminated."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
	
	[[ $((16 & $i)) -ne 0 ]] && true ## instance stopping
		if [ $? -eq 0 ]; then
			subject="Monitoring Errors"
			body="Monitoring Backup Server $zabbix_backup is stopping."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	

	[[ $((32 & $i)) -ne 0 ]] && true ## instance status unknown
		if [ $? -eq 0 ]; then
			subject="Monitoring Errors"
			body="Monitoring Backup Server $zabbix_backup instance status is in an unknown state."
			echo $body | mail -s "$subject" "$email_to" -a "From:$email_from"
			exit
		fi	
		
	## if ssh is down, reboot instance
	[[ $((2048 & $i)) -ne 0 ]] && true
		if [ $? -eq 0 ]; then
			fix_server
			exit
		fi
exit