/// module 2.0 示例。
///
/// 分两部分：
///   Part A — 覆盖 module/ 全部对外 API（ModuleDescriptor、ModuleRegistry、
///            ModuleLoader、SidebarSection、renderer）。
///   Part B — 用真实插件 .exe 演示多轮有状态 HTTP 交互。
///
/// 运行前需先构建 plugin.exe：
///   cd example/plugins/my_module
///   pyinstaller plugin.py --onefile --distpath .
import 'dart:convert';
import 'dart:io';
import '../modules.dart';
import '../lib/renderer.dart';

void main() async {
  final rootDir = Directory.current.path;
  final pluginsDir =
      '$rootDir${Platform.pathSeparator}example${Platform.pathSeparator}plugins';

  // ═══════════════════════════════════════════════════════════════
  // Part A: 对外接口全覆盖
  //
  // 覆盖 barrel (modules.dart) 导出的全部公开类和方法：
  //   ModuleRegistry  — register / registerAll / registerFromJson / seal /
  //                     modules / findById / buildRoutePaths /
  //                     navGroups / navFlat / paletteItems
  //   ModuleDescriptor — fromJson / fromJsonString(间接) / toJson / const 构造
  //                      isServiceOnly / hasSidebar / allRoutePaths
  //   ModuleLoader     — 构造 / isRunning / port / stop
  //   SidebarSection   — 构造 / == / hashCode / toString
  //   loadBuiltinModules / scanModules / scanAndLoadModules(间接)
  //   renderSidebar / renderModule
  // ═══════════════════════════════════════════════════════════════

  final registry = ModuleRegistry(); // 创建注册中心

  // ── A1. loadBuiltinModules — 加载 builtins/ 目录的内置模块 ──
  // 内置模块与外部插件使用同一种 manifest.json 格式。
  loadBuiltinModules('$rootDir${Platform.pathSeparator}builtins', registry);

  // ── A2. scanModules + registerAll — 扫描外部插件目录并批量注册 ──
  // scanModules 只解析 manifest.json，不启动进程。
  // registerAll 等价于逐个调用 register。
  final scanned = scanModules(pluginsDir);
  print('═══ scanModules: ${scanned.map((d) => d.id).join(', ')} ═══');
  registry.registerAll(scanned);

  // ── A3. registerFromJson — 从 JSON 字符串注册 ──
  // 内部调用 ModuleDescriptor.fromJsonString → ModuleDescriptor.fromJson →
  //   register。适用于无需 manifest 文件的快速注册。
  // V2: UI 范式通过 pages[].layout.slots 声明组件类型。
  registry.registerFromJson(
      '{"type":"module","id":"json_demo","name":"JSON 模块",'
      '"pages":[{"id":"doc","label":"文档","layout":{"type":"flex","slots":{'
      '"main":{"component":{"type":"document","config":{"trackChanges":true,"comments":true}}}}}}]}');

  // ── A4. ModuleDescriptor const 构造 — Dart 代码中直接构造 ──
  // 展示 const 构造所有子描述符的嵌套用法。
  // V2: UI 范式通过 pages[].layout.slots 的 ComponentDescriptor 声明。
  registry.register(const ModuleDescriptor(
    id: 'dart_demo',
    name: 'Dart 模块',
    pages: [
      PageDescriptor(
        id: 'chat',
        label: '对话',
        layout: LayoutDescriptor(
          type: 'flex',
          slots: {
            'main': SlotDescriptor(
              component: ComponentDescriptor(
                type: 'chat',
                config: {
                  'thinking': {'transparent': true, 'mode': 'scroll'},
                  'stream': {'cursorStyle': 'static'},
                },
                input: const InputOptions(
                  mode: 'code',
                  language: 'dart',
                ),
              ),
            ),
          },
        ),
      ),
    ],
    actions: ActionDescriptor(sortable: ['name'], exportable: ['csv']),
  ));

  // ── A5. seal — 锁定注册中心，校验依赖完整性 ──
  // seal 后不能再 register，所有只读 getter 可用。
  // 依赖校验：检查每个模块的 dependencies 是否都已注册。
  registry.seal();

  // ── A6. modules + toJson — 只读模块列表 + 序列化 ──
  // modules 返回 List<ModuleDescriptor>，seal 后才可调用。
  // toJson 将描述符转回 JSON，供调试/持久化。
  print('\n═══ modules (${registry.modules.length}) ═══');
  for (final m in registry.modules) {
    // isServiceOnly: route 为空时 = true（纯服务模块，无 UI）。
    // hasSidebar: 需同时有 icon + sidebar + route。
    final ui = _inferUiEx(m);
    print('  ${m.id.padRight(16)} ui=${ui.padRight(12)} service=${m.isServiceOnly} sidebar=${m.hasSidebar}');
  }
  print('═══ toJson (agent 前 150 字符) ═══');
  // 验证序列化：agent 模块 → JSON 字符串
  final agentModule = registry.findById('agent_from');
  print(const JsonEncoder.withIndent(' ')
      .convert(agentModule!.toJson())
      .substring(0, 150));

  // ── A7. findById — 按 id 查找模块 ──
  // 返回 ModuleDescriptor?，不存在时返回 null。
  print('\n═══ findById ═══');
  for (final id in ['agent_from', 'dart_demo', 'nonexistent']) {
    print('  $id → ${registry.findById(id)?.name ?? "(not found)"}');
  }

  // ── A8. buildRoutePaths — 收集所有模块路由路径 ──
  // 来源：module.route + layout.panels[].path + secondaryNavs[].routePath。
  // 框架层据此构建 GoRouter 路由表。
  print('\n═══ buildRoutePaths (${registry.buildRoutePaths().length}) ═══');
  for (final r in registry.buildRoutePaths()) {
    print('  $r');
  }

  // ── A9. navGroups / navFlat / paletteItems — 导航三件套 ──
  // navGroups: 按 SidebarSection 分组的导航条目，侧边栏渲染用。
  // navFlat: 扁平列表，collapsed 侧边栏用。
  // paletteItems: 命令面板条目（title/subtitle/icon/route/category 五元组）。
  print('\n═══ navGroups (${registry.navGroups.length} 组) ═══');
  for (final (sec, entries) in registry.navGroups) {
    print('  $sec');
    for (final e in entries) {    // NavEntry: icon + label + routePath + order
      print('    ${e.label} → ${e.routePath} (order=${e.order})');
    }
  }
  print('\n═══ navFlat (${registry.navFlat.length}) ═══');
  for (final e in registry.navFlat) {
    print('  ${e.label}');
  }
  print('\n═══ paletteItems (${registry.paletteItems.length}) ═══');
  for (final p in registry.paletteItems) {
    print('  ${p.title} [${p.category}]');
  }

  // ── A10. SidebarSection — 侧边栏分类（class 非 enum，插件可自定义） ──
  // == 基于 label + order 的 hashCode，同 label+order 即同一分组。
  const s = SidebarSection('自定义分类', order: 35);
  print('\n═══ SidebarSection ═══  $s  == self: ${s == s}');

  // ── A11. ModuleLoader 构造 + 属性 — 进程管理（不实际启动） ──
  // ModuleLoader 管理单个 process-backed 模块生命周期。
  // isRunning: 进程健康运行中（需 start 后）。
  // port: 监听端口（需 start 后）。
  final tmpLoader = ModuleLoader(
    ModuleDescriptor(id: '_tmp', name: 'Temp'),
    '.',
    projectRoot: rootDir,
  );
  print(
      '═══ ModuleLoader ═══  isRunning=${tmpLoader.isRunning}  port=${tmpLoader.port ?? "—"}');
  tmpLoader.stop(); // 清理（此处无进程，仅演示 API）

  // ── A12. 渲染器 — renderSidebar + renderModule ──
  // renderSidebar: 终端 ASCII 渲染侧边栏导航。
  // renderModule: 根据 ui 字段分派到对应渲染器（chat/default/spreadsheet/...）。
  print('\n═══ renderSidebar ═══');
  print(renderSidebar(registry));

  for (final m in registry.modules) {
    final ui = _inferUiEx(m);
    print('\n═══ renderModule(${m.id}) [ui=$ui] ═══');
    print(renderModule(m));
  }

  // ═══════════════════════════════════════════════════════════════
  // Part B: 真实插件 .exe 多轮交互
  //
  //  1. 初始状态 — GET /data  → 三条预置数据
  //  2. 搜索     — GET /search → 按姓名过滤
  //  3. 新增     — POST /items → 追加一条
  //  4. 编辑     — PUT  /items/:id → 更新分数
  //  5. 删除     — DELETE /items/:id → 移除
  //
  // 每轮改完都重新 GET /data 验证状态变化，证明 .exe 内存中维持数据。
  // ═══════════════════════════════════════════════════════════════

  final plugin = registry.findById('my_module');
  if (plugin == null || plugin.process.isEmpty) {
    print('\n═══ 跳过 .exe 演示 (无 process 字段) ═══');
    exit(0);
  }

  // 检查 .exe 是否存在。PyInstaller 构建：pyinstaller plugin.py --onefile --distpath .
  final pluginDir = '$pluginsDir${Platform.pathSeparator}my_module';
  final exePath = '$pluginDir${Platform.pathSeparator}${plugin.process.first.exe}';
  if (!File(exePath).existsSync()) {
    print(
        '\n$exePath 不存在。构建: cd $pluginDir && pyinstaller plugin.py --onefile --distpath .');
    exit(0);
  }

  // ModuleLoader.start() — 启动 exe → PORT 检测 → health check
  // 成功后 isRunning=true, port=监听端口
  final loader = ModuleLoader(plugin, pluginDir, projectRoot: rootDir);
  await loader.start();

  if (!loader.isRunning || loader.port == null) {
    print('\n✗ 后端未就绪 (isRunning=${loader.isRunning})');
    exit(0);
  }
  print('\n═══ .exe 就绪 (port=${loader.port}) ═══');

  final base = 'http://localhost:${loader.port}';
  final client = HttpClient();

  // 第 1 轮 — 初始状态：查看 plugin.py 预置的 3 条数据
  var data = await _get(client, '$base/data');
  print('═══ 第 1 轮: GET /data (初始) ═══');
  _show(data);

  // 第 2 轮 — 搜索：按姓名搜索，验证 /search?q= 端点
  var found = await _get(client, '$base/search?q=张');
  print('═══ 第 2 轮: GET /search?q=张 ═══');
  _show(found);

  // 第 3 轮 — 新增：POST /items 追加一条，再 GET /data 验证新增生效
  await _send(client, 'POST', '$base/items', {'name': '赵六', 'score': 88});
  data = await _get(client, '$base/data');
  print('═══ 第 3 轮: POST /items → GET /data (新增后) ═══');
  _show(data);

  // 第 4 轮 — 编辑：PUT /items/:id 更新分数，再 GET /data 验证修改生效
  final newId = (data.last as Map)['id'];
  await _send(client, 'PUT', '$base/items/$newId', {'score': 99});
  data = await _get(client, '$base/data');
  print('═══ 第 4 轮: PUT /items/$newId → GET /data (编辑后) ═══');
  _show(data);

  // 第 5 轮 — 删除：DELETE /items/:id 移除，再 GET /data 验证恢复初始条数
  await _send(client, 'DELETE', '$base/items/$newId', null);
  data = await _get(client, '$base/data');
  print('═══ 第 5 轮: DELETE /items/$newId → GET /data (删除后) ═══');
  _show(data);

  // 关闭 HTTP 客户端，停止后端进程
  client.close();
  loader.stop();  // cancel stdout 订阅 + SIGTERM 杀进程
  print('\n✓ 完成');
  exit(0);
}

