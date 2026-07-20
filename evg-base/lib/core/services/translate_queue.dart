/// 并行翻译调度器 — maxParallel 槽位 + FIFO 等待队列 + Stream 事件驱动。
library;

import 'dart:async';

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/services/pdf_translate_service.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

// ═══════ 内部事件类型 ═══════

sealed class QueueEvent {}

class QueueSnapshotEvent extends QueueEvent {
  final List<JobState> waiting;
  final List<JobState> active;
  final List<JobState> completed;
  QueueSnapshotEvent(this.waiting, this.active, this.completed);
}

class QueueJobProgressEvent extends QueueEvent {
  final String jobId;
  final int current;
  final int total;
  final String message;
  QueueJobProgressEvent(this.jobId, this.current, this.total, this.message);
}

class QueueJobStageEvent extends QueueEvent {
  final String jobId;
  final String stage;
  final String message;
  QueueJobStageEvent(this.jobId, this.stage, this.message);
}

class QueueJobDoneEvent extends QueueEvent {
  final JobState job;
  QueueJobDoneEvent(this.job);
}

// ═══════ JobState ═══════

enum JobStatus { queued, translating, done, error }

class JobState {
  final String id;
  final String inputPath;
  final String inputName;
  final String outputDir;
  JobStatus status;
  int currentPage;
  int totalPages;
  String? progressMessage;
  String? stageMessage;
  PdfTranslateResult? result;
  String? errorMessage;

  JobState({
    required this.id,
    required this.inputPath,
    required this.inputName,
    required this.outputDir,
    this.status = JobStatus.queued,
    this.currentPage = 0,
    this.totalPages = 0,
    this.progressMessage,
    this.stageMessage,
    this.result,
    this.errorMessage,
  });

  double get progress =>
      totalPages > 0 ? currentPage / totalPages : 0.0;
}

// ═══════ TranslateQueue ═══════

class TranslateQueue {
  final PdfTranslateService _service;
  final int maxParallel;
  final String apiKey;
  final String model;
  final String? thinking;

  String _langIn = 'en';
  String _langOut = 'zh';

  final List<JobState> _waitingJobs = [];
  final List<JobState> _activeJobs = [];
  final List<JobState> _completedJobs = [];

  final StreamController<QueueEvent> _eventController =
      StreamController<QueueEvent>.broadcast();

  Stream<QueueEvent> get eventStream => _eventController.stream;

  List<JobState> get waitingJobs => List.unmodifiable(_waitingJobs);
  List<JobState> get activeJobs => List.unmodifiable(_activeJobs);
  List<JobState> get completedJobs => List.unmodifiable(_completedJobs);

  bool get isRunning => _activeJobs.isNotEmpty || _waitingJobs.isNotEmpty;

  TranslateQueue({
    required PdfTranslateService service,
    required this.apiKey,
    this.model = 'deepseek-chat',
    this.thinking,
    this.maxParallel = 3,
  }) : _service = service;

  void setLanguages(String langIn, String langOut) {
    _langIn = langIn;
    _langOut = langOut;
  }

  void enqueueAll(List<String> filePaths) {
    if (filePaths.isEmpty) return;

    for (final path in filePaths) {
      final name = p.basename(path);
      _waitingJobs.add(JobState(
        id: const Uuid().v4(),
        inputPath: path,
        inputName: name,
        outputDir: p.join(p.dirname(path), 'translated', name),
      ));
    }

    _emitSnapshot();
    _drain();
  }

  void reset() {
    _waitingJobs.clear();
    _activeJobs.clear();
    _completedJobs.clear();
    _emitSnapshot();
  }

  // ── 调度核心 ──

  void _drain() {
    while (_activeJobs.length < maxParallel && _waitingJobs.isNotEmpty) {
      final job = _waitingJobs.removeAt(0);
      _activeJobs.add(job);
      _startJob(job);
    }
    _emitSnapshot();
  }

  Future<void> _startJob(JobState job) async {
    job.status = JobStatus.translating;
    job.progressMessage = '准备翻译...';
    _emitSnapshot();

    try {
      final result = await _service.translate(
        inputPath: job.inputPath,
        outputDir: job.outputDir,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        langIn: _langIn,
        langOut: _langOut,
        onProgress: (current, total, message) {
          job.currentPage = current;
          job.totalPages = total;
          job.progressMessage = message;
          _eventController.add(
              QueueJobProgressEvent(job.id, current, total, message));
        },
        onStage: (stage, message) {
          job.stageMessage = message;
          _eventController.add(QueueJobStageEvent(job.id, stage, message));
        },
      );

      job.status = JobStatus.done;
      job.result = result;
      Log().info('TranslateQueue: job done', data: {
        'jobId': job.id, 'name': job.inputName, 'seconds': result.totalSeconds,
      });
    } catch (e) {
      job.status = JobStatus.error;
      job.errorMessage = e.toString();
      Log().warn('TranslateQueue: job failed',
          data: {'jobId': job.id, 'name': job.inputName, 'error': e.toString()});
    }

    _activeJobs.remove(job);
    _completedJobs.add(job);
    _eventController.add(QueueJobDoneEvent(job));
    _emitSnapshot();
    _drain();
  }

  void _emitSnapshot() {
    _eventController.add(QueueSnapshotEvent(
      List.from(_waitingJobs),
      List.from(_activeJobs),
      List.from(_completedJobs),
    ));
  }

  void dispose() {
    _eventController.close();
  }
}
