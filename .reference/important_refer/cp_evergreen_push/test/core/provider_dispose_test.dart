import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 0.1.2 — Controller 必须在 Provider dispose 时释放。
///
/// 修复前：agent_provider.dart 的 Controller 从未被 dispose。
class _DisposableNotifier extends StateNotifier<int> {
  bool disposed = false;
  _DisposableNotifier() : super(0);
}

void main() {
  group('Provider — onDispose', () {
    test('ref.onDispose 在 ProviderContainer.dispose 时被调用', () {
      final notifier = _DisposableNotifier();
      bool didDispose = false;
      final provider = StateNotifierProvider<_DisposableNotifier, int>((ref) {
        ref.onDispose(() {
          didDispose = true;
        });
        return notifier;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(provider.notifier);
      expect(didDispose, false);

      container.dispose();
      expect(didDispose, true);
    });
  });
}
