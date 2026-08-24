/// Core API 端口发现 —— HTML 插件 bridge 代理层的基础设施。
///
/// core 侧 6 组 HttpServer（Agent/Config/Data/Module/Theme/Core）各自在
/// projectRoot 写入 `.xxx_port` 端口文件。本模块读取这些文件得到端口映射，
/// 供 bridge 转发 HTTP 请求使用；缺失/读取失败时降级为「服务不可用」。
///
/// ## 端口文件（写于 projectRoot）
/// - `.agent_port`  → AgentHttpServer（chat/stream、sessions、tools…）
/// - `.config_port` → ConfigHttpServer（settings、permissions、sources…）
/// - `.data_port`   → DataHttpServer（types、refresh、connectivity…）
/// - `.module_port` → ModuleHttpServer（模块路由查询，含 `/module/sidecars`）
/// - `.theme_port`  → ThemeHttpServer（主题配色查询）
/// - `.core_port`   → CoreHttpServer（install、ocr、plugins…）
///
/// ## 设计
/// - 依赖面小（dart:io / dart:convert / package:path + greenix_path 的
///   [androidPluginsDir] 常量，后者为纯字符串拼接，不触发平台通道），可独立单测。
/// - [findProjectRoot] 复用 `scraper_generator_view._findProjectRoot()` 同款逻辑：
///   桌面向上找 `pubspec.yaml`；Android 返回插件目录父级（与 AppBootstrap 一致）。
/// - [probeHealth] 对已发现端口的服务做 HTTP health 探测（`GET /health` /
///   `GET /xxx/health`），区分「端口文件存在但 HTTP 不通」（服务启动中/已崩溃）
///   与「完全未启动」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/utils/greenix_path.dart' show androidPluginsDir;
import 'package:path/path.dart' as p;

/// 6 组 core 服务的统一标识与端口文件名。
///
/// 各服务 health 端点（已核对 core 源码路由表）：
/// - Agent 为根路径 `GET /health`（其余 5 组均为 `GET /xxx/health`）。
enum CoreService {
  agent('agent', '.agent_port', '/health'),
  config('config', '.config_port', '/config/health'),
  data('data', '.data_port', '/data/health'),
  module('module', '.module_port', '/module/health'),
  theme('theme', '.theme_port', '/theme/health'),
  core('core', '.core_port', '/core/health');

  const CoreService(this.id, this.portFile, this.healthPath);

  /// 服务标识（bridge API 前缀）。
  final String id;

  /// 端口文件名（写于 projectRoot）。
  final String portFile;

  /// health 探测路径（未实现 health 的服务退化为 null → 仅文件探测）。
  final String healthPath;
}

/// 单个服务的可达性状态。
enum ServiceReachability {
  /// 端口文件存在且 HTTP health 探测通过（绿）。
  reachable,

  /// 端口文件存在但 health 探测失败（红：服务进程异常/端口占用）。
  degraded,

  /// 端口文件缺失（灰：服务未启动）。
  missing,

  /// 端口文件存在但内容非数字（红：文件损坏）。
  invalidPort,
}

/// 端口发现 + 可达性探测结果。
class CoreServiceStatus {
  final CoreService service;
  final int? port;
  final ServiceReachability reachability;
  final String? error;

  const CoreServiceStatus({
    required this.service,
    this.port,
    this.reachability = ServiceReachability.missing,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': service.id,
        'port': port,
        'reachability': reachability.name,
        'error': error,
      };

  @override
  String toString() =>
      'CoreServiceStatus(${service.id}: ${reachability.name}${port != null ? ' @$port' : ''})';
}

/// 端口发现器：读取 projectRoot 下 6 个 `.xxx_port` 文件 → 端口映射。
///
/// 带缓存（一次读取后复用），[refresh] 强制重读。所有方法纯同步
/// （端口文件读取是本地小文件 IO，同步即可），便于 bridge 同步转发。
class CoreApiDiscovery {
  /// 可选注入的 projectRoot（测试用）；为空时自动 [findProjectRoot]。
  final String? projectRootOverride;

  CoreApiDiscovery({this.projectRootOverride});

  Map<String, int>? _cache;
  String? _resolvedRoot;

  /// 定位 projectRoot：桌面向上找 pubspec.yaml；Android 为插件目录父级。
  ///
  /// 与 `scraper_generator_view._findProjectRoot()` / `AppBootstrap.projectRoot`
  /// 逻辑一致——端口文件由 core 各 HttpServer 写在这里。
  ///
  /// ⚠️ Android 关键修复（T1）：进程 CWD 是只读的 `/`，且无 pubspec.yaml。
  /// 若默认 `pluginsDir` 为字面量 `'plugins'`，`p.dirname('plugins')` 得到 `'.'`
  /// （即 `/`），`.config_port` 等端口文件永远找不到 → 6 组 core 服务全部误报
  /// 「未启动」，bridge 的 `platform.api.call` / `data.refresh` / `ai.chat`
  /// 全部抛「服务未启动（端口文件缺失）」。AppBootstrap 实际把端口文件写在
  /// `p.dirname(androidPluginsDir)`（应用可写目录下 `.greenix`），此处对齐：
  /// 默认 pluginsDir 取 [androidPluginsDir]，父级即端口文件所在目录。
  static String findProjectRoot({String? pluginsDir}) {
    if (Platform.isAndroid) {
      final plugins = pluginsDir ?? androidPluginsDir;
      return p.dirname(plugins);
    }
    var dir = Directory.current;
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current.path;
  }

