#!/bin/bash
# Cloudlets URL redirects automation written by Jackie Chen
# 08/12/2015 - Version 1.0
# 30/03/2016 - Version 1.1 - Add feature to remove duplicated rules

# Load environment variables
source config

# Cloudlets API credential
HEADER="import Cloudlets; s = Cloudlets.client(\"$CLD_BASEURL\",\"$CLD_CLIENTTOKEN\",\"$CLD_CLIENTSECRET\",\"$CLD_ACCESSTOKEN\")"

# List cloudlets policy ID
list_policy_id(){
	echo ""
	echo "Downloading all policy ID, this will take a few minutes..."
	for id in `$MYPYTHON -c "$HEADER; print s.listGroups()" | jq -r .[].groupId`
	do
		$MYPYTHON -c "$HEADER; print s.listPolicies(str($id))" >> .temp.allid
	done
	cat .temp.allid | jq -r '.[] | "\(.name) \(.policyId)"' | sort -u  > .temp.policy_id
}

# Read redirects job queue
read_open_jobs()
{
	# Read jobs from local file or from job queue
	if [ "$1" != "" ]
	then
		sed -i '/^$/d' $1
		cat $1 > .temp.open_jobs
		mail -s "`logname` added new URL redirects" $RECEIVER < .temp.open_jobs
	else
		echo "Reading open job queues..."
		aws dynamodb scan --table-name $JOB_QUEUE | jq -r '.Items[] | select(.jobstatus.S=="OPEN") | "\(.fromurl.S)  \(.tourl.S)"' > .temp.open_jobs
	fi

	# Validation
	TOTAL=`cat .temp.open_jobs | wc -l`
	if [ $TOTAL -lt 1 ]; then echo "No jobs are in open status, exit"; exit 1; fi
	echo There are $TOTAL open jobs in the queue.
	for (( c=1; c<=$TOTAL; c++  ))
	do
		OPENJOB=$(sed -n ${c}p .temp.open_jobs)
		url_check $OPENJOB
	done
}

check_staging_jobs()
{
	echo ""
    echo "Reading staging job queues..."
    aws dynamodb scan --table-name $JOB_QUEUE | jq -r '.Items[] | select(.jobstatus.S=="STAGING") | "\(.fromurl.S)  \(.tourl.S) \(.notes.S)"' > .staging.jobs
    STOTAL=$(cat .staging.jobs | wc -l)
    if [ $STOTAL -eq 0  ]
    then
        echo "Good, no jobs are in staging status"
	else
		for (( m=1; m<=$STOTAL; m++  ))
		do
			SJOB=$(sed -n ${m}p .staging.jobs)
			SJOB_FROM=$(echo $SJOB | cut -d" " -f1)
			SJOB_TO=$(echo $SJOB | cut -d" " -f2)
			SJOB_NOTES=$(echo $SJOB | cut -d" " -f3)
			echo $SJOB_FROM $SJOB_TO >> $SJOB_NOTES
		done
	fi
}

update_job_status()
{
	echo "Updating job status to $3"
	aws dynamodb put-item --item "{\"fromurl\":{\"S\":\"$1\"},\"tourl\":{\"S\":\"$2\"},\"jobstatus\":{\"S\":\"$3\"},\"notes\":{\"S\":\"$4\"}}" --table-name $JOB_QUEUE
}

url_check()
{
	FROM_URL=$1
	TO_URL=$2
	if [ ! $(echo $FROM_URL | /bin/grep -i ^http)  ]; then echo "Error: URL should start with http:// - FROM_URL: $FROM_URL"; exit 1; fi
	if [ -z $(echo $FROM_URL | cut -d "/" -f4)  ]; then echo "Error: URL should have a path after the host - FROM_URL: $FROM_URL"; exit 1; fi
	if [ ! $(echo $TO_URL | /bin/grep -i ^http)  ]; then echo "Error: URL should start with http:// - TO_URL: $TO_URL"; exit 1; fi
}

