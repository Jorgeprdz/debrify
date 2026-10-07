import 'package:debrify/services/cast_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        'errorCode': 'CAST_SESSION_RESUME_FAILED',
      });
      expect(snapshot.state, CastPlaybackState.error);
      expect(snapshot.resumePosition, const Duration(seconds: 33));
      expect(snapshot.errorCode, 'CAST_SESSION_RESUME_FAILED');
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
