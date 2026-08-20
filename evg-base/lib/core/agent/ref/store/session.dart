/// Port of reasonix/internal/store/session.go.
library;

import 'package:path/path.dart' as p;

/// Reports whether [name] is a primary session transcript file.
bool isSessionTranscriptName(String name) {
  final n = name.trim();
  return n.endsWith('.jsonl') &&
      !n.endsWith('.events.jsonl') &&
      !n.endsWith('.conflicts.jsonl') &&
      !n.endsWith('.guardian.jsonl');
}

String _stem(String sessionPath) {
  if (sessionPath.trim().isEmpty) return '';
  return sessionPath.replaceFirst(RegExp(r'\.jsonl$'), '');
}

String sessionRecoveryState(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.recovery.json';

String sessionContext(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.context.json';

String sessionMeta(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '$sessionPath.meta';

String sessionGoalState(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.goal-state.json';

String sessionEventLog(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.events.jsonl';

String sessionEventLogDamaged(String sessionPath) =>
    '${sessionEventLog(sessionPath)}.damaged';

String sessionEventIndex(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.event-index.json';

String sessionDisplayIndex(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.display-index.json';

String sessionConflictLog(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.conflicts.jsonl';

String sessionLockFile(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '$sessionPath.lock';

String sessionLeaseLock(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '$sessionPath.lease.lock';

String sessionLeaseInfo(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '$sessionPath.lease.json';

String sessionCheckpointDir(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.ckpt';

String sessionJobsDir(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.jobs';

String sessionInboxDir(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.inbox';

String sessionCleanupPending(String sessionPath) =>
    sessionPath.trim().isEmpty ? '' : '${_stem(sessionPath)}.cleanup-pending.json';

/// Returns every regular-file sidecar owned by a session transcript.
List<String> sessionSidecarFiles(String sessionPath) {
  if (sessionPath.trim().isEmpty) return <String>[];
  return [
    sessionMeta(sessionPath),
    sessionGoalState(sessionPath),
    sessionEventLog(sessionPath),
    sessionEventLogDamaged(sessionPath),
    sessionEventIndex(sessionPath),
    sessionDisplayIndex(sessionPath),
    sessionConflictLog(sessionPath),
    sessionRecoveryState(sessionPath),
    sessionContext(sessionPath),
  ];
}
