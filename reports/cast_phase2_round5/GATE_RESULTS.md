# Round 5 — final semantic static audit

18/18 STATIC PASS; P0 open=0; P1 open=0. This verdict is source-bound, not an application test/build/runtime result. Mechanical recheck is recorded separately in STATIC_GATE_OUTPUT.txt.

| Gate | Scope | Static verdict | Evidence / rationale |
|---|---|---|---|
| G01 | Dependency and remote | PASS | Live PR3 remains open on the exact phase1 ancestor; phase2 remote remains historical baseline. Recovered eight objects were SHA1-verified and reconciled contextually, including player hunks. |
| G02 | Full scoped P0 audit | PASS | Changed Dart/native/player/storage boundaries and Phase1 contracts were reread; no confirmed P0 is open. This is scoped source evidence, not total runtime correctness. |
| G03 | P1-01 through P1-10 closure | PASS | All original categories and 48 detailed source findings closed by final cross-author traces; late commands, tracking and restore authority remain explicit. |
| G04 | Intent before awaits | PASS | Tap/previous/episode/provider intents are captured synchronously; nested continuations retain ticket/profile. Old local provider results cannot promote a new Cast intent. |
| G05 | Physical command serialization | PASS | Coordinator and native ledger retain physical LOAD/control exclusion after logical timeout/supersession. Controls include exact expected epoch/URL/SID. No cancellation is inferred from a deadline. |
| G06 | Verified restoration | PASS | Fresh receiver identity is checked before adoption, with local effect ticket across refresh. Local restore opens committed B before seek/play and continuously requires retired receiver/no physical uncertainty/same profile. |
| G07 | Epoch and snapshot revision | PASS | Opaque bridge and session IDs, per-bridge monotonic snapshots and retired-session tombstones prevent old Activity/client/epoch callbacks from reviving or overwriting current state. |
| G08 | Receiver divergence | PASS | Wire snapshot is separate from accepted media clock. Late/expired A is quarantined, including paired ACK/EventChannel delivery; recovery requires confirmed identity, not fictitious B playback. |
| G09 | Transactional tracks | PASS | Manual revision and original profile/series/media fence late choices; language/OFF uses additive per-series storage. Subtitle replacement validates WebVTT and only commits current verified media; logical rollback preserves previous intent without claiming physical rollback. |
| G10 | Metadata EPG MDBList | PASS | Internal preload/save/adjacent/guide/MDBList helpers bind generation, media/profile and playlist target. Preference guards recheck after hidden WebDAV barrier; database cancellation rolls back the whole deletion/tombstone transaction. |
| G11 | Exactly-once ended and tracking | PASS | Ended identity includes navigation, bridge, epoch, media SID, content URL and ended sequence. Completion gate/immutable targets and per-tracker ordered effects preserve outgoing A clock and reject obsolete continuations. |
| G12 | Hung native recovery | PASS | Watchdog/post-dispatch ambiguity preserves physical ledger and Result. Only actual completion or SDK-confirmed retirement releases exclusion. Controller remains reachable during blocked transfer; physical-drain notification handles retirement event before Result. |
| G13 | Phase1 compatibility | PASS | Existing public service/load validation/channel names/options and request-map shape preserved. Initialization precedes epoch capture. LOCAL sheet flow, separate LOCAL track IDs and platform/headers/split-stream policy stay intact. |
| G14 | 45 distinct authored regressions | PASS | I01–I06/L07–L12/C13–C18/S19–S24/R25–R30/T31–T36/E37–E42/P43–P45 have unique production-connected bodies and concrete assertions; all names/lines/assertions match source. Authored, never run. |
| G15 | Diff and static verification | PASS | git diff --check and source delimiter/local import/wire/matrix/hash checks are required by the static script. These checks do not parse/typecheck/execute Dart or Kotlin. |
| G16 | Independent adversarial audit | PASS | Native author reviewed Dart/player; Dart author reviewed native/player/preferences. Reviewers returned concrete failures, repairs were iterated, and final frozen hashes have no confirmed open P0/P1. |
| G17 | Integrated files and contracts | PASS | All edited production/test/pubspec boundaries, Dart↔Kotlin field types/client authority, profile persistence and source helper call sites were reread. Tests use production functions with transport/store fakes at boundaries; helper coverage is identified honestly. |
| G18 | Authorized operations | PASS | During static recovery only source/Git/read/textual audit operations were used; no Flutter/Dart test/analyze/Gradle/build/Actions/merge. Latest user authorizes final PR integration and Android compile after closure; app test/analyze bans remain. |

Source inventory SHA256: `4c26b097a487ef9afd3568daa59a2961f4a9a9262755bf46504b0779e75b23b3`.

All mandatory regression tests AUTHORED / NOT RUN. Independent review narratives remain separate from the mechanical checker; textual presence alone is never the semantic authority.
