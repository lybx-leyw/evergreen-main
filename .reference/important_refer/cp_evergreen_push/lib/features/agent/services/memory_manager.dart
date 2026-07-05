import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/agent/memory/fact.dart';

/// 全局记忆管理器——提取、存储、冲突检测、自动更新。
///
/// 使用 FileMemoryStore（全局 scope），跨会话持久化。
class MemoryManager {
  late final String _storeDir;
  bool _init = false;

  MemoryManager();

  Future<void> _ensureInit() async {
    if (_init) return;
    final appDir = await getApplicationSupportDirectory();
    _storeDir = p.join(appDir.path, 'memories', 'global');
    await Directory(_storeDir).create(recursive: true);
    _init = true;
  }

  /// 从一轮对话中提取关键事实 → 全局记忆。
  Future<void> extractAndStoreGlobal(
      String userInput, String assistantReply) async {
    await _ensureInit();

    final now = DateTime.now();
    final timeAnchor = '${now.year}年${now.month}月';
    final facts = <MemoryFact>[];

    // 年级
    final gradeMatch = RegExp(r'(大一|大二|大三|大四|研一|研二|研三|博[一二三四五])').firstMatch(userInput);
    if (gradeMatch != null) {
      facts.add(MemoryFact(
        fact: '用户是${gradeMatch.group(0)}学生', timeAnchor: timeAnchor,
        confidence: 0.95, recordedAt: now, source: userInput,
      ));
    }
    // 专业
    final majorMatch = RegExp(r'(主修|专业[是为]|读的?是)([^\s，。,\.]{2,20})').firstMatch(userInput);
    if (majorMatch != null) {
      facts.add(MemoryFact(
        fact: '用户主修${majorMatch.group(2)}', timeAnchor: timeAnchor,
        confidence: 0.90, recordedAt: now, source: userInput,
      ));
    }
    // 学校
    if (userInput.contains('浙大') || userInput.contains('浙江大学')) {
      facts.add(MemoryFact(
        fact: '用户就读于浙江大学', timeAnchor: timeAnchor,
        confidence: 0.95, recordedAt: now, source: userInput,
      ));
    }
    // 风格偏好
    if (userInput.contains('简洁') || userInput.contains('简短')) {
      facts.add(MemoryFact(
        fact: '用户偏好简洁回答', timeAnchor: timeAnchor,
        confidence: 0.8, isStyleFact: true, recordedAt: now, source: userInput,
      ));
    }
    if (userInput.contains('详细') || userInput.contains('仔细')) {
      facts.add(MemoryFact(
        fact: '用户偏好详细解释', timeAnchor: timeAnchor,
        confidence: 0.8, isStyleFact: true, recordedAt: now, source: userInput,
      ));
    }

    // 筛选 + 存储到全局文件（置信度 >= 0.5）
    for (final f in facts) {
      if (f.confidence >= 0.5) {
        await _upsertGlobal(f);
      }
    }
  }

  Future<void> _upsertGlobal(MemoryFact fact) async {
    final key = fact.fact.hashCode.toRadixString(16);
    final file = File(p.join(_storeDir, '$key.json'));

    // 检查冲突：遍历已有文件，检测矛盾
    try {
      final dir = Directory(_storeDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final raw = await entity.readAsString();
              final existing = MemoryFact.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>);
              if (existing.contradicts(fact)) {
                await entity.delete();
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 存储新事实
    await file.writeAsString(jsonEncode(fact.toJson()));
  }

  /// 构建全局记忆注入块。
  Future<String> buildContext() async {
    await _ensureInit();
    final facts = <MemoryFact>[];
    try {
      final dir = Directory(_storeDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final raw = await entity.readAsString();
              facts.add(MemoryFact.fromJson(
                  jsonDecode(raw) as Map<String, dynamic>));
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (facts.isEmpty) return '';
    facts.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    final buf = StringBuffer();
    buf.writeln('## 全局记忆 (Global Memory — 跨会话持久化)');
    buf.writeln('以下是已确认的关于用户的客观事实（带时间锚定）：');
    for (final f in facts) {
      buf.writeln('- ${f.toPrompt()}');
      if (f.isStyleFact) buf.writeln('  (风格偏好，可灵活参考)');
    }
    buf.writeln('注意：如果用户提出与上述矛盾的新信息，以新信息为准更新。');
    return buf.toString();
  }
}