fix_duplicates()
{
	echo ">>>>>>>>>> Checking the duplicated rules in $POLICYNAME..."
	RULE_LINE=$(cat .temp.$POLICYID.policyfile | jq -r .[].matchURL | wc -l)
	echo $POLICYNAME has $RULE_LINE redirect rules
	n=0
	j=''
	if [[ $(echo $FROMURL | grep -c '?' ) -gt 0 ]]
	then
		# URL with query string
  		FROMURL_PATH=/`echo $FROMURL | cut -d '/' -f4- | cut -d '?' -f1`
  		FROMURL_QUERY=`echo $FROMURL | cut -d '/' -f4- | cut -d '?' -f2`
  		for (( i=0; i<${RULE_LINE}; i++ ))
  		do
    		RULE_REGEX=`jq -r .[$i].matches[].matchValue .temp.$POLICYID.policyfile | tr '\n' ','`
    		if [[ $(echo $RULE_REGEX | grep -c "${FROMURL_PATH}") -eq 1 ]] && [[ $(echo $RULE_REGEX | grep -c "${FROMURL_QUERY}") -eq 1 ]]
    		then
      			j=$j,$i
      			let n=$n+1
    		fi
  		done
	else
  		for (( i=0; i<${RULE_LINE}; i++ ))
  		do
    		if [[ "$(jq -r .[$i].matches[].matchValue .temp.$POLICYID.policyfile)" == "${FROMURL}(/)?$" ]] || [[ "$(jq -r .[$i].matchURL .temp.$POLICYID.policyfile)" == $FROMURL ]]
    		then
      			j=$j,$i
      			let n=$n+1
    		fi
  		done
	fi

	echo $n rules are for the same source URL.

	if [ $n -gt 1 ]
	then
		echo "Line $j have duplicated source URL"
		DUP=`echo $j | cut -d',' -f2-$n`
		echo "The following rules #$DUP will be deleted due to duplication"
		jq -r .[$DUP] .temp.$POLICYID.policyfile
		jq -r .[$DUP] .temp.$POLICYID.policyfile >> .temp.job.$POLICYID.$POLICYNAME.removed
		echo "Deleting duplicated rules..."
		jq "del(.[$DUP])" .temp.$POLICYID.policyfile > .temp.$POLICYID.policyfile.nodup
		mv -f .temp.$POLICYID.policyfile .temp.$POLICYID.policyfile.withdup
		mv -f .temp.$POLICYID.policyfile.nodup .temp.$POLICYID.policyfile
	fi
}

create_new_version()
{
	echo ""
	echo ">>>>>>>>>> Creating new version policy based on $PRODPOLICYVERSION..."
	$MYPYTHON -c "$HEADER; print s.createPolicyVersion('$POLICYID', '$PRODPOLICYVERSION', '.temp.$POLICYID.policyfile', '$VERNOTES')" > .temp.$POLICYID.newversion
	#cat .temp.$POLICYID.newversion
	NEWVERSION=`cat .temp.$POLICYID.newversion | jq -r .version`
	echo The new version is $NEWVERSION
}

activate_version()
{
	echo ""
	# POLICYENV can only be staging or prod
	POLICYENV=$1
	echo ">>>>>>>>>> Activating version $NEWVERSION of $POLICYNAME ($POLICYID) in $POLICYENV"
	$MYPYTHON -c "$HEADER; print s.activateVersion('$POLICYID','$NEWVERSION', '$POLICYENV')" > .temp.$POLICYID.$1
	grep -i error .temp.$POLICYID.$1
	if [ $? -eq 0 ]
   	then
		echo "Something went wrong when activating $POLICYNAME version $NEWVERSION in $POLICYENV"
		mail -s "Something went wrong when activating $POLICYNAME version $NEWVERSION in $POLICYENV" $RECEIVER < .temp.$POLICYID.$1
		continue
	else
		cat .temp.$POLICYID.$1
		echo "------------------------------------------------------" >> .temp.$POLICYID.$1
		echo "Added the following redirects" >> .temp.$POLICYID.$1
		echo "------------------------------------------------------" >> .temp.$POLICYID.$1
		cat .temp.job.$POLICYID.$POLICYNAME >> .temp.$POLICYID.$1
		echo "------------------------------------------------------" >> .temp.$POLICYID.$1
		echo "Removed the following duplicated redirects" >> .temp.$POLICYID.$1
		echo "------------------------------------------------------" >> .temp.$POLICYID.$1
		cat .temp.job.$POLICYID.$POLICYNAME.removed >> .temp.$POLICYID.$1
		mail -s "Autosam Bot pushed $POLICYNAME version $NEWVERSION to $1" $RECEIVER < .temp.$POLICYID.$1
	fi
}

download_policy()
{
	echo "Downloading policy from production version $PRODPOLICYVERSION..."
	$MYPYTHON -c "$HEADER; print s.getPolicyVersion('$POLICYID','$PRODPOLICYVERSION')" > .temp.$POLICYID.policy.old
	grep -v '"location": "/cloudlets/api/v2/policies' .temp.$POLICYID.policy.old > .temp.$POLICYID.policy.new
}

add_policy()
{
	$MYPYTHON -c "$HEADER; s.addRule('$MERGEDRULES','$NEWRULE')"
}

check_policy_status()
{
	$MYPYTHON -c "$HEADER; print s.getPolicy('$POLICYID')" | jq -r '.activations[] | "\(.network) \(.policyInfo.status) \(.policyInfo.version)"' | sort -u  > .temp.$POLICYID.status
	STAGPOLICYSTATUS=`cat .temp.$POLICYID.status | grep staging | awk {'print $2'}`
	STAGPOLICYVERSION=`cat .temp.$POLICYID.status | grep staging | awk {'print $3'}`
	PRODPOLICYSTATUS=`cat .temp.$POLICYID.status | grep prod | awk {'print $2'}`
	PRODPOLICYVERSION=`cat .temp.$POLICYID.status | grep prod | awk {'print $3'}`
	echo "STAGING: status-${STAGPOLICYSTATUS}, version-${STAGPOLICYVERSION}"
	echo "PRODUCTION: status-${PRODPOLICYSTATUS}, version-${PRODPOLICYVERSION}"
	if [ "$PRODPOLICYVERSION" == "0" ]
	then
		echo "0 means no production version yet, force to use version 1"
	        PRODPOLICYVERSION=1
	fi
}

