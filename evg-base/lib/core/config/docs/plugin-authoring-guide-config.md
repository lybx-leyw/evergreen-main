# plugin-authoring-guide-config.md — Config 配置插件撰写指南

> 面向插件开发者：如何为插件声明设置项和权限，如何通过 ConfigHttpServer 读写配置。

---

## 一、配置插件目录结构规范

每个插件通过 `config.json` 声明设置项和权限。平台启动时自动扫描，无需代码注册。

### 目录布局

```
plugins/<name>/
├── config/
│   └── config.json          # 推荐（符合插件规范）
├── agent/
│   └── manifest.json        # Agent 能力声明
└── ...
```

**兼容**：也可直接放在插件根目录 `config.json`。

**加载顺序**：先查 `config.json`（根目录），不存在则查 `config/config.json`。两个都存在时只加载根目录的。

---

## 二、config.json 完整字段说明

### 顶层字段

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `id` | **是** | string | 插件唯一标识，建议使用目录名，如 `"my_plugin"` |
| `name` | **是** | string | UI 分组标题，用于设置界面分组展示，如 `"我的插件"` |
| `settings` | 否 | array | 设置项数组，每个元素为一个设置项声明 |
| `permissions` | 否 | array | 权限声明数组，每个元素为一个权限声明 |

### settings 条目字段

| 字段 | 必填 | 适用类型 | 类型 | 说明 |
|------|------|----------|------|------|
| `key` | **是** | 全部 | string | 存储键，**全局唯一**（建议加插件前缀，如 `MY_PLUGIN_API_KEY`） |
| `label` | **是** | 全部 | string | UI 标签，如 `"API 密钥"` |
| `type` | 否 | 全部 | string | `string`（默认）/ `bool` / `path` / `option` |
| `default` | 否 | 全部 | string | 默认值（统一用字符串），bool 默认为 `"false"` |
| `isSecure` | 否 | string | bool | 敏感字段标记，UI 以密码框展示，日志脱敏，默认 `false` |
| `hint` | 否 | string / path / option | string | 帮助文本，显示在输入框下方 |
| `options` | **是** | option | array | 下拉选项列表 `[{ "value": "存储值", "label": "显示文本" }]` |

### permissions 条目字段

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `key` | **是** | string | 权限唯一标识，如 `"NETWORK"`、`"FILE_READ"`，建议大写蛇形命名 |
| `label` | **是** | string | 短标签，如 `"网络访问"`，用于授权弹窗标题 |
| `description` | **是** | string | 自然语言描述，说明用途与风险，展示在授权弹窗中 |
| `default` | 否 | bool | 默认授权状态，默认 `true`（首次安装时默认授权） |

---

## 三、设置项类型

Config 模块支持 **4 种**设置类型。所有值以字符串形式存储在 SharedPreferences 中。

| 类型 | 用途 | 特有字段 | 写入校验 |
|------|------|---------|---------|
| `string` | API 密钥、URL、用户名 | `isSecure`（敏感标记） | 无 |
| `bool` | 功能开关 | — | 拒绝非 `"true"/"false"` 的值 |
| `path` | 文件/目录路径 | — | 无 |
| `option` | 下拉单选 | `options`（**必填**） | 拒绝不在选项列表中的值 |

**共性**：
- `type` 缺失或无法识别时默认按 `string` 处理
- `default` 不填时回退空字符串 `""`
- `isSecure: true` 仅在 `string` 类型生效，UI 以密码框展示、日志脱敏
- `default` 值必须为字符串（`"true"`/`"false"`，非 JSON bool）

---

## 四、权限声明

### 存储格式

权限以 `perm.<pluginId>.<permKey>` 格式存储在 SharedPreferences 中（bool 类型）。

### 命名约定

- 使用 `UPPER_SNAKE_CASE`：`NETWORK`、`FILE_READ`、`CAMERA`
- 简洁明确，全局作用域（所有插件共享 `perm.` 前缀）

