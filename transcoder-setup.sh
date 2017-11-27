#!/bin/sh

#
# Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Change this if you want to use a specific AWS CLI profile.
profile="default"

hubProjectId=$1
rolesTemplateFilename="cloudformation-roles.yml"
rolesStackName="VideoTranscoderRolesStack"
lambdaTemplateFilename="cloudformation-lambda.yml"
lambdaStackName="VideoTranscoderLambdaStack"

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

echo "Mobile Hub Project Details :\n${projectDetails}\n"

echo "Parsing for \"userfiles\" Amazon S3 bucket..."
cmd="jq -r '.details.resources[] .name | match(\".*-userfiles-.*\").string'"
echo "\nEXECUTE> echo ...projectdetails... | ${cmd}"
userFilesBucket=`echo ${projectDetails} | jq -r '.details.resources[] .name | match(".*-userfiles-.*").string'`

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to find User Data Storage S3 bucket in project. Please make sure the User Data Storage feature is configured.\n"
  exit -1
fi

echo "\nUser Data Storage S3 Bucket : ${userFilesBucket}\n"

echo "Parsing for \"hosting\" Amazon S3 bucket..."
cmd="jq -r '.details.resources[] .name | match(\".*-hosting-.*\").string'"
echo "\nEXECUTE> echo ...projectdetails... | ${cmd}"
hostingBucket=`echo ${projectDetails} | jq -r '.details.resources[] .name | match(".*-hosting-.*").string'`

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to find Hosting & Streaming S3 bucket in project. Please make sure the Hosting & Streaming feature is configured.\n"
  exit -1
fi

echo "\nHosting S3 Bucket : ${hostingBucket}\n"

echo "Parsing for \"deployments\" Amazon S3 bucket..."
cmd="jq -r '.details.resources[] .name | match(\".*-deployments-.*\").string'"
echo "\nEXECUTE> echo ...projectdetails... | ${cmd}"
deploymentsBucket=`echo ${projectDetails} | jq -r '.details.resources[] .name | match(".*-deployments-.*").string'`

echo "\nDeployments S3 Bucket : ${deploymentsBucket}\n"

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to find Deployments S3 bucket in project.\n"
  exit -1
fi

echo "Copy AWS CloudFormation template to S3..."
cmd="aws --profile ${profile} s3 cp ./${rolesTemplateFilename} s3://${deploymentsBucket} --acl public-read"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy file to S3.\n"
  exit -1
fi

echo "\nAWS CloudFormation Template uploaded OK.\n"

echo "Checking for existing AWS CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation describe-stacks --stack-name ${rolesStackName}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -eq 0 ]; then
  echo "\nOld stack exists. Removing..."
  cmd="aws --profile ${profile} cloudformation delete-stack --stack-name ${rolesStackName}"
  echo "\nEXECUTE> ${cmd}"
  ${cmd}

  echo "\nWaiting for CloudFormation Stack..."
  cmd="aws --profile ${profile} cloudformation wait stack-delete-complete --stack-name ${rolesStackName}"
  echo "\nEXECUTE> ${cmd}"
  ${cmd}

  if [ $? -ne 0 ]; then
    echo "\nERROR: Unable to delete AWS CloudFormation stack.\n"
    exit -1
  fi
fi

now=`date "+%Y%m%d%H%M%S"`
pipelineRoleName=TranscoderPipelineRole${now}
lambdaRoleName=TranscoderLambdaExecutionRole${now}

echo "\nDeploying AWS CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation create-stack \
--stack-name ${rolesStackName} \
--template-url https://s3.amazonaws.com/${deploymentsBucket}/${rolesTemplateFilename} \
--capabilities CAPABILITY_NAMED_IAM \
--parameters ParameterKey=UserFilesS3BucketPattern,ParameterValue=arn:aws:s3:::${userFilesBucket}/* \
ParameterKey=HostingS3BucketPattern,ParameterValue=arn:aws:s3:::${hostingBucket}/* \
ParameterKey=HostingS3Bucket,ParameterValue=arn:aws:s3:::${hostingBucket} \
ParameterKey=TranscoderPipelineRoleName,ParameterValue=${pipelineRoleName} \
ParameterKey=LambdaExecutionRoleName,ParameterValue=${lambdaRoleName} "

echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to deploy AWS CloudFormation stack.\n"
  exit -1
fi

echo "\nWaiting for CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation wait stack-create-complete --stack-name ${rolesStackName}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to create AWS CloudFormation stack.\n"
  exit -1
fi

attempts=0
max=10

transcoderRoleARN=""
lambdaExecutionRoleARN=""

while [ ${attempts} -lt ${max} ]
do
  attempts=$((attempts+1))
  cmd="aws --profile ${profile} cloudformation describe-stacks --stack-name ${rolesStackName} | jq -r '.Stacks[].Outputs[0].OutputValue'"
  echo "\nEXECUTE> ${cmd}"
  transcoderRoleARN=`aws --profile ${profile} cloudformation describe-stacks --stack-name ${rolesStackName} | jq -r '.Stacks[].Outputs[0].OutputValue'`
  lambdaExecutionRoleARN=`aws --profile ${profile} cloudformation describe-stacks --stack-name ${rolesStackName} | jq -r '.Stacks[].Outputs[1].OutputValue'`

  if [ "${transcoderRoleARN}" != "" ] \
       && [ "${transcoderRoleARN}" != "null" ] \
       && [ "${lambdaExecutionRoleARN}" != "" ] \
       && [ "${lambdaExecutionRoleARN}" != "null" ]
  then
    echo "Transcoder Pipeline Role ARN : ${transcoderRoleARN}"
    echo "Lambda Execution Role ARN : ${lambdaExecutionRoleARN}"

    break;
  fi

  sleep 10
done

if [ ${attempts} -ge ${max} ]
then
  echo "\nERROR: Exceeded maximum attempts to get role ARN from AWS CloudFormation stack. Verify stack deployed successfully.\n"
  exit -1
fi

echo "\nLooking for existing pipelines..."

cmd="aws --profile ${profile} elastictranscoder list-pipelines"
echo "\nEXECUTE> ${cmd}"
pipelines=`${cmd}`

echo "${pipelines}\n"

echo "Parsing for \"VideoTranscoderPipeline\"..."
cmd="jq -r '.Pipelines[] .Name | match(\".*VideoTranscoderPipeline.*\").string'"
echo "\nEXECUTE> echo ...pipelines... | ${cmd}"
pipelineId=`echo ${pipelines} | jq '.Pipelines[] | select(."Name"=="VideoTranscoderPipeline").Id'`

if [ "${pipelineId}" != "" ]; then
  pipelineId="${pipelineId//\"}"
  echo "\nDeleting existing Elastic Transcoder pipeline : ${pipelineId}"

  cmd="aws --profile ${profile} elastictranscoder delete-pipeline --id ${pipelineId}"
  echo "\nEXECUTE> ${cmd}"
  ${cmd}

  if [ $? -ne 0 ]; then
    echo "\nERROR: Unable to delete existing Elastic Transcoder pipeline.\n"
    exit -1
  fi
fi

echo "\nCreating Amazon Elastic Transcoder Pipeline..."

cmd="aws --profile ${profile} elastictranscoder create-pipeline \
--name VideoTranscoderPipeline \
--input-bucket ${userFilesBucket} \
--output-bucket ${hostingBucket} \
--role ${transcoderRoleARN}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to create Elastic Transcoder pipeline.\n"
  exit -1
fi

cmd="aws --profile ${profile} elastictranscoder list-pipelines"
echo "\nEXECUTE> ${cmd}"
pipelines=`${cmd}`

echo "${pipelines}\n"

