/// Plugin Bridge — 自动扫描 plugins/<name>/agent/ 下的 .py（统一主路径）或 .exe（legacy）并包装为 Tool。
///
/// ## API
/// | 方法 | 说明 |
/// |------|------|
/// | `PluginBridge.discover(Directory)` | 扫描目录，返回发现的全部 PluginTool |
/// | `PluginBridge.registerAll(Registry, Directory)` | 扫描并注册到 Registry |
/// | `PluginBridge.refresh(Registry, Directory)` | 重新扫描，同步增删 |
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import '../tool.dart';

// ═══════ ArgSpec ═══════

/// args 模式的命令行构造规范。
///
/// style：
/// - `flag`：每个 key → `--key value`，bool true → `--key`，bool false → 跳过。
/// - `positional`：按 order 数组顺序输出 value，不输出 key。
/// - `json`：退化为 `--args=<json>`（无 argSpec 时的默认行为）。
///
/// prefix：flag 前缀，默认 `--`。设为 `"-"` 即为短 flag，设为 `"/"` 为 Windows 风格。
/// flags：按 key 覆盖 flag 名，如 `{"query":"-q"}`。
/// order：positional 模式的参数顺序，不指定则按 schema properties 声明顺序。
class ArgSpec {
  final String style;
  final String prefix;
  final Map<String, String> flags;
  final List<String> order;

  const ArgSpec({
    this.style = 'json',
    this.prefix = '--',
    this.flags = const {},
    this.order = const [],
  });

