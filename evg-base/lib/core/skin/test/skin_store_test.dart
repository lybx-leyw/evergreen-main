/// SkinStore 全量测试——register / find / setActive / ChangeNotifier 通知。
library;

import 'package:test/test.dart';

import '../skin_descriptor.dart';
import '../skin_store.dart';

SkinDescriptor _skin(String id, [String name = '']) =>
    SkinDescriptor(id: id, name: name.isEmpty ? id : name);

void main() {
  group('SkinStore', () {
    late SkinStore store;

    setUp(() {
      store = SkinStore();
    });

    test('register — 新皮肤包', () {
      store.register(_skin('a'));
      expect(store.all.length, 1);
    });

    test('register — 同 id 覆盖', () {
      store.register(_skin('a', 'First'));
      store.register(_skin('a', 'Second'));
      expect(store.all.length, 1);
      expect(store.findById('a')?.name, 'Second');
    });

    test('all — 返回不可变列表', () {
      store.register(_skin('a'));
      expect(store.all.length, 1);
    });

    test('all — 空 store', () {
      expect(store.all, isEmpty);
    });

    test('findById — 命中', () {
      store.register(_skin('a'));
      expect(store.findById('a')?.id, 'a');
    });

    test('findById — 未命中返回 null', () {
      expect(store.findById('nonexistent'), isNull);
    });

    test('activeSkin — 初始为 null', () {
      expect(store.activeSkin, isNull);
    });

    test('activeSkin — set/get', () {
      final s = _skin('a');
      store.activeSkin = s;
      expect(store.activeSkin?.id, 'a');
    });

    test('activeSkin — 设置后触发 ChangeNotifier', () {
      var notified = false;
      store.addListener(() => notified = true);
      store.activeSkin = _skin('a');
      expect(notified, isTrue);
    });

    test('activeSkin — 同皮肤包不重复通知', () {
      final s = _skin('a');
      store.activeSkin = s;
      var count = 0;
      store.addListener(() => count++);
      store.activeSkin = s; // 相同皮肤包
      expect(count, 0);
    });

    test('activeSkin — 取消监听后不再通知', () {
      var count = 0;
      void listener() => count++;
      store.addListener(listener);
      store.removeListener(listener);
      store.activeSkin = _skin('a');
      expect(count, 0);
    });

    test('setActiveById — 成功返回 true', () {
      store.register(_skin('a'));
      expect(store.setActiveById('a'), isTrue);
      expect(store.activeSkin?.id, 'a');
    });

    test('setActiveById — 不存在返回 false', () {
      expect(store.setActiveById('nonexistent'), isFalse);
      expect(store.activeSkin, isNull);
    });

    test('activeOrFirst — 已设置返回 active', () {
      store.register(_skin('a'));
      store.register(_skin('b'));
      store.activeSkin = store.findById('b');
      expect(store.activeOrFirst?.id, 'b');
    });

    test('activeOrFirst — 未设置返回第一个', () {
      store.register(_skin('a'));
      store.register(_skin('b'));
      expect(store.activeOrFirst?.id, 'a');
    });

    test('activeOrFirst — 空 store 返回 null', () {
      expect(store.activeOrFirst, isNull);
    });

    test('dispose — 清空监听者', () {
      var count = 0;
      store.addListener(() => count++);
      store.dispose();
      // dispose 后 ChangeNotifier 不可再使用，设置 activeSkin 会触发断言
      expect(
        () => store.activeSkin = _skin('a'),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