echo "Parsing for \"VideoTranscoderPipeline\"..."
cmd="jq -r '.Pipelines[] .Name | match(\".*VideoTranscoderPipeline.*\").string'"
echo "\nEXECUTE> echo ...pipelines... | ${cmd}"
pipelineId=`echo ${pipelines} | jq '.Pipelines[] | select(."Name"=="VideoTranscoderPipeline").Id'`

if [ ${pipelineId} = "" ]; then
  echo "\nERROR: Unable to find Elastic Transcoder pipeline.\n"
  exit -1
fi

echo "\nCopy AWS CloudFormation template to S3..."
cmd="aws --profile ${profile} s3 cp ${lambdaTemplateFilename} s3://${deploymentsBucket} --acl public-read"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy file to S3.\n"
  exit -1
fi

zip lambda.zip index.js

echo "\nCopy AWS Lambda code to S3..."
cmd="aws --profile ${profile} s3 cp lambda.zip s3://${deploymentsBucket} --acl public-read"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy file to S3.\n"
  exit -1
fi

echo "\nChecking for existing AWS CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation describe-stacks --stack-name ${lambdaStackName}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -eq 0 ]; then
  echo "\nOld stack exists. Removing..."
  cmd="aws --profile ${profile} cloudformation delete-stack --stack-name ${lambdaStackName}"
  echo "\nEXECUTE> ${cmd}"
  ${cmd}

  echo "\nWaiting for CloudFormation Stack..."
  cmd="aws --profile ${profile} cloudformation wait stack-delete-complete --stack-name ${lambdaStackName}"
  echo "\nEXECUTE> ${cmd}"
  ${cmd}

  if [ $? -ne 0 ]; then
    echo "\nERROR: Unable to delete AWS CloudFormation stack.\n"
    exit -1
  fi
fi

echo "\nDeploying AWS CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation create-stack \
--stack-name ${lambdaStackName} \
--template-url https://s3.amazonaws.com/${deploymentsBucket}/${lambdaTemplateFilename} \
--capabilities CAPABILITY_NAMED_IAM \
--parameters ParameterKey=DeploymentsS3Bucket,ParameterValue=${deploymentsBucket} \
ParameterKey=LambdaExecutionRoleARN,ParameterValue=${lambdaExecutionRoleARN} \
ParameterKey=TranscoderPipelineID,ParameterValue=${pipelineId} \
ParameterKey=UserFilesS3Bucket,ParameterValue=${userFilesBucket}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to deploy AWS CloudFormation stack.\n"
  exit -1
fi

echo "\nWaiting for CloudFormation Stack..."
cmd="aws --profile ${profile} cloudformation wait stack-create-complete --stack-name ${lambdaStackName}"
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to create AWS CloudFormation stack.\n"
  exit -1
fi

echo "\nGetting Lambda ARN..."
cmd="aws --profile ${profile} cloudformation describe-stacks --stack-name ${lambdaStackName} --query \"Stacks[0].Outputs[0].OutputValue\""
echo "\nEXECUTE> ${cmd}"
lambda_arn=`aws --profile ${profile} cloudformation describe-stacks --stack-name ${lambdaStackName} --query 'Stacks[0].Outputs[0].OutputValue'`

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to get AWS Lambda ARN from CloudFormation stack.\n"
  exit -1
fi

