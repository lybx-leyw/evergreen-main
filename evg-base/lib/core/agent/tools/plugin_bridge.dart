/// Plugin Bridge — 自动扫描 plugins/<name>/agent/.exe 并包装为 Tool。
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
      order: (json['order'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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

  const PluginManifest({
    required this.name,
    required this.description,
    required this.schema,
    this.readOnly = false,
    this.argMode = 'stdin',
    this.argSpec = const ArgSpec(),
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
    );
  }

  bool get isValid => name.isNotEmpty;
}

// ═══════ PluginTool ═══════

/// 包装单个 .exe 插件为 Agent Tool。
class PluginTool extends Tool {
  final String _exePath;
  final PluginManifest _manifest;

  PluginTool({required String exePath, required PluginManifest manifest})
      : _exePath = exePath,
        _manifest = manifest;

  @override
  String get name => _manifest.name;
  @override
  String get description => _manifest.description;
  @override
  Map<String, dynamic> get schema => _manifest.schema;
  @override
  bool get readOnly => _manifest.readOnly;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    try {
      final process = _manifest.argMode == 'args'
          ? await _runWithArgs(args)
          : await _runWithStdin(args);

      final exitCode = await process.exitCode;
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();

      if (exitCode != 0) {
        final errInfo = stderr.isNotEmpty ? '\n[stderr]\n$stderr' : '';
        return '[plugin "${_manifest.name}" exited with code $exitCode]$errInfo\n$stdout';
      }
      if (stderr.isNotEmpty) return '$stdout\n[stderr]\n$stderr';
      return stdout.isNotEmpty ? stdout : '_(no output)_';
    } catch (e) {
      return '[plugin "${_manifest.name}" error: $e]';
    }
  }

  Future<Process> _runWithStdin(Map<String, dynamic> args) async {
    final process = await Process.start(_exePath, [], mode: ProcessStartMode.normal);
    process.stdin.write(jsonEncode(args));
    await process.stdin.close();
    return process;
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

  Future<Process> _runWithArgs(Map<String, dynamic> args) async {
    return Process.start(_exePath, _buildArgv(args), mode: ProcessStartMode.normal);
  }
}

// ═══════ PluginBridge ═══════

/// 扫描 plugins/<name>/agent/ 目录，发现 .exe 并注册为 Tool。
class PluginBridge {
  /// 扫描目录，返回发现的所有 PluginTool。
  static List<Tool> discover(Directory pluginsDir) {
    if (!pluginsDir.existsSync()) return [];
    final tools = <Tool>[];
    for (final entry in pluginsDir.listSync()) {
      if (entry is! Directory) continue;
      final exeFile = _findExe(entry);
      if (exeFile == null) continue;
      final manifest = _readManifest(entry, exeFile);
      if (!manifest.isValid) continue;
      tools.add(PluginTool(exePath: exeFile.path, manifest: manifest));
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

  /// 在 agent/ 子目录中找 .exe，优先匹配与目录同名的。
  static File? _findExe(Directory dir) {
    final agentDir = Directory('${dir.path}/agent');
    if (!agentDir.existsSync()) return null;
    final dirName = dir.uri.pathSegments.last;
    File? firstExe;
    for (final f in agentDir.listSync()) {
      if (f is File && f.path.endsWith('.exe')) {
        final name = f.uri.pathSegments.last;
        if (name == '$dirName.exe') return f;
        firstExe ??= f;
      }
    }
    return firstExe;
  }

  /// 读取 manifest.json（必写），不存在或无效返回空 name。
  static PluginManifest _readManifest(Directory dir, File exeFile) {
    final mf = File('${dir.path}/agent/manifest.json');
    if (!mf.existsSync()) return const PluginManifest(name: '', description: '', schema: {});
    try {
      final m = PluginManifest.fromJson(mf.readAsStringSync());
      if (m.isValid) return m;
    } catch (_) {}
    return const PluginManifest(name: '', description: '', schema: {});
  }
}
