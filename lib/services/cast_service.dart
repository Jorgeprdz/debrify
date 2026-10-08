import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cast_phase2_policy.dart';
import 'cast_load_coordinator.dart';

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
  final String? mediaContentId;
  final int? mediaSessionId;
  final String? sessionEpoch;
  final String? bridgeInstanceId;
  final bool receiverOperationBlocked;
  final int snapshotRevision;

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
    this.mediaContentId,
    this.mediaSessionId,
    this.sessionEpoch,
    this.bridgeInstanceId,
    this.receiverOperationBlocked = false,
    this.snapshotRevision = 0,
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
      mediaContentId: stringValue(raw['mediaContentId']),
      mediaSessionId: (raw['mediaSessionId'] as num?)?.toInt(),
      sessionEpoch: stringValue(raw['sessionEpoch']),
      bridgeInstanceId: stringValue(raw['bridgeInstanceId']),
      receiverOperationBlocked: raw['receiverOperationBlocked'] == true,
      snapshotRevision: (raw['snapshotRevision'] as num?)?.toInt() ?? 0,
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

/// The platform boundary is injectable; receiver authority stays in CastService.
abstract interface class CastTransport {
  Stream<Object?> get events;
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]);
}

class _ChannelCastTransport implements CastTransport {
  static const _method = MethodChannel('com.debrify.app/cast');
  static const _events = EventChannel('com.debrify.app/cast_events');

  @override
  Stream<Object?> get events => _events.receiveBroadcastStream();

  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]) =>
      _method.invokeMethod<Object?>(method, arguments);
}

class CastService extends ChangeNotifier {
  CastService({
    CastTransport? transport,
    bool? isAndroid,
    Duration callerTimeout = const Duration(seconds: 30),
  }) : _transport = transport ?? _ChannelCastTransport(),
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _navigationLoads = CastLoadCoordinator<CastSnapshot>(callerTimeout: callerTimeout) {
    _navigationLoads.onPhysicalStateChanged = () {
      if (!_disposed) notifyListeners();
    };
  }

  static final CastService instance = CastService();
  final CastTransport _transport;
  final bool _isAndroid;
  final CastLoadCoordinator<CastSnapshot> _navigationLoads;
  CastSnapshot _snapshot = const CastSnapshot();
  // Wire reality and the accepted tracking clock have separate authority.
  CastSnapshot _receiverSnapshot = const CastSnapshot();
  String? _acceptedContentId;
  int? _acceptedMediaSessionId;
  String? _acceptedSessionEpoch;
  final Set<String> _retiredSessionEpochs = <String>{};
  final Set<String> _retiredBridges = <String>{};
  final Map<String, int> _bridgeRevisions = <String, int>{};
  String? _currentBridge;
  String? _wireSessionEpoch;
  bool _receiverRecoveryRequired = false;
  bool _controlSnapshotsQuarantined = false;
  ({int generation, String? epoch, String? bridge})? _pendingStopAuthority;
  final Map<Object, ({String? epoch, bool Function() permitted})>
      _physicalControlAuthorities = <Object, ({String? epoch, bool Function() permitted})>{};
  bool _disposed = false;
  bool get receiverRecoveryRequired => _receiverRecoveryRequired;
  StreamSubscription<Object?>? _eventSubscription;
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
    if (_disposed || _initialized || !_isAndroid) {
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
    _eventSubscription ??= _transport.events.listen(
      (event) {
        if (event is Map) _applySnapshot(CastSnapshot.fromMap(Map<Object?, Object?>.from(event)));
      },
      onError: (Object error) {
        if (_disposed) return;
        // Stream errors are local observations, not receiver-session retirement.
        _snapshot = _copySnapshot(_snapshot,
          state: CastPlaybackState.error,
          errorCode: error is PlatformException ? error.code : 'CAST_EVENT_ERROR');
        notifyListeners();
      },
    );
    try {
      final raw = await _transport.invoke('getState');
      if (raw is Map) {
        _applySnapshot(CastSnapshot.fromMap(Map<Object?, Object?>.from(raw)));
      } else {
        final available = await _transport.invoke('isCastAvailable') == true;
        if (!_disposed) {
          _snapshot = CastSnapshot(available: available);
          notifyListeners();
        }
      }
    } on PlatformException catch (error) {
      if (!_disposed) {
        _snapshot = _copySnapshot(_snapshot, state: CastPlaybackState.error,
          errorCode: error.code);
        notifyListeners();
      }
    } finally {
      _initialized = true;
    }
  }