echo "\nWriting S3 Notification JSON..."
echo "{\n\
  \"LambdaFunctionConfigurations\":\n\
    [\n\
      {\n\
        \"Id\": \"VideoTranscodingTrigger-mp4\",\n\
        \"Filter\": {\n\
          \"Key\": {\n\
            \"FilterRules\": [\n\
              {\n\
                \"Name\": \"suffix\",\n\
                \"Value\": \"mp4\"\n\
              }\n\
            ]\n\
          }\n\
        },\n\
        \"LambdaFunctionArn\": ${lambda_arn},\n\
        \"Events\": [\"s3:ObjectCreated:*\"]\n\
      },\n\
      {\n\
        \"Id\": \"VideoTranscodingTrigger-mov\",\n\
        \"Filter\": {\n\
          \"Key\": {\n\
            \"FilterRules\": [\n\
              {\n\
                \"Name\": \"suffix\",\n\
                \"Value\": \"mov\"\n\
              }\n\
            ]\n\
          }\n\
        },\n\
        \"LambdaFunctionArn\": ${lambda_arn},\n\
        \"Events\": [\"s3:ObjectCreated:*\"]\n\
      }\n\
    ]\n\
  }" > s3notification.json

echo "\nS3 Notification (event trigger for AWS Lambda) settings..."
cat s3notification.json

cmd="aws --profile ${profile} s3api put-bucket-notification-configuration --bucket ${userFilesBucket} --notification-configuration file://s3notification.json"
echo "\nSetting S3 upload notification trigger..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to setup S3 notification.\n"
  exit -1
fi

cmd="aws --profile ${profile} mobile export-bundle --project-id ${hubProjectId} --platform ANDROID --bundle-id app-config --query downloadUrl"

echo "\nFetching Mobile App configuration URL..."
echo "\nEXECUTE> ${cmd}"
appConfigURL=`${cmd}`
appConfigURL=${appConfigURL//\"}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to export app-config bundle.\n"
  exit -1
fi

echo "\nApp Configuration Bundle URL : ${appConfigURL}"

cmd="wget -O awsconfiguration.zip ${appConfigURL}"

echo "\nDownloading Mobile App configuration bundle..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to download Mobile App configuration bundle.\n"
  exit -1
fi

cmd="unzip -o awsconfiguration.zip"

echo "\nUnzipping Mobile App configuration bundle..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to unzip Mobile App configuration bundle.\n"
  exit -1
fi

cmd="cp awsconfiguration.json android/VideoDemo/app/src/main/res/raw/awsconfiguration.json"

echo "\nCopying Mobile App configuration to demo app folder..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy Mobile App configuration JSON to demo app folder.\n"
  exit -1
fi

cmd="aws --profile ${profile} mobile export-bundle --project-id ${hubProjectId} --platform JAVASCRIPT --bundle-id app-config --query downloadUrl"

echo "\nFetching Website configuration URL..."
echo "\nEXECUTE> ${cmd}"
webConfigURL=`${cmd}`
webConfigURL=${webConfigURL//\"}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to export app-config bundle.\n"
  exit -1
fi

echo "\nWebsite Configuration Bundle URL : ${webConfigURL}"

cmd="wget -O aws-exports.zip ${webConfigURL}"

echo "\nDownloading Website configuration bundle..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to download Website configuration bundle.\n"
  exit -1
fi

cmd="unzip -o aws-exports.zip"

echo "\nUnzipping Website configuration bundle..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to unzip Website configuration bundle.\n"
  exit -1
fi

cmd="cp aws-config.js website/app/scripts/aws-config.js"

echo "\nCopying Website configuration to demo website folder..."
echo "\nEXECUTE> ${cmd}"
${cmd}

if [ $? -ne 0 ]; then
  echo "\nERROR: Unable to copy Website configuration to demo website folder.\n"
  exit -1
fi

cmd="aws --profile ${profile} s3 cp ./example-video.mp4 s3://${userFilesBucket}/uploads/"
echo "\nTo use AWS CLI to copy a file to S3 bucket...\n${cmd}"

echo "\nOr, use the following script to copy a file to S3...\n./upload.sh ./example-video.mp4"
echo "aws --profile ${profile} s3 cp \$1 s3://${userFilesBucket}/uploads/" > upload.sh
chmod a+x upload.sh

echo "\nDONE -- SUCCESS\n"

consoleUrl="https://console.aws.amazon.com/mobilehub/home?#/${hubProjectId}/build/cdn"
open ${consoleUrl}
