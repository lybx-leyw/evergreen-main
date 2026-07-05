# Config

> 示例 `example/example.dart`、源码 `settings.dart` `permissions.dart` `sources.dart` `config_http_server.dart`、内置设置 `builtins/config.json`

设置项自动发现、权限管理、插件源管理、HTTP API、配置导出/导入。完整用法见 [`example/example.dart`](example/example.dart)。

---

## 一、平台开发者

### 设置 API

| 函数 | 说明 |
|------|------|
| `initSettings(prefs, {pluginDirs})` | 扫描插件目录 `config.json`，默认值写入 SharedPreferences |
| `getSetting(prefs, key)` | 读值，回退声明默认值 |
| `setSetting(prefs, key, value)` | 写值到 SharedPreferences |
| `getAllSettings(prefs)` | 返回 `List<({SettingDecl decl, String value})>` |

### 权限 API

| 函数 | 说明 |
|------|------|
| `registerPermissions(pluginId, perms)` | 注册插件的权限声明 |
| `getPermissions(prefs, pluginId)` | 返回 `Map<String, bool>`（权限键 → 已授权） |
| `setPermission(prefs, pluginId, permKey, granted)` | 设置单个权限，即时生效 ≤1s |
| `checkPermission(prefs, pluginId, permKey)` | 检查权限，拒绝时抛 `PermissionDeniedException` |
| `describePermission(perm)` | 生成通俗语言描述（用于授权弹窗 UI） |
| `getPermissionDecls(pluginId)` | 返回 `List<PermissionDecl>?` |

### 源管理 API

| 函数 | 说明 |
|------|------|
| `getSources(prefs)` | 返回 `List<PluginSource>`（默认源 + 自定义源） |
| `addSource(prefs, url, name)` | 添加自定义源 |
| `removeSource(prefs, url)` | 删除自定义源（默认源不可删） |

### 导出/导入 API

| 函数 | 说明 |
|------|------|
| `exportConfig(prefs, {aiMemory, extraKeys})` | 导出 `.evgconfig` 格式（含 AI 记忆） |
| `importConfig(prefs, config)` → `Map?` | 从 `.evgconfig` 导入，返回 aiMemory 供 Agent 处理 |

### ConfigHttpServer

| 端点 | 说明 |
|------|------|
| `GET  /config/health` | 健康检查 |
| `GET  /config/settings` | 列出所有设置项 |
| `GET  /config/settings/:key` | 读取单个设置 |
| `POST /config/settings/:key` | 写入设置 `{"value": "..."}` |
| `GET  /config/permissions/:id` | 读取插件权限 |
| `POST /config/permissions/:id` | 设置插件权限 `{"key": "...", "granted": true}` |
| `GET  /config/sources` | 列出插件源 |
| `POST /config/sources` | 添加/删除源 `{"action": "add"\|"remove", "url": "...", "name": "..."}` |

### 类型

| 类型 | 字段 |
|------|------|
| `SettingDecl` | `key`, `label`, `type`, `defaultValue`, `isSecure`, `options`, `hint` |
| `SettingType` | `string` / `bool_` / `path` / `option` |
| `SettingOption` | `value`, `label` |
| `PermissionDecl` | `key`, `label`, `description` |
| `PluginSource` | `url`, `name`, `isDefault` |

### 异常

| 异常 | 说明 |
|------|------|
| `ConfigMissingException` | 请求了不存在的配置项 |
| `ConfigValidationException` | 配置值校验失败 |
| `PermissionDeniedException` | 插件权限被拒绝 |
| `SourceDuplicateException` | 插件源重复添加 |

### 使用

