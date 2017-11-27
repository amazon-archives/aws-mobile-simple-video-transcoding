/*
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
*/
const aws = require('aws-sdk');
const elastictranscoder = new aws.ElasticTranscoder({apiVersion: '2012-09-25'});
const s3 = new aws.S3(2006-03-01);

// Constants
const PIPELINE_ID = process.env.PIPELINE_ID;
const SEGMENT_DURATION = '5'; // seconds
const OUTPUT_FOLDER    = 'content/';
const CONTENT_FOLDERS_REGEXP = /content\/(.+)\/.+/;
const CONTENT_INDEX    = 'index.json';
const PLAYLIST_NAME    = 'default';

exports.handler = function(event, context) {
    console.log('Received S3 Event:');
    console.log(JSON.stringify(event, 2));

    const bucket = event.Records[0].s3.bucket.name;
    const key = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, ' '));
    const params = {
        Bucket: bucket,
        Key: key
    };

    s3.headObject(params, function(err, data) {

        if (err) {
            console.error(err, err.stack);
            context.fail('Error fetching object metadata: ' + err);
            return;
        }

        console.log('S3 Object HEAD Result:');
        console.log(JSON.stringify(data, 2));

        const metadata = data.Metadata;
        metadata.userIp = event.Records[0].requestParameters.sourceIPAddress;
        metadata.userPrincipal = event.Records[0].userIdentity.principalId;

        const videoId =
            String(new Date().getTime()) +
            '-' +
            event.Records[0].userIdentity.principalId.split(':')[1];
        const outputPrefix = OUTPUT_FOLDER + videoId + '/';

        console.log('Allocated Video ID : ' + videoId);

        var request =
            {"Inputs":[{"Key":key}],
             "OutputKeyPrefix":outputPrefix,
             "Outputs":[
               {"Key":'160k',
                "PresetId":'1351620000001-200060',
                "SegmentDuration":SEGMENT_DURATION},
               {"Key":'400k',
                "PresetId":'1351620000001-200050',
                "SegmentDuration":SEGMENT_DURATION},
               {"Key":'600k',
                "PresetId":'1351620000001-200040',
                "SegmentDuration":SEGMENT_DURATION},
               {"Key":'1000k',
                "PresetId":'1351620000001-200030',
                "SegmentDuration":SEGMENT_DURATION},
               {"Key":'1500k',
                "PresetId":'1351620000001-200020',
                "SegmentDuration":SEGMENT_DURATION},
               {"Key":'2000k',
                "PresetId":'1351620000001-200010',
                "SegmentDuration":SEGMENT_DURATION}
             ],
             "Playlists":[{
                 "Format":"HLSv3",
                 "Name":PLAYLIST_NAME,
                 "OutputKeys":[
                   '160k',
                   '400k',
                   '600k',
                   '1000k',
                   '1500k',
                   '2000k'
                 ]
             }],
             "PipelineId":PIPELINE_ID,
             "UserMetadata":metadata};

        console.log('Elastic Transcoder Request:');
        console.log(JSON.stringify(request, 2));

        elastictranscoder.createJob(request, function (err, data) {
            if (err) {
                console.error(err, err.stack);
                context.fail(err);
                return;
            }

            console.log('Elastic Transcoder Job Data:');
            console.log(JSON.stringify(data, 2));

            // Construct the name of the 'hosting' bucket from the 'userfiles' bucket.
            const hostingBucket = bucket.replace(/-userfiles-/,'-hosting-');

            appendJobToContentIndex(hostingBucket, videoId, (err, data) => {
              if (err) {
                console.error(err, err.stack);
                context.fail(err);
                return;
              } else {
                console.log('OK');
                context.succeed(data);
              }
            });
        });
    });
};

// Re-writes the content list file with the list of available videos and
// this new video ID.
function appendJobToContentIndex(bucket, videoId, callback) {
  console.log('appendJobToContentIndex(' + videoId + ')');

  const fileList = [];

  listFilesFromS3(bucket, null, fileList, (err, data) => {
      if (err) {
          const message = 'Unable to list files in bucket ' + bucket + '. ' + err;
          console.error(message);
          callback(message);
          return;
      }

      const fileMap = {};

      fileList
        .filter(filename => {
          return filename.match(/content\/.+\//);
        })
        .map(filename => filename.replace(CONTENT_FOLDERS_REGEXP, '$1'))
        .forEach(filename => {
          fileMap[filename] = 1;
        });

      // Add latest video to the list
      fileMap[videoId] = 1;

      const newIndex = JSON.stringify(Object.keys(fileMap).sort().reverse());
      console.log('new index = ' + newIndex);

      var params = {
        Body: newIndex,
        Bucket: bucket,
        Key: OUTPUT_FOLDER + CONTENT_INDEX,
      };

      s3.putObject(params, callback);
  });
}

// List files in S3 bucket.
function listFilesFromS3(bucketName, marker, files, callback) {
  var params = {
    Bucket: bucketName
  };

  if (marker) {
    params.Marker = marker;
  }

  s3.listObjects(params, function(err, data) {
    if (err) {
      return callback(err);
    }

    data.Contents.forEach(file => {
        files.push(file.Key);
    });

    if (data.IsTruncated) {
      var length = data.Contents.length;
      var marker = data.Contents[length-1].Key;
      listFilesFromS3(bucketName, marker, files, callback);
    } else {
      return callback(undefined, files);
    }
  });
}
