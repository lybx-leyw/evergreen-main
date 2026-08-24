# Config

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-25 |
| 负责人 | core-config |
| 适用 | config 子包 |

> 完整用法 → [`example/example.dart`](example/example.dart) | AI 协作指南 → [`CLAUDE.md`](CLAUDE.md)
>
> **HTML-first 事实**：用户 HTML 插件用 `platform.settings.get/set` 读写设置，无需手写 config.json；
> 平台级/开发者模式插件仍可用 `config/config.json` 声明设置与权限。

---

## 一、平台开发者 API

### 设置

| 函数 | 说明 |
|------|------|
| `initSettings(prefs, {pluginDirs})` | 扫描插件目录 `config.json`，默认值写入 SP |
| `getSetting(prefs, key)` | 读值，回退声明默认值 |
| `setSetting(prefs, key, value)` | 写值 + 类型校验 |
| `getAllSettings(prefs)` | 返回 `List<({SettingDecl decl, String value})>` |
| `exportConfig(prefs, {aiMemory, extraKeys})` | 导出 `.evgconfig`（含 AI 记忆） |
| `importConfig(prefs, config)` → `Map?` | 导入 `.evgconfig`，返回 aiMemory |

### 权限

| 函数 | 说明 |
|------|------|
| `registerPermissions(pluginId, perms)` | 注册权限声明 |
| `getPermissions(prefs, pluginId)` | 返回 `Map<String, bool>` |
| `setPermission(prefs, pluginId, permKey, granted)` | 设置单个权限，即时生效 |
| `checkPermission(prefs, pluginId, permKey)` | 检查权限，拒绝时抛 `PermissionDeniedException` |
| `describePermission(perm)` | 生成 `【标签】描述` 格式文本 |
| `getPermissionDecls(pluginId)` | 返回 `List<PermissionDecl>?` |

### 源管理

| 函数 | 说明 |
|------|------|
| `getSources(prefs)` | 返回 `List<PluginSource>`（默认源 + 自定义源） |
| `addSource(prefs, url, name)` | 添加自定义源，重复 URL 抛 `SourceDuplicateException` |
| `removeSource(prefs, url)` | 删除自定义源（默认源不可删） |

### ConfigHttpServer 附加能力

| 成员 | 说明 |
|------|------|
| `registerSetting(key, label)` / `unregisterSetting(key)` | 动态注册/注销设置项（无需 config.json 声明，HTTP 可读写） |
| `setGreenixConfigPath(path)` | 设置 `.greenix/config.json` 写入路径并触发首次全量同步 |
| `syncConfigToGreenix()` | 全部配置（静态 + 动态）覆写为扁平 JSON；非空值保护，Android 首启不覆写凭证 |

### 运行期热注册（设计器/爬虫）

| 函数 | 说明 |
|------|------|
| `registerConfigFromManifest({configServer, pluginDir})` | 读取插件 `config/config.json` → `registerSetting` 热注册；返回 `ConfigRegisterSummary(registered, savedDefaults)`，默认值由调用方写入 SP |

### HTTP 端点（ConfigHttpServer）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/config/health` | 健康检查 |
| GET | `/config/settings` | 列出全部设置项 |
| POST | `/config/settings` | 按 body `{"key","value"}` 写设置（动态注册） |
| GET | `/config/settings/:key` | 读单个设置 |
| POST | `/config/settings/:key` | 写设置 `{"value":"..."}` |
| GET | `/config/permissions/:id` | 读插件权限 |
| POST | `/config/permissions/:id` | 设权限 `{"key":"...","granted":true}` |
| GET | `/config/sources` | 列出插件源 |
| POST | `/config/sources` | 增删源 `{"action":"add"\|"remove","url":"...","name":"..."}` |

> 注：`POST /config/settings` 与 `POST /config/settings/:key` 写入未在 config.json 声明的 key 时，会自动动态注册（类型固定 string，响应 `registered: true`）。所有响应带 CORS 头 `Access-Control-Allow-Origin: *`。

### 类型

| 类型 | 字段 |
|------|------|
| `SettingDecl` | `key`, `label`, `type`, `defaultValue`, `isSecure`, `options`, `hint`, `suggestions` |
| `SettingType` | `string` / `bool_` / `path` / `option` |
| `SettingOption` | `value`, `label` |
| `PermissionDecl` | `key`, `label`, `description`, `defaultGranted` |
| `PluginSource` | `url`, `name`, `isDefault` |

### 异常

| 异常 | 触发场景 |
|------|---------|
| `ConfigMissingException` | 请求了未声明的配置项 |
| `ConfigValidationException` | bool_ 非 "true"/"false"、option 值不在列表中、删除默认源 |
| `PermissionDeniedException` | `checkPermission()` 时权限被拒绝 |
| `SourceDuplicateException` | 重复添加同名源 URL |

---

## 二、插件开发者

在插件目录放置 `config/config.json`（推荐）或 `config.json`。`initSettings()` 自动扫描并集成，无需代码注册。

### 字段速查

**顶层：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 插件唯一标识 |
| `name` | 是 | UI 分组标题 |
| `settings` | 否 | 设置项数组 |
| `permissions` | 否 | 权限声明数组 |

**settings 条目：**

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `key` | 是 | 全部 | 存储键，全局唯一 |
| `label` | 是 | 全部 | UI 标签 |
| `type` | 否 | 全部 | `string`(默认) / `bool` / `path` / `option` |
| `default` | 否 | 全部 | 默认值字符串 |
| `isSecure` | 否 | string | 敏感标记，仅 string 有效 |
| `hint` | 否 | string/path/option | 帮助文本 |
| `options` | 是* | option | `[{"value":"...","label":"..."}]` |
| `suggestions` | 否 | string/path | 快捷填充建议（仅 UI 提示，**不参与写入校验**，可自由填写任意值）；元素支持 `{"value","label"}` 或纯字符串两种写法 |

**permissions 条目：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `key` | 是 | 权限标识，建议 `UPPER_SNAKE_CASE` |
| `label` | 是 | UI 标签 |
| `description` | 是 | 用途与风险说明 |
| `default` | 否 | 默认授权状态，默认 `true` |

> 完整指南 → [`docs/plugin-authoring-guide-config.md`](docs/plugin-authoring-guide-config.md)

---

## 三、质量自评

| 维度 | 状态 |
|------|------|
| 设置注册/读写/持久化 + 默认值回退 + 类型校验 | ✅ |
| 权限注册/读写/即时生效/拒绝不阻塞安装 | ✅ |
| 源管理（默认源 + 自定义源增删） | ✅ |
| ConfigHttpServer 端点（含动态注册，见上表） | ✅ |
| 配置导出/导入（含 AI 记忆） | ✅ |
| 权限自动提取（config.json `permissions` 字段） | ✅ |
| `.greenix/config.json` 同步（非空值保护） | ✅ |
| 运行期热注册（registerConfigFromManifest） | ✅ |
| 测试：`dart test` 全量通过（见 `test/`） | ✅ |
| 静态分析：`dart analyze` 零错误零警告 | ✅ |
| 示例：`dart run example/example.dart` 正常运行 | ✅ |

## 四、已知限制

- SharedPreferences stub 不支持 `getKeys()`，导出依赖 `_decls` 列表；实际运行时完整 SP 支持。
- ConfigHttpServer 端口由外部写入 `.config_port` 文件发现。
- `_decls` 模块级可变状态，重复调用 `initSettings()` 会清空重建。**只在 main() 调用一次**。
- 所有值以字符串存于 SP，bool 为 `"true"/"false"` 字符串。
