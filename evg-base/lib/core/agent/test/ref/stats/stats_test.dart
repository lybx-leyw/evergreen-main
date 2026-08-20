/// Port of reasonix/internal/stats/stats_test.go.
///
/// Translation notes:
/// - t.TempDir() maps to Directory.systemTemp.createTempSync().
/// - The dispatcher is shared per stats dir; tests that need deterministic
///   reads call flush() after emitting, matching the Go flushRecorder helper.
/// - filelock usage mirrors the Go test's lock-hold scenario.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../ref/billing/cost_quote.dart' as billing;
import '../../../../ref/event/event.dart' as event;
import '../../../../ref/filelock/filelock.dart' as filelock;
import '../../../../ref/provider/usage.dart' as provider;
import '../../../../ref/stats/stats.dart' as stats;

Future<void> flushRecorder(stats.Recorder recorder) async {
  await recorder.flush();
}

void main() {
  test('recorder writes daily file', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final inner = _SpySink();
    final r = _newRecorder(inner, dir.path, 'desktop');

    r.emit(_usageEvent('deepseek/deepseek-v4-flash', 100, 50, 10, 20, 30, 150));
    r.emit(_usageEvent('deepseek/deepseek-v4-pro', 200, 100, 0, 0, 0, 300));
    r.emit(_turnEvent());
    await flushRecorder(r);

    final files = _dailyJSONLFiles(dir);
    expect(files.length, 1);
    final data = File('${dir.path}/${files[0]}').readAsStringSync();
    var lines = 0;
    for (final b in data.codeUnits) {
      if (b == 0x0A) lines++;
    }
    expect(lines, 3);
    expect(inner.events.length, 3);
  });

  test('recorder counts merged provider requests', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final r = _newRecorder(_SpySink(), dir.path, 'desktop');
    final e = _usageEvent('deepseek/deepseek-v4-pro', 100, 50, 10, 0, 100, 150);
    e.usage!.requestCount = 2;
    r.emit(e);
    await flushRecorder(r);

    final day = stats.dayStart(DateTime.now());
    final got = await stats.queryStats(
        r.writer, stats.SourceFilter(from: day, to: day));
    expect(got.requests, 2);
    expect(got.daily.length, 1);
    expect(got.daily[0].requests, 2);
  });

  test('recorder captures guardian usage and preserves protocol audit',
      () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final inner = _AuditSpySink();
    final r = _newRecorder(inner, dir.path, 'desktop');
    r.emit(event.Event()
      ..kind = event.Kind.guardianAssessment
      ..modelRef = 'deepseek/deepseek-v4-flash'
      ..guardian = event.GuardianResult()
      ..usage = provider.Usage()
      ..promptTokens = 10
      ..completionTokens = 5
      ..totalTokens = 15);
    event.recordProtocolRecovery(
        r,
        event.ProtocolRecoveryAudit(
            kind: event.ProtocolRecoveryKind.missingReasoningRetryRecovered));
    await flushRecorder(r);

    final day = stats.dayStart(DateTime.now());
    final got = await stats.queryStats(
        r.writer, stats.SourceFilter(from: day, to: day));
    expect(got.tokens, 15);
    expect(got.topModel, 'deepseek/deepseek-v4-flash');
    expect(inner.protocol.length, 1);
    expect(inner.protocol[0].kind,
        event.ProtocolRecoveryKind.missingReasoningRetryRecovered);
  });

  test('recorder skips zero usage', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final r = _newRecorder(_SpySink(), dir.path, 'desktop');
    r.emit(_usageEvent('m', 0, 0, 0, 0, 0, 0));
    r.emit(_turnEvent());
    await flushRecorder(r);
    final files = _dailyJSONLFiles(dir);
    expect(files.length, 1);
  });

  test('recorder persists request-only failure without forwarding receipt',
      () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final inner = _SpySink();
    final r = _newRecorder(inner, dir.path, 'desktop');
    r.emit(event.Event()
      ..kind = event.Kind.usage
      ..modelRef = 'deepseek/deepseek-v4-pro'
      ..usage = provider.Usage()
      ..requestCount = 3);
    await flushRecorder(r);

    final day = stats.dayStart(DateTime.now());
    final got = await stats.queryStats(
        r.writer, stats.SourceFilter(from: day, to: day));
    expect(got.requests, 3);
    expect(got.tokens, 0);
    expect(got.activeDays, 1);
    expect(got.models.length, 0);
    expect(got.providers.length, 0);
    expect(inner.events.length, 0);
  });

  test('recorder never waits for stats file lock', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final lock = await filelock.FileLock.acquire('${dir.path}/.append.lock');
    expect(lock, isNotNull);

    final inner = _SpySink();
    final recorder = _newRecorder(inner, dir.path, 'desktop');
    recorder.emit(_usageEvent('deepseek/model', 10, 4, 0, 0, 10, 14));
    expect(inner.events.length, 1);

    await lock!.release();
    await flushRecorder(recorder);
    final day = stats.dayStart(DateTime.now());
    final result = await stats.queryStats(
        recorder.writer, stats.SourceFilter(from: day, to: day));
    expect(result.tokens, 14);
  });

  test('recorder disabled on empty dir', () async {
    final r = _newRecorder(_SpySink(), '', 'desktop');
    r.emit(_usageEvent('m', 1, 1, 0, 0, 0, 2));
    r.emit(_turnEvent());
    final got = await stats.queryStats(
        r.writer,
        stats.SourceFilter(
            from: DateTime.now().subtract(const Duration(hours: 24)),
            to: DateTime.now()));
    expect(got.tokens, 0);
    expect(got.turns, 0);
  });

  test('query aggregates', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final w = stats.Writer(dir.path);
    final now = DateTime.now();
    final day = stats.dayStart(now);

    await w.append(stats.StatsRecord()
      ..timestamp = day.add(const Duration(hours: 1))
      ..modelRef = 'deepseek/deepseek-v4-flash'
      ..source = 'desktop'
      ..total = 100
      ..prompt = 60
      ..completion = 40
      ..cacheHit = 10
      ..cacheMiss = 50);
    await w.append(stats.StatsRecord()
      ..timestamp = day.add(const Duration(hours: 2))
      ..modelRef = 'deepseek/deepseek-v4-pro'
      ..source = 'desktop'
      ..total = 200
      ..prompt = 100
      ..completion = 100);
    await w.append(stats.StatsRecord()
      ..timestamp = day.add(const Duration(hours: 3))
      ..source = 'desktop'
      ..turn = true);
    await w.append(stats.StatsRecord()
      ..timestamp = DateTime(day.year, day.month, day.day - 1)
      ..modelRef = 'zhipu/glm-5.2'
      ..source = 'cli'
      ..total = 300);

    final got = await stats.queryStats(
        w,
        stats.SourceFilter(
            from: DateTime(day.year, day.month, day.day - 1), to: day));
    expect(got.tokens, 600);
    expect(got.requests, 3);
    expect(got.turns, 1);
    expect(got.cacheHit, 10);
    expect(got.cacheMiss, 50);
    expect(got.activeDays, 2);
    expect(got.topModel, 'zhipu/glm-5.2');
    expect(got.daily.length, 2);
    expect(got.daily[0].cacheHit, 0);
    expect(got.daily[0].cacheMiss, 0);
    expect(got.daily[1].cacheHit, 10);
    expect(got.daily[1].cacheMiss, 50);
    expect(got.models.length, 3);
    final found = <String, int>{};
    for (final p in got.providers) {
      found[p.provider] = p.tokens;
    }
    expect(found['deepseek'], 300);
    expect(found['zhipu'], 300);
    expect(found.length, 2);
    expect(got.models[0].percent, greaterThan(0));
    expect(got.models[0].percent, lessThanOrEqualTo(100));
  });

  test('query source filter', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final w = stats.Writer(dir.path);
    final now = DateTime.now();
    final day = stats.dayStart(now);

    await w.append(stats.StatsRecord()
      ..timestamp = day
      ..modelRef = 'm1'
      ..source = 'desktop'
      ..total = 100);
    await w.append(stats.StatsRecord()
      ..timestamp = day
      ..modelRef = 'm2'
      ..source = 'cli'
      ..total = 50);

    final got = await stats.queryStats(
        w, stats.SourceFilter(source: 'cli', from: day, to: day));
    expect(got.tokens, 50);
    expect(got.models.length, 1);
    expect(got.models[0].model, 'm2');
  });

  test('query empty range', () async {
    final w =
        stats.Writer(Directory.systemTemp.createTempSync('stats-test-').path);
    final now = DateTime.now();
    final got = await stats.queryStats(
        w,
        stats.SourceFilter(
            from: now, to: now.subtract(const Duration(hours: 24))));
    expect(got.tokens, 0);
    expect(got.activeDays, 0);
    expect(got.daily.length, 0);
  });

  test('query disabled writer returns array contract', () async {
    final now = DateTime.now();
    final got = await stats.queryStats(
        stats.Writer(''), stats.SourceFilter(from: now, to: now));
    expect(got.daily, isNotNull);
    expect(got.models, isNotNull);
    expect(got.providers, isNotNull);
    final b = jsonEncode(got.toJson());
    final wire = jsonDecode(b) as Map<String, dynamic>;
    expect(wire['daily'], '[]');
    expect(wire['models'], '[]');
    expect(wire['providers'], '[]');
  });

  test('query top provider aggregates across models', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final w = stats.Writer(dir.path);
    final day = stats.dayStart(DateTime.now());
    for (final rec in [
      stats.StatsRecord()
        ..timestamp = day
        ..modelRef = 'provider-a/model-1'
        ..total = 60,
      stats.StatsRecord()
        ..timestamp = day
        ..modelRef = 'provider-a/model-2'
        ..total = 60,
      stats.StatsRecord()
        ..timestamp = day
        ..modelRef = 'provider-b/model-1'
        ..total = 100,
    ]) {
      await w.append(rec);
    }
    final got =
        await stats.queryStats(w, stats.SourceFilter(from: day, to: day));
    expect(got.topModel, 'provider-b/model-1');
    expect(got.topProvider, 'provider-a');
  });

  test('decode records skips malformed', () {
    const good = '{"ts":"2026-08-02T10:00:00+08:00","total":100}';
    const bad = '{"ts":"2026-08-02T10:00:00+08:00","total":';
    final recs = stats.decodeRecords('$good\n$bad\n$bad\n$good');
    expect(recs.length, 2);
    for (final r in recs) {
      expect(r.total, 100);
    }
  });

  test('append repairs torn trailing record', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final w = stats.Writer(dir.path);
    final now = DateTime.now();
    final path = '${dir.path}/${stats.dayLayout(now)}.jsonl';
    File(path).writeAsStringSync('{"ts":"2026-08-02T10:00:00+08:00","total":');
    await w.append(stats.StatsRecord()
      ..timestamp = now
      ..modelRef = 'deepseek/deepseek-v4-flash'
      ..total = 42);
    final recs = await w.readDaily(stats.dayLayout(now));
    expect(recs, isNotNull);
    expect(recs!.length, 1);
    expect(recs[0].total, 42);
    expect(recs[0].modelRef, 'deepseek/deepseek-v4-flash');
  });

  test('concurrent writers append whole records', () async {
    final dir = Directory.systemTemp.createTempSync('stats-test-');
    final now = DateTime.now();
    const writers = 8;
    const perWriter = 40;
    final futures = <Future<void>>[];
    for (var i = 0; i < writers; i++) {
      final model = i;
      futures.add(() async {
        final w = stats.Writer(dir.path);
        for (var j = 0; j < perWriter; j++) {
          await w.append(stats.StatsRecord()
            ..timestamp = now
            ..modelRef = 'provider/model-$model'
            ..total = 1);
        }
      }());
    }
    await Future.wait(futures);

    final w = stats.Writer(dir.path);
    final recs = await w.readDaily(stats.dayLayout(now));
    expect(recs, isNotNull);
    expect(recs!.length, writers * perWriter);
  });

  test('daily tokens wire keys', () {
    final d = stats.DailyTokens()
      ..day = '2026-08-02'
      ..total = 150
      ..byModel = {'deepseek/x': 150}
      ..requests = 2
      ..turns = 1
      ..cacheHit = 10
      ..cacheMiss = 50;
    final b = jsonEncode(d.toJson());
    final keys = jsonDecode(b) as Map<String, dynamic>;
    for (final want in [
      'day',
      'total',
      'byModel',
      'byProvider',
      'requests',
      'turns',
      'cacheHit',
      'cacheMiss'
    ]) {
      expect(keys.containsKey(want), isTrue, reason: 'wire key $want missing');
    }
    for (final bad in ['by_model', 'by_provider', 'cache_hit', 'cache_miss']) {
      expect(keys.containsKey(bad), isFalse,
          reason: 'legacy snake_case key $bad still present');
    }
  });

  test('provider split', () {
    expect(stats.providerOf('deepseek/deepseek-v4-flash'), 'deepseek');
    expect(stats.providerOf('bare-model'), 'default');
  });
}

