import '../screens/video_player/utils/language_mapping.dart';

enum PlaybackOwner {
  local,
  transferringToCast,
  cast,
  transferringToLocal,
}

class PlaybackOwnershipController {
  PlaybackOwner _owner = PlaybackOwner.local;

  PlaybackOwner get owner => _owner;
  bool get isLocal => _owner == PlaybackOwner.local;
  bool get isCast => _owner == PlaybackOwner.cast;
  bool get acceptsLocalTelemetry => _owner == PlaybackOwner.local;
  bool get acceptsCastTelemetry => _owner == PlaybackOwner.cast;

  void beginCastTransfer() {
    if (_owner == PlaybackOwner.local) {
      _owner = PlaybackOwner.transferringToCast;
    }
  }

  void commitCast() {
    if (_owner == PlaybackOwner.transferringToCast ||
        _owner == PlaybackOwner.cast) {
      _owner = PlaybackOwner.cast;
    }
  }

  void cancelCastTransfer() {
    if (_owner == PlaybackOwner.transferringToCast) {
      _owner = PlaybackOwner.local;
    }
  }

  void beginLocalTransfer() {
    if (_owner == PlaybackOwner.cast) {
      _owner = PlaybackOwner.transferringToLocal;
    }
  }

  void commitLocal() {
    if (_owner == PlaybackOwner.transferringToLocal ||
        _owner == PlaybackOwner.local) {
      _owner = PlaybackOwner.local;
    }
  }

  void resetLocal() => _owner = PlaybackOwner.local;
}

class CastEndedGate {
  int _lastAccepted = 0;

  int get lastAccepted => _lastAccepted;

  void sync(int sequence) {
    if (sequence > _lastAccepted) _lastAccepted = sequence;
  }

  bool accept(int sequence) {
    if (sequence <= _lastAccepted) return false;
    _lastAccepted = sequence;
    return true;
  }
}

class CastSwitchTransaction<T> {
  final T previous;
  final Duration position;
  final bool wasPlaying;
  T? committed;

  CastSwitchTransaction({
    required this.previous,
    required this.position,
    required this.wasPlaying,
  });

  bool get hasCommitted => committed != null;

  void commit(T value) {
    committed = value;
  }

  T rollback() {
    committed = null;
    return previous;
  }
}

enum CastRemoteTrackType { audio, subtitle, video, unknown }

class CastRemoteTrack {
  final String id;
  final CastRemoteTrackType type;
  final String? language;
  final String? label;
  final String? mimeType;
  final String? codec;
  final bool selected;

  const CastRemoteTrack({
    required this.id,
    required this.type,
    this.language,
    this.label,
    this.mimeType,
    this.codec,
    this.selected = false,
  });

  factory CastRemoteTrack.fromMap(Map<Object?, Object?> raw) {
    final type = switch (raw['type']?.toString()) {
      'audio' => CastRemoteTrackType.audio,
      'subtitle' || 'text' => CastRemoteTrackType.subtitle,
      'video' => CastRemoteTrackType.video,
      _ => CastRemoteTrackType.unknown,
    };
    String? clean(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return CastRemoteTrack(
      id: raw['id']?.toString() ?? '',
      type: type,
      language: clean(raw['language']),
      label: clean(raw['label']),
      mimeType: clean(raw['mimeType']),
      codec: clean(raw['codec']),
      selected: raw['selected'] == true,
    );
  }

  String get displayLabel {
    final explicit = label?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final pretty = LanguageMapper.niceLanguage(language);
    if (pretty.isNotEmpty) return pretty;
    return type == CastRemoteTrackType.audio ? 'Audio' : 'Subtitles';
  }
}

class CastLanguagePolicy {
  static String _normalizeTag(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll('_', '-');

  static CastRemoteTrack? _exact(
    Iterable<CastRemoteTrack> tracks,
    String? language,
  ) {
    final target = _normalizeTag(language);
    if (target.isEmpty) return null;
    for (final track in tracks) {
      if (_normalizeTag(track.language) == target ||
          _normalizeTag(track.label) == target) {
        return track;
      }
    }
    return null;
  }

  static CastRemoteTrack? _family(
    Iterable<CastRemoteTrack> tracks,
    String? language,
  ) {
    if (language == null || language.trim().isEmpty) return null;
    for (final track in tracks) {
      if (LanguageMapper.matchesLanguage(language, track.language) ||
          LanguageMapper.matchesLanguage(language, track.label)) {
        return track;
      }
    }
    return null;
  }

  static CastRemoteTrack? _match(
    Iterable<CastRemoteTrack> tracks,
    String? language,
  ) =>
      _exact(tracks, language) ?? _family(tracks, language);

  static CastRemoteTrack? chooseAudio({
    required Iterable<CastRemoteTrack> tracks,
    String? manualLanguage,
    String? preferredLanguage,
  }) {
    final audio = tracks
        .where((track) => track.type == CastRemoteTrackType.audio)
        .toList(growable: false);
    if (audio.isEmpty) return null;

    CastRemoteTrack? selected;
    for (final track in audio) {
      if (track.selected) {
        selected = track;
        break;
      }
    }
    return _match(audio, manualLanguage) ??
        _match(audio, preferredLanguage) ??
        _match(audio, 'en') ??
        selected ??
        audio.first;
  }

  static CastRemoteTrack? chooseSubtitle({
    required Iterable<CastRemoteTrack> tracks,
    required bool explicitlyDisabled,
    String? manualLanguage,
    String? preferredLanguage,
  }) {
    if (explicitlyDisabled) return null;
    final subtitles = tracks
        .where((track) => track.type == CastRemoteTrackType.subtitle)
        .toList(growable: false);
    if (subtitles.isEmpty) return null;

    final manual = _match(subtitles, manualLanguage);
    if (manual != null) return manual;

    final preferredTag = _normalizeTag(preferredLanguage);
    final preferredIsGenericSpanish =
        preferredTag == 'es' ||
        preferredTag == 'spa' ||
        preferredTag == 'spanish' ||
        preferredTag == 'español' ||
        preferredTag == 'espanol';
    if (!preferredIsGenericSpanish) {
      final preferred = _match(subtitles, preferredLanguage);
      if (preferred != null) return preferred;
    }

    CastRemoteTrack? genericSpanish;
    CastRemoteTrack? latinAmericanSpanish;
    CastRemoteTrack? spainSpanish;
    for (final track in subtitles) {
      final raw = _normalizeTag(track.language);
      final canonical =
          LanguageMapper.canonicalLanguage(track.language) ??
          LanguageMapper.canonicalLanguage(track.label);
      if (canonical != 'es') continue;

      if (raw == 'es' || raw == 'spa' || !raw.contains('-')) {
        genericSpanish ??= track;
      } else if (raw == 'es-es') {
        spainSpanish ??= track;
      } else {
        // Regional Spanish other than es-ES is treated as Latin-American for
        // the default fallback. LanguageMapper remains the canonical family
        // matcher; this only resolves ordering inside the Spanish family.
        latinAmericanSpanish ??= track;
      }
    }

    CastRemoteTrack? selected;
    for (final track in subtitles) {
      if (track.selected) {
        selected = track;
        break;
      }
    }

    return genericSpanish ??
        latinAmericanSpanish ??
        spainSpanish ??
        _family(subtitles, 'es') ??
        selected;
  }
}

enum CastSourceCompatibilityKind {
  supported,
  unsupportedHeaders,
  unsupportedScheme,
  unsupportedContainer,
  unsupportedAudioVideoLayout,
  unknown,
}

class CastSourceCompatibility {
  final CastSourceCompatibilityKind kind;
  final String? reason;

