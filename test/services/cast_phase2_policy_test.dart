import 'package:debrify/services/cast_phase2_policy.dart';
import 'package:flutter_test/flutter_test.dart';

CastRemoteTrack audio(
  String id,
  String language, {
  bool selected = false,
}) => CastRemoteTrack(
  id: id,
  type: CastRemoteTrackType.audio,
  language: language,
  label: language,
  selected: selected,
);

CastRemoteTrack subtitle(
  String id,
  String language, {
  bool selected = false,
}) => CastRemoteTrack(
  id: id,
  type: CastRemoteTrackType.subtitle,
  language: language,
  label: language,
  mimeType: 'text/vtt',
  selected: selected,
);

void main() {
  group('Cast audio language policy', () {
    final tracks = <CastRemoteTrack>[
      audio('11', 'es-MX'),
      audio('12', 'eng'),
      audio('13', 'fr'),
    ];

    test('English preference selects equivalent eng track', () {
      final picked = CastLanguagePolicy.chooseAudio(
        tracks: tracks,
        preferredLanguage: 'en',
      );
      expect(picked?.id, '12');
    });

    test('manual selection language wins over default English', () {
      final picked = CastLanguagePolicy.chooseAudio(
        tracks: tracks,
        manualLanguage: 'es-419',
        preferredLanguage: 'en-US',
      );
      expect(picked?.id, '11');
    });

    test('missing preferred language falls back to English', () {
      final picked = CastLanguagePolicy.chooseAudio(
        tracks: tracks,
        preferredLanguage: 'ja',
      );
      expect(picked?.id, '12');
    });

    test('selected/default track wins when English is unavailable', () {
      final picked = CastLanguagePolicy.chooseAudio(
        tracks: <CastRemoteTrack>[
          audio('21', 'de'),
          audio('22', 'fr', selected: true),
        ],
        preferredLanguage: 'ja',
      );
      expect(picked?.id, '22');
    });

    test('exact manual regional audio wins before language-family fallback', () {
      final picked = CastLanguagePolicy.chooseAudio(
        tracks: <CastRemoteTrack>[
          audio('70', 'en-GB'),
          audio('71', 'en-US'),
        ],
        manualLanguage: 'en-US',
        preferredLanguage: 'en',
      );
      expect(picked?.id, '71');
    });

    test('session restore can remap manual language to a new ephemeral id', () {
      final restored = CastLanguagePolicy.chooseAudio(
        tracks: <CastRemoteTrack>[
          audio('901', 'en-GB'),
          audio('902', 'spa'),
        ],
        manualLanguage: 'eng',
      );
      expect(restored?.id, '901');
    });
  });

  group('Cast subtitle language policy', () {
    final tracks = <CastRemoteTrack>[
      subtitle('31', 'en'),
      subtitle('32', 'es-MX'),
      subtitle('33', 'fr'),
    ];

    test('Spanish preference selects es-MX through canonical matching', () {
      final picked = CastLanguagePolicy.chooseSubtitle(
        tracks: tracks,
        explicitlyDisabled: false,
        preferredLanguage: 'spa',
      );
      expect(picked?.id, '32');
    });

    test('manual subtitle wins over Spanish default', () {
      final picked = CastLanguagePolicy.chooseSubtitle(
        tracks: tracks,
        explicitlyDisabled: false,
        manualLanguage: 'en-US',
        preferredLanguage: 'es',
      );
      expect(picked?.id, '31');
    });

    test('explicit subtitles disabled always wins', () {
      final picked = CastLanguagePolicy.chooseSubtitle(
        tracks: tracks,
        explicitlyDisabled: true,
        manualLanguage: 'es-419',
        preferredLanguage: 'es',
      );
      expect(picked, isNull);
    });

    test('Spanish fallback prefers LATAM over Spain when generic es is absent', () {
      final picked = CastLanguagePolicy.chooseSubtitle(
        tracks: <CastRemoteTrack>[
          subtitle('80', 'es-ES'),
          subtitle('81', 'es-419'),
        ],
        explicitlyDisabled: false,
        preferredLanguage: 'es',
      );
      expect(picked?.id, '81');
    });

    test('es, es-MX and es-419 normalize to the same Spanish family', () {
      for (final preference in <String>['es', 'spa', 'es-MX', 'es-419']) {
        final picked = CastLanguagePolicy.chooseSubtitle(
          tracks: tracks,
          explicitlyDisabled: false,
          preferredLanguage: preference,
        );
        expect(picked?.id, '32', reason: preference);
      }
    });
  });

  group('External Cast subtitle compatibility', () {
    test('remote WebVTT is directly supported', () {
      final result = CastSubtitleSupport.classify(
        'https://subs.example.test/es/movie.vtt',
      );
      expect(result.kind, CastSubtitleSupportKind.supported);
      expect(result.mimeType, 'text/vtt');
    });

    test('SRT is classified as requiring conversion, not supported', () {
      expect(
        CastSubtitleSupport.classify(
          'https://subs.example.test/movie.srt',
        ).kind,
        CastSubtitleSupportKind.requiresConversion,
      );
    });

    test('ASS/SSA is classified unsupported', () {
      expect(
        CastSubtitleSupport.classify(
          'https://subs.example.test/movie.ass',
        ).kind,
        CastSubtitleSupportKind.unsupportedFormat,
      );
    });

    test('local/private subtitle URL is unreachable by receiver', () {
      expect(
        CastSubtitleSupport.classify(
          'file:///data/user/0/com.debrify.app/cache/sub.vtt',
        ).kind,
        CastSubtitleSupportKind.unreachable,
      );
    });
  });

  group('Cast source compatibility and transaction', () {
    test('direct MP4 is supported; unknown HTTP container remains attemptable', () {
      expect(
        CastSourceCompatibility.classify(
          url: 'https://cdn.example.test/movie.mp4',
        ).kind,
        CastSourceCompatibilityKind.supported,
      );
      final unknown = CastSourceCompatibility.classify(
        url: 'https://cdn.example.test/tokenized/stream',
      );
      expect(unknown.kind, CastSourceCompatibilityKind.unknown);
      expect(unknown.canAttempt, isTrue);
    });

    test('explicit blockers are rejected while heuristic-only containers stay unknown', () {
      expect(
        CastSourceCompatibility.classify(
          url: 'https://cdn.example.test/movie.mp4',
          headers: const <String, String>{'Authorization': 'redacted'},
        ).kind,
        CastSourceCompatibilityKind.unsupportedHeaders,
      );
      expect(
        CastSourceCompatibility.classify(url: 'magnet:?xt=urn:btih:abc').kind,
        CastSourceCompatibilityKind.unsupportedScheme,
      );
      expect(
        CastSourceCompatibility.classify(
          url: 'https://cdn.example.test/movie.mkv',
        ).kind,
        CastSourceCompatibilityKind.unknown,
      );
      expect(
        CastSourceCompatibility.classify(
          url: 'https://cdn.example.test/video.mp4',
          separateAudioUrl: 'https://cdn.example.test/audio.m4a',
        ).kind,
        CastSourceCompatibilityKind.unsupportedAudioVideoLayout,
      );
    });

    test('source switch preserves outgoing position and play state', () {
      final transaction = CastSwitchTransaction<String>(
        previous: 'SOURCE_A',
        position: const Duration(minutes: 17, seconds: 3),
        wasPlaying: true,
      );
      expect(transaction.position, const Duration(minutes: 17, seconds: 3));
      expect(transaction.wasPlaying, isTrue);
    });

    test('successful source load commits new ownership', () {
      final transaction = CastSwitchTransaction<String>(
        previous: 'SOURCE_A',
        position: Duration.zero,
        wasPlaying: true,
      );
      transaction.commit('SOURCE_B');
      expect(transaction.hasCommitted, isTrue);
      expect(transaction.committed, 'SOURCE_B');
    });

    test('failed source load rolls back logical ownership to previous source', () {
      final transaction = CastSwitchTransaction<String>(
        previous: 'SOURCE_A',
        position: const Duration(seconds: 90),
        wasPlaying: false,
      )..commit('SOURCE_B');
      expect(transaction.rollback(), 'SOURCE_A');
      expect(transaction.hasCommitted, isFalse);
    });
  });

  group('Autoplay resolution transaction', () {
    test('no next episode leaves current media authoritative', () {
      final transaction = CastSwitchTransaction<Map<String, Object?>>(
        previous: const <String, Object?>{
          'title': 'Episode 4',
          'season': 1,
          'episode': 4,
        },
        position: const Duration(minutes: 41),
        wasPlaying: true,
      );

      expect(transaction.hasCommitted, isFalse);
      expect(transaction.rollback()['episode'], 4);
    });

    test('resolver failure preserves previous media ownership', () {
      final transaction = CastSwitchTransaction<String>(
        previous: 'EPISODE_4_SOURCE',
        position: const Duration(minutes: 41),
        wasPlaying: true,
      );

      // No candidate is committed when resolution returns null/fails.
      expect(transaction.rollback(), 'EPISODE_4_SOURCE');
      expect(transaction.hasCommitted, isFalse);
    });

    test('metadata changes only when next media commits', () {
      final transaction = CastSwitchTransaction<Map<String, Object?>>(
        previous: const <String, Object?>{
          'title': 'Episode 4',
          'season': 1,
          'episode': 4,
        },
        position: Duration.zero,
        wasPlaying: true,
      );
      const nextMetadata = <String, Object?>{
        'title': 'Episode 5',
        'season': 1,
        'episode': 5,
      };

      expect(transaction.previous['episode'], 4);
      transaction.commit(nextMetadata);
      expect(transaction.committed?['episode'], 5);
      expect(transaction.hasCommitted, isTrue);
    });
  });

  group('Autoplay duplicate-ended guard', () {
    test('ended -> next accepts first sequence only', () {
      final gate = CastEndedGate();
      expect(gate.accept(7), isTrue);
      expect(gate.accept(7), isFalse);
      expect(gate.accept(6), isFalse);
      expect(gate.accept(8), isTrue);
    });

    test('session restore sync prevents replaying an old ended event', () {
      final gate = CastEndedGate()..sync(22);
      expect(gate.accept(22), isFalse);
      expect(gate.accept(23), isTrue);
    });
  });

  group('Playback ownership and tracking authority', () {
    test('local ownership is authoritative initially', () {
      final owner = PlaybackOwnershipController();
      expect(owner.owner, PlaybackOwner.local);
      expect(owner.acceptsLocalTelemetry, isTrue);
      expect(owner.acceptsCastTelemetry, isFalse);
    });

    test('local -> Cast has no double authoritative telemetry', () {
      final owner = PlaybackOwnershipController();
      owner.beginCastTransfer();
      expect(owner.acceptsLocalTelemetry, isFalse);
      expect(owner.acceptsCastTelemetry, isFalse);
      owner.commitCast();
      expect(owner.acceptsLocalTelemetry, isFalse);
      expect(owner.acceptsCastTelemetry, isTrue);
    });

    test('Cast -> local has no double authoritative telemetry', () {
      final owner = PlaybackOwnershipController()
        ..beginCastTransfer()
        ..commitCast()
        ..beginLocalTransfer();
      expect(owner.acceptsLocalTelemetry, isFalse);
      expect(owner.acceptsCastTelemetry, isFalse);
      owner.commitLocal();
      expect(owner.acceptsLocalTelemetry, isTrue);
      expect(owner.acceptsCastTelemetry, isFalse);
    });

    test('failed local -> Cast transfer returns authority to local', () {
      final owner = PlaybackOwnershipController()..beginCastTransfer();
      owner.cancelCastTransfer();
      expect(owner.owner, PlaybackOwner.local);
      expect(owner.acceptsLocalTelemetry, isTrue);
    });
  });
}
