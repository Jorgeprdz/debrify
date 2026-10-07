package com.debrify.app.cast

import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.debrify.app.MainActivity
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DebrifyCastManager(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "com.debrify.app/cast"
        const val EVENT_CHANNEL = "com.debrify.app/cast_events"
        private const val PROGRESS_PERIOD_MS = 1_000L
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var castContext: CastContext? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    private var disposed = false

    private var state = DebrifyCastState.DISCONNECTED
    private var deviceName: String? = null
    private var lastPositionMs: Long? = null
    private var lastDurationMs: Long? = null
    private var resumeShouldPlay: Boolean? = null
    private var lastErrorCode: String? = null

    private val castStateListener = CastStateListener {
        if (!disposed) emitSnapshot()
    }

    private val remoteCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() {
            captureRemotePosition()
            updatePlaybackState()
            emitSnapshot()
        }

        override fun onMetadataUpdated() {
            captureRemotePosition()
            emitSnapshot()
        }

        override fun onMediaError(mediaError: com.google.android.gms.cast.MediaError) {
            captureRemotePosition()
            state = DebrifyCastState.ERROR
            lastErrorCode = "CAST_MEDIA_ERROR"
            emitSnapshot()
        }
    }

    private val progressListener = RemoteMediaClient.ProgressListener { progressMs, durationMs ->
        lastPositionMs = progressMs.takeIf { it >= 0 }
        lastDurationMs = durationMs.takeIf { it > 0 }
        emitSnapshot()
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            state = DebrifyCastState.CONNECTING
            lastErrorCode = null
            emitSnapshot()
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            bindSession(session)
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            state = DebrifyCastState.ERROR
            lastErrorCode = "CAST_SESSION_START_FAILED"
            emitSnapshot()
        }

        override fun onSessionEnding(session: CastSession) {
            captureRemotePosition()
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            captureRemotePosition()
            unbindRemoteClient()
            deviceName = null
            state = DebrifyCastState.DISCONNECTED
            if (error != 0) lastErrorCode = "CAST_SESSION_ENDED"
            emitSnapshot()
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {
            state = DebrifyCastState.CONNECTING
            emitSnapshot()
        }

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            bindSession(session)
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            captureRemotePosition()
            unbindRemoteClient()
            state = DebrifyCastState.ERROR
            lastErrorCode = "CAST_SESSION_RESUME_FAILED"
            emitSnapshot()
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {
            captureRemotePosition()
            state = DebrifyCastState.CONNECTING
            emitSnapshot()
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        initializeCastContext()
    }

    private fun initializeCastContext() {
        if (disposed || castContext != null) return
        try {
            val context = CastContext.getSharedInstance(activity)
            castContext = context
            context.addCastStateListener(castStateListener)
            context.sessionManager.addSessionManagerListener(
                sessionListener,
                CastSession::class.java,
            )
            context.sessionManager.currentCastSession
                ?.takeIf { it.isConnected }
                ?.let(::bindSession)
            emitSnapshot()
        } catch (_: Exception) {
            state = DebrifyCastState.ERROR
            lastErrorCode = "CAST_UNAVAILABLE"
            emitSnapshot()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("CAST_DISPOSED", "Cast bridge is no longer attached.", null)
            return
        }
        when (call.method) {
            "isCastAvailable" -> result.success(isCastAvailable())
            "openCastDialog", "requestSession" -> openCastDialog(result)
            "loadMedia" -> loadMedia(call.arguments, result)
            "play" -> runRemoteCommand(result) { it.play() }
            "pause" -> runRemoteCommand(result) { it.pause() }
            "seek" -> seek(call, result)
            "stop" -> runRemoteCommand(result) { it.stop() }
            "disconnect" -> disconnect(result)
            "getState" -> result.success(snapshot())
            else -> result.notImplemented()
        }
    }

    fun onHostResumed() {
        if (disposed) return
        initializeCastContext()
        val session = castContext?.sessionManager?.currentCastSession
        if (session?.isConnected == true && remoteMediaClient == null) bindSession(session)
        emitSnapshot()
    }

    fun onHostPaused() {
        if (disposed) return
        captureRemotePosition()
        emitSnapshot()
    }

    private fun openCastDialog(result: MethodChannel.Result) {
        val context = castContext
        if (context == null) {
            result.error("CAST_UNAVAILABLE", "Google Cast is unavailable.", null)
            return
        }
        try {
            val session = context.sessionManager.currentCastSession
            if (session?.isConnected == true) {
                MediaRouteControllerDialog(activity).show()
            } else {
                MediaRouteChooserDialog(activity).apply {
                    setRouteSelector(context.mergedSelector)
                }.show()
            }
            result.success(true)
        } catch (_: Exception) {
            result.error("CAST_DIALOG_FAILED", "Unable to open the Cast device picker.", null)
        }
    }

    private fun loadMedia(arguments: Any?, result: MethodChannel.Result) {
        val raw = arguments as? Map<*, *>
        if (raw == null) {
            result.error("CAST_BAD_REQUEST", "Cast media request is missing.", null)
            return
        }

        val request = try {
            CastMediaRequest.fromMap(raw)
        } catch (error: CastRequestException) {
            result.error(error.errorCode, error.message, null)
            return
        } catch (_: Exception) {
            result.error("CAST_BAD_REQUEST", "Cast media request is invalid.", null)
            return
        }

        if (request.hasUnsupportedHeaders) {
            result.error(
                "CAST_UNSUPPORTED_HEADERS",
                "This stream requires HTTP headers that cannot be safely attached to the Default Media Receiver request.",
                mapOf("headerCount" to request.headers.size),
            )
            return
        }

        val client = connectedClient(result) ?: return
        val loadBuilder = com.google.android.gms.cast.MediaLoadRequestData.Builder()
            .setMediaInfo(request.toMediaInfo())
            .setAutoplay(request.autoplay)
        request.positionMs?.let(loadBuilder::setCurrentTime)
        val loadRequest = loadBuilder.build()

        resumeShouldPlay = request.autoplay
        lastPositionMs = request.positionMs
        lastDurationMs = request.durationMs
        lastErrorCode = null

        try {
            client.load(loadRequest).setResultCallback { mediaResult ->
                if (mediaResult.status.isSuccess) {
                    captureRemotePosition()
                    updatePlaybackState()
                    result.success(snapshot())
                    emitSnapshot()
                } else {
                    state = DebrifyCastState.ERROR
                    lastErrorCode = "CAST_LOAD_FAILED"
                    emitSnapshot()
                    result.error(
                        "CAST_LOAD_FAILED",
                        "The Cast receiver rejected the media load request.",
                        mapOf("statusCode" to mediaResult.status.statusCode),
                    )
                }
            }
        } catch (_: Exception) {
            state = DebrifyCastState.ERROR
            lastErrorCode = "CAST_LOAD_FAILED"
            emitSnapshot()
            result.error("CAST_LOAD_FAILED", "Unable to send media to the Cast receiver.", null)
        }
    }

    private fun seek(call: MethodCall, result: MethodChannel.Result) {
        val positionMs = call.argument<Number>("positionMs")?.toLong()
        if (positionMs == null || positionMs < 0) {
            result.error("CAST_BAD_SEEK", "A non-negative seek position is required.", null)
            return
        }
        lastPositionMs = positionMs
        val options = MediaSeekOptions.Builder()
            .setPosition(positionMs)
            .setResumeState(MediaSeekOptions.RESUME_STATE_UNCHANGED)
            .build()
        runRemoteCommand(result) { it.seek(options) }
    }

    private fun runRemoteCommand(
        result: MethodChannel.Result,
        command: (RemoteMediaClient) ->
            com.google.android.gms.common.api.PendingResult<RemoteMediaClient.MediaChannelResult>,
    ) {
        val client = connectedClient(result) ?: return
        try {
            command(client).setResultCallback { mediaResult ->
                if (mediaResult.status.isSuccess) {
                    captureRemotePosition()
                    updatePlaybackState()
                    result.success(snapshot())
                    emitSnapshot()
                } else {
                    result.error(
                        "CAST_COMMAND_FAILED",
                        "The Cast receiver rejected the command.",
                        mapOf("statusCode" to mediaResult.status.statusCode),
                    )
                }
            }
        } catch (_: Exception) {
            result.error("CAST_COMMAND_FAILED", "Unable to control the Cast receiver.", null)
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        val context = castContext
        if (context == null) {
            result.success(snapshot())
            return
        }
        captureRemotePosition()
        try {
            context.sessionManager.endCurrentSession(true)
            result.success(snapshot())
        } catch (_: Exception) {
            result.error("CAST_DISCONNECT_FAILED", "Unable to end the Cast session.", null)
        }
    }

    private fun connectedClient(result: MethodChannel.Result): RemoteMediaClient? {
        val session = castContext?.sessionManager?.currentCastSession
        val client = session?.takeIf { it.isConnected }?.remoteMediaClient
        if (client == null) {
            result.error("CAST_NOT_CONNECTED", "No active Cast session.", null)
            return null
        }
        if (client !== remoteMediaClient) bindSession(session)
        return client
    }

    private fun bindSession(session: CastSession) {
        unbindRemoteClient()
        deviceName = session.castDevice?.friendlyName
        val client = session.remoteMediaClient
        remoteMediaClient = client
        client?.registerCallback(remoteCallback)
        client?.addProgressListener(progressListener, PROGRESS_PERIOD_MS)
        client?.requestStatus()
        lastErrorCode = null
        state = DebrifyCastState.CONNECTED
        captureRemotePosition()
        updatePlaybackState()
        emitSnapshot()
    }

    private fun unbindRemoteClient() {
        val client = remoteMediaClient ?: return
        try {
            client.unregisterCallback(remoteCallback)
        } catch (_: Exception) {
        }
        try {
            client.removeProgressListener(progressListener)
        } catch (_: Exception) {
        }
        remoteMediaClient = null
    }

    private fun captureRemotePosition() {
        val client = remoteMediaClient ?: return
        try {
            val position = client.approximateStreamPosition
            if (position >= 0) lastPositionMs = position
            val duration = client.mediaInfo?.streamDuration ?: MediaInfo.UNKNOWN_DURATION
            if (duration >= 0) lastDurationMs = duration
            if (client.isPlaying) resumeShouldPlay = true
            if (client.isPaused) resumeShouldPlay = false
        } catch (_: Exception) {
        }
    }

    private fun updatePlaybackState() {
        val client = remoteMediaClient
        state = when {
            client == null -> DebrifyCastState.DISCONNECTED
            runCatching { client.isPlaying }.getOrDefault(false) -> DebrifyCastState.PLAYING
            runCatching { client.isPaused }.getOrDefault(false) -> DebrifyCastState.PAUSED
            else -> DebrifyCastState.CONNECTED
        }
    }

    private fun isCastAvailable(): Boolean {
        val context = castContext ?: return false
        val active = runCatching {
            context.sessionManager.currentCastSession?.isConnected == true
        }.getOrDefault(false)
        if (active) return true
        return runCatching {
            context.castState != CastState.NO_DEVICES_AVAILABLE
        }.getOrDefault(false)
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "available" to isCastAvailable(),
        "connected" to (remoteMediaClient != null),
        "state" to state.wireValue,
        "deviceName" to deviceName,
        "positionMs" to lastPositionMs,
        "durationMs" to lastDurationMs,
        "resumePositionMs" to lastPositionMs,
        "resumeShouldPlay" to resumeShouldPlay,
        "errorCode" to lastErrorCode,
    )

    private fun emitSnapshot() {
        if (disposed) return
        eventSink?.success(snapshot())
    }

    fun dispose() {
        if (disposed) return
        captureRemotePosition()
        disposed = true
        unbindRemoteClient()
        castContext?.let { context ->
            runCatching { context.removeCastStateListener(castStateListener) }
            runCatching {
                context.sessionManager.removeSessionManagerListener(
                    sessionListener,
                    CastSession::class.java,
                )
            }
        }
        eventSink = null
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        castContext = null
    }
}
