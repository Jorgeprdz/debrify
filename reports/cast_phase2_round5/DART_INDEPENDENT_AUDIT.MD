# Independent native-reviewer Dart audit

READ-ONLY audit of other author's implementation; no Dart/player edits by this reviewer.
Baseline HEAD: 7f288ecc79def0eb5a7439abc3fc5a74ec39772e.

Latest reviewed source Git blob IDs:
- lib/services/cast_service.dart: 17589a70be2a3df3579d88b3b36d8bf99d9efb67
- lib/services/cast_load_coordinator.dart: 52082ee48729ccc3f006f4049de63459bd7ad4bd
- test/services/cast_service_coordination_test.dart: f22137f82c6adc725d7a44a0586dd7a1713e587b
- test/services/cast_load_coordinator_test.dart: 910f6bf9f20db44882544958b825ff05d48d5a4c
- test/services/cast_service_test.dart: 4b99c93a71c2e471d0c788ed703b8031a197b704
- Cross-layer native: 6e2a168a2a86647848a02a20e48e7b73081b304b

## Closed P1 findings

1. First Phase 1 public load captures a null epoch before initialization. Public load/coordinatedLoad now initialize first, maintain user-intent generation, and preserve validation exception codes. The private transport dispatch has no provider/initialization await between permission and native call.
2. Current-generation timed-out physical A is not reconciled. Coordinator exposes logicalPending with every physical reply; service marks recovery even for first-ever A with no previously accepted media. It retains accepted P clock and wire reality separately.
3. Mismatching receiver identities are hidden and ordinary controls target stale media. ReceiverSnapshot advances actual wire reality; accepted snapshot stays frozen; controls require exact accepted epoch/content/media ID and no recovery. Native receives and revalidates these identities.
4. Different bridge origin/null epoch revision cannot replace old connected snapshot. Always-present bridgeInstanceId and per-bridge revisions retire old bridge callbacks. New matching provisional status can authorize an earlier matching ACK clock without overriding a newer divergent identity. Returned LOAD value is the adopted latest snapshot.
5. Suspension retires a live epoch and restores local playback prematurely. Non-null disconnected epoch represents unconfirmed lifecycle; native marks it blocked and Dart retains accepted identity/resume/manual intent. Same-epoch resume remains eligible. Proven null-epoch retirement clears intent and permits local restoration.
6. C18 stale control EventChannel bypasses ACK suppression. Concrete old trace: P@12s, pause G, navigation G+1, then P/paused@90s delivered through native ACK plus event. Service previously rejected ACK but committed event at _applySnapshot. New service-owned physical authority tokens quarantine matching-epoch obsolete/expired controls; events advance wire only, and quarantine persists after physical ACK until explicit verified adoption, authoritative LOAD, or proven retirement. Both event-first and ACK-first production-service cases are authored; normal P progress without stale physical control remains accepted.
7. Confirmed SDK retirement EventChannel arrives before old native Result and leaves UI blocked forever. Previously retirement event notified while coordinator fence still held; later Result release notified nobody after logical caller timeout. Coordinator now invokes physical-state-change observer after actual LOAD/control exclusion release; service notifies and both retirement delivery orders are covered by authored LOAD/control cases.

STOP review: same epoch/bridge/generation preflight authority permits confirmed receiver unload, including SDK invalidated media ID0 with a cached URL only if that URL is still the accepted target. Clearing accepted STOP identity prevents subsequent controls dispatching invalid SID. Rejected same-epoch/bridge control replies quarantine and retain wire reality; safe-caught permission callbacks guarantee physical token cleanup. Epoch replacement after an accepted session explicitly requires recovery and retains its resume clock. Latest LOAD return uses the newest adopted same-identity snapshot. Stale STOP remains quarantined; ordinary non-STOP controls still require exact media identity. No physical cancellation is inferred from deadline/cancellation or SDK ambiguous errors.

No additional open P0/P1 found in the hash-bound Dart/coordinator scope after these repairs. This is a static assessment, not a runtime success claim.

## Verification constraints

Read source/diffs and authored regression scenarios; compared native/Dart channel names, field types, command arguments, pending-fence lifecycle, receiver identity, and snapshot revision production. git diff --check was used for static whitespace review. No application tests, compiler/analyzer/formatter, builds, Flutter/Dart/Gradle/Actions, commits, pushes, or remote mutations were executed. Tests remain AUTHORED / NOT RUN. The fake transport exercises production service/coordinator authority; it does not establish SDK/device behavior.

Player pause-yield/source ownership transition review is tracked separately in player-independent-audit.md and was still being revised at this artifact's initial write.
