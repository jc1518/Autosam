#Autosam

##Description
Autosam is a project that I created to automate the Akamai Cloudlets Edge Redirect from end to end, including add new rules, remove duplicated rules if there are any, push to staging, test in staging, push to production, test in production.     

##Design
Autosam is written in Bash and Python, and it utilizes a few technologies: [slack](https://slack.com/), [hubot](https://hubot.github.com/), [AWS DynamoDB](https://aws.amazon.com/documentation/dynamodb/) and [Cloudlets API](https://developer.akamai.com/api/luna/cloudlets/overview.html).

Here is the high level architecture
![architecture](design/autosam_architecture.png)

##Workflow
Here is the detailed workflow design
![workflow](design/autosam_v2_workflow.png)

##Lifecycle
Autosam treats every redirect as a job. And job has different status in its lifecycle.  
![lifecycle](design/redirect_job_lifecycle.png)  
    
##Setup
* Clone project.  
..```bash
git clone https://github.com/jc1518/Autosam.git
```
* Install dependencies. 
- Cloudlets python module requires [edgegrid](https://github.com/akamai-open/AkamaiOPEN-edgegrid-python)
```bash
pip install edgegrid-python
```
- jq 
```bash
sudo apt-get -y install jq
or 
sudo yum -y install jq
``` 
* Create a AWS DynamoDB table for storing your job status.  

* Create Cloudlets configs and associte them to properties. Ensure you follow a good naming convention. e.g www.jackiechen.org use www_jackiechen_prod as the Cloudlets config name. If you do it different, you have to update line 200 in autosam_v2.sh to fit your case.
```bash
POLICYNAME=$(echo "$JOB" | cut -d' ' -f1 | cut -d'/' -f3 | cut -d'.' -f1-2 | t    r '.' '_')"_prod"
```      
* Setup your credentials in the [config](config) file, you need credentials for both Cloudlets API and AWS DynamoDB API calls. Also replace sample value with your Akamai Group ID, email address, sites ... 

##Usage
Autosam supports two methods of submitting redirect jobs.
* Slack bot
This requires to create a hubot and integrate it into Slack. The code can be found in myHubot repo. [lib/autosam.js](https://github.com/jc1518/myhubot/blob/master/lib/autosam.js) and [scripts/autosam.js](https://github.com/jc1518/myhubot/blob/master/scripts/autosam.js)
![autosam_bot](design/autosam_bot.png)

* Text file
This a simple mode, just add all your redirects in a text file, one redirect per line. Then give it to autosam to process.
```bash
./autosam_v2.sh <file>
```  
##Redirect types
Autosam supports both basic redirects and URL with query string. This can be extended to support more types in the [Cloudlets module](https://github.com/jc1518/Autosam/blob/master/Cloudlets/__init__.py)



