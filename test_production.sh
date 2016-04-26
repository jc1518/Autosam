#!/bin/bash
# Test Cloudlets URL redirects in production written by Jackie Chen
# 13/01/2016 - Version 1.0

# Load environment variables
source config

# Cloudlets API credential
HEADER="import Cloudlets; s = Cloudlets.client(\"$CLD_BASEURL\",\"$CLD_CLIENTTOKEN\",\"$CLD_CLIENTSECRET\",\"$CLD_ACCESSTOKEN\")"

# Test URL redirect
REDIRECT="import requests,sys; requests.packages.urllib3.disable_warnings(); fromurl = sys.argv[1]; tourl = sys.argv[2]; response = requests.get(fromurl, verify=False); print('0' if tourl in response.url else '1')"

check_production_job()
{
	echo "Reading production job queues..."
	aws dynamodb scan --table-name $JOB_QUEUE | jq -r '.Items[] | select(.jobstatus.S=="PRODUCTION") | "\(.fromurl.S)  \(.tourl.S) \(.notes.S)"' > .production.jobs
	PTOTAL=$(cat .production.jobs | wc -l)
	if [ $PTOTAL -eq 0 ]
	then
		echo "No jobs are in production status, exit"
		exit 1
	fi
	for (( m=1; m<=$PTOTAL; m++ ))
	do
		JOB=$(sed -n ${m}p .production.jobs)
		PJOB=$(echo $JOB | awk {'print $1 " " $2'})
		POLICYID=$(echo $JOB | awk {'print $3'})
		check_policy_status
		if [[ "$PRODPOLICYSTATUS" == *"pending" ]]
		then
			echo "The production configuration is in pending status, skip this job for now"
			continue
		fi
		test_redirect
	done
}

check_policy_status()
{
	$MYPYTHON -c "$HEADER; print s.getPolicy('$POLICYID')" | jq -r '.activations[] | "\(.network) \(.policyInfo.status) \(.policyInfo.version)"' | sort -u > .temp2.$POLICYID.status
	STAGPOLICYSTATUS=`cat .temp2.$POLICYID.status | grep staging | awk {'print $2'}`
	STAGPOLICYVERSION=`cat .temp2.$POLICYID.status | grep staging | awk {'print $3'}`
	PRODPOLICYSTATUS=`cat .temp2.$POLICYID.status | grep prod | awk {'print $2'}`
	PRODPOLICYVERSION=`cat .temp2.$POLICYID.status | grep prod | awk {'print $3'}`
}

update_job_status()
{
	echo "Updating job status to $3"
	aws dynamodb put-item --item "{\"fromurl\":{\"S\":\"$1\"},\"tourl\":{\"S\":\"$2\"},\"jobstatus\":{\"S\":\"$3\"}}" --table-name $JOB_QUEUE
}

test_redirect()
{
		echo ""
		rm -rf .production.test_result
		echo Testing redirect: $PJOB
		RETURN=$($MYPYTHON -c "$REDIRECT" $PJOB)
		echo "Result: $RETURN (0-passed, 1-failed)"
		if [ $RETURN == '0' ]
		then
			SUBJECT="PASSED"
			echo $PJOB PASSED > .production.test_result
			update_job_status $PJOB "CLOSED"
		fi
		if [ $RETURN == '1' ]
		then
			SUBJECT="FAILED"
			echo $PJOB FAILED > .production.test_result
			update_job_status $PJOB "PRODUCTION-FAILED"
		fi
		mail -s "$SUBJECT: Production URL redirect test" $RECEIVER < .production.test_result
}

# Main function
rm -rf .temp2.* .production.*
check_production_job
