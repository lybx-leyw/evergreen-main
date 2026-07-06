/// HTML 渲染器离线测试脚本。
///
/// 读取 TARGET_MODULE_JSON.md，提取 V2 showcase manifest，
/// 调用 HtmlRenderer 生成 HTML，写入文件。
///
/// 运行: dart run test_render.dart
import 'dart:convert';
import 'dart:io';
import 'html_renderer.dart';

void main() {
  // 读取 TARGET_MODULE_JSON.md
  final mdPath = '../../../../TARGET_MODULE_JSON.md';
  final mdFile = File(mdPath);

  if (!mdFile.existsSync()) {
    stderr.writeln('ERROR: 找不到 $mdPath');
    stderr.writeln('请从 evg-base/lib/renderer/html/ 目录运行此脚本');
    exit(1);
  }

  final md = mdFile.readAsStringSync();

  // 从 markdown 中提取 V2 JSON（定位 schemaVersion 2.0）
  final schemaIdx = md.indexOf('"schemaVersion": "2.0"');
  if (schemaIdx < 0) {
    stderr.writeln('ERROR: 在 TARGET_MODULE_JSON.md 中找不到 V2 manifest');
    exit(1);
  }

  final blockStart = md.lastIndexOf('```json', schemaIdx);
  if (blockStart < 0) {
    stderr.writeln('ERROR: 找不到 JSON 代码块');
    exit(1);
  }

  final afterMarker = blockStart + '```json'.length;
  final nl = md.indexOf('\n', afterMarker);
  final contentStart = nl >= 0 ? nl + 1 : afterMarker;
  final contentEnd = md.indexOf('\n```', contentStart);
  if (contentEnd < 0) {
    stderr.writeln('ERROR: JSON 代码块未闭合');
    exit(1);
  }

  var jsonStr = md.substring(contentStart, contentEnd).trim();

  // 剥离 JSON 注释和尾部逗号
  jsonStr = jsonStr.replaceAllMapped(RegExp(r'("(?:[^"\\]|\\.)*")|\/\/.*$', multiLine: true), (m) => m.group(1) ?? '');
  jsonStr = jsonStr.replaceAllMapped(RegExp(r'("(?:[^"\\]|\\.)*")|\/\*[\s\S]*?\*\/'), (m) => m.group(1) ?? '');
  jsonStr = jsonStr.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);

  // 解析
  Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(jsonStr) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('ERROR: JSON 解析失败: $e');
    // 打印出错位置附近的内容
    stderr.writeln('\n--- JSON (前200字符) ---');
    stderr.writeln(jsonStr.substring(0, jsonStr.length < 200 ? jsonStr.length : 200));
    exit(1);
  }

  print('✅ V2 Manifest 解析成功');
  print('   模块: ${manifest['name']}');
  print('   版本: ${manifest['version']}');
  print('   页面数: ${(manifest['pages'] as List?)?.length ?? 0}');

  // 渲染 HTML
  final html = HtmlRenderer.render(manifest);

  print('✅ HTML 生成成功 (${html.length} 字符)');

  // 写入文件
  final outputPath = 'test_output.html';
  File(outputPath).writeAsStringSync(html);
  print('✅ 输出文件: ${File(outputPath).absolute.path}');
  print('\n在浏览器中打开此文件即可预览所有 9 个页面的 V2 渲染效果。');
}