  Future<bool> connect() async {
    await initialize();
    if (_disposed || !_isAndroid) return false;
    try {
      return await _transport.invoke('openCastDialog') == true;
    } on PlatformException catch (error) {
      throw CastException.fromPlatform(error);
    }
  }

  /// Claim authority at user-intent entry, before any asynchronous provider.
  int beginNavigationIntent() {
    final ticket = _navigationLoads.beginIntent();
    if (_hasCurrentPhysicalControl) _quarantineControlSnapshots();
    return ticket;
  }
  bool isCurrentLoad(int generation) => _navigationLoads.isCurrent(generation);
  bool get hasLoadInFlight => _navigationLoads.hasInFlight ||
      _receiverSnapshot.receiverOperationBlocked;
  bool get receiverOperationBlocked => _navigationLoads.isBlockedOnReceiver ||
      _receiverSnapshot.receiverOperationBlocked ||
      (!_receiverSnapshot.connected && _receiverSnapshot.sessionEpoch != null);
  bool get receiverLoadBlocked => receiverOperationBlocked;

  void cancelNavigationLoads() {
    _navigationLoads.invalidate();
    if (_hasCurrentPhysicalControl) _quarantineControlSnapshots();
  }

  /// LOAD ACK confirms receiver acceptance/identity, NOT decoding/playback.
  /// No raw native LOAD result is applied to UI before authoritative commit.
  Future<CastLoadResult<CastSnapshot>> coordinatedLoad(
    CastMediaRequest request, {
    required int generation,
    required bool Function() permitted,
  }) async {
    await initialize();
    final expectedEpoch = _receiverSnapshot.sessionEpoch;
    final result = await _navigationLoads.submit(
      generation: generation,
      load: () => _loadNative(request, expectedEpoch: expectedEpoch),
      permitted: () => !_disposed && _receiverSnapshot.connected &&
          expectedEpoch != null && _receiverSnapshot.sessionEpoch == expectedEpoch &&
          !_receiverSnapshot.receiverOperationBlocked && permitted(),
      verify: (ack) => _loadAckMatches(ack, request.url, expectedEpoch) &&
          !_receiverRecoveryRequiredForAck(ack),
      onPhysicalResult: (ack, observedGeneration, logicalPending) {
        if (_disposed || _isRetiredSnapshot(ack) ||
            ack.bridgeInstanceId != _currentBridge || ack.sessionEpoch != expectedEpoch ||
            _receiverSnapshot.sessionEpoch != expectedEpoch) return;
        final uncommitted = !logicalPending || !isCurrentLoad(observedGeneration) ||
            !permitted() || ack.mediaContentId != request.url ||
            ack.mediaSessionId == null || ack.mediaSessionId! <= 0;
        // Capture physical reality even if this is the first delivered unblock
        // snapshot. A current ticket may have already logically timed out.
        _applySnapshot(ack, uncommittedPhysicalLoad: uncommitted);
        if (uncommitted) _markRecoveryIfDivergent(includeUnadopted: true);
      },
    );
    if (result.committed && isCurrentLoad(generation) &&
        permitted() && result.value != null && !_disposed) {
      final ack = result.value!;
      if (!_loadAckMatches(ack, request.url, expectedEpoch) ||
          _receiverRecoveryRequiredForAck(ack)) {
        _markRecoveryIfDivergent();
        return CastLoadResult<CastSnapshot>(CastLoadOutcome.rejected, generation,
          value: ack);
      }
      _acceptedContentId = request.url;
      _acceptedMediaSessionId = ack.mediaSessionId;
      _acceptedSessionEpoch = ack.sessionEpoch;
      _receiverRecoveryRequired = false;
      _controlSnapshotsQuarantined = false;
      _applySnapshot(ack, authoritativeLoad: true);
      return CastLoadResult<CastSnapshot>(CastLoadOutcome.committed, generation, value: _snapshot);
    } else if (result.committed) {
      _markRecoveryIfDivergent(includeUnadopted: true);
      return CastLoadResult<CastSnapshot>(isCurrentLoad(generation)
        ? CastLoadOutcome.cancelled : CastLoadOutcome.superseded, generation);
    } else {
      _markRecoveryIfDivergent();
    }
    return result;
  }

