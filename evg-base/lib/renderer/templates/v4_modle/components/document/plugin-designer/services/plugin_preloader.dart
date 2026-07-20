/// 插件预加载器 —— 监控 plugins/ 目录变化，触发热加载。
///
/// 使用 `watcher` 包监控 manifest.json 文件变化，通过回调通知上游重建 ModuleRegistry。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// 插件变更事件。
class PluginChangeEvent {
  /// 变更的插件目录路径（如 `plugins/my-plugin/module/`）。
  final String pluginPath;

  /// 变更类型。
  final PluginChangeType type;

  /// 变更的 manifest.json 完整路径。
  final String manifestPath;

  /// 时间戳。
  final DateTime timestamp;

  const PluginChangeEvent({
    required this.pluginPath,
    required this.type,
    required this.manifestPath,
    required this.timestamp,
  });
}

/// 变更类型。
enum PluginChangeType {
  /// manifest 被创建。
  created,

  /// manifest 被修改。
  modified,

  /// manifest 被删除。
  deleted,
}

/// 监控 plugins/ 目录中 manifest.json 变化，触发热加载。
///
/// 用法：
/// ```dart
/// final preloader = PluginPreloader('plugins/');
/// preloader.onChange.listen((event) {
///   // 重新扫描模块
///   ModuleRegistry.rescan(event.pluginPath);
/// });
/// preloader.start();
/// ```
class PluginPreloader {
  final String _pluginsDir;
  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _sub;

  final _changeController =
      StreamController<PluginChangeEvent>.broadcast();
  Stream<PluginChangeEvent> get onChange => _changeController.stream;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  PluginPreloader(this._pluginsDir);

  /// 开始监控。
  void start() {
    if (_isRunning) return;
    final dir = Directory(_pluginsDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _watcher = DirectoryWatcher(_pluginsDir);
    _sub = _watcher!.events.listen(_onFileEvent);
    _isRunning = true;
  }

  /// 停止监控。
  void stop() {
    _sub?.cancel();
    _sub = null;
    _watcher = null;
    _isRunning = false;
  }

  void _onFileEvent(WatchEvent event) {
    final path = event.path;
    // 只关心 manifest.json 文件
    if (!path.endsWith('manifest.json')) return;
    // 忽略备份/临时文件
    if (path.contains('~') || path.contains('.tmp')) return;

    // 检查是否是 module/ 级别的 manifest（module/manifest.json）
    // 而非 data/manifest.json 或 config/manifest.json
    final normalized = path.replaceAll('\\', '/');
    if (!normalized.contains('/module/manifest.json')) return;

    PluginChangeType type;
    switch (event.type) {
      case ChangeType.ADD:
        type = PluginChangeType.created;
        break;
      case ChangeType.MODIFY:
        type = PluginChangeType.modified;
        break;
      case ChangeType.REMOVE:
        type = PluginChangeType.deleted;
        break;
      default:
        type = PluginChangeType.modified;
    }

    final pluginDir = p.dirname(p.dirname(path));

    _changeController.add(PluginChangeEvent(
      pluginPath: pluginDir,
      type: type,
      manifestPath: path,
      timestamp: DateTime.now(),
    ));
  }

  /// 释放资源。
  void dispose() {
    stop();
    _changeController.close();
  }
}