### 描述文本规范

`description` 展示在授权弹窗中，建议包含**用途说明 + 风险提示**：

> ✅ "允许插件访问互联网以获取实时天气数据。每次刷新时使用。"
>
> ❌ "网络权限"

---

## 五、完整示例

### config.json（覆盖 4 种类型 + 权限）

```json
{
  "id": "my_plugin",
  "name": "我的插件",
  "settings": [
    { "key": "MY_API_KEY",  "label": "API 密钥",  "type": "string", "isSecure": true, "hint": "从开发者后台获取" },
    { "key": "MY_FEATURE",  "label": "高级功能",  "type": "bool",   "default": "false" },
    { "key": "MY_DATA_DIR", "label": "数据目录",  "type": "path",   "hint": "选择数据存储文件夹" },
    {
      "key": "MY_MODE", "label": "运行模式", "type": "option", "default": "normal",
      "options": [
        { "value": "fast", "label": "快速" },
        { "value": "normal", "label": "标准" },
        { "value": "full", "label": "完整" }
      ],
      "hint": "快速模式跳过校验"
    }
  ],
  "permissions": [
    { "key": "NETWORK",  "label": "网络访问", "description": "访问互联网获取实时数据", "default": true },
    { "key": "FILE_READ", "label": "读取文件", "description": "读取用户文档目录下的文件", "default": false }
  ]
}
```

### 目录结构

```
plugins/my_plugin/
├── config/
│   └── config.json
├── agent/
│   └── manifest.json
└── my_plugin.exe
```

---

## 六、通过 HTTP API 读写配置

插件 `.exe` 通过 `ConfigHttpServer` 读写配置，不直接访问 SharedPreferences。

**端口发现**：读取 `.config_port` 文件 → `http://127.0.0.1:PORT/config/...`

```bash
# 读设置
curl http://127.0.0.1:PORT/config/settings/MY_API_KEY
# → {"key":"MY_API_KEY","value":"sk-abc123"}

# 写设置
curl -X POST http://127.0.0.1:PORT/config/settings/MY_API_KEY \
  -H "Content-Type: application/json" -d '{"value":"sk-abc123"}'

# 读权限
curl http://127.0.0.1:PORT/config/permissions/my_plugin
# → {"pluginId":"my_plugin","permissions":[{"key":"NETWORK","granted":true,"label":"网络访问"}]}

# 设权限
curl -X POST http://127.0.0.1:PORT/config/permissions/my_plugin \
  -H "Content-Type: application/json" -d '{"key":"CAMERA","granted":false}'

# 健康检查
curl http://127.0.0.1:PORT/config/health
# → {"status":"ok","settingsCount":14}
```

---

## 七、测试与调试

**验证加载**：

将 `config.json` 放入 `plugins/<name>/config/` 目录，启动平台后配置自动加载。可通过 HTTP API 验证：

```bash
# 检查所有设置项
curl http://127.0.0.1:PORT/config/health
# → {"status":"ok","settingsCount":14}
```

**常见问题**：

| 问题 | 原因 | 解决 |
|------|------|------|
| 设置项未出现 | key 冲突 | 加插件前缀，如 `MYPLUGIN_API_KEY` |
| config.json 未加载 | 路径不对 | 确认位于 `config/config.json` 或 `config.json` |
| bool 写入失败 | 值不是 `"true"/"false"` | 使用字符串，非 JSON bool |
| option 写入失败 | 值不在 options 列表 | 检查 value 完全匹配 |
| 权限检查无效 | 未注册声明 | 确认 `permissions` 字段格式正确 |
| 设置值丢失 | `initSettings` 多次调用 | 只在 `main()` 调用一次 |

---

## 八、参考

- 本文档 §二：完整字段说明
- 本文档 §三：4 种设置项类型详解
- 本文档 §五：完整 JSON 示例
- 本文档 §六：HTTP API 读写配置
