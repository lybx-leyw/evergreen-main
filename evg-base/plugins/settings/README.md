# Settings 插件

设置插件：`module/`（v4 Dart 设置页）+ `config/`（设置项声明）。

## 结构

```
plugins/settings/
├── module/manifest.json    ← v4 Dart 设置模块（SettingsView 渲染设置页）
└── config/config.json      ← 设置项声明（key/label/type/isSecure/hint…）
```

- 设置页 UI 由 Flutter 端（Dart `SettingsView`）渲染，数据由 `ConfigHttpServer`
  提供（端口经 `.config_port` 发现）。
- 所有设置项在 `config/config.json` 中声明，格式：

```json
{
  "key": "DEEPSEEK_API_KEY",
  "label": "DeepSeek API Key",
  "type": "string",
  "isSecure": true,
  "hint": "从 platform.deepseek.com 获取"
}
```

支持的 `type`：`string`、`bool`、`option`、`path`。

`string` / `path` 可附带 `suggestions`（快捷填充建议列表，元素为 `{"value","label"}` 或纯字符串），
仅作 UI 提示，不限制用户填写任意值——例如模型 id 支持自由填写以兼容任意 OpenAI 端点。

## 变更记录

- **2026-08-25（t-A4）**：清理遗留 `.exe` 形态——删除 `module/settings.py`（旧「独立 HTTP
  设置服务」API 代理，无任何代码消费方：module manifest 无 `process` 声明、renderer/core
  均不引用）及本地产物 `settings.spec` / `settings.exe`、渲染日志/截图。统一 Python 路径后
  不再保留桌面专属二进制；设置功能由 v4 Dart 设置页全权承担，无功能损失。
