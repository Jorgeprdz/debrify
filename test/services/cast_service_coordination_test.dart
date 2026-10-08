// Round 5 regression scenarios: AUTHORED / NOT RUN (execution prohibited).
import 'dart:async';

import 'package:debrify/services/cast_load_coordinator.dart';
import 'package:debrify/services/cast_phase2_policy.dart';
import 'package:debrify/services/cast_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const pUrl = 'https://media.invalid/previous.mp4';
const aUrl = 'https://media.invalid/a.mp4';
const bUrl = 'https://media.invalid/b.mp4';

Map<Object?, Object?> wire({
  String bridge = 'bridge-1',
  String? epoch = 'session-1',
  String? url = pUrl,
  int? mediaId = 1,
  int revision = 1,
  int position = 12000,
  bool connected = true,
  bool blocked = false,
  String state = 'playing',
}) => <Object?, Object?>{
  'available': true,
  'connected': connected,
  'state': state,
  'bridgeInstanceId': bridge,
  'sessionEpoch': epoch,
  'snapshotRevision': revision,
  'receiverOperationBlocked': blocked,
  'mediaContentId': url,
  'mediaSessionId': mediaId,
  'positionMs': position,
  'durationMs': 100000,
  'resumePositionMs': position,
  'resumeShouldPlay': state == 'playing',
};

class NativeCall {
  NativeCall(this.method, this.arguments);
  final String method;
  final Map<String, Object?>? arguments;
  final reply = Completer<Object?>();
}

// Only the platform boundary is fake. State ordering, filtering, coordination,
// recovery, adoption and control commits execute the production CastService.
class ControlledTransport implements CastTransport {
  final controller = StreamController<Object?>.broadcast(sync: true);
  final calls = <NativeCall>[];
  final pendingMethods = <String>{'loadMedia', 'seek', 'pause', 'play',
    'selectSubtitleTrack', 'disableSubtitles', 'stop'};
  Map<Object?, Object?> current = wire();
  Map<Object?, Object?>? disconnectReply;

  @override
  Stream<Object?> get events => controller.stream;

  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]) {
    if (method == 'getState') return Future<Object?>.value(current);
    if (method == 'isCastAvailable' || method == 'openCastDialog') {
      return Future<Object?>.value(true);
    }
    if (method == 'disconnect') {
      emit(disconnectReply ?? wire(epoch: null, url: null, mediaId: null, connected: false,
        revision: 100, state: 'disconnected'));
      return Future<Object?>.value(current);
    }
    final call = NativeCall(method, arguments);
    calls.add(call);
    if (!pendingMethods.contains(method)) return Future<Object?>.value(current);
    return call.reply.future;
  }

  void emit(Map<Object?, Object?> value) {
    current = value;
    controller.add(value);
  }

  NativeCall last(String method) => calls.lastWhere((call) => call.method == method);
  int count(String method) => calls.where((call) => call.method == method).length;

  void answer(String method, Map<Object?, Object?> value) {
    current = value;
    last(method).reply.complete(value);
  }
}

class Fixture {
  Fixture(this.native, this.service);
  final ControlledTransport native;
  final CastService service;
}

Future<Fixture> ready({Duration timeout = const Duration(seconds: 30)}) async {
  final native = ControlledTransport();
  final service = CastService(transport: native, isAndroid: true,
    callerTimeout: timeout);
  await service.initialize();
  final ticket = service.beginNavigationIntent();
  expect(service.adoptVerifiedReceiverIdentity(fresh: await service.refresh(),
    expectedContentId: pUrl, generation: ticket), isTrue);
  return Fixture(native, service);
}

Future<void> flush() async => Future<void>.delayed(Duration.zero);

Future<void> staleA(Fixture f) async {
  final a = f.service.beginNavigationIntent();
  final first = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
    generation: a, permitted: () => true);
  await flush();
  f.service.beginNavigationIntent(); // New provider B has not submitted LOAD.
  expect((await first).outcome, CastLoadOutcome.superseded);
  f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3,
    position: 87000));
  await flush();
}

