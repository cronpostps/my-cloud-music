package com.example.car_music_lite

import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.media.MediaMetadata
import android.os.Bundle
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "car_music_lite/native_keys"
    private var mediaSession: MediaSession? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Tạo đường ống kết nối với Dart
        methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
        
        // Khởi tạo MediaSession lõi của Android (Không dùng bản Compat nữa)
        mediaSession = MediaSession(this, "CarMusicLite").apply {
            
            // Giả lập trạng thái luôn Đang Phát để giành quyền nhận Vô lăng
            val state = PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS)
                .setState(PlaybackState.STATE_PLAYING, 0, 1.0f)
                .build()
            setPlaybackState(state)

            // Bắt sự kiện bấm phím và gửi qua cho Flutter (Dart)
            setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val keyEvent = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                    if (keyEvent != null && keyEvent.action == KeyEvent.ACTION_DOWN) {
                        when (keyEvent.keyCode) {
                            KeyEvent.KEYCODE_MEDIA_NEXT -> {
                                methodChannel?.invokeMethod("next", null)
                                return true
                            }
                            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                                methodChannel?.invokeMethod("prev", null)
                                return true
                            }
                            KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                                methodChannel?.invokeMethod("toggle", null)
                                return true
                            }
                        }
                    }
                    return super.onMediaButtonEvent(mediaButtonIntent)
                }

                override fun onSkipToNext() { methodChannel?.invokeMethod("next", null) }
                override fun onSkipToPrevious() { methodChannel?.invokeMethod("prev", null) }
                override fun onPlay() { methodChannel?.invokeMethod("toggle", null) }
                override fun onPause() { methodChannel?.invokeMethod("toggle", null) }
            })
            isActive = true
        }
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "updateMetadata") {
                val title = call.argument<String>("title") ?: "Unknown"
                val artist = call.argument<String>("artist") ?: "Root"

                val metadata = MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                    .build()

                mediaSession?.setMetadata(metadata)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        mediaSession?.isActive = false
        mediaSession?.release()
        super.onDestroy()
    }
}