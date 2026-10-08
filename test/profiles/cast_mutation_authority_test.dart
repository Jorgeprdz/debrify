// AUTHORED / NOT RUN. Uses the actual preference mutation barrier and store.
import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'p.one.g.1.cast_intent': 'previous',
      'p.one.g.1.finished': <String>['old'],
      'p.two.g.1.cast_intent': 'other-profile',
    });
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    ProfileRuntime.initializeCommitted(ProfileScope(
      profileId: 'one', dataGeneration: 1, sessionEpoch: 1));
  });
  tearDown(() {
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    ProfileRuntime.debugReset();
  });

  test('Cast string write revoked while WebDAV barrier held never reaches delegate', () async {
    final prefs = await ProfilePreferences.instance();
    final entered = Completer<void>();
    final release = Completer<void>();
    final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var permitted = true;
    final revision = ProfilePreferences.diagnosticMutationState['preferenceRevision'];
    final write = prefs.setStringGuarded('cast_intent', 'obsolete-off',
      permitted: () => permitted);
    permitted = false;
    release.complete();
    await snapshot;
    expect(await write, isFalse);
    expect(prefs.getString('cast_intent'), 'previous');
    expect(ProfilePreferences.diagnosticMutationState['preferenceRevision'], revision);
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('p.two.g.1.cast_intent'), 'other-profile');
  });

  test('Cast completion list revoked behind barrier cannot mark another episode finished', () async {
    final prefs = await ProfilePreferences.instance();
    final entered = Completer<void>();
    final release = Completer<void>();
    final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var permitted = true;
    final write = prefs.setStringListGuarded('finished', ['old', 'obsolete-A'],
      permitted: () => permitted);
    permitted = false;
    release.complete();
    await snapshot;
    expect(await write, isFalse);
    expect(prefs.getStringList('finished'), ['old']);
    expect(await prefs.setStringListGuarded('finished', ['old', 'current-B'],
      permitted: () => true), isTrue);
    expect(prefs.getStringList('finished'), ['old', 'current-B']);
  });

  test('Revoked atomic Cast preference draft never invokes mutation callback', () async {
    final prefs = await ProfilePreferences.instance();
    final entered = Completer<void>();
    final release = Completer<void>();
    final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var permitted = true;
    var transforms = 0;
    final write = prefs.mutateStringAtomically('cast_intent', (current) {
      transforms++;
      return '$current:obsolete';
    }, permitted: () => permitted);
    permitted = false;
    release.complete();
    await snapshot;
    expect(await write, isFalse);
    expect(transforms, 0);
    expect(prefs.getString('cast_intent'), 'previous');
    expect(await prefs.mutateStringAtomically('cast_intent',
      (current) => '$current:current', permitted: () => true), isTrue);
    expect(prefs.getString('cast_intent'), 'previous:current');
  });
}
