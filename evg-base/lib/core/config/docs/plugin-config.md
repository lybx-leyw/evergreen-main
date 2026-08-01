# plugin-config.md — config.json 开发规范

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | 插件 config.json 作者 |

> 面向插件开发者：如何为插件声明设置项、权限。

---

## 一、概述

每个插件可通过 `config.json` 声明设置项和权限。平台启动时自动扫描 `plugins/` 和 `builtins/` 目录，无需任何代码注册。

设置项通过 SharedPreferences 持久化，插件 .exe 可通过 `ConfigHttpServer`（HTTP API）读写，也可在平台设置界面中由用户手动配置。

---

## 二、目录结构

```
plugins/
└── my_plugin/
    └── config.json              # 插件根目录（兼容旧格式）

    或

plugins/
└── my_plugin/
    └── config/
        └── config.json          # 推荐格式（符合插件规范）
```

平台会先检查 `config/config.json`，找不到则回退到 `config.json`。

---

## 三、config.json 完整 Schema

```json
{
  "id": "my_plugin",
  "name": "我的插件",
  "settings": [
    {
      "key": "MY_API_KEY",
      "label": "API 密钥",
      "type": "string",
      "default": "",
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
    },
    {
      "key": "MY_DATA_DIR",
      "label": "数据目录",
      "type": "path"
    }
  ],

  "permissions": [
    {
      "key": "NETWORK",
      "label": "网络访问",
      "description": "允许插件访问互联网以获取实时数据",
      "default": true
    },
    {
      "key": "FILE_READ",
      "label": "读取文件",
      "description": "允许插件读取用户文档目录下的文件",
      "default": false
    }
  ]
}
```

---

## 四、字段说明

### 顶层字段

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `id` | 是 | string | 插件唯一标识，建议使用目录名 |
| `name` | 是 | string | UI 分组标题，用于设置界面分组 |
| `settings` | 否 | array | 设置项数组 |
| `permissions` | 否 | array | 权限声明数组 |

### settings 条目

| 字段 | 必填 | 适用类型 | 说明 |
|------|------|----------|------|
| `key` | 是 | 全部 | 存储键，全局唯一（建议加插件前缀） |
| `label` | 是 | 全部 | UI 标签 |
| `type` | 否 | 全部 | `string`（默认）/ `bool` / `path` / `option` |
| `default` | 否 | 全部 | 默认值，bool 默认 `"false"`（值为字符串） |
| `isSecure` | 否 | string | 敏感字段，UI 以密码框展示，日志脱敏 |
| `hint` | 否 | string / path / option | 帮助文本，显示在输入框下方 |
| `options` | 是 | option | 下拉选项 `[{value, label}]` |

### permissions 条目

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `key` | 是 | string | 权限唯一标识，如 `NETWORK`、`FILE_READ` |
| `label` | 是 | string | 短标签，如 "网络访问" |
| `description` | 是 | string | 自然语言描述，展示在授权弹窗中 |
| `default` | 否 | bool | 默认授权状态，默认 `true` |

---

## 五、类型详解

### string
普通文本。`isSecure: true` 时 UI 以密码框展示。

### bool
布尔开关。存储值为 `"true"` 或 `"false"`（字符串）。默认值也必须用字符串形式声明。

### path
文件/目录路径。UI 提供"浏览..."按钮（平台渲染层实现）。

### option
下拉单选。必须提供 `options` 数组，每个选项含 `value`（存储值）和 `label`（显示文本）。

---

## 六、通过 ConfigHttpServer 读写

插件 .exe 可通过 HTTP API 读写设置（无需直接访问 SharedPreferences）：

```bash
# 读单个设置
curl http://127.0.0.1:PORT/config/settings/MY_API_KEY

# 写设置
curl -X POST http://127.0.0.1:PORT/config/settings/MY_API_KEY \
  -H "Content-Type: application/json" \
  -d '{"value": "sk-abc123"}'

# 列出全部
curl http://127.0.0.1:PORT/config/settings
```

端口号从 `.config_port` 文件读取。

---

## 七、使用流程

1. 在插件目录下创建 `config/config.json`（推荐）或 `config.json`
2. 填写 `id`、`name`、`settings`、`permissions`
3. 部署到 `plugins/` 目录
4. 平台启动时自动加载——设置默认值写入 SharedPreferences
5. 插件 .exe 启动后通过 ConfigHttpServer 读写设置
6. 用户可在设置界面中查看和修改
