package com.amazonaws.videodemo.videodemo;
/*
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
*/

import android.Manifest;
import android.app.Activity;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.provider.MediaStore;
import android.support.design.widget.FloatingActionButton;
import android.support.v7.app.AlertDialog;
import android.support.v7.app.AppCompatActivity;
import android.support.v7.widget.Toolbar;
import android.util.Log;
import android.view.View;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.TextView;

import com.amazonaws.mobile.auth.core.IdentityHandler;
import com.amazonaws.mobile.auth.core.IdentityManager;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferListener;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferObserver;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferState;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferUtility;
import com.amazonaws.regions.Region;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3Client;
import com.amazonaws.util.IOUtils;
import com.devbrackets.android.exomedia.listener.OnCompletionListener;
import com.devbrackets.android.exomedia.listener.OnErrorListener;
import com.devbrackets.android.exomedia.ui.widget.VideoView;
import com.devbrackets.android.exomedia.listener.OnPreparedListener;
import com.amazonaws.mobile.client.AWSMobileClient;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.Date;

public class MainActivity extends AppCompatActivity implements OnPreparedListener, IdentityHandler, OnErrorListener, OnCompletionListener {
    private static final String LOG_TAG = MainActivity.class.getSimpleName();
    private static final String CONTENT_INDEX_KEY = "content/index.json";
    private static final String CONTENT_FOLDER = "/content/";
    private static final String CONTENT_FILENAME = "/default.m3u8";
    private static final int REQUEST_VIDEO = 308;       // arbitrary request type id
    private static final int REQUEST_PERMISSIONS = 403; // arbitrary request type id

    private String userIdentity = "";
    private volatile String loadingContentId = "";
    private volatile String playingContentId = "";
    private VideoView videoView;

    private Handler timerHandler;
    private Runnable timerRunnable;

    private void setupVideoView(final String hostingURL, final String contentId) {
        // Make sure to use the correct VideoView import
        videoView = (VideoView) findViewById(R.id.videoView);

        videoView.reset();
        videoView.setVisibility(View.GONE);
        videoView.setOnPreparedListener(this);
        videoView.setOnErrorListener(this);
        videoView.setOnCompletionListener(this);

        loadingContentId = contentId;

        final Uri uri =
                Uri.parse(hostingURL + CONTENT_FOLDER + contentId + CONTENT_FILENAME);

        Log.d(LOG_TAG, "URI: " + uri);

        videoView.setVideoURI(uri);
        videoView.requestFocus();
    }

    /**
     * Called when video is done loading and is ready to play.
     */
    @Override
    public void onPrepared() {
        Log.d(LOG_TAG, "onPrepared");

        playingContentId = loadingContentId;

        ((TextView) findViewById(R.id.textView_playing))
                .setText("NOW PLAYING\n" + playingContentId + "\n");

        videoView.setVisibility(View.VISIBLE);
        videoView.start();
    }

    /**
     * Called when Activity is created.
     *
     * @param savedInstanceState bundle for state if resuming
     */
    @Override
    protected void onCreate(final Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        final Toolbar toolbar = (Toolbar) findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);

