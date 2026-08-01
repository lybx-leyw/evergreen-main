/// Config HTTP Server — 将配置能力暴露为内部 HTTP API。
///
/// 插件 .exe 通过本端点读写设置、权限、插件源，无需直接访问 SharedPreferences。
/// 启动后端口写入 `.config_port` 文件，供外部 .exe 发现。
///
/// ## 9 端点一览
/// | # | 方法 | 路径 | 说明 |
/// |---|------|------|------|
/// | 1 | GET  | `/config/health`           | 健康检查 |
/// | 2 | GET  | `/config/settings`         | 列出所有设置项 |
/// | 3 | GET  | `/config/settings/:key`    | 读取单个设置 |
/// | 4 | POST | `/config/settings`         | 批量写入设置（body: {"key":"...","value":"..."}） |
/// | 5 | POST | `/config/settings/:key`    | 按路径写入设置（body: {"value":"..."}） |
/// | 6 | GET  | `/config/permissions/:id`  | 读取插件权限 |
/// | 7 | POST | `/config/permissions/:id`  | 设置插件权限 |
/// | 8 | GET  | `/config/sources`          | 列出插件源 |
/// | 9 | POST | `/config/sources`          | 添加/删除插件源 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import 'permissions.dart';
import 'sources.dart';
import 'exceptions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ConfigHttpServer
// ═══════════════════════════════════════════════════════════════════════════

/// 配置层 HTTP 服务器。供插件 .exe 通过 HTTP 读写设置、权限、源。
class ConfigHttpServer {
  final SharedPreferences _prefs;
  final int _requestedPort;

  HttpServer? _server;
  bool _running = false;
  int _lastStatus = 0;

  /// 动态注册的设置项（未在 config.json 中声明，运行时注入）。
  /// key → label 映射。
  final Map<String, String> _dynamicSettings = {};

  /// `.greenix/config.json` 的绝对路径。
  /// 设置后，每次配置变更都会同步覆写该文件。
  String? _greenixConfigPath;

  ConfigHttpServer(this._prefs, {int port = 0}) : _requestedPort = port;

  /// 是否正在监听。
  bool get isRunning => _running;

  /// 实际端口号（未启动时返回 0）。
  int get port => _server?.port ?? 0;

  /// 动态注册一个全局配置项（无需 config.json 声明）。
  ///
  /// 注册后可通过 HTTP `GET/POST /config/settings/{key}` 读写，
  /// 并在 `GET /config/settings` 列表中显示。
  /// 若 key 已存在于静态声明或动态注册表，则覆盖 label。
  void registerSetting(String key, String label) {
    _dynamicSettings[key] = label;
    stderr.writeln('[ConfigHttp] 📝 动态注册: $key ($label)');
  }

  /// 取消注册一个动态配置项。
  void unregisterSetting(String key) {
    _dynamicSettings.remove(key);
    stderr.writeln('[ConfigHttp] 🗑 取消注册: $key');
  }