  bool _loadAckMatches(CastSnapshot ack, String contentId, String? epoch) =>
      !_disposed && ack.connected && epoch != null && ack.sessionEpoch == epoch &&
      ack.mediaContentId == contentId && ack.mediaSessionId != null &&
      ack.mediaSessionId! > 0 && !_isRetiredSnapshot(ack) &&
      ack.bridgeInstanceId == _currentBridge &&
      _receiverSnapshot.connected && _receiverSnapshot.sessionEpoch == epoch;

  bool _receiverRecoveryRequiredForAck(CastSnapshot ack) {
    final latest = _receiverSnapshot;
    // A newer matching provisional event can be adopted when its earlier ACK
    // arrives. A newer divergent receiver identity cannot be overridden by ACK.
    return latest.bridgeInstanceId == ack.bridgeInstanceId &&
        latest.snapshotRevision > ack.snapshotRevision &&
        (latest.mediaContentId != ack.mediaContentId ||
         latest.mediaSessionId != ack.mediaSessionId ||
         latest.sessionEpoch != ack.sessionEpoch);
  }

  /// Session adoption never sends LOAD. The caller must first refresh from
  /// the native receiver and match the exact current screen request.
  bool adoptVerifiedReceiverIdentity({
    required CastSnapshot fresh,
    required String expectedContentId,
    required int generation,
  }) {
    if (hasLoadInFlight || !isCurrentLoad(generation) ||
        !fresh.connected || fresh.sessionEpoch == null ||
        fresh.mediaSessionId == null || fresh.mediaSessionId! <= 0 ||
        fresh.mediaContentId != expectedContentId ||
        _isRetiredSnapshot(fresh) ||
        fresh.bridgeInstanceId != _receiverSnapshot.bridgeInstanceId ||
        fresh.snapshotRevision != _receiverSnapshot.snapshotRevision ||
        _receiverSnapshot.sessionEpoch != fresh.sessionEpoch ||
        _receiverSnapshot.mediaContentId != fresh.mediaContentId ||
        _receiverSnapshot.mediaSessionId != fresh.mediaSessionId) return false;
    _acceptedContentId = fresh.mediaContentId;
    _acceptedMediaSessionId = fresh.mediaSessionId;
    _acceptedSessionEpoch = fresh.sessionEpoch;
    _receiverRecoveryRequired = false;
    _controlSnapshotsQuarantined = false;
    _snapshot = fresh;
    notifyListeners();
    return true;
  }

  /// Phase 1 public API remains available but can no longer bypass the
  /// Phase 2 physical LOAD coordinator.
  Future<CastSnapshot> load(CastMediaRequest request) async {
    final generation = beginNavigationIntent();
    await initialize();
    _validateMediaRequest(request);
    if (!_isAndroid) return _snapshot;
    final outcome = await coordinatedLoad(
      request, generation: generation, permitted: () => true,
    );
    if (outcome.committed && outcome.value != null) return outcome.value!;
    final error = outcome.error;
    if (error is CastException) throw error;
    throw const CastException(
      'CAST_LOAD_FAILED', 'The requested Cast LOAD did not commit.',
    );
  }

  /// Only the serialized coordinator may invoke the platform LOAD channel.
  Future<CastSnapshot> _loadNative(CastMediaRequest request, {
    required String? expectedEpoch,
  }) async {
    // coordinatedLoad initialized before claiming physical exclusion. No
    // await may split its pre-dispatch ownership check from channel dispatch.
    _validateMediaRequest(request);
    try {
      final raw = await _transport.invoke('loadMedia', <String, Object?>{
        ...request.toMap(),
        'expectedSessionEpoch': expectedEpoch,
      });
      if (raw is! Map) {
        throw const CastException('CAST_LOAD_FAILED', 'Receiver returned no LOAD identity.');
      }
      return CastSnapshot.fromMap(Map<Object?, Object?>.from(raw));
    } on PlatformException catch (error) {
      throw CastException.fromPlatform(error);
    }
  }

