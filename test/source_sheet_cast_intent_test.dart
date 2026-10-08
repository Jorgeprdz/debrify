import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent fixture(int index) => Torrent(
  rowid: index,
  infohash: 'fixture',
  name: 'Candidate $index',
  sizeBytes: 0, createdUnix: 0, seeders: 0, leechers: 0,
  completed: 0, scrapedDate: 0,
  streamType: StreamType.directUrl,
);

void main() {
  testWidgets('current Cast selection survives own authority change and telemetry rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final rebuild = ValueNotifier<int>(0);
    final pending = Completer<String?>();
    final commits = <int>[];
    var authority = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<int>(
      valueListenable: rebuild,
      builder: (_, __, ___) => SourceSheet(sources: [fixture(0), fixture(1)],
        currentSourceIndex: 0, currentPlaybackAuthority: () => authority,
        resolveSource: (_) async => null, onSourceSelected: (_, __) {},
        onSelectionIntent: (_) => ++authority,
        resolveSourceWithIntent: (_, __) => pending.future,
        onResolvedSourceSelected: (index, _, ticket) {
          if (ticket == authority) commits.add(index);
        }, onClose: () {}),
    ))));
    await tester.tap(find.text('Candidate 1'));
    await tester.pump();
    rebuild.value++;
    await tester.pump();
    pending.complete('https://media.invalid/current.mp4');
    await tester.pump();
    expect(authority, 1);
    expect(commits, [1]);
    await tester.pumpWidget(const SizedBox());
    rebuild.dispose();
  });

  testWidgets('A B A current-source tap retires pending B provider intent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pendingB = Completer<String?>();
    final commits = <int>[];
    var authority = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SourceSheet(
      sources: [fixture(0), fixture(1)], currentSourceIndex: 0,
      currentPlaybackAuthority: () => authority,
      resolveSource: (_) async => null, onSourceSelected: (_, __) {},
      onSelectionIntent: (_) => ++authority,
      resolveSourceWithIntent: (source, _) => source.rowid == 1
          ? pendingB.future : Future.value('https://media.invalid/a.mp4'),
      onResolvedSourceSelected: (index, _, ticket) {
        if (ticket == authority) commits.add(index);
      }, onClose: () {},
    ))));
    await tester.tap(find.text('Candidate 1'));
    await tester.pump();
    await tester.tap(find.text('Candidate 0'));
    await tester.pump();
    pendingB.complete('https://media.invalid/b.mp4');
    await tester.pump();
    expect(authority, 2);
    expect(commits, [0]);
  });

  testWidgets('addon result from episode A cannot merge after episode B rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final episodes = Completer<List<Torrent>?>();
    final currentEpisode = ValueNotifier<int>(1);
    final merges = <List<Torrent>>[];
    final pinned = Torrent.fromJson({...fixture(0).toJson(), 'source': 'stremio:comet'});
    final fetcher = SeriesSourceFetcher(season: 1, episode: 1,
      searchPacks: (_, _) async => [], searchEpisodes: (_, _) async => [],
      listAddons: () async => const [SourceAddonRef('comet-id', 'Comet')],
      fetchAddonEpisodes: (_, _, _) => episodes.future);
    await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<int>(
      valueListenable: currentEpisode,
      builder: (_, episode, __) => SourceSheet(sources: [pinned], currentSourceIndex: 0,
        currentSeason: 1, currentEpisode: episode, seriesFetcher: fetcher,
        currentPlaybackAuthority: () => currentEpisode.value,
        resolveSource: (_) async => null, onSourceSelected: (_, __) {},
        onSourcesMerged: merges.add, onClose: () {}),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch all results'));
    await tester.pump();
    currentEpisode.value = 2;
    await tester.pump();
    episodes.complete([fixture(2)]);
    await tester.pump();
    expect(merges, isEmpty);
    expect(find.text('Candidate 2'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    currentEpisode.dispose();
  });

  testWidgets('latest selected source wins over prior provider', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final a = Completer<String?>();
    final b = Completer<String?>();
    final commits = <int>[];
    var ticket = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SourceSheet(
        sources: [fixture(0), fixture(1)],
        currentSourceIndex: -1,
        resolveSource: (_) async => null,
        onSourceSelected: (_, __) {},
        onSelectionIntent: (_) => ++ticket,
        resolveSourceWithIntent: (s, _) => s.rowid == 0 ? a.future : b.future,
        onResolvedSourceSelected: (i, _, t) {
          if (t == ticket) commits.add(i);
        },
        onClose: () {},
      )),
    ));
    await tester.tap(find.text('Candidate 0'));
    await tester.pump();
    await tester.tap(find.text('Candidate 1'));
    await tester.pump();
    b.complete('https://media.invalid/b.mp4');
    await tester.pump();
    a.complete('https://media.invalid/a.mp4');
    await tester.pump();
    expect(commits, [1]);
  });
}