        final FloatingActionButton uploadButton = (FloatingActionButton) findViewById(R.id.uploadButton);
        uploadButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(final View view) {

                if (videoView != null) {
                    videoView.pause();
                }

                recordVideo();
            }
        });

        AWSMobileClient.getInstance().initialize(this).execute();
        final IdentityManager identityManager = IdentityManager.getDefaultIdentityManager();
        identityManager.getUserID(this);
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.menu_main, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        // Handle action bar item clicks here. The action bar will
        // automatically handle clicks on the Home/Up button, so long
        // as you specify a parent activity in AndroidManifest.xml.
        int id = item.getItemId();

        //noinspection SimplifiableIfStatement
        if (id == R.id.action_settings) {
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d(LOG_TAG, "onResume");
        startTimer();
    }

    @Override
    protected void onPause() {
        super.onPause();
        Log.d(LOG_TAG, "onPause");
        stopTimer();
    }

    private void startTimer() {
        stopTimer();
        timerHandler = new Handler();

        timerRunnable = new Runnable() {
            @Override
            public void run() {
                Log.d(LOG_TAG, "timer expired");
                reloadContentIndex();
                timerHandler.postDelayed(this, 30000);
            }
        };

        timerHandler.post(timerRunnable);
    }

    private void stopTimer() {
        if (timerHandler != null) {
            timerHandler.removeCallbacks(timerRunnable);
            timerHandler = null;
        }
    }

    private void reloadContentIndex() {
        Log.d(LOG_TAG, "reloadContentIndex");

        try {
            final JSONObject contentManagerConfig =
                    AWSMobileClient.getInstance()
                            .getConfiguration()
                            .optJsonObject("ContentManager");
            final String bucket = contentManagerConfig.getString("Bucket");
            final String region = contentManagerConfig.getString("Region");
            final String cloudFrontURL = contentManagerConfig.getString("CloudFrontURL");

            final File outputDir = getCacheDir();
            final File outputFile = File.createTempFile("index", ".json", outputDir);

            final AmazonS3 s3 =
                    new AmazonS3Client(AWSMobileClient.getInstance().getCredentialsProvider());
            s3.setRegion(Region.getRegion(region));
            final TransferUtility transferUtility =
                    new TransferUtility(s3, getApplicationContext());
            final TransferObserver observer = transferUtility.download(
                    bucket,
                    CONTENT_INDEX_KEY,
                    outputFile);

            observer.setTransferListener(new TransferListener() {
                @Override
                public void onStateChanged(final int id, final TransferState state) {
                    Log.d(LOG_TAG, "S3 Download state change : " + state);

                    if (TransferState.COMPLETED == state) {

                        try {
                            final String contentsIndex =
                                    IOUtils.toString(new FileInputStream(outputFile));

                            final JSONArray jsonArray =
                                    (JSONArray) new JSONTokener(contentsIndex).nextValue();

                            Log.d(LOG_TAG, "CONTENTS INDEX = " + jsonArray);

                            if (jsonArray.length() <= 0) {
                                this.onError(id, new IllegalStateException("No videos available."));
                                return;
                            }

                            final String contentId = jsonArray.getString(0);

                            Log.d(LOG_TAG, "Playing Content ID : " + playingContentId);

                            if (!contentId.equalsIgnoreCase(playingContentId)) {
                                Log.d(LOG_TAG, "New Content ID : " + contentId);
                                setupVideoView(cloudFrontURL, contentId);
                            }

                        } catch (final IOException | JSONException e) {
                            this.onError(id, e);
                        }
                    }
                }

                @Override
                public void onProgressChanged(final int id, final long bytesCurrent, final long bytesTotal) {
                    Log.d(LOG_TAG, "S3 Download progress : " + bytesCurrent);
                }

                @Override
                public void onError(final int id, final Exception ex) {
                    Log.e(LOG_TAG, "FAILED : " + ex.getMessage(), ex);

                    if (ex.getMessage().contains("key does not exist")) {
                        Log.d(LOG_TAG, "No content index");
                        ((TextView) findViewById(R.id.textView_playing))
                                .setText("CONTENT INDEX IS NOT AVAILABLE\n");
                        return;
                    }
                }
            });
        } catch (final JSONException | IOException e) {
            Log.e(LOG_TAG, e.getMessage(), e);
        }
    }

    /**
     * Called when Amazon Cognito User Identity has been loaded.
     *
     * @param identityId user identity
     */
    @Override
    public void onIdentityId(final String identityId) {
        Log.d(LOG_TAG, "Identity : " + identityId);

        userIdentity = identityId;
        ((TextView) findViewById(R.id.textView_userId))
                .setText("Amazon Cognito Identity\n" + userIdentity);
    }

    /**
     * Called when an error occurs while trying to load Amazon Cognito User Identity.
     *
     * @param exception exception
     */
    @Override
    public void handleError(final Exception exception) {
        Log.e(LOG_TAG, exception.getMessage(), exception);
    }

    /**
     * Called when video view encounters an error.
     *
     * @param e exception
     * @return true if the error is handled, else false
     */
    @Override
    public boolean onError(final Exception e) {
        Log.e(LOG_TAG, "Video Load Failed: " + e.getMessage(), e);

        ((TextView) findViewById(R.id.textView_playing))
                .setText("COMING SOON\n" + loadingContentId + "\n");

        return false;
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, final Intent data) {
        Log.d(LOG_TAG, "onActivityResult: " + resultCode + " " + data);

        if (resultCode == Activity.RESULT_OK) {
            if (requestCode == REQUEST_VIDEO) {
                final Uri videoUri = data.getData();
                final String[] projection = {MediaStore.Video.VideoColumns.DATA};
                final Cursor cursor = getContentResolver().query(videoUri, projection, null, null, null);

                int vidsCount = 0;
                String filename = null;

                if (cursor != null) {
                    cursor.moveToFirst();
                    vidsCount = cursor.getCount();

                    do {
                        filename = cursor.getString(0);
                    } while (cursor.moveToNext());

                    final File file = new File(filename);

                    if (file != null &&
                            file.exists() &&
                            file.length() > 0) {
                        Log.d(LOG_TAG, "Video File : " + file.getName());
                        uploadVideoFile(file);
                    } else {
                        Log.d(LOG_TAG, "No video produced.");
                    }
                } else {
                    Log.d(LOG_TAG, "No video produced.");
                }
            }
        }
    }

    private void recordVideo() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.CAMERA,
                            Manifest.permission.READ_EXTERNAL_STORAGE},
                    REQUEST_PERMISSIONS);
            return;
        }

        launchVideoRecord();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_PERMISSIONS) {
            if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchVideoRecord();
            } else {
                Log.e(LOG_TAG, "No permissions to use camera.");
            }
        }
    }

    private void launchVideoRecord() {
        final Intent intent =
                new Intent(MediaStore.ACTION_VIDEO_CAPTURE);

        if (intent.resolveActivity(getPackageManager()) != null) {
            startActivityForResult(intent, REQUEST_VIDEO);
        }
    }

    private void uploadVideoFile(final File file) {
        Log.d(LOG_TAG, "uploadVideoFile: " + file);

        final Activity activity = this;

        try {
            final JSONObject contentManagerConfig =
                    AWSMobileClient.getInstance()
                            .getConfiguration()
                            .optJsonObject("S3TransferUtility");
            final String bucket = contentManagerConfig.getString("Bucket");
            final String region = contentManagerConfig.getString("Region");

            final AmazonS3 s3 =
                    new AmazonS3Client(AWSMobileClient.getInstance().getCredentialsProvider());
            s3.setRegion(Region.getRegion(region));
            final TransferUtility transferUtility =
                    new TransferUtility(s3, getApplicationContext());
            final String objectKey = "private/" + userIdentity + "/" + (new Date()).getTime() + ".mp4";
            final TransferObserver observer = transferUtility.upload(
                    bucket,
                    objectKey,
                    file);

            observer.setTransferListener(new TransferListener() {
                @Override
                public void onStateChanged(final int id, final TransferState state) {
                    Log.d(LOG_TAG, "S3 Upload state change : " + state);

                    if (TransferState.COMPLETED == state) {
                        final AlertDialog.Builder builder =
                                new AlertDialog.Builder(activity);
                        builder.setTitle("Video Upload")
                                .setMessage("Your file has been uploaded.")
                                .setPositiveButton(android.R.string.ok,
                                        new DialogInterface.OnClickListener() {
                                    public void onClick(DialogInterface dialog, int which) {
                                        if (videoView != null) {
                                            videoView.restart();
                                        }
                                    }
                                })
                                .setIcon(android.R.drawable.ic_dialog_alert)
                                .show();
                    }
                }

                @Override
                public void onProgressChanged(final int id, final long bytesCurrent, final long bytesTotal) {
                    Log.d(LOG_TAG, "S3 Upload progress : " + bytesCurrent);
                }

                @Override
                public void onError(final int id, final Exception ex) {
                    Log.e(LOG_TAG, "FAILED : " + ex.getMessage(), ex);

                    final AlertDialog.Builder builder =
                            new AlertDialog.Builder(activity);
                    builder.setTitle("Video Upload")
                            .setMessage("Your file upload has failed : " + ex.getMessage())
                            .setPositiveButton(android.R.string.ok,
                                    new DialogInterface.OnClickListener() {
                                        public void onClick(DialogInterface dialog, int which) {
                                            if (videoView != null) {
                                                videoView.restart();
                                            }
                                        }
                                    })
                            .setIcon(android.R.drawable.ic_dialog_alert)
                            .show();
                }
            });
        } catch (final JSONException e) {
            Log.e(LOG_TAG, e.getMessage(), e);
        }
    }

    @Override
    public void onCompletion() {
        Log.d(LOG_TAG, "onCompletion");
        videoView.restart();
    }
}
