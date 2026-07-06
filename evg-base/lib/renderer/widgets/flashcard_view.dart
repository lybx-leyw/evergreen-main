import 'package:flutter/material.dart';
import 'markdown_renderer.dart';
import 'evergreen_progress.dart';

/// 单张闪卡数据模型。
class Flashcard {
  final String question;
  final String answer;

  const Flashcard({required this.question, required this.answer});
}

/// 解析 AI 生成的卡片输出为 [Flashcard] 列表。
///
/// 格式：
/// ```
/// ---
/// ## ❓ 问题
/// 问题内容
///
/// ## 💡 答案
/// 答案内容
/// ---
/// ```
List<Flashcard> parseFlashcards(String text) {
  final result = <Flashcard>[];
  // 按独立成行的 --- 分隔卡片（行遍历，支持开头/中间/结尾）
  final segments = <String>[];
  {
    final buf = StringBuffer();
    for (final line in text.split('\n')) {
      if (line.trimLeft() == '---') {
        final content = buf.toString().trim();
        if (content.isNotEmpty) segments.add(content);
        buf.clear();
      } else {
        buf.writeln(line);
      }
    }
    final last = buf.toString().trim();
    if (last.isNotEmpty) segments.add(last);
  }

  for (final raw in segments) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    // 提取问题：## ❓ 问题 或 ## Q 或类似标记后的内容
    String? question;
    String? answer;

    final lines = trimmed.split('\n');
    var currentSection = '';
    final qLines = <String>[];
    final aLines = <String>[];

    for (final line in lines) {
      final stripped = line.trimLeft();
      if (stripped.startsWith('## ❓') || stripped.startsWith('## Q') ||
          stripped.startsWith('## 问题') || stripped.startsWith('❓') ||
          stripped.startsWith('**问题')) {
        currentSection = 'q';
        // 提取同一行上的问题文本（如 "## ❓ 什么是康奈尔笔记法？" → "什么是康奈尔笔记法？"）
        // 但如果只剩标签词（"问题"、"Q"等），不添加（内容在下一行）
        var rest = stripped;
        rest = rest.replaceFirst(RegExp(r'^\*\*问题\*\*'), '').trim();
        rest = rest.replaceFirst(RegExp(r'^##\s*'), '');
        rest = rest.replaceFirst(RegExp(r'^(❓|💡|Q|A)\s*'), '');
        rest = rest.replaceFirst(RegExp(r'^(问题|答案|Question|Answer)\s*'), '');
        rest = rest.trim();
        if (rest.isNotEmpty) {
          qLines.add(rest);
        }
        continue;
      }
      if (stripped.startsWith('## 💡') || stripped.startsWith('## A') ||
          stripped.startsWith('## 答案') || stripped.startsWith('💡') ||
          stripped.startsWith('**答案')) {
        currentSection = 'a';
        var rest = stripped;
        rest = rest.replaceFirst(RegExp(r'^\*\*答案\*\*'), '').trim();
        rest = rest.replaceFirst(RegExp(r'^##\s*'), '');
        rest = rest.replaceFirst(RegExp(r'^(💡|❓|Q|A)\s*'), '');
        rest = rest.replaceFirst(RegExp(r'^(答案|问题|Answer|Question)\s*'), '');
        rest = rest.trim();
        if (rest.isNotEmpty) {
          aLines.add(rest);
        }
        continue;
      }
      // 跳过空行和分隔线
      if (stripped.isEmpty || stripped == '---') continue;

      if (currentSection == 'q') {
        qLines.add(line);
      } else if (currentSection == 'a') {
        aLines.add(line);
      }
    }

    question = qLines.join('\n').trim();
    answer = aLines.join('\n').trim();

    if (question.isNotEmpty && answer.isNotEmpty) {
      result.add(Flashcard(question: question, answer: answer));
    }
  }
  return result;
}

/// 交互式闪卡视图：单点翻面，左右切换。
class FlashcardView extends StatefulWidget {
  final List<Flashcard> cards;

  const FlashcardView({super.key, required this.cards});

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flip() {
    if (_flipController.isCompleted) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    _isFlipped = !_isFlipped;
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.cards.length) return;
    setState(() {
      _currentIndex = index;
      _isFlipped = false;
      _flipController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.cards[_currentIndex];
    final theme = Theme.of(context);

    return Column(
      children: [
        // 进度指示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_currentIndex + 1} / ${widget.cards.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EvergreenProgress(
                  value: (_currentIndex + 1) / widget.cards.length,
                  semanticLabel: '闪卡进度：${_currentIndex + 1} / ${widget.cards.length}',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '第 ${_currentIndex + 1}/${widget.cards.length} 张',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // 卡片主体
        Expanded(
          child: GestureDetector(
            onTap: _flip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedBuilder(
                animation: _flipController,
                builder: (context, child) {
                  final angle = _flipController.value * 3.14159;
                  // 正面显示在 0°~90°，背面显示在 90°~180°
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        child: _buildFront(card),
                      ),
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle + 3.14159),
                        child: _buildBack(card),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

        // 底部导航
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _currentIndex > 0
                    ? () => _goTo(_currentIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '点击翻面',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                onPressed: _currentIndex < widget.cards.length - 1
                    ? () => _goTo(_currentIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFront(Flashcard card) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '问题',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: MarkdownRenderer(
                  text: card.question,
                  useCard: false,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(Flashcard card) {
    final theme = Theme.of(context);
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
            Icon(Icons.lightbulb, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '答案',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: MarkdownRenderer(
                  text: card.answer,
                  useCard: false,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
