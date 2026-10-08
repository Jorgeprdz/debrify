# Independent native cross-review — source only

Reviewed integrated DebrifyCastManager.kt and MainActivity attachment/disposal call sites without native edits, SDK compiler, application tests, builds, analysis or external Actions.

Confirmed and communicated P1 retired-session resurrection: prior observeStartedSession removed tombstones based only on SDK isConnected/current-session properties, allowing delayed lifecycle callbacks to revive an already retired exact SDK session. Native implementer removed resurrection of retired session objects; re-read verifies the clearing helper/calls absent.

Confirmed cross-layer P1 transient suspension: connected=false/epoch=null was interpreted by Dart as permanent retirement, retiring a resumable epoch and allowing local restoration while receiver execution was uncertain. Native now preserves non-retired ledger epoch and explicitly marks receiverOperationBlocked while disconnected without confirmed retirement. Dart retains accepted identity/clock/session intent and uses blocker independently of connected. Actual-service suspension/resume/retirement and unconfirmed-disconnect subtitle-OFF tests authored, NOT RUN. Player collaborator notified to gate local restoration before connected checks.

Confirmed pre-dispatch LOAD epoch gap: a native MethodCall could observe a different current session after Dart's preflight. Native now requires expectedSessionEpoch at loadMedia before LOAD; Dart adds field only to private transport dispatch while preserving public request-map shape.

Final source read: EngineBridge persists channels/subscriber across Activity replacement; ownership/binding-generation/client/current-session checks protect old callbacks. ReceiverLedger persists physical operation across managers/messengers; global admission rejects overlap. Watchdog and post-dispatch failure preserve Result and physical fence, surfacing blocker. Success or confirmed onSessionEnded settles once through Reply, releases physical fence, emits bridge-scoped revisions. Snapshot-producing reads/ACKs/events increment revisions; retired session properties cannot revive last ledger. Disconnect request alone does not retire ledger; deadline reports pending and preserves exclusion.

No remaining confirmed P0/P1 in this native file at this reviewed source version. This is a static source verdict only. SDK contract, compilation, runtime scheduling, actual Activity recreation and device behavior remain unexecuted/unverified. Conservative failure fences intentionally require confirmed SDK retirement when physical completion cannot be proven.

Final native decoder-error delta re-read: `ReceiverLedger.capture` resets the error latch only for a changed physical media identity (259-276); `updatePlaybackState` gives a latched media error or SDK IDLE_REASON_ERROR priority over connected state (287-295). `onMediaError` captures the current identity before setting the latch (815-820). Fresh playing/paused status clears the latch (803-809). `finishPhysicalSuccess` no longer erases an active decode error (156-163). Thus physical operation success does not claim decoding/playback success. No additional confirmed P0/P1 found in this exact source delta.

Final reviewed native Git blob: 6e2a168a2a86647848a02a20e48e7b73081b304b

Final reviewed native SHA-256: 6260aea7de5029e217a7ff15c08dabd7555a1130bc93c4a64f7fcd32f0cb097e
