/// 一次性证明：renderer 真实字段适配（timetable/flashcards/quiz/settings/button/nav-button）。
import 'dart:convert';
import 'package:evergreen_base/renderer/html/html_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const _timetableJson = '''
{
  "schemaVersion": "2.0", "type": "module", "id": "x", "name": "x",
  "pages": [{
    "id": "p", "label": "p", "default": true,
    "layout": {"type": "grid", "preset": {"columns": 1}, "slots": {
      "main": {"component": {"type": "timetable", "config": {
        "sessions": [
          {"courseName": "高等数学", "teacher": "张三", "location": "东1-201", "dayOfWeek": 1, "periods": [1, 2]},
          {"courseName": "大学英语", "teacher": "李四", "location": "东2-305", "dayOfWeek": 3, "periods": [3]}
        ]
      }}}
    }}
  }]
}''';

const _multiJson = '''
{
  "schemaVersion": "2.0", "type": "module", "id": "y", "name": "y",
  "pages": [{
    "id": "p", "label": "p", "default": true,
    "layout": {"type": "grid", "preset": {"columns": 3}, "slots": {
      "a": {"component": {"type": "nav-button", "config": {"label": "课程", "icon": "📚", "target": "/courses"}}},
      "b": {"component": {"type": "button", "config": {"buttons": [
        {"label": "课表视图", "icon": "📅", "event": "slot:switch", "style": "tonal"}]}}},
      "c": {"component": {"type": "flashcards", "config": {"wordList": [
        {"word": "abandon", "meaning": "v. 放弃"}]}}},
      "d": {"component": {"type": "quiz", "config": {"wordList": [
        {"word": "benefit", "meaning": "n. 益处"}], "questionTypes": ["multiple-choice"], "timeLimit": 300, "passScore": 80}}},
      "e": {"component": {"type": "settings", "config": {"settings": [
        {"key": "DEEPSEEK_API_KEY", "label": "DeepSeek API Key", "type": "string"}]}}}
    }}
  }]
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('timetable 渲染真实 sessions', () async {
    final html = await HtmlRenderer.render(jsonDecode(_timetableJson));
    expect(html, contains('高等数学'));
    expect(html, contains('张三'));
    expect(html, contains('东1-201'));
    expect(html, contains('evg-tt-session'));
    expect(html, isNot(contains('待实现')));
    print('[PROOF] timetable 字段适配 OK');
  });

  test('flashcards/quiz/settings/button/nav-button 渲染真实字段', () async {
    final html = await HtmlRenderer.render(jsonDecode(_multiJson));
    expect(html, contains('课程'));
    expect(html, contains('课表视图'));
    expect(html, contains('abandon'));
    expect(html, contains('benefit'));
    expect(html, contains('DeepSeek API Key'));
    expect(html, isNot(contains('待实现')));
    print('[PROOF] 多组件字段适配 OK');
  });
}
