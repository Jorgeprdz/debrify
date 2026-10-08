/// A screen effect belongs to one navigation and one physical receiver media.
/// Content URLs and media session IDs alone can be reused by a new session.
class CastPlayerMediaIdentity {
  final int generation;
  final String? bridgeInstanceId;
  final String? sessionEpoch;
  final int? mediaSessionId;
  final String? contentId;
  final int endedSequence;

  const CastPlayerMediaIdentity({required this.generation,
    required this.bridgeInstanceId, required this.sessionEpoch,
    required this.mediaSessionId, required this.contentId,
    required this.endedSequence});

  bool sameMediaAs(CastPlayerMediaIdentity other) =>
      generation == other.generation && bridgeInstanceId == other.bridgeInstanceId &&
      sessionEpoch == other.sessionEpoch && mediaSessionId == other.mediaSessionId &&
      contentId == other.contentId;

  bool sameAs(CastPlayerMediaIdentity other) =>
      sameMediaAs(other) && endedSequence == other.endedSequence;
}

class CastPlayerEffectTicket {
  final CastPlayerMediaIdentity identity;
  final CastPlayerMediaIdentity? Function() current;
  const CastPlayerEffectTicket(this.identity, this.current);
  bool get isCurrent {
    final latest = current();
    return latest != null && identity.sameAs(latest);
  }

  Future<T?> resolve<T>(Future<T> pending) async {
    if (!isCurrent) return null;
    final value = await pending;
    return isCurrent ? value : null;
  }
}

class CastPlayerGuardedEffect {
  static Future<T?> resolve<T>(Future<T> pending, bool Function() current) async {
    if (!current()) return null;
    final value = await pending;
    return current() ? value : null;
  }
}

class CastPlayerManualIntentTicket {
  final int revision;
  final int Function() currentRevision;
  final CastPlayerEffectTicket media;
  final bool Function()? permitted;
  const CastPlayerManualIntentTicket({required this.revision,
    required this.currentRevision, required this.media, this.permitted});
  bool get isCurrent => revision == currentRevision() && media.isCurrent &&
      (permitted?.call() ?? true);
}

class CastPlayerSeriesLanguagePreference {
  final String seriesIdentity;
  final String? audioLanguage;
  final String? subtitleLanguage;
  final bool subtitlesDisabled;
  final bool updateAudio;
  final bool updateSubtitle;
  const CastPlayerSeriesLanguagePreference({required this.seriesIdentity,
    this.audioLanguage, this.subtitleLanguage, this.subtitlesDisabled = false,
    this.updateAudio = true, this.updateSubtitle = true});
  Map<String, dynamic> toMap() => {
    if (audioLanguage != null) 'audioLanguage': audioLanguage,
    if (subtitleLanguage != null) 'subtitleLanguage': subtitleLanguage,
    'subtitlesDisabled': subtitlesDisabled,
  };
  factory CastPlayerSeriesLanguagePreference.fromMap(String seriesIdentity,
    Map<String, dynamic> map) => CastPlayerSeriesLanguagePreference(
      seriesIdentity: seriesIdentity,
      audioLanguage: map['audioLanguage'] as String?,
      subtitleLanguage: map['subtitleLanguage'] as String?,
      subtitlesDisabled: map['subtitlesDisabled'] == true,
    );
}

/// Captured before LOAD; outgoing scrobbles must never read the incoming clock.
class CastPlayerTrackingTarget {
  final String? imdbId;
  final String? contentType;
  final int? season;
  final int? episode;
  final Duration position;
  final Duration duration;
  const CastPlayerTrackingTarget({required this.imdbId, required this.contentType,
    required this.season, required this.episode, required this.position,
    required this.duration});
  double get progress => duration <= Duration.zero ? 0.0 :
      (position.inMicroseconds * 100 / duration.inMicroseconds).clamp(0.0, 100.0).toDouble();
}

/// Preserve action order across async ID/auth reads: old STOP must settle
/// before the new target's START/checkpoint reaches an account.
class CastPlayerTrackingQueue {
  Future<void> _tail = Future<void>.value();
  Future<void> send(Future<Object?> Function() effect) {
    final operation = _tail.then((_) async { await effect(); });
    _tail = operation.catchError((_) {});
    return operation;
  }
}

class CastPlayerCompletionTarget {
  final String? imdbId;
  final String contentType;
  final String title;
  final int? season;
  final int? episode;
  const CastPlayerCompletionTarget({required this.imdbId, required this.contentType,
    required this.title, this.season, this.episode});
  String get key => '$contentType:${imdbId ?? title}:$season:$episode';
}

class CastPlayerCompletionGate {
  final Set<String> _claimed = {};
  bool claim(String identity) => _claimed.add(identity);
  void reset() => _claimed.clear();
}

class CastPlayerRestorePlan {
  static Future<bool> yieldToCast({required bool Function() permitted,
    required Future<void> Function() pauseLocal,
    Future<void> Function()? settleReceiver, void Function()? publish}) async {
    if (!permitted()) return false;
    await pauseLocal();
    if (!permitted()) return false;
    if (settleReceiver != null) {
      await settleReceiver();
      if (!permitted()) return false;
    }
    publish?.call();
    return true;
  }

  static bool mayCancelInitialTransfer({required bool ownsAttempt,
    required bool remoteCommitted, required bool receiverUncertain}) =>
      ownsAttempt && !remoteCommitted && !receiverUncertain;

  static bool needsOpen({required String? parkedUrl, required String committedUrl}) =>
      parkedUrl != committedUrl;
  static bool mayResumeLocal({required bool localOwnsPlayback,
    required bool sleepStopped}) => localOwnsPlayback && !sleepStopped;

  /// Publish local ownership only after the committed media opened and its
  /// clock/play intent landed. A failed or stale restore retains transfer ownership.
  static Future<bool> restore({
    required String? parkedUrl,
    required String committedUrl,
    required bool headersChanged,
    required Duration position,
    required bool shouldPlay,
    bool Function()? shouldPlayNow,
    required bool Function() permitted,
    required Future<void> Function() open,
    required Future<void> Function(Duration) seek,
    required Future<void> Function(bool) setPlaying,
  }) async {
    if (!permitted()) return false;
    if (headersChanged || needsOpen(parkedUrl: parkedUrl, committedUrl: committedUrl)) {
      await open();
      if (!permitted()) return false;
    }
    if (position >= Duration.zero) {
      await seek(position);
      if (!permitted()) return false;
    }
    await setPlaying(shouldPlayNow?.call() ?? shouldPlay);
    return permitted();
  }
}