void main() {
  test('I06 local source fallback preserves local telemetry and ownership', () {
    final ownership = PlaybackOwnershipController();
    expect(CastSourceCompatibility.classify(url: 'file:///local.mp4').canAttempt,
      isFalse);
    expect(ownership.isLocal, isTrue);
    expect(ownership.acceptsLocalTelemetry, isTrue);
    ownership.beginCastTransfer();
    ownership.cancelCastTransfer();
    expect(ownership.owner, PlaybackOwner.local);
    expect(StremioTvNextRecovery.canResumeLocal(ownership.owner, true), isTrue);
  });

  test('C13 manual seek validates exact committed URL media ID and epoch', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    expect(await f.service.seekForCommittedMedia(const Duration(seconds: 40),
      generation: ticket, contentId: aUrl, mediaSessionId: 1,
      permitted: () => true), isNull);
    expect(await f.service.seekForCommittedMedia(const Duration(seconds: 40),
      generation: ticket, contentId: pUrl, mediaSessionId: 2,
      permitted: () => true), isNull);
    final seek = f.service.seekForCommittedMedia(const Duration(seconds: 40),
      generation: ticket, contentId: pUrl, mediaSessionId: 1,
      permitted: () => true);
    await flush();
    final args = f.native.last('seek').arguments!;
    expect(args['expectedContentId'], pUrl);
    expect(args['expectedMediaSessionId'], 1);
    expect(args['expectedSessionEpoch'], 'session-1');
    f.native.answer('seek', wire(position: 40000, revision: 2));
    expect((await seek)!.position, const Duration(seconds: 40));
    f.service.dispose();
  });

  test('C14 deferred percent seek cancels when navigation supersedes ticket', () async {
    final f = await ready();
    final gate = CastStartPercentGate();
    final percent = gate.prepare(contentId: aUrl, previousMediaSessionId: 1,
      startAtPercent: .5);
    gate.confirm(percent);
    final old = f.service.beginNavigationIntent();
    f.service.beginNavigationIntent();
    gate.cancel();
    expect(gate.claim(contentId: aUrl, mediaSessionId: 2,
      duration: const Duration(seconds: 100)), isNull);
    expect(await f.service.seekForCommittedMedia(const Duration(seconds: 50),
      generation: old, contentId: pUrl, mediaSessionId: 1,
      permitted: () => gate.isCurrent(percent)), isNull);
    expect(f.native.count('seek'), 0);
    f.service.dispose();
  });

  test('C15 a manual seek never dispatches while LOAD is physical', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    expect(await f.service.seekForCommittedMedia(const Duration(seconds: 20),
      generation: ticket, contentId: pUrl, mediaSessionId: 1,
      permitted: () => true), isNull);
    expect(f.native.count('seek'), 0);
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 2));
    expect((await load).committed, isTrue);
    f.service.dispose();
  });

  test('C16 later LOAD waits for previously dispatched seek physical ACK', () async {
    final f = await ready();
    final old = f.service.beginNavigationIntent();
    final seek = f.service.seekForCommittedMedia(const Duration(seconds: 20),
      generation: old, contentId: pUrl, mediaSessionId: 1,
      permitted: () => true);
    await flush();
    final current = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: bUrl),
      generation: current, permitted: () => true);
    await flush();
    expect(f.native.count('loadMedia'), 0);
    f.native.answer('seek', wire(position: 20000, revision: 2));
    expect(await seek, isNull);
    await flush();
    expect(f.native.count('loadMedia'), 1);
    f.native.answer('loadMedia', wire(url: bUrl, mediaId: 3, revision: 3));
    expect((await load).committed, isTrue);
    expect(f.service.snapshot.mediaContentId, bUrl);
    f.service.dispose();
  });

  test('C17 timed-out seek cannot commit late and still excludes next LOAD', () {
    fakeAsync((clock) {
      Fixture? fixture;
      ready(timeout: const Duration(seconds: 1)).then((value) => fixture = value);
      clock.flushMicrotasks();
      final f = fixture!;
      final ticket = f.service.beginNavigationIntent();
      CastSnapshot? response;
      var callerSettled = false;
      f.service.seekForCommittedMedia(const Duration(seconds: 90),
        generation: ticket, contentId: pUrl, mediaSessionId: 1,
        permitted: () => true).then((value) { response = value; callerSettled = true; });
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(callerSettled, isTrue);
      expect(response, isNull);
      expect(f.service.receiverLoadBlocked, isTrue);
      final newer = f.service.beginNavigationIntent();
      CastLoadResult<CastSnapshot>? committed;
      f.service.coordinatedLoad(const CastMediaRequest(url: bUrl),
        generation: newer, permitted: () => true).then((value) => committed = value);
      clock.flushMicrotasks();
      expect(f.native.count('loadMedia'), 0);
      f.native.answer('seek', wire(position: 90000, revision: 2));
      clock.flushMicrotasks();
      expect(f.service.position, const Duration(seconds: 12));
      expect(f.native.count('loadMedia'), 1);
      f.native.answer('loadMedia', wire(url: bUrl, mediaId: 3, revision: 3));
      clock.flushMicrotasks();
      expect(committed!.committed, isTrue);
      f.service.dispose();
    });
  });

  test('C18 late pause ACK and event never rewrite clock in either channel order', () async {
    for (final eventFirst in [true, false]) {
      final f = await ready();
      final pause = f.service.pause();
      final rejected = expectLater(pause, throwsA(isA<CastException>()));
      await flush();
      f.service.beginNavigationIntent(); // B provider is unresolved.
      final late = wire(state: 'paused', position: 90000, revision: 2);
      if (eventFirst) {
        f.native.emit(late);
        expect(f.service.position, const Duration(seconds: 12));
        expect(f.service.state, CastPlaybackState.playing);
        f.native.answer('pause', late);
        await rejected;
      } else {
        f.native.answer('pause', late);
        await rejected;
        await flush();
        f.native.emit(late);
      }
      await flush();
      expect(f.service.state, CastPlaybackState.playing);
      expect(f.service.position, const Duration(seconds: 12));
      expect(f.service.receiverRecoveryRequired, isTrue);
      expect(f.service.hasLoadInFlight, isFalse);
      final fresh = await f.service.refresh();
      final ticket = f.service.beginNavigationIntent();
      expect(f.service.adoptVerifiedReceiverIdentity(fresh: fresh,
        expectedContentId: pUrl, generation: ticket), isTrue);
      expect(f.service.receiverRecoveryRequired, isFalse);
      expect(f.service.position, const Duration(seconds: 90));
      expect(f.service.state, CastPlaybackState.paused);
      f.service.dispose();
    }
  });

  test('S19 fresh matching receiver identity adopts without LOAD', () async {
    final native = ControlledTransport();
    final service = CastService(transport: native, isAndroid: true);
    await service.initialize();
    final ticket = service.beginNavigationIntent();
    final fresh = await service.refresh();
    expect(service.adoptVerifiedReceiverIdentity(fresh: fresh,
      expectedContentId: pUrl, generation: ticket), isTrue);
    expect(native.count('loadMedia'), 0);
    expect(service.snapshot.mediaSessionId, 1);
    service.dispose();
  });

  test('S20 restored receiver with mismatching URL cannot adopt', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: await f.service.refresh(),
      expectedContentId: aUrl, generation: ticket), isFalse);
    expect(f.native.count('loadMedia'), 0);
    f.service.dispose();
  });

  test('S21 matching restored URL with wrong media session cannot adopt', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final wrong = CastSnapshot.fromMap(wire(mediaId: 99));
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: wrong,
      expectedContentId: pUrl, generation: ticket), isFalse);
    f.service.dispose();
  });

  test('S22 matching restored URL and media ID with wrong epoch cannot adopt', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final wrong = CastSnapshot.fromMap(wire(epoch: 'other-session'));
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: wrong,
      expectedContentId: pUrl, generation: ticket), isFalse);
    f.service.dispose();
  });

  test('S23 retired session callback cannot disconnect new session', () async {
    final f = await ready();
    f.native.emit(wire(epoch: 'session-2', revision: 3, mediaId: 5));
    expect(f.service.snapshot.sessionEpoch, 'session-2');
    f.native.emit(wire(epoch: 'session-1', revision: 100, connected: false,
      state: 'disconnected'));
    expect(f.service.connected, isTrue);
    expect(f.service.snapshot.sessionEpoch, 'session-2');
    f.service.dispose();
  });

  test('S24 old bridge LOAD ACK after recreation cannot commit', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    f.native.emit(wire(bridge: 'bridge-2', epoch: 'session-2', revision: 1,
      url: bUrl, mediaId: 8));
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 10));
    expect((await load).committed, isFalse);
    await flush();
    expect(f.service.snapshot.bridgeInstanceId, 'bridge-2');
    expect(f.service.snapshot.sessionEpoch, 'session-2');
    f.service.dispose();
  });

  test('R25 superseded physical A ACK is observed without committing A', () async {
    final f = await ready();
    await staleA(f);
    expect(f.service.receiverRecoveryRequired, isTrue);
    expect(f.service.snapshot.mediaContentId, pUrl);
    expect(f.service.position, const Duration(seconds: 12));
    expect((await f.service.refresh()).mediaContentId, aUrl);
    f.service.dispose();
  });

  test('R26 current timed-out A late ACK enters recovery with frozen P clock', () {
    fakeAsync((clock) {
      Fixture? fixture;
      ready(timeout: const Duration(seconds: 1)).then((value) => fixture = value);
      clock.flushMicrotasks();
      final f = fixture!;
      final ticket = f.service.beginNavigationIntent();
      CastLoadResult<CastSnapshot>? outcome;
      f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
        generation: ticket, permitted: () => true).then((value) => outcome = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(outcome!.outcome, CastLoadOutcome.failed);
      expect(f.service.receiverLoadBlocked, isTrue);
      f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3,
        position: 87000));
      clock.flushMicrotasks();
      expect(f.service.receiverRecoveryRequired, isTrue);
      expect(f.service.position, const Duration(seconds: 12));
      expect(f.service.hasLoadInFlight, isFalse);
      f.service.dispose();
    });
  });

  test('R27 verified B commit clears recovery after late A and failed B provider', () async {
    final f = await ready();
    await staleA(f); // B provider failed before submitting a LOAD.
    expect(f.service.receiverRecoveryRequired, isTrue);
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: bUrl),
      generation: ticket, permitted: () => true);
    await flush();
    f.native.answer('loadMedia', wire(url: bUrl, mediaId: 3, revision: 4,
      position: 5000, state: 'connected'));
    expect((await load).committed, isTrue);
    expect(f.service.receiverRecoveryRequired, isFalse);
    expect(f.service.snapshot.mediaContentId, bUrl);
    expect(f.service.state, CastPlaybackState.connected);
    f.service.dispose();
  });

  test('R28 provisional event does not reject earlier valid LOAD ACK', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    f.native.emit(wire(url: aUrl, mediaId: 2, revision: 4, position: 30000));
    expect(f.service.position, const Duration(seconds: 12));
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3,
      position: 29000));
    expect((await load).committed, isTrue);
    expect(f.service.snapshot.mediaContentId, aUrl);
    // The newer same-identity wire event wins over the older ACK clock.
    expect(f.service.position, const Duration(seconds: 30));
    f.service.dispose();
  });

  test('R29 bridge with no session retires old callbacks then reconnects', () async {
    final f = await ready();
    f.native.emit(wire(bridge: 'bridge-2', epoch: null, connected: false,
      url: null, mediaId: null, revision: 1, state: 'disconnected'));
    expect(f.service.connected, isFalse);
    f.native.emit(wire(bridge: 'bridge-1', revision: 999));
    expect(f.service.connected, isFalse);
    f.native.emit(wire(bridge: 'bridge-2', epoch: 'session-2', revision: 2,
      url: bUrl, mediaId: 4));
    expect(f.service.connected, isTrue);
    expect(f.service.snapshot.sessionEpoch, 'session-2');
    f.service.dispose();
  });

  test('R30 proven disconnect clears recovery and preserves accepted resume', () async {
    final f = await ready();
    await staleA(f);
    expect(f.service.receiverRecoveryRequired, isTrue);
    f.native.emit(wire(epoch: null, url: null, mediaId: null, connected: false,
      revision: 4, position: 87000, state: 'disconnected'));
    expect(f.service.receiverRecoveryRequired, isFalse);
    expect(f.service.connected, isFalse);
    expect(f.service.snapshot.resumePosition, const Duration(seconds: 12));
    expect(f.service.snapshot.resumeShouldPlay, isTrue);
    expect(f.service.state, CastPlaybackState.disconnected);
    f.service.dispose();
  });

  test('T31 language policy reads committed remote tracks after LOAD', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    final ack = wire(url: aUrl, mediaId: 2, revision: 2);
    ack['availableSubtitleTracks'] = [
      {'id': '7', 'type': 'subtitle', 'language': 'en'},
      {'id': '8', 'type': 'subtitle', 'language': 'es'}];
    f.native.answer('loadMedia', ack);
    expect((await load).committed, isTrue);
    expect(CastLanguagePolicy.chooseSubtitle(tracks: f.service.availableSubtitleTracks,
      explicitlyDisabled: false, preferredLanguage: 'en')!.id, '7');
    f.service.dispose();
  });

  test('T32 manual OFF wins over delayed automatic language preference', () async {
    final f = await ready();
    final defaultLanguage = Completer<String>();
    final choice = defaultLanguage.future.then((language) =>
      CastLanguagePolicy.chooseSubtitle(tracks: const [CastRemoteTrack(id: '7',
        type: CastRemoteTrackType.subtitle, language: 'en')],
        explicitlyDisabled: f.service.sessionSubtitlesDisabled,
        preferredLanguage: language));
    f.service.rememberSubtitlesDisabled();
    defaultLanguage.complete('en');
    expect(await choice, isNull);
    expect(f.service.sessionSubtitlesDisabled, isTrue);
    f.service.dispose();
  });

  test('T33 stale embedded subtitle result cannot change newly committed media', () async {
    final f = await ready();
    final selection = f.service.selectSubtitleTrack('7');
    final stale = expectLater(selection, throwsA(isA<CastException>()));
    await flush();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: bUrl),
      generation: ticket, permitted: () => true);
    f.native.answer('selectSubtitleTrack', wire(revision: 2)..['selectedSubtitleTrack'] = '7');
    await stale;
    await flush();
    f.native.answer('loadMedia', wire(url: bUrl, mediaId: 3, revision: 3));
    expect((await load).committed, isTrue);
    expect(f.service.selectedSubtitleTrack, isNull);
    expect(f.service.sessionSubtitleLanguage, isNull);
    f.service.dispose();
  });

  test('T34 prepared WebVTT request leaves committed language intent untouched', () async {
    final f = await ready();
    f.service.rememberSubtitleLanguage('es');
    final previous = const CastMediaRequest(url: pUrl);
    final candidate = previous.copyWith(textTracks: const [CastTextTrackRequest(
      id: 9, url: 'https://subtitles.invalid/addon.vtt', language: 'en', label: 'English')]);
    expect(CastSubtitleSupport.classify(candidate.textTracks.single.url).supported,
      isTrue);
    expect(previous.textTracks, isEmpty);
    expect(f.service.availableSubtitleTracks, isEmpty);
    expect(f.service.sessionSubtitleLanguage, 'es');
    f.service.dispose();
  });

  test('T35 rejected addon replacement retains previous track intent', () async {
    final f = await ready();
    f.service.rememberSubtitleLanguage('es');
    final previous = const CastMediaRequest(url: pUrl);
    final transaction = CastSwitchTransaction<CastMediaRequest>(previous: previous,
      position: const Duration(seconds: 12), wasPlaying: true);
    final candidate = previous.copyWith(textTracks: const [CastTextTrackRequest(
      id: 9, url: 'https://subtitles.invalid/addon.vtt', language: 'en', label: 'English')]);
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(candidate,
      generation: ticket, permitted: () => true);
    await flush();
    f.native.last('loadMedia').reply.completeError(PlatformException(code: 'CAST_LOAD_FAILED'));
    expect((await load).outcome, CastLoadOutcome.failed);
    expect(identical(transaction.rollback(), previous), isTrue);
    expect(f.service.snapshot.mediaContentId, pUrl);
    expect(f.service.sessionSubtitleLanguage, 'es');
    expect(f.service.availableSubtitleTracks, isEmpty);
    f.service.dispose();
  });

  test('T36 obsolete subtitle LOAD cannot clear current transition authority', () async {
    final f = await ready();
    final first = f.service.beginNavigationIntent();
    final old = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: first, permitted: () => true);
    await flush();
    final latest = f.service.beginNavigationIntent();
    final current = f.service.coordinatedLoad(const CastMediaRequest(url: bUrl),
      generation: latest, permitted: () => true);
    expect((await old).committed, isFalse);
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 2));
    await flush();
    expect(f.service.isCurrentLoad(first), isFalse);
    expect(f.service.isCurrentLoad(latest), isTrue);
    expect(f.service.hasLoadInFlight, isTrue);
    f.native.answer('loadMedia', wire(url: bUrl, mediaId: 3, revision: 3));
    expect((await current).committed, isTrue);
    expect(f.service.hasLoadInFlight, isFalse);
    f.service.dispose();
  });

  test('P43 Phase 1 load initializes before epoch capture and preserves errors', () async {
    final native = ControlledTransport();
    final service = CastService(transport: native, isAndroid: true);
    final first = service.load(const CastMediaRequest(url: aUrl));
    await flush();
    expect(native.count('loadMedia'), 1);
    native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 2));
    expect((await first).mediaContentId, aUrl);
    final invalid = service.load(const CastMediaRequest(url: 'file:///invalid.mp4'));
    await expectLater(invalid, throwsA(isA<CastException>().having(
      (error) => error.code, 'specific error code', 'CAST_INVALID_URL')));
    expect(native.count('loadMedia'), 1);
    expect(await service.connect(), isTrue);
    service.dispose();
  });
  test('first-ever timed-out LOAD late ACK exposes recovery without accepted media', () {
    fakeAsync((clock) {
      final native = ControlledTransport()..current = wire(url: null, mediaId: null,
        state: 'connected');
      final service = CastService(transport: native, isAndroid: true,
        callerTimeout: const Duration(seconds: 1));
      CastLoadResult<CastSnapshot>? result;
      final ticket = service.beginNavigationIntent();
      service.coordinatedLoad(const CastMediaRequest(url: aUrl), generation: ticket,
        permitted: () => true).then((value) => result = value);
      clock.flushMicrotasks();
      expect(native.count('loadMedia'), 1);
      clock.elapse(const Duration(seconds: 1));
      expect(result!.outcome, CastLoadOutcome.failed);
      native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3));
      clock.flushMicrotasks();
      expect(service.receiverRecoveryRequired, isTrue);
      expect(service.snapshot.mediaContentId, isNull);
      service.dispose();
    });
  });

  test('native blocked signal notifies even while replacement clock is frozen', () async {
    final f = await ready();
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    var notifications = 0;
    f.service.addListener(() => notifications++);
    f.native.emit(wire(url: aUrl, mediaId: 2, revision: 2, blocked: true));
    expect(f.service.receiverOperationBlocked, isTrue);
    expect(f.service.snapshot.mediaContentId, pUrl);
    expect(notifications, greaterThan(0));
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3));
    expect((await load).committed, isTrue);
    expect(f.service.receiverOperationBlocked, isFalse);
    f.service.dispose();
  });

  test('ordinary controls carry exact committed identity and reject divergence', () async {
    final f = await ready();
    final pause = f.service.pause();
    await flush();
    final args = f.native.last('pause').arguments!;
    expect(args['expectedContentId'], pUrl);
    expect(args['expectedMediaSessionId'], 1);
    expect(args['expectedSessionEpoch'], 'session-1');
    f.native.answer('pause', wire(state: 'paused', revision: 2));
    expect((await pause).state, CastPlaybackState.paused);
    f.native.emit(wire(url: aUrl, mediaId: 2, revision: 3));
    expect(f.service.receiverRecoveryRequired, isTrue);
    await expectLater(f.service.play(), throwsA(isA<CastException>()));
    expect(f.native.count('play'), 0);
    f.service.dispose();
  });

  test('same session bridge recreation preserves exact identity and accepts new revision origin', () async {
    final f = await ready();
    f.native.emit(wire(bridge: 'bridge-2', revision: 1, position: 14000));
    final ticket = f.service.beginNavigationIntent();
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: await f.service.refresh(),
      expectedContentId: pUrl, generation: ticket), isTrue);
    f.native.emit(wire(bridge: 'bridge-1', revision: 999, position: 98000));
    expect(f.service.snapshot.bridgeInstanceId, 'bridge-2');
    expect(f.service.position, const Duration(seconds: 14));
    expect(f.native.count('loadMedia'), 0);
    f.service.dispose();
  });

  test('disposing service rejects late physical snapshots without notification', () async {
    final f = await ready();
    var notifications = 0;
    f.service.addListener(() => notifications++);
    final ticket = f.service.beginNavigationIntent();
    final load = f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
      generation: ticket, permitted: () => true);
    await flush();
    f.service.dispose();
    expect((await load).outcome, CastLoadOutcome.cancelled);
    f.native.answer('loadMedia', wire(url: aUrl, mediaId: 2, revision: 3));
    await flush();
    expect(notifications, 0);
    expect(f.service.snapshot.mediaContentId, pUrl);
  });

  test('suspension keeps accepted identity and blocks until resume or confirmed retirement', () async {
    final f = await ready();
    f.native.emit(wire(connected: false, epoch: 'session-1', url: null,
      mediaId: null, revision: 2, position: 98000, state: 'connecting'));
    expect(f.service.receiverOperationBlocked, isTrue);
    expect(f.service.snapshot.sessionEpoch, 'session-1');
    expect(f.service.snapshot.mediaContentId, pUrl);
    expect(f.service.position, const Duration(seconds: 12));
    await expectLater(f.service.pause(), throwsA(isA<CastException>()));
    expect(f.native.count('pause'), 0);
    f.native.emit(wire(epoch: 'session-1', revision: 3, position: 15000));
    expect(f.service.receiverOperationBlocked, isFalse);
    expect(f.service.connected, isTrue);
    expect(f.service.position, const Duration(seconds: 15));
    f.native.emit(wire(epoch: null, connected: false, url: null, mediaId: null,
      revision: 4, state: 'disconnected'));
    expect(f.service.receiverOperationBlocked, isFalse);
    expect(f.service.snapshot.sessionEpoch, isNull);
    expect(f.service.snapshot.resumePosition, const Duration(seconds: 15));
    f.service.dispose();
  });

  test('unconfirmed disconnect cannot clear session subtitle OFF intent', () async {
    final f = await ready();
    f.service.rememberSubtitlesDisabled();
    f.native.disconnectReply = wire(epoch: 'session-1', url: null, mediaId: null,
      connected: false, blocked: true, state: 'connecting', revision: 2);
    final pending = await f.service.disconnect();
    expect(pending.sessionEpoch, 'session-1');
    expect(f.service.receiverOperationBlocked, isTrue);
    expect(f.service.sessionSubtitlesDisabled, isTrue);
    expect(pending.resumePosition, const Duration(seconds: 12));
    f.native.emit(wire(epoch: 'session-1', revision: 3));
    expect(f.service.sessionSubtitlesDisabled, isTrue);
    f.native.emit(wire(epoch: null, connected: false, url: null, mediaId: null,
      revision: 4, state: 'disconnected'));
    expect(f.service.sessionSubtitlesDisabled, isFalse);
    f.service.dispose();
  });

  test('ordinary accepted P progress remains live after failed B provider without stale control', () async {
    final f = await ready();
    f.service.beginNavigationIntent(); // B provider fails before native dispatch.
    f.native.emit(wire(revision: 2, position: 15000));
    expect(f.service.receiverRecoveryRequired, isFalse);
    expect(f.service.position, const Duration(seconds: 15));
    expect(f.service.state, CastPlaybackState.playing);
    f.service.dispose();
  });

  test('current STOP accepts unloaded event and ACK in either channel order', () async {
    for (final eventFirst in [true, false]) {
      final f = await ready();
      final stop = f.service.stop();
      await flush();
      final stopped = wire(url: null, mediaId: null, revision: 2,
        position: 0, state: 'connected');
      if (eventFirst) f.native.emit(stopped);
      f.native.answer('stop', stopped);
      final result = await stop;
      if (!eventFirst) f.native.emit(stopped);
      expect(result.state, CastPlaybackState.connected);
      expect(result.mediaContentId, isNull);
      expect(f.service.receiverRecoveryRequired, isFalse);
      expect(f.service.snapshot.mediaSessionId, isNull);
      expect(f.service.state, CastPlaybackState.connected);
      f.service.dispose();
    }
  });

  test('superseded STOP cannot authorize unload event for newer navigation', () async {
    final f = await ready();
    final stop = f.service.stop();
    final rejected = expectLater(stop, throwsA(isA<CastException>()));
    await flush();
    f.service.beginNavigationIntent();
    final stopped = wire(url: null, mediaId: null, revision: 2,
      position: 0, state: 'connected');
    f.native.emit(stopped);
    f.native.answer('stop', stopped);
    await rejected;
    await flush();
    expect(f.service.receiverRecoveryRequired, isTrue);
    expect(f.service.snapshot.mediaContentId, pUrl);
    expect(f.service.position, const Duration(seconds: 12));
    f.service.dispose();
  });

  test('confirmed retirement always notifies after timed-out physical LOAD exclusion ends', () {
    for (final eventFirst in [true, false]) {
      fakeAsync((clock) {
        Fixture? fixture;
        ready(timeout: const Duration(seconds: 1)).then((value) => fixture = value);
        clock.flushMicrotasks();
        final f = fixture!;
        final blockedStates = <bool>[];
        f.service.addListener(() => blockedStates.add(f.service.receiverOperationBlocked));
        final ticket = f.service.beginNavigationIntent();
        f.service.coordinatedLoad(const CastMediaRequest(url: aUrl),
          generation: ticket, permitted: () => true);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(f.service.receiverOperationBlocked, isTrue);
        final retired = wire(epoch: null, connected: false, url: null, mediaId: null,
          revision: 3, state: 'disconnected');
        if (eventFirst) f.native.emit(retired);
        f.native.last('loadMedia').reply.completeError(PlatformException(code: 'CAST_SESSION_RETIRED'));
        clock.flushMicrotasks();
        if (!eventFirst) f.native.emit(retired);
        clock.flushMicrotasks();
        expect(f.service.receiverOperationBlocked, isFalse);
        expect(blockedStates.last, isFalse);
        expect(f.service.snapshot.resumePosition, const Duration(seconds: 12));
        expect(f.service.connected, isFalse);
        f.service.dispose();
      });
    }
  });

  test('replaced accepted session requires visible recovery until exact verified adoption', () async {
    final f = await ready();
    f.native.emit(wire(epoch: 'session-2', url: bUrl, mediaId: 8, revision: 2));
    expect(f.service.snapshot.sessionEpoch, 'session-2');
    expect(f.service.receiverRecoveryRequired, isTrue);
    await expectLater(f.service.pause(), throwsA(isA<CastException>()));
    expect(f.native.count('pause'), 0);
    final fresh = await f.service.refresh();
    final ticket = f.service.beginNavigationIntent();
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: fresh,
      expectedContentId: pUrl, generation: ticket), isFalse);
    expect(f.service.receiverRecoveryRequired, isTrue);
    expect(f.service.adoptVerifiedReceiverIdentity(fresh: fresh,
      expectedContentId: bUrl, generation: ticket), isTrue);
    expect(f.service.receiverRecoveryRequired, isFalse);
    f.service.dispose();
  });

  test('confirmed retirement notifies after timed-out control fence ends in either channel order', () {
    for (final eventFirst in [true, false]) {
      fakeAsync((clock) {
        Fixture? fixture;
        ready(timeout: const Duration(seconds: 1)).then((value) => fixture = value);
        clock.flushMicrotasks();
        final f = fixture!;
        final blockedStates = <bool>[];
        f.service.addListener(() => blockedStates.add(f.service.receiverOperationBlocked));
        Object? failure;
        f.service.pause().catchError((Object error) {
          failure = error;
          return f.service.snapshot;
        });
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(failure, isA<CastException>());
        expect(f.service.receiverOperationBlocked, isTrue);
        final retired = wire(epoch: null, connected: false, url: null, mediaId: null,
          revision: 3, state: 'disconnected');
        if (eventFirst) f.native.emit(retired);
        f.native.last('pause').reply.completeError(PlatformException(code: 'CAST_SESSION_RETIRED'));
        clock.flushMicrotasks();
        if (!eventFirst) f.native.emit(retired);
        clock.flushMicrotasks();
        expect(f.service.receiverOperationBlocked, isFalse);
        expect(f.service.receiverRecoveryRequired, isFalse);
        expect(blockedStates.last, isFalse);
        expect(f.service.snapshot.resumePosition, const Duration(seconds: 12));
        f.service.dispose();
      });
    }
  });

  test('STOP accepts invalidated media session with cached same-target metadata', () async {
    final f = await ready();
    final stop = f.service.stop();
    await flush();
    final stopped = wire(url: pUrl, mediaId: 0, revision: 2, state: 'connected');
    f.native.emit(stopped);
    f.native.answer('stop', stopped);
    expect((await stop).state, CastPlaybackState.connected);
    expect(f.service.receiverRecoveryRequired, isFalse);
    expect(f.service.snapshot.mediaSessionId, 0);
    await expectLater(f.service.play(), throwsA(isA<CastException>()));
    expect(f.native.count('play'), 0);
    f.service.dispose();
  });

}
