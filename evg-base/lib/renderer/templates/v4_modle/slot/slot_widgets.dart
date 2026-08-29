/// Slot 组件适配器 —— 将 `renderer/widgets/` 中的原子组件桥接到 SlotDispatch。
///
/// 对应 PLAN_NOW §四 的 53 个组件类型中，部分已有 `widgets/` 实现但未接入 SlotDispatch。
/// 本文件提供适配层，接受 `ComponentDescriptor` + `PageEventBus`，渲染实际 widget。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/data/data.dart' show DataOrchestrator;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/type_check_input.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/flashcard_view.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/mindmap_widget.dart';

/// 契约①定时刷新写侧：对 `orch://<name>` 端点经中枢强制重抓并覆写缓存。
/// 未注册/拉取失败静默（随后 [resolveDataSource] 读缓存时优雅降级）。
Future<void> _refreshCacheWrite(
    DataSourceDescriptor ds, DataOrchestrator orch) async {
  final ep = ds.endpoint;
  if (ep == null || !ep.startsWith('orch://')) return;
  try {
    await orch.refreshByName(ep.substring('orch://'.length));
  } catch (_) {/* 契约①：刷新失败不阻塞 UI，读侧仍缓存优先 */}
}

// ═══════ TypeCheckSlot ═══════

/// 打字背词模式 slot 组件。
///
/// 从 config.wordList 加载词库，按 mode 显示中文/英文释义，
/// 用户对照输入。完成时通过 EventBus 发出 word_completed 事件。
class TypeCheckSlot extends StatefulWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final PageEventBus? pageEventBus;
  final String moduleId;

  const TypeCheckSlot({
    super.key,
    required this.slotKey,
    required this.config,
    this.pageEventBus,
    required this.moduleId,
  });

  @override
  State<TypeCheckSlot> createState() => _TypeCheckSlotState();
}

