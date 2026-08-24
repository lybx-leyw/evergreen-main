# Settings 插件

独立 HTTP 设置插件——从 ConfigHttpServer 动态拉取所有设置声明，渲染完整 HTML 设置页面。

## 端点一览

访问 `http://127.0.0.1:{PORT}/` 即可看到所有设置项并直接编辑保存。

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/` `/settings` | **HTML 页面**：动态拉取所有设置声明并渲染表单 |
| `GET` | `/api/settings` | JSON：所有设置项列表 |
| `GET` | `/api/settings/:key` | JSON：读取单个设置 |
| `POST` | `/api/settings/:key` | JSON：保存设置 `{"value": "..."}` |
| `GET` | `/api/export` | JSON：导出全部设置 |
| `POST` | `/api/import` | JSON：导入设置 |
| `GET` | `/health` | 健康检查 |

## HTML 页面功能

- 根据 `config.json` 中的 `type` 动态渲染对应控件：
  - `bool` → 开关滑块
  - `option` → 下拉选择框
  - `string` / `path` → 文本输入框（安全字段用密码类型）
- `string` 类型声明 `suggestions` 时，文本输入框下方渲染快捷填充建议（仅提示，不限制输入）
- 在线编辑即时保存（Toast 提示）
- JSON 导出 / 导入
- 刷新按钮

## 依赖

- **ConfigHttpServer**：通过 `.config_port` 文件发现端口，拉取设置声明和当前值
- 无外部 Python 依赖（标准库 only）

## 编译

```bash
pyinstaller --onefile --windowed settings.py
```

## 设置声明

所有设置项在 `plugins/settings/config/config.json` 中声明，格式：

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
