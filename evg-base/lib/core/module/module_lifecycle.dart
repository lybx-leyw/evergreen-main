/// 模块生命周期管理器——安装/卸载/禁用/升级。
///
/// 按照 [PLAN_NOW §十一] 定义：
///
/// | 事件 | 行为 |
/// |------|------|
/// | **安装** | 自动创建 `.greenix/workspaces/<moduleId>/` 目录，初始化 memory 存储 |
/// | **卸载** | 删除 workspace 目录；**保留 memory**（用户可手动清） |
/// | **禁用** | 冻结所有状态（停进程），不删除数据 |
/// | **启用** | 恢复状态，重启进程 |
/// | **升级** | 不做数据迁移，新字段给默认值；旧字段保持不变 |
///
/// # 与现有组件的关系
///
/// - [GreenixPath.ensureWorkspaceDir]: workspace 目录创建
/// - [ProcessManager]: 进程生命周期
/// - [PluginInstaller]: 安装/卸载回调
/// - [ModuleRegistry]: 注册/注销
///
/// # 使用方式
///
/// ```dart
/// final lifecycle = ModuleLifecycle(
///   pluginsRoot: 'plugins/',
///   workingDirectory: 'plugins/vocab-tutor/',
/// );
///
/// // 安装
/// await lifecycle.install(moduleId: 'vocab-tutor', descriptor: desc);
///
/// // 升级
/// await lifecycle.upgrade(moduleId: 'vocab-tutor', newDescriptor: updatedDesc);
///
/// // 禁用
/// await lifecycle.disable('vocab-tutor');
///
/// // 启用
/// await lifecycle.enable('vocab-tutor');
///
/// // 卸载
/// await lifecycle.uninstall('vocab-tutor');
/// ```
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../log.dart';
import '../utils/greenix_path.dart';
import 'module_descriptor.dart';
import 'process_manager.dart';

/// 模块生命周期状态。
enum ModuleState {
  /// 已安装，正常运行。
  active,

  /// 已安装但被禁用（进程已停，数据保留）。
  disabled,

  /// 未安装。
  notInstalled,
}

/// 模块生命周期管理器。
///
/// 不持有 [ModuleDescriptor] 自身——每次操作传入，支持升级场景的 descriptor 切换。
/// 但会持久化跟踪各模块的 [ModuleState]。
class ModuleLifecycle {
  /// 插件安装根目录（即 `plugins/` 路径）。
  final String pluginsRoot;

  /// 模块工作目录（即 `plugins/<moduleId>/` 路径前缀）。
  final String workingDirectory;

  /// 模块启用/禁用状态追踪。
  final Map<String, ModuleState> _states = {};

  /// 禁用时保存的模块级进程描述符（恢复时复用）。
  /// moduleId → ProcessDescriptor JSON
  final Map<String, Map<String, dynamic>> _savedModuleProcess = {};

  ModuleLifecycle({
    required this.pluginsRoot,
    required this.workingDirectory,
  });

  // ═══════ 状态查询 ═══════

  /// 查询模块当前状态。
  ModuleState stateOf(String moduleId) {
    return _states[moduleId] ?? ModuleState.notInstalled;
  }

  /// 模块是否处于活跃状态。
  bool isActive(String moduleId) => stateOf(moduleId) == ModuleState.active;

  /// 模块是否被禁用。
  bool isDisabled(String moduleId) => stateOf(moduleId) == ModuleState.disabled;

  // ═══════ 安装 ═══════

  /// 安装模块。
  ///
  /// 1. 创建 workspace 目录
  /// 2. 初始化 memory 存储目录
  /// 3. 标记为 [ModuleState.active]
  ///
  /// [descriptor] 为已解析的模块描述符。
  Future<void> install({
    required String moduleId,
    required ModuleDescriptor descriptor,
  }) async {
    Log().info('ModuleLifecycle: 安装模块 $moduleId');

    // 1. 创建 workspace 目录
    ensureWorkspaceDir(moduleId);

    // 2. 初始化 workspace 子目录结构
    _ensureWorkspaceSubdirs(moduleId);

    // 3. 初始化 memory 存储目录（保留 memory，由 FileMemoryStore 后续管理）
    _ensureMemoryDir(moduleId);

    // 4. 标记为 active
    _states[moduleId] = ModuleState.active;
    if (descriptor.process != null) {
      _savedModuleProcess[moduleId] = descriptor.process!.toJson();
    }

    Log().info('ModuleLifecycle: 模块 $moduleId 安装完成，状态=active');
  }

  // ═══════ 卸载 ═══════

  /// 卸载模块。
  ///
  /// 1. 停止所有进程（通过 [ProcessManager]）
  /// 2. 删除 workspace 目录
  /// 3. **保留 memory**（用户可手动清理 `.greenix/memories/`）
  /// 4. 清除状态追踪
  ///
  /// [onStop] — 外部提供的进程停止回调（在销毁 ProcessManager 前调用）。
  Future<void> uninstall(
    String moduleId, {
    Future<void> Function()? onStop,
  }) async {
    Log().info('ModuleLifecycle: 卸载模块 $moduleId');

    // 1. 停止所有进程
    await onStop?.call();

    // 2. 删除 workspace 目录
    try {
      final wsDir = Directory(greenixWorkspaceDir(moduleId));
      if (wsDir.existsSync()) {
        await wsDir.delete(recursive: true);
        Log().info('ModuleLifecycle: workspace 目录已删除: ${wsDir.path}');
      }
    } catch (e) {
      Log().warn('ModuleLifecycle: 删除 workspace 目录失败 ($moduleId): $e');
    }

    // 3. 删除插件目录本身
    try {
      final pluginDir = Directory(p.join(pluginsRoot, moduleId));
      if (pluginDir.existsSync()) {
        await pluginDir.delete(recursive: true);
        Log().info('ModuleLifecycle: 插件目录已删除: ${pluginDir.path}');
      }
    } catch (e) {
      Log().warn('ModuleLifecycle: 删除插件目录失败 ($moduleId): $e');
    }

    // 4. 清除状态
    _states.remove(moduleId);
    _savedModuleProcess.remove(moduleId);

    Log().info('ModuleLifecycle: 模块 $moduleId 卸载完成（memory 已保留）');
  }

