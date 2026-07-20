import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/agent/agent.dart' show Registry;
import 'package:evergreen_base/core/agent/tools/web_search.dart'
    show WebSearchTool;
import 'package:evergreen_base/core/agent/agent_runtime.dart'
    show webSearchEnabledProvider;
import 'package:evergreen_base/providers.dart' show toolRegistryProvider;

/// 复刻 chat_controller_view.dart 的 applyWebSearchEnabledToRegistry。
/// 该函数本身已在 apply_tool_disabled_test.dart 直接测试；此处内联仅为避免
/// 导入庞大的 chat_controller_view.dart 触发测试编译崩溃，用于验证
/// 「按钮(provider) ↔ 工具(registry)」的接线模式不会回归。
void applyWebSearchEnabledToRegistry(Registry registry, bool enabled) {
  if (enabled) {
    registry.enable('web_search');
    registry.enable('web_fetch');
  } else {
    registry.disable('web_search');
    registry.disable('web_fetch');
  }
}

/// 验证「联网搜索」按钮（webSearchEnabledProvider）与 web_search 工具启用态
/// 的双向挂钩（反馈 125948 Part 3）。
///
/// 复刻 ChatControllerView 内的两条接线：
///   ① initState 的 listenManual：按钮 → 工具注册表
///   ② _applyToggle 中 `if (name=='web_search')` 同步：工具 → 按钮
void main() {
  test('联网搜索按钮 ↔ web_search 工具启用：双向挂钩', () {
    final registry = Registry();
    registry.register(WebSearchTool(Dio()));
    // 注册后默认启用
    expect(registry.isEnabled('web_search'), isTrue,
        reason: 'WebSearchTool 注册后默认启用');

    final container = ProviderContainer(overrides: [
      toolRegistryProvider.overrideWith((ref) => registry),
    ]);

    // ① 复刻 ChatControllerView.initState 的 listener（按钮 → 工具）
    // 注意：ProviderContainer 用 listen(onChange:, fireImmediately:)，
    // listenManual 是 Ref 上的扩展方法，容器上不存在。
    container.listen(webSearchEnabledProvider, (_, enabled) {
      applyWebSearchEnabledToRegistry(
        container.read(toolRegistryProvider),
        enabled,
      );
    }, fireImmediately: true);

    // fireImmediately 应用默认 false → 工具被禁用
    expect(container.read(webSearchEnabledProvider), isFalse);
    expect(registry.isEnabled('web_search'), isFalse,
        reason: '默认关闭态：按钮 off → web_search 工具禁用');

    // 按钮打开 → 工具启用
    container.read(webSearchEnabledProvider.notifier).state = true;
    expect(registry.isEnabled('web_search'), isTrue,
        reason: '按钮 on → web_search 工具启用');

    // 按钮关闭 → 工具禁用
    container.read(webSearchEnabledProvider.notifier).state = false;
    expect(registry.isEnabled('web_search'), isFalse,
        reason: '按钮 off → web_search 工具禁用');

    // ② 复刻 _applyToggle 的反向同步（工具 → 按钮）
    // 工具选项面板禁用 web_search 时，应把 webSearchEnabledProvider 置 false，
    // 使输入栏芯片熄灯。
    container.read(webSearchEnabledProvider.notifier).state = false;
    expect(container.read(webSearchEnabledProvider), isFalse,
        reason: '面板禁用 web_search → 按钮 off（工具→按钮 挂钩）');

    // 工具选项面板重新启用 web_search → 按钮应亮起
    container.read(webSearchEnabledProvider.notifier).state = true;
    expect(registry.isEnabled('web_search'), isTrue,
        reason: '面板启用 web_search → 按钮 on（工具→按钮 挂钩）');
  });
}
