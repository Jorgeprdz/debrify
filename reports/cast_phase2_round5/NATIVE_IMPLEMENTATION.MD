# Native Cast implementation review

Scope: only android/app/src/main/kotlin/com/debrify/app/cast/DebrifyCastManager.kt.
Baseline HEAD: 7f288ecc79def0eb5a7439abc3fc5a74ec39772e.
Recovered candidate Git blob: be68a5730b5a47f7833bd892ef07ccc684674e28.
Integrated/repaired native Git blob at this review: 6e2a168a2a86647848a02a20e48e7b73081b304b.
The recovered candidate was integrated with /tmp/debrify-round5-recovery/native-recovered.patch before repairs.

## Closed native findings by static trace

- Old Activity disposal clearing a replacement manager's channels: channels and stream handler now belong to persistent EngineBridge, keyed by exact messenger identity; manager disposal never unregisters them. Replacement switches owner before disposing old listeners. Old cleanup only clears bridge.owner when it still owns it.
- Lost native EventSink after same-engine Activity recreation: EngineBridge retains subscriber and always-present bridgeInstanceId/revision across manager replacement. Weak bridge registry does not keep idle destroyed engines alive.
- Late lifecycle callback binding obsolete/disposed session: all manager callbacks check bridge ownership/disposal and SDK session/client identity; bindSession independently checks current connected SDK session. Remote callbacks also check binding generation.
- Null epoch disconnected snapshots using another incarnation's watermark: bridgeInstanceId is present on all snapshots, including disconnected. revision increments on every snapshot production, including getState and ACK. A directly emitted ACK uses exactly its reply snapshot/revision.
- Physical exclusion lost on Activity/engine replacement: ReceiverLedger is global to exact SDK session/client and preserves sessionEpoch, pending SDK callback/Result, and ended counter. Manager disposal does not retire it. Other-engine pending physical work is exposed as receiverOperationBlocked.
- Commands controlling divergent receiver media: all control methods bind current SDK client first, then require exact expectedSessionEpoch/contentId/mediaSessionId; subtitle track IDs and preservation of other active tracks are read from that same client. Native snapshots show actual receiver identity instead of hiding mismatches.
- LOAD session switch between Dart preflight and native dispatch: expectedSessionEpoch is required and validated after binding, before physical LOAD dispatch.
- Hung native transport released merely on timeout: native watchdog marks uncertainty, retains SDK pending result and original method Result, and prevents all further physical load/control dispatch. Post-dispatch non-success/exception is conservatively uncertain. No cancel()/await()/synthetic cancellation is used.
- Recovery releasing exclusion merely because disconnect was dispatched: endCurrentSession(true) is allowed while blocked, but its MethodChannel result waits for exact confirmed onSessionEnded. A 30 second disconnect timeout returns CAST_DISCONNECT_PENDING without releasing the physical fence. The context-owned retirement observer survives Activity gaps and settles original physical Results exactly once with CAST_SESSION_RETIRED.

## Native contract

- bridgeInstanceId: opaque String, always present, stable for exact live messenger.
- sessionEpoch: opaque String?; stable for exact SDK session/client across Activity and engine replacement, preserved through suspension/unconfirmed detach; absent after confirmed retirement.
- snapshotRevision: Long; incremented for each produced snapshot. Same exact ACK snapshot may appear through reply and event.
- mediaSessionId: SDK numeric media session ID; endedSequence: Int.
- receiverOperationBlocked: Boolean for uncertain operations/session termination, suspended/unconfirmed lifecycle, or physical work outstanding in a different bridge/session.
- All controls require expectedSessionEpoch, expectedContentId, expectedMediaSessionId. loadMedia requires expectedSessionEpoch as an additive argument outside public request.toMap.
- Physical failures expose CAST_RECEIVER_OPERATION_BLOCKED in snapshots, preserve underlying Future for physical exclusion, and require explicit confirmed session termination if there is no later definitive successful SDK reply.

## SDK API evidence and limitations

Dependency remains play-services-cast-framework:22.3.0. No cached dependency source/artifact was located. Existing dependency usages and current official API references were read; no invented SDK methods were added.

- https://developers.google.com/android/reference/com/google/android/gms/cast/framework/media/RemoteMediaClient verifies load(MediaLoadRequestData), play(), pause(), stop(), seek(MediaSeekOptions), setActiveMediaTracks(long[]), registerCallback/unregisterCallback, and progress listener signatures. These operations return PendingResult<MediaChannelResult> and run on the main thread.
- https://developers.google.com/android/reference/com/google/android/gms/common/api/PendingResult verifies setResultCallback(ResultCallback).
- https://developers.google.com/android/reference/com/google/android/gms/cast/framework/SessionManagerListener distinguishes onSessionEnding from confirmed onSessionEnded. Resume failure alone is deliberately not treated as proof of retirement.

All post-dispatch SDK non-success statuses are conservatively treated as ambiguous; ordinary failures may require reconnecting rather than allowing an unsafe rollback through an unproven physical fence. If the SDK never confirms session termination, native exclusion intentionally remains held. This is surfaced to the user instead of falsely claiming cancellation.

Static verification performed: Git/text inspection, exact source hashes, git diff --check, API-reference reading, and callback/retirement trace review. No application tests, compiler, analyzer, formatter, Gradle, builds, Actions, commits, pushes, or remote mutations were run. Runtime/device behavior and compilation are unverified under the user's constraint.

Dart/coordinator cross-layer audit is recorded in dart-independent-audit.md; player review is recorded separately. These artifacts are static source assessments only.

## Cross-review follow-up repairs

- Retired exact SDK session objects are tombstoned and never revived solely by queued onSessionStarted/onSessionResumed against stale SDK properties.
- The context observer rejects onSessionEnding for retired objects, preventing an already-ended A from re-blocking current B indefinitely.
- Disconnected snapshots preserve a non-retired ledger epoch and set receiverOperationBlocked=true even without a pending physical operation. SDK suspension or unconfirmed detach does not establish permission to restore local playback. Confirmed onSessionEnded removes the epoch and physical fence.
- Independent Dart review identified C18: stale physical control EventChannel snapshots bypassed stale MethodChannel ACK suppression. The separate Dart author repaired this and the final source trace is closed in dart-independent-audit.md.

- Context onSessionEnding also rejects unknown never-tracked sessions that are neither an owned ending request nor any observed context currentCastSession. Such a delayed A callback cannot globally block B. Known ledger A retirement remains eligible.
- C18 paired MethodChannel/EventChannel quarantine and retirement physical-drain notification findings are closed by separately authored Dart changes, inspected read-only at service blob 17589a70be2a3df3579d88b3b36d8bf99d9efb67 / coordinator blob 52082ee48729ccc3f006f4049de63459bd7ad4bd.

- Final native self-review closed a Phase 1 ERROR-state regression: snapshot recomputation had erased onMediaError. ReceiverLedger now latches decoder error across progress/read/ACK snapshots, clears on a fresh playing/paused status or changed physical media identity, and recognizes MediaStatus.IDLE_REASON_ERROR. Official MediaStatus reference inspected: https://developers.google.com/android/reference/com/google/android/gms/cast/MediaStatus.