class _TypeCheckSlotState extends State<TypeCheckSlot> {
  final _inputCtrl = TextEditingController();
  List<Map<String, dynamic>> _words = [];
  int _currentIndex = 0;
  String _mode = 'chinese-to-english';
  bool _shuffle = true;
  String _feedback = '';
  int _correctCount = 0;
  int _wrongCount = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final cfg = widget.config.config;
    _mode = cfg['mode'] as String? ?? 'chinese-to-english';
    _shuffle = cfg['shuffle'] as bool? ?? true;
    _loadWords(cfg['wordList']);
  }

  void _loadWords(dynamic wordList) {
    final inline = extractWordList(wordList);
    if (inline != null && inline.isNotEmpty) {
      _words = inline;
      if (_shuffle) _words.shuffle();
      setState(() {});
      return;
    }
    _loadWordsFromFile(wordList is String ? wordList : 'words.json');
  }

  void _loadWordsFromFile(String wordListFile) {
    try {
      final wsDir = greenixWorkspaceDir(widget.moduleId);
      final file = File(p.join(wsDir, wordListFile));
      if (!file.existsSync()) {
        debugPrint('[TypeCheckSlot] 词库未找到: ${file.path}');
        setState(() => _feedback = '词库文件未找到: $wordListFile');
        return;
      }
      final json = jsonDecode(file.readAsStringSync()) as List;
      _words = json.cast<Map<String, dynamic>>();
      if (_shuffle) _words.shuffle();
      setState(() {});
    } catch (e) {
      setState(() => _feedback = '加载词库失败: $e');
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _currentWord =>
      _currentIndex < _words.length ? _words[_currentIndex] : null;

  void _checkAnswer() {
    final word = _currentWord;
    if (word == null || _finished) return;

    final input = _inputCtrl.text.trim();
    if (input.isEmpty) return;

    final correct = _mode == 'chinese-to-english'
        ? (input.toLowerCase() == (word['word'] as String).toLowerCase())
        : (input == word['meaning'] as String);

    if (correct) {
      _correctCount++;
      setState(() => _feedback = '✅ 正确！');
      _emitEvent('answer_correct', {'word': word['word'], 'meaning': word['meaning']});

      if (_currentIndex + 1 < _words.length) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          setState(() {
            _currentIndex++;
            _inputCtrl.clear();
            _feedback = '';
          });
        });
      } else {
        setState(() {
          _finished = true;
          _feedback = '🎉 全部完成！正确 $_correctCount / ${_words.length}';
        });
        _emitEvent('word_completed', {
          'total': _words.length,
          'correct': _correctCount,
          'wrong': _wrongCount,
        });
      }
    } else {
      _wrongCount++;
      final expected = _mode == 'chinese-to-english'
          ? word['word'] as String
          : word['meaning'] as String;
      setState(() => _feedback = '❌ 错误！正确答案: $expected');
      _emitEvent('answer_wrong', {
        'word': word['word'],
        'meaning': word['meaning'],
        'input': input,
      });
    }
  }

  void _emitEvent(String eventName, Map<String, dynamic> data) {
    widget.pageEventBus?.emit(eventName, sourceSlot: widget.slotKey, data: data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = _currentWord;

    if (_words.isEmpty) {
      return _buildPlaceholder(context, '📚 加载词库中...', _feedback);
    }

    if (_finished) {
      return _buildFinishedView(theme);
    }

    final meaning = (word?['meaning'] as String?) ?? '';
    final engWord = (word?['word'] as String?) ?? '';
    final prompt = _mode == 'chinese-to-english' ? meaning : engWord;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 进度
          Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '打字学习 (${_currentIndex + 1}/${_words.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '✅$_correctCount  ❌$_wrongCount',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 提示词
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              prompt,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),

          // 输入框
          TextField(
            controller: _inputCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _mode == 'chinese-to-english' ? '输入对应的英文单词...' : '输入对应的中文含义...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_circle),
                onPressed: _checkAnswer,
              ),
            ),
            onSubmitted: (_) => _checkAnswer(),
          ),
          const SizedBox(height: 8),

          // 反馈
          if (_feedback.isNotEmpty)
            Text(
              _feedback,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _feedback.startsWith('✅') ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFinishedView(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
          const SizedBox(height: 16),
          Text(
            '学习完成！',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '正确: $_correctCount / ${_words.length}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _currentIndex = 0;
                _correctCount = 0;
                _wrongCount = 0;
                _finished = false;
                _feedback = '';
                _inputCtrl.clear();
                if (_shuffle) _words.shuffle();
              });
              _emitEvent('reset_round', {'words': _words.length});
            },
            icon: const Icon(Icons.replay),
            label: const Text('再来一轮'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.book, size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ═══════ FlashcardsSlot ═══════

/// 从 [config.wordList] 内联列表或数据源返回值中提取词库列表。
/// 支持 `List<Map>` 直接内联，或 `{wordList:[...]}` 的 Map。
List<Map<String, dynamic>>? extractWordList(dynamic resolved) {
  List? rawList;
  if (resolved is List) {
    rawList = resolved;
  } else if (resolved is Map && resolved['wordList'] is List) {
    rawList = resolved['wordList'] as List;
  }
  if (rawList == null) return null;
  return rawList
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

/// 闪卡复习 slot 组件。
///
/// 词库来源（M2 P2）：
/// - 有 `config.dataSource` → 经 [resolveDataSource] 拉取 `{wordList:[...]}` 或直接 `List`；
/// - 否则回退 `config.wordList`（本地工作区文件名）加载。
/// 展示为闪卡（正面=释义，背面=单词），用户标记"认识"/"不认识"，经 EventBus 发状态事件。
class FlashcardsSlot extends ConsumerStatefulWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final PageEventBus? pageEventBus;
  final String moduleId;

  const FlashcardsSlot({
    super.key,
    required this.slotKey,
    required this.config,
    this.pageEventBus,
    required this.moduleId,
  });

  @override
  ConsumerState<FlashcardsSlot> createState() => _FlashcardsSlotState();
}

class _FlashcardsSlotState extends ConsumerState<FlashcardsSlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  bool _isFlipped = false;
  List<Map<String, dynamic>> _words = [];
  int _currentIndex = 0;
  int _knownCount = 0;
  int _forgottenCount = 0;
  bool _finished = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _loadWords();
    final ds = widget.config.dataSource;
    if (ds != null && ds.refreshInterval > 0) {
        _refreshTimer = Timer.periodic(Duration(seconds: ds.refreshInterval), (_) {
        if (!mounted || _finished) return;
        _loadFromDataSource(ds, forceRefresh: true);
      });
    }
  }

  void _loadWords() {
    final ds = widget.config.dataSource;
    if (ds != null) {
      _loadFromDataSource(ds);
    } else {
      _loadFromFile();
    }
  }

  /// 经数据源拉取词库；失败/为空则优雅降级回本地文件。
  /// [forceRefresh] 为 true 时先经中枢强制重抓写缓存，再缓存优先读（契约①）。
  Future<void> _loadFromDataSource(DataSourceDescriptor ds,
      {bool forceRefresh = false}) async {
    try {
      final orch = ref.read(dataOrchestratorProvider);
      if (forceRefresh) {
        await _refreshCacheWrite(ds, orch); // 写侧：强制重抓写缓存
      }
      final resolved = await resolveDataSource(ds: ds, orch: orch); // 读侧：缓存优先
      final words = extractWordList(resolved);
      if (words != null && words.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _words = words;
          _words.shuffle();
        });
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    _loadFromFile();
  }

  void _loadFromFile() {
    final cfg = widget.config.config;
    final wordList = cfg['wordList'];
    // 优先内联词表
    final inline = extractWordList(wordList);
    if (inline != null && inline.isNotEmpty) {
      _words = inline;
      _words.shuffle();
      setState(() {});
      return;
    }
    final wordListFile = wordList as String? ?? 'words.json';
    try {
      final wsDir = greenixWorkspaceDir(widget.moduleId);
      final file = File(p.join(wsDir, wordListFile));
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as List;
      _words = json.cast<Map<String, dynamic>>();
      _words.shuffle();
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _flipCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _currentWord =>
      _currentIndex < _words.length ? _words[_currentIndex] : null;

  void _flip() {
    setState(() => _isFlipped = !_isFlipped);
    if (_isFlipped) {
      _flipCtrl.forward();
      _emitEvent('card_flipped', {'word': _currentWord?['word']});
    } else {
      _flipCtrl.reverse();
    }
  }

  void _markKnown() {
    _knownCount++;
    _emitEvent('card_known', {
      'word': _currentWord?['word'],
      'meaning': _currentWord?['meaning'],
    });
    _nextCard();
  }

  void _markForgotten() {
    _forgottenCount++;
    _emitEvent('card_forgotten', {
      'word': _currentWord?['word'],
      'meaning': _currentWord?['meaning'],
    });
    // 将忘记的单词放回队尾
    if (_currentWord != null) {
      _words.add(_currentWord!);
    }
    _nextCard();
  }

  void _nextCard() {
    if (_currentIndex + 1 < _words.length) {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
        _flipCtrl.reset();
      });
    } else {
      setState(() => _finished = true);
    }
  }

  void _emitEvent(String eventName, Map<String, dynamic> data) {
    widget.pageEventBus?.emit(eventName, sourceSlot: widget.slotKey, data: data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = _currentWord;

    if (_words.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.style, size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('加载词库中...', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    if (_finished) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text('复习完成！', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('认识: $_knownCount  忘记: $_forgottenCount',
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _currentIndex = 0;
                  _knownCount = 0;
                  _forgottenCount = 0;
                  _finished = false;
                  _isFlipped = false;
                  _flipCtrl.reset();
                  _words.shuffle();
                });
              },
              icon: const Icon(Icons.replay),
              label: const Text('重新复习'),
            ),
          ],
        ),
      );
    }

    final meaning = word?['meaning'] as String? ?? '';
    final engWord = word?['word'] as String? ?? '';
    final phonetic = word?['phonetic'] as String? ?? '';
    final example = word?['example'] as String? ?? '';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 进度
            Row(
              children: [
                Icon(Icons.style, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '闪卡复习 (${_currentIndex + 1}/${_words.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text('认识:$_knownCount  忘记:$_forgottenCount',
                    style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 16),

            // 闪卡
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
              child: GestureDetector(
                onTap: _flip,
                child: AnimatedBuilder(
                  animation: _flipCtrl,
                builder: (context, child) {
                  final angle = _flipCtrl.value * 3.14159;
                  final showFront = _flipCtrl.value < 0.5;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 正面：中文释义（翻转前半程可见，避免背面镜像）
                      Opacity(
                        opacity: showFront ? 1.0 : 0.0,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: _buildCardFace(
                            theme,
                            meaning,
                            '释义',
                            Icons.translate,
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      // 背面：英文单词（翻转后半程可见，此时角度已过正面→不镜像）
                      Opacity(
                        opacity: showFront ? 0.0 : 1.0,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle + 3.14159),
                          child: _buildCardBack(theme, engWord, phonetic, example),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _markForgotten,
                icon: const Icon(Icons.do_not_disturb, color: Colors.red),
                label: const Text('忘记了'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _markKnown,
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('认识了'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildCardFace(ThemeData theme, String text, String label,
      IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(label, style: theme.textTheme.labelLarge?.copyWith(
              color: color, fontWeight: FontWeight.w600, letterSpacing: 1,
            )),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  text,
                  style: theme.textTheme.headlineSmall?.copyWith(height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('点击翻面查看答案',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBack(ThemeData theme, String word, String phonetic, String example) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.primaryContainer,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.spellcheck, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('单词', style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 12),
            Text(word, style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 1,
            )),
            if (phonetic.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(phonetic, style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary, fontStyle: FontStyle.italic,
              )),
            ],
            if (example.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(example, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic,
              ), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════ MindmapSlot ═══════

/// 思维导图 slot 组件。
///
/// 从 config.content 或 config.src 加载缩进文本，渲染为可视化节点图。
class MindmapSlot extends StatelessWidget {
  final String slotKey;
  final ComponentDescriptor config;

  const MindmapSlot({
    super.key,
    required this.slotKey,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final content = _extractContent(config.config);
    if (content.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree, size: 32,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text('在 config 中设置 content 字段来显示思维导图'),
          ],
        ),
      );
    }

    // 使用 mainAxisSize.max + Expanded 确保 MindMapWidget 严格受限，
    // 避免 Column(min) 结合 LayoutBuilder 导致 "BOTTOM OVERFLOWED" 溢出。
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('思维导图', style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: MindMapWidget(text: content),
          ),
        ],
      ),
    );
  }

  static String _extractContent(Map<String, dynamic> config) {
    if (config case {'content': String content}) return content;
    if (config case {'src': String src}) return 'mindmap\n$src';
    return '';
  }
}

// ═══════ QuizSlot ═══════

/// 综合测验 slot 组件。
///
/// 支持三种题型：
/// - **multiple-choice**: 显示中文释义，4 选 1 英文单词
/// - **fill-blank**: 显示中文释义，用户拼写单词（类似 type-check）
/// - **match-pairs**: 左右两列，拖拽匹配（简化：按钮点选）
///
/// 通过 config.questionTypes 指定启用的题型列表，
/// config.timeLimit 设置总时限（秒），config.passScore 设置及格分（百分制）。
/// 通过 EventBus 发出 test_started / question_answered / test_completed 事件。
class QuizSlot extends ConsumerStatefulWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final PageEventBus? pageEventBus;
  final String moduleId;

  const QuizSlot({
    super.key,
    required this.slotKey,
    required this.config,
    this.pageEventBus,
    required this.moduleId,
  });

  @override
  ConsumerState<QuizSlot> createState() => _QuizSlotState();
}

class _QuizSlotState extends ConsumerState<QuizSlot> {
  // 词库
  List<Map<String, dynamic>> _words = [];

  // 题型配置
  List<String> _questionTypes = ['multiple-choice', 'fill-blank'];
  int _timeLimitSec = 300;
  int _passScore = 80;

  // 测验状态
  bool _started = false;
  bool _finished = false;
  int _correctCount = 0;
  int _wrongCount = 0;

  // 当前题目
  int _questionIndex = 0;
  String _currentType = 'multiple-choice';

  // 选择题选项
  List<String> _choices = [];
  int? _selectedChoice;

  // 填空题
  final _fillCtrl = TextEditingController();
  String _fillFeedback = '';

  // 配对题
  List<MapEntry<String, String>> _pairs = [];
  String? _selectedLeft;
  String? _selectedRight;
  int _matchScore = 0;

  // 倒计时
  int _remainingSec = 0;
  Timer? _timer;

  // dataSource 自动刷新（refreshInterval）
  Timer? _refreshTimer;

  // 答题记录
  final List<Map<String, dynamic>> _answerLog = [];

  @override
  void initState() {
    super.initState();
    _parseConfig();
    _loadWords();
    final ds = widget.config.dataSource;
    if (ds != null && ds.refreshInterval > 0) {
        _refreshTimer = Timer.periodic(Duration(seconds: ds.refreshInterval), (_) {
        if (!mounted || _started) return;
        _loadFromDataSource(ds, forceRefresh: true);
      });
    }
  }

  void _parseConfig([Map<String, dynamic>? override]) {
    final cfg = override ?? widget.config.config;
    if (cfg['questionTypes'] is List) {
      _questionTypes = (cfg['questionTypes'] as List).cast<String>();
    }
    if (cfg['timeLimit'] != null) {
      _timeLimitSec = (cfg['timeLimit'] as num?)?.toInt() ?? _timeLimitSec;
    }
    if (cfg['passScore'] != null) {
      _passScore = (cfg['passScore'] as num?)?.toInt() ?? _passScore;
    }
  }

  void _loadWords() {
    final ds = widget.config.dataSource;
    if (ds != null) {
      _loadFromDataSource(ds);
    } else {
      _loadFromFile();
    }
  }

  /// 经数据源拉取 `{wordList, questionTypes, timeLimit, passScore}`；
  /// 失败/为空则优雅降级回本地文件。
  /// [forceRefresh] 为 true 时先经中枢强制重抓写缓存，再缓存优先读（契约①）。
  Future<void> _loadFromDataSource(DataSourceDescriptor ds,
      {bool forceRefresh = false}) async {
    try {
      final orch = ref.read(dataOrchestratorProvider);
      if (forceRefresh) {
        await _refreshCacheWrite(ds, orch); // 写侧：强制重抓写缓存
      }
      final resolved = await resolveDataSource(ds: ds, orch: orch); // 读侧：缓存优先
      // Map 形态可同时携带题型/时限/及格分配置。
      if (resolved is Map<String, dynamic>) {
        _parseConfig(resolved);
      }
      final words = extractWordList(resolved);
      if (words != null && words.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _words = words;
          if (_words.length > 10) _words.shuffle();
        });
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    _loadFromFile();
  }

  void _loadFromFile() {
    final cfg = widget.config.config;
    final wordList = cfg['wordList'];
    final inline = extractWordList(wordList);
    if (inline != null && inline.isNotEmpty) {
      _words = inline;
      if (_words.length > 10) _words.shuffle();
      setState(() {});
      return;
    }
    final wordListFile = wordList as String? ?? 'words.json';
    try {
      final wsDir = greenixWorkspaceDir(widget.moduleId);
      final file = File(p.join(wsDir, wordListFile));
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as List;
      _words = json.cast<Map<String, dynamic>>();
      if (_words.length > 10) _words.shuffle();
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _timer?.cancel();
    _fillCtrl.dispose();
    super.dispose();
  }

  // ── 事件发射 ──

  void _emitEvent(String eventName, Map<String, dynamic> data) {
    widget.pageEventBus?.emit(eventName, sourceSlot: widget.slotKey, data: data);
  }

  // ── 开始测验 ──

  void _startTest() {
    setState(() {
      _started = true;
      _finished = false;
      _correctCount = 0;
      _wrongCount = 0;
      _questionIndex = 0;
      _remainingSec = _timeLimitSec;
      _answerLog.clear();
      _words.shuffle();
      _nextQuestion();
    });
    _emitEvent('test_started', {
      'totalQuestions': _words.length,
      'timeLimit': _timeLimitSec,
      'passScore': _passScore,
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSec <= 0) {
        _timer?.cancel();
        _finishTest();
        return;
      }
      setState(() => _remainingSec--);
    });
  }

  // ── 生成下一题 ──

  void _nextQuestion() {
    if (_questionIndex >= _words.length) {
      _finishTest();
      return;
    }
    // 随机选题型
    _currentType = _questionTypes[_questionIndex % _questionTypes.length];

    setState(() {
      _selectedChoice = null;
      _fillFeedback = '';
      _fillCtrl.clear();
      _selectedLeft = null;
      _selectedRight = null;
      if (_currentType == 'multiple-choice') _generateChoices();
      if (_currentType == 'match-pairs') _generatePairs();
    });
  }

  // ═══════ 选择题 ═══════

  void _generateChoices() {
    final correct = _words[_questionIndex]['word'] as String? ?? '';
    final others = _words
        .where((w) => w['word'] != correct)
        .map((w) => w['word'] as String? ?? '')
        .where((w) => w.isNotEmpty)
        .toList();
    others.shuffle();
    _choices = [correct, ...others.take(3)];
    _choices.shuffle();
  }

  void _answerChoice(int index) {
    if (_selectedChoice != null) return;
    final correct = _words[_questionIndex]['word'] as String? ?? '';
    final isCorrect = _choices[index] == correct;
    setState(() {
      _selectedChoice = index;
      if (isCorrect) _correctCount++; else _wrongCount++;
    });
    _answerLog.add({
      'type': 'multiple-choice',
      'word': correct,
      'meaning': _words[_questionIndex]['meaning'],
      'correct': isCorrect,
    });
    _emitEvent('question_answered', {
      'type': 'multiple-choice',
      'word': correct,
      'correct': isCorrect,
      'index': _questionIndex,
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _questionIndex++);
        _nextQuestion();
      }
    });
  }

  // ═══════ 填空题 ═══════

  void _checkFill() {
    final correct = _words[_questionIndex]['word'] as String? ?? '';
    final input = _fillCtrl.text.trim();
    if (input.isEmpty) return;
    final isCorrect = input.toLowerCase() == correct.toLowerCase();
    setState(() {
      _fillFeedback = isCorrect ? '✅ 正确！' : '❌ 答案是: $correct';
      if (isCorrect) _correctCount++; else _wrongCount++;
    });
    _answerLog.add({
      'type': 'fill-blank',
      'word': correct,
      'meaning': _words[_questionIndex]['meaning'],
      'input': input,
      'correct': isCorrect,
    });
    _emitEvent('question_answered', {
      'type': 'fill-blank',
      'word': correct,
      'input': input,
      'correct': isCorrect,
      'index': _questionIndex,
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _questionIndex++);
        _nextQuestion();
      }
    });
  }

  // ═══════ 配对题 ═══════

  void _generatePairs() {
    final word = _words[_questionIndex];
    _pairs = [
      MapEntry('释义', word['meaning'] as String? ?? ''),
      MapEntry('音标', word['phonetic'] as String? ?? ''),
      MapEntry('例句', word['example'] as String? ?? ''),
    ];
    // 只保留有值的
    _pairs.removeWhere((e) => e.value.isEmpty);
    _matchScore = 0;
  }

  void _selectLeft(String key) {
    setState(() => _selectedLeft = key);
  }

  void _selectRight(String value) {
    if (_selectedLeft != null) {
      final matched = _pairs.any((p) => p.key == _selectedLeft && p.value == value);
      if (matched) _matchScore++;
      setState(() {
        _selectedLeft = null;
      });
      if (_matchScore >= _pairs.length) {
        _correctCount++;
        _answerLog.add({
          'type': 'match-pairs',
          'word': _words[_questionIndex]['word'],
          'matches': _matchScore,
        });
        _emitEvent('question_answered', {
          'type': 'match-pairs',
          'word': _words[_questionIndex]['word'],
          'matches': _matchScore,
          'total': _pairs.length,
          'index': _questionIndex,
        });
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() => _questionIndex++);
            _nextQuestion();
          }
        });
      }
    }
  }

  // ═══════ 结束 ═══════

  void _finishTest() {
    _timer?.cancel();
    final total = _correctCount + _wrongCount;
    final score = total > 0 ? (_correctCount / total * 100).round() : 0;
    final passed = score >= _passScore;
    setState(() => _finished = true);
    _emitEvent('test_completed', {
      'score': score,
      'correct': _correctCount,
      'wrong': _wrongCount,
      'total': total,
      'passed': passed,
      'passScore': _passScore,
      'answerLog': _answerLog,
    });
  }

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_words.isEmpty) {
      return Center(
        child: Text('词库为空，请在 .greenix/workspaces/vocab-tutor/words.json 中添加单词'),
      );
    }

    if (!_started) {
      return _buildStartView(theme);
    }

    if (_finished) {
      return _buildResultView(theme);
    }

    return _buildQuestionView(theme);
  }

  Widget _buildStartView(ThemeData theme) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('综合测验', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('共 ${_words.length} 题 · 时限 ${_timeLimitSec}秒 · 及格 ${_passScore}分',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('题型: ${_questionTypes.map((t) => _typeLabel(t)).join('、')}',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始测验'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(ThemeData theme) {
    final total = _correctCount + _wrongCount;
    final score = total > 0 ? (_correctCount / total * 100).round() : 0;
    final passed = score >= _passScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            passed ? Icons.emoji_events : Icons.sentiment_dissatisfied,
            size: 64,
            color: passed ? Colors.amber : Colors.orange,
          ),
          const SizedBox(height: 16),
          Text(
            passed ? '测验通过！' : '继续加油！',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: passed ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text('得分: $score 分', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('正确: $_correctCount  错误: $_wrongCount  共: $total 题',
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: score / 100,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: passed ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 24),

          // 答题明细
          if (_answerLog.isNotEmpty) ...[
            Text('答题记录', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...(_answerLog.asMap().entries.map((e) {
              final a = e.value;
              final isCorrect = a['correct'] == true;
              return ListTile(
                dense: true,
                leading: Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? Colors.green : Colors.red,
                  size: 20,
                ),
                title: Text(
                  '${e.key + 1}. ${a['word']} (${_typeLabel(a['type'] as String)})',
                  style: theme.textTheme.bodySmall,
                ),
              );
            })),
          ],

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _started = false;
                _finished = false;
                _correctCount = 0;
                _wrongCount = 0;
                _questionIndex = 0;
                _answerLog.clear();
                _words.shuffle();
              });
            },
            icon: const Icon(Icons.replay),
            label: const Text('重新测验'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionView(ThemeData theme) {
    final word = _questionIndex < _words.length ? _words[_questionIndex] : null;
    if (word == null) {
      _finishTest();
      return const SizedBox();
    }

    final meaning = word['meaning'] as String? ?? '';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部状态栏
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _typeLabel(_currentType),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_questionIndex + 1}/${_words.length}',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(Icons.timer, size: 16,
                    color: _remainingSec <= 30 ? Colors.red : theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('${_remainingSec ~/ 60}:${(_remainingSec % 60).toString().padLeft(2, '0')}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _remainingSec <= 30 ? Colors.red : null,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _questionIndex / _words.length,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 16),

            // 题目
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(meaning, style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600, height: 1.3,
                    ), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text('请回答对应的英文单词',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            // 答题区域
            _buildAnswerArea(theme, word),

            // 底部得分
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text('$_correctCount', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
                const SizedBox(width: 16),
                Icon(Icons.cancel, size: 16, color: Colors.red),
                const SizedBox(width: 4),
                Text('$_wrongCount', style: theme.textTheme.bodySmall?.copyWith(color: Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerArea(ThemeData theme, Map<String, dynamic> word) {
    switch (_currentType) {
      case 'fill-blank':
        return _buildFillBlank(theme);
      case 'match-pairs':
        return _buildMatchPairs(theme);
      case 'multiple-choice':
      default:
        return _buildMultipleChoice(theme);
    }
  }

  Widget _buildMultipleChoice(ThemeData theme) {
    return Column(
      children: List.generate(_choices.length, (i) {
        final isSelected = _selectedChoice == i;
        final isCorrect = _choices[i] == (_words[_questionIndex]['word'] as String? ?? '');
        final showResult = _selectedChoice != null;

        Color? bgColor;
        if (showResult) {
          if (isCorrect) bgColor = Colors.green.withValues(alpha: 0.2);
          else if (isSelected) bgColor = Colors.red.withValues(alpha: 0.2);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _selectedChoice == null ? () => _answerChoice(i) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                backgroundColor: bgColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(
                  color: showResult
                      ? (isCorrect ? Colors.green : (isSelected ? Colors.red : theme.colorScheme.outlineVariant))
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Text('${'ABCD'[i]}. ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Expanded(child: Text(_choices[i], style: theme.textTheme.titleMedium)),
                  if (showResult && isCorrect)
                    const Icon(Icons.check, color: Colors.green),
                  if (showResult && isSelected && !isCorrect)
                    const Icon(Icons.close, color: Colors.red),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFillBlank(ThemeData theme) {
    return Column(
      children: [
        TextField(
          controller: _fillCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入单词...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: _fillFeedback.isEmpty
                ? IconButton(icon: const Icon(Icons.check), onPressed: _checkFill)
                : null,
          ),
          onSubmitted: (_) => _checkFill(),
          enabled: _fillFeedback.isEmpty,
        ),
        if (_fillFeedback.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _fillFeedback,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _fillFeedback.startsWith('✅') ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMatchPairs(ThemeData theme) {
    final leftKeys = _pairs.map((p) => p.key).toList();
    final rightValues = _pairs.map((p) => p.value).toList()..shuffle();
    final matched = <String>{};

    return Row(
      children: [
        // 左侧：标签
        Expanded(
          child: Column(
            children: leftKeys.map((key) {
              final isSelected = _selectedLeft == key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _selectLeft(key),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isSelected
                          ? theme.colorScheme.primaryContainer
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(key, style: theme.textTheme.titleSmall),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 16),
        // 右侧：值
        Expanded(
          child: Column(
            children: rightValues.map((value) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _selectRight(value),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(value, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'multiple-choice': return '单选题';
      case 'fill-blank': return '填空题';
      case 'match-pairs': return '配对题';
      default: return type;
    }
  }
}
