import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/widgets/flashcard_view.dart';

void main() {
  group('parseFlashcards', () {
    test('空文本 → 空列表', () {
      expect(parseFlashcards(''), isEmpty);
    });

    test('无卡片结构的文本 → 空列表', () {
      expect(parseFlashcards('这是一段普通文本'), isEmpty);
    });

    test('单张卡片（问题+答案）', () {
      final result = parseFlashcards('## ❓ 问题\n1+1=?\n\n## 💡 答案\n2');
      expect(result.length, 1);
      expect(result[0].question, '1+1=?');
      expect(result[0].answer, '2');
    });

    test('多张卡片用 --- 分隔', () {
      const text = '---\n'
          '## ❓ 问题\nQ1\n\n## 💡 答案\nA1\n'
          '---\n'
          '## ❓ 问题\nQ2\n\n## 💡 答案\nA2\n'
          '---\n'
          '## ❓ 问题\nQ3\n\n## 💡 答案\nA3';
      final result = parseFlashcards(text);
      expect(result.length, 3);
      expect(result[0].question, 'Q1');
      expect(result[0].answer, 'A1');
      expect(result[1].question, 'Q2');
      expect(result[1].answer, 'A2');
      expect(result[2].question, 'Q3');
      expect(result[2].answer, 'A3');
    });

    test('多行问题和答案', () {
      final result = parseFlashcards(
        '## ❓ 问题\n第一行\n第二行\n\n## 💡 答案\n答案行1\n答案行2',
      );
      expect(result.length, 1);
      expect(result[0].question, '第一行\n第二行');
      expect(result[0].answer, '答案行1\n答案行2');
    });

    test('AI输出完整格式示例（带 --- 包裹）', () {
      const text = '---\n'
          '## ❓ 什么是康奈尔笔记法？\n'
          '\n'
          '## 💡 答案\n'
          '康奈尔笔记法是一种将页面分为**线索区**、**笔记区**和**总结区**的笔记方法。\n'
          '\n'
          '---\n'
          '## ❓ 知识卡片的格式要求？\n'
          '\n'
          '## 💡 答案\n'
          '每张卡片用 `---` 分隔，包含 `问题` 和 `答案` 两个部分。';
      final result = parseFlashcards(text);
      expect(result.length, 2);
      expect(result[0].question, '什么是康奈尔笔记法？');
      expect(result[0].answer, contains('康奈尔笔记法'));
      expect(result[1].question, '知识卡片的格式要求？');
      expect(result[1].answer, contains('---'));
    });

    test('不规范的标记格式也能解析', () {
      // 部分 AI 可能输出不同标记
      final result = parseFlashcards(
        '**问题**\nQ1\n\n**答案**\nA1\n\n---\n**问题**\nQ2\n\n**答案**\nA2',
      );
      expect(result.length, 2);
      expect(result[0].question, 'Q1');
      expect(result[0].answer, 'A1');
    });

    test('答案缺少数值 → 跳过该卡片', () {
      final result = parseFlashcards(
        '## ❓ 问题\nQ1\n\n## 💡 答案\nA1\n\n---\n## ❓ 问题\nQ2',
      );
      // Q2 缺少答案，应跳过
      expect(result.length, 1);
      expect(result[0].question, 'Q1');
    });

    test('问题缺少数值 → 跳过该卡片', () {
      final result = parseFlashcards(
        '## 💡 答案\nA1\n\n---\n## ❓ 问题\nQ2\n\n## 💡 答案\nA2',
      );
      // 第一张缺少问题，应跳过
      expect(result.length, 1);
      expect(result[0].question, 'Q2');
    });

    test('空卡片段被跳过', () {
      final result = parseFlashcards(
        '---\n---\n## ❓ 问题\nQ1\n\n## 💡 答案\nA1\n---\n---\n',
      );
      expect(result.length, 1);
    });

    test('markdown 加粗标记保留在内容中', () {
      final result = parseFlashcards(
        '## ❓ 问题\n**重要概念**是什么？\n\n## 💡 答案\n这是**核心**内容。',
      );
      expect(result.length, 1);
      expect(result[0].question, '**重要概念**是什么？');
      expect(result[0].answer, '这是**核心**内容。');
    });

    test('代码块内容保留', () {
      final result = parseFlashcards(
        '## ❓ 问题\n如何定义函数？\n\n## 💡 答案\n```dart\nvoid main() {}\n```',
      );
      expect(result.length, 1);
      expect(result[0].answer, contains('void main()'));
    });
  });
}
