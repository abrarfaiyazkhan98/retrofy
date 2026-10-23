package com.abrarfaiyazkhan.retrofy

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Holds the OAuth redirect until Dart is listening, which covers the app
// being killed while the user was signing in on the browser.
object SpotifyAuthRedirects {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "retrofy/spotify_auth").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingRedirect" -> {
                        result.success(pending)
                        pending = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun deliver(uri: String) {
        val current = channel
        if (current == null) {
            pending = uri
            return
        }
        // Buffer only when Dart is not listening yet, so it is read once.
        current.invokeMethod("redirect", uri, object : MethodChannel.Result {
            override fun success(result: Any?) {}

            override fun error(code: String, message: String?, details: Any?) {
                pending = uri
            }

            override fun notImplemented() {
                pending = uri
            }
        })
    }
}

// Receives retrofy://spotify-callback from the browser, hands it to Dart and
// returns to the existing Retrofy task instead of stacking a new activity.
class SpotifyAuthRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.toString()?.let(SpotifyAuthRedirects::deliver)
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(it)
        }
        finish()
    }
}
