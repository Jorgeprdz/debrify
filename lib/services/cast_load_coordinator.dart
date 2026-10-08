import 'dart:async';

/// Receiver LOAD is a physical operation. Superseding a request settles its
/// caller, but cannot cancel a command already sent to Chromecast.
enum CastLoadOutcome { committed, rejected, superseded, cancelled, failed }

class CastLoadResult<T> {
  const CastLoadResult(this.outcome, this.generation, {this.value, this.error});
  final CastLoadOutcome outcome;
  final int generation;
  final T? value;
  final Object? error;
  bool get committed => outcome == CastLoadOutcome.committed;
}

class _CastLoadOperation<T> {
  _CastLoadOperation({
    required this.generation,
    required this.load,
    required this.verify,
    this.permitted,
    this.onPhysicalReply,
    this.onPhysicalResult,
  });

  final int generation;
  final Future<T> Function() load;
  final bool Function(T) verify;
  final bool Function()? permitted;
  final void Function(T reply, int generation)? onPhysicalReply;
  final void Function(T reply, int generation, bool logicalPending)? onPhysicalResult;
  final Completer<CastLoadResult<T>> result = Completer<CastLoadResult<T>>();
  Timer? timeoutTimer;

  void settle(CastLoadOutcome outcome, {T? value, Object? error}) {
    if (!result.isCompleted) {
      result.complete(
        CastLoadResult<T>(outcome, generation, value: value, error: error),
      );
    }
  }
}

/// Begin an intent BEFORE awaiting any provider, metadata or network callback.
/// All nested steps must pass the same ticket to submit().
///
/// The remote transport is always single-flight. A timeout settles the Dart
/// caller but deliberately leaves physical exclusion held until its underlying
/// native Future eventually settles. Never infer receiver cancellation.
class CastLoadCoordinator<T> {
  CastLoadCoordinator({
    this.callerTimeout = const Duration(seconds: 30),
    this.onPhysicalStateChanged,
  });

  final Duration callerTimeout;
  void Function()? onPhysicalStateChanged;
  int _generation = 0;
  bool _disposed = false;
  _CastLoadOperation<T>? _active;
  _CastLoadOperation<T>? _pending;
  int _physicalControlsInFlight = 0;
  int _timedOutControlsInFlight = 0;
  final Set<void Function()> _cancelControlCallers = <void Function()>{};

  int get generation => _generation;
  bool get hasInFlight => _active != null || _physicalControlsInFlight > 0;
  bool get isBlockedOnReceiver =>
      _active?.result.isCompleted == true || _timedOutControlsInFlight > 0;
  bool isCurrent(int ticket) => !_disposed && ticket == _generation;

  int beginIntent() {
    final next = ++_generation;
    _settleControlCallers();
    if (_disposed) return next;
    _pending?.settle(CastLoadOutcome.superseded);
    _pending?.timeoutTimer?.cancel();
    _pending = null;
    // The caller need not wait for obsolete transport; physical drain still does.
    _active?.settle(CastLoadOutcome.superseded);
    return next;
  }

  Future<CastLoadResult<T>> submit({
    required int generation,
    required Future<T> Function() load,
    required bool Function(T) verify,
    bool Function()? permitted,
    void Function(T reply, int generation)? onPhysicalReply,
    void Function(T reply, int generation, bool logicalPending)? onPhysicalResult,
  }) {
    if (!isCurrent(generation)) {
      return Future<CastLoadResult<T>>.value(
        CastLoadResult<T>(
          _disposed ? CastLoadOutcome.cancelled : CastLoadOutcome.superseded,
          generation,
        ),
      );
    }
    final op = _CastLoadOperation<T>(
      generation: generation,
      load: load,
      verify: verify,
      permitted: permitted,
      onPhysicalReply: onPhysicalReply,
      onPhysicalResult: onPhysicalResult,
    );
    // Reentrancy or a second nested LOAD may supersede an earlier *queued*
    // same-generation command. It never creates parallel physical LOADs.
    _pending?.settle(CastLoadOutcome.superseded);
    _pending?.timeoutTimer?.cancel();
    _pending = op;
    if (callerTimeout > Duration.zero) {
      op.timeoutTimer = Timer(callerTimeout, () {
        // Even a QUEUED caller must settle when the receiver is hung.
        op.settle(CastLoadOutcome.failed, error: StateError('Cast LOAD timeout'));
        if (identical(_pending, op)) _pending = null;
      });
    }
    _drain();
    return op.result.future;
  }

  void _drain() {
    if (_disposed || _active != null ||
        _physicalControlsInFlight > 0 || _pending == null) return;
    final op = _pending!;
    _pending = null;
    _active = op;
    unawaited(_execute(op));
  }

