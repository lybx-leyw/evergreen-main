/// AskTool — AI 结构化提问用户（移植自 reasonix/internal/agent/ask.go）。
///
/// 让模型在遇到真正属于用户的决策分叉时（选哪个库、哪种方案、范围边界），
/// 以结构化多选（1-4 问）而非散文提问，前端渲染可选项，用户选择后作为工具
/// 结果返回。通过 [Asker] 接口到达 UI；无 Asker（headless 运行）时返回显式
/// 的"模型假设回退"，自主运行永不阻塞、也不假装用户已作答。
library;

import 'dart:convert';

import '../event.dart';
import '../tool.dart';

/// Asker — 把一批结构化问题提交给用户并取回回答。
///
/// 由 UI 层实现（弹窗渲染 AskOption），core 层只定义接口保持纯 Dart。
/// 无实现（headless）时 [AskTool] 返回模型假设回退。
abstract class Asker {
  /// 返回与 [questions] 一一对应的回答；用户完全关闭时不返回任何回答
  /// （长度可为 0，由 [AskTool] 解释为"不要替我做决定"）。
  Future<List<AskAnswer>> ask(AskRequest request);
}

/// AskTool：模型向用户提 1-4 个多选问题。
///
/// 直接实现 [Tool]（非 SimpleTool）以保留实例字段 [asker] 的访问能力。
class AskTool extends Tool {
  /// 可选的用户交互实现（UI 层注入）。
  final Asker? asker;

  AskTool({this.asker});

  @override
  String get name => 'ask';

  @override
  String get description =>
      '当你遇到真正属于用户决策的分叉（选哪个方案/库/范围），'
      '且无法从请求、代码或合理默认值中自行解决时，向用户提 1-4 个'
      '结构化多选问题。前端展示选项供用户选择，选择结果返回给你。'
      '优先于用散文提问。有明显默认值的决策不要用它——选合理默认继续。'
      '每个问题含 header（短标签）、question（问题文本）、'
      '2-4 个 options（label + 可选 description，推荐项放第一个）、'
      'multiSelect（是否可多选）。';

  @override
  Map<String, dynamic> get schema => const {
        'type': 'object',
        'properties': {
          'questions': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 4,
            'description': '1-4 个问题一起问。',
            'items': {
              'type': 'object',
              'properties': {
                'header': {
                  'type': 'string',
                  'description': '问题短标签（tab 标题），如 "方案"。',
                },
                'question': {
                  'type': 'string',
                  'description': '完整问题文本。',
                },
                'options': {
                  'type': 'array',
                  'minItems': 2,
                  'maxItems': 4,
                  'description': '选项，推荐项放第一个。',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'label': {
                        'type': 'string',
                        'description': '选项文本（简洁）。',
                      },
                      'description': {
                        'type': 'string',
                        'description': '可选的一行说明。',
                      },
                    },
                    'required': ['label'],
                  },
                },
                'multiSelect': {
                  'type': 'boolean',
                  'description': '是否允许多选。',
                },
              },
              'required': ['question', 'header', 'options'],
            },
          },
        },
        'required': ['questions'],
      };

  /// 提问是只读的：无宿主副作用，永远不需要批准。
  @override
  bool get readOnly => true;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final raw = args['questions'];
    if (raw is! List || raw.isEmpty) {
      return '[error: ask 需要至少一个问题]';
    }

    final questions = <AskQuestion>[];
    try {
      for (var i = 0; i < raw.length; i++) {
        final q = raw[i] as Map<String, dynamic>;
        final question = (q['question'] as String? ?? '').trim();
        final optionsRaw = q['options'] as List? ?? const [];
        if (question.isEmpty || optionsRaw.length < 2) {
          return '[error: 第 ${i + 1} 个问题缺少 question 或至少两个选项]';
        }
        final seen = <String>{};
        final options = <AskOption>[];
        for (final o in optionsRaw) {
          final om = o as Map<String, dynamic>;
          final label = (om['label'] as String? ?? '').trim();
          if (label.isEmpty) return '[error: 选项 label 不能为空]';
          if (seen.contains(label)) {
            return '[error: 选项 label 重复: $label]';
          }
          seen.add(label);
          options.add(AskOption(
            label: label,
            description: (om['description'] as String? ?? '').trim(),
          ));
        }
        questions.add(AskQuestion(
          id: 'q${i + 1}',
          header: (q['header'] as String? ?? '').trim(),
          question: question,
          options: options,
          multiSelect: q['multiSelect'] == true,
        ));
      }
    } catch (e) {
      return '[error: ask 参数解析失败: $e]';
    }

    final asker = this.asker;
    if (asker == null) {
      // Headless / 无交互用户：不阻塞自主运行，但显式标注来源，
      // 防止模型把假设当成用户选择。
      return '没有交互用户作答。这是模型假设回退，不是用户回答。'
          '请用你的最佳判断继续，说明你做的假设；'
          '当选项风险不同时优先选择最安全且可逆的选项。';
    }

    final answers = await asker.ask(AskRequest(
      id: 'ask_${DateTime.now().millisecondsSinceEpoch}',
      questions: questions,
    ));
    return formatAnswers(questions, answers);
  }

  /// 渲染用户选择为紧凑、模型可读的摘要，按 header 区分问题。
  ///
  /// 用户什么都没选（关闭弹窗）时返回显式停止信号而非逐问"(未回答)"——
  /// 否则模型会把空结果读成"继续行动"的许可。
  static String formatAnswers(
      List<AskQuestion> questions, List<AskAnswer> answers) {
    final pick = <String, List<String>>{};
    for (final a in answers) {
      pick[a.questionId] = a.selected;
    }
    var answered = 0;
    for (final q in questions) {
      if ((pick[q.id] ?? const []).isNotEmpty) answered++;
    }
    if (answered == 0) {
      return '用户关闭了问题而没有选择——请理解为"不要替我做决定，先聊聊"。'
          '不要选择任何选项、不要运行工具、不要针对此问题采取进一步行动；'
          '停下来等待用户的下一条消息。';
    }
    final buf = StringBuffer('用户回答：\n');
    for (final q in questions) {
      final sel = pick[q.id] ?? const <String>[];
      final label = q.header.isNotEmpty ? q.header : q.question;
      if (sel.isEmpty) {
        buf.writeln('- $label: (未回答——不要假设选择)');
        continue;
      }
      buf.writeln('- $label: ${sel.join(', ')}');
    }
    return buf.toString().trimRight();
  }
}
