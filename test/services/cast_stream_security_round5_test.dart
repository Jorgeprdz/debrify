// Round 5: AUTHORED / NOT RUN. Application test execution is prohibited.
import 'dart:async';

import 'package:debrify/services/cast_phase2_policy.dart';
import 'package:debrify/services/cast_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTransport implements CastTransport {
  final methods = <String>[];
  final arguments = <Map<String, Object?>?>[];
  @override
  Stream<Object?> get events => const Stream<Object?>.empty();
  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? value]) async {
    methods.add(method);
    arguments.add(value);
    if (method == 'isCastAvailable') return true;
    return <Object?, Object?>{
      'available': true,
      'connected': true,
      'state': 'playing',
      'bridgeInstanceId': 'security-bridge',
      'sessionEpoch': 'security-session',
      'snapshotRevision': methods.length,
      'mediaContentId': 'https://media.example/previous.mp4',
      'mediaSessionId': 12,
    };
  }
}

void main() {
  test('P44 split audio/video stream cannot masquerade as direct receiver media', () {
    const video = 'https://media.example/video.mpd?token=video';
    const audio = 'https://media.example/audio.m4a?token=audio';
    final split = CastSourceCompatibility.classify(
      url: video, separateAudioUrl: audio);
    expect(split.kind, CastSourceCompatibilityKind.unsupportedAudioVideoLayout);
    expect(split.canAttempt, isFalse);
    expect(split.reason, contains('Separate audio/video'));
    final multiplexed = CastSourceCompatibility.classify(url: video);
    expect(multiplexed.kind, CastSourceCompatibilityKind.supported);
    expect(multiplexed.canAttempt, isTrue);
    final unknown = CastSourceCompatibility.classify(
      url: 'https://media.example/signed-stream?token=opaque');
    expect(unknown.kind, CastSourceCompatibilityKind.unknown);
    expect(unknown.canAttempt, isTrue);
  });

  test('P45 credential headers are rejected before any native LOAD transmission', () async {
    final transport = _RecordingTransport();
    final service = CastService(transport: transport, isAndroid: true);
    const request = CastMediaRequest(
      url: 'https://media.example/protected.mp4',
      headers: {'Authorization': 'Bearer regression-secret'},
    );
    await expectLater(service.load(request), throwsA(isA<CastException>()
      .having((error) => error.code, 'error code', 'CAST_UNSUPPORTED_HEADERS')));
    expect(transport.methods, isNot(contains('loadMedia')));
    expect(transport.arguments.any((value) =>
      value?.toString().contains('regression-secret') ?? false), isFalse);
    expect(service.snapshot.mediaContentId, 'https://media.example/previous.mp4');
    service.dispose();
  });
}
