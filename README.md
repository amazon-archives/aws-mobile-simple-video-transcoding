# AWS Mobile Hub Extension - Simple Video Transcoding

This project includes extensions to an AWS Mobile Hub project. These add capabilities to your Mobile App or Website.

This extension adds automatic video transcoding of uploaded videos to adaptive multi-bitrate formats. When your mobile app users upload video files to the "userfiles" Amazon S3 bucket of your AWS Mobile Hub backend, the files will automatically be transcoded to HLS (HTTP Live Streaming) format, and they will be placed in the "hosting" Amazon S3 bucket. Your Amazon CloudFront distribution will stream the video files in the downlink direction to devices using adaptive multi-bitrate protocols in order to reduce bandwidth, reduce buffering, and optimize the user experience in watching the videos.

![image](readme-images/architecture.png?raw=true)

This project includes a demo Android Mobile App project which uploads video files and plays the transcoded videos and a demo website which also plays the video files.

## Requirements

* Mac OSX - The extension setup script was built for Mac OSX. It uses 'jq' to parse JSON output from the AWS CLI. It may work on other platforms with minor modification.
* AWS Account - If you do not already have an account, following any of the AWS management console links below will prompt you to setup an account.
* [JQ](https://stedolan.github.io/jq/) - for parsing JSON results from AWS CLI
* [NPM](https://www.npmjs.com/) - for building demo website
* [Gulp](https://gulpjs.com/) - for building demo website
* [Bower](https://bower.io/) - for building demo website

## Steps

* Install AWS CLI
* Setup Permissions
* Create AWS Mobile Hub Project
* Install Mobile Backend Extension
* Build and Deploy Website
* Build Mobile App
* Upload a Video

### 1. Install AWS CLI
The setup script in this project uses the AWS CLI (Universal Command Line) tool. You can find installation instructions here:
* [AWS CLI Installation Instructions - https://github.com/aws/aws-cli](https://github.com/aws/aws-cli)

To verify if the AWS CLI is setup properly, you can run a command like this:

    aws --version
It should output something like this.

    aws-cli/1.11.156 Python/2.7.10 Darwin/15.6.0 botocore/1.7.14

### 2. Setup Permissions

#### Create Custom IAM Policy

Launch a browser window with the following link:
- [AWS IAM - Create Custom Policy - https://console.aws.amazon.com/iam/home?region=us-east-1#/policies$new](https://console.aws.amazon.com/iam/home?region=us-east-1#/policies$new)

Select 'Create Your Own Policy'.

---
![image](readme-images/iam-create-policy.png?raw=true)

---

Type a Policy Name and Description and then input the following Policy Document:

    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*"
            ],
            "Resource": [
                "arn:aws:cloudformation:*:*:stack/VideoTranscoderLambdaStack/*",
                "arn:aws:cloudformation:*:*:stack/VideoTranscoderRolesStack/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::*-mobilehub-*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutBucketNotification"
            ],
            "Resource": "arn:aws:s3:::*-mobilehub-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:AttachRolePolicy",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:DeleteRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PassRole",
                "iam:PutRolePolicy"
            ],
            "Resource": [
                "arn:aws:iam::*:role/TranscoderPipelineRole*",
                "arn:aws:iam::*:role/TranscoderLambdaExecutionRole*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:*"
            ],
            "Resource": "arn:aws:lambda:*:*:function:TranscoderJobSubmitter"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elastictranscoder:*"
            ],
            "Resource": "*"
        }
    ]
    }

This policy is included in the repository as [custom-policy.json](./custom-policy.json).

Click 'Validate Policy'. If everything is OK, then click 'Create Policy'.

---
![image](readme-images/iam-edit-policy.png?raw=true)

---

#### Create AWS IAM (Identity & Access Management) User

