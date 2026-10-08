# Independent focused player/preference audit — final source-only

Reviewed the final frozen files below without production edits or application tests/compiler/analyzer/Flutter/Dart/Gradle/build/Actions execution. Static Git whitespace verification is clean. No confirmed open P0/P1 remains in this focused scope at these exact artifacts. This is not runtime PASS or a whole-repository correctness claim.

## Repaired findings independently re-read

- Handoff: screen `_yieldLocalAndPublishCast`15546 pauses the phone before publishing Cast and rechecks original profile/generation/exact receiver identity around awaits. `_togglePlay`16112, `_seekUserPlayback`16080 and `_onPipAction`13141 reject LOCAL mutations outside LOCAL ownership/original profile. `_settleInitialCastTransfer`15518 checks live profile/sleep/lifecycle/generation/retirement immediately before queued local play. The pending-pause/Space, PiP bypass and stale rollback-play traces are closed by source inspection.
- SourceSheet `_captureFetchContext`81, listing155 and provider loops563 capture provider/season/episode/player authority and validate after provider awaits before state or merge. Parent `_sourceFetchAuthority`9985 captures profile/owner/navigation/media context; merge callback18381 validates captured parent authority. Sheet `didUpdateWidget`193 separates selection authority from fetch context. `_selectSource`478 synchronizes post-tap selection authority, synchronously retires pre-tap fetch state, preserves the current resolver on same-ticket telemetry rebuild, and lets A-current claim intent while B resolves. Late A-fetch/B-episode contamination, selection self-cancellation, stuck fetch state and A→B→A intent traces are closed. Legacy LOCAL pending-selection behavior is preserved.
- Manual languages: screen `_bindCastLanguageSeries`647 rejects obsolete original profile; series/profile changes invalidate revision and session intent. `_castManualLanguageTicket`659 validates original profile/CAST ownership/no physical operation/exact accepted identity before binding or revision mutation, then captures profile/series/media/manual revision for replies. Flags change only after current-ticket validation. `_applyCastLanguagePolicy`15277 validates original profile/accepted owner before binding and rechecks captured authority after storage awaits. Old OFF/language ACKs cannot overwrite newer same-media intent or another profile/series.
- Preference edge: `ProfilePreferences.setStringGuarded`406, `setStringListGuarded`416 and `mutateStringAtomically`429 preserve existing profile/security/budget/projection semantics. `_write`775 rechecks permission at790 after the actual WebDAV barrier before synchronous preparation/delegate dispatch. Rejection performs no mutation/revision/publication. `StorageService.saveSeriesCastLanguagePreferences`4572 captures profile, retains its lock, recomputes the latest map at this edge and preserves untouched audio/subtitle dimensions. The additive language/OFF key remains separate from LOCAL `saveSeriesTrackPreferences`4600 and its audioTrackId/subtitleTrackId data. The nested stale-write/lost-map trace is closed.
- New sleep delta: authority `yieldToCast`128 checks permission after local pause and receiver settlement before publication; `restore`153 samples live play intent at physical dispatch after open/seek. Screen sleep transfer handling, rollback scheduling and accepted replacement/rollback sleep pause15176 were independently re-read; an uncertain receiver pause surfaces an explicit failure. No additional confirmed scoped P0/P1 found.

## Authored evidence — NOT RUN

Actual SourceSheet widget/completer scenarios assert: current selection survives its own authority plus telemetry rebuild; A→B→A wins; A episode fetch cannot merge into B; later provider selection wins. Authority helper cases prove pause failure/retirement fences, deferred-restore sleep and receiver pause before publication; these are helper proofs, not real player/device integration. Actual production StorageService cases assert independent series values, audio-only preservation of durable subtitle OFF and stale overwrite rejection. Profile barrier cases use the real exclusive mutation barrier/delegate and assert revoked string/list/atomic writes do not mutate, revoked transforms never run, positive controls succeed, another profile and revision remain unchanged.

Compilation, SDK/device behavior, actual player pause/seek/callbacks, platform storage timing and widget execution remain unverified. Existing LOCAL representation/branches were compared statically; no claim that all preexisting LOCAL async paths were tested.

## Exact reviewed SHA-256 artifacts

| File | SHA-256 |
|---|---|
| lib/screens/video_player_screen.dart | f912e80a9b7ae3a234035bba2b9e9775b122f95928237b9243e037cbe8813a54 |
| lib/screens/video_player/widgets/source_sheet.dart | f1d8886d58cce4a19f0f28121c3ba9e63104f6c25943f2e286e02ff783f12918 |
| lib/services/storage_service.dart | dc6e59a7496c1403f80c8127925e89424e68b536ee0eca885e45ad536a0d99b4 |
| lib/services/cast_player_authority.dart | 254d60bb81b2334873d6bdaba49a6883b45ce34af72807d2460cd4ff15c334e6 |
| lib/services/profiles/profile_preferences.dart | 88bb07926919f3dbf25469ec683c65153c36df044240bf553abaebcdb929bfc9 |
| test/source_sheet_cast_intent_test.dart | e59463fdd62b9129665a98176f658abf1e091027bede890feb4cc11aa0efc5bb |
| test/services/cast_player_authority_test.dart | cc44043313ee67ec6683eaf58ed49190c65c7241682f09c4ca6cb993a83c2463 |
| test/services/cast_series_language_preferences_test.dart | 11a0c4d729c12d67d2e3b52d49a2da1e3aa0e817df69b33bfeefb1eb38b11474 |
| test/profiles/cast_mutation_authority_test.dart | 078ed83632543cf6bca2a0e926a8bc5cb762aa2be3fe3469590999a902d125f6 |

Git blobs: screen 9d8d628171ebab1c4339047e862d12a023a6c9ff; sheet 1769c4a21e58306a9bbaa96a1b5c6ba73e15acdb; storage 4000ae3f7f2ff1898a878b72cba717d7cfe8b40c; authority c98b280cf7d9cc2236ebda883988a27935bd6765.
