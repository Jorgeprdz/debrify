import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cast_phase2_policy.dart';

enum CastPlaybackState {
  disconnected,
  connecting,
  connected,
  playing,
  paused,
  ended,
  error;

  static CastPlaybackState fromWire(Object? value) {
    final wire = value?.toString().trim().toLowerCase();
    return CastPlaybackState.values.firstWhere(
      (state) => state.name == wire,
      orElse: () => CastPlaybackState.disconnected,
    );
  }
}

@immutable
class CastSnapshot {
  final bool available;
  final bool connected;
  final CastPlaybackState state;
  final String? deviceName;
  final Duration? position;
  final Duration? duration;
  final Duration? resumePosition;
  final bool? resumeShouldPlay;
  final String? errorCode;
  final List<CastRemoteTrack> availableAudioTracks;
  final List<CastRemoteTrack> availableSubtitleTracks;
  final String? selectedAudioTrack;
  final String? selectedSubtitleTrack;
  final int endedSequence;

  const CastSnapshot({
    this.available = false,
    this.connected = false,
    this.state = CastPlaybackState.disconnected,
    this.deviceName,
    this.position,
    this.duration,
    this.resumePosition,
    this.resumeShouldPlay,
    this.errorCode,
    this.availableAudioTracks = const <CastRemoteTrack>[],
    this.availableSubtitleTracks = const <CastRemoteTrack>[],
    this.selectedAudioTrack,
    this.selectedSubtitleTrack,
    this.endedSequence = 0,
  });