  /// 当前 projectRoot（首次解析后缓存）。
  String get projectRoot {
    if (_resolvedRoot == null) {
      _resolvedRoot = projectRootOverride ?? findProjectRoot();
    }
    return _resolvedRoot!;
  }

  /// 读取全部 6 个端口文件，返回 `serviceId → port` 映射。
  ///
  /// - 文件缺失 / 内容非数字 → 该项不进入映射（降级为服务不可用）。
  /// - 结果缓存；调用 [refresh] 强制重读。
  Map<String, int> discover() {
    final cached = _cache;
    if (cached != null) return cached;

    final root = projectRoot;
    final result = <String, int>{};
    for (final svc in CoreService.values) {
      final file = File(p.join(root, svc.portFile));
      try {
        if (!file.existsSync()) continue;
        final raw = file.readAsStringSync().trim();
        final port = int.tryParse(raw);
        if (port == null || port <= 0 || port > 65535) continue;
        result[svc.id] = port;
      } catch (e) {
        debug('[CoreApiDiscovery] 读取 ${svc.portFile} 失败: $e');
      }
    }
    _cache = result;
    return result;
  }

  /// 强制重读端口文件（服务重启后端口可能变化）。
  Map<String, int> refresh() {
    _cache = null;
    return discover();
  }

  /// 获取单个服务端口；未发现返回 null。
  int? portOf(CoreService service) => discover()[service.id];

  /// 对单个服务做可达性探测。
  ///
  /// 两级判定：
  /// 1. 端口文件存在且解析出合法端口 → 继续 health 探测；
  /// 2. health 请求 200 且 `status == ok`（宽松匹配）→ reachable；
  ///    否则 → degraded。
  /// 文件缺失 → missing；内容非数字 → invalidPort。
  Future<CoreServiceStatus> probe(CoreService service,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final root = projectRoot;
    final file = File(p.join(root, service.portFile));

    // 1. 端口文件存在性
    try {
      if (!file.existsSync()) {
        return CoreServiceStatus(service: service);
      }
      final raw = file.readAsStringSync().trim();
      final port = int.tryParse(raw);
      if (port == null || port <= 0 || port > 65535) {
        return CoreServiceStatus(
          service: service,
          reachability: ServiceReachability.invalidPort,
          error: '端口文件内容非法: "$raw"',
        );
      }

      // 2. health 探测
      final ok = await _probeHealth(service, port, timeout: timeout);
      if (ok) {
        return CoreServiceStatus(
          service: service,
          port: port,
          reachability: ServiceReachability.reachable,
        );
      }
      return CoreServiceStatus(
        service: service,
        port: port,
        reachability: ServiceReachability.degraded,
        error: 'health 探测失败（HTTP 不可达）',
      );
    } catch (e) {
      return CoreServiceStatus(
        service: service,
        reachability: ServiceReachability.degraded,
        error: '探测异常: $e',
      );
    }
  }

  /// 探测全部 6 个服务的可达性（并行）。
  Future<List<CoreServiceStatus>> probeAll({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final futures = CoreService.values
        .map((s) => probe(s, timeout: timeout))
        .toList();
    return Future.wait(futures);
  }

  /// 对指定服务端口发 HTTP health 请求。
  Future<bool> _probeHealth(CoreService service, int port,
      {required Duration timeout}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port${service.healthPath}'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      debug('[CoreApiDiscovery] ${service.id} health ${res.statusCode}: $body');
      if (res.statusCode != 200) return false;
      // 宽松匹配：body 含 "ok" 即认为健康（各 server 响应格式略异）。
      return body.toLowerCase().contains('ok');
    } catch (e) {
      debug('[CoreApiDiscovery] ${service.id} health 失败: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 调试日志开关（单测/诊断用，避免刷屏）。
  static bool verbose = false;

  static void debug(String msg) {
    if (verbose) {
      // 不使用 debugPrint（本文件纯 Dart，bridge 侧有 Flutter 环境但保持解耦）。
      // ignore: avoid_print
      print(msg);
    }
  }
}

/// 便捷单例（bridge 与创作中心共用同一发现器实例，端口缓存共享）。
final CoreApiDiscovery coreApiDiscovery = CoreApiDiscovery();
