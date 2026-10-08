package com.debrify.app.cast

import android.os.Handler
import android.os.Looper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.debrify.app.MainActivity
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.MediaTrack
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.PendingResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.IdentityHashMap
import java.util.UUID

class DebrifyCastManager(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val METHOD_CHANNEL = "com.debrify.app/cast"
        const val EVENT_CHANNEL = "com.debrify.app/cast_events"
        private const val PROGRESS_PERIOD_MS = 1_000L
        private const val OPERATION_DEADLINE_MS = 30_000L
        private val mainHandler = Handler(Looper.getMainLooper())

        // All access is on the Android main thread, as required by Cast SDK.
        // Weak registry entries avoid retaining an idle, destroyed Flutter engine.
        private val bridges = mutableListOf<WeakReference<EngineBridge>>()
        private val receivers = IdentityHashMap<CastSession, MutableList<ReceiverLedger>>()
        private val retiredSessions = mutableListOf<WeakReference<CastSession>>()
        private val endingSessions = IdentityHashMap<CastSession, Boolean>()
        private val observedContexts = IdentityHashMap<CastContext, Boolean>()

        private fun bridgeFor(messenger: BinaryMessenger): EngineBridge {
            bridges.removeAll { it.get() == null }
            bridges.mapNotNull { it.get() }.firstOrNull { it.messenger === messenger }
                ?.let { return it }
            return EngineBridge(messenger).also { bridges.add(WeakReference(it)) }
        }

        private fun ledgerFor(session: CastSession, client: RemoteMediaClient): ReceiverLedger {
            val entries = receivers.getOrPut(session) { mutableListOf() }
            return entries.firstOrNull { !it.retired && it.client === client }
                ?: ReceiverLedger(session, client).also {
                    it.ending = endingSessions.containsKey(session)
                    entries.add(it)
                }
        }

        private fun isRetired(session: CastSession): Boolean {
            retiredSessions.removeAll { it.get() == null }
            return retiredSessions.any { it.get() === session }
        }

        private fun notifyBridges() {
            bridges.removeAll { it.get() == null }
            bridges.mapNotNull { it.get() }.forEach { it.emit() }
        }

        private fun physicalOperationExists(): Boolean =
            receivers.values.any { ledgers -> ledgers.any { it.operation != null } }

        private fun uncertainOperationExists(): Boolean =
            endingSessions.isNotEmpty() || receivers.values.any { ledgers ->
                ledgers.any { it.operation?.uncertain == true || it.ending }
            }

        private fun markUncertain(ledger: ReceiverLedger, operation: PhysicalOperation) {
            if (ledger.retired || ledger.operation !== operation) return
            operation.uncertain = true
            ledger.errorCode = "CAST_RECEIVER_OPERATION_BLOCKED"
            // A logical deadline or SDK failure does not prove cancellation.
            // Keep both the original Result and physical fence until a definitive
            // successful reply or confirmed SDK session termination.
            notifyBridges()
        }

        private fun retireSession(session: CastSession) {
            // Mark retired before any Result/stream callback can synchronously
            // read SDK properties still reflecting the ending session.
            if (!isRetired(session)) retiredSessions.add(WeakReference(session))
            endingSessions.remove(session)
            val ledgers = receivers.remove(session).orEmpty()
            ledgers.forEach { ledger ->
                ledger.capture()
                ledger.retired = true
                ledger.ending = false
                val operation = ledger.operation
                ledger.operation = null
                operation?.deadline?.let(mainHandler::removeCallbacks)
                operation?.pendingResult = null
                operation?.reply?.error(
                    "CAST_SESSION_RETIRED", "The Cast session ended before the operation completed.",
                )
            }
            bridges.mapNotNull { it.get() }.forEach { bridge ->
                if (bridge.lastLedger?.session === session) {
                    bridge.detachedState = DebrifyCastState.DISCONNECTED
                    bridge.detachedErrorCode = null
                }
                bridge.completeDisconnect(session)
            }
            notifyBridges()
        }

        // This observer belongs to CastContext, not an Activity. It remains
        // installed across manager disposal, so retirement can settle the ledger
        // even in the gap before the replacement Activity attaches.
        private val retirementListener = object : SessionManagerListener<CastSession> {
            override fun onSessionStarting(session: CastSession) = Unit
            override fun onSessionStarted(session: CastSession, sessionId: String) = Unit
            override fun onSessionStartFailed(session: CastSession, error: Int) = Unit
            override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
            override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = Unit
            override fun onSessionResumeFailed(session: CastSession, error: Int) {
                // Resume failure alone is not an onSessionEnded confirmation.
                receivers[session]?.forEach { ledger ->
                    ledger.operation?.let { markUncertain(ledger, it) }
                }
            }
            override fun onSessionEnding(session: CastSession) {
                if (isRetired(session)) return
                if (!receivers.containsKey(session) && !endingSessions.containsKey(session) &&
                    observedContexts.keys.none { it.sessionManager.currentCastSession === session }) return
                endingSessions[session] = true
                receivers[session]?.forEach { it.ending = true }
                notifyBridges()
            }
            override fun onSessionEnded(session: CastSession, error: Int) = retireSession(session)
            override fun onSessionSuspended(session: CastSession, reason: Int) {
                receivers[session]?.forEach { ledger ->
                    ledger.operation?.let { markUncertain(ledger, it) }
                }
            }
        }

        private fun observeRetirement(context: CastContext) {
            if (observedContexts.containsKey(context)) return
            context.sessionManager.addSessionManagerListener(
                retirementListener, CastSession::class.java,
            )
            observedContexts[context] = true
        }

        private fun finishPhysicalSuccess(ledger: ReceiverLedger, operation: PhysicalOperation) {
            if (ledger.retired || ledger.operation !== operation) return
            ledger.operation = null
            operation.deadline?.let(mainHandler::removeCallbacks)
            operation.pendingResult = null
            ledger.capture()
            if (!ledger.mediaErrorActive) ledger.errorCode = null
            ledger.updatePlaybackState()
            val snapshot = operation.bridge.snapshot()
            // The snapshot always describes actual receiver reality. Dart must
            // quarantine a mismatching identity rather than hide that reality.
            operation.reply.success(snapshot)
            operation.bridge.emit(snapshot)
            notifyBridges()
        }

        private fun startPhysicalOperation(
            bridge: EngineBridge,
            ledger: ReceiverLedger,
            result: MethodChannel.Result,
            command: (RemoteMediaClient) -> PendingResult<RemoteMediaClient.MediaChannelResult>,
        ) {
            if (ledger.retired || ledger.ending || endingSessions.isNotEmpty() || physicalOperationExists()) {
                result.error(
                    "CAST_RECEIVER_OPERATION_BLOCKED",
                    "A receiver operation is still pending. End the Cast session before reconnecting.",
                    null,
                )
                return
            }
            val operation = PhysicalOperation(bridge, Reply(result))
            ledger.operation = operation
            operation.deadline = Runnable { markUncertain(ledger, operation) }
            mainHandler.postDelayed(operation.deadline!!, OPERATION_DEADLINE_MS)
            try {
                val pending = command(ledger.client)
                operation.pendingResult = pending
                pending.setResultCallback { mediaResult ->
                    if (ledger.retired || ledger.operation !== operation) return@setResultCallback
                    if (mediaResult.status.isSuccess) {
                        finishPhysicalSuccess(ledger, operation)
                    } else {
                        // Transport timeouts/cancellation and receiver failures
                        // are not interchangeable. Conservatively retain the
                        // fence for all post-dispatch non-success replies.
                        markUncertain(ledger, operation)
                    }
                }
            } catch (_: Exception) {
                // The SDK call may have sent the command before throwing.
                markUncertain(ledger, operation)
            }
        }

        private fun tracks(client: RemoteMediaClient, type: Int): List<Map<String, Any?>> {
            val active = client.mediaStatus?.activeTrackIds?.toSet().orEmpty()
            return client.mediaInfo?.mediaTracks.orEmpty().filter { it.type == type }.map { track ->
                mapOf(
                    "id" to track.id.toString(),
                    "type" to if (type == MediaTrack.TYPE_AUDIO) "audio" else "subtitle",
                    "language" to track.language,
                    "label" to track.name,
                    "mimeType" to track.contentType,
                    "codec" to null,
                    "selected" to active.contains(track.id),
                )
            }
        }
    }

    private class Reply(result: MethodChannel.Result) {
        private var target: MethodChannel.Result? = result
        fun success(value: Any?) {
            val result = target ?: return
            target = null
            // A destroyed engine cannot receive a reply. Never crash or send twice.
            runCatching { result.success(value) }
        }
        fun error(code: String, message: String) {
            val result = target ?: return
            target = null
            runCatching { result.error(code, message, null) }
        }
    }

    private class PhysicalOperation(val bridge: EngineBridge, val reply: Reply) {
        var uncertain = false
        var deadline: Runnable? = null
        var pendingResult: PendingResult<RemoteMediaClient.MediaChannelResult>? = null
    }

    private class ReceiverLedger(val session: CastSession, val client: RemoteMediaClient) {
        // Stable across manager/Activity replacement for this exact SDK session
        // and client. A confirmed retirement creates a new epoch next time.
        val sessionEpoch = UUID.randomUUID().toString()
        var retired = false
        var ending = false
        var operation: PhysicalOperation? = null
        var state = DebrifyCastState.CONNECTED
        var positionMs: Long? = null
        var durationMs: Long? = null
        var resumeShouldPlay: Boolean? = null
        var errorCode: String? = null
        var mediaErrorActive = false
        var endedSequence = 0
        private var endedForCurrentMedia = false
        private var observedMediaSessionId: Long? = null
        private var observedContentId: String? = null

        fun capture() {
            try {
                val mediaSessionId = client.mediaStatus?.mediaSessionId?.toLong()
                val contentId = client.mediaInfo?.contentId
                if (mediaSessionId != observedMediaSessionId || contentId != observedContentId) {
                    observedMediaSessionId = mediaSessionId
                    observedContentId = contentId
                    positionMs = null
                    durationMs = null
                    resumeShouldPlay = null
                    endedForCurrentMedia = false
                    mediaErrorActive = false
                }
                positionMs = client.approximateStreamPosition.takeIf { it >= 0 }
                durationMs = client.mediaInfo?.streamDuration?.takeIf { it > 0 }
                if (client.isPlaying) resumeShouldPlay = true
                if (client.isPaused) resumeShouldPlay = false
            } catch (_: Exception) {
                durationMs = null
            }
        }

        fun updatePlaybackState() {
            val status = runCatching { client.mediaStatus }.getOrNull()
            if (mediaErrorActive || (status?.playerState == MediaStatus.PLAYER_STATE_IDLE &&
                    status.idleReason == MediaStatus.IDLE_REASON_ERROR)) {
                state = DebrifyCastState.ERROR
                errorCode = "CAST_MEDIA_ERROR"
                return
            }
            if (status?.playerState == MediaStatus.PLAYER_STATE_IDLE &&
                status.idleReason == MediaStatus.IDLE_REASON_FINISHED) {
                if (!endedForCurrentMedia) {
                    endedForCurrentMedia = true
                    ++endedSequence
                }
                state = DebrifyCastState.ENDED
                resumeShouldPlay = false
                return
            }
            if (status != null && status.playerState != MediaStatus.PLAYER_STATE_IDLE &&
                status.playerState != MediaStatus.PLAYER_STATE_UNKNOWN) {
                endedForCurrentMedia = false
            }
            state = when {
                runCatching { client.isPlaying }.getOrDefault(false) -> DebrifyCastState.PLAYING
                runCatching { client.isPaused }.getOrDefault(false) -> DebrifyCastState.PAUSED
                else -> DebrifyCastState.CONNECTED
            }
        }
    }

    private class DisconnectReply(val session: CastSession, val reply: Reply) {
        var deadline: Runnable? = null
    }

    private class EngineBridge(val messenger: BinaryMessenger) :
        MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
        private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
        private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
        val bridgeInstanceId = UUID.randomUUID().toString()
        var owner: DebrifyCastManager? = null
        var context: CastContext? = null
        var lastLedger: ReceiverLedger? = null
        var detachedState = DebrifyCastState.DISCONNECTED
        var detachedErrorCode: String? = null
        private var revision = 0L
        private var eventSink: EventChannel.EventSink? = null
        private val disconnectReplies = mutableListOf<DisconnectReply>()

        init {
            methodChannel.setMethodCallHandler(this)
            eventChannel.setStreamHandler(this)
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            emit()
        }
        override fun onCancel(arguments: Any?) { eventSink = null }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "getState" -> {
                    owner?.synchronizeSession()
                    result.success(snapshot())
                }
                "isCastAvailable" -> result.success(isAvailable())
                "disconnect" -> disconnect(result)
                else -> {
                    val activeOwner = owner
                    if (activeOwner == null) {
                        result.error("CAST_BRIDGE_DETACHED", "Cast Activity is being recreated.", null)
                    } else activeOwner.onMethodCall(call, result)
                }
            }
        }

        private fun isAvailable(): Boolean {
            val cast = context ?: return false
            return runCatching {
                cast.sessionManager.currentCastSession?.isConnected == true ||
                    cast.castState != CastState.NO_DEVICES_AVAILABLE
            }.getOrDefault(false)
        }

        fun snapshot(): Map<String, Any?> {
            val session = runCatching { context?.sessionManager?.currentCastSession }.getOrNull()
            val client = runCatching {
                session?.takeIf { it.isConnected && !isRetired(it) }?.remoteMediaClient
            }.getOrNull()
            val current = if (session != null && client != null) ledgerFor(session, client) else null
            if (current != null) {
                lastLedger = current
                current.capture()
                current.updatePlaybackState()
            }
            val timing = current ?: lastLedger
            val lifecycleUncertain = current == null && lastLedger?.retired == false
            val audio = current?.let { runCatching { tracks(it.client, MediaTrack.TYPE_AUDIO) }.getOrDefault(emptyList()) }.orEmpty()
            val text = current?.let { runCatching { tracks(it.client, MediaTrack.TYPE_TEXT) }.getOrDefault(emptyList()) }.orEmpty()
            ++revision
            return mapOf(
                "available" to isAvailable(),
                "connected" to (current != null),
                "state" to (current?.state ?: detachedState).wireValue,
                "deviceName" to current?.session?.castDevice?.friendlyName,
                "positionMs" to timing?.positionMs,
                "durationMs" to timing?.durationMs,
                "resumePositionMs" to timing?.positionMs,
                "resumeShouldPlay" to timing?.resumeShouldPlay,
                "errorCode" to if (uncertainOperationExists() || lifecycleUncertain) "CAST_RECEIVER_OPERATION_BLOCKED"
                    else current?.errorCode ?: detachedErrorCode,
                "availableAudioTracks" to audio,
                "availableSubtitleTracks" to text,
                "selectedAudioTrack" to audio.firstOrNull { it["selected"] == true }?.get("id"),
                "selectedSubtitleTrack" to text.firstOrNull { it["selected"] == true }?.get("id"),
                "endedSequence" to (timing?.endedSequence ?: 0),
                // Signed content IDs are transient channel data, never logged/stored.
                "mediaContentId" to current?.client?.mediaInfo?.contentId,
                "mediaSessionId" to current?.client?.mediaStatus?.mediaSessionId,
                // Suspension is not retirement. Preserve this epoch until the
                // SDK confirms onSessionEnded, so a resumed session can be adopted.
                "sessionEpoch" to (current?.sessionEpoch ?:
                    lastLedger?.takeIf { !it.retired }?.sessionEpoch),
                "bridgeInstanceId" to bridgeInstanceId,
                "snapshotRevision" to revision,
                "receiverOperationBlocked" to (
                    lifecycleUncertain || uncertainOperationExists() ||
                        (physicalOperationExists() &&
                            (current == null || current.operation == null || current.operation?.bridge !== this))
                    ),
            )
        }

        fun emit(value: Map<String, Any?> = snapshot()) {
            val sink = eventSink ?: return
            runCatching { sink.success(value) }
        }

        private fun disconnect(result: MethodChannel.Result) {
            val cast = context
            val session = cast?.sessionManager?.currentCastSession
            if (cast == null || session == null) {
                if (physicalOperationExists()) {
                    result.error(
                        "CAST_RECEIVER_OPERATION_BLOCKED",
                        "The previous receiver session has not confirmed termination.", null,
                    )
                } else result.success(snapshot())
                return
            }
            // End-session request is allowed through the physical operation fence.
            // Do not report disconnection or release that fence merely on dispatch.
            val pending = DisconnectReply(session, Reply(result))
            disconnectReplies.add(pending)
            pending.deadline = Runnable {
                pending.reply.error(
                    "CAST_DISCONNECT_PENDING", "Cast session termination is not yet confirmed.",
                )
                // No physical exclusion or session identity is retired here.
                notifyBridges()
            }
            mainHandler.postDelayed(pending.deadline!!, OPERATION_DEADLINE_MS)
            receivers[session]?.forEach { it.ending = true }
            endingSessions[session] = true
            notifyBridges()
            try {
                cast.sessionManager.endCurrentSession(true)
            } catch (_: Exception) {
                pending.deadline?.let(mainHandler::removeCallbacks)
                disconnectReplies.remove(pending)
                pending.reply.error("CAST_DISCONNECT_FAILED", "Unable to end the Cast session.")
                // An exception may occur after dispatch. Remain fenced.
                notifyBridges()
            }
        }

        fun completeDisconnect(session: CastSession) {
            val completed = disconnectReplies.filter { it.session === session }
            disconnectReplies.removeAll(completed.toSet())
            completed.forEach {
                it.deadline?.let(mainHandler::removeCallbacks)
                it.reply.success(snapshot())
            }
        }
    }

    private val bridge = bridgeFor(messenger)
    private var disposed = false
    private var castContext: CastContext? = null
    private var attachedSession: CastSession? = null
    private var prospectiveSession: CastSession? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    private var ledger: ReceiverLedger? = null
    private var bindingGeneration = 0L
    private var boundCallback: RemoteMediaClient.Callback? = null
    private var boundProgress: RemoteMediaClient.ProgressListener? = null

    private fun ownsBridge(): Boolean = !disposed && bridge.owner === this
    private fun currentSession(): CastSession? = castContext?.sessionManager?.currentCastSession
    private fun ownsSession(session: CastSession): Boolean =
        ownsBridge() && currentSession() === session
    private fun ownsCallback(client: RemoteMediaClient, generation: Long): Boolean =
        ownsBridge() && generation == bindingGeneration && client === remoteMediaClient &&
            attachedSession === currentSession() && attachedSession?.remoteMediaClient === client

    private val castStateListener = CastStateListener { if (ownsBridge()) bridge.emit() }
    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            if (!ownsSession(session)) return
            prospectiveSession = session
            bridge.detachedState = DebrifyCastState.CONNECTING
            bridge.detachedErrorCode = null
            bridge.emit()
        }
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            if (!ownsSession(session)) return
            bindSession(session)
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            if (!ownsBridge() || prospectiveSession !== session ||
                (currentSession() != null && currentSession() !== session)) return
            prospectiveSession = null
            bridge.detachedState = DebrifyCastState.ERROR
            bridge.detachedErrorCode = "CAST_SESSION_START_FAILED"
            bridge.emit()
        }
        override fun onSessionEnding(session: CastSession) {
            if (!ownsBridge() || attachedSession !== session) return
            ledger?.capture()
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            if (!ownsBridge() || (attachedSession !== session && prospectiveSession !== session)) return
            unbindRemoteClient()
            attachedSession = null
            prospectiveSession = null
            ledger = null
            bridge.detachedState = DebrifyCastState.DISCONNECTED
            bridge.detachedErrorCode = if (error != 0) "CAST_SESSION_LOST" else null
            bridge.emit()
        }
        override fun onSessionResuming(session: CastSession, sessionId: String) {
            if (!ownsSession(session)) return
            prospectiveSession = session
            bridge.detachedState = DebrifyCastState.CONNECTING
            bridge.emit()
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            if (!ownsSession(session)) return
            bindSession(session)
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            if (!ownsBridge() || (attachedSession !== session && prospectiveSession !== session) ||
                (currentSession() != null && currentSession() !== session)) return
            unbindRemoteClient()
            attachedSession = null
            prospectiveSession = null
            ledger = null
            bridge.detachedState = DebrifyCastState.ERROR
            bridge.detachedErrorCode = "CAST_SESSION_LOST"
            bridge.emit()
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            if (!ownsSession(session) || attachedSession !== session) return
            ledger?.capture()
            bridge.detachedState = DebrifyCastState.CONNECTING
            bridge.detachedErrorCode = "CAST_SESSION_LOST"
            bridge.emit()
        }
    }

    init {
        val previousOwner = bridge.owner
        bridge.owner = this
        // Previous owner's disposal cannot unregister the engine-scoped channels
        // or subscriber now used by this owner.
        previousOwner?.dispose()
        initializeCastContext()
    }

    private fun initializeCastContext() {
        if (!ownsBridge() || castContext != null) return
        try {
            val context = CastContext.getSharedInstance(activity)
            castContext = context
            bridge.context = context
            observeRetirement(context)
            context.addCastStateListener(castStateListener)
            context.sessionManager.addSessionManagerListener(sessionListener, CastSession::class.java)
            synchronizeSession()
            bridge.emit()
        } catch (_: Exception) {
            bridge.detachedState = DebrifyCastState.ERROR
            bridge.detachedErrorCode = "CAST_UNAVAILABLE"
            bridge.emit()
        }
    }

    private fun synchronizeSession() {
        if (!ownsBridge()) return
        val session = currentSession()
        val client = session?.takeIf { it.isConnected }?.remoteMediaClient
        if (session != null && client != null) {
            if (session !== attachedSession || client !== remoteMediaClient) bindSession(session)
        } else if (attachedSession !== session) {
            unbindRemoteClient()
            attachedSession = null
            ledger = null
            bridge.detachedState = DebrifyCastState.DISCONNECTED
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!ownsBridge()) {
            result.error("CAST_DISPOSED", "Cast bridge is no longer attached.", null)
            return
        }
        when (call.method) {
            "openCastDialog", "requestSession" -> openCastDialog(result)
            "loadMedia" -> loadMedia(call.arguments, result)
            "play" -> runRemoteCommand(call, result) { it.play() }
            "pause" -> runRemoteCommand(call, result) { it.pause() }
            "stop" -> runRemoteCommand(call, result) { it.stop() }
            "seek" -> seek(call, result)
            "selectAudioTrack" -> selectAudioTrack(call, result)
            "selectSubtitleTrack" -> selectSubtitleTrack(call, result)
            "disableSubtitles" -> disableSubtitles(call, result)
            else -> result.notImplemented()
        }
    }

    fun onHostResumed() {
        if (!ownsBridge()) return
        initializeCastContext()
        synchronizeSession()
        bridge.emit()
    }
    fun onHostPaused() { if (ownsBridge()) bridge.emit() }

    private fun openCastDialog(result: MethodChannel.Result) {
        val context = castContext
        if (context == null) {
            result.error("CAST_UNAVAILABLE", "Google Cast is unavailable.", null)
            return
        }
        try {
            if (context.sessionManager.currentCastSession?.isConnected == true) {
                MediaRouteControllerDialog(activity).show()
            } else {
                MediaRouteChooserDialog(activity).apply { setRouteSelector(context.mergedSelector) }.show()
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
        val receiver = connectedLedger(result) ?: return
        val expectedEpoch = raw["expectedSessionEpoch"] as? String
        if (expectedEpoch == null || expectedEpoch != receiver.sessionEpoch) {
            result.error("CAST_STALE_LOAD", "Cast session changed before LOAD dispatch.", null)
            return
        }
        val load = try {
            val builder = com.google.android.gms.cast.MediaLoadRequestData.Builder()
                .setMediaInfo(request.toMediaInfo()).setAutoplay(request.autoplay)
            request.positionMs?.let(builder::setCurrentTime)
            builder.build()
        } catch (_: Exception) {
            result.error("CAST_BAD_REQUEST", "Cast media metadata is invalid.", null)
            return
        }
        startPhysicalOperation(bridge, receiver, result) { it.load(load) }
    }

    private fun connectedLedger(result: MethodChannel.Result): ReceiverLedger? {
        synchronizeSession()
        val session = currentSession()
        val client = session?.takeIf { it.isConnected }?.remoteMediaClient
        val receiver = ledger
        if (!ownsBridge() || client == null || client !== remoteMediaClient ||
            session !== attachedSession || receiver == null || receiver.retired) {
            result.error("CAST_SESSION_LOST", "No active Cast session.", null)
            return null
        }
        return receiver
    }

    private fun controlLedger(call: MethodCall, result: MethodChannel.Result): ReceiverLedger? {
        // Bind first: track IDs and receiver identity must come from this client.
        val receiver = connectedLedger(result) ?: return null
        val arguments = call.arguments as? Map<*, *>
        val epoch = arguments?.get("expectedSessionEpoch") as? String
        val contentId = arguments?.get("expectedContentId") as? String
        val mediaSessionId = integerValue(arguments?.get("expectedMediaSessionId"))
        if (epoch == null || contentId == null || mediaSessionId == null || mediaSessionId <= 0 ||
            receiver.sessionEpoch != epoch || receiver.client.mediaInfo?.contentId != contentId ||
            receiver.client.mediaStatus?.mediaSessionId?.toLong() != mediaSessionId) {
            result.error("CAST_STALE_COMMAND", "Command target is no longer active.", null)
            return null
        }
        if (receiver.ending || endingSessions.isNotEmpty() || physicalOperationExists()) {
            result.error(
                "CAST_RECEIVER_OPERATION_BLOCKED",
                "A receiver operation is still pending. End the Cast session before reconnecting.", null,
            )
            return null
        }
        return receiver
    }

    private fun runRemoteCommand(
        call: MethodCall,
        result: MethodChannel.Result,
        command: (RemoteMediaClient) -> PendingResult<RemoteMediaClient.MediaChannelResult>,
    ) {
        val receiver = controlLedger(call, result) ?: return
        startPhysicalOperation(bridge, receiver, result, command)
    }

    private fun seek(call: MethodCall, result: MethodChannel.Result) {
        val positionMs = integerValue((call.arguments as? Map<*, *>)?.get("positionMs"))
        if (positionMs == null || positionMs < 0) {
            result.error("CAST_BAD_SEEK", "A non-negative seek position is required.", null)
            return
        }
        val receiver = controlLedger(call, result) ?: return
        val options = MediaSeekOptions.Builder().setPosition(positionMs)
            .setResumeState(MediaSeekOptions.RESUME_STATE_UNCHANGED).build()
        startPhysicalOperation(bridge, receiver, result) { it.seek(options) }
    }

    private fun integerValue(raw: Any?): Long? = when (raw) {
        is Long -> raw
        is Int -> raw.toLong()
        is Short -> raw.toLong()
        is Byte -> raw.toLong()
        else -> null
    }

    private fun parseTrackId(call: MethodCall): Long? = when (val raw = (call.arguments as? Map<*, *>)?.get("trackId")) {
        is String -> raw.toLongOrNull()
        else -> integerValue(raw)
    }

    private fun selectAudioTrack(call: MethodCall, result: MethodChannel.Result) {
        val receiver = controlLedger(call, result) ?: return
        val id = parseTrackId(call)
        if (id == null || receiver.client.mediaInfo?.mediaTracks.orEmpty()
                .none { it.id == id && it.type == MediaTrack.TYPE_AUDIO }) {
            result.error("CAST_TRACK_NOT_FOUND", "The requested audio track is not available.", null)
            return
        }
        result.error(
            "CAST_AUDIO_TRACK_UNSUPPORTED_RECEIVER",
            "Remote audio-track selection requires a Custom Cast Receiver.", mapOf("trackId" to id),
        )
    }

    private fun activeTrackIdsExcluding(client: RemoteMediaClient, type: Int): List<Long> {
        val excluded = client.mediaInfo?.mediaTracks.orEmpty().filter { it.type == type }.map { it.id }.toSet()
        return client.mediaStatus?.activeTrackIds?.toList().orEmpty().filterNot { it in excluded }
    }

    private fun selectSubtitleTrack(call: MethodCall, result: MethodChannel.Result) {
        val receiver = controlLedger(call, result) ?: return
        val id = parseTrackId(call)
        if (id == null || receiver.client.mediaInfo?.mediaTracks.orEmpty()
                .none { it.id == id && it.type == MediaTrack.TYPE_TEXT }) {
            result.error("CAST_TRACK_NOT_FOUND", "The requested subtitle track is not available.", null)
            return
        }
        val active = activeTrackIdsExcluding(receiver.client, MediaTrack.TYPE_TEXT) + id
        startPhysicalOperation(bridge, receiver, result) { it.setActiveMediaTracks(active.toLongArray()) }
    }

    private fun disableSubtitles(call: MethodCall, result: MethodChannel.Result) {
        val receiver = controlLedger(call, result) ?: return
        val active = activeTrackIdsExcluding(receiver.client, MediaTrack.TYPE_TEXT).toLongArray()
        startPhysicalOperation(bridge, receiver, result) { it.setActiveMediaTracks(active) }
    }

    private fun bindSession(session: CastSession) {
        if (!ownsSession(session) || !session.isConnected || isRetired(session)) return
        val client = session.remoteMediaClient ?: return
        unbindRemoteClient()
        attachedSession = session
        prospectiveSession = null
        remoteMediaClient = client
        ledger = ledgerFor(session, client)
        bridge.lastLedger = ledger
        bridge.detachedErrorCode = null
        val generation = ++bindingGeneration
        val callback = object : RemoteMediaClient.Callback() {
            override fun onStatusUpdated() {
                if (!ownsCallback(client, generation)) return
                ledger?.capture()
                if (client.isPlaying || client.isPaused) {
                    ledger?.mediaErrorActive = false
                    if (ledger?.errorCode == "CAST_MEDIA_ERROR") ledger?.errorCode = null
                }
                bridge.emit()
            }
            override fun onMetadataUpdated() {
                if (ownsCallback(client, generation)) bridge.emit()
            }
            override fun onMediaError(mediaError: com.google.android.gms.cast.MediaError) {
                if (!ownsCallback(client, generation)) return
                ledger?.capture()
                ledger?.mediaErrorActive = true
                ledger?.errorCode = "CAST_MEDIA_ERROR"
                bridge.emit()
            }
        }
        val progress = RemoteMediaClient.ProgressListener { _, _ ->
            if (ownsCallback(client, generation)) bridge.emit()
        }
        boundCallback = callback
        boundProgress = progress
        client.registerCallback(callback)
        client.addProgressListener(progress, PROGRESS_PERIOD_MS)
        client.requestStatus()
        bridge.emit()
    }

    private fun unbindRemoteClient() {
        ++bindingGeneration
        val client = remoteMediaClient
        val callback = boundCallback
        val progress = boundProgress
        remoteMediaClient = null
        boundCallback = null
        boundProgress = null
        if (client != null && callback != null) runCatching { client.unregisterCallback(callback) }
        if (client != null && progress != null) runCatching { client.removeProgressListener(progress) }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        unbindRemoteClient()
        attachedSession = null
        prospectiveSession = null
        ledger = null
        castContext?.let { context ->
            runCatching { context.removeCastStateListener(castStateListener) }
            runCatching { context.sessionManager.removeSessionManagerListener(sessionListener, CastSession::class.java) }
        }
        if (bridge.owner === this) bridge.owner = null
        // Engine channels, subscriber, epochs and physical ledger survive.
        // Disposal alone is not evidence that a receiver command was cancelled.
        castContext = null
    }
}