// ═══════════════════════════════════════════════════════════════
// HTTP helpers
// ═══════════════════════════════════════════════════════════════

/// 格式化打印数据列表（id / name / score）。
void _show(List data) {
  if (data.isEmpty) return print('  (空)');
  for (final item in data) {
    print('  #${item['id']}  ${item['name']}  ${item['score']}分');
  }
}

/// 发送 GET 请求并解析 JSON 数组。
Future<List> _get(HttpClient c, String url) async {
  final r = await (await c.getUrl(Uri.parse(url))).close();
  return jsonDecode(await r.transform(utf8.decoder).join()) as List;
}

/// 发送 POST / PUT / DELETE 请求。
///
/// body 为 null 时不发送请求体（如 DELETE 无 body）。
/// 使用 req.add(bytes) + contentLength 确保 Content-Length 头正确发送，
/// 以便 Python http.server 的 rfile.read(length) 能正确读取。
Future<void> _send(
    HttpClient c, String method, String url, Map<String, dynamic>? body) async {
  final req = method == 'POST'
      ? await c.postUrl(Uri.parse(url))
      : method == 'PUT'
          ? await c.putUrl(Uri.parse(url))
          : await c.deleteUrl(Uri.parse(url));
  if (body != null) {
    final bytes = utf8.encode(jsonEncode(body));
    req.headers.contentType = ContentType.json;
    req.contentLength = bytes.length;
    req.add(bytes);
  }
  await req.close();
}

/// V2: 从模块的页面组件类型推断 UI 范式（替代 V1 的 m.ui）。
String _inferUiEx(ModuleDescriptor m) {
  if (m.pages.isEmpty) return '';
  final types = m.pages.expand((p) => p.componentTypes).toSet();
  if (types.contains('chat')) return 'chat';
  if (types.contains('spreadsheet')) return 'spreadsheet';
  if (types.contains('document')) return 'document';
  if (types.contains('presentation')) return 'presentation';
  if (types.contains('dashboard')) return 'dashboard';
  if (types.contains('editor')) return 'editor';
  return types.first;
}