  const CastSourceCompatibility(this.kind, [this.reason]);

  bool get canAttempt =>
      kind == CastSourceCompatibilityKind.supported ||
      kind == CastSourceCompatibilityKind.unknown;

  static CastSourceCompatibility classify({
    required String url,
    Map<String, String>? headers,
    String? separateAudioUrl,
  }) {
    if (separateAudioUrl?.trim().isNotEmpty == true) {
      return const CastSourceCompatibility(
        CastSourceCompatibilityKind.unsupportedAudioVideoLayout,
        'Separate audio/video URLs are not supported by the Default Media Receiver sender flow.',
      );
    }
    if (headers?.entries.any(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        ) ==
        true) {
      return const CastSourceCompatibility(
        CastSourceCompatibilityKind.unsupportedHeaders,
        'The stream requires request headers.',
      );
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const CastSourceCompatibility(
        CastSourceCompatibilityKind.unsupportedScheme,
        'Cast requires a receiver-reachable HTTP/HTTPS URL.',
      );
    }

    final path = uri.path.toLowerCase();
    if (path.endsWith('.mp4') ||
        path.endsWith('.m4v') ||
        path.endsWith('.webm') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.mpd') ||
        path.endsWith('.mp3') ||
        path.endsWith('.m4a')) {
      return const CastSourceCompatibility(
        CastSourceCompatibilityKind.supported,
      );
    }
    return const CastSourceCompatibility(
      CastSourceCompatibilityKind.unknown,
      'Container/codec compatibility must be decided by the receiver.',
    );
  }
}

enum CastSubtitleSupportKind {
  supported,
  unsupportedFormat,
  unreachable,
  requiresConversion,
}

class CastSubtitleSupport {
  final CastSubtitleSupportKind kind;
  final String? mimeType;

  const CastSubtitleSupport(this.kind, [this.mimeType]);

  bool get supported => kind == CastSubtitleSupportKind.supported;

  static CastSubtitleSupport classify(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const CastSubtitleSupport(CastSubtitleSupportKind.unreachable);
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.vtt')) {
      return const CastSubtitleSupport(
        CastSubtitleSupportKind.supported,
        'text/vtt',
      );
    }
    if (path.endsWith('.srt')) {
      return const CastSubtitleSupport(
        CastSubtitleSupportKind.requiresConversion,
      );
    }
    if (path.endsWith('.ass') ||
        path.endsWith('.ssa') ||
        path.endsWith('.sub') ||
        path.endsWith('.idx')) {
      return const CastSubtitleSupport(
        CastSubtitleSupportKind.unsupportedFormat,
      );
    }
    return const CastSubtitleSupport(
      CastSubtitleSupportKind.unsupportedFormat,
    );
  }
}
