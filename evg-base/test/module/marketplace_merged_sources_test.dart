/// 回归测试：市场中心合并「运行时已注册数据源」与「已加载 Skill」。
///
/// 覆盖修复前缺失的两类卡片：
/// 1. DataOrchestrator 已注册数据源（如 zju 校园数据源、设计器热注册）应在市场显示，
///    即便磁盘 plugins/ 下没有对应 data/manifest.json；
/// 2. SkillIndex 已加载 Skill（含 .greenix/skills/ 旧路径、plugins/<id>/skill/）应在市场显示，
///    而非仅扫 plugins/<id>/skill/*.md 单目录导致的遗漏（如「ziyuan」类资源 skill）。
library;

import 'dart:io';

import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 写入一个 .greenix/skills/ 风格的真实 skill（旧路径，marketplace 旧扫描漏掉）。
Skill _writeGreenixSkill(Directory root, String name, String desc) {
  final dir = Directory(p.join(root.path, '.greenix', 'skills'))..createSync(recursive: true);
  final f = File(p.join(dir.path, '$name.md'))
    ..writeAsStringSync('---\nname: $name\ndescription: $desc\n---\n# body');
  return Skill(
    name: name,
    description: desc,
    body: '# body',
    scope: SkillScope.global,
    path: f.path,
  );
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mp_merged_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('合并 DataOrchestrator 已注册数据源（磁盘无 manifest 也显示）',
      (tester) async {
    // 注册一个数据源，但磁盘 plugins/ 下不写任何 data manifest。
    final orch = DataOrchestrator();
    orch.register(
      DataType<Map<String, dynamic>>(
        name: 'zju_zdbk_transcript',
        category: 'zju',
        displayName: '浙大成绩单',
        ttl: const Duration(minutes: 5),
      ),
      () async => <String, dynamic>{},
    );

    final skillIndex = SkillIndex();
    final skill = _writeGreenixSkill(tmp, 'ziyuan', '资源类技能');
    skillIndex.add(skill);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataOrchestratorProvider.overrideWith((ref) => orch),
          skillIndexProvider.overrideWith((ref) => skillIndex),
          moduleRegistryProvider.overrideWith((ref) => ModuleRegistry()..seal()),
          pluginsDirProvider.overrideWith((ref) => tmp.path),
        ],
        child: const MaterialApp(home: Scaffold(body: MarketplaceSlot())),
      ),
    );
    await tester.pumpAndSettle();

    // 数据源卡出现（displayName 或 name）。
    expect(find.text('浙大成绩单'), findsWidgets,
        reason: 'DataOrchestrator 已注册数据源应在市场显示');
    // 真实 skill（.greenix/skills/ 路径）出现。
    expect(find.text('ziyuan'), findsWidgets,
        reason: 'SkillIndex 已加载的 .greenix/skills/ skill 应在市场显示');
    expect(find.text('资源类技能'), findsWidgets);
  });

  testWidgets('磁盘 data manifest 与 orchestrator 同名数据源去重（不重复）',
      (tester) async {
    final orch = DataOrchestrator();
    orch.register(
      DataType<Map<String, dynamic>>(
        name: 'dup_src',
        category: 'test',
        displayName: '重复源',
        ttl: const Duration(minutes: 5),
      ),
      () async => <String, dynamic>{},
    );
    // 磁盘写一个同名 data-source 插件（id 与 orch name 相同）。
    final pluginDir = Directory(p.join(tmp.path, 'dup_src'))..createSync();
    Directory(p.join(pluginDir.path, 'data')).createSync();
    File(p.join(pluginDir.path, 'data', 'manifest.json')).writeAsStringSync(
      '{"type":"data-source","name":"重复源","script":"x.py","dataTypes":'
      '[{"name":"dup_src","displayName":"重复源"}]}');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataOrchestratorProvider.overrideWith((ref) => orch),
          skillIndexProvider.overrideWith((ref) => SkillIndex()),
          moduleRegistryProvider.overrideWith((ref) => ModuleRegistry()..seal()),
          pluginsDirProvider.overrideWith((ref) => tmp.path),
        ],
        child: const MaterialApp(home: Scaffold(body: MarketplaceSlot())),
      ),
    );
    await tester.pumpAndSettle();

    // 去重后只出现一次「重复源」（磁盘版，非内置）。
    expect(find.text('重复源'), findsOneWidget,
        reason: '磁盘与 orchestrator 同名数据源应去重，不重复显示');
  });
}
