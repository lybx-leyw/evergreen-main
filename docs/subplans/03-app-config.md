# 03 — AppConfig 规范化（细化版）

**阶段：** 一 | **估时：** 3 天 | **依赖：** 无（可与错误处理体系并行） | **关联 Bug：** BUG-10

---

## 1. 现状问题

| 问题 | 典型代码 | 后果 |
|------|----------|------|
| 全局可变静态类 | `AppConfig.set(key, value)` | 无法测试注入、无法追踪谁在修改 |
| 全部 `String?` | `static String? _zjuPassword` | `bool` 值 (`deepseekThinking`) 也是字符串 `"enabled"` |
| 敏感字段无保护 | `print('[LoginDebug] password=***...')` 手动脱敏 | 全凭自觉，一处遗漏密码就明文泄露 |
| 主题不持久 | `StateProvider((ref) => ThemeVariant.system)` | 重启 App 主题重置为 system |
| `.env` 路径不稳定 | `Platform.resolvedExecutable` | debug 和 release 在不同目录，设置丢失 |
| 7 个消费者散落各处 | `AppConfig.zjuUsername` 散布于 auth/tutor/agent/wordpecker | 重构时牵一发动全身 |

---

## 2. 设计目标

1. **Riverpod 化**：`AppConfig` 从静态类 → `AppConfigNotifier` (StateNotifier)，通过 Provider 注入
2. **类型安全**：配置项区分 `String`/`int`/`bool`/`enum`，拒绝裸字符串
3. **敏感字段标记**：`@secure` 注解，`toString()` 和 `Log()` 自动脱敏为 `***`
4. **主题持久化**：`themeVariantProvider` 启动时从 `SharedPreferences` 恢复
5. **路径修复**：`.env` 文件路径使用 `getApplicationSupportDirectory()`

---

## 3. 核心类型设计

### 3.1 `AppConfig` — 配置状态类

```dart
// lib/core/config/app_config.dart

/// 标记敏感字段——toString() / Log() 自动脱敏。
class Secure {
  const Secure();
}

class AppConfig {
  // ── 认证 ──
  final String? zjuUsername;
  @Secure() final String? zjuPassword;

  // ── AI ──
  @Secure() final String? deepseekApiKey;
  final String deepseekModel;       // 默认 'deepseek-v4-flash'
  final bool deepseekThinking;       // true=enabled, false=disabled

  // ── 第三方 ──
  final String? pintiaCookie;
  final String? dingtalkWebhook;
  final String? cc98Username;
  @Secure() final String? cc98Password;

  // ── 路径 ──
  final String? downloadPath;
  final String? videoPlayerPath;

  const AppConfig({
    this.zjuUsername,
    this.zjuPassword,
    this.deepseekApiKey,
    this.deepseekModel = 'deepseek-v4-flash',
    this.deepseekThinking = true,
    this.pintiaCookie,
    this.dingtalkWebhook,
    this.cc98Username,
    this.cc98Password,
    this.downloadPath,
    this.videoPlayerPath,
  });

  // ── 派生属性 ──

  bool get hasZjuCredentials =>
      zjuUsername != null && zjuUsername!.isNotEmpty &&
      zjuPassword != null && zjuPassword!.isNotEmpty;

  bool get hasDeepSeekApiKey =>
      deepseekApiKey != null && deepseekApiKey!.isNotEmpty;

  // ── 安全 toString ──

  @override
  String toString() {
    return 'AppConfig('
        'zjuUsername: $zjuUsername, '
        'zjuPassword: ${_mask(zjuPassword)}, '
        'deepseekApiKey: ${_mask(deepseekApiKey)}, '
        'deepseekModel: $deepseekModel, '
        'deepseekThinking: $deepseekThinking, '
        'cc98Password: ${_mask(cc98Password)}, '
        'downloadPath: $downloadPath'
        ')';
  }

  static String _mask(String? value) {
    if (value == null || value.isEmpty) return '(null)';
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***';
  }
}
```