  // ═══════ 禁用 ═══════

  /// 禁用模块。
  ///
  /// 1. 冻结所有状态：停止所有进程
  /// 2. **不删除任何数据**（workspace + memory 完整保留）
  /// 3. 标记为 [ModuleState.disabled]
  ///
  /// [onStop] — 外部提供的进程停止回调。
  /// [descriptor] — 保存模块级进程描述符，供恢复时使用。
  Future<void> disable(
    String moduleId, {
    Future<void> Function()? onStop,
    ModuleDescriptor? descriptor,
  }) async {
    Log().info('ModuleLifecycle: 禁用模块 $moduleId');

    // 1. 停止所有进程
    await onStop?.call();

    // 2. 保存模块级进程描述符（用于恢复）
    if (descriptor?.process != null) {
      _savedModuleProcess[moduleId] = descriptor!.process!.toJson();
    }

    // 3. 标记为 disabled
    _states[moduleId] = ModuleState.disabled;

    Log().info('ModuleLifecycle: 模块 $moduleId 已禁用（数据完整保留）');
  }

  /// 启用模块（从 disabled 恢复）。
  ///
  /// 1. 恢复状态标记为 [ModuleState.active]
  /// 2. 返回 true 表示模块已恢复（调用方负责重启进程）
  ///
  /// 不自动重启进程——由调用方在恢复后调用 [ProcessManager.startModule]。
  /// 返回已保存的模块级进程描述符（如果有），供调用方重启。
  Map<String, dynamic>? enable(String moduleId) {
    final current = _states[moduleId];
    if (current == ModuleState.disabled) {
      _states[moduleId] = ModuleState.active;
      Log().info('ModuleLifecycle: 模块 $moduleId 已启用');

      // 返回保存的进程描述符，供调用方重启
      return _savedModuleProcess[moduleId];
    }

    if (current == ModuleState.active) {
      Log().warn('ModuleLifecycle: 模块 $moduleId 已处于 active 状态，跳过');
      return _savedModuleProcess[moduleId];
    }

    Log().warn('ModuleLifecycle: 模块 $moduleId 未安装，无法启用');
    return null;
  }

  // ═══════ 升级 ═══════

  /// 升级模块。
  ///
  /// 策略：不做数据迁移，新字段给默认值；旧字段保持不变。
  ///
  /// 流程：
  /// 1. 禁用当前模块（停进程、冻结状态）
  /// 2. 用新的 [ModuleDescriptor] 替换
  /// 3. 重新创建 workspace 子目录（`ensureWorkspaceSubdirs` 仅在不存在时创建）
  /// 4. 启用模块
  ///
  /// [onStop] — 旧模块进程停止回调。
  /// [onRestart] — 新模块进程重启回调（传入新 descriptor）。
  Future<void> upgrade({
    required String moduleId,
    required ModuleDescriptor newDescriptor, {
    Future<void> Function()? onStop,
    Future<void> Function(ModuleDescriptor newDesc)? onRestart,
  }) async {
    Log().info('ModuleLifecycle: 升级模块 $moduleId → v${newDescriptor.version}');

    // 1. 禁用（停进程、冻结状态）
    await disable(moduleId, onStop: onStop);

    // 2. 确保 workspace 子目录存在（不覆盖已有数据）
    _ensureWorkspaceSubdirs(moduleId, overwrite: false);

    // 3. 更新保存的进程描述符
    if (newDescriptor.process != null) {
      _savedModuleProcess[moduleId] = newDescriptor.process!.toJson();
    }

    // 4. 启用
    _states[moduleId] = ModuleState.active;

    // 5. 通知重启
    await onRestart?.call(newDescriptor);

    Log().info('ModuleLifecycle: 模块 $moduleId 升级完成（数据未迁移，旧字段保留）');
  }

  // ═══════ 内部辅助 ═══════

  /// 创建 workspace 子目录结构。
  ///
  /// ```
  /// .greenix/workspaces/<moduleId>/
  /// ├── _shared/        ← 栏间显式共享
  /// └── _ai/            ← AI 工作产物
  /// ```
  ///
  /// [overwrite] 为 true 时强制重建所有子目录；为 false 时仅在不存在时创建。
  void _ensureWorkspaceSubdirs(String moduleId, {bool overwrite = true}) {
    final base = greenixWorkspaceDir(moduleId);

    for (final sub in ['_shared', '_ai']) {
      final subDir = Directory(p.join(base, sub));
      if (overwrite) {
        if (!subDir.existsSync()) subDir.createSync(recursive: true);
      } else {
        // 升级模式：仅在不存在时创建
        if (!subDir.existsSync()) {
          subDir.createSync(recursive: true);
        }
      }
    }
  }

  /// 确保 memory 存储目录存在。
  void _ensureMemoryDir(String moduleId) {
    final memDir = Directory(p.join(greenixMemoriesDir, 'plugin', moduleId));
    if (!memDir.existsSync()) {
      memDir.createSync(recursive: true);
      Log().info('ModuleLifecycle: memory 目录已创建: ${memDir.path}');
    }
  }
}
