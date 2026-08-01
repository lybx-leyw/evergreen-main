/// 能力维度枚举——定义插件可以提供的六种能力类型。
///
/// 每个维度对应 `plugins/<name>/` 下的一个子目录或配置。
///
/// # 维度说明
///
/// | 维度 | 检测方式 | 说明 |
/// |---|---|---|
/// | `agent` | `plugins/<name>/agent/` 目录存在 | AI 工具声明（PluginBridge） |
/// | `module` | `plugins/<name>/module/manifest.json` | UI 模块声明（ModuleLoader） |
/// | `theme` | `plugins/<name>/theme/` 目录存在 | 配色声明（ThemeLoader） |
/// | `data` | `plugins/<name>/data/manifest.json` | 数据源声明（DataSourceLoader） |
/// | `config` | `plugins/<name>/config/config.json` | 设置项声明（SettingsLoader） |
/// | `process` | `ModuleDescriptor.process != null` | 后端 .exe 进程 |
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/log.dart';
import 'module_descriptor.dart';

/// 插件能力维度——六种能力类型。
///
/// 由 [discoverCapabilities] 自动从插件目录结构检测。
enum CapabilityDimension {
  /// AI 工具声明——plugins/<name>/agent/ 目录存在。
  agent,

  /// UI 模块声明——plugins/<name>/module/manifest.json。
  module,

  /// 配色主题声明——plugins/<name>/theme/ 目录存在。
  theme,

  /// 数据源声明——plugins/<name>/data/manifest.json。
  data,

  /// 设置项声明——plugins/<name>/config/config.json。
  config,

  /// 后端进程——ModuleDescriptor 中包含 process 字段。
  process,
}

/// 从字符串解析能力维度（用于 HTTP 查询参数 `?dim=`）。
///
/// 不区分大小写。无法匹配时返回 `null`。
CapabilityDimension? parseCapabilityDimension(String name) {
  for (final dim in CapabilityDimension.values) {
    if (dim.name.toLowerCase() == name.toLowerCase()) return dim;
  }
  return null;
}

/// 扫描插件目录，自动发现其具备的能力维度。
///
/// 检查 `plugins/<name>/` 下的各子目录和 manifest 文件：
/// - `agent/` 目录 → [CapabilityDimension.agent]
/// - `module/manifest.json` → [CapabilityDimension.module]
/// - `theme/` 目录 → [CapabilityDimension.theme]
/// - `data/manifest.json` → [CapabilityDimension.data]
/// - `config/config.json` → [CapabilityDimension.config]
///
/// [descriptor] 是可选的——传入已解析的 [ModuleDescriptor] 可额外检测
/// [CapabilityDimension.process]。
List<CapabilityDimension> discoverCapabilities(
  String pluginDir, {
  ModuleDescriptor? descriptor,
}) {
  final dims = <CapabilityDimension>[];

  final dir = Directory(pluginDir);
  if (!dir.existsSync()) return dims;

  // agent/
  if (Directory(p.join(pluginDir, 'agent')).existsSync()) {
    dims.add(CapabilityDimension.agent);
  }

  // module/manifest.json
  if (File(p.join(pluginDir, 'module', 'manifest.json')).existsSync()) {
    dims.add(CapabilityDimension.module);
  }

  // theme/
  if (Directory(p.join(pluginDir, 'theme')).existsSync()) {
    dims.add(CapabilityDimension.theme);
  }

  // data/manifest.json
  if (File(p.join(pluginDir, 'data', 'manifest.json')).existsSync()) {
    dims.add(CapabilityDimension.data);
  }

  // config/config.json
  if (File(p.join(pluginDir, 'config', 'config.json')).existsSync()) {
    dims.add(CapabilityDimension.config);
  }

  // process (.exe 后端)
  if (descriptor != null) {
    dims.add(CapabilityDimension.process);
  }

  Log().debug('discoverCapabilities: $pluginDir → ${dims.map((d) => d.name).toList()}');
  return dims;
}
