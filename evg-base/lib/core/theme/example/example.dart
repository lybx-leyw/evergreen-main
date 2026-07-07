/// theme 模块全部对外接口使用示例。
///
/// 覆盖 barrel (theme.dart) 导出的所有公开 API：
///   ThemeDescriptor  — const 构造 / fromJson / fromJsonString / toJson /
///                      tokenValue / tokenColor / parseHex
///   ThemeStore       — register / all / findById / activeTheme / setActiveById / activeOrFirst
///   ThemeHttpServer  — start / stop / 6 端点
///   scanThemes / loadThemes / scanThemeFile
///   render_rules     — Spacing / Radii / FontSize / Shadows / Durations / ComponentSize
///   ThemeColor       — fromHex / tryParse / toHex
import 'dart:io';
import '../theme.dart';

void main() {
  // ═══════ ThemeDescriptor ═══════
  final store = ThemeStore();
  final rootDir = Directory.current.path;

  // ── const 构造（五层正交架构）──
  const programmatic = ThemeDescriptor(
    id: 'programmatic',
    name: '程序化主题',
    app: {'sidebar': {'active': '#9C27B0'}},
    module: {},
    page: {},
    slot: {},
    components: {'button': {'primary': '#9C27B0', 'text': '#FFFFFF'}},
  );
  store.register(programmatic);

  // ── fromJsonString（直接加载内置主题文件）──
  final lightFile = File('$rootDir${Platform.pathSeparator}builtins${Platform.pathSeparator}light${Platform.pathSeparator}theme${Platform.pathSeparator}theme.json');
  if (lightFile.existsSync()) {
    store.register(ThemeDescriptor.fromJsonString(lightFile.readAsStringSync()));
  }

  // ── loadThemes — 扫描内置主题 ──
  // 内置主题优先级最低，插件可覆盖同 id 主题。
  loadThemes('$rootDir${Platform.pathSeparator}builtins', store);
  print('═══ 内置主题: ${store.all.map((t) => t.name).join(', ')} ═══');
  print('   共 ${store.all.length} 个\n');

  // ── scanThemeFile — 单文件加载 ──
  try {
    final builtinTheme = scanThemeFile(
        '$rootDir${Platform.pathSeparator}builtins${Platform.pathSeparator}light${Platform.pathSeparator}theme${Platform.pathSeparator}theme.json');
    print('   单文件加载: ${builtinTheme.name} (id=${builtinTheme.id})');
  } catch (e) {
    print('   (scanThemeFile 跳过: $e)');
  }

  // ── scanThemes — 扫描示例插件 ──
  final pluginDir =
      '$rootDir${Platform.pathSeparator}example${Platform.pathSeparator}plugins';
  final scanned = scanThemes(pluginDir);
  for (final t in scanned) {
    store.register(t);
  }

  // ═══════ ThemeStore 响应式切换 ═══════
  // 默认激活 light 主题
  store.setActiveById('light');
  print('═══ 活跃主题: ${store.activeTheme?.name} (id=${store.activeTheme?.id}) ═══');

  // 注册 ChangeNotifier 监听
  store.addListener(() {
    print('   [通知] 主题已切换 → ${store.activeTheme?.name}');
  });

  // 切换为 dark 主题
  store.setActiveById('dark');
  print('   切换后: ${store.activeTheme?.name}\n');

  // activeOrFirst — 未设置时回退第一个已注册主题
  final fallback = ThemeStore();
  fallback.register(const ThemeDescriptor(
    id: 'only',
    name: '唯一主题',
    app: {},
    module: {},
    page: {},
    slot: {},
    components: {},
  ));
  print('   activeOrFirst (未设置): ${fallback.activeOrFirst?.name}');

  // ═══════ 颜色查询 ═══════
  print('\n═══ 颜色查询 ═══');
  final active = store.activeTheme!;

  // tokenValue(layer, component, subToken) — 字符串查询
  print('   tokenValue(app, "sidebar", "active") = ${active.tokenValue(active.app, 'sidebar', 'active')}');
  print('   tokenValue(components, "button", "primary") = ${active.tokenValue(active.components, 'button', 'primary')}');

  // tokenColor(layer, component, subToken) — ThemeColor 查询
  final sc = active.tokenColor(active.app, 'sidebar', 'active');
  print('   tokenColor(app, "sidebar", "active") = ${sc?.toHex()} (value=0x${sc?.value.toRadixString(16)})');

  // 直接访问层数据
  print('   app.sidebar = ${active.app["sidebar"]}');
  print('   components.button = ${active.components["button"]}');

  // parseHex — 静态方法
  final parsed = ThemeDescriptor.parseHex('#FF5722');
  print('   parseHex("#FF5722") = ${parsed?.toHex(withAlpha: false)}');

  // 各层 token 数量
  print('   各层: app=${active.app.length} module=${active.module.length} page=${active.page.length} slot=${active.slot.length} components=${active.components.length}');

  // ═══════ ThemeColor ═══════
  print('\n═══ ThemeColor ═══');
  final tc = ThemeColor.fromHex('#1677FF');
  print('   fromHex("#1677FF") → toHex() = ${tc.toHex()}, toHex(withAlpha: false) = ${tc.toHex(withAlpha: false)}');
  print('   tryParse("red") = ${ThemeColor.tryParse("red") ?? "null"}');

  // ═══════ render_rules ═══════
  print('\n═══ 设计常量 ═══');
  print('   间距: xs=${Spacing.xs} sm=${Spacing.sm} md=${Spacing.md} lg=${Spacing.lg} xl=${Spacing.xl}');
  print('   圆角: sm=${Radii.sm} md=${Radii.md} lg=${Radii.lg} full=${Radii.full}');
  print('   字号: caption=${FontSize.caption} body=${FontSize.body} title=${FontSize.title} heading=${FontSize.heading}');
  print('   时长: fast=${Durations.fast}ms normal=${Durations.normal}ms slow=${Durations.slow}ms');
  print('   组件: sidebar=${ComponentSize.sidebarWidth} header=${ComponentSize.headerHeight} button=${ComponentSize.buttonHeight}');

  // ═══════ ThemeHttpServer ═══════
  print('\n═══ ThemeHttpServer ═══');
  final server = ThemeHttpServer(store);
  server.start().then((port) {
    print('   服务器已启动 → http://127.0.0.1:$port');
    print('   端点:');
    print('     GET  /theme/health');
    print('     GET  /theme/themes');
    print('     GET  /theme/themes/:id');
    print('     GET  /theme/active');
    print('     POST /theme/active');
    print('     GET  /theme/token?layer=&component=&token=');
    print('   按 Enter 停止服务器...');

    // 非阻塞等待后停止
    Future.delayed(Duration(milliseconds: 500), () {
      server.stop();
      print('   服务器已停止。');
    });
  });

  // ═══════ toJson ═══════
  print('\n═══ toJson (light 主题前 200 字符) ═══');
  final light = store.findById('light')!;
  final jsonStr = light.toJson().toString();
  print(jsonStr.substring(0, jsonStr.length > 200 ? 200 : jsonStr.length));

  // ═══════ 空查找 ═══════
  print('\n═══ 空查找 ═══');
  print('   findById("nonexistent") = ${store.findById("nonexistent") ?? "null"}');
  final t = store.findById('light');
  if (t != null) {
    print('   tokenValue(app, "sidebar", "nonexistent") = ${t.tokenValue(t.app, 'sidebar', 'nonexistent') ?? "null"}');
    print('   tokenValue(components, "nonexistent", "bg") = ${t.tokenValue(t.components, 'nonexistent', 'bg') ?? "null"}');
  }
  print('   setActiveById("ghost") = ${store.setActiveById("ghost")}');

  print('\n═══ 全部 20+ API 覆盖完毕 ═══');
}
