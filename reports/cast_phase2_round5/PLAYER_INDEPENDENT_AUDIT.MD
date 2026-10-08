# Independent native-reviewer player audit

READ-ONLY review of the other author's integrated player/helper/source-sheet implementation. Baseline HEAD 7f288ecc79def0eb5a7439abc3fc5a74ec39772e. This artifact records static source findings; authored tests were NOT RUN.

Final reviewed source blobs:
- lib/screens/video_player_screen.dart: 9d8d628171ebab1c4339047e862d12a023a6c9ff
- lib/services/cast_player_authority.dart: c98b280cf7d9cc2236ebda883988a27935bd6765
- lib/screens/video_player/widgets/source_sheet.dart: 1769c4a21e58306a9bbaa96a1b5c6ba73e15acdb
- test/services/cast_player_authority_test.dart: b3e498c448a54d6d8857912cd19f37177508031b
- test/source_sheet_cast_intent_test.dart: 1b8980af7ed1c20083d67c3715d32810b9f4f3f9

## Closed by reviewed source traces

- Navigation/source tap claims its generation synchronously before provider/guide awaits; nested requests retain the originating generation. Old resolvers cannot mint fresh intent. Local resolver completions require unchanged local ownership/effect identity before publishing playlists.
- Completion tickets carry generation, opaque bridge, opaque epoch, media session ID, URL and ENDED sequence. Deduplication and immutable outgoing tracking targets prevent repeated completion and B clock attribution to A.
- Accepted physical receiver identity is separate from failed newer provider intent, retaining P telemetry while uncommitted physical LOAD/control events lack authority.
- Local pause/yield failures no longer publish Cast ownership/tracking first. Production helper now owns the publication callback after successful pause and revalidated permission; the authored failure test uses that actual callback, rather than a constant counter. Transfer remains retained and error/retry is surfaced.
- Initial transfer settlement requires same attempt, no accepted live receiver, and no physical/uncertain fence; post-retirement physical drain triggers cleanup. Known accepted live media remains transferable until explicit verified retry or confirmed retirement.
- Suspension/quarantine stops local/Cast heartbeat sessions, and queued nonhistorical local tracker work requires local ownership. Blocked transfer affords native controller/reconnect recovery without another LOAD.
- Language manual revision is captured after logical series/profile binding and automatic policies do not increment manual revision. Stored language writes require unchanged manual/media/profile/series tickets.

## Final-cycle P1 closed by reread source traces

1. CLOSED: Restored adoption local-navigation authority: _maybeAdoptRestoredCastSession captures local request A and awaits refresh, but its return checks only native identity. Local source/episode B can land meanwhile and still satisfy those checks; the method then adopts Cast A and pauses B under B metadata. Repair: capture local effect/ownership/profile/current request authority before refresh and revalidate before beginCastNavigation/adoption. The integrated method now captures the production player effect/ownership/profile and rechecks current request URL after guarded refresh, before adoption. A deferred-refresh source-change helper regression is authored and not run.
2. CLOSED: Restore receiver-lifecycle authority: _restoreLocalAfterCast preflights settled retirement only before asynchronous open/seek. Its current closure omits wire connected/epoch, blockers, physical flight and profile. A new B epoch can connect during restore with no accepted service identity, after which the helper still plays/commits local. Repair: continuously require confirmed null-epoch disconnected wire reality and no uncertainty/physical work, plus same profile/attempt before each operation/publication. The integrated current closure now requires same profile, no physical flight/uncertainty, and disconnected null-epoch receiver state at every helper continuation. A deferred seek/reconnect helper regression is authored and not run.
3. CLOSED: The same profile capture must precede initial LOAD/seek and retry refresh; capturing only in yield after prior awaits lets an old profile attempt publish under the new profile. The integrated LOAD and alignment permissions now retain the original profile; retry guarded refresh and yield explicitly carry that original scope. Screen profile ownership itself is fixed to its creation profile.

No tests, compiler/analyzer/formatter, application builds, Flutter/Dart/Gradle/Actions, commits, pushes or remote mutations were run. Git source hashes, source reads and git diff --check are the only verification performed. SDK/device/runtime behavior remains unverified.

The reconnect-during-restore retained transfer now exposes the native device/controller UI through Cast, allowing confirmed retirement before retrying local restore. The adoption/profile/receiver-restoration findings above are closed at these hashes. New author edits after the recorded hashes require a delta reread; this is not a compilation or runtime claim.

## Follow-up sleep/lifecycle P1 CLOSED by final source reread

P1 evolving sleep/lifecycle intent during restore: helper receives captured shouldPlay before open/seek awaits. A pending seek plus _fireSleepTimer sets _sleepStopLatched=true during transferringToLocal (therefore no physical local pause), then old setPlaying(true) resumes and resets active intent. Live pause/sleep/background intent must be sampled immediately before dispatch, rather than before awaits. The background callback must recognize pending local transfer as a transition so its flag is armed even when mpv is already parked. Sent to player author/root; regression requested.

The same sleep-stop family affects transferringToCast: the timer currently sends neither local nor remote pause when no Cast publication exists, so hung LOAD can leave mpv playing and successful eventual LOAD can publish a playing receiver despite the latch. Local renderer should pause immediately; remote pending work must drain physically before a same-attempt/profile/media guarded receiver pause, with uncertainty retained if pause cannot be proven. This is not permission to fabricate LOAD cancellation.

Final closure: restore now samples production shouldPlayNow immediately before setPlaying, writes sampled intent, and considers local transfer as a background transition. Sleep timer pauses mpv immediately in either transfer. The production yield helper awaits settleReceiver before publication; the screen physically pauses exact verified accepted receiver when sleep stopped, then rechecks the same attempt/profile/media permission. Ambiguous pause remains physically excluded and does not publish successful handoff. Authored deferred seek/sleep and local-yield/receiver-pause ordering helper tests were read but NOT RUN. Profile-change pause errors are caught; PiP requires local/profile ownership. SourceSheet preserves a current selection across its own authority change and retires old provider fetch contexts at the synchronous tap; its telemetry rebuild regression was read but NOT RUN.

No open P0/P1 found in the final scoped, exact-hash source traces. Regression coverage is helper/fake-transport source evidence, not compiled/widget/device test execution.
