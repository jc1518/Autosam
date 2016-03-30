#!/bin/bash
# Test Cloudlets URL redirects in staging written by Jackie Chen
# 12/01/2016 - Version 1.0

# Notes: This script does not work behind proxy, as it needs to spoof the hosts file to test change in staging.

# Load environment variables
source config

# Cloudlets API credential
HEADER="import Cloudlets; s = Cloudlets.client(\"$CLD_BASEURL\",\"$CLD_CLIENTTOKEN\",\"$CLD_CLIENTSECRET\",\"$CLD_ACCESSTOKEN\")"

# Test URL redirect
REDIRECT="import requests,sys; requests.packages.urllib3.disable_warnings(); fromurl = sys.argv[1]; tourl = sys.argv[2]; response = requests.get(fromurl, verify=False); print('0' if tourl in response.url else '1')"

check_proxy()
{
	export | grep -i http_proxy
	if [ $? -eq 0 ]
	then
		echo "The script does not work behind proxy, as it needs to spoof the host file to test change in staging."
		exit 1
	fi
}

check_staging_job()
{
	echo "Reading staging job queues..."
	aws dynamodb scan --table-name $JOB_QUEUE | jq -r '.Items[] | select(.jobstatus.S=="STAGING") | "\(.fromurl.S)  \(.tourl.S) \(.notes.S)"' > .staging.jobs
	STOTAL=$(cat .staging.jobs | wc -l)
	if [ $STOTAL -eq 0 ]
	then
		echo "No jobs are in staging status, exit"
		exit 1
	fi
	for (( m=1; m<=$STOTAL; m++ ))
	do
		SJOB=$(sed -n ${m}p .staging.jobs)
		SJOB_FROM=$(echo $SJOB | cut -d" " -f1)
		SJOB_TO=$(echo $SJOB | cut -d" " -f2)
		SJOB_NOTES=$(echo $SJOB | cut -d" " -f3)
		echo $SJOB_FROM $SJOB_TO >> $SJOB_NOTES
	done
}

update_job_status()
{
	echo "Updating job status to $3"
	if [ "$3" == "PRODUCTION" ]
	then
		aws dynamodb put-item --item "{\"fromurl\":{\"S\":\"$1\"},\"tourl\":{\"S\":\"$2\"},\"jobstatus\":{\"S\":\"$3\"},\"notes\":{\"S\":\"$4\"}}" --table-name $JOB_QUEUE
	else
		aws dynamodb put-item --item "{\"fromurl\":{\"S\":\"$1\"},\"tourl\":{\"S\":\"$2\"},\"jobstatus\":{\"S\":\"$3\"}}" --table-name $JOB_QUEUE
	fi
}

add_spoof_host()
{
	echo ""
	echo "Spoofing host file to test staging"
	sudo bash -c "echo '###spoofing_start###' >> /etc/hosts"
	for MYSITE in `echo $MYSITES | tr ';' '\n'`
	do
		STAGINGHOST=$(dig +short $(dig +short CNAME $MYSITE | sed 's/.net./-staging.net/g') | sort | head -1)
		sudo bash -c "echo $STAGINGHOST $MYSITE >> /etc/hosts"
	done
	sudo bash -c "echo '###spoofing_end###' >> /etc/hosts"
	sleep 3
}

remove_spoof_host()
{
	echo ""
	echo "Removing spoof from host file"
	STARTLINE=$(grep -n "###spoofing_start###" /etc/hosts | cut -d":" -f1)
	ENDLINE=$(grep -n "###spoofing_end###" /etc/hosts | cut -d":" -f1)
	sudo bash -c "sed -i $STARTLINE,${ENDLINE}d /etc/hosts"
}

read_pending_configurations()
{
	echo ""
	echo "Checking any pending configurations..."
	ls | grep ^staging | grep -v test_result
	if [ $? -ne 0 ]; then echo "No pending configurations in staging!"; exit 1; fi
	TOTAL=$(ls staging.* | grep -v test_result | wc -l)
	echo "There are $TOTAL pending configurations for testing in staging"
}

