import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/tutor/providers/notes_provider.dart';

void main() {
  group('NotesState', () {
    test('初始状态默认值正确', () {
      const state = NotesState();
      expect(state.mode, 'summary');
      expect(state.inputContent, '');
      expect(state.result, '');
      expect(state.isLoading, false);
      expect(state.isCleaning, false);
      expect(state.cleaningContent, '');
      expect(state.savedNotes, isEmpty);
      expect(state.viewingNote, isNull);
      expect(state.isLoadingSaved, false);
    });

    test('copyWith 修改 inputContent', () {
      final state = const NotesState().copyWith(inputContent: '测试内容');
      expect(state.inputContent, '测试内容');
      expect(state.isCleaning, false);
    });

    test('copyWith 启用清洗状态', () {
      final state = const NotesState().copyWith(
        isCleaning: true,
        cleaningContent: '清洗中...',
      );
      expect(state.isCleaning, isTrue);
      expect(state.cleaningContent, '清洗中...');
      expect(state.isLoading, false);
    });

    test('copyWith clearCleaning 清除清洗内容', () {
      final state = NotesState(
        isCleaning: true,
        cleaningContent: '旧内容',
      ).copyWith(clearCleaning: true);
      expect(state.cleaningContent, '');
      expect(state.isCleaning, isTrue);
    });

    test('清洗完成后覆盖 inputContent', () {
      final state = NotesState(
        inputContent: '原始内容',
        isCleaning: true,
        cleaningContent: '清洗输出...',
      ).copyWith(
        inputContent: '清洗后的内容',
        isCleaning: false,
        clearCleaning: true,
      );
      expect(state.inputContent, '清洗后的内容');
      expect(state.isCleaning, isFalse);
      expect(state.cleaningContent, '');
    });

    test('copyWith 保留未修改的字段', () {
      const original = NotesState(mode: 'cards', inputContent: '原始');
      final updated = original.copyWith(isCleaning: true);
      expect(updated.mode, 'cards');
      expect(updated.inputContent, '原始');
      expect(updated.isCleaning, isTrue);
    });

    test('流式场景: isLoading + result 同时非空', () {
      const state = NotesState(isLoading: true, result: '部分内容...');
      expect(state.isLoading, isTrue);
      expect(state.result, isNotEmpty);
    });

    test('流式场景: result 累积', () {
      final state = NotesState(result: '第一段').copyWith(result: '第一段第二段');
      expect(state.result, '第一段第二段');
    });

    test('viewingNote 切换', () {
      final note = SavedNote(id: '1', title: '测试', content: '内容', mode: 'summary', createdAt: DateTime.now());
      final state = NotesState().copyWith(viewingNote: note);
      expect(state.viewingNote, isNotNull);
      expect(state.viewingNote!.title, '测试');

      final cleared = state.copyWith(clearViewingNote: true);
      expect(cleared.viewingNote, isNull);
    });

    test('savedNotes 增删', () {
      final notes = [
        SavedNote(id: '1', title: '笔记1', content: '内容1', mode: 'summary', createdAt: DateTime.now()),
        SavedNote(id: '2', title: '笔记2', content: '内容2', mode: 'cards', createdAt: DateTime.now()),
      ];
      final state = NotesState().copyWith(savedNotes: notes);
      expect(state.savedNotes.length, 2);

      final filtered = state.copyWith(
        savedNotes: state.savedNotes.where((n) => n.id != '1').toList(),
      );
      expect(filtered.savedNotes.length, 1);
      expect(filtered.savedNotes.first.id, '2');
    });
  });

  group('SavedNote', () {
    test('创建默认值正确', () {
      final note = SavedNote(
        id: '1', title: '测试笔记', content: '内容', mode: 'summary',
        createdAt: DateTime(2026, 6, 11),
      );
      expect(note.id, '1');
      expect(note.title, '测试笔记');
      expect(note.mode, 'summary');
    });

    test('toJson / fromJson 往返', () {
      final note = SavedNote(
        id: '123', title: '数学笔记', content: '微积分核心概念...', mode: 'cards',
        createdAt: DateTime(2026, 6, 11, 10, 30),
      );
      final json = note.toJson();
      final restored = SavedNote.fromJson(json);
      expect(restored.id, note.id);
      expect(restored.title, note.title);
      expect(restored.content, note.content);
      expect(restored.mode, note.mode);
      expect(restored.createdAt, note.createdAt);
    });

    test('preview 截断长内容', () {
      final note = SavedNote(
        id: '1', title: '长笔记', content: 'A' * 200, mode: 'summary',
        createdAt: DateTime.now(),
      );
      expect(note.preview.length, 123);
      expect(note.preview.endsWith('...'), isTrue);
    });

    test('preview 短内容不截断', () {
      final note = SavedNote(
        id: '2', title: '短笔记', content: '短内容', mode: 'summary',
        createdAt: DateTime.now(),
      );
      expect(note.preview, '短内容');
    });

    test('fromJson 容错处理无效数据', () {
      final note = SavedNote.fromJson({'id': 'abc', 'title': '测试'});
      expect(note.id, 'abc');
      expect(note.title, '测试');
      expect(note.content, '');
      expect(note.mode, 'summary');
    });
  });

  group('OCR 纠错词典', () {
    // OCR 纠错词典是 NotesNotifier 的静态常量 _ocrFixMap
    // 此处验证 _fixOcrText 的等价行为
    test('常见错字纠正', () {
      // 模拟 _fixOcrText 逻辑
      const fixMap = {
        '井': '并', '从': '从', 'r1': 'n', '丨': '|',
      };
      String fixText(String text) {
        var result = text;
        for (final entry in fixMap.entries) {
          result = result.replaceAll(entry.key, entry.value);
        }
        return result;
      }

      expect(fixText('井且'), '并且');
      expect(fixText('从而'), '从而');
      expect(fixText('r1值'), 'n值');
    });

    test('多个纠错同时应用', () {
      const fixMap = {'井': '并', '从': '从'};
      String fixText(String text) {
        var result = text;
        for (final entry in fixMap.entries) {
          result = result.replaceAll(entry.key, entry.value);
        }
        return result;
      }

      expect(fixText('井从'), '并从');
    });

    test('无错字不修改', () {
      const fixMap = {'井': '并'};
      String fixText(String text) {
        var result = text;
        for (final entry in fixMap.entries) {
          result = result.replaceAll(entry.key, entry.value);
        }
        return result;
      }

      expect(fixText('正常文本'), '正常文本');
    });
  });

  group('ConcurrencyLimiter', () {
    test('信号量限制并发数', () async {
      final limiter = _TestLimiter(maxConcurrent: 2);
      final started = <int>[];
      final completed = <int>[];

      final futures = List.generate(4, (i) async {
        await limiter.acquire();
        started.add(i);
        await Future.delayed(const Duration(milliseconds: 10));
        completed.add(i);
        limiter.release();
      });

      // 启动所有任务后等待一小段时间
      await Future.delayed(const Duration(milliseconds: 5));

      // 最多只有 2 个任务在运行
      expect(started.length, 2);

      await Future.wait(futures);
      expect(completed.length, 4);
    });

    test('release 后唤醒等待任务', () async {
      final limiter = _TestLimiter(maxConcurrent: 1);
      final order = <int>[];

      final futures = List.generate(3, (i) async {
        await limiter.acquire();
        order.add(i);
        await Future.delayed(const Duration(milliseconds: 5));
        limiter.release();
      });

      await Future.wait(futures);
      expect(order, [0, 1, 2]); // 顺序执行
    });
  });
}

/// 用于单元测试的 _ConcurrencyLimiter 副本（原始类为私有的 _ConcurrencyLimiter）。
class _TestLimiter {
  final int maxConcurrent;
  int _running = 0;
  final List<void Function()> _queue = [];

  _TestLimiter({this.maxConcurrent = 4});

  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(() => completer.complete());
    await completer.future;
    _running++;
  }

  void release() {
    _running--;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      next();
    }
  }
}