  Future<void> _execute(_CastLoadOperation<T> op) async {
    try {
      if (!isCurrent(op.generation)) {
        op.settle(CastLoadOutcome.superseded);
        return;
      }
      if (op.permitted?.call() == false) {
        op.settle(CastLoadOutcome.cancelled);
        return;
      }
      final remoteFuture = op.load();
      // Timer began at submission; physical exclusion still lasts until ACK.
      final reply = await remoteFuture;
      // Physical receiver reality must still be observed after a caller has
      // been superseded. Never reinterpret that event as a logical commit.
      try {
        op.onPhysicalResult?.call(reply, op.generation, !op.result.isCompleted);
        op.onPhysicalReply?.call(reply, op.generation);
      } catch (_) {
        // Observation failure cannot make a completed LOAD physically pending.
      }
      if (!isCurrent(op.generation)) {
        op.settle(CastLoadOutcome.superseded);
      } else if (op.permitted?.call() == false) {
        op.settle(CastLoadOutcome.cancelled);
      } else if (!op.verify(reply)) {
        op.settle(CastLoadOutcome.rejected, value: reply);
      } else {
        op.settle(CastLoadOutcome.committed, value: reply);
      }
    } catch (error) {
      op.settle(
        isCurrent(op.generation)
            ? CastLoadOutcome.failed
            : CastLoadOutcome.superseded,
        error: error,
      );
    } finally {
      op.timeoutTimer?.cancel();
      if (identical(_active, op)) _active = null;
      _drain();
      _notifyPhysicalStateChanged();
    }
  }

  /// Serializes a physical receiver command ahead of any later LOAD.
  /// Control may complete logically on timeout but physical exclusion remains
  /// until the native Future actually returns (or the bridge proves it ended).
  Future<R?> dispatchControl<R>({
    required int generation,
    required Future<R> Function() command,
    bool Function()? permitted,
  }) {
    if (!isCurrent(generation) || _active != null ||
        _pending != null || _physicalControlsInFlight > 0 ||
        permitted?.call() == false) return Future<R?>.value(null);
    final caller = Completer<R?>();
    void cancelCaller() {
      if (!caller.isCompleted) caller.complete(null);
    }
    _cancelControlCallers.add(cancelCaller);
    ++_physicalControlsInFlight;
    var timedOut = false;
    Timer? timer;
    if (callerTimeout > Duration.zero) {
      timer = Timer(callerTimeout, () {
        if (!caller.isCompleted) {
          timedOut = true;
          ++_timedOutControlsInFlight;
          caller.complete(null);
        }
      });
    }
    unawaited(_runControl(
      generation: generation,
      command: command,
      permitted: permitted,
      caller: caller,
      onPhysicalSettled: () {
        _cancelControlCallers.remove(cancelCaller);
        timer?.cancel();
        if (timedOut) --_timedOutControlsInFlight;
        --_physicalControlsInFlight;
        _drain();
        _notifyPhysicalStateChanged();
      },
    ));
    return caller.future;
  }

  Future<void> _runControl<R>({
    required int generation,
    required Future<R> Function() command,
    required bool Function()? permitted,
    required Completer<R?> caller,
    required void Function() onPhysicalSettled,
  }) async {
    try {
      if (!isCurrent(generation) || permitted?.call() == false) {
        if (!caller.isCompleted) caller.complete(null);
        return;
      }
      final reply = await command();
      if (!caller.isCompleted) {
        caller.complete(
          isCurrent(generation) && permitted?.call() != false ? reply : null,
        );
      }
    } catch (error, stack) {
      if (!caller.isCompleted) {
        if (!isCurrent(generation) || permitted?.call() == false) {
          caller.complete(null);
        } else {
          caller.completeError(error, stack);
        }
      }
    } finally {
      onPhysicalSettled();
    }
  }

  void _notifyPhysicalStateChanged() {
    try {
      onPhysicalStateChanged?.call();
    } catch (_) {
      // Observer failure cannot re-acquire a drained physical fence.
    }
  }

  void _settleControlCallers() {
    for (final cancel in _cancelControlCallers.toList(growable: false)) {
      cancel();
    }
  }

  void invalidate() {
    ++_generation;
    _settleControlCallers();
    _pending?.settle(CastLoadOutcome.cancelled);
    _pending?.timeoutTimer?.cancel();
    _pending = null;
    _active?.settle(CastLoadOutcome.cancelled);
    // Never release _active: a late native callback may still reach receiver.
  }

  void dispose() {
    invalidate();
    _disposed = true;
  }
}
