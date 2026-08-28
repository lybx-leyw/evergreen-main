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
import 'agent_process_registry.dart';
import 'vision_pdf_preprocess.dart';

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

  /// 进程生命周期（Task 三决策 3.1）：
  /// - `once`（默认）：一次性——AI 调用该 tool 后进程即被回收（现有 runOnce 路径）；
  /// - `resident`：常驻——AI 调用后进程持续运行，登记到后台进程注册表，
  ///   直到 AI 用 `kill_process` 主动结束。
  ///
  /// 解析：缺省 → `once`；未知值 → 静默回退 `once`（项目铁律「未知静默忽略」）。
  final String lifetime;

  /// 执行前预处理声明（Task R3-6，可选）：
  /// - `pdf_split`：vision 等文件类插件——python 执行前，Dart 侧识别
  ///   file_path=*.pdf 时预拆分（安卓经系统 PdfRenderer 渲染 pages_dir 注入；
  ///   桌面不触发，vision.py 内部 fitz 路径不变）。
  ///
  /// 解析：缺省/未知值 → `''`（不预处理，向后兼容旧插件；未知静默忽略）。
  final String preprocess;

  const PluginManifest({
    required this.name,
    required this.description,
    required this.schema,
    this.readOnly = false,
    this.argMode = 'stdin',
    this.argSpec = const ArgSpec(),
    this.runtime = 'native',
    this.lifetime = 'once',
    this.preprocess = '',
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
      lifetime: _parseLifetime(map['lifetime']),
      preprocess: map['preprocess']?.toString() ?? '',
    );
  }

  /// 解析 `lifetime`：仅 `"resident"` 命中常驻；缺省 / 未知值一律回退 `once`
  /// （向后兼容：旧插件无该字段行为不变）。
  static String _parseLifetime(dynamic raw) {
    final s = raw?.toString();
    if (s == 'resident') return 'resident';
    return 'once';
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
      // 执行前预处理（Task R3-6）：manifest 声明 `preprocess:"pdf_split"` 时，
      // 安卓侧在 python 执行前用系统 PdfRenderer 预拆分 PDF → 注入 pages_dir；
      // 失败/非安卓 → 原参透传（fail-open，vision.py 内部兜底：桌面 fitz /
      // 安卓降级提示——零行为变化）。
      var effectiveArgs = args;
      String? pagesDir;
      if (_manifest.preprocess == 'pdf_split') {
        final outcome = await VisionPdfPreprocess.trySplitPdf(args);
        if (outcome != null) {
          effectiveArgs = outcome.args;
          pagesDir = outcome.pagesDir;
        }
      }
      try {
        // 常驻插件（lifetime:"resident"）：startLong 常驻 + 登记后台注册表，
        // execute 立即返回「已后台启动」占位文本。
        return (_manifest.lifetime == 'resident')
            ? await _executeResident(runner, effectiveArgs)
            : await _executeOnce(runner, effectiveArgs);
      } finally {
        // 预拆分页图片目录在 python 执行结束后回收（vision 为 once 生命周期，
        // python 进程内已读入字节；resident 常驻进程可能在执行返回后异步读目录，
        // 故不清理）。删除失败静默忽略——系统 cache 目录兜底回收。
        if (pagesDir != null && _manifest.lifetime != 'resident') {
          try {
            Directory(pagesDir).deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      return '[plugin "${_manifest.name}" error: $e]';
    }
  }

  /// 一次性执行（lifetime 缺省 / `once`，向后兼容的既有路径）。
  Future<String> _executeOnce(PluginRunner runner, Map<String, dynamic> args) async {
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
  }

  /// 常驻执行（lifetime:"resident"）：经 [PluginRunner.startLong] 启动后
  /// 登记到全局后台进程注册表，返回「已后台启动」占位文本；进程输出在后台
  /// 累积，AI 可后续用 `list_processes` 查看、`kill_process` 结束。
  ///
  /// 幂等：同 key（工具名）已在运行则不重复启动。
  Future<String> _executeResident(
      PluginRunner runner, Map<String, dynamic> args) async {
    final key = _manifest.name;
    if (agentProcessRegistry.isRunning(key)) {
      return '[后台已运行: $key] 进程已在后台运行，输出将自动回填。'
          '可用 list_processes 查看累积输出，或 kill_process 结束。';
    }
    final argv = _manifest.argMode == 'args'
        ? _buildArgv(args)
        : const <String>[];
    final proc = await runner.startLong(
      _exePath,
      argv,
      runtime: _manifest.runtime,
    );
    if (_manifest.argMode == 'stdin') {
      try {
        proc.stdin.write(jsonEncode(args));
        await proc.stdin.close();
      } catch (_) {
        // 进程可能已退出或 stdin 不可写：忽略，常驻进程仍以空参数运行。
      }
    }
    agentProcessRegistry.attach(key, proc);
    return '[后台已启动: $key] 输出将自动回填。'
        '可用 list_processes 查看累积输出，或 kill_process 结束。';
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
