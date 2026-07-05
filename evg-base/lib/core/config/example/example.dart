/// Config 模块 API 示例——覆盖全部 4 个函数。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

Future<void> main() async {
  final prefs = await SharedPreferences.getInstance();

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 1：initSettings —— 启动时调用一次
  // 扫描插件目录中的 config.json，将默认值写入 SharedPreferences。
  // 已存在的 key 不覆盖，保证用户修改过的值不丢失。
  // ═══════════════════════════════════════════════════════════════════════

  await initSettings(prefs, pluginDirs: [
    'builtins/',        // 内置设置
    'example/plugins/', // 示例插件
  ]);

  print('=== 1. initSettings 完成 ===');

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 2：getSetting —— 读值，回退声明默认值
  // 优先返回用户写入的值，未写入时回退 config.json 中的 default 字段。
  // ═══════════════════════════════════════════════════════════════════════

  print('\n--- 2a. 读默认值（用户未写入，回退 default） ---');
  print('DEEPSEEK_MODEL    = ${getSetting(prefs, 'DEEPSEEK_MODEL')}');
  print('DEEPSEEK_THINKING = ${getSetting(prefs, 'DEEPSEEK_THINKING')}');
  print('MY_FEATURE        = ${getSetting(prefs, 'MY_FEATURE')}');
  print('MY_MODE           = ${getSetting(prefs, 'MY_MODE')}');

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 3：setSetting —— 写值到 SharedPreferences
  // ═══════════════════════════════════════════════════════════════════════

  print('\n--- 2b. 写入 ---');
  await setSetting(prefs, 'DEEPSEEK_MODEL', 'deepseek-v4-pro');
  await setSetting(prefs, 'MY_API_KEY', 'sk-abc123');

  print('DEEPSEEK_MODEL = ${getSetting(prefs, 'DEEPSEEK_MODEL')}');
  print('MY_API_KEY     = ${getSetting(prefs, 'MY_API_KEY')}');

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 4：getAllSettings —— 全部声明 + 当前值，供设置界面渲染
  // 返回 (SettingDecl, String) 列表，设置界面遍历即可渲染表单。
  // ═══════════════════════════════════════════════════════════════════════

  print('\n--- 3. getAllSettings —— 供设置界面渲染 ---');
  for (final s in getAllSettings(prefs)) {
    print('${s.decl.key.padRight(24)} | ${s.decl.type.name.padRight(7)} | ${s.value}');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 5：权限管理 —— 注册、读写、检查
  // ═══════════════════════════════════════════════════════════════════════

  print('\n=== 5. 权限管理 ===');

  // 5a. 注册权限声明
  registerPermissions('my_plugin', [
    const PermissionDecl(key: 'NETWORK', label: '网络访问', description: '允许插件访问互联网获取实时数据'),
    const PermissionDecl(key: 'FILE_READ', label: '读取文件', description: '允许插件读取用户文档目录'),
    const PermissionDecl(key: 'CAMERA', label: '摄像头', description: '允许插件调用摄像头拍照'),
  ]);
  print('已注册 my_plugin 的 3 项权限');

  // 5b. 查看全部权限（首次安装，全部默认 true）
  final perms = getPermissions(prefs, 'my_plugin');
  print('当前权限状态: $perms');

  // 5c. 用户拒绝 "摄像头" 权限
  await setPermission(prefs, 'my_plugin', 'CAMERA', false);
  print('用户拒绝 CAMERA 权限');

  // 5d. 即时生效验证
  print('CAMERA 即时状态: ${getPermissions(prefs, 'my_plugin')['CAMERA']}');

  // 5e. 插件调用时检查权限
  try {
    checkPermission(prefs, 'my_plugin', 'CAMERA');
    print('CAMERA 权限已授权——可以拍照');
  } on PermissionDeniedException catch (e) {
    print('CAMERA 权限被拒绝: $e');
  }

  // NETWORK 未拒绝，应通过
  checkPermission(prefs, 'my_plugin', 'NETWORK');
  print('NETWORK 权限已授权——可以联网');

  // 5f. 生成授权弹窗描述
  print('\n--- 安装时授权弹窗文案 ---');
  final decls = getPermissionDecls('my_plugin') ?? [];
  for (final decl in decls) {
    print(describePermission(decl));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 6：插件源管理 —— 默认源 + 自定义源
  // ═══════════════════════════════════════════════════════════════════════

  print('\n=== 6. 插件源管理 ===');

  // 6a. 列出全部源（默认含官方源）
  var sources = getSources(prefs);
  print('当前源列表:');
  for (final s in sources) {
    print('  ${s.isDefault ? "[默认]" : "[自定义]"} ${s.name}: ${s.url}');
  }

  // 6b. 添加自定义源
  await addSource(prefs, 'https://plugins.example.com/index.json', '个人私有源');
  await addSource(prefs, 'https://company.internal/plugins.json', '公司内部源');
  print('已添加 2 个自定义源');

  // 6c. 查看更新后的列表
  sources = getSources(prefs);
  print('更新后源列表 (${sources.length}):');
  for (final s in sources) {
    print('  ${s.isDefault ? "[默认]" : "[自定义]"} ${s.name}: ${s.url}');
  }

  // 6d. 删除自定义源
  await removeSource(prefs, 'https://plugins.example.com/index.json');
  print('已删除 "个人私有源"');

  // 6e. 尝试删除默认源（会失败）
  try {
    await removeSource(prefs, defaultSourceUrl);
  } on ConfigValidationException catch (e) {
    print('删除默认源被阻止: $e');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 7：配置导出/导入 —— .evgconfig 格式
  // ═══════════════════════════════════════════════════════════════════════

  print('\n=== 7. 配置导出/导入 ===');

  // 7a. 导出（含 AI 记忆）
  final exported = await exportConfig(prefs, aiMemory: {
    'memories': [
      {'name': 'user-pref', 'body': '用户喜欢简洁回答'},
    ],
  });
  print('导出配置 (format: ${exported['format']}, version: ${exported['version']})');
  print('导出 settings 数: ${(exported['settings'] as Map).length}');
  print('导出含 AI 记忆: ${exported.containsKey('aiMemory')}');

  // 7b. 修改导出数据模拟迁移
  final modified = Map<String, dynamic>.from(exported);
  modified['settings']['DEEPSEEK_MODEL'] = 'deepseek-v4-pro-migrated';
  print('模拟迁移: 修改 DEEPSEEK_MODEL');

  // 7c. 导入——返回 aiMemory 供 Agent 模块处理
  final aiMemory = await importConfig(prefs, modified);
  print('导入后 DEEPSEEK_MODEL = ${getSetting(prefs, 'DEEPSEEK_MODEL')}');
  if (aiMemory != null) {
    print('AI 记忆待 Agent 导入: ${aiMemory['memories']}');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 规则 8：ConfigHttpServer —— 8 端点（启动后保持 2 秒供演示）
  // ═══════════════════════════════════════════════════════════════════════

  print('\n=== 8. ConfigHttpServer ===');

  final server = ConfigHttpServer(prefs);
  final port = await server.start();
  print('服务器启动: http://127.0.0.1:$port');
  print('  curl http://127.0.0.1:$port/config/health');
  print('  curl http://127.0.0.1:$port/config/settings');
  print('  curl http://127.0.0.1:$port/config/settings/DEEPSEEK_MODEL');
  print('  curl -X POST http://127.0.0.1:$port/config/settings/DEEPSEEK_MODEL -H "Content-Type: application/json" -d \'{"value":"v2"}\'');
  print('  curl http://127.0.0.1:$port/config/permissions/my_plugin');
  print('  curl -X POST http://127.0.0.1:$port/config/permissions/my_plugin -H "Content-Type: application/json" -d \'{"key":"CAMERA","granted":true}\'');
  print('  curl http://127.0.0.1:$port/config/sources');
  print('  curl -X POST http://127.0.0.1:$port/config/sources -H "Content-Type: application/json" -d \'{"action":"add","url":"https://new.source","name":"新源"}\'');

  // 保持 2 秒供手动验证
  await Future.delayed(const Duration(milliseconds: 500));
  await server.stop();
  print('服务器已关闭');
}