  factory CastSnapshot.fromMap(Map<Object?, Object?> raw) {
    Duration? durationValue(Object? value) {
      if (value is! num) return null;
      final milliseconds = value.toInt();
      if (milliseconds < 0) return null;
      return Duration(milliseconds: milliseconds);
    }

    String? stringValue(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    List<CastRemoteTrack> trackList(Object? value) {
      if (value is! List) return const <CastRemoteTrack>[];
      return value
          .whereType<Map>()
          .map(
            (track) => CastRemoteTrack.fromMap(
              Map<Object?, Object?>.from(track),
            ),
          )
          .where((track) => track.id.isNotEmpty)
          .toList(growable: false);
    }

    final audioTracks = trackList(raw['availableAudioTracks']);
    final subtitleTracks = trackList(raw['availableSubtitleTracks']);

    return CastSnapshot(
      available: raw['available'] == true,
      connected: raw['connected'] == true,
      state: CastPlaybackState.fromWire(raw['state']),
      deviceName: stringValue(raw['deviceName']),
      position: durationValue(raw['positionMs']),
      duration: durationValue(raw['durationMs']),
      resumePosition: durationValue(raw['resumePositionMs']),
      resumeShouldPlay: raw['resumeShouldPlay'] is bool
          ? raw['resumeShouldPlay'] as bool
          : null,
      errorCode: stringValue(raw['errorCode']),
      availableAudioTracks: audioTracks,
      availableSubtitleTracks: subtitleTracks,
      selectedAudioTrack: stringValue(raw['selectedAudioTrack']),
      selectedSubtitleTrack: stringValue(raw['selectedSubtitleTrack']),
      endedSequence: (raw['endedSequence'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class CastTextTrackRequest {
  final int id;
  final String url;
  final String language;
  final String label;
  final String mimeType;

  const CastTextTrackRequest({
    required this.id,
    required this.url,
    required this.language,
    required this.label,
    this.mimeType = 'text/vtt',
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'url': url,
    'language': language,
    'label': label,
    'mimeType': mimeType,
  };
}

@immutable
class CastMediaRequest {
  final String url;
  final String? mimeType;
  final String? title;
  final String? subtitle;
  final String? seriesTitle;
  final int? season;
  final int? episode;
  final String? posterUrl;
  final String? backdropUrl;
  final Duration? position;
  final Duration? duration;
  final Map<String, String> headers;
  final List<CastTextTrackRequest> textTracks;
  final bool autoplay;
  final bool isLive;

  const CastMediaRequest({
    required this.url,
    this.mimeType,
    this.title,
    this.subtitle,
    this.seriesTitle,
    this.season,
    this.episode,
    this.posterUrl,
    this.backdropUrl,
    this.position,
    this.duration,
    this.headers = const <String, String>{},
    this.textTracks = const <CastTextTrackRequest>[],
    this.autoplay = true,
    this.isLive = false,
  });

  CastMediaRequest copyWith({
    String? url,
    String? mimeType,
    String? title,
    String? subtitle,
    String? seriesTitle,
    int? season,
    int? episode,
    String? posterUrl,
    String? backdropUrl,
    Duration? position,
    Duration? duration,
    Map<String, String>? headers,
    List<CastTextTrackRequest>? textTracks,
    bool? autoplay,
    bool? isLive,
  }) => CastMediaRequest(
    url: url ?? this.url,
    mimeType: mimeType ?? this.mimeType,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    seriesTitle: seriesTitle ?? this.seriesTitle,
    season: season ?? this.season,
    episode: episode ?? this.episode,
    posterUrl: posterUrl ?? this.posterUrl,
    backdropUrl: backdropUrl ?? this.backdropUrl,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    headers: headers ?? this.headers,
    textTracks: textTracks ?? this.textTracks,
    autoplay: autoplay ?? this.autoplay,
    isLive: isLive ?? this.isLive,
  );

  bool get isDirectHttpUrl => isDirectHttpMediaUrl(url);
  bool get hasUnsupportedHeaders =>
      headers.entries.any((entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty);

  Map<String, Object?> toMap() => <String, Object?>{
    'url': url,
    if (mimeType?.trim().isNotEmpty == true) 'mimeType': mimeType!.trim(),
    if (title?.trim().isNotEmpty == true) 'title': title!.trim(),
    if (subtitle?.trim().isNotEmpty == true) 'subtitle': subtitle!.trim(),
    if (seriesTitle?.trim().isNotEmpty == true)
      'seriesTitle': seriesTitle!.trim(),
    if (season != null) 'season': season,
    if (episode != null) 'episode': episode,
    if (posterUrl?.trim().isNotEmpty == true) 'posterUrl': posterUrl!.trim(),
    if (backdropUrl?.trim().isNotEmpty == true)
      'backdropUrl': backdropUrl!.trim(),
    if (position != null && !position!.isNegative)
      'positionMs': position!.inMilliseconds,
    if (duration != null && !duration!.isNegative)
      'durationMs': duration!.inMilliseconds,
    if (headers.isNotEmpty) 'headers': Map<String, String>.from(headers),
    if (textTracks.isNotEmpty)
      'textTracks': textTracks.map((track) => track.toMap()).toList(growable: false),
    'autoplay': autoplay,
    'isLive': isLive,
  };

  static bool isDirectHttpMediaUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static String? inferMimeType(String url, {String? fallbackName}) {
    String candidate = Uri.tryParse(url)?.path ?? url;
    if (!candidate.contains('.') && fallbackName != null) {
      candidate = fallbackName;
    }
    final lower = candidate.split('?').first.toLowerCase();
    if (lower.endsWith('.m3u8')) return 'application/x-mpegURL';
    if (lower.endsWith('.mpd')) return 'application/dash+xml';
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    return null;
  }
}

class CastException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const CastException(this.code, this.message, [this.details]);

  factory CastException.fromPlatform(PlatformException error) => CastException(
    error.code,
    error.message ?? 'Google Cast operation failed.',
    error.details,
  );

  @override
  String toString() => 'CastException($code): $message';
}

class CastService extends ChangeNotifier {
  CastService._();

  static final CastService instance = CastService._();

  static const MethodChannel _method = MethodChannel('com.debrify.app/cast');
  static const EventChannel _events = EventChannel(
    'com.debrify.app/cast_events',
  );

  CastSnapshot _snapshot = const CastSnapshot();
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  Future<void>? _initializing;
  String? sessionAudioLanguage;
  String? sessionSubtitleLanguage;
  bool sessionSubtitlesDisabled = false;

  CastSnapshot get snapshot => _snapshot;
  bool get available => _snapshot.available;
  bool get connected => _snapshot.connected;
  CastPlaybackState get state => _snapshot.state;
  String? get deviceName => _snapshot.deviceName;
  Duration? get position => _snapshot.position;
  Duration? get duration => _snapshot.duration;
  List<CastRemoteTrack> get availableAudioTracks =>
      _snapshot.availableAudioTracks;
  List<CastRemoteTrack> get availableSubtitleTracks =>
      _snapshot.availableSubtitleTracks;
  String? get selectedAudioTrack => _snapshot.selectedAudioTrack;
  String? get selectedSubtitleTrack => _snapshot.selectedSubtitleTrack;
  int get endedSequence => _snapshot.endedSequence;

  Future<void> initialize() {
    if (_initialized || !Platform.isAndroid) {
      _initialized = true;
      return Future<void>.value();
    }
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;

    final future = _initializeAndroid();
    _initializing = future;
    return future.whenComplete(() {
      if (identical(_initializing, future)) _initializing = null;
    });
  }

  Future<void> _initializeAndroid() async {
    _eventSubscription ??= _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _applySnapshot(
            CastSnapshot.fromMap(Map<Object?, Object?>.from(event)),
          );
        }
      },
      onError: (Object error) {
        _applySnapshot(
          CastSnapshot(
            available: _snapshot.available,
            connected: _snapshot.connected,
            state: CastPlaybackState.error,
            deviceName: _snapshot.deviceName,
            position: _snapshot.position,
            duration: _snapshot.duration,
            resumePosition: _snapshot.resumePosition,
            resumeShouldPlay: _snapshot.resumeShouldPlay,
            availableAudioTracks: _snapshot.availableAudioTracks,
            availableSubtitleTracks: _snapshot.availableSubtitleTracks,
            selectedAudioTrack: _snapshot.selectedAudioTrack,
            selectedSubtitleTrack: _snapshot.selectedSubtitleTrack,
            endedSequence: _snapshot.endedSequence,
            errorCode: error is PlatformException
                ? error.code
                : 'CAST_EVENT_ERROR',
          ),
        );
      },
    );

    try {
      final state = await _method.invokeMapMethod<Object?, Object?>('getState');
      if (state != null) {
        _applySnapshot(CastSnapshot.fromMap(state));
      } else {
        final available =
            await _method.invokeMethod<bool>('isCastAvailable') ?? false;
        _applySnapshot(CastSnapshot(available: available));
      }
    } on PlatformException catch (error) {
      _applySnapshot(
        CastSnapshot(
          state: CastPlaybackState.error,
          errorCode: error.code,
        ),
      );
    } finally {
      _initialized = true;
    }
  }

  Future<bool> connect() async {
    await initialize();
    if (!Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('openCastDialog') ?? false;
    } on PlatformException catch (error) {
      throw CastException.fromPlatform(error);
    }
  }

  Future<CastSnapshot> load(CastMediaRequest request) async {
    await initialize();
    if (!request.isDirectHttpUrl) {
      throw const CastException(
        'CAST_INVALID_URL',
        'Google Cast requires a direct HTTP or HTTPS media URL.',
      );
    }
    if (request.hasUnsupportedHeaders) {
      throw const CastException(
        'CAST_UNSUPPORTED_HEADERS',
        'This stream requires HTTP headers that the Default Media Receiver cannot safely receive.',
      );
    }
    return _invokeSnapshot('loadMedia', request.toMap());
  }

  Future<CastSnapshot> play() => _invokeSnapshot('play');
  Future<CastSnapshot> pause() => _invokeSnapshot('pause');

  Future<CastSnapshot> seek(Duration position) {
    if (position.isNegative) {
      throw const CastException(
        'CAST_BAD_SEEK',
        'Cast seek position must be non-negative.',
      );
    }
    return _invokeSnapshot(
      'seek',
      <String, Object?>{'positionMs': position.inMilliseconds},
    );
  }

  Future<CastSnapshot> stop() => _invokeSnapshot('stop');

  Future<CastSnapshot> selectAudioTrack(String trackId) =>
      _invokeSnapshot(
        'selectAudioTrack',
        <String, Object?>{'trackId': trackId},
      );

  Future<CastSnapshot> selectSubtitleTrack(String trackId) =>
      _invokeSnapshot(
        'selectSubtitleTrack',
        <String, Object?>{'trackId': trackId},
      );

  Future<CastSnapshot> disableSubtitles() =>
      _invokeSnapshot('disableSubtitles');

  void rememberAudioLanguage(String? language) {
    final value = language?.trim();
    sessionAudioLanguage = value == null || value.isEmpty ? null : value;
  }

  void rememberSubtitleLanguage(String? language) {
    final value = language?.trim();
    sessionSubtitleLanguage = value == null || value.isEmpty ? null : value;
    sessionSubtitlesDisabled = false;
  }

  void rememberSubtitlesDisabled() {
    sessionSubtitleLanguage = null;
    sessionSubtitlesDisabled = true;
  }

  void restoreSessionTrackIntent(CastSnapshot snapshot) {
    if (sessionAudioLanguage == null && snapshot.selectedAudioTrack != null) {
      for (final track in snapshot.availableAudioTracks) {
        if (track.id == snapshot.selectedAudioTrack) {
          rememberAudioLanguage(track.language ?? track.label);
          break;
        }
      }
    }

    if (!sessionSubtitlesDisabled && sessionSubtitleLanguage == null) {
      final selectedId = snapshot.selectedSubtitleTrack;
      if (selectedId != null) {
        for (final track in snapshot.availableSubtitleTracks) {
          if (track.id == selectedId) {
            rememberSubtitleLanguage(track.language ?? track.label);
            break;
          }
        }
      } else if (snapshot.availableSubtitleTracks.isNotEmpty) {
        rememberSubtitlesDisabled();
      }
    }
  }

  void clearSessionTrackIntent() {
    sessionAudioLanguage = null;
    sessionSubtitleLanguage = null;
    sessionSubtitlesDisabled = false;
  }

  Future<CastSnapshot> disconnect() async {
    final snapshot = await _invokeSnapshot('disconnect');
    clearSessionTrackIntent();
    return snapshot;
  }

  Future<CastSnapshot> refresh() => _invokeSnapshot('getState');

  Future<CastSnapshot> _invokeSnapshot(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    await initialize();
    if (!Platform.isAndroid) return _snapshot;
    try {
      final raw = await _method.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
      if (raw != null) {
        final next = CastSnapshot.fromMap(raw);
        _applySnapshot(next);
        return next;
      }
      return _snapshot;
    } on PlatformException catch (error) {
      throw CastException.fromPlatform(error);
    }
  }

  void _applySnapshot(CastSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }

  @visibleForTesting
  static CastSnapshot parseSnapshot(Map<Object?, Object?> raw) =>
      CastSnapshot.fromMap(raw);
}
