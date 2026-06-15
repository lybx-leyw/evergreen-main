import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 0.1.1 — ref.read 不建立依赖链，ref.watch 建立依赖链。
///
/// 修复前：examsListProvider 用 ref.read(zdbkExamsProvider.future)，
/// invalidate examsListProvider 时不会重新读取 zdbkExamsProvider。
class _IntNotifier extends StateNotifier<int> {
  _IntNotifier() : super(0);
  void inc() => state++;
}

void main() {
  group('Provider — watch chain', () {
    test('ref.watch 建立依赖，上游变化下游自动重新计算', () {
      final container = ProviderContainer();
      final upstream = StateProvider<int>((ref) => 0);
      final downstream = Provider<int>((ref) {
        return ref.watch(upstream) * 2;
      });
      addTearDown(container.dispose);

      expect(container.read(downstream), 0);
      container.read(upstream.notifier).state = 5;
      expect(container.read(downstream), 10); // watch 自动更新
    });

    test('ref.read 不建立依赖，下游需手动 invalidate', () {
      final container = ProviderContainer();
      final upstream = StateProvider<int>((ref) => 0);
      final downstream = FutureProvider<int>((ref) async {
        return ref.read(upstream); // read — no dependency
      });
      addTearDown(container.dispose);

      final first = container.read(downstream.future);
      container.read(upstream.notifier).state = 5;
      final second = container.read(downstream.future);
      // 没有 invalidate downstream，仍然返回旧值
      expect(second, completion(0));
    });
  });
}