  /// 无 argSpec 时默认 json 风格（`--args=<json>`）。
  factory ArgSpec.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ArgSpec();
    return ArgSpec(
      style: json['style']?.toString() ?? 'json',
      prefix: json['prefix']?.toString() ?? '--',
      flags: (json['flags'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      order: (json['order'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

// ═══════ PluginManifest ═══════

/// 从 manifest.json 解析的元数据。
class PluginManifest {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final bool readOnly;
  final String argMode;
  final ArgSpec argSpec;
  final String runtime;

  const PluginManifest({
    required this.name,
    required this.description,
    required this.schema,
    this.readOnly = false,
    this.argMode = 'stdin',
    this.argSpec = const ArgSpec(),
    this.runtime = 'native',
  });

  /// 从 JSON 字符串解析。
  factory PluginManifest.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final rawSpec = map['argSpec'];
    final argSpec = (rawSpec is Map<String, dynamic>)
        ? ArgSpec.fromJson(rawSpec)
        : const ArgSpec();
    return PluginManifest(
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      schema: (map['schema'] as Map<String, dynamic>?) ?? {
        'type': 'object',
        'properties': {},
      },
      readOnly: map['readOnly'] == true,
      argMode: map['argMode']?.toString() == 'args' ? 'args' : 'stdin',
      argSpec: argSpec,
      runtime: map['runtime'] as String? ?? 'native',
    );
  }

  bool get isValid => name.isNotEmpty;
}

// ═══════ PluginTool ═══════

/// 包装单个插件（.exe 或 .py）为 Agent Tool。
class PluginTool extends Tool {
  final String _exePath;
  final PluginManifest _manifest;
  PluginRunner? _runner;

  PluginTool({
    required String exePath,
    required PluginManifest manifest,
    PluginRunner? runner,
  })  : _exePath = exePath,
        _manifest = manifest,
        _runner = runner;

  @override
  String get name => _manifest.name;
  @override
  String get description => _manifest.description;
  @override
  Map<String, dynamic> get schema => _manifest.schema;
  @override
  bool get readOnly => _manifest.readOnly;

  /// 入口文件路径（`.py` 统一主路径；`.exe` 为 legacy 回退）。
  String get entryPath => _exePath;

  Future<PluginRunner> _ensureRunner() async {
    return _runner ??= await sharedPluginRunner;
  }

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final runner = await _ensureRunner();
      final RunResult res;
      if (_manifest.argMode == 'args') {
        res = await runner.runOnce(
          _exePath,
          _buildArgv(args),
          runtime: _manifest.runtime,
        );
      } else {
        res = await runner.runOnce(
          _exePath,
          const [],
          stdinJson: args,
          runtime: _manifest.runtime,
        );
      }
      if (res.exitCode != 0) {
        final errInfo =
            res.stderr.isNotEmpty ? '\n[stderr]\n${res.stderr}' : '';
        return '[plugin "${_manifest.name}" exited with code '
            '${res.exitCode}]$errInfo\n${res.stdout}';
      }
      if (res.stderr.isNotEmpty) {
        return '${res.stdout}\n[stderr]\n${res.stderr}';
      }
      return res.stdout.isNotEmpty ? res.stdout : '_(no output)_';
    } catch (e) {
      return '[plugin "${_manifest.name}" error: $e]';
    }
  }

  List<String> _buildArgv(Map<String, dynamic> args) {
    final spec = _manifest.argSpec;
    switch (spec.style) {
      case 'positional':
        return _buildPositional(args, spec);
      case 'flag':
        return _buildFlagArgs(args, spec);
      case 'json':
      default:
        return ['--args=${jsonEncode(args)}'];
    }
  }

  /// flag 风格：`--key value`。
  List<String> _buildFlagArgs(Map<String, dynamic> args, ArgSpec spec) {
    final argv = <String>[];
    for (final entry in args.entries) {
      final flag = spec.flags[entry.key] ?? '${spec.prefix}${entry.key}';
      final value = entry.value;
      if (value is bool) {
        if (value) argv.add(flag);
      } else if (value != null) {
        argv.add(flag);
        argv.add(value.toString());
      }
    }
    return argv;
  }

  /// positional 风格：按 order 顺序输出 value。
  List<String> _buildPositional(Map<String, dynamic> args, ArgSpec spec) {
    final argv = <String>[];
    final keys = spec.order.isNotEmpty
        ? spec.order
        : _manifest.schema['properties']?.keys.toList() ?? args.keys.toList();
    for (final key in keys) {
      final value = args[key];
      if (value != null) argv.add(value.toString());
    }
    return argv;
  }
}

// ═══════ PluginBridge ═══════

/// 扫描 plugins/<name>/agent/ 目录，发现 .py（统一主路径）或 .exe（legacy）并注册为 Tool。
class PluginBridge {
  /// 扫描目录，返回发现的所有 PluginTool。
  static List<Tool> discover(Directory pluginsDir) {
    if (!pluginsDir.existsSync()) return [];
    final tools = <Tool>[];
    for (final entry in pluginsDir.listSync()) {
      if (entry is! Directory) continue;
      final manifest = _readManifest(entry);
      if (!manifest.isValid) continue;
      final entryFile = _findEntry(entry, manifest);
      if (entryFile == null) continue;
      tools.add(PluginTool(exePath: entryFile.path, manifest: manifest));
    }
    return tools;
  }

  /// 扫描并注册到 Registry（已注册的跳过）。
  static void registerAll(Registry registry, Directory pluginsDir) {
    for (final t in discover(pluginsDir)) {
      if (!registry.has(t.name)) registry.register(t);
    }
  }

  /// 重新扫描并同步 Registry（新增注册，已删除的移除）。
  static void refresh(Registry registry, Directory pluginsDir) {
    final tools = discover(pluginsDir);
    final names = tools.map((t) => t.name).toSet();
    for (final t in registry.all()) {
      if (t is PluginTool && !names.contains(t.name)) registry.remove(t.name);
    }
    for (final t in tools) {
      if (!registry.has(t.name)) registry.register(t);
    }
  }

  /// 在 agent/ 子目录中找入口文件：**`.py` 优先**（统一 python 唯一路径，
  /// 同名 `<目录名>.py` 最高优先），仅当**无任何 `.py`** 且 manifest **未显式
  /// 声明 `runtime: "python"`**（即 native/缺省）时才回退 `.exe`（legacy 向后
  /// 兼容——存量 .exe 插件仍可运行）。
  static File? _findEntry(Directory dir, PluginManifest manifest) {
    final agentDir = Directory('${dir.path}/agent');
    if (!agentDir.existsSync()) return null;
    final dirName = dir.uri.pathSegments.last;
    File? firstPy;
    File? firstExe;
    for (final f in agentDir.listSync()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.py')) {
        if (name == '$dirName.py') return f; // 同名 .py 最高优先
        firstPy ??= f;
      } else if (name.endsWith('.exe')) {
        if (name == '$dirName.exe') {
          firstExe ??= f; // 同名 .exe 是候选但不再提前返回（.py 优先）
        } else {
          firstExe ??= f;
        }
      }
    }
    if (firstPy != null) return firstPy;
    // 无 .py：仅 manifest 未声明 runtime:"python"（native/缺省）时回退 .exe。
    // runtime:"python" 却只有 .exe 属声明错配，跳过该插件（fail 可见而非误跑）。
    if (firstExe != null && manifest.runtime != 'python') return firstExe;
    return null;
  }

  /// 读取 manifest.json（必写），不存在或无效返回空 name。
  static PluginManifest _readManifest(Directory dir) {
    final mf = File('${dir.path}/agent/manifest.json');
    if (!mf.existsSync()) {
      return const PluginManifest(name: '', description: '', schema: {});
    }
    try {
      final m = PluginManifest.fromJson(mf.readAsStringSync());
      if (m.isValid) return m;
    } catch (_) {}
    return const PluginManifest(name: '', description: '', schema: {});
  }
}