**设计决策：**
- `deepseekThinking` 从 `String?`（`"enabled"`/`"disabled"`）→ `bool`，消除字符串比较
- `@Secure()` 注解目前是文档标记，未来可接 lint 规则或 `Log()` 自动脱敏
- `toString()` 内置 `_mask()`，任何地方打印 `AppConfig` 都不会泄露密码

### 3.2 `AppConfigNotifier` — Riverpod StateNotifier

```dart
// lib/core/config/app_config_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

class AppConfigNotifier extends StateNotifier<AppConfig> {
  final SharedPreferences _prefs;

  AppConfigNotifier(this._prefs) : super(const AppConfig());

  /// 初始化：env → .env 文件 → SharedPreferences → 合并为 AppConfig。
  Future<void> initialize() async {
    final values = <String, String>{};

    // 1. 系统环境变量（最高优先级）
    _loadFromEnv(values);

    // 2. .env 文件（填补环境变量空白）
    await _loadFromEnvFile(values);

    // 3. SharedPreferences（最低优先级，填补空白）
    await _loadFromPrefs(values);

    state = AppConfig(
      zjuUsername: values['ZJU_USERNAME'],
      zjuPassword: values['ZJU_PASSWORD'],
      deepseekApiKey: values['DEEPSEEK_API_KEY'],
      deepseekModel: values['DEEPSEEK_MODEL'] ?? 'deepseek-v4-flash',
      deepseekThinking: values['DEEPSEEK_THINKING'] != 'disabled',
      pintiaCookie: values['PINTIA_COOKIE'],
      dingtalkWebhook: values['DINGTALK_WEBHOOK'],
      cc98Username: values['CC98_USERNAME'],
      cc98Password: values['CC98_PASSWORD'],
      downloadPath: values['MATERIAL_DOWNLOAD_PATH'],
      videoPlayerPath: values['VIDEO_OPENER'],
    );
  }

  /// 批量更新配置（从设置界面调用）。
  Future<void> saveAll(Map<String, String?> updates) async {
    final newState = _applyUpdates(state, updates);
    state = newState;

    // 持久化到 SharedPreferences + .env 文件
    await _persistToPrefs(updates);
    await _persistToEnvFile(newState);
  }

  /// 单项更新。
  void set(String key, String? value) {
    state = _applyUpdates(state, {key: value});
  }

  // ── Private helpers ────────────────────────────────────────────

  AppConfig _applyUpdates(AppConfig current, Map<String, String?> updates) {
    return AppConfig(
      zjuUsername: _pick(updates, 'ZJU_USERNAME', current.zjuUsername),
      zjuPassword: _pick(updates, 'ZJU_PASSWORD', current.zjuPassword),
      deepseekApiKey: _pick(updates, 'DEEPSEEK_API_KEY', current.deepseekApiKey),
      deepseekModel: _pick(updates, 'DEEPSEEK_MODEL', current.deepseekModel),
      deepseekThinking: updates.containsKey('DEEPSEEK_THINKING')
          ? updates['DEEPSEEK_THINKING'] != 'disabled'
          : current.deepseekThinking,
      pintiaCookie: _pick(updates, 'PINTIA_COOKIE', current.pintiaCookie),
      dingtalkWebhook: _pick(updates, 'DINGTALK_WEBHOOK', current.dingtalkWebhook),
      cc98Username: _pick(updates, 'CC98_USERNAME', current.cc98Username),
      cc98Password: _pick(updates, 'CC98_PASSWORD', current.cc98Password),
      downloadPath: _pick(updates, 'MATERIAL_DOWNLOAD_PATH', current.downloadPath),
      videoPlayerPath: _pick(updates, 'VIDEO_OPENER', current.videoPlayerPath),
    );
  }

  String? _pick(Map<String, String?> updates, String key, String? current) =>
      updates.containsKey(key) ? updates[key] : current;

  // ... (env / .env / prefs 加载逻辑从原 AppConfig 迁移)
  // ... (env 文件写入使用 getApplicationSupportDirectory())
}
```

### 3.3 Provider 声明