Launch a browser window with the following link:
- [AWS IAM - Create User -  https://console.aws.amazon.com/iam/home?region=us-east-1#/users$new?step=details](https://console.aws.amazon.com/iam/home?region=us-east-1#/users$new?step=details)

---
![image](readme-images/iam-create-user.png?raw=true)

---

Enter a name for the user, select programmatic access and click 'Next: Permissions'

#### Add Required IAM Policies

Select 'Attach existing policies directly'. Check the checkbox for the following managed policies.
- DeploymentPolicy (or whatever you called your custom policy in the 'Create Custom IAM Policy' step)
- AWSMobileHub_FullAccess
- IAMReadOnlyAccess

---
![image](readme-images/iam-add-policies.png?raw=true)

---

#### Download Credentials

Click the 'Show' link under 'Secret access key'. Copy the Access key ID and Secret access key to a file or click the 'Download .csv' link to download the values to your Downloads folder.

#### Install Credentials in AWS CLI

    aws configure
    AWS Access Key ID: <access key ID from previous step>
    AWS Secret Access Key: <secret access key from previous step>
    Default region: us-east-1
    Default output format [None]: <return>

#### Verify AWS CLI permissions

This command will show you which IAM user you are using when you make calls to AWS services from the AWS CLI. It is the AWS CLI equivalent of 'whoami'.

    aws iam get-user

You should see something like this:

    {
        "User": {
            "UserName": "AWS-CLI-ACHUD",
            "Path": "/",
            "CreateDate": "2015-10-28T15:52:47Z",
            "UserId": "AIDAJ7A5TZOVP5A4DQ7OE",
            "Arn": "arn:aws:iam::207859480101:user/AWS-CLI-ACHUD"
        }
    }

#### AWS CLI Multiple Profiles

The AWS CLI allows you to configure multiple profiles for different IAM users. If you already have some AWS CLI profiles, you can rename them by editing the ~/.aws/credentials file. The instructions here use your 'default' profile. In general, you can run any AWS CLI command with a specific profile, like this:

    aws --profile some-other-profile-name iam get-user

### 3. Create an AWS Mobile Hub Project

Choose a project name and region. The following command will create the project and enable User Sign-in, User Data Storage, and Hosting & Streaming in the AWS Mobile Hub Project.

Note: Alternatively, you can run the 'create-project.sh' script contained in this repository.

        aws mobile create-project --snapshot-id yvsue7ksnvy9fo --name "Video Transcoder" --project-region us-east-1

The command will output information about your project.

        {
          "details": {
          "name": "Video Transcoder",
          "projectId": "abc1234-ce7d-4093-b630-276a8505da3d",
          "region": "us-east-1",
          "state": "NORMAL",
          "consoleUrl": "https://console.aws.amazon.com/mobilehub/home#/abc1234-ce7d-4093-b630-276a8505da3d/build",
          "lastUpdatedDate": 1507827668.767,
          "createdDate": 1507827668.767,
          ...
If this is your first time using AWS Mobile Hub, you may see an error like this:

        An error occurred (UnauthorizedException) when calling the
        CreateProject operation: You must first enable Mobile Hub
        in your account before using the service.

        Visit the below address to get started:
        https://console.aws.amazon.com/mobilehub/home?#/activaterole/
If this happens, simply follow link and click "Yes, activate role" to enable AWS Mobile Hub in your AWS account.

---
![image](readme-images/servicerole.png?raw=true)

---

#### (Optional) Examine your AWS Mobile Hub project in the console.

Take the "consoleUrl" value from the previous command and open it in a browser.

        open https://console.aws.amazon.com/mobilehub/home#/abc1234-ce7d-4093-b630-276a8505da3d/build

#### Learn about your AWS Resources

Your AWS Mobile Hub project created a number of AWS resources and configured them to work together. You can view these resources by using the "Resources" link in the Mobile Hub console (previous command). Here are some of the more important resources that were created.

- Amazon Cognito User Pool - Your user pool allows your app users to authenticate (sign-in) to your mobile app. It also provides Multi-Factor Authentication (MFA) which uses a secondary channel, such as Email or SMS to verify the user's identity.

- Amazon Cognito Identity Pool - Your identity pool federates user identities across all your identity providers, such as your user pool. You may enable other identity providers, such as Facebook, Google, or Active Directory (using SAML). The identity pool links these identities together, if for example, you allow your users to sign-in with more than one provider. It also provides credentials to your users with permissions provided by your IAM roles.

- Amazon Identity & Access Management (IAM) Roles - Each role provides a set of permissions which are encapsulated in the attached IAM policies.
  - Unauth Role - This role is assumed by users of your app who are not signed in (guess access). It provides limited permissions for things like reporting analytics metrics.
  - Auth Role - This role is assumed by your signed-in users. It provides fine-grained access to resources, e.g., each user has their own folders in S3.
  - Lambda Execution Role - This role is assumed by AWS Lambda when your functions execute. It provides your lambda with the permissions it needs to access your resources, e.g., to read files from S3.


- Amazon Identity & Access Management (IAM) policies - Each IAM role has a number of policies attached to it. These policies provide permissions to access AWS resources and in some cases, they provide fine-grained access control, such as restricting write access to only the specific user's folders in S3.

- Amazon Simple Storage Service (S3) Buckets - Each S3 bucket is a repository of files in the cloud.
  - UserFiles - The UserFiles S3 bucket in an AWS Mobile Hub project provides specific behaviors in terms of access control. It contains the following folders:
    - uploads/ - Write by any app user. Readable by no one.
    - public/ - Readable/Writeable by any app user.
    - private/_user-identity_/ - Each user has their own private folder which is only readable/writeable by that user.
    - protected/_user-identity_/ - Each user has their own protected folder which is only writeable by that user, but may be read by any app user.

  - Hosting - The Hosting S3 bucket is a publicly accessible repository where you make files available for website hosting. App users have no permissions to write to this folder; they can only read.

  - Deployments - The Deployments S3 bucket is used to deploy build artifacts to AWS Lambda and Amazon API Gateway.

- Amazon CloudFront Distribution - Your CloudFront distribution is an edge-cache on top of your Hosting S3 bucket. It provides fast access to cached content from the AWS global POP (points of presence) locations around the globe. It also has some built-in media streaming capabilities.

#### (Optional) List your AWS Mobile Hub project details.

        aws mobile describe-project --project-id abc1234-ce7d-4093-b630-276a8505da3d
        {
          "details": {
          "name": "Video Transcoder",
          "projectId": "abc1234-ce7d-4093-b630-276a8505da3d",
          "region": "us-east-1",
          "state": "NORMAL",
          "consoleUrl": "https://console.aws.amazon.com/mobilehub/home#/abc1234-ce7d-4093-b630-276a8505da3d/build",
          "lastUpdatedDate": 1507827668.767,
          "createdDate": 1507827668.767,
          ...

### 4. Install Mobile Backend Extension

#### Run the extension setup script

        chmod a+x ./transcoder-setup.sh
        ./transcoder-setup.sh

The script will show you the list of AWS Mobile Hub projects you have available.

    ...
    {
      "projects":
      [
        {
          "projectId": "abc123-801e-407b-a460-700eb4bc92cb",
          "name": "Video Transcoder"
        }
      ]
    }

You can also list projects with this command.

    aws mobile list-projects

#### Run the extension setup script with your Project ID

Select the project you want to add the extension to and pass that into the script.

    ./transcoder-setup.sh abc123-801e-407b-a460-700eb4bc92cb

The script will execute a number of commands using the AWS CLI. Each command it executes is printed with "EXECUTE>" shown as a prefix, like this.

    EXECUTE> aws cloudformation describe-stacks --stack-name VideoTranscoderRolesStack

This will setup all the backend resources you need. When it is done, you should see this.

    ...
    DONE -- SUCCESS

This will launch a browser window on the AWS Mobile Hub Hosting and Streaming feature page of your project, which contains links to launch your hosted website for both your (non-cached) Amazon S3 domain and (cached) Amazon CloudFront domain.

---
![image](readme-images/hosting-console.png?raw=true)

---

This script also downloaded and install the following configuration files for your project.

- __website/app/scripts/aws-config.js__ - Provides the demo website with configuration information about your project resources.

- __android/VideoDemo/app/src/main/res/raw/awsconfiguration.json__ - Provides the demo Android app with configuration information about your project resources.

#### (Optional) Examine your AWS CloudFormation stacks

If you'd like to examine your AWS CloudFormation stacks, you can follow this link:
- [AWS CloudFormation Console - https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks?filter=active](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks?filter=active)

---
![image](readme-images/cloudformation-console.png?raw=true)

---
#### (Optional) Check the status of your Amazon ElasticTranscoder Jobs

If you'd like to see the status of your video transcoding jobs, you can follow this link:
- [Amazon Elastic Transcoder Console - https://console.aws.amazon.com/elastictranscoder/home?region=us-east-1#pipelines:](https://console.aws.amazon.com/elastictranscoder/home?region=us-east-1#pipelines:)

---
![image](readme-images/transcoder-console.png?raw=true)

---
#### (Optional) Check your AWS Lambda function logs

If you'd like to see the logs for your AWS Lambda function which kicks off the transcoder jobs, you can follow this link:
- [AWS CloudWatch Logs - https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logEventViewer:group=/aws/lambda/TranscoderJobSubmitter](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logEventViewer:group=/aws/lambda/TranscoderJobSubmitter)

#### (Optional) Edit your AWS Lambda FunctionName

If you'd like to edit your AWS Lambda function, you can follow this link:
- [AWS Lambda Console - https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/TranscoderJobSubmitter?tab=configuration](https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/TranscoderJobSubmitter?tab=configuration)

---
![image](readme-images/lambda-console.png?raw=true)

---


### 5. Build and Deploy Website

#### Install NPM packages

    cd website
    npm install --save-dev
    node_modules/.bin/bower install

#### Build website

    node_modules/.bin/gulp

#### Publish website distribution

    chmod a+x ./publish.sh
    ./publish.sh

The script will show you the list of AWS Mobile Hub projects if you don't specify one.

    ...
    {
      "projects":
      [
        {
          "projectId": "abc123-801e-407b-a460-700eb4bc92cb",
          "name": "Video Transcoder"
        }
      ]
    }

You can also list projects with this command.

    aws mobile list-projects

Run the publish script with your Project ID.

    ./publish.sh abc123-801e-407b-a460-700eb4bc92cb

This will build your website using Gulp and copy the distribution (dist folder) contents into your project's 'hosting' Amazon S3 bucket.

#### Restrict CORS - Cross-Origin Resource Sharing

This project creates an Amazon S3 bucket which you can use to host assets for a website. The bucket is created with a wildcarded CORS policy. This policy removes any restrictions from scripts running in the website accessing contents in other domains.

    <?xml version="1.0" encoding="UTF-8"?>
    <CORSConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <CORSRule>
      <AllowedOrigin>*</AllowedOrigin>
      <AllowedMethod>HEAD</AllowedMethod>
      <AllowedMethod>GET</AllowedMethod>
      <AllowedMethod>PUT</AllowedMethod>
      <AllowedMethod>POST</AllowedMethod>
      <AllowedMethod>DELETE</AllowedMethod>
      <MaxAgeSeconds>3000</MaxAgeSeconds>
      <ExposeHeader>x-amz-server-side-encryption</ExposeHeader>
      <ExposeHeader>x-amz-request-id</ExposeHeader>
      <ExposeHeader>x-amz-id-2</ExposeHeader>
      <AllowedHeader>*</AllowedHeader>
    </CORSRule>
    </CORSConfiguration>

If you plan to use this to host a production website, then you should scope this policy down to allow only the domains and methods that your site requires. You can edit this policy in the Amazon S3 console under "Permissions -> CORS configuration". Simply clone the "*" domain rule once for each domain your website uses and remove any methods you do not want to allow.

### 6. Build Mobile App

#### Open the Project
Start [Android Studio](https://developer.android.com/studio/index.html). Choose "Import project (Gradle, Eclipse ADT, etc.)" and select the "android/VideoDemo/build.gradle" file.

#### Run the App

Click the play button to launch the app in the Android Emulator. The app will prompt you to create a user account and then sign in with the user account. This uses your Amazon Cognito User Pool which was created as part of your AWS Mobile Hub project.

Once you create an account, you can see details of the created user in the Amazon Cognito console.
* [Amazon Cognito User Pools Console - https://console.aws.amazon.com/cognito/users/?](https://console.aws.amazon.com/cognito/users/?)

---
![image](readme-images/app-signin.png?raw=true)

---

When you first start the app, it will attempt to read the index of available video content from the 'hosting' Amazon S3 bucket that was created as part of your AWS Mobile Hub project. Initially, there is no content, so you will see a message that says 'CONTENT INDEX IS NOT AVAILABLE'. It will look for an update to the content index in S3 every 30 seconds.

---
![image](readme-images/app-start.png?raw=true)

---

### Upload a Video

Click the '+' button to capture a video file to upload. This will upload the file to the 'userfiles' Amazon S3 bucket. It will trigger the AWS Lambda function that creates a job in Amazon Elastic Transcoder. The lambda function will also create a new record in the content index file (content/index.json) in your 'hosting' Amazon S3 bucket. The app will read the new index file and play the new video file after it has been transcoded to HLS (HTTP Live Streaming) format.

Alternatively, you can use the generated 'upload.sh' script to upload a video file to your 'userfiles' S3 bucket like this...

    ./upload.sh example-video.mp4

## Talk to Us

* [AWS Mobile Developer Forum - https://forums.aws.amazon.com/forum.jspa?forumID=88](https://forums.aws.amazon.com/forum.jspa?forumID=88)

## Author

Andrew Chud - Amazon Web Services

## License

This library is licensed under the Apache 2.0 License. See the [**LICENSE**](./LICENSE) file for more info.

## Attribution

This project makes use of the following projects which are available under Apache 2.0 license.
- [Hls.js - https://github.com/video-dev/hls.js/](https://github.com/video-dev/hls.js/)
- [ExoMedia - https://github.com/brianwernick/ExoMedia](https://github.com/brianwernick/ExoMedia)
