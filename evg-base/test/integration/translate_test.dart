/// Translate 模块单元测试 — Service + Queue + Models。
library;

import 'package:evergreen_base/core/services/pdf_translate_service.dart';
import 'package:evergreen_base/core/services/translate_queue.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/translate/translate_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // ═══════ Models 测试 ═══════
  group('Translate Models', () {
    test('TranslationJob copyWith preserves unchanged', () {
      final job = TranslationJob(id: 't1', inputPath: '/t.pdf', inputName: 't.pdf', langIn: 'en', langOut: 'zh');
      final u = job.copyWith(status: TranslationStatus.translating);
      expect(u.id, 't1');
      expect(u.status, TranslationStatus.translating);
    });

    test('TranslationJob progress', () {
      final job = TranslationJob(id: '1', inputPath: '/t.pdf', inputName: 't.pdf',
          langIn: 'en', langOut: 'zh', currentPage: 5, totalPages: 10);
      expect(job.progress, 0.5);
    });

    test('TranslationJob status helpers', () {
      final idle = TranslationJob(id: '1', inputPath: '/a.pdf', inputName: 'a.pdf',
          langIn: 'en', langOut: 'zh', status: TranslationStatus.idle);
      expect(idle.isActive, false);
      expect(idle.copyWith(status: TranslationStatus.translating).isActive, true);
      expect(idle.copyWith(status: TranslationStatus.done).isTerminal, true);
    });

    test('stageFromString fallback', () {
      expect(TranslationJob.stageFromString('unknown'), TranslateStage.translate);
    });

    test('PdfTranslateResult hasOutput', () {
      expect(const PdfTranslateResult().hasOutput, false);
      expect(const PdfTranslateResult(dualPdfPath: '/t/d.pdf').hasOutput, true);
    });

    test('QueueState calculations', () {
      final state = QueueState(completed: [
        TranslationJob(id: '1', inputPath: '/a.pdf', inputName: 'a.pdf', langIn: 'en', langOut: 'zh', status: TranslationStatus.done),
        TranslationJob(id: '2', inputPath: '/b.pdf', inputName: 'b.pdf', langIn: 'en', langOut: 'zh', status: TranslationStatus.done),
      ]);
      expect(state.totalFiles, 2);
      expect(state.doneCount, 2);
      expect(state.overallProgress, 1.0);
    });
  });

  // ═══════ Service 测试 ═══════
  group('PdfTranslateService', () {
    test('translate throws on missing file', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      expect(
        () => svc.translate(inputPath: '/nope.pdf', outputDir: '/t', apiKey: 'sk'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('文件不存在'))),
      );
    });

    test('checkEnvironment missingDeps when deps not installed', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      final status = await svc.checkEnvironment();
      // 如果找到了 Python 但 pdf2zh 未安装 → missingDeps
      expect(status, anyOf(EnvStatus.missingPython, EnvStatus.missingDeps));
    });
  });

  // ═══════ Queue 测试 ═══════
  group('TranslateQueue', () {
    test('enqueueAll emits snapshot', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      final q = TranslateQueue(service: svc, apiKey: 'sk', maxParallel: 2);
      final events = <QueueEvent>[];
      final sub = q.eventStream.listen(events.add);
      q.enqueueAll(['/tmp/a.pdf', '/tmp/b.pdf']);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(events.whereType<QueueSnapshotEvent>(), isNotEmpty);
      await sub.cancel();
      q.dispose();
    });

    test('maxParallel limits active', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      final q = TranslateQueue(service: svc, apiKey: 'sk', maxParallel: 2);
      q.enqueueAll(['/tmp/a.pdf', '/tmp/b.pdf', '/tmp/c.pdf', '/tmp/d.pdf']);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(q.activeJobs.length, lessThanOrEqualTo(2));
      q.dispose();
    });

    test('reset clears all', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      final q = TranslateQueue(service: svc, apiKey: 'sk', maxParallel: 2);
      q.enqueueAll(['/tmp/a.pdf']);
      await Future.delayed(const Duration(milliseconds: 50));
      q.reset();
      expect(q.waitingJobs, isEmpty);
      expect(q.activeJobs, isEmpty);
      expect(q.completedJobs, isEmpty);
      q.dispose();
    });

    test('empty enqueue does nothing', () async {
      final svc = PdfTranslateService(scriptPath: p.join('n', 'pdf_translate.py'));
      final q = TranslateQueue(service: svc, apiKey: 'sk', maxParallel: 2);
      final events = <QueueEvent>[];
      final sub = q.eventStream.listen(events.add);
      q.enqueueAll([]);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.whereType<QueueSnapshotEvent>(), isEmpty);
      await sub.cancel();
      q.dispose();
    });
  });
}
