import 'package:debrify/services/cast_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cast load snapshot identity', () {
    test('parses actual media identity and duration', () {
      final snap = CastService.parseSnapshot(<Object?, Object?>{
        'mediaContentId': 'https://example.test/next.mp4',
        'mediaSessionId': 42, 'durationMs': 75000,
      });
      expect(snap.mediaContentId, 'https://example.test/next.mp4');
      expect(snap.mediaSessionId, 42);
      expect(snap.duration, const Duration(seconds: 75));
    });
    test('does not invent missing media identity', () {
      final snap = CastService.parseSnapshot(<Object?, Object?>{
        'durationMs': 75000,
      });
      expect(snap.mediaContentId, isNull);
      expect(snap.mediaSessionId, isNull);
    });
  });
  group('CastMediaRequest', () {
    test('serializes direct media request without optional metadata', () {
      const request = CastMediaRequest(
        url: 'https://cdn.example.test/movie.mp4?token=opaque',
        title: 'Movie',
        position: Duration(seconds: 42),
        duration: Duration(minutes: 100),
        autoplay: true,
      );

      final map = request.toMap();

      expect(map['url'], startsWith('https://cdn.example.test/movie.mp4'));
      expect(map['title'], 'Movie');
      expect(map['positionMs'], 42000);
      expect(map['durationMs'], 6000000);
      expect(map['autoplay'], isTrue);
      expect(map.containsKey('subtitle'), isFalse);
      expect(map.containsKey('posterUrl'), isFalse);
      expect(map.containsKey('headers'), isFalse);
    });

    test('infers priority Cast MIME types', () {
      expect(
        CastMediaRequest.inferMimeType('https://example.test/master.m3u8'),
        'application/x-mpegURL',
      );
      expect(
        CastMediaRequest.inferMimeType('https://example.test/manifest.mpd'),
        'application/dash+xml',
      );
      expect(
        CastMediaRequest.inferMimeType('https://example.test/video.mp4'),
        'video/mp4',
      );
      expect(
        CastMediaRequest.inferMimeType(
          'https://example.test/download/123',
          fallbackName: 'Episode.S01E01.mp4',
        ),
        'video/mp4',
      );
    });

    test('rejects non-http media URLs', () {
      expect(
        CastMediaRequest.isDirectHttpMediaUrl('magnet:?xt=urn:btih:123'),
        isFalse,
      );
      expect(
        CastMediaRequest.isDirectHttpMediaUrl('file:///storage/movie.mp4'),
        isFalse,
      );
      expect(
        CastMediaRequest.isDirectHttpMediaUrl('https://media.example.test/v'),
        isTrue,
      );
    });

    test('classifies active HTTP headers as unsupported for default receiver', () {
      const request = CastMediaRequest(
        url: 'https://media.example.test/video.mp4',
        headers: <String, String>{'Authorization': 'redacted-for-test'},
      );
      expect(request.hasUnsupportedHeaders, isTrue);
    });

    test('serializes receiver-reachable WebVTT text tracks', () {
      const request = CastMediaRequest(
        url: 'https://media.example.test/movie.mp4',
        textTracks: <CastTextTrackRequest>[
          CastTextTrackRequest(
            id: 1001,
            url: 'https://subs.example.test/es.vtt',
            language: 'es',
            label: 'Spanish',
          ),
        ],
      );

      final map = request.toMap();
      final tracks = map['textTracks'] as List<Object?>;
      final track = tracks.single as Map<String, Object?>;
      expect(track['id'], 1001);
      expect(track['url'], 'https://subs.example.test/es.vtt');
      expect(track['language'], 'es');
      expect(track['mimeType'], 'text/vtt');
    });

    test('serializes next-episode metadata from zero without stale position', () {
      const request = CastMediaRequest(
        url: 'https://media.example.test/show/s02e04.m3u8',
        title: 'Episode Four',
        seriesTitle: 'Example Show',
        season: 2,
        episode: 4,
        position: Duration.zero,
        autoplay: true,
      );

      final map = request.toMap();
      expect(map['title'], 'Episode Four');
      expect(map['seriesTitle'], 'Example Show');
      expect(map['season'], 2);
      expect(map['episode'], 4);
      expect(map['positionMs'], 0);
      expect(map['autoplay'], isTrue);
    });

    test('serializes next-episode metadata from zero position', () {
      const request = CastMediaRequest(
        url: 'https://media.example.test/show/s02e04.m3u8',
        title: 'Episode Four',
        seriesTitle: 'Example Show',
        season: 2,
        episode: 4,
        position: Duration.zero,
        autoplay: true,
      );
      final map = request.toMap();
      expect(map['title'], 'Episode Four');
      expect(map['seriesTitle'], 'Example Show');
      expect(map['season'], 2);
      expect(map['episode'], 4);
      expect(map['positionMs'], 0);
    });

    test('omits unknown position and duration', () {
      const request = CastMediaRequest(
        url: 'https://media.example.test/live.m3u8',
        isLive: true,
      );
      final map = request.toMap();
      expect(map.containsKey('positionMs'), isFalse);
      expect(map.containsKey('durationMs'), isFalse);
    });
  });

  group('Cast session language intent', () {
    final service = CastService.instance;

    tearDown(service.clearSessionTrackIntent);

    test('stores language intent rather than ephemeral receiver ids', () {
      service.rememberAudioLanguage('eng');
      service.rememberSubtitleLanguage('es-MX');

      expect(service.sessionAudioLanguage, 'eng');
      expect(service.sessionSubtitleLanguage, 'es-MX');
      expect(service.sessionSubtitlesDisabled, isFalse);
    });

    test('explicit subtitle off is session scoped and wins', () {
      service.rememberSubtitleLanguage('es-419');
      service.rememberSubtitlesDisabled();

      expect(service.sessionSubtitleLanguage, isNull);
      expect(service.sessionSubtitlesDisabled, isTrue);

      service.clearSessionTrackIntent();
      expect(service.sessionSubtitlesDisabled, isFalse);
    });
  });

  group('Cast session track intent restore', () {
    test('restores manual language intent from receiver-selected tracks', () {
      final service = CastService.instance;
      service.clearSessionTrackIntent();
      service.restoreSessionTrackIntent(
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'playing',
          'connected': true,
          'availableAudioTracks': <Object?>[
            <Object?, Object?>{
              'id': '71',
              'type': 'audio',
              'language': 'eng',
              'selected': true,
            },
          ],
          'availableSubtitleTracks': <Object?>[
            <Object?, Object?>{
              'id': '81',
              'type': 'subtitle',
              'language': 'es-MX',
              'selected': true,
            },
          ],
          'selectedAudioTrack': '71',
          'selectedSubtitleTrack': '81',
        }),
      );

      expect(service.sessionAudioLanguage, 'eng');
      expect(service.sessionSubtitleLanguage, 'es-MX');
      expect(service.sessionSubtitlesDisabled, isFalse);
      service.clearSessionTrackIntent();
    });

    test('restored receiver subtitles-off state wins over stored default', () {
      final service = CastService.instance;
      service.clearSessionTrackIntent();
      service.restoreSessionTrackIntent(
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'playing',
          'connected': true,
          'availableSubtitleTracks': <Object?>[
            <Object?, Object?>{
              'id': '91',
              'type': 'subtitle',
              'language': 'spa',
              'selected': false,
            },
          ],
          'selectedSubtitleTrack': null,
        }),
      );

      expect(service.sessionSubtitleLanguage, isNull);
      expect(service.sessionSubtitlesDisabled, isTrue);
      service.clearSessionTrackIntent();
    });
  });

  group('CastSnapshot', () {
    test('tracks disconnected -> connecting -> connected states', () {
      final states = <CastPlaybackState>[
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'disconnected',
        }).state,
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'connecting',
        }).state,
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'connected',
          'connected': true,
        }).state,
      ];
      expect(
        states,
        <CastPlaybackState>[
          CastPlaybackState.disconnected,
          CastPlaybackState.connecting,
          CastPlaybackState.connected,
        ],
      );
    });

    test('represents Cast unavailable without inventing a session', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'available': false,
        'connected': false,
        'state': 'disconnected',
      });
      expect(snapshot.available, isFalse);
      expect(snapshot.connected, isFalse);
    });

    test('restores final remote position after disconnect', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'disconnected',
        'connected': false,
        'resumePositionMs': 123456,
        'resumeShouldPlay': true,
      });
      expect(snapshot.resumePosition, const Duration(milliseconds: 123456));
      expect(snapshot.resumeShouldPlay, isTrue);
    });

    test('keeps pause intent when remote session ends', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'disconnected',
        'resumePositionMs': 9000,
        'resumeShouldPlay': false,
      });
      expect(snapshot.resumeShouldPlay, isFalse);
    });

    test('represents unexpected session loss as error with recoverable position', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'error',
        'connected': false,
        'resumePositionMs': 33000,
        'errorCode': 'CAST_SESSION_LOST',
      });
      expect(snapshot.state, CastPlaybackState.error);
      expect(snapshot.resumePosition, const Duration(seconds: 33));
      expect(snapshot.errorCode, 'CAST_SESSION_LOST');
    });

    test('parses remote audio/subtitle tracks and selected ids', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'playing',
        'connected': true,
        'availableAudioTracks': <Object?>[
          <Object?, Object?>{
            'id': '41',
            'type': 'audio',
            'language': 'eng',
            'label': 'English',
            'selected': true,
          },
        ],
        'availableSubtitleTracks': <Object?>[
          <Object?, Object?>{
            'id': '51',
            'type': 'subtitle',
            'language': 'es-MX',
            'label': 'Español',
            'mimeType': 'text/vtt',
            'selected': true,
          },
        ],
        'selectedAudioTrack': '41',
        'selectedSubtitleTrack': '51',
        'endedSequence': 9,
      });

      expect(snapshot.availableAudioTracks.single.id, '41');
      expect(snapshot.availableAudioTracks.single.selected, isTrue);
      expect(snapshot.availableSubtitleTracks.single.language, 'es-MX');
      expect(snapshot.availableSubtitleTracks.single.mimeType, 'text/vtt');
      expect(snapshot.selectedAudioTrack, '41');
      expect(snapshot.selectedSubtitleTrack, '51');
      expect(snapshot.endedSequence, 9);
    });

    test('represents remote ended state with monotonic sequence', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'ended',
        'connected': true,
        'positionMs': 1800000,
        'durationMs': 1800000,
        'endedSequence': 12,
      });
      expect(snapshot.state, CastPlaybackState.ended);
      expect(snapshot.endedSequence, 12);
      expect(snapshot.position, const Duration(minutes: 30));
    });

    test('preserves playing and paused remote status', () {
      expect(
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'playing',
          'connected': true,
        }).state,
        CastPlaybackState.playing,
      );
      expect(
        CastService.parseSnapshot(const <Object?, Object?>{
          'state': 'paused',
          'connected': true,
        }).state,
        CastPlaybackState.paused,
      );
    });

    test('treats negative remote position/duration as unknown', () {
      final snapshot = CastService.parseSnapshot(const <Object?, Object?>{
        'state': 'connected',
        'positionMs': -1,
        'durationMs': -1,
      });
      expect(snapshot.position, isNull);
      expect(snapshot.duration, isNull);
    });
  });
}