```dart
// lib/core/config/app_config_notifier.dart

final appConfigProvider =
    StateNotifierProvider<AppConfigNotifier, AppConfig>((ref) {
  // SharedPreferences 不能在 Provider 中异步获取——
  // 由 main() 预先创建并通过 override 注入
  throw UnimplementedError('Use ProviderScope override in main()');
});
```

```dart
// lib/main.dart

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final configNotifier = AppConfigNotifier(prefs);
  await configNotifier.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((ref) => configNotifier),
      ],
      child: const EvergreenApp(),
    ),
  );
}
```

---

## 4. 消费者迁移路径

| 当前写法 | 迁移后写法 |
|----------|-----------|
| `AppConfig.zjuUsername` | `ref.read(appConfigProvider).zjuUsername` |
| `AppConfig.hasDeepSeekApiKey` | `ref.read(appConfigProvider).hasDeepSeekApiKey` |
| `DeepSeekClient(dio)` 内部读 `AppConfig` | `DeepSeekClient(dio, apiKey: config.deepseekApiKey, model: config.deepseekModel)` |
| `AppConfig.set(key, value)` | `ref.read(appConfigProvider.notifier).set(key, value)` |
| `await AppConfig.initialize()` | `await configNotifier.initialize()`（在 main() 中） |

**受影响文件（7 个）：**

| 文件 | 当前引用 | 迁移方式 |
|------|---------|----------|
| `main.dart` | `AppConfig.initialize()` | Provider override 注入 |
| `auth_provider.dart` | `AppConfig.zjuUsername` / `zjuPassword` | `ref.read(appConfigProvider)` |
| `agent_provider.dart` | `AppConfig.deepseekApiKey` / `deepseekModel` | `ref.read(appConfigProvider)` |
| `notes_provider.dart` | `AppConfig.hasDeepSeekApiKey` | `ref.read(appConfigProvider)` |
| `deepseek_client.dart` | 构造函数内读 `AppConfig` | 参数注入，移除外层依赖 |
| `wordpecker_provider.dart` | `AppConfig.hasDeepSeekApiKey` | `ref.read(appConfigProvider)` |
| `settings_service.dart` | `AppConfig.set()` / `saveToEnvFile()` | 迁移到 `AppConfigNotifier` |
| `settings_screen.dart` | 间接（通过 settings_service） | 自动适配 |

---

## 5. BUG-10：主题不持久修复

### 现状

```dart
final themeVariantProvider = StateProvider<ThemeVariant>((ref) => ThemeVariant.system);
```

重启 App 后总是 `system`，因为 `StateProvider` 没有从 `SharedPreferences` 读取。

### 修复方案

```dart
// lib/core/config/theme.dart

extension ThemeVariantStorage on ThemeVariant {
  String toStorageKey() => name; // 'system', 'light', 'dark', 'evergreen', 'liyu'

  static ThemeVariant fromStorageKey(String key) {
    return ThemeVariant.values.firstWhere(
      (v) => v.name == key,
      orElse: () => ThemeVariant.system,
    );
  }
}
```

```dart
// lib/app.dart

final themeVariantProvider = StateNotifierProvider<ThemeVariantNotifier, ThemeVariant>((ref) {
  // 从 SharedPreferences 读取已保存的主题
  final prefs = ref.read(sharedPreferencesProvider); // 或通过其他方式获取
  final saved = prefs.getString('theme_variant') ?? 'system';
  return ThemeVariantNotifier(ThemeVariantStorage.fromStorageKey(saved), prefs);
});

class ThemeVariantNotifier extends StateNotifier<ThemeVariant> {
  final SharedPreferences _prefs;
  ThemeVariantNotifier(super.initialState, this._prefs);

  void set(ThemeVariant variant) {
    state = variant;
    _prefs.setString('theme_variant', variant.toStorageKey());
  }
}
```

**UI 层调用变更：**
```dart
// 旧
ref.read(themeVariantProvider.notifier).state = value;

// 新
ref.read(themeVariantProvider.notifier).set(value);
```

---

## 6. `.env` 文件路径修复