// ── helpers ──

stats.Recorder _newRecorder(event.Sink inner, String dir, String source) {
  final writer = stats.Writer(dir);
  writer.usage = stats.managerForUsage(dir);
  return stats.Recorder(
    inner: inner,
    writer: writer,
    dispatcher: stats.RecordDispatcher.forDir(dir),
    source: source,
  );
}

List<String> _dailyJSONLFiles(Directory dir) {
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.jsonl'))
      .toList();
}

event.Event _usageEvent(String model, int prompt, int completion, int reasoning,
    int hit, int miss, int total) {
  return event.Event()
    ..kind = event.Kind.usage
    ..modelRef = model
    ..usage = provider.Usage()
    ..promptTokens = prompt
    ..completionTokens = completion
    ..reasoningTokens = reasoning
    ..cacheHitTokens = hit
    ..cacheMissTokens = miss
    ..totalTokens = total;
}

event.Event _turnEvent() => event.Event()..kind = event.Kind.turnDone;

class _SpySink implements event.Sink {
  final events = <event.Event>[];

  @override
  void emit(event.Event e) => events.add(e);
}

class _AuditSpySink implements event.Sink, event.ProtocolRecoveryAuditSink {
  final events = <event.Event>[];
  final protocol = <event.ProtocolRecoveryAudit>[];

  @override
  void emit(event.Event e) => events.add(e);

  @override
  void recordProtocolRecovery(event.ProtocolRecoveryAudit a) => protocol.add(a);
}
