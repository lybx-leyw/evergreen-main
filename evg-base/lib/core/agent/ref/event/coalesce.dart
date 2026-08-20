part of 'event.dart';

const coalesceMaxBytes = 16 << 10;
const defaultStreamDeltaWindow = Duration(milliseconds: 16);

Sink coalesce(Sink inner, Duration window) {
  if (nilutil.isNil(inner)) return discard;
  if (window <= Duration.zero) return inner;
  return _Coalescer(inner, window);
}

bool isStreamDelta(Event e) {
  if ((e.kind != Kind.text && e.kind != Kind.reasoning) || e.text.isEmpty) {
    return false;
  }
  // Ensure every other meaningful field is at its default.
  return e.modelRef.isEmpty &&
      e.detail.isEmpty &&
      e.code.isEmpty &&
      e.reasoning.isEmpty &&
      e.memoryCitations.isEmpty &&
      e.level == Level.info &&
      e.audience == NoticeAudience.$default &&
      e.source.isEmpty &&
      e.usageSource.isEmpty &&
      e.sessionHit == 0 &&
      e.sessionMiss == 0 &&
      e.retryAttempt == 0 &&
      e.retryMax == 0 &&
      e.itemId.isEmpty &&
      e.usage == null &&
      e.pricing == null &&
      e.costQuote == null &&
      e.cacheDiagnostics == null &&
      e.readiness == null &&
      e.receipt == null &&
      e.checkpointTurn == null &&
      e.retryScope == null &&
      e.workspace == null &&
      e.completion == null &&
      e.err == null &&
      !e.cancelled &&
      e.outcome.isEmpty;
}

class _Coalescer implements Sink {
  final Sink inner;
  final Duration window;

  final Queue<Event> _queue = Queue<Event>();
  bool _pending = false;
  Kind _kind = Kind.turnStarted;
  final StringBuffer _buf = StringBuffer();
  Timer? _timer;
  DateTime _lastForward = DateTime(0);
  bool _draining = false;

  _Coalescer(this.inner, this.window);

  @override
  void emit(Event e) {
    _lock(() {
      if (!isStreamDelta(e)) {
        _enqueueFlushLocked();
        _queue.add(e);
        _drainAndUnlockLocked();
        return;
      }
      if (_pending && _kind != e.kind) {
        _enqueueFlushLocked();
      }
      final now = DateTime.now();
      if (!_pending && now.difference(_lastForward) >= window) {
        _lastForward = now;
        _queue.add(e);
        _drainAndUnlockLocked();
        return;
      }
      if (!_pending) {
        _pending = true;
        _kind = e.kind;
        _timer?.cancel();
        _timer = Timer(window, _flush);
      }
      _buf.write(e.text);
      if (_buf.length >= coalesceMaxBytes) {
        _enqueueFlushLocked();
      }
      _drainAndUnlockLocked();
    });
  }

  void _flush() {
    _lock(() {
      _enqueueFlushLocked();
      _drainAndUnlockLocked();
    });
  }

  void _enqueueFlushLocked() {
    if (!_pending) return;
    _timer?.cancel();
    _queue.add(Event()
      ..kind = _kind
      ..text = _buf.toString());
    _buf.clear();
    _pending = false;
    _lastForward = DateTime.now();
  }

  void _drainAndUnlockLocked() {
    if (_draining || _queue.isEmpty) {
      _unlock();
      return;
    }
    _draining = true;
    while (_queue.isNotEmpty) {
      final batch = _queue.toList();
      _queue.clear();
      _unlock();
      for (final e in batch) {
        inner.emit(e);
      }
      _lockVoid();
    }
    _draining = false;
    _unlock();
  }

  // --- minimal mutex emulation ---
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  bool _held = false;

  void _lock(void Function() f) {
    if (_held) {
      final c = Completer<void>();
      _waiters.add(c);
      c.future.then((_) => _lock(f));
      return;
    }
    _held = true;
    f();
  }

  void _lockVoid() {
    _held = true;
  }

  void _unlock() {
    _held = false;
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }

  void _runLocked(void Function() f) {
    _lock(() {
      f();
      _unlock();
    });
  }

  void recordDelegationAudit(evidence.DelegationAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordDelegationAudit(inner, a);
      });

  void recordReadinessAudit(evidence.ReadinessAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordReadinessAudit(inner, a);
      });

  void recordTurnCompletion() => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordTurnCompletion(inner);
      });

  void recordProtocolRecovery(ProtocolRecoveryAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordProtocolRecovery(inner, a);
      });

  void recordContractShadow(ContractShadowAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordContractShadow(inner, a);
      });

  void recordCompletionReport(CompletionReportAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordCompletionReport(inner, a);
      });

  void recordOutcomeProgress(evidence.OutcomeSample sample) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordOutcomeProgress(inner, sample);
      });

  void recordMemoryRecall(MemoryRecallAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordMemoryRecall(inner, a);
      });

  void recordDelegationAdmission(DelegationAdmissionAudit a) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordDelegationAdmission(inner, a);
      });

  void recordWorkspaceMutation(WorkspaceMutation m) => _runLocked(() {
        _enqueueFlushLocked();
        _drainAndUnlockLocked();
        recordWorkspaceMutation(inner, m);
      });
}