test_redirect()
{
	for site in `ls staging.* | grep -v test_result`
	do
		echo ""
		echo ">>>>>>>>>> Processing $site"
		n=0
		POLICYID=$(echo $site  | cut -d'.' -f2)
		POLICYNAME=$(echo $site  | cut -d'.' -f3)
		NEWVERSION=$(echo $site  | cut -d'.' -f4)
		OLDPRODVERSION=$(echo $site  | cut -d'.' -f5)
		check_policy_status
		if [ $STAGPOLICYSTATUS == "pending" ]
		then
			echo "The staging configuration is in pending status, skip this job for now"
			continue
		fi
		SUBTOTAL=$(cat $site | wc -l)
		for (( j=1; j<=$SUBTOTAL; j++ ))
		do
			JOB=$(sed -n ${j}p $site)
			echo ""
			echo Testing redirect: $JOB
			RETURN=$($MYPYTHON -c "$REDIRECT" $JOB)
			echo "Result: $RETURN (0-passed, 1-failed)"
			if [ $RETURN == '0' ]
			then
			   	echo $JOB PASSED >> $site.test_result
				update_job_status $JOB "STAGING-PASSED"
		   	fi
			if [ $RETURN == '1' ]
			then
				echo $JOB FAILED >> $site.test_result
				update_job_status $JOB "STAGING-FAILED"
		   	fi
			let n=$n+$RETURN
		done
		#echo n is $n
		TESTRETURN="FAILED:"
		if [ $n -eq 0 ]
	   	then
			TESTRETURN="PASSED:"
			echo ""
			echo "Test is passed :)"
			cat $site.test_result
			# Check the before and after production version
			if [ "$OLDPRODVERSION" != "$NEWPRODVERSION" ]
			then
				echo ""
				echo "Abort activating prod of $POLICYNAME, as production version has changed while testing staging: old-$OLDPRODVERSION, new-$NEWPRODVERSION"
				echo "--------------------------------------------------------" >> $site.test_result
				echo "Abort activating prod of $POLICYNAME, as production version has changed while testing staging: old-$OLDPRODVERSION, new-$NEWPRODVERSION" >> $site.test_result
				echo "--------------------------------------------------------" >> $site.test_result
				for (( j=1; j<=$SUBTOTAL; j++  ))
				do
					JOB=$(sed -n ${j}p $site)
					update_job_status $JOB "PRODUCTION-ABORT"
				done
			else
				# Active this version in production
				echo ""
				echo "$POLICYNAME version $NEWVERSION is ready to be pushed to prod!"
				echo "--------------------------------------------------------" >> $site.test_result
				echo "$POLICYNAME version $NEWVERSION is ready to be pushed to prod!" >> $site.test_result
				echo "--------------------------------------------------------" >> $site.test_result
				#activate_prod
				# Manual mode
				for (( j=1; j<=$SUBTOTAL; j++  ))
				do
					JOB=$(sed -n ${j}p $site)
					update_job_status $JOB "PRODUCTION-READY" $POLICYID
				done
				rm -rf $site
			fi
		else
			echo ""
			echo "Test is failed :("
			cat $site.test_result
		fi
		mail -s "$TESTRETURN $site" $RECEIVER < $site.test_result
		rm -rf $site.test_result
	done
}

check_policy_status()
{
	$MYPYTHON -c "$HEADER; print s.getPolicy('$POLICYID')" | jq -r '.activations[] | "\(.network) \(.policyInfo.status) \(.policyInfo.version)"' | sort -u  > .temp1.$POLICYID.status
	STAGPOLICYSTATUS=`cat .temp1.$POLICYID.status | grep staging | awk {'print $2'}`
	STAGPOLICYVERSION=`cat .temp1.$POLICYID.status | grep staging | awk {'print $3'}`
	PRODPOLICYSTATUS=`cat .temp1.$POLICYID.status | grep prod | awk {'print $2'}`
	PRODPOLICYVERSION=`cat .temp1.$POLICYID.status | grep prod | awk {'print $3'}`
	NEWPRODVERSION=$PRODPOLICYVERSION
}

activate_prod()
{
	echo ""
	if [ $n -eq 0 ]
	then
		echo ">>>>>>>>>> Activating version $NEWVERSION of $POLICYNAME ($POLICYID) in prod"
		$MYPYTHON -c "$HEADER; print s.activateVersion('$POLICYID','$NEWVERSION', 'prod')" >> .temp1.$POLICYID.prod
		grep -i error .temp1.$POLICYID.prod
		if [ $? -eq 0 ]
		then
			echo "Something went wrong when activating $POLICYNAME version $NEWVERSION in prod"
			mail -s "Something went wrong when activating $POLICYNAME version $NEWVERSION in prod" $RECEIVER < .temp1.$POLICYID.prod
			continue
		else
			cat .temp1.$POLICYID.prod
			mail -s "Autosam Bot pushed $POLICYNAME version $NEWVERSION to prod" $RECEIVER < .temp1.$POLICYID.prod
			for (( j=1; j<=$SUBTOTAL; j++  ))
			do
				JOB=$(sed -n ${j}p $site)
				update_job_status $JOB "PRODUCTION" $POLICYID
			done
		fi
	fi
}

# Main function
rm -rf .temp1.* staging.*
check_proxy
check_staging_job
read_pending_configurations
add_spoof_host
test_redirect
remove_spoof_host

