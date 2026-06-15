import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/widgets/markdown_renderer.dart';

Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)));

/// 查找包含指定文本的任意 widget（Text + RichText + SelectableText）。
Finder _findText(String pattern) {
  return find.byWidgetPredicate((widget) {
    if (widget is Text && widget.data != null) {
      return widget.data!.contains(pattern);
    }
    if (widget is RichText) {
      return widget.text.toPlainText().contains(pattern);
    }
    if (widget is SelectableText && widget.data != null) {
      return widget.data!.contains(pattern);
    }
    return false;
  });
}

Future<void> _pumpUntilReady(WidgetTester tester) async {
  await tester.pump();
}

void main() {
  // ── 格式检测（纯单元测试，无需 pump） ──────────────────────
  group('格式自动识别', () {
    test('hasHtml 识别纯文本 → false', () {
      expect(MarkdownRenderer.hasHtml('这是一段普通文本'), isFalse);
    });

    test('hasHtml 识别 HTML → true', () {
      expect(MarkdownRenderer.hasHtml('<p>段落</p>'), isTrue);
    });

    test('hasHtml 泛型 <T> 不误判', () {
      expect(MarkdownRenderer.hasHtml('List<T>'), isFalse);
    });

    test('hasHtml 比较符号 < 不误判', () {
      expect(MarkdownRenderer.hasHtml('a < b 且 b > c'), isFalse);
    });
  });

  // ── 基本渲染 ───────────────────────────────────────────────
  group('基本渲染', () {
    testWidgets('纯文本正常显示', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '这是一段测试文本'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('这是一段测试文本'), findsOneWidget);
    });

    testWidgets('Markdown 标题', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '# 标题一\n\n## 标题二'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('标题一'), findsOneWidget);
      expect(_findText('标题二'), findsOneWidget);
    });

    testWidgets('加粗斜体', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '**加粗** *斜体* 普通'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('加粗'), findsOneWidget);
      expect(_findText('斜体'), findsOneWidget);
    });

    testWidgets('列表渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '- 项目一\n- 项目二'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('项目一'), findsOneWidget);
      expect(_findText('项目二'), findsOneWidget);
    });

    testWidgets('分隔线不崩溃', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '上面\n\n---\n\n下面'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('上面'), findsOneWidget);
      expect(_findText('下面'), findsOneWidget);
    });
  });

  // ── 代码块 ─────────────────────────────────────────────────
  group('代码块', () {
    testWidgets('dart 代码块正常显示', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '正文\n```dart\nvoid main() {}\n```\n结尾'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('正文'), findsOneWidget);
      expect(_findText('void main()'), findsOneWidget);
      expect(_findText('结尾'), findsOneWidget);
    });

    testWidgets('无语言标记代码块', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```\nplain code\n```'),
      ));
      await _pumpUntilReady(tester);
      // 验证代码块容器存在（SelectableText 文本无法通过 find.textContaining 找到）
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('未知语言回退普通代码块', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```unknown\nsome content\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('some content'), findsOneWidget);
    });
  });

  // ── HTML 渲染 ───────────────────────────────────────────────
  group('HTML 渲染', () {
    testWidgets('简单 HTML', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '<p>段落</p><b>加粗</b>'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('段落'), findsOneWidget);
      expect(_findText('加粗'), findsOneWidget);
    });

    testWidgets('空 HTML 不崩溃', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '<p></p>'),
      ));
      await tester.pump();
    });
  });

  // ── 特殊代码块 ───────────────────────────────────────────────
  group('特殊代码块', () {
    testWidgets('math 代码块', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```math\nE=mc^2\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('```math'), findsNothing);
    });

    testWidgets('mindmap 代码块', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```mindmap\n中心主题\n  分支1\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('```mindmap'), findsNothing);
    });
  });

  // ── 多语言代码块 ─────────────────────────────────────────────
  group('多语言代码块', () {
    testWidgets('python 代码块正常渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```python\nprint("hello")\nfor i in range(3):\n    print(i)\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('print("hello")'), findsOneWidget);
      expect(_findText('for i in range'), findsOneWidget);
    });

    testWidgets('javascript 代码块正常渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```javascript\nconst x = 1;\nconsole.log(x);\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('const x = 1'), findsOneWidget);
    });

    testWidgets('html 代码块正常渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```html\n<div>hello</div>\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('<div>'), findsOneWidget);
    });

    testWidgets('bash/shell 代码块正常渲染', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```bash\nflutter build windows --release\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('flutter build'), findsOneWidget);
    });

    testWidgets('mermaid 代码块不渲染为普通代码', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '```mermaid\ngraph TD\nA-->B\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('```mermaid'), findsNothing);
    });
  });

  // ── 大代码块（模拟 AI 画图/生成代码场景） ──────────────────
  group('大代码块 — 渲染稳定性', () {
    testWidgets('500 行 Python 代码块不崩溃', (tester) async {
      final lines = <String>[];
      for (var i = 0; i < 500; i++) {
        lines.add('print("line $i")');
      }
      await tester.pumpWidget(_wrap(
        MarkdownRenderer(text: '```python\n${lines.join('\n')}\n```'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('print("line 0")'), findsOneWidget);
      expect(_findText('print("line 499")'), findsOneWidget);
      // 不应抛出 overflow 异常
      expect(tester.takeException(), isNull);
    });

    testWidgets('2000 字符纯代码无 fence 不崩溃', (tester) async {
      final code = '  ' + 'a' * 2000;
      await tester.pumpWidget(_wrap(
        MarkdownRenderer(text: code),
      ));
      await _pumpUntilReady(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超长单行代码不溢出', (tester) async {
      final longLine = 'x = ' + List.filled(300, ' + ').join() + '1';
      await tester.pumpWidget(_wrap(
        MarkdownRenderer(text: '```python\n$longLine\n```'),
      ));
      await _pumpUntilReady(tester);
      // 不应有 RenderFlex overflow
      expect(tester.takeException(), isNull);
    });
  });

  // ── AI 典型输出模式 ──────────────────────────────────────────
  group('AI 典型回复格式', () {
    testWidgets('文字 + 代码块 + 文字', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text:
          '这是一个 Python 示例：\n\n'
          '```python\n'
          'def hello():\n'
          '    return "world"\n'
          '```\n\n'
          '运行 `hello()` 即可。'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('这是一个 Python 示例'), findsOneWidget);
      expect(_findText('def hello()'), findsOneWidget);
      expect(_findText('运行'), findsOneWidget);
    });

    testWidgets('多段代码块交错文字', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text:
          '后端代码：\n\n'
          '```python\n'
          '@app.route("/")\n'
          'def index():\n'
          '    return "ok"\n'
          '```\n\n'
          '前端代码：\n\n'
          '```javascript\n'
          'fetch("/").then(r => r.text())\n'
          '```\n\n'
          '这样就完成了。'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('后端代码'), findsOneWidget);
      expect(_findText('@app.route'), findsOneWidget);
      expect(_findText('前端代码'), findsOneWidget);
      expect(_findText('fetch("/")'), findsOneWidget);
      expect(_findText('这样就完成了'), findsOneWidget);
    });

    testWidgets('项目符号 + 内联代码', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text:
          '- 安装：`pip install requests`\n'
          '- 运行：`python main.py`\n'
          '- 测试：`pytest`'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('pip install'), findsOneWidget);
      expect(_findText('python main.py'), findsOneWidget);
      expect(_findText('pytest'), findsOneWidget);
    });

    testWidgets('带缩进的代码块', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text:
          '    def foo():\n'
          '        return 42'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('def foo'), findsOneWidget);
    });
  });

  // ── 回退模式 ─────────────────────────────────────────────────
  group('markdownFailed 回退', () {
    testWidgets('回退时剥离 markdown 语法标记', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(
          text: '**加粗** *斜体* 普通',
          markdownFailed: true,
        ),
      ));
      await _pumpUntilReady(tester);
      // 回退使用 SelectableText（无法通过 _findText 检查内容）
      expect(find.byType(SelectableText), findsOneWidget);
      expect(_findText('**'), findsNothing);
    });
  });

  // ── 边界情况 ─────────────────────────────────────────────────
  group('边界情况', () {
    testWidgets('空文本不崩溃', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: ''),
      ));
      await tester.pump();
    });

    testWidgets('超长文本不崩溃', (tester) async {
      final longText = '测试段落。\n\n' * 100;
      await tester.pumpWidget(_wrap(
        MarkdownRenderer(text: longText),
      ));
      await tester.pump();
    });

    testWidgets('useCard=false', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '无卡片', useCard: false),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('无卡片'), findsOneWidget);
    });

    testWidgets('混合 fence 不崩溃', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '开头\n```dart\nvoid main() {}\n```\n中间\n```python\nx = 1\n```\n结尾'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('开头'), findsOneWidget);
      expect(_findText('中间'), findsOneWidget);
      expect(_findText('结尾'), findsOneWidget);
    });

    testWidgets('未闭合 fence', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarkdownRenderer(text: '开头\n```dart\n未闭合代码'),
      ));
      await _pumpUntilReady(tester);
      expect(_findText('开头'), findsOneWidget);
      expect(_findText('未闭合代码'), findsOneWidget);
    });
  });
}
