import 'dart:async';

import 'package:debrify/services/cast_load_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

class FakeCastGateway {
  final started = <String>[];
  final responses = <String, Completer<String>>{};
  int running = 0;
  int maxRunning = 0;

  Future<String> load(String name) async {
    started.add(name);
    running++;
    if (running > maxRunning) maxRunning = running;
    final pending = Completer<String>();
    responses[name] = pending;
    try {
      return await pending.future;
    } finally {
      running--;
    }
  }
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('I01 slow A, fast B intent: stale A never commits', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final aId = q.beginIntent();
    final a = q.submit(generation: aId, load: () => f.load('A'), verify: (s) => s == 'A');
    final bId = q.beginIntent();
    final b = q.submit(generation: bId, load: () => f.load('B'), verify: (s) => s == 'B');
    expect((await a).outcome, CastLoadOutcome.superseded);
    expect(f.started, ['A']);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A', 'B']);
    f.responses['B']!.complete('B');
    expect((await b).outcome, CastLoadOutcome.committed);
    expect(f.maxRunning, 1);
  });

  test('I02 late provider A cannot enqueue after B has begun', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final b = q.beginIntent();
    final bResult = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    final aResult = await q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    expect(aResult.outcome, CastLoadOutcome.superseded);
    expect(f.started, ['B']);
    f.responses['B']!.complete('B');
    expect((await bResult).committed, true);
  });

  test('I03 A in flight, B/C queued: B settles, only C is dispatched', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    final b = q.beginIntent();
    final bf = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    final c = q.beginIntent();
    final cf = q.submit(generation: c, load: () => f.load('C'), verify: (_) => true);
    expect((await af).outcome, CastLoadOutcome.superseded);
    expect((await bf).outcome, CastLoadOutcome.superseded);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A', 'C']);
    f.responses['C']!.complete('C');
    expect((await cf).committed, true);
    expect(f.maxRunning, 1);
  });

  test('L11 A fails while newer B is pending; B drains', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    final b = q.beginIntent();
    final bf = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    f.responses['A']!.completeError(StateError('receiver failed'));
    expect((await af).outcome, CastLoadOutcome.superseded);
    await flush();
    f.responses['B']!.complete('B');
    expect((await bf).committed, true);
    expect(f.maxRunning, 1);
  });

  test('current failure settles and does not poison subsequent requests', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    f.responses['A']!.completeError(StateError('transport'));
    expect((await af).outcome, CastLoadOutcome.failed);
    await flush();
    final b = q.beginIntent();
    final bf = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    f.responses['B']!.complete('B');
    expect((await bf).committed, true);
  });

  test('invalid ACK identity is rejected', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (s) => s == 'A');
    f.responses['A']!.complete('wrong');
    expect((await af).outcome, CastLoadOutcome.rejected);
  });

  test('rollback of obsolete generation is not submitted', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final old = q.beginIntent();
    q.beginIntent();
    final rollback = await q.submit(
      generation: old, load: () => f.load('old-rollback'), verify: (_) => true,
    );
    expect(rollback.outcome, CastLoadOutcome.superseded);
    expect(f.started, isEmpty);
  });

  test('disconnect invalidates caller, but late ACK never commits', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    q.invalidate();
    expect((await af).outcome, CastLoadOutcome.cancelled);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A']);
  });

  test('new session intent cannot overlap old unresolved transport', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    q.invalidate();
    expect((await af).outcome, CastLoadOutcome.cancelled);
    final b = q.beginIntent();
    final bf = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    expect(f.started, ['A']);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A','B']);
    f.responses['B']!.complete('B');
    expect((await bf).committed, true);
  });

  test('L09 timeout settles caller without releasing physical exclusion', () {
    fakeAsync((clock) {
      final q = CastLoadCoordinator<String>(callerTimeout: const Duration(seconds: 1));
      final f = FakeCastGateway();
      CastLoadResult<String>? first;
      final a = q.beginIntent();
      q.submit(generation: a, load: () => f.load('A'), verify: (_) => true)
          .then((result) => first = result);
      clock.elapse(const Duration(seconds: 1));
      expect(first!.outcome, CastLoadOutcome.failed);
      expect(q.isBlockedOnReceiver, isTrue);
      final b = q.beginIntent();
      CastLoadResult<String>? second;
      q.submit(generation: b, load: () => f.load('B'), verify: (_) => true)
          .then((result) => second = result);
      clock.flushMicrotasks();
      expect(f.started, ['A']);
      f.responses['A']!.complete('A');
      clock.flushMicrotasks();
      expect(f.started, ['A', 'B']);
      f.responses['B']!.complete('B');
      clock.flushMicrotasks();
      expect(second!.committed, isTrue);
      expect(f.maxRunning, 1);
      q.dispose();
    });
  });

  test('L07 reentrant completion submits later request only after old completion', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final first = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    final later = first.then((_) {
      final b = q.beginIntent();
      return q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    });
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A', 'B']);
    f.responses['B']!.complete('B');
    expect((await later).committed, true);
    expect(f.maxRunning, 1);
  });

  test('L12 dispose settles physical and queued callers exactly once', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final af = q.submit(generation: a, load: () => f.load('A'), verify: (_) => true);
    final b = q.beginIntent();
    final bf = q.submit(generation: b, load: () => f.load('B'), verify: (_) => true);
    q.dispose();
    expect((await af).outcome, CastLoadOutcome.superseded);
    expect((await bf).outcome, CastLoadOutcome.cancelled);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A']);
    final c = q.beginIntent();
    final cr = await q.submit(generation: c, load: () => f.load('C'), verify: (_) => true);
    expect(cr.outcome, CastLoadOutcome.cancelled);
  });

  test('pre-dispatch permission rejects without touching receiver', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final r = await q.submit(
      generation: a,
      permitted: () => false,
      load: () => f.load('A'),
      verify: (_) => true,
    );
    expect(r.outcome, CastLoadOutcome.cancelled);
    expect(f.started, isEmpty);
  });
  test('prior dispatched control physically blocks a newer LOAD', () async {
    final q = CastLoadCoordinator<String>();
    final gateway = FakeCastGateway();
    final controlGate = Completer<String>();
    final old = q.beginIntent();
    final control = q.dispatchControl<String>(
      generation: old, command: () => controlGate.future,
    );
    final current = q.beginIntent();
    final pending = q.submit(
      generation: current, load: () => gateway.load('new'),
      verify: (_) => true,
    );
    expect(gateway.started, isEmpty);
    controlGate.complete('old seek ACK');
    expect(await control, isNull);
    await flush();
    expect(gateway.started, ['new']);
    gateway.responses['new']!.complete('new');
    expect((await pending).committed, true);
    expect(gateway.maxRunning, 1);
  });

  test('a new control does not bypass an outstanding LOAD', () async {
    final q = CastLoadCoordinator<String>();
    final gateway = FakeCastGateway();
    final activeId = q.beginIntent();
    final active = q.submit(
      generation: activeId,
      load: () => gateway.load('A'), verify: (_) => true,
    );
    var seekCalls = 0;
    final blocked = await q.dispatchControl<String>(
      generation: activeId,
      command: () async { ++seekCalls; return 'seek'; },
    );
    expect(blocked, isNull);
    expect(seekCalls, 0);
    gateway.responses['A']!.complete('A');
    expect((await active).committed, true);
  });

  test('control permission is rechecked before physical dispatch', () async {
    final q = CastLoadCoordinator<String>();
    final ticket = q.beginIntent();
    var dispatched = false;
    final result = await q.dispatchControl<String>(
      generation: ticket,
      permitted: () => false,
      command: () async { dispatched = true; return 'unexpected'; },
    );
    expect(result, isNull);
    expect(dispatched, false);
  });

  test('L10 stale physical ACK is observed but cannot become logical commit',
      () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final observed = <String>[];
    final firstTicket = q.beginIntent();
    final first = q.submit(
      generation: firstTicket,
      load: () => f.load('A'),
      verify: (_) => true,
      onPhysicalReply: (reply, generation) {
        observed.add('$generation:$reply');
      },
    );
    final laterTicket = q.beginIntent();
    expect((await first).outcome, CastLoadOutcome.superseded);
    f.responses['A']!.complete('A');
    await flush();
    expect(observed, ['$firstTicket:A']);
    final later = q.submit(
      generation: laterTicket,
      load: () => f.load('B'),
      verify: (_) => true,
    );
    f.responses['B']!.complete('B');
    expect((await later).committed, true);
    expect(f.maxRunning, 1);
  });


  test('L08 pending replacement within same generation dispatches only final', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final g = q.beginIntent();
    final active = q.submit(
      generation: g, load: () => f.load('busy'), verify: (_) => true,
    );
    final firstQueued = q.submit(
      generation: g, load: () => f.load('obsolete'), verify: (_) => true,
    );
    final lastQueued = q.submit(
      generation: g, load: () => f.load('latest'), verify: (_) => true,
    );
    expect((await firstQueued).outcome, CastLoadOutcome.superseded);
    f.responses['busy']!.complete('busy');
    expect((await active).committed, true);
    await flush();
    expect(f.started, ['busy', 'latest']);
    f.responses['latest']!.complete('latest');
    expect((await lastQueued).committed, true);
    expect(f.maxRunning, 1);
  });

  test('rejected physical ACK leaves coordinator reusable', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final rejected = q.submit(
      generation: a, load: () => f.load('A'),
      verify: (reply) => reply == 'expected-A',
    );
    f.responses['A']!.complete('wrong content');
    expect((await rejected).outcome, CastLoadOutcome.rejected);
    final b = q.beginIntent();
    final accepted = q.submit(
      generation: b, load: () => f.load('B'), verify: (_) => true,
    );
    f.responses['B']!.complete('B');
    expect((await accepted).committed, true);
    expect(f.maxRunning, 1);
  });

  test('throwing physical observer does not authorize stale commit', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final a = q.beginIntent();
    final old = q.submit(
      generation: a, load: () => f.load('A'), verify: (_) => true,
      onPhysicalReply: (_, __) => throw StateError('observer failed'),
    );
    final b = q.beginIntent();
    final newer = q.submit(
      generation: b, load: () => f.load('B'), verify: (_) => true,
    );
    expect((await old).outcome, CastLoadOutcome.superseded);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A', 'B']);
    f.responses['B']!.complete('B');
    expect((await newer).committed, true);
  });

  test('I05 cancelled ticket never invokes deferred LOAD factory', () async {
    final q = CastLoadCoordinator<String>();
    final ticket = q.beginIntent();
    q.invalidate();
    var invoked = 0;
    final response = await q.submit(
      generation: ticket, load: () async {
        invoked += 1;
        return 'unexpected';
      }, verify: (_) => true,
    );
    expect(response.outcome, CastLoadOutcome.superseded);
    expect(invoked, 0);
  });

  test('stale control result is logically null after navigation', () async {
    final q = CastLoadCoordinator<String>();
    final ack = Completer<String>();
    final a = q.beginIntent();
    final control = q.dispatchControl<String>(
      generation: a, command: () => ack.future,
    );
    q.beginIntent();
    ack.complete('old pause');
    expect(await control, isNull);
    expect(q.hasInFlight, isFalse);
  });

  test('active control is not bypassed by a newer LOAD', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final controlAck = Completer<String>();
    final first = q.beginIntent();
    final control = q.dispatchControl<String>(
      generation: first, command: () => controlAck.future,
    );
    final second = q.beginIntent();
    final load = q.submit(
      generation: second, load: () => f.load('B'), verify: (_) => true,
    );
    expect(f.started, isEmpty);
    controlAck.complete('A seek');
    expect(await control, isNull);
    await flush();
    expect(f.started, ['B']);
    f.responses['B']!.complete('B');
    expect((await load).committed, true);
    expect(f.maxRunning, 1);
  });

  test('dispose during control still preserves physical exclusion', () async {
    final q = CastLoadCoordinator<String>();
    final ack = Completer<String>();
    final ticket = q.beginIntent();
    final control = q.dispatchControl<String>(
      generation: ticket, command: () => ack.future,
    );
    q.dispose();
    final rejected = await q.dispatchControl<String>(
      generation: ticket, command: () async => 'must not run',
    );
    expect(rejected, isNull);
    ack.complete('late reply');
    expect(await control, isNull);
    await flush();
    expect(q.hasInFlight, isFalse);
  });

  test('current permission revocation blocks pending provider dispatch', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final firstTicket = q.beginIntent();
    final current = q.submit(
      generation: firstTicket, load: () => f.load('A'), verify: (_) => true,
    );
    final nextTicket = q.beginIntent();
    var permitted = true;
    final next = q.submit(
      generation: nextTicket, load: () => f.load('B'),
      permitted: () => permitted, verify: (_) => true,
    );
    permitted = false;
    f.responses['A']!.complete('A');
    expect((await current).outcome, CastLoadOutcome.superseded);
    expect((await next).outcome, CastLoadOutcome.cancelled);
    expect(f.started, ['A']);
  });

  test('old generation cannot issue control after new session intent', () async {
    final q = CastLoadCoordinator<String>();
    final old = q.beginIntent();
    final latest = q.beginIntent();
    var executed = false;
    final stale = await q.dispatchControl<String>(
      generation: old, command: () async {
        executed = true;
        return 'old seek';
      },
    );
    expect(stale, isNull);
    expect(executed, false);
    final current = await q.dispatchControl<String>(
      generation: latest, command: () async => 'new seek',
    );
    expect(current, 'new seek');
  });


  test('I04 current rejected load never promotes an older request', () async {
    final q = CastLoadCoordinator<String>();
    final f = FakeCastGateway();
    final oldTicket = q.beginIntent();
    final old = q.submit(
      generation: oldTicket, load: () => f.load('A'),
      verify: (_) => true,
    );
    final currentTicket = q.beginIntent();
    final newer = q.submit(
      generation: currentTicket, load: () => f.load('B'),
      verify: (_) => true,
    );
    expect((await old).outcome, CastLoadOutcome.superseded);
    f.responses['A']!.complete('A');
    await flush();
    expect(f.started, ['A', 'B']);
    f.responses['B']!.completeError(StateError('provider/receiver refused B'));
    expect((await newer).outcome, CastLoadOutcome.failed);
    expect(q.isCurrent(oldTicket), false);
    expect(q.isCurrent(currentTicket), true);
    expect(f.maxRunning, 1);
  });

  test('dispose settles control caller immediately while native Future remains held', () async {
    final q = CastLoadCoordinator<String>(callerTimeout: Duration.zero);
    final reply = Completer<String>();
    final ticket = q.beginIntent();
    final control = q.dispatchControl<String>(generation: ticket,
      command: () => reply.future);
    q.dispose();
    expect(await control, isNull);
    expect(q.hasInFlight, isTrue);
    reply.complete('late acknowledgement');
    await flush();
    expect(q.hasInFlight, isFalse);
  });

}
