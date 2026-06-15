import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自动刷新设置。
class AutoRefreshState {
  final bool enabled;
  final int intervalMinutes;

  const AutoRefreshState({this.enabled = true, this.intervalMinutes = 3});
}

/// 自动刷新设置 Provider。
final autoRefreshProvider = StateProvider<AutoRefreshState>((_) {
  return const AutoRefreshState();
});

/// 全局刷新 tick——每次定时器触发时递增，数据源 watch 此 provider 可自动刷新。
final autoRefreshTickProvider = StateProvider<int>((_) => 0);

/// 页面打开时是否应刷新数据。
bool shouldRefresh(WidgetRef ref) {
  return ref.read(autoRefreshProvider).enabled;
}

/// 后台定时刷新器。
Timer? _refreshTimer;

/// 启动/重启定时器，每次 tick 递增 [autoRefreshTickProvider]。
void restartAutoRefresh({
  bool enabled = true,
  int intervalMinutes = 3,
  void Function()? onTick,
}) {
  _refreshTimer?.cancel();
  if (!enabled || intervalMinutes <= 0) return;
  _refreshTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
    debugPrint('[AutoRefresh] tick ($intervalMinutes min)');
    // 延迟 500ms 确保当前帧/动画/状态转换完全结束再触发
    Future.delayed(const Duration(milliseconds: 500), () => onTick?.call());
  });
}

void stopAutoRefresh() {
  _refreshTimer?.cancel();
  _refreshTimer = null;
}

/// 初始化自动刷新。
Future<void> initAutoRefresh(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  // 兼容 String 和 bool 两种存储格式（设置界面以字符串形式保存）
  final enabledRaw = prefs.get('AUTO_REFRESH_ENABLED');
  final enabled = enabledRaw is bool ? enabledRaw : (enabledRaw != 'false');
  final intervalRaw = prefs.get('AUTO_REFRESH_INTERVAL');
  final interval = intervalRaw is int
      ? intervalRaw
      : (int.tryParse(intervalRaw?.toString() ?? '') ?? 3);
  ref.read(autoRefreshProvider.notifier).state =
      AutoRefreshState(enabled: enabled, intervalMinutes: interval);
  // 定时器直接递增 tick，由各 Provider watch 决定是否重跑
  restartAutoRefresh(
    enabled: enabled,
    intervalMinutes: interval,
    onTick: () {
      ref.read(autoRefreshTickProvider.notifier).state++;
    },
  );
}