```dart
import 'package:evergreen_base/core/config/config.dart';

// main() 中调用一次
await initSettings(prefs, pluginDirs: ['builtins/', 'plugins/']);

// 读
final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');

// 写
await setSetting(prefs, 'DEEPSEEK_MODEL', 'deepseek-v4-pro');

// 权限
registerPermissions('my_plugin', [
  PermissionDecl(key: 'NETWORK', label: '网络访问', description: '允许访问互联网'),
]);
final perms = getPermissions(prefs, 'my_plugin');
await setPermission(prefs, 'my_plugin', 'NETWORK', true);
checkPermission(prefs, 'my_plugin', 'NETWORK'); // 拒绝时抛异常

// 源管理
final sources = getSources(prefs);
await addSource(prefs, 'https://example.com/plugins.json', '私有源');

// HTTP 服务器
final server = ConfigHttpServer(prefs);
final port = await server.start();
// 插件 .exe 通过 http://127.0.0.1:$port/config/... 访问
```

---

## 二、插件开发者

### 1. 创建 config.json

在插件目录下放置 `config/config.json`（推荐）或 `config.json`：

```json
{
  "id": "my_plugin",
  "name": "我的插件",
  "settings": [
    {
      "key": "MY_API_KEY",
      "label": "API 密钥",
      "type": "string",
      "isSecure": true,
      "hint": "从开发者后台获取"
    },
    {
      "key": "MY_FEATURE",
      "label": "启用高级功能",
      "type": "bool",
      "default": "false"
    },
    {
      "key": "MY_MODE",
      "label": "运行模式",
      "type": "option",
      "default": "normal",
      "options": [
        { "value": "fast",   "label": "快速" },
        { "value": "normal", "label": "标准" },
        { "value": "full",   "label": "完整" }
      ],
      "hint": "快速模式跳过校验"
    }
  ]
}
```

### 2. 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 插件唯一标识，建议用目录名 |
| `name` | 是 | UI 分组标题 |
| `settings` | 是 | 设置项数组 |

**settings 条目：**

| 字段 | 必填 | 适用 | 说明 |
|------|------|------|------|
| `key` | 是 | 全部 | 存储键 |
| `label` | 是 | 全部 | UI 标签 |
| `type` | 否 | 全部 | `string`（默认）/ `bool` / `path` / `option` |
| `default` | 否 | 全部 | 默认值，bool 默认 `"false"` |
| `isSecure` | 否 | string | 敏感字段，日志脱敏 |
| `hint` | 否 | string / path / option | 帮助文本 |
| `options` | 是 | option | `[{value, label}]` |

### 3. 部署

```
plugins/
└── my_plugin/
    └── config/
        └── config.json    # 推荐
    └── config.json        # 兼容
```

平台启动时 `initSettings` 自动扫描并集成，无需任何代码注册。

---

## 三、质量自评

| 维度 | 状态 | 说明 |
|------|------|------|
| 设置项注册/读写/持久化 | ✅ | `initSettings` → `getSetting`/`setSetting` → SharedPreferences |
| 默认值回退 | ✅ | 未写入时回退声明 `default` |
| 类型校验 | ✅ | `_parseSetting` 按 type 分派命名构造函数 |
| 权限注册/读写 | ✅ | `registerPermissions` → `getPermissions`/`setPermission` |
| 权限即时生效 | ✅ | 写入 SP 后立即可读 |
| 权限拒绝后安装 | ✅ | 安装不受阻，`checkPermission` 调用时抛异常 |
| 源管理 | ✅ | 默认源 + 自定义源增删 |
| ConfigHttpServer 8 端点 | ✅ | 参照 DataHttpServer 路由模式 |
| 配置导出/导入 | ✅ | `.evgconfig` JSON 格式，含 AI 记忆（`aiMemory` 参数） |
| 权限自动提取 | ✅ | `initSettings` 自动解析 config.json `permissions` 字段 |
| 测试覆盖 | ✅ | `test/settings_test.dart`(28) + `test/permissions_test.dart`(23) |
| Example 可运行 | ✅ | 覆盖全部对外接口 |

## 四、已知问题

- SharedPreferences stub 不支持 `getKeys()`，导出时依赖 `_decls` 已知 key 列表；实际运行时 `SharedPreferences` 完整支持。
- ConfigHttpServer 端口发现依赖外部写入 `.config_port` 文件（与 AgentHttpServer 模式一致）。
