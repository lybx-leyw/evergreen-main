/// 文件型插件接线的**编译冒烟 + 行为**测试（补 analyze 的盲区）。
///
/// ⚠️ 为什么需要这个文件：`lib/renderer/**` 是嵌套子包，在目录内跑
/// `flutter analyze` 会产出 **85 个假错误**（连 `package:flutter/material.dart`
/// 都解析不了；同目录未改动的 `file_export_bar.dart` 同样如此）。
/// **根上下文的测试编译**才是可信的——因此用本文件把
/// [openLocalFile] 与 [FileSourceSlot] 拉进根上下文编译一次。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/shared/file_opener.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/data/file_source_slot.dart';

void main() {
  group('openLocalFile（平台「打开文件」服务）', () {
    test('空路径 → Err（不崩溃）', () async {
      final r = await openLocalFile('');
      expect(r.isOk, isFalse);
    });

    test('空白路径 → Err', () async {
      final r = await openLocalFile('   ');
      expect(r.isOk, isFalse);
    });

    test('文件不存在 → Err（不尝试启动系统应用）', () async {
      final r = await openLocalFile('/tmp/definitely-not-exists-xyz-123');
      expect(r.isOk, isFalse);
      final msg = r.fold((_) => '', (e) => '$e');
      expect(msg, contains('文件不存在'));
    });
  });

  group('FileSourceSlot（编译冒烟）', () {
    test('可从 ComponentDescriptor 构造（确认接线符号存在且可编译）', () {
      final desc = ComponentDescriptor.fromJson({
        'type': 'file-source',
        'config': {
          'dataSource': {'endpoint': 'orch://lecture_materials'}
        },
      });
      final slot = FileSourceSlot(config: desc);
      expect(slot, isNotNull);
      // 继承 DataSourceSlot ⇒ 具备声明式字段映射与期望形状
      expect(slot.dataMapping, isNotNull);
    });
  });
}
