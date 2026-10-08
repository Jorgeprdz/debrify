import 'dart:async';

import 'package:debrify/services/cast_player_authority.dart';
import 'package:debrify/services/cast_phase2_policy.dart';
import 'package:flutter_test/flutter_test.dart';

CastPlayerMediaIdentity identity({int generation = 1, int epoch = 1,
  int media = 7, String content = 'A', int ended = 0}) =>
    CastPlayerMediaIdentity(generation: generation, bridgeInstanceId: 'bridge',
      sessionEpoch: 'session-$epoch', mediaSessionId: media, contentId: content,
      endedSequence: ended);

void main() {
  test('sleep stop during deferred restore seek dispatches pause instead of play', () async {
    final seeking = Completer<void>();
    var sleepStopped = false;
    final dispatched = <bool>[];
    final restoring = CastPlayerRestorePlan.restore(parkedUrl: 'B', committedUrl: 'B',
      headersChanged: false, position: const Duration(seconds: 24), shouldPlay: true,
      shouldPlayNow: () => !sleepStopped,
      permitted: () => true, open: () async {}, seek: (_) => seeking.future,
      setPlaying: (play) async { dispatched.add(play); });
    sleepStopped = true;
    seeking.complete();
    expect(await restoring, isTrue);
    expect(dispatched, [false]);
  });

  test('sleep stop during local yield pauses accepted receiver before publication', () async {
    final localPause = Completer<void>();
    final receiverPause = Completer<void>();
    final events = <String>[];
    var sleepStopped = false;
    final yielding = CastPlayerRestorePlan.yieldToCast(permitted: () => true,
      pauseLocal: () => localPause.future,
      settleReceiver: () async {
        if (sleepStopped) { events.add('receiver:pause'); await receiverPause.future; }
      }, publish: () { events.add('publish:cast'); });
    sleepStopped = true;
    localPause.complete();
    await Future<void>.value();
    expect(events, ['receiver:pause']);
    receiverPause.complete();
    expect(await yielding, isTrue);
    expect(events, ['receiver:pause', 'publish:cast']);
  });

  test('previous guide completion retains its original intent and cannot promote A', () async {
    final previous = identity();
    var current = previous;
    final ticket = CastPlayerEffectTicket(previous, () => current);
    final guide = Completer<({int season, int episode})?>();
    final resolved = ticket.resolve(guide.future);
    current = identity(generation: 2, content: 'B', media: 8);
    guide.complete((season: 1, episode: 3));
    expect(await resolved, isNull);
    expect(current.generation, 2);
    expect(current.contentId, 'B');
  });

  test('confirmed retirement releases only its uncommitted initial transfer', () {
    final ownership = PlaybackOwnershipController()..beginCastTransfer();
    void settle({bool current = true, bool committed = false, bool uncertain = false}) {
      if (CastPlayerRestorePlan.mayCancelInitialTransfer(ownsAttempt: current,
        remoteCommitted: committed, receiverUncertain: uncertain)) {
        ownership.cancelCastTransfer();
      }
    }
    settle(uncertain: true);
    expect(ownership.owner, PlaybackOwner.transferringToCast);
    settle(current: false);
    expect(ownership.owner, PlaybackOwner.transferringToCast);
    settle();
    expect(ownership.owner, PlaybackOwner.local);
    ownership.beginCastTransfer();
    ownership.commitCast();
    settle(committed: true);
    expect(ownership.owner, PlaybackOwner.cast);
  });

  test('local pause failure cannot publish Cast ownership', () async {
    final ownership = PlaybackOwnershipController()..beginCastTransfer();
    var castPublications = 0;
    final pending = CastPlayerRestorePlan.yieldToCast(
      permitted: () => ownership.owner == PlaybackOwner.transferringToCast,
      pauseLocal: () async { throw StateError('local pause failed'); },
      publish: () { ownership.commitCast(); castPublications++; },
    );
    await expectLater(pending, throwsStateError);
    expect(ownership.owner, PlaybackOwner.transferringToCast);
    expect(castPublications, 0);
  });

  test('retired receiver during local pause cannot publish Cast ownership', () async {
    final ownership = PlaybackOwnershipController()..beginCastTransfer();
    final paused = Completer<void>();
    var receiverCurrent = true;
    final pending = CastPlayerRestorePlan.yieldToCast(
      permitted: () => receiverCurrent &&
          ownership.owner == PlaybackOwner.transferringToCast,
      pauseLocal: () => paused.future,
    );
    receiverCurrent = false;
    paused.complete();
    expect(await pending, isFalse);
    expect(ownership.owner, PlaybackOwner.transferringToCast);
  });

  test('late manual OFF cannot overwrite newer language on the same media', () async {
    final media = identity();
    var revision = 1;
    final off = CastPlayerManualIntentTicket(revision: revision,
      currentRevision: () => revision, media: CastPlayerEffectTicket(media, () => media));
    var remembered = 'off';
    final pendingOff = Completer<void>();
    final result = (() async {
      await pendingOff.future;
      if (off.isCurrent) remembered = 'off';
    })();
    revision++;
    final selected = CastPlayerManualIntentTicket(revision: revision,
      currentRevision: () => revision, media: CastPlayerEffectTicket(media, () => media));
    remembered = 'es';
    pendingOff.complete();
    await result;
    expect(remembered, 'es');
    expect(off.isCurrent, isFalse);
    expect(selected.isCurrent, isTrue);
  });

  test('restored receiver refresh cannot adopt after local source changes', () async {
    var source = 'A';
    final pending = Completer<String>();
    final effect = CastPlayerGuardedEffect.resolve(pending.future, () => source == 'A');
    source = 'B';
    pending.complete('receiver-A');
    expect(await effect, isNull);
    expect(source, 'B');
  });

  test('receiver reconnect while local restore seeks blocks play and publication', () async {
    final seeking = Completer<void>();
    var retired = true;
    var localPlays = 0;
    final restoring = CastPlayerRestorePlan.restore(parkedUrl: 'B', committedUrl: 'B',
      headersChanged: false, position: const Duration(seconds: 24), shouldPlay: true,
      permitted: () => retired, open: () async {}, seek: (_) => seeking.future,
      setPlaying: (_) async { localPlays++; });
    retired = false;
    seeking.complete();
    expect(await restoring, isFalse);
    expect(localPlays, 0);
  });

  test('E37 old tracker STOP uses A clock and settles before B starts', () async {
    final outgoing = CastPlayerTrackingTarget(imdbId: 'ttA', contentType: 'series',
      season: 1, episode: 4, position: const Duration(minutes: 70),
      duration: const Duration(minutes: 100));
    final incoming = CastPlayerTrackingTarget(imdbId: 'ttB', contentType: 'series',
      season: 2, episode: 1, position: Duration.zero,
      duration: const Duration(minutes: 40));
    final pendingStop = Completer<void>();
    final queue = CastPlayerTrackingQueue();
    final calls = <String>[];
    final stop = queue.send(() async {
      calls.add('stop:${outgoing.imdbId}:${outgoing.episode}:${outgoing.progress}');
      await pendingStop.future;
    });
    final start = queue.send(() async {
      calls.add('start:${incoming.imdbId}:${incoming.progress}');
    });
    await Future<void>.value();
    expect(calls, ['stop:ttA:4:70.0']);
    pendingStop.complete();
    await Future.wait([stop, start]);
    expect(calls, ['stop:ttA:4:70.0', 'start:ttB:0.0']);
  });

  test('E38 ended continuation is rejected after newer navigation', () async {
    final start = identity(ended: 5);
    var current = start;
    final gate = CastPlayerEffectTicket(start, () => current);
    final pending = Completer<void>();
    var advances = 0;
    final effect = (() async {
      await pending.future;
      if (!gate.isCurrent) return false;
      advances++;
      return true;
    })();
    current = identity(generation: 2, content: 'B', media: 8, ended: 5);
    pending.complete();
    expect(await effect, isFalse);
    expect(advances, 0);
  });

  test('E39 same URL and media session from another epoch has no authority', () {
    final start = identity(ended: 5);
    var current = start;
    final ticket = CastPlayerEffectTicket(start, () => current);
    expect(ticket.isCurrent, isTrue);
    current = identity(epoch: 2, ended: 5);
    expect(ticket.isCurrent, isFalse);
    current = identity(ended: 6);
    expect(ticket.isCurrent, isFalse);
  });

  test('E40 threshold and ended claim one immutable effective completion', () {
    final gate = CastPlayerCompletionGate();
    const completion = CastPlayerCompletionTarget(imdbId: 'ttB',
      contentType: 'series', title: 'Current show', season: 2, episode: 3);
    expect(gate.claim(completion.key), isTrue);
    expect(gate.claim(completion.key), isFalse);
    expect(completion.imdbId, 'ttB');
    expect(completion.episode, 3);
    gate.reset();
    expect(gate.claim(completion.key), isTrue);
  });

  test('E41 disconnect opens committed B before seeking and restoring play', () async {
    var localUrl = 'A';
    final calls = <String>[];
    final restored = await CastPlayerRestorePlan.restore(
      parkedUrl: localUrl, committedUrl: 'B', headersChanged: false,
      position: const Duration(seconds: 24), shouldPlay: true,
      permitted: () => true,
      open: () async { calls.add('open:B'); localUrl = 'B'; },
      seek: (position) async { calls.add('seek:$localUrl:${position.inSeconds}'); },
      setPlaying: (play) async { calls.add('play:$localUrl:$play'); },
    );
    expect(restored, isTrue);
    expect(localUrl, 'B');
    expect(calls, ['open:B', 'seek:B:24', 'play:B:true']);
  });

  test('E42 foreground resume rejects both transfers and Cast ownership', () {
    final ownership = PlaybackOwnershipController();
    var localStarts = 0;
    void foreground() {
      if (CastPlayerRestorePlan.mayResumeLocal(
        localOwnsPlayback: ownership.isLocal, sleepStopped: false)) localStarts++;
    }
    ownership.beginCastTransfer();
    foreground();
    ownership.commitCast();
    foreground();
    ownership.beginLocalTransfer();
    foreground();
    expect(localStarts, 0);
    ownership.commitLocal();
    foreground();
    expect(localStarts, 1);
    expect(CastPlayerRestorePlan.mayResumeLocal(localOwnsPlayback: true,
      sleepStopped: true), isFalse);
  });
}