  void _validateMediaRequest(CastMediaRequest request) {
    if (!request.isDirectHttpUrl) {
      throw const CastException('CAST_INVALID_URL',
        'Google Cast requires a direct HTTP or HTTPS media URL.');
    }
    if (request.hasUnsupportedHeaders) {
      throw const CastException('CAST_UNSUPPORTED_HEADERS',
        'This stream requires HTTP headers that the Default Media Receiver cannot safely receive.');
    }
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

  /// The native receiver validates the identity again just before dispatch.
  /// An already dispatched physical seek cannot be cancelled by Dart.
  Future<CastSnapshot?> seekForCommittedMedia(
    Duration position, {
    required int generation,
    required String? contentId,
    required int? mediaSessionId,
    required bool Function() permitted,
  }) async {
    if (position.isNegative) {
      throw const CastException('CAST_BAD_SEEK', 'Negative seek position.');
    }
    await initialize();
    final epoch = _acceptedSessionEpoch;
    bool validTarget() => !_disposed && connected && isCurrentLoad(generation) &&
        permitted() && !_receiverRecoveryRequired &&
        contentId != null && mediaSessionId != null && mediaSessionId > 0 &&
        epoch != null && _acceptedContentId == contentId &&
        _acceptedMediaSessionId == mediaSessionId && _acceptedSessionEpoch == epoch &&
        _receiverMatchesAccepted();
    if (!_isAndroid || !validTarget() || hasLoadInFlight) return null;
    final reply = await _navigationLoads.dispatchControl<CastSnapshot?>(
      generation: generation,
      permitted: validTarget,
      command: () => _runPhysicalControl(epoch: epoch, permitted: validTarget,
        command: () async {
        try {
          final raw = await _transport.invoke('seek', <String, Object?>{
            'positionMs': position.inMilliseconds,
            'expectedContentId': contentId,
            'expectedMediaSessionId': mediaSessionId,
            'expectedSessionEpoch': epoch,
          });
          return raw is Map ? CastSnapshot.fromMap(Map<Object?, Object?>.from(raw)) : null;
        } on PlatformException catch (error) {
          if (error.code == 'CAST_STALE_COMMAND') return null;
          throw CastException.fromPlatform(error);
        }
      }),
    );
    // No global mutation occurs inside the outstanding physical command.
    if (reply == null || !validTarget() ||
        reply.mediaContentId != contentId || reply.mediaSessionId != mediaSessionId ||
        reply.sessionEpoch != epoch || _isRetiredSnapshot(reply)) {
      if (_hasCurrentPhysicalControl) _quarantineControlSnapshots();
      return null;
    }
    _applySnapshot(reply);
    return _snapshot;
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
    cancelNavigationLoads();
    return _invokeSnapshot('disconnect');
  }

  Future<CastSnapshot> refresh() => _invokeSnapshot('getState');

  Future<CastSnapshot> _invokeSnapshot(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final generation = _navigationLoads.generation;
    await initialize();
    if (_disposed) throw const CastException('CAST_DISPOSED', 'Cast service is disposed.');
    if (!_isAndroid) return _snapshot;
    Future<CastSnapshot?> invokeNativeSnapshot(Map<String, Object?>? args) async {
      try {
        final raw = await _transport.invoke(method, args);
        return raw is Map ? CastSnapshot.fromMap(Map<Object?, Object?>.from(raw)) : null;
      } on PlatformException catch (error) {
        throw CastException.fromPlatform(error);
      }
    }
    if (method == 'getState' || method == 'disconnect') {
      final next = await invokeNativeSnapshot(arguments);
      if (next == null || !_applySnapshot(next)) return _receiverSnapshot;
      // A refresh returns fresh receiver reality even while accepted UI is frozen.
      return method == 'disconnect' || !next.connected ? _snapshot : next;
    }
    final epoch = _acceptedSessionEpoch;
    final contentId = _acceptedContentId;
    final mediaSessionId = _acceptedMediaSessionId;
    final bridge = _receiverSnapshot.bridgeInstanceId;
    bool permitted() => !_disposed && isCurrentLoad(generation) &&
        !_receiverRecoveryRequired && epoch != null && contentId != null &&
        mediaSessionId != null && _acceptedSessionEpoch == epoch &&
        _acceptedContentId == contentId && _acceptedMediaSessionId == mediaSessionId &&
        _receiverSnapshot.bridgeInstanceId == bridge &&
        (_receiverMatchesAccepted() ||
         (method == 'stop' && _currentStopMayUnload(_receiverSnapshot)));
    if (!permitted() || !_receiverMatchesAccepted() || hasLoadInFlight) {
      throw const CastException('CAST_COMMAND_SUPERSEDED',
        'Command target is no longer the committed receiver media.');
    }
    if (method == 'stop') {
      _pendingStopAuthority = (generation: generation, epoch: epoch, bridge: bridge);
    }
    try {
      final controlled = await _navigationLoads.dispatchControl<CastSnapshot?>(
        generation: generation,
        permitted: permitted,
        command: () => _runPhysicalControl(epoch: epoch, permitted: permitted,
          command: () => invokeNativeSnapshot(<String, Object?>{
            ...?arguments,
            'expectedSessionEpoch': epoch,
            'expectedContentId': contentId,
            'expectedMediaSessionId': mediaSessionId,
          })),
      );
      final identityMatches = controlled != null &&
          controlled.mediaContentId == contentId && controlled.mediaSessionId == mediaSessionId;
      final stopped = method == 'stop' && controlled != null &&
          _currentStopMayUnload(controlled);
      if (controlled == null || !permitted() || controlled.sessionEpoch != epoch ||
          controlled.bridgeInstanceId != bridge ||
          (!identityMatches && !stopped) || _isRetiredSnapshot(controlled)) {
        if (epoch != null && _receiverSnapshot.sessionEpoch == epoch &&
            _receiverSnapshot.bridgeInstanceId == bridge) {
          _quarantineControlSnapshots();
          if (controlled != null && !_isRetiredSnapshot(controlled) &&
              controlled.sessionEpoch == epoch && controlled.bridgeInstanceId == bridge) {
            _applySnapshot(controlled);
          }
        }
        throw const CastException('CAST_COMMAND_SUPERSEDED',
          'Command not committed after receiver ownership changed.');
      }
      if (method == 'stop') {
        // Google Cast STOP unloads content and invalidates its media session.
        // Only this still-owned exact-preflight transaction may accept unload.
        _acceptedContentId = null;
        _acceptedMediaSessionId = null;
        _acceptedSessionEpoch = null;
        _receiverRecoveryRequired = false;
        _controlSnapshotsQuarantined = false;
      }
      _applySnapshot(controlled, authoritativeLoad: method == 'stop');
      return _snapshot;
    } finally {
      if (_pendingStopAuthority?.generation == generation) _pendingStopAuthority = null;
    }
  }

  bool _isUnloadedSnapshot(CastSnapshot snapshot) => snapshot.connected &&
      snapshot.state == CastPlaybackState.connected &&
      (snapshot.mediaSessionId == null || snapshot.mediaSessionId! <= 0);

  bool _currentStopMayUnload(CastSnapshot snapshot) {
    final stop = _pendingStopAuthority;
    return stop != null && isCurrentLoad(stop.generation) &&
        !_controlSnapshotsQuarantined && snapshot.sessionEpoch == stop.epoch &&
        snapshot.bridgeInstanceId == stop.bridge && _isUnloadedSnapshot(snapshot) &&
        (snapshot.mediaContentId == null || snapshot.mediaContentId == _acceptedContentId);
  }

  Future<CastSnapshot?> _runPhysicalControl({
    required String? epoch,
    required bool Function() permitted,
    required Future<CastSnapshot?> Function() command,
  }) async {
    final token = Object();
    _physicalControlAuthorities[token] = (epoch: epoch, permitted: permitted);
    try {
      return await command();
    } finally {
      // MethodChannel and EventChannel can deliver the same old command in
      // either order. Preserve quarantine after physical ACK until fresh proof
      // explicitly restores receiver authority.
      try {
        if (!_disposed && epoch != null && _receiverSnapshot.sessionEpoch == epoch &&
            (!_permissionHolds(permitted) || _navigationLoads.isBlockedOnReceiver)) {
          _quarantineControlSnapshots();
        }
      } finally {
        _physicalControlAuthorities.remove(token);
      }
    }
  }

  bool _permissionHolds(bool Function() permitted) {
    try {
      return permitted();
    } catch (_) {
      return false;
    }
  }

  bool get _hasCurrentPhysicalControl => _physicalControlAuthorities.values.any(
      (authority) => authority.epoch == _receiverSnapshot.sessionEpoch);

  void _quarantineControlSnapshots() {
    if (_disposed || _receiverSnapshot.sessionEpoch == null) return;
    final changed = !_controlSnapshotsQuarantined || !_receiverRecoveryRequired;
    _controlSnapshotsQuarantined = true;
    _receiverRecoveryRequired = true;
    if (changed) notifyListeners();
  }

  bool _isRetiredSnapshot(CastSnapshot next) =>
      (next.bridgeInstanceId != null && _retiredBridges.contains(next.bridgeInstanceId)) ||
      (next.sessionEpoch != null && _retiredSessionEpochs.contains(next.sessionEpoch));

  bool _receiverMatchesAccepted() => _receiverSnapshot.connected &&
      _acceptedSessionEpoch != null && _acceptedContentId != null &&
      _acceptedMediaSessionId != null &&
      _receiverSnapshot.sessionEpoch == _acceptedSessionEpoch &&
      _receiverSnapshot.mediaContentId == _acceptedContentId &&
      _receiverSnapshot.mediaSessionId == _acceptedMediaSessionId;

  void _markRecoveryIfDivergent({bool includeUnadopted = false}) {
    if (_disposed || !_receiverSnapshot.connected ||
        (_acceptedContentId == null && !includeUnadopted) ||
        _receiverMatchesAccepted() || _receiverRecoveryRequired) return;
    _receiverRecoveryRequired = true;
    notifyListeners();
  }

  bool _applySnapshot(CastSnapshot next, {
    bool authoritativeLoad = false,
    bool uncommittedPhysicalLoad = false,
  }) {
    if (_disposed || _isRetiredSnapshot(next)) return false;
    final bridge = next.bridgeInstanceId;
    if (_currentBridge != null && bridge == null) return false;
    if (bridge != null) {
      final watermark = _bridgeRevisions[bridge] ?? -1;
      if (next.snapshotRevision < watermark) {
        if (!authoritativeLoad ||
            next.sessionEpoch != _receiverSnapshot.sessionEpoch ||
            next.mediaContentId != _receiverSnapshot.mediaContentId ||
            next.mediaSessionId != _receiverSnapshot.mediaSessionId) return false;
        next = _receiverSnapshot; // Newer provisional event, same accepted LOAD.
      }
      if (_currentBridge != bridge) {
        if (_currentBridge != null) _retiredBridges.add(_currentBridge!);
        _currentBridge = bridge;
      }
      _bridgeRevisions[bridge] = next.snapshotRevision;
    }
    final previousWire = _receiverSnapshot;
    final hadAcceptedIdentity = _acceptedContentId != null;
    final epochChanged = _wireSessionEpoch != next.sessionEpoch;
    if (epochChanged) {
      if (_wireSessionEpoch != null) _retiredSessionEpochs.add(_wireSessionEpoch!);
      _wireSessionEpoch = next.sessionEpoch;
      if (previousWire.connected || _acceptedSessionEpoch != null) {
        cancelNavigationLoads();
      }
      _acceptedContentId = null;
      _acceptedMediaSessionId = null;
      _acceptedSessionEpoch = null;
      _receiverRecoveryRequired = false;
      _controlSnapshotsQuarantined = false;
    }
    _receiverSnapshot = next;
    if (epochChanged && hadAcceptedIdentity && next.connected) {
      _receiverRecoveryRequired = true;
      _snapshot = _copySnapshot(next, preserveUnknownTimes: true,
        position: _snapshot.position, duration: _snapshot.duration,
        resumePosition: _snapshot.position ?? _snapshot.resumePosition,
        resumeShouldPlay: _snapshot.state == CastPlaybackState.playing ? true :
            _snapshot.state == CastPlaybackState.paused ? false : _snapshot.resumeShouldPlay);
      notifyListeners();
      return true;
    }
    if (!next.connected && next.sessionEpoch != null) {
      // Suspension/unconfirmed loss is not SDK retirement. Retain the accepted
      // identity and clock; no local ownership transfer is safe at this point.
      if (previousWire.connected) cancelNavigationLoads();
      _snapshot = _copySnapshot(next, state: CastPlaybackState.connecting,
        preserveUnknownTimes: true,
        position: _snapshot.position, duration: _snapshot.duration,
        resumePosition: _snapshot.position ?? _snapshot.resumePosition,
        resumeShouldPlay: _snapshot.state == CastPlaybackState.playing ? true :
            _snapshot.state == CastPlaybackState.paused ? false : _snapshot.resumeShouldPlay,
        mediaContentId: _snapshot.mediaContentId,
        mediaSessionId: _snapshot.mediaSessionId,
        receiverOperationBlocked: true);
      notifyListeners();
      return true;
    }
    if (!next.connected) {
      final preserveAcceptedResume = hadAcceptedIdentity ||
          ((previousWire.connected || previousWire.sessionEpoch != null) &&
           _snapshot.mediaContentId != null);
      if (previousWire.connected) cancelNavigationLoads();
      if (preserveAcceptedResume) {
        next = _copySnapshot(next, preserveUnknownTimes: true,
          position: _snapshot.position,
          duration: _snapshot.duration,
          resumePosition: _snapshot.position ?? _snapshot.resumePosition,
          resumeShouldPlay: _snapshot.state == CastPlaybackState.playing ? true :
              _snapshot.state == CastPlaybackState.paused ? false : _snapshot.resumeShouldPlay);
      }
      _acceptedContentId = null;
      _acceptedMediaSessionId = null;
      _acceptedSessionEpoch = null;
      _receiverRecoveryRequired = false;
      _controlSnapshotsQuarantined = false;
      clearSessionTrackIntent();
    } else if (!authoritativeLoad) {
      if (_physicalControlAuthorities.values.any((authority) =>
          authority.epoch == next.sessionEpoch && !_permissionHolds(authority.permitted)) ||
          (_hasCurrentPhysicalControl && _navigationLoads.isBlockedOnReceiver)) {
        _quarantineControlSnapshots();
      }
      if (_controlSnapshotsQuarantined ||
          (_receiverRecoveryRequired && _acceptedContentId == null)) {
        notifyListeners();
        return true;
      }
      if (uncommittedPhysicalLoad) {
        _markRecoveryIfDivergent(includeUnadopted: true);
      }
      if (_acceptedContentId != null && !_receiverMatchesAccepted()) {
        if (_currentStopMayUnload(next)) {
          notifyListeners();
          return true;
        }
        if (uncommittedPhysicalLoad || !_navigationLoads.hasInFlight) {
          _markRecoveryIfDivergent();
        }
        notifyListeners();
        return true; // Wire reality advances; the accepted clock stays frozen.
      }
      if (_acceptedContentId == null && _navigationLoads.hasInFlight &&
          next.mediaContentId != null && !epochChanged) {
        notifyListeners();
        return true;
      }
    }
    _snapshot = next;
    notifyListeners();
    return true;
  }

  CastSnapshot _copySnapshot(CastSnapshot source, {
    CastPlaybackState? state,
    Duration? position,
    Duration? duration,
    Duration? resumePosition,
    bool? resumeShouldPlay,
    String? errorCode,
    String? mediaContentId,
    int? mediaSessionId,
    bool? receiverOperationBlocked,
    bool preserveUnknownTimes = false,
  }) => CastSnapshot(
    available: source.available, connected: source.connected,
    state: state ?? source.state, deviceName: source.deviceName,
    position: preserveUnknownTimes ? position : position ?? source.position,
    duration: preserveUnknownTimes ? duration : duration ?? source.duration,
    resumePosition: preserveUnknownTimes ? resumePosition : resumePosition ?? source.resumePosition,
    resumeShouldPlay: preserveUnknownTimes ? resumeShouldPlay : resumeShouldPlay ?? source.resumeShouldPlay,
    errorCode: errorCode ?? source.errorCode,
    availableAudioTracks: source.availableAudioTracks,
    availableSubtitleTracks: source.availableSubtitleTracks,
    selectedAudioTrack: source.selectedAudioTrack,
    selectedSubtitleTrack: source.selectedSubtitleTrack,
    endedSequence: source.endedSequence,
    mediaContentId: mediaContentId ?? source.mediaContentId,
    mediaSessionId: mediaSessionId ?? source.mediaSessionId, sessionEpoch: source.sessionEpoch,
    bridgeInstanceId: source.bridgeInstanceId,
    receiverOperationBlocked: receiverOperationBlocked ?? source.receiverOperationBlocked,
    snapshotRevision: source.snapshotRevision,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _navigationLoads.dispose();
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    super.dispose();
  }

  @visibleForTesting
  static CastSnapshot parseSnapshot(Map<Object?, Object?> raw) =>
      CastSnapshot.fromMap(raw);
}
