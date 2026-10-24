package com.abrarfaiyazkhan.retrofy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.android.appremote.api.error.AuthenticationFailedException
import com.spotify.android.appremote.api.error.CouldNotFindSpotifyApp
import com.spotify.android.appremote.api.error.NotLoggedInException
import com.spotify.android.appremote.api.error.OfflineModeException
import com.spotify.android.appremote.api.error.SpotifyConnectionTerminatedException
import com.spotify.android.appremote.api.error.SpotifyDisconnectedException
import com.spotify.android.appremote.api.error.SpotifyRemoteServiceException
import com.spotify.android.appremote.api.error.UnsupportedFeatureVersionException
import com.spotify.android.appremote.api.error.UserNotAuthorizedException
import com.spotify.protocol.client.CallResult
import com.spotify.protocol.client.Subscription
import com.spotify.protocol.types.Capabilities
import com.spotify.protocol.types.Empty
import com.spotify.protocol.types.PlayerState
import com.spotify.sdk.android.auth.AuthorizationClient
import com.spotify.sdk.android.auth.AuthorizationRequest
import com.spotify.sdk.android.auth.AuthorizationResponse
import com.spotify.sdk.android.auth.browser.RedirectUriReceiverActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Controls the installed Spotify app through the official App Remote SDK.
// Spotify decodes and plays all audio; this only relays commands and state.
object SpotifyRemoteBridge : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private const val TAG = "RetrofySpotify"
    private const val AUTH_REQUEST_CODE = 0x5350
    private val main = Handler(Looper.getMainLooper())
    private var authorizing: ((String?) -> Unit)? = null
    private var appRemoteRedirectUri: String? = null
    private lateinit var appContext: Context
    private var events: EventChannel.EventSink? = null
    private var remote: SpotifyAppRemote? = null
    private var connecting: MutableList<MethodChannel.Result>? = null
    private var playerSubscription: Subscription<PlayerState>? = null
    private var capabilitySubscription: Subscription<Capabilities>? = null

    // Showing Spotify's approval screen needs an activity to start from.
    var activity: Activity? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        appContext = context
        MethodChannel(messenger, "retrofy/spotify_remote").setMethodCallHandler(this)
        EventChannel(messenger, "retrofy/spotify_remote/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { events?.success(event) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSpotifyInstalled" ->
                result.success(SpotifyAppRemote.isSpotifyInstalled(appContext))
            "connect" -> connect(call, result)
            "disconnect" -> {
                disconnect()
                result.success(null)
            }
            else -> command(call, result)
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (remote?.isConnected == true) {
            result.success(null)
            return
        }
        connecting?.let {
            it.add(result)
            return
        }
        val clientId = call.argument<String>("clientId")
        val redirectUri = call.argument<String>("redirectUri")
        appRemoteRedirectUri = call.argument<String>("appRemoteRedirectUri")
        if (clientId.isNullOrEmpty() || redirectUri.isNullOrEmpty()) {
            result.error("not_configured", null, null)
            return
        }
        val waiting = mutableListOf(result)
        connecting = waiting
        startConnect(clientId, redirectUri, waiting, mayAuthorize = true)
    }

    // The SDK's built-in approval prompt (showAuthView) is opened by the
    // Spotify app from the background, which current Android versions block.
    // Instead, connect silently and, if Retrofy is not approved yet, ask for
    // app-remote-control through the official auth library from Retrofy's
    // foreground activity, then connect again.
    private fun startConnect(
        clientId: String,
        redirectUri: String,
        waiting: MutableList<MethodChannel.Result>,
        mayAuthorize: Boolean,
    ) {
        val params = ConnectionParams.Builder(clientId)
            .setRedirectUri(redirectUri)
            .showAuthView(false)
            .build()
        SpotifyAppRemote.connect(
            activity ?: appContext,
            params,
            object : Connector.ConnectionListener {
                override fun onConnected(appRemote: SpotifyAppRemote) {
                    remote = appRemote
                    subscribe(appRemote)
                    finishConnecting(waiting) { it.success(null) }
                }

                // Also called later when an established connection drops.
                override fun onFailure(error: Throwable) {
                    val code = errorCode(error)
                    Log.i(TAG, "App Remote connection failed: $code")
                    if (connecting !== waiting) {
                        clear()
                        emit(mapOf("type" to "disconnected", "code" to code))
                    } else if (code == "not_authorized" && mayAuthorize) {
                        authorize(clientId, redirectUri) { failure ->
                            if (failure == null) {
                                startConnect(clientId, redirectUri, waiting, mayAuthorize = false)
                            } else {
                                finishConnecting(waiting) { it.error(failure, null, null) }
                            }
                        }
                    } else {
                        finishConnecting(waiting) { it.error(code, error.message, null) }
                    }
                }
            },
        )
    }

    private fun authorize(clientId: String, redirectUri: String, done: (String?) -> Unit) {
        val current = activity
        // The auth library must use the redirect its receiver declares.
        val authRedirect = appRemoteRedirectUri ?: redirectUri
        if (current == null) {
            done("not_authorized")
            return
        }
        authorizing = done
        val request = AuthorizationRequest.Builder(
            clientId,
            AuthorizationResponse.Type.CODE,
            authRedirect,
        )
            .setScopes(arrayOf("app-remote-control"))
            .build()
        // LoginActivity throws in onCreate, killing the app, when no
        // RedirectUriReceiverActivity filter matches the redirect. Check the
        // same condition first so a misconfiguration is reported instead.
        if (!receiverDeclares(current, authRedirect)) {
            authorizing = null
            Log.w(TAG, "No RedirectUriReceiverActivity filter for the approval redirect")
            done("auth_failed")
            return
        }
        AuthorizationClient.openLoginActivity(current, AUTH_REQUEST_CODE, request)
    }

    private fun receiverDeclares(context: Context, redirectUri: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(redirectUri))
            .addCategory(Intent.CATEGORY_DEFAULT)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage(context.packageName)
        return context.packageManager.queryIntentActivities(intent, 0).any {
            it.activityInfo.name == RedirectUriReceiverActivity::class.java.name
        }
    }

    // Only the outcome matters: approving grants app-remote-control to
    // Retrofy. The returned code is never stored, used or logged.
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != AUTH_REQUEST_CODE) return false
        val response = AuthorizationClient.getResponse(resultCode, data)
        Log.i(TAG, "App Remote approval result: ${response.type} ${response.error ?: ""}")
        val done = authorizing
        authorizing = null
        done?.invoke(
            when (response.type) {
                AuthorizationResponse.Type.CODE,
                AuthorizationResponse.Type.TOKEN -> null
                AuthorizationResponse.Type.ERROR -> "auth_failed"
                else -> "not_authorized"
            },
        )
        return true
    }

    private fun finishConnecting(
        waiting: MutableList<MethodChannel.Result>,
        reply: (MethodChannel.Result) -> Unit,
    ) {
        if (connecting === waiting) connecting = null
        main.post { waiting.forEach(reply) }
    }

    private fun subscribe(appRemote: SpotifyAppRemote) {
        playerSubscription = appRemote.playerApi.subscribeToPlayerState()
            .setEventCallback { emit(playerStateMap(it)) }
        capabilitySubscription = appRemote.userApi.subscribeToCapabilities()
            .setEventCallback {
                emit(mapOf("type" to "capabilities", "canPlayOnDemand" to it.canPlayOnDemand))
            }
    }

    private fun playerStateMap(state: PlayerState): Map<String, Any?> {
        val track = state.track
        // Names and URIs stay index-aligned so Go to Artist opens the right
        // artist page by its Spotify ID, never by a name search.
        val artistList = track?.artists?.filterNotNull()?.takeIf { it.isNotEmpty() }
            ?: listOfNotNull(track?.artist)
        val artists = artistList.map { it.name ?: "" }
        val artistUris = artistList.map { it.uri }
        return mapOf(
            "type" to "playerState",
            "trackUri" to track?.uri,
            "trackName" to track?.name,
            "artists" to artists,
            "artistUris" to artistUris,
            "albumName" to track?.album?.name,
            "imageUri" to track?.imageUri?.raw,
            "durationMs" to (track?.duration ?: 0L),
            "positionMs" to state.playbackPosition,
            "isPaused" to state.isPaused,
            "playbackSpeed" to state.playbackSpeed.toDouble(),
            "isShuffling" to (state.playbackOptions?.isShuffling ?: false),
            "repeatMode" to (state.playbackOptions?.repeatMode ?: 0),
            "isEpisode" to (track?.isEpisode ?: false),
        )
    }

    private fun command(call: MethodCall, result: MethodChannel.Result) {
        val player = remote?.takeIf { it.isConnected }?.playerApi
        if (player == null) {
            result.error("not_connected", null, null)
            return
        }
        val pending: CallResult<Empty> = when (call.method) {
            "play" -> player.play(call.argument<String>("uri"))
            "skipToIndex" ->
                player.skipToIndex(call.argument<String>("uri"), call.argument<Int>("index") ?: 0)
            "resume" -> player.resume()
            "pause" -> player.pause()
            "skipNext" -> player.skipNext()
            "skipPrevious" -> player.skipPrevious()
            "seekTo" -> player.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
            "setShuffle" -> player.setShuffle(call.argument<Boolean>("enabled") ?: false)
            "setRepeat" -> player.setRepeat(call.argument<Int>("mode") ?: 0)
            else -> {
                result.notImplemented()
                return
            }
        }
        pending
            .setResultCallback { main.post { result.success(null) } }
            .setErrorCallback { error ->
                main.post { result.error(errorCode(error), error.message, null) }
            }
    }

    private fun clear() {
        playerSubscription?.cancel()
        capabilitySubscription?.cancel()
        playerSubscription = null
        capabilitySubscription = null
        remote = null
    }

    private fun disconnect() {
        val current = remote
        clear()
        current?.let(SpotifyAppRemote::disconnect)
    }

    // Stable codes shared with the Dart side, which localizes them. Matched by
    // type, not class name: release builds rename the SDK's classes.
    private fun errorCode(error: Throwable): String = when (error) {
        is CouldNotFindSpotifyApp -> "not_installed"
        is NotLoggedInException -> "not_logged_in"
        is UserNotAuthorizedException -> "not_authorized"
        is AuthenticationFailedException -> "auth_failed"
        is UnsupportedFeatureVersionException -> "unsupported_version"
        is OfflineModeException -> "offline"
        is SpotifyDisconnectedException,
        is SpotifyConnectionTerminatedException -> "disconnected"
        is SpotifyRemoteServiceException -> "remote_service"
        else -> "unknown"
    }
}
