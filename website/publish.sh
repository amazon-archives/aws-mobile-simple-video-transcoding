#!/bin/sh

# Change this if you want to use a specific AWS CLI profile.
profile="default"

hubProjectId=$1

echo "\nChecking AWS CLI installation..."
cmd="aws --version"
echo "\nEXECUTE> ${cmd}\n"
`${cmd}`

if [ $? -ne 0 ]; then
  echo "\nERROR: AWS CLI is not installed.\n\nPlease install it using instructions here:\nhttp://docs.aws.amazon.com/cli/latest/userguide/installing.html\n"
  exit -1
fi

echo "\nAWS CLI is installed."

if [ "" = "$1" ]; then
  echo "\nERROR: You must specify an AWS Mobile Hub project ID.\n\nListing Mobile Hub projects...";
  cmd="aws --profile ${profile} mobile list-projects"
  echo "\nEXECUTE> ${cmd}\n"
  ${cmd}

  if [ $? -ne 0 ]; then
    echo "\nERROR: Unable to list projects.\n"
  fi

  exit -1;
fi

echo "\nMobile Hub Project ID : ${hubProjectId}"

cmd="aws --profile ${profile} mobile describe-project --project-id ${hubProjectId}"
echo "\nEXECUTE> ${cmd}\n"
projectDetails=`${cmd}`

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to fetch project details.\n"
  exit -1
fi

# echo "Mobile Hub Project Details :\n${projectDetails}\n"

echo "Parsing for \"hosting\" Amazon S3 bucket..."
cmd="jq -r '.details.resources[] .name | match(\".*-hosting-.*\").string'"
echo "\nEXECUTE> echo ...projectdetails... | ${cmd}"
hostingBucket=`echo ${projectDetails} | jq -r '.details.resources[] .name | match(".*-hosting-.*").string'`

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to find Hosting S3 bucket in project. Please make sure the User Data Storage feature is configured.\n"
  exit -1
fi

echo "\nHosting S3 Bucket : ${hostingBucket}\n"

echo "Copy Files to S3..."
cmd="aws --profile ${profile} s3 cp --recursive ./dist s3://${hostingBucket} --acl public-read"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy files to S3.\n"
  exit -1
fi

echo "\nDONE -- SUCCESS\n"

consoleUrl="https://console.aws.amazon.com/mobilehub/home?#/${hubProjectId}/build/cdn"
open ${consoleUrl}
