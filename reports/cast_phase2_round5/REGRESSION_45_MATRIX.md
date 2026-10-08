# Round 5 regression matrix

45 distinct mandatory cases. AUTHORED / NOT RUN. Additional cases are separately inventoried. Production helpers/transport and widget harnesses are referenced explicitly; none establishes SDK/device execution.

## C13 — manual seek validates exact committed URL media ID and epoch

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:136`
- Initial: Accepted P URL/SID/epoch
- Adversarial: Seek with wrong URL or SID, then exact identity
- Expected: Wrong seeks do not dispatch; exact lease accompanies native seek
- Assertions: `expect(await f.service.seekForCommittedMedia(const Duration(seconds: 40),`; `expect(await f.service.seekForCommittedMedia(const Duration(seconds: 40),`; `expect(args['expectedContentId'], pUrl);`; `expect(args['expectedMediaSessionId'], 1);`; `expect(args['expectedSessionEpoch'], 'session-1');`; `expect((await seek)!.position, const Duration(seconds: 40));`
- Status: **AUTHORED / NOT RUN**.

## C14 — deferred percent seek cancels when navigation supersedes ticket

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:158`
- Initial: Prepared 50% automatic seek with old ticket
- Adversarial: New navigation cancels start-percent gate
- Expected: No claim and no native seek for stale intent
- Assertions: `expect(gate.claim(contentId: aUrl, mediaSessionId: 2,`; `expect(await f.service.seekForCommittedMedia(const Duration(seconds: 50),`; `expect(f.native.count('seek'), 0);`
- Status: **AUTHORED / NOT RUN**.

## C15 — a manual seek never dispatches while LOAD is physical

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:176`
- Initial: P accepted while A LOAD physically outstanding
- Adversarial: User seeks P before LOAD reply
- Expected: Seek never reaches receiver during physical LOAD
- Assertions: `expect(await f.service.seekForCommittedMedia(const Duration(seconds: 20),`; `expect(f.native.count('seek'), 0);`; `expect((await load).committed, isTrue);`
- Status: **AUTHORED / NOT RUN**.

## C16 — later LOAD waits for previously dispatched seek physical ACK

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:191`
- Initial: Physical P seek outstanding
- Adversarial: Submit newer B LOAD before seek ACK
- Expected: B waits for actual seek completion
- Assertions: `expect(f.native.count('loadMedia'), 0);`; `expect(await seek, isNull);`; `expect(f.native.count('loadMedia'), 1);`; `expect((await load).committed, isTrue);`; `expect(f.service.snapshot.mediaContentId, bUrl);`
- Status: **AUTHORED / NOT RUN**.

## C17 — timed-out seek cannot commit late and still excludes next LOAD

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:213`
- Initial: One-second virtual deadline on physical seek
- Adversarial: Timeout seek, then begin B before late ACK
- Expected: Late seek cannot rewrite accepted clock and still excludes B
- Assertions: `expect(callerSettled, isTrue);`; `expect(response, isNull);`; `expect(f.service.receiverLoadBlocked, isTrue);`; `expect(f.native.count('loadMedia'), 0);`; `expect(f.service.position, const Duration(seconds: 12));`; `expect(f.native.count('loadMedia'), 1);`; `expect(committed!.committed, isTrue);`
- Status: **AUTHORED / NOT RUN**.

## C18 — late pause ACK and event never rewrite clock in either channel order

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:247`
- Initial: Physical pause for accepted P pending
- Adversarial: New navigation begins before old pause ACK
- Expected: Old ACK cannot rewrite accepted playback clock
- Assertions: `final rejected = expectLater(pause, throwsA(isA<CastException>()));`; `expect(f.service.position, const Duration(seconds: 12));`; `expect(f.service.state, CastPlaybackState.playing);`; `expect(f.service.state, CastPlaybackState.playing);`; `expect(f.service.position, const Duration(seconds: 12));`; `expect(f.service.receiverRecoveryRequired, isTrue);`; `expect(f.service.hasLoadInFlight, isFalse);`; `expect(f.service.adoptVerifiedReceiverIdentity(fresh: fresh,`; `expect(f.service.receiverRecoveryRequired, isFalse);`; `expect(f.service.position, const Duration(seconds: 90));`; `expect(f.service.state, CastPlaybackState.paused);`
- Status: **AUTHORED / NOT RUN**.

## E37 — old tracker STOP uses A clock and settles before B starts

- Production: `lib/screens/video_player_screen.dart` / `_captureCastTrackingTarget`; `lib/screens/video_player_screen.dart` / `_stopCastTrackingForNavigation`; `lib/screens/video_player_screen.dart` / `_queueTrackerEffect`; `lib/services/cast_player_authority.dart` / `CastPlayerTrackingTarget`; `lib/services/cast_player_authority.dart` / `CastPlayerTrackingQueue`
- Test: `test/services/cast_player_authority_test.dart:155`
- Initial: {"incoming": "ttB S2E1 0/40min", "outgoing": "ttA S1E4 70/100min"}
- Adversarial: capture immutable outgoing target; enqueue pending A STOP; enqueue B START; resolve A STOP
- Expected: A STOP carries 70%, S1E4; B START does not dispatch while A STOP pending; B START follows A STOP at 0%
- Assertions: `expect(calls, ['stop:ttA:4:70.0']);`; `expect(calls, ['stop:ttA:4:70.0', 'start:ttB:0.0']);`
- Status: **AUTHORED / NOT RUN**.

## E38 — ended continuation is rejected after newer navigation

- Production: `lib/screens/video_player_screen.dart` / `_castEffectTicket`; `lib/screens/video_player_screen.dart` / `_handleCastEnded`; `lib/services/cast_player_authority.dart` / `CastPlayerEffectTicket`
- Test: `test/services/cast_player_authority_test.dart:179`
- Initial: {"initial": "generation1/bridge/session1/media7/A/ended5", "replacement": "generation2/media8/B"}
- Adversarial: capture ended ticket; await deferred completion; replace navigation/media; resolve pending completion
- Expected: ticket invalid; zero old auto-advance effects
- Assertions: `expect(await effect, isFalse);`; `expect(advances, 0);`
- Status: **AUTHORED / NOT RUN**.

## E39 — same URL and media session from another epoch has no authority

- Production: `lib/screens/video_player_screen.dart` / `_castMediaIdentity`; `lib/screens/video_player_screen.dart` / `_castEffectTicket`; `lib/services/cast_player_authority.dart` / `CastPlayerMediaIdentity`; `lib/services/cast_player_authority.dart` / `CastPlayerEffectTicket`
- Test: `test/services/cast_player_authority_test.dart:197`
- Initial: {"initialEpoch": "session1", "newEpoch": "session2", "same": "bridge/media7/A/generation1"}
- Adversarial: capture valid ticket; change only physical epoch; restore epoch then increase endedSequence
- Expected: epoch change invalidates ticket; new ended sequence invalidates old continuation
- Assertions: `expect(ticket.isCurrent, isTrue);`; `expect(ticket.isCurrent, isFalse);`; `expect(ticket.isCurrent, isFalse);`
- Status: **AUTHORED / NOT RUN**.

## E40 — threshold and ended claim one immutable effective completion

- Production: `lib/screens/video_player_screen.dart` / `_captureCompletionTarget`; `lib/screens/video_player_screen.dart` / `_markCurrentEpisodeAsFinished`; `lib/screens/video_player_screen.dart` / `_resetLocalCompletionState`; `lib/services/cast_player_authority.dart` / `CastPlayerCompletionTarget`; `lib/services/cast_player_authority.dart` / `CastPlayerCompletionGate`
- Test: `test/services/cast_player_authority_test.dart:208`
- Initial: {"currentContent": "ttB Current show S2E3", "launchContent": "A excluded from target"}
- Adversarial: claim current effective completion; claim again from ended; reset on committed media change; claim rewatch
- Expected: exactly one claim per current media; target retains effective B identity; new play may claim again
- Assertions: `expect(gate.claim(completion.key), isTrue);`; `expect(gate.claim(completion.key), isFalse);`; `expect(completion.imdbId, 'ttB');`; `expect(completion.episode, 3);`; `expect(gate.claim(completion.key), isTrue);`
- Status: **AUTHORED / NOT RUN**.

## E41 — disconnect opens committed B before seeking and restoring play

- Production: `lib/screens/video_player_screen.dart` / `_restoreLocalAfterCast`; `lib/services/cast_player_authority.dart` / `CastPlayerRestorePlan`
- Test: `test/services/cast_player_authority_test.dart:220`
- Initial: {"committedCast": "B", "parkedLocal": "A", "resumeSeconds": 24, "shouldPlay": true}
- Adversarial: execute production restore orchestration; open B; seek B to24; play B
- Expected: open:B precedes seek:B:24; play:B:true follows seek; successful restore result
- Assertions: `expect(restored, isTrue);`; `expect(localUrl, 'B');`; `expect(calls, ['open:B', 'seek:B:24', 'play:B:true']);`
- Status: **AUTHORED / NOT RUN**.

## E42 — foreground resume rejects both transfers and Cast ownership

- Production: `lib/screens/video_player_screen.dart` / `_resumeFromBackground`; `lib/services/cast_player_authority.dart` / `CastPlayerRestorePlan`
- Test: `test/services/cast_player_authority_test.dart:236`
- Initial: {"productionOwnership": "PlaybackOwnershipController", "sleepStopped": false}
- Adversarial: begin Cast transfer; foreground; commit Cast; foreground; begin local transfer; foreground; commit local; foreground
- Expected: zero local starts in either transfer and Cast; one local start only after committed local ownership; sleep latch rejects local resume
- Assertions: `expect(localStarts, 0);`; `expect(localStarts, 1);`; `expect(CastPlayerRestorePlan.mayResumeLocal(localOwnsPlayback: true,`
- Status: **AUTHORED / NOT RUN**.

## I01 — slow A, fast B intent: stale A never commits

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:32`
- Initial: A physical LOAD active, B newer intent
- Adversarial: Complete obsolete A before B
- Expected: A superseded; B commits; physical concurrency remains one
- Assertions: `expect((await a).outcome, CastLoadOutcome.superseded);`; `expect(f.started, ['A']);`; `expect(f.started, ['A', 'B']);`; `expect((await b).outcome, CastLoadOutcome.committed);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## I02 — late provider A cannot enqueue after B has begun

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:49`
- Initial: A provider ticket captured, B already current
- Adversarial: Late provider A submits with old ticket
- Expected: A never reaches gateway; B retains authority
- Assertions: `expect(aResult.outcome, CastLoadOutcome.superseded);`; `expect(f.started, ['B']);`; `expect((await bResult).committed, true);`
- Status: **AUTHORED / NOT RUN**.

## I03 — A in flight, B/C queued: B settles, only C is dispatched

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:62`
- Initial: A active; B then C queued
- Adversarial: Resolve A after replacing B with C
- Expected: Only C dispatches after A; B settles superseded
- Assertions: `expect((await af).outcome, CastLoadOutcome.superseded);`; `expect((await bf).outcome, CastLoadOutcome.superseded);`; `expect(f.started, ['A', 'C']);`; `expect((await cf).committed, true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## I04 — current rejected load never promotes an older request

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:491`
- Initial: Current A rejected by identity verification
- Adversarial: Introduce subsequent current request
- Expected: Rejected A cannot be promoted as rollback or authority
- Assertions: `expect((await old).outcome, CastLoadOutcome.superseded);`; `expect(f.started, ['A', 'B']);`; `expect((await newer).outcome, CastLoadOutcome.failed);`; `expect(q.isCurrent(oldTicket), false);`; `expect(q.isCurrent(currentTicket), true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## I05 — cancelled ticket never invokes deferred LOAD factory

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:383`
- Initial: Captured ticket explicitly invalidated
- Adversarial: Submit deferred physical factory
- Expected: Factory not invoked, caller settles superseded
- Assertions: `expect(response.outcome, CastLoadOutcome.superseded);`; `expect(invoked, 0);`
- Status: **AUTHORED / NOT RUN**.

## I06 — local source fallback preserves local telemetry and ownership

- Production: `lib/services/cast_phase2_policy.dart` / `PlaybackOwnershipController`; `lib/services/cast_phase2_policy.dart` / `CastSourceCompatibility`
- Test: `test/services/cast_service_coordination_test.dart:124`
- Initial: Local owner and local-only file source
- Adversarial: Attempt incompatible Cast transfer then cancel
- Expected: Local telemetry and recovery ownership remain local
- Assertions: `expect(CastSourceCompatibility.classify(url: 'file:///local.mp4').canAttempt,`; `expect(ownership.isLocal, isTrue);`; `expect(ownership.acceptsLocalTelemetry, isTrue);`; `expect(ownership.owner, PlaybackOwner.local);`; `expect(StremioTvNextRecovery.canResumeLocal(ownership.owner, true), isTrue);`
- Status: **AUTHORED / NOT RUN**.

## L07 — reentrant completion submits later request only after old completion

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:188`
- Initial: Active A; caller completion may enqueue B reentrantly
- Adversarial: Complete A and submit new LOAD
- Expected: Physical A settles before B starts; max one
- Assertions: `expect(f.started, ['A', 'B']);`; `expect((await later).committed, true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## L08 — pending replacement within same generation dispatches only final

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:321`
- Initial: A active and same-generation pending B
- Adversarial: Replace queued B with final C
- Expected: B settles superseded, only final pending command dispatches
- Assertions: `expect((await firstQueued).outcome, CastLoadOutcome.superseded);`; `expect((await active).committed, true);`; `expect(f.started, ['busy', 'latest']);`; `expect((await lastQueued).committed, true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## L09 — timeout settles caller without releasing physical exclusion

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:160`
- Initial: A underlying native Future unresolved, B pending
- Adversarial: Expire logical deadline using virtual clock
- Expected: Caller fails but physical exclusion remains until native ACK
- Assertions: `expect(first!.outcome, CastLoadOutcome.failed);`; `expect(q.isBlockedOnReceiver, isTrue);`; `expect(f.started, ['A']);`; `expect(f.started, ['A', 'B']);`; `expect(second!.committed, isTrue);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## L10 — stale physical ACK is observed but cannot become logical commit

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:291`
- Initial: A obsolete after B intent
- Adversarial: Late physical ACK for A
- Expected: Observer sees reality; logical A never commits
- Assertions: `expect((await first).outcome, CastLoadOutcome.superseded);`; `expect(observed, ['$firstTicket:A']);`; `expect((await later).committed, true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## L11 — A fails while newer B is pending; B drains

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:81`
- Initial: A physical active with newer B pending
- Adversarial: Complete A with transport error
- Expected: A superseded; B drains only after physical A returns
- Assertions: `expect((await af).outcome, CastLoadOutcome.superseded);`; `expect((await bf).committed, true);`; `expect(f.maxRunning, 1);`
- Status: **AUTHORED / NOT RUN**.

## L12 — dispose settles physical and queued callers exactly once

- Production: `lib/services/cast_load_coordinator.dart` / `CastLoadCoordinator`
- Test: `test/services/cast_load_coordinator_test.dart:205`
- Initial: Active and pending LOAD callers
- Adversarial: Dispose coordinator before physical reply
- Expected: Callers settle cancelled exactly once; no later dispatch
- Assertions: `expect((await af).outcome, CastLoadOutcome.superseded);`; `expect((await bf).outcome, CastLoadOutcome.cancelled);`; `expect(f.started, ['A']);`; `expect(cr.outcome, CastLoadOutcome.cancelled);`
- Status: **AUTHORED / NOT RUN**.

## P43 — Phase 1 load initializes before epoch capture and preserves errors

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:552`
- Initial: Fresh uninitialized Phase1 public service
- Adversarial: Call load, invalid URL, then connect
- Expected: Initialization precedes epoch capture; specific errors preserved; no invalid LOAD
- Assertions: `expect(native.count('loadMedia'), 1);`; `expect((await first).mediaContentId, aUrl);`; `await expectLater(invalid, throwsA(isA<CastException>().having(`; `expect(native.count('loadMedia'), 1);`; `expect(await service.connect(), isTrue);`
- Status: **AUTHORED / NOT RUN**.

## P44 — split audio/video stream cannot masquerade as direct receiver media

- Production: `lib/services/cast_phase2_policy.dart` / `CastSourceCompatibility`
- Test: `test/services/cast_stream_security_round5_test.dart:32`
- Initial: Receiver sender given split audio/video URLs
- Adversarial: Classify split MPD/audio then multiplexed/unknown stream
- Expected: Split blocked; supported multiplexed and unknown codec policy preserved
- Assertions: `expect(split.kind, CastSourceCompatibilityKind.unsupportedAudioVideoLayout);`; `expect(split.canAttempt, isFalse);`; `expect(split.reason, contains('Separate audio/video'));`; `expect(multiplexed.kind, CastSourceCompatibilityKind.supported);`; `expect(multiplexed.canAttempt, isTrue);`; `expect(unknown.kind, CastSourceCompatibilityKind.unknown);`; `expect(unknown.canAttempt, isTrue);`
- Status: **AUTHORED / NOT RUN**.

## P45 — credential headers are rejected before any native LOAD transmission

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_stream_security_round5_test.dart:49`
- Initial: Observed previous native media snapshot; request with protected Authorization header (no claim of accepted/adopted ownership)
- Adversarial: Invoke public load with secret header
- Expected: Specific unsupported-headers failure; no native LOAD or secret transmission
- Assertions: `await expectLater(service.load(request), throwsA(isA<CastException>()`; `expect(transport.methods, isNot(contains('loadMedia')));`; `expect(transport.arguments.any((value) =>`; `expect(service.snapshot.mediaContentId, 'https://media.example/previous.mp4');`
- Status: **AUTHORED / NOT RUN**.

## R25 — superseded physical A ACK is observed without committing A

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:350`
- Initial: P accepted, A physical active, B supersedes
- Adversarial: Late successful physical A arrives
- Expected: Wire A observed; UI/tracking clock P frozen; recovery explicit
- Assertions: `expect(f.service.receiverRecoveryRequired, isTrue);`; `expect(f.service.snapshot.mediaContentId, pUrl);`; `expect(f.service.position, const Duration(seconds: 12));`; `expect((await f.service.refresh()).mediaContentId, aUrl);`
- Status: **AUTHORED / NOT RUN**.

## R26 — current timed-out A late ACK enters recovery with frozen P clock

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:360`
- Initial: P accepted with A current LOAD and virtual deadline
- Adversarial: Timeout caller then acknowledge A at 87 seconds
- Expected: Recovery required; P remains 12 seconds; no resurrected commit
- Assertions: `expect(outcome!.outcome, CastLoadOutcome.failed);`; `expect(f.service.receiverLoadBlocked, isTrue);`; `expect(f.service.receiverRecoveryRequired, isTrue);`; `expect(f.service.position, const Duration(seconds: 12));`; `expect(f.service.hasLoadInFlight, isFalse);`
- Status: **AUTHORED / NOT RUN**.

## R27 — verified B commit clears recovery after late A and failed B provider

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:384`
- Initial: Receiver divergence from stale A; B provider failed
- Adversarial: Later verified B LOAD succeeds
- Expected: Recovery clears only for confirmed B identity
- Assertions: `expect(f.service.receiverRecoveryRequired, isTrue);`; `expect((await load).committed, isTrue);`; `expect(f.service.receiverRecoveryRequired, isFalse);`; `expect(f.service.snapshot.mediaContentId, bUrl);`; `expect(f.service.state, CastPlaybackState.connected);`
- Status: **AUTHORED / NOT RUN**.

## R28 — provisional event does not reject earlier valid LOAD ACK

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:401`
- Initial: A LOAD pending; provisional A event revision4 at30s
- Adversarial: Older matching ACK revision3 at29s
- Expected: A commits with newest matching wire clock30s
- Assertions: `expect(f.service.position, const Duration(seconds: 12));`; `expect((await load).committed, isTrue);`; `expect(f.service.snapshot.mediaContentId, aUrl);`; `expect(f.service.position, const Duration(seconds: 30));`
- Status: **AUTHORED / NOT RUN**.

## R29 — bridge with no session retires old callbacks then reconnects

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:418`
- Initial: Old bridge-1/session-1 connected
- Adversarial: New bridge-2 disconnected, old callback, then reconnect
- Expected: Old revision999 cannot revive retired bridge; new epoch accepted
- Assertions: `expect(f.service.connected, isFalse);`; `expect(f.service.connected, isFalse);`; `expect(f.service.connected, isTrue);`; `expect(f.service.snapshot.sessionEpoch, 'session-2');`
- Status: **AUTHORED / NOT RUN**.

## R30 — proven disconnect clears recovery and preserves accepted resume

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:432`
- Initial: Divergent receiver A at87s, accepted P clock12s
- Adversarial: Confirmed disconnect snapshot
- Expected: Recovery clears; resume retains accepted P position/play intent
- Assertions: `expect(f.service.receiverRecoveryRequired, isTrue);`; `expect(f.service.receiverRecoveryRequired, isFalse);`; `expect(f.service.connected, isFalse);`; `expect(f.service.snapshot.resumePosition, const Duration(seconds: 12));`; `expect(f.service.snapshot.resumeShouldPlay, isTrue);`; `expect(f.service.state, CastPlaybackState.disconnected);`
- Status: **AUTHORED / NOT RUN**.

## S19 — fresh matching receiver identity adopts without LOAD

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:283`
- Initial: Fresh native P snapshot matching screen URL
- Adversarial: Adopt using current navigation ticket
- Expected: Exact identity accepted without native LOAD
- Assertions: `expect(service.adoptVerifiedReceiverIdentity(fresh: fresh,`; `expect(native.count('loadMedia'), 0);`; `expect(service.snapshot.mediaSessionId, 1);`
- Status: **AUTHORED / NOT RUN**.

## S20 — restored receiver with mismatching URL cannot adopt

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:296`
- Initial: Fresh P receiver snapshot
- Adversarial: Request adoption for different content URL
- Expected: Adoption denied; no LOAD or accepted identity fabrication
- Assertions: `expect(f.service.adoptVerifiedReceiverIdentity(fresh: await f.service.refresh(),`; `expect(f.native.count('loadMedia'), 0);`
- Status: **AUTHORED / NOT RUN**.

## S21 — matching restored URL with wrong media session cannot adopt

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:305`
- Initial: Current P media session 1
- Adversarial: Use restored same URL with wrong media session
- Expected: Adoption denied for mismatching SID
- Assertions: `expect(f.service.adoptVerifiedReceiverIdentity(fresh: wrong,`
- Status: **AUTHORED / NOT RUN**.

## S22 — matching restored URL and media ID with wrong epoch cannot adopt

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:314`
- Initial: Current P epoch session-1
- Adversarial: Use restored same URL/SID from another epoch
- Expected: Adoption denied despite reused URL and SID
- Assertions: `expect(f.service.adoptVerifiedReceiverIdentity(fresh: wrong,`
- Status: **AUTHORED / NOT RUN**.

## S23 — retired session callback cannot disconnect new session

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:323`
- Initial: Receiver replaced session-1 with session-2
- Adversarial: Delayed old epoch disconnection callback
- Expected: New session remains connected and authoritative
- Assertions: `expect(f.service.snapshot.sessionEpoch, 'session-2');`; `expect(f.service.connected, isTrue);`; `expect(f.service.snapshot.sessionEpoch, 'session-2');`
- Status: **AUTHORED / NOT RUN**.

## S24 — old bridge LOAD ACK after recreation cannot commit

- Production: `lib/services/cast_service.dart` / `CastService`
- Test: `test/services/cast_service_coordination_test.dart:334`
- Initial: A physical LOAD on bridge-1
- Adversarial: Recreate bridge/session before A ACK
- Expected: Old bridge ACK cannot commit or replace bridge-2
- Assertions: `expect((await load).committed, isFalse);`; `expect(f.service.snapshot.bridgeInstanceId, 'bridge-2');`; `expect(f.service.snapshot.sessionEpoch, 'session-2');`
- Status: **AUTHORED / NOT RUN**.

## T31 — language policy reads committed remote tracks after LOAD

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:446`
- Initial: New A LOAD awaiting remote tracks
- Adversarial: ACK contains English and Spanish subtitle IDs
- Expected: Policy reads committed remote list, chooses English actual ID
- Assertions: `expect((await load).committed, isTrue);`; `expect(CastLanguagePolicy.chooseSubtitle(tracks: f.service.availableSubtitleTracks,`
- Status: **AUTHORED / NOT RUN**.

## T32 — manual OFF wins over delayed automatic language preference

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:463`
- Initial: Automatic language preference Future pending
- Adversarial: User explicitly disables subtitles before preference returns
- Expected: Manual OFF remains authoritative and selection is null
- Assertions: `expect(await choice, isNull);`; `expect(f.service.sessionSubtitlesDisabled, isTrue);`
- Status: **AUTHORED / NOT RUN**.

## T33 — stale embedded subtitle result cannot change newly committed media

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:478`
- Initial: P subtitle selection physical command pending
- Adversarial: Navigate and commit B before old result applies
- Expected: Old subtitle cannot change B tracks or remembered language
- Assertions: `final stale = expectLater(selection, throwsA(isA<CastException>()));`; `expect((await load).committed, isTrue);`; `expect(f.service.selectedSubtitleTrack, isNull);`; `expect(f.service.sessionSubtitleLanguage, isNull);`
- Status: **AUTHORED / NOT RUN**.

## T34 — prepared WebVTT request leaves committed language intent untouched

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:496`
- Initial: P and Spanish language intent accepted
- Adversarial: Prepare addon English WebVTT replacement without commit
- Expected: Existing request/list/language untouched; VTT policy accepts candidate
- Assertions: `expect(CastSubtitleSupport.classify(candidate.textTracks.single.url).supported,`; `expect(previous.textTracks, isEmpty);`; `expect(f.service.availableSubtitleTracks, isEmpty);`; `expect(f.service.sessionSubtitleLanguage, 'es');`
- Status: **AUTHORED / NOT RUN**.

## T35 — rejected addon replacement retains previous track intent

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:510`
- Initial: P accepted with Spanish intent and staged addon replacement
- Adversarial: Native replacement returns failure
- Expected: Logical transaction rolls back; prior identity/language/tracks retained
- Assertions: `expect((await load).outcome, CastLoadOutcome.failed);`; `expect(identical(transaction.rollback(), previous), isTrue);`; `expect(f.service.snapshot.mediaContentId, pUrl);`; `expect(f.service.sessionSubtitleLanguage, 'es');`; `expect(f.service.availableSubtitleTracks, isEmpty);`
- Status: **AUTHORED / NOT RUN**.

## T36 — obsolete subtitle LOAD cannot clear current transition authority

- Production: `lib/services/cast_service.dart` / `CastService`; `lib/services/cast_phase2_policy.dart` / `CastLanguagePolicy`
- Test: `test/services/cast_service_coordination_test.dart:531`
- Initial: Obsolete subtitle A LOAD active and B queued
- Adversarial: Late A ACK then verified B ACK
- Expected: Obsolete result cannot clear B in-flight/current ticket authority
- Assertions: `expect((await old).committed, isFalse);`; `expect(f.service.isCurrentLoad(first), isFalse);`; `expect(f.service.isCurrentLoad(latest), isTrue);`; `expect(f.service.hasLoadInFlight, isTrue);`; `expect((await current).committed, isTrue);`; `expect(f.service.hasLoadInFlight, isFalse);`
- Status: **AUTHORED / NOT RUN**.