**现状：**
```dart
static String get _envFilePath {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  return p.join(exeDir, '.env');
}
```

**问题：** `Platform.resolvedExecutable` 在 debug 模式指向 `build/windows/x64/runner/Debug/`，release 模式指向安装目录。设置界面保存后，下次 debug 跑找不到文件。

**修复：**
```dart
static Future<String> get _envFilePath async {
  final appDir = await getApplicationSupportDirectory();
  return p.join(appDir.path, '.env');
}
```

`getApplicationSupportDirectory()` 返回稳定的路径：
- Windows: `%LOCALAPPDATA%/evergreen/`
- macOS: `~/Library/Application Support/evergreen/`

---

## 7. 测试策略

| 测试 | 内容 |
|------|------|
| `app_config_test.dart` | `_mask()` 脱敏正确：`"1234567890"` → `"123***"` |
| | `toString()` 不含明文密码 |
| | `deepseekThinking` → `bool` 转换：`"disabled"` → `false` |
| | `hasZjuCredentials` 在有/无凭据时正确 |
| `app_config_notifier_test.dart` | 三层优先级：env > .env > SharedPreferences（mock SharedPreferences） |
| | `saveAll()` 后 `SharedPreferences` 写入正确 |
| `theme_variant_test.dart` | `toStorageKey()` / `fromStorageKey()` 往返一致 |
| | 重启后主题不丢失（mock SharedPreferences） |

---

## 8. 执行计划

| 步骤 | 内容 | 产出物 | 估时 |
|------|------|--------|------|
| **Step 1** | 定义 `AppConfig` 不可变类 + `@Secure()` | `app_config.dart` 重写 | 0.5 天 |
| **Step 2** | 实现 `AppConfigNotifier` + `appConfigProvider` | `app_config_notifier.dart` 新建 | 0.5 天 |
| **Step 3** | `main()` 注入 Provider、`.env` 路径修复 | `main.dart` 修改 | 0.25 天 |
| **Step 4** | 迁移 7 个消费者文件 | 逐个修改 | 0.5 天 |
| **Step 5** | `themeVariantProvider` → `StateNotifier` + `toStorageKey/fromStorageKey` | `app.dart` + `theme.dart` 修改 | 0.25 天 |
| **Step 6** | `settings_service` 逻辑迁移到 `AppConfigNotifier` | 删除 settings_service.dart | 0.25 天 |
| **Step 7** | 测试编写 | `app_config_test.dart` + `theme_variant_test.dart` | 0.5 天 |
| **Step 8** | 全量回归：`flutter test` + `flutter run` | CI 绿 | 0.25 天 |

---

## 9. 验收标准

- [ ] `AppConfig` 为不可变类，所有字段通过构造函数注入
- [ ] `appConfigProvider` 通过 Riverpod 注入，消费者不再直接引用静态类
- [ ] `AppConfig.toString()` 不含明文密码和 API Key
- [ ] `deepseekThinking` 为 `bool` 类型
- [ ] `themeVariantProvider` 启动时从 `SharedPreferences` 恢复，切换后持久化
- [ ] `.env` 文件路径使用 `getApplicationSupportDirectory()`
- [ ] 旧 `AppConfig` 静态类标记 `@Deprecated` 后安全删除
- [ ] 7 个消费者全部迁移，`flutter analyze` 零警告
- [ ] 主题切换后重启 App，主题保持不丢失
- [ ] 测试 100% 通过

---

## 10. 风险

| 风险 | 缓解 |
|------|------|
| `SharedPreferences` 在 `main()` 中异步获取，Provider 初始化顺序复杂 | 使用 `ProviderScope.overrides` 注入预初始化的 notifier |
| `DeepSeekClient` 构造函数参数变更，影响 `tutor`/`wordpecker` Provider | 用 `ref.watch(appConfigProvider)` 读取后传参，不改构造函数签名 |
| 旧 `settings_service.dart` 删除后，设置界面可能引用断裂 | Step 6 前 grep 所有 `settings_service` 引用，逐修复 |