categorize_job()
{
	for (( n=1; n<=$TOTAL; n++ ))
	do
		echo Reading job $n of $TOTAL...
		JOB=$(sed -n ${n}p .temp.open_jobs)
		POLICYNAME=$(echo "$JOB" | cut -d' ' -f1 | cut -d'/' -f3 | cut -d'.' -f1-2 | tr '.' '_')"_prod"
		POLICYID=$(cat .temp.policy_ids | grep -w $POLICYNAME | cut -d' ' -f2)
		if [ -z $POLICYID ]
		then
			echo Can not find policy ID for $POLICYNAME
			# set status as error
			update_job_status $JOB "ERROR: config is not in Cloudlets" "Config could not be found"
			continue
		else
			echo JOB FROM TO: $JOB
			echo POLICY NAME ID: $POLICYNAME $POLICYID
			echo $JOB >> .temp.job.$POLICYID.$POLICYNAME
		fi
	done
}

process_job()
{
	echo ""
	for site in `ls .temp.job.*`
	do
		SUBTOTAL=`cat $site | wc -l`
		POLICYID=`echo $site | cut -d'.' -f4`
		POLICYNAME=`echo $site | cut -d'.' -f5`
		# Checking if any previous pending configurations
		ls | grep ^staging.$POLICYID | grep -v test
		if [ $? -eq 0 ]
		then
			echo "Quit, as there is a pending configuration needs to be tested out first"
			continue
		fi
		echo ""
		echo "*********************************************************"
		echo Working on $POLICYNAME $POLICYID
		check_policy_status
		# Skip if there is a pending status
		if [ $STAGPOLICYSTATUS == "pending" ] || [ $PRODPOLICYSTATUS == "pending" ]
		then
			echo "The configuration is in pending status, skip this job for now"
			continue
		fi
		download_policy
		unset FROMPATH
		# Append the new rules
		for (( m=1; m<=$SUBTOTAL; m++ ))
		do
			echo ""
			echo ">>>>>>>>>> Processing job $m of $SUBTOTAL for $POLICYNAME"
			JOB=$(sed -n ${m}p $site)
			FROMURL=`echo $JOB | awk {'print $1'}`
			# Remove trailing slash if any
			FROMURL=`echo $FROMURL | sed -e 's/\/$//'`
			TOURL=`echo $JOB | awk {'print $2'}`
			FROMPATH="${FROMPATH}`echo $FROMURL | cut -d '/' -f4-`,"
			echo FROM_URL: $FROMURL
			echo TO_URL: $TOURL
			$MYPYTHON -c "$HEADER; print s.createRule('$FROMURL', '$TOURL')" > .temp.$POLICYID.$m
			echo "Merging following policy..."
			cat .temp.$POLICYID.$m | jq -r .
			jq -s '.[0] as $o1 | .[1] as $o2 | ($o1 + $o2) | .matchRules = ($o1.matchRules + $o2.matchRules)' .temp.$POLICYID.policy.new .temp.$POLICYID.$m > .temp.$POLICYID.policy.temp
			mv .temp.$POLICYID.policy.temp .temp.$POLICYID.policy.new
		done
		UPDATES="`cat .temp.$POLICYID.policy.new | jq -r .matchRules`"
		echo $UPDATES > .temp.$POLICYID.policyfile
		# Fix duplicates
		for (( m=1; m<=$SUBTOTAL; m++ ))
		do
			JOB=$(sed -n ${m}p $site)
			FROMURL=`echo $JOB | awk {'print $1'}`
			# Remove trailing slash if any
			FROMURL=`echo $FROMURL | sed -e 's/\/$//'`
			fix_duplicates
		done
        NOTE_LENGTH=`echo $FROMPATH | wc -m`
        if [ "$NOTE_LENGTH" -gt 220  ]; then FROMPATH="the last $SUBTOTAL rules"; fi
		VERNOTES=", added: $FROMPATH"
		create_new_version
		activate_version staging
		# Create pending job for testing staging later
		for (( m=1; m<=$SUBTOTAL; m++ ))
		do
			JOB=$(sed -n ${m}p $site)
			update_job_status $JOB "STAGING" "staging.$POLICYID.$POLICYNAME.$NEWVERSION.$PRODPOLICYVERSION"
		done
	done
}

# Main function
rm -rf .temp.*
rm -rf staging.*
read_open_jobs $1
check_staging_jobs
list_policy_id
categorize_job
process_job
#rm $1