  /// 启动监听。返回实际绑定的端口号。
  Future<int> start() async {
    if (_running) return _server!.port;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _requestedPort,
    );
    _running = true;

    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// 关闭服务器。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _server?.close(force: true);
    _server = null;
  }

  /// 设置 `.greenix/config.json` 的写入路径，并执行首次全量同步。
  ///
  /// 应在 [start] 成功后调用，使 scraper 脚本的 `_get_config()` Tier 2 降级
  /// 能直接读取本地 JSON 文件（无需 HTTP 发现 ConfigHttpServer）。
  void setGreenixConfigPath(String path) {
    _greenixConfigPath = path;
    syncConfigToGreenix();
  }

  /// 将所有配置项（静态声明 + 动态注册）覆写到 `.greenix/config.json`。
  ///
  /// 公开方法，允许 main.dart 在注册动态设置后强制刷新。
  /// 格式: `{"KEY": "value", ...}`（扁平 JSON 字典）。
  /// 父目录不存在时自动创建。
  ///
  /// ⚠️ 保护机制：已有非空值不被 SharedPreferences 空值覆写。
  /// Android 首次启动时 prefs 可能全部为空 → 若直接覆写会把设置面板
  /// 用户已填入的真实凭证清空。
  void syncConfigToGreenix() {
    if (_greenixConfigPath == null) {
      print('[ConfigHttp] ⚠ syncConfigToGreenix 跳过: _greenixConfigPath==null');
      return;
    }
    try {
      print('[ConfigHttp] 🔄 syncConfigToGreenix 开始 path=$_greenixConfigPath');
      final file = File(_greenixConfigPath!);

      // 1. 读取已有 config.json，记住所有 key（含空值）。
      //    注意：必须包含空值 key，否则安全网写入的空值 key 会在同步时被丢弃，
      //    导致 Python scraper 三级降级全失败。
      final existingAll = <String, String>{};
      if (file.existsSync()) {
        try {
          final raw = file.readAsStringSync();
          final map = jsonDecode(raw) as Map<String, dynamic>;
          for (final e in map.entries) {
            existingAll[e.key] = e.value?.toString() ?? '';
          }
          print('[ConfigHttp] 📖 读取 config.json OK, ${existingAll.length} keys');
          print('[ConfigHttp]    hasZJU_USERNAME=${existingAll.containsKey("ZJU_USERNAME")}');
          print('[ConfigHttp]    ZJU_USERNAME.val="${existingAll["ZJU_USERNAME"]}"');
        } catch (e) {
          print('[ConfigHttp] ❌ 读取 config.json 失败: $e — existingAll 将为空，所有仅存在于文件的 key（如安全网写入的 ZJU_USERNAME）将丢失！');
        }
      } else {
        print('[ConfigHttp] 📖 config.json 尚不存在');
      }

      // 2. 构建新配置（来自 SharedPreferences）
      final allSettings = getAllSettings(_prefs);
      print('[ConfigHttp] 📋 getAllSettings: ${allSettings.length} 项, hasZJU_USERNAME=${allSettings.any((s) => s.decl.key == "ZJU_USERNAME")}');
      print('[ConfigHttp] 📋 _dynamicSettings: ${_dynamicSettings.keys.toList()}');

      final config = <String, String>{};
      for (final s in allSettings) {
        config[s.decl.key] = s.value;
      }
      for (final key in _dynamicSettings.keys) {
        config[key] = getSetting(_prefs, key);
      }
      print('[ConfigHttp] 📋 config(from prefs): ${config.length} keys, hasZJU_USERNAME=${config.containsKey("ZJU_USERNAME")}');

      // 3. 兜底：已有文件的所有 key 必须保留（含空值），非空值优先于 prefs 空值
      int preserved = 0;
      for (final e in existingAll.entries) {
        final newVal = config[e.key];
        if (newVal == null) {
          // key 完全不在 SharedPreferences → 保留已有值（含空值，安全网写入）
          config[e.key] = e.value;
          preserved++;
          if (e.key == 'ZJU_USERNAME') {
            print('[ConfigHttp] 🔒 ZJU_USERNAME 完全不在 prefs，从文件保留: "${e.value}"');
          }
        } else if (newVal.isEmpty && e.value.isNotEmpty) {
          // SharedPreferences 有空值但文件有非空值 → 用文件的值（防覆盖）
          config[e.key] = e.value;
          preserved++;
          if (e.key == 'ZJU_USERNAME') {
            print('[ConfigHttp] 🔒 ZJU_USERNAME prefs 空但文件有非空值，从文件保留: "${e.value}"');
          }
        }
        // else: SharedPreferences 有非空值 → 保留 prefs 值（用户新填入的优先）
      }

      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(config));

      // 步骤 4：写回后立即验证 ZJU_USERNAME 是否真的在文件中
      try {
        final verifyRaw = file.readAsStringSync();
        final verifyMap = jsonDecode(verifyRaw) as Map<String, dynamic>;
        print('[ConfigHttp] ✅ 写入完成: ${config.length} 项, preserved=$preserved');
        print('[ConfigHttp]    verify hasZJU_USERNAME=${verifyMap.containsKey("ZJU_USERNAME")}');
        print('[ConfigHttp]    verify ZJU_USERNAME.val="${verifyMap["ZJU_USERNAME"]}"');
      } catch (ve) {
        print('[ConfigHttp] ❌ 写入后验证失败: $ve');
      }

      if (preserved > 0) {
        print('[ConfigHttp]    🔒 保留 $preserved 项（来自已有文件）');
      }
    } catch (e) {
      print('[ConfigHttp] ❌ 同步 greenix config 失败：$e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 路由
  // ═══════════════════════════════════════════════════════════════════════

  static final _paramPattern = RegExp(r'^:(\w+)$');

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      await _dispatch(request);
    } catch (e) {
      _respond(request.response, 500, {'error': '内部错误: $e'});
      stderr.writeln('[ConfigHttp] ${request.method} ${request.uri.path} → 500 (ERROR: $e)');
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;
    final sw = Stopwatch()..start();
    stderr.writeln('[ConfigHttp] $method $path');

    final segments =
        path.split('/')..removeAt(0); // drop leading empty

    // 精确匹配
    final exactKey = '$method $path';
    final exact = _routes[exactKey];
    if (exact != null) {
      await exact(request, {});
      stderr.writeln('[ConfigHttp] $method $path → $_lastStatus (${sw.elapsedMilliseconds}ms)');
      return;
    }

    // 参数匹配
    for (final entry in _paramRoutes.entries) {
      final parts = entry.key.split(' ');
      if (parts[0] != method) continue;
      final patternSegments =
          parts[1].split('/')..removeAt(0);
      if (patternSegments.length != segments.length) continue;

      final params = <String, String>{};
      var match = true;
      for (var i = 0; i < patternSegments.length; i++) {
        final pm = _paramPattern.firstMatch(patternSegments[i]);
        if (pm != null) {
          params[pm.group(1)!] = segments[i];
        } else if (patternSegments[i] != segments[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        await entry.value(request, params);
        stderr.writeln('[ConfigHttp] $method $path → $_lastStatus (${sw.elapsedMilliseconds}ms)');
        return;
      }
    }

    // 404
    _respond(request.response, 404, {
      'error': '未找到: $method $path',
    });
    stderr.writeln('[ConfigHttp] $method $path → 404 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 路由表 ──

  late final Map<String, Future<void> Function(HttpRequest, Map<String, String>)>
      _routes = {
    // 1: health
    'GET /config/health': (req, _) async {
      _respond(req.response, 200, {
        'status': 'ok',
        'settingsCount': getAllSettings(_prefs).length,
      });
    },

    // 2: list all settings
    'GET /config/settings': (req, _) async {
      final all = getAllSettings(_prefs);
      // 合并动态注册的设置项
      final dynamicSettings = _dynamicSettings.entries.map((e) => {
            'key': e.key,
            'label': e.value,
            'type': 'string',
            'value': getSetting(_prefs, e.key),
            'defaultValue': '',
            'isSecure': true,
            'hint': '动态注入的配置项',
            'options': null,
          }).toList();
      _respond(req.response, 200, {
        'settings': [
          ...all.map((s) => {
                'key': s.decl.key,
                'label': s.decl.label,
                'type': s.decl.type.name,
                'value': s.value,
                'defaultValue': s.decl.defaultValue,
                'isSecure': s.decl.isSecure,
                'hint': s.decl.hint,
                'options': s.decl.options
                    ?.map((o) => {'value': o.value, 'label': o.label})
                    .toList(),
              }),
          ...dynamicSettings,
        ],
      });
    },

    // 4: write setting by body key (SaveCredentialTool 使用)
    'POST /config/settings': (req, _) async {
      final body = await _readBody(req);
      final key = body['key'] as String?;
      final value = body['value'] as String?;
      if (key == null || key.isEmpty) {
        _respond(req.response, 400, {'error': '缺少 key'});
        return;
      }
      if (value == null) {
        _respond(req.response, 400, {'error': '缺少 value'});
        return;
      }
      try {
        await setSetting(_prefs, key, value);
        // 自动注册为动态设置项（若尚未声明）
        if (!_dynamicSettings.containsKey(key)) {
          _dynamicSettings[key] = key;
        }
        syncConfigToGreenix();
        _respond(req.response, 200, {'key': key, 'value': value, 'registered': true});
      } on ConfigValidationException catch (e) {
        _respond(req.response, 400, {'error': '$e'});
      }
    },

    // 7: list sources
    'GET /config/sources': (req, _) async {
      final sources = getSources(_prefs);
      _respond(req.response, 200, {
        'sources': sources.map((s) => {
              'url': s.url,
              'name': s.name,
              'isDefault': s.isDefault,
            }).toList(),
      });
    },

    // 8: add/remove source
    'POST /config/sources': (req, _) async {
      final body = await _readBody(req);
      final action = body['action'] as String?;
      final url = body['url'] as String?;
      final name = body['name'] as String?;

      if (url == null || url.isEmpty) {
        _respond(req.response, 400, {'error': '缺少 url'});
        return;
      }

      try {
        if (action == 'add') {
          await addSource(_prefs, url, name ?? url);
          _respond(req.response, 200, {'added': url});
        } else if (action == 'remove') {
          await removeSource(_prefs, url);
          _respond(req.response, 200, {'removed': url});
        } else {
          _respond(req.response, 400, {
            'error': 'action 必须为 "add" 或 "remove"',
          });
        }
      } on SourceDuplicateException {
        _respond(req.response, 409, {'error': '源已存在: $url'});
      } on ConfigValidationException catch (e) {
        _respond(req.response, 400, {'error': '$e'});
      }
    },
  };

  late final Map<String, Future<void> Function(HttpRequest, Map<String, String>)>
      _paramRoutes = {
    // 3: read single setting
    'GET /config/settings/:key': (req, p) async {
      final key = p['key']!;
      final value = getSetting(_prefs, key);
      _respond(req.response, 200, {'key': key, 'value': value});
    },

    // 5: write setting by URL path key
    'POST /config/settings/:key': (req, p) async {
      final key = p['key']!;
      final body = await _readBody(req);
      final value = body['value'] as String?;
      if (value == null) {
        _respond(req.response, 400, {'error': '缺少 value'});
        return;
      }
      await setSetting(_prefs, key, value);
      // 自动注册为动态设置项
      if (!_dynamicSettings.containsKey(key)) {
        _dynamicSettings[key] = key;
      }
      syncConfigToGreenix();
      _respond(req.response, 200, {'key': key, 'value': value});
    },

    // 6: read plugin permissions
    'GET /config/permissions/:id': (req, p) async {
      final id = p['id']!;
      final perms = getPermissions(_prefs, id);
      final decls = getPermissionDecls(id);
      _respond(req.response, 200, {
        'pluginId': id,
        'permissions': perms.entries.map((e) => {
              'key': e.key,
              'granted': e.value,
              'label': decls
                      ?.where((d) => d.key == e.key)
                      .firstOrNull
                      ?.label ??
                  e.key,
            }).toList(),
      });
    },

    // 7: set plugin permission
    'POST /config/permissions/:id': (req, p) async {
      final id = p['id']!;
      final body = await _readBody(req);
      final permKey = body['key'] as String?;
      final granted = body['granted'] as bool?;

      if (permKey == null) {
        _respond(req.response, 400, {'error': '缺少 key'});
        return;
      }
      if (granted == null) {
        _respond(req.response, 400, {'error': '缺少 granted (bool)'});
        return;
      }

      await setPermission(_prefs, id, permKey, granted);
      _respond(req.response, 200, {
        'pluginId': id,
        'key': permKey,
        'granted': granted,
      });
    },
  };

  // ═══════════════════════════════════════════════════════════════════════
  // 辅助
  // ═══════════════════════════════════════════════════════════════════════

  void _respond(HttpResponse response, int status, Map<String, dynamic> body) {
    _lastStatus = status;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.write(jsonEncode(body));
    response.close();
  }
}

/// 读取请求体 JSON。
Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
  final raw = await utf8.decodeStream(req);
  if (raw.isEmpty) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}
