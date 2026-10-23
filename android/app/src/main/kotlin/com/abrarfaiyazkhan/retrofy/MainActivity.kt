package com.abrarfaiyazkhan.retrofy

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// audio_service keeps one cached Flutter engine for background playback, so
// the Spotify bridges are process-wide and simply re-attach to that engine.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        SpotifyRemoteBridge.attach(applicationContext, messenger)
        SpotifyAuthRedirects.attach(messenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SpotifyRemoteBridge.activity = this
    }

    override fun onResume() {
        super.onResume()
        SpotifyRemoteBridge.activity = this
    }

    @Deprecated("Spotify's auth library reports its result here.")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!SpotifyRemoteBridge.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        if (SpotifyRemoteBridge.activity === this) {
            SpotifyRemoteBridge.activity = null
        }
        super.onDestroy()
    }
}
