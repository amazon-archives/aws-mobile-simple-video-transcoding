/*
 Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/
const CONTENTS_FOLDER = 'content/';
const PLAYLIST_FILENAME = '/default.m3u8';
const INDEX_FILENAME = 'index.json';
const LOOP_INTERVAL = 10000; // 10 seconds

var contents = [];
var hls;
var loadingContentId;
var playingContentId;
var autoPlay = true;

function bodyOnLoad() {
  doPollingLoopIteration();
  setInterval(doPollingLoopIteration, LOOP_INTERVAL);
}

function doPollingLoopIteration() {
  const contentZero = contents.length > 0 ? contents[0] : null;

  loadContentsIndex((err, data) => {

    if (err) {
      if (err.code && err.code.includes('NoSuchKey')) {
        console.log('No content index exists.');
        showError('CONTENT INDEX IS NOT AVAILABLE');
        return;
      }
      console.error(err);
      showError(err);
    } else {
      const latestContentId = contents[0];

      console.log('Latest Content ID = ' + latestContentId);
      console.log('Loading Content ID = ' + loadingContentId);
      console.log('Playing Content ID = ' + playingContentId);

      if (autoPlay && playingContentId !== latestContentId) {
        checkIfContentFileExists(latestContentId, (err, data) => {
          if (err) {
            console.log('Top content file does not exist.');
            showComingSoon('Next : ' + latestContentId);
          } else {
            console.log('Top content file exists. Loading...');
            loadVideo(latestContentId);
          }
        });
      }
    }
  });
}

function setupVideo(callback) {

  if(Hls.isSupported()) {

    if (hls) {
      hls.destroy();
    }

    hls = new Hls({
      autoStartLoad: true,
      debug: false
    });

    hls.on(Hls.Events.MANIFEST_PARSED, function() {
      console.log('Video parsed. Playing...');
      showError(''); // Clear any errors
      showComingSoon('');
      playingContentId = loadingContentId;
      loadingContentId = undefined;
      showNowPlaying('Now Playing : ' + playingContentId);
      var video = document.getElementById('video');

      video.play();

      return;
    });

    hls.on(Hls.Events.LEVEL_SWITCHING, function(eventType, data) {
      console.log('EVENT.LEVEL_SWITCHING = ' + JSON.stringify(data, 2));
    });

    hls.on(Hls.Events.ERROR, function (event, data) {
      var errorType = data.type;
      var errorDetails = data.details;
      var errorFatal = data.fatal;
      var reason = data.reason ? ', reason = ' + data.reason : '';

      var errorText =
        'ERROR: type = ' + errorType +
        ', details = ' + errorDetails + reason;
      console.error(errorText);
      showError(errorText);
      return;
    });

    hls.attachMedia(video);

    callback(null, null);
  } else {
    callback('HLS - NOT SUPPORTED');
  }
}

function loadVideo(contentId) {
  console.log('loadVideo: ' + contentId);
  const url = CONTENTS_FOLDER + contentId + PLAYLIST_FILENAME;
  console.log('URL = ' + url);
  var video = document.getElementById('video');
  video.pause();

  setupVideo((err, data) => {
    if (err) {
      console.error(err);
      showError(err);
      return;
    }

    loadingContentId = contentId;
    hls.loadSource(url);
  });
}

function updateContentsIndex() {
  console.log('updateContentsIndex');

  var linkContents = '';

  contents.forEach(filename => {
    linkContents +=
      '<a href="javascript:autoPlay = false; loadVideo(\'' + filename + '\');">' + filename + '</a><br/>';
  });

  document.getElementById('contents').innerHTML = linkContents;
}

function loadContentsIndex(callback) {
  console.log('loadContentsIndex');

  const key = CONTENTS_FOLDER + INDEX_FILENAME;

  loadFileFromS3(key, (err, data) => {

    if (err) {
      return callback(err);
    }

    try {
      contents = JSON.parse(data);
      updateContentsIndex();
      showError(''); // Clear any errors
      callback(null, null);
    } catch (err) {
      callback(err);
    }
  });
}

function loadFileFromWebsite(url, callback) {
  console.log('loadFileFromWebsite: ' + url);

  const ajaxRequest = new XMLHttpRequest();

  ajaxRequest.onreadystatechange = function() {
    if (ajaxRequest.readyState === XMLHttpRequest.DONE) {
      if (ajaxRequest.status === 200) {
        callback(null, ajaxRequest.responseText);
      } else {
        const err =
          'ERROR: Failed to load file (' +
          url +
          ') : ' +
          ajaxRequest.status +
          ' ' +
          ajaxRequest.statusText;
        callback(err, null);
      }
    }
  };

  ajaxRequest.open('GET', url, true);
  ajaxRequest.send(null);
}

function loadFileFromS3(key, callback) {
  console.log('loadFileFromS3: ' + key);

  AWS.config.update({
    customUserAgent: 'MobileHub v0.1 SimpleVideoTranscoding',
    region: aws_content_delivery_bucket_region
  });

  const s3 = new AWS.S3({
    apiVersion: '2006-03-01',
    params: {
      Bucket: aws_content_delivery_bucket
    }
  });

  s3.getObject({Key: key}, (err, data) => {

    if (err) {
      callback(err);
      return;
    }

    const content = data.Body.toString('utf-8');
    callback(null, content);
  });
}

function checkIfContentFileExists(contentId, callback) {
  const url = CONTENTS_FOLDER + contentId + PLAYLIST_FILENAME;
  loadFileFromWebsite(url, callback);
}

function showNowPlaying(message) {
  document.getElementById('now-playing').innerHTML = message;
}

function showComingSoon(message) {
  document.getElementById('coming-soon').innerHTML = message;
}

function showError(error) {
  document.getElementById('error').innerHTML = error;
}
