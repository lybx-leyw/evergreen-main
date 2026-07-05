import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/plan/services/plan_store.dart';
import 'package:evergreen_multi_tools/features/plan/models/plan.dart';
import 'package:evergreen_multi_tools/features/plan/models/plan_task.dart';

void main() {
  late String tmpDir;

  var _counter = 0;
  int _hashCode() => Object.hash(DateTime.now().microsecondsSinceEpoch, _counter);

  setUp(() {
    _counter++;
    // 加随机后缀避免并发测试共享目录
    tmpDir = '${Directory.systemTemp.path}/plan_test_${DateTime.now().millisecondsSinceEpoch}_$_counter${_hashCode()}';
    Directory(tmpDir).createSync(recursive: true);
  });

  tearDown(() {
    Directory(tmpDir).deleteSync(recursive: true);
  });

  group('PlanStore CRUD', () {
    test('load 不存在的计划 → null', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      expect(store.load('nonexistent'), isNull);
    });

    test('listAll 空目录 → []', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      expect(store.listAll(), isEmpty);
    });

    test('delete 不存在的计划不崩溃', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      await store.delete('nonexistent');
    });
  });

  group('PlanStore 往返', () {
    test('save → load 往返', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      final original = Plan(
        id: 'plan_test', name: '测试', preface: '序语',
        outline: [PlanTask.create(title: '任务A')],
      );
      await store.save(original);
      final loaded = store.load('plan_test');
      expect(loaded, isNotNull);
      expect(loaded!.name, '测试');
      expect(loaded.preface, '序语');
      expect(loaded.outline.length, 1);
    });

    test('save → listAll 含该计划', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      await store.save(Plan.create(name: 'P1'));
      await store.save(Plan.create(name: 'P2'));
      expect(store.listAll().length, 2);
    });

    test('delete → listAll 不含', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      final p = Plan.create(name: '待删除');
      await store.save(p);
      expect(store.listAll().length, 1);
      await store.delete(p.id);
      expect(store.listAll(), isEmpty);
    });

    test('listAll 按 updatedAt 降序', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      final p1 = Plan(id: 'a', name: 'old', updatedAt: DateTime(2026, 6, 1));
      final p2 = Plan(id: 'b', name: 'new', updatedAt: DateTime(2026, 6, 10));
      await store.save(p1);
      await store.save(p2);
      final list = store.listAll();
      expect(list[0].id, 'b');
      expect(list[1].id, 'a');
    });

    test('save 覆盖更新', () async {
      final store = await PlanStore.create(storagePath: tmpDir);
      final p = Plan.create(name: '旧名');
      await store.save(p);
      await store.save(p.copyWith(name: '新名'));
      expect(store.load(p.id)!.name, '新名');
    });
  });
}
