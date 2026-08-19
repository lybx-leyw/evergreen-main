/// AskTool 单元测试（A11 移植验证）。
///
/// 覆盖：
/// 1. headless（无 Asker）→ 返回模型假设回退，不阻塞
/// 2. 参数校验：无 questions / 少于 2 选项 / 空 label / 重复 label
/// 3. Asker 交互：多选/单选 → formatAnswers 格式正确
/// 4. 用户关闭（无回答）→ 显式停止信号（"不要替我做决定"）
/// 5. readOnly == true
library;

import 'package:test/test.dart';

import '../event.dart';
import '../tools/ask_tool.dart';

void main() {
  group('AskTool headless（无 Asker）', () {
    test('无 Asker 返回模型假设回退，不阻塞', () async {
      final tool = AskTool();
      final result = await tool.execute({
        'questions': [
          {
            'header': '方案',
            'question': '选哪个方案？',
            'options': [
              {'label': 'A'},
              {'label': 'B'},
            ],
          },
        ],
      });
      expect(result, contains('模型假设回退'));
      expect(result, contains('不是用户回答'));
    });

    test('readOnly == true（提问无副作用，永不需批准）', () {
      final tool = AskTool();
      expect(tool.readOnly, isTrue);
    });
  });

  group('AskTool 参数校验', () {
    test('无 questions → error', () async {
      final tool = AskTool();
      final result = await tool.execute({'questions': []});
      expect(result, contains('[error:'));
    });

    test('问题少于 2 选项 → error', () async {
      final tool = AskTool();
      final result = await tool.execute({
        'questions': [
          {
            'header': 'x',
            'question': 'q',
            'options': [
              {'label': 'A'},
            ],
          },
        ],
      });
      expect(result, contains('[error:'));
    });

    test('空 label → error', () async {
      final tool = AskTool();
      final result = await tool.execute({
        'questions': [
          {
            'header': 'x',
            'question': 'q',
            'options': [
              {'label': ''},
              {'label': 'B'},
            ],
          },
        ],
      });
      expect(result, contains('[error:'));
    });

    test('重复 label → error', () async {
      final tool = AskTool();
      final result = await tool.execute({
        'questions': [
          {
            'header': 'x',
            'question': 'q',
            'options': [
              {'label': 'A'},
              {'label': 'A'},
            ],
          },
        ],
      });
      expect(result, contains('[error:'));
    });
  });

  group('AskTool 与 Asker 交互', () {
    test('用户回答 → formatAnswers 输出选择', () async {
      final tool = AskTool(asker: _FakeAsker([
        const AskAnswer(questionId: 'q1', selected: ['A']),
      ]));
      final result = await tool.execute({
        'questions': [
          {
            'header': '方案',
            'question': '选哪个方案？',
            'options': [
              {'label': 'A', 'description': '推荐'},
              {'label': 'B'},
            ],
          },
        ],
      });
      expect(result, contains('用户回答：'));
      expect(result, contains('- 方案: A'));
    });

    test('用户关闭（无回答）→ 显式停止信号', () async {
      final tool = AskTool(asker: _FakeAsker([]));
      final result = await tool.execute({
        'questions': [
          {
            'header': '方案',
            'question': '选哪个方案？',
            'options': [
              {'label': 'A'},
              {'label': 'B'},
            ],
          },
        ],
      });
      expect(result, contains('不要替我做决定'));
      expect(result, contains('停下来等待用户'));
    });

    test('多选问题：multiSelect 保留多个选择', () async {
      final tool = AskTool(asker: _FakeAsker([
        const AskAnswer(questionId: 'q1', selected: ['A', 'C']),
      ]));
      final result = await tool.execute({
        'questions': [
          {
            'header': '标签',
            'question': '选择标签（可多选）？',
            'multiSelect': true,
            'options': [
              {'label': 'A'},
              {'label': 'B'},
              {'label': 'C'},
            ],
          },
        ],
      });
      expect(result, contains('- 标签: A, C'));
    });
  });
}

/// 固定回答的假 Asker。
class _FakeAsker implements Asker {
  final List<AskAnswer> answers;
  _FakeAsker(this.answers);

  @override
  Future<List<AskAnswer>> ask(AskRequest request) async {
    return answers;
  }
}
