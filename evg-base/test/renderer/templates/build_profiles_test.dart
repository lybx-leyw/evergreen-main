// 双版 release 契约测试：
//   同一仓库按 profile 构建浙大专用版（release_full）/ 通用版（release_std）。
//   本测试锁定 build_profiles/*.json 与生成物之间的不变式，防止误改导致
//   通用版混入浙大内容或浙大版丢模板：
//     1. release_full 必须包含 zju / classroom / zdbk（浙大场景）
//     2. release_std  必须不含 zju / classroom / zdbk（通用版 = 无浙大）
//     3. 两版引用的模板名都必须已登记在 templates_index.json（生成器同款校验）
//     4. 仓库默认生成物（template_registry.g.dart）= release_full 对应内容
//        （本地开发/默认构建即浙大专用版，与 app_bootstrap.dart 的
//        kZjuEnabled 默认 true 行为一致）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final indexPath = '$root/lib/renderer/templates/templates_index.json';
  final profilesDir = '$root/build_profiles';
  final generatedPath =
      '$root/lib/renderer/templates/generated/template_registry.g.dart';

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  List<String> profileTemplates(String profile) =>
      (readJson('$profilesDir/$profile.json')['templates'] as List)
          .cast<String>();

  test('profile 文件存在且两版模板均已登记（与生成器校验一致）', () {
    final indexTemplates = (readJson(indexPath)['templates'] as List)
        .cast<Map<String, dynamic>>();
    final registered = indexTemplates.map((t) => t['name'] as String).toSet();
    for (final profile in ['release_full', 'release_std']) {
      for (final name in profileTemplates(profile)) {
        expect(registered.contains(name), isTrue,
            reason: 'profile $profile 引用的模板 "$name" 未在 templates_index.json 登记');
      }
    }
  });

  test('浙大专用版（release_full）必须包含浙大场景模板', () {
    final tpl = profileTemplates('release_full');
    for (final zju in ['zju', 'classroom', 'zdbk']) {
      expect(tpl.contains(zju), isTrue,
          reason: 'release_full 应含 "$zju"，否则浙大专用版丢失浙大内容');
    }
    expect(tpl.contains('v4'), isTrue, reason: 'v4 是任何版本的兜底模板，必须存在');
  });

  test('通用版（release_std）不得包含浙大场景模板', () {
    final tpl = profileTemplates('release_std');
    for (final zju in ['zju', 'classroom', 'zdbk']) {
      expect(tpl.contains(zju), isFalse,
          reason: 'release_std 不应含 "$zju"，通用版必须剔除浙大内容');
    }
    expect(tpl.contains('v4'), isTrue, reason: 'v4 是任何版本的兜底模板，必须存在');
  });

  test('仓库默认生成物与 release_full 契约一致（默认构建 = 浙大专用版）', () {
    final generated = File(generatedPath).readAsStringSync();
    final full = profileTemplates('release_full');
    for (final name in full) {
      expect(generated.contains("'$name':"), isTrue,
          reason: '生成物应含 release_full 的模板路由 "$name"');
    }
    // release_std 独有的模板不应出现在默认生成物中（两版模板集不同，
    // 且 std 是 full 的子集，此断言校验生成物确实来自 full 而非 std）。
    expect(generated.contains('zju_modle/zju_modle_template.dart'), isTrue,
        reason: '默认生成物应 import 浙大模板入口（当前生成物 = release_full）');
  });
}
