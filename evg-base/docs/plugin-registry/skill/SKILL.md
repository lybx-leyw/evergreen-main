---
name: evergreen-plugin-author
description: >
  为 Evergreen Multi-Tools 平台（本地优先的 Flutter 桌面微工具平台）创作并上架第三方插件。
  当用户要求「写一个 Evergreen 插件」「给 Evergreen 市场开发插件」「让某个外部仓库被 Evergreen 市场收录」，
  或需要生成 plugin manifest.json / 适配壳（scraper.py / fetch.py / tool.py）/ registry 条目时使用。
  本 Skill 是 Evergreen 插件上架协议（docs/plugin-registry/plugin-registry-spec-v1.md）的可执行化身，
  指导 AI 从零产出五类插件（theme / module / data-source / agent / skin）的完整、可被市场自动发现的文件。
---

# Evergreen 插件创作 Skill

你是 **Evergreen 插件市场的第三方插件作者**。本 Skill 让你从零产出一个能被 Evergreen 市场
**自动发现、下载、加载**的插件。

读者（你）读完本 Skill 即可产出：registry 条目 + `install` 下载声明 + `manifest` + 适配壳（如需）。

---

## 前置：Evergreen 是什么、飞轮如何运转

- Evergreen = Flutter 桌面微工具平台（**无账号、无服务端、本地优先、AI 原生**）。
- 插件市场采用「飞轮」模式：

```
第三方作者向 registry 提 PR（新增/更新 plugins.json 条目）
        ↓
市场打开时读取 registry（plugins.json）→ 自动发现并展示条目
        ↓
用户点「安装」→ 按 install 声明下载 → 按 manifest 落盘 → 插件被系统加载
```

- **核心原则**：registry 条目是「协议声明」，不是「代码」。你只需声明
  「我的插件从哪下载、manifest 从哪来」，Evergreen 就能自动完成下载与加载。
- 权威规范文档：`docs/plugin-registry/plugin-registry-spec-v1.md`（上架协议，含 agent 型契约）；
  `lib/core/module/docs/plugin-module.md`（module manifest 全字段）；
  `lib/core/config/docs/plugin-authoring-guide-config.md`（config 设置项与权限声明）；
  `lib/core/agent/docs/plugin-agent-tool.md`（agent 工具 manifest 契约，.py 统一主路径）。

---

## 源码出处（遇到疑问直接查源码）

- **Evergreen 源码仓库**：`https://github.com/lybx-leyw/evergreen-main`
- 本 Skill 只是协议摘要，**字段的最终权威是源码**。创作插件时若对某个字段、某个 key、
  某段加载逻辑拿不准，直接去 GitHub 翻对应源码：

| 疑问点 | 翻源码位置 |
|--------|-----------|
| registry 条目解析 / `PluginManifest` / `installStrategy` | `lib/core/module/plugin_registry.dart` |
| module manifest 全字段（`ModuleDescriptor`） | `lib/core/module/` + `lib/core/module/docs/plugin-module.md` |
| data-source manifest 契约（含 `auth`/`stream`/`file` 可选段） | `lib/core/data/plugin/data_source_manifest.dart` |
| data-source 注册 / 适配壳加载 | `lib/core/data/`（`register_data_source.dart` + `plugin/data_source_loader.dart`） |
| agent 工具 manifest（`lifetime` 一次性/常驻、argMode/argSpec） | `lib/core/agent/docs/plugin-agent-tool.md` + `lib/core/agent/tools/plugin_bridge.dart` |
| skin 皮肤包 manifest（DIY 段） | `lib/core/skin/skin_descriptor.dart` + `lib/core/skin/skin_loader.dart` |
| 配置设置项 + 权限声明 | `lib/core/config/docs/plugin-authoring-guide-config.md` + `lib/core/config/builtins/config.json` |
| release 下载 / assetPattern 匹配 | `lib/core/services/release_downloader.dart` |
| GitHub 克隆 / star / manifest 下载 | `lib/core/services/github_clone.dart` / `github_metadata.dart` |
| Python 环境 / pip 装依赖 | `lib/core/utils/python_env.dart` |
| 进程执行（runOnce 一次性 / startLong 常驻） | `lib/core/plugin/plugin_runner.dart` |
| 四级进程作用域管理（module/page/slot/action） | `lib/core/module/process_manager.dart` |
| `ProcessDescriptor` 字段定义（scope/runtime/protocol） | `lib/core/module/module_descriptor.dart` |
| HTML bridge JS 生成 + Dart 转发 | `lib/renderer/templates/html_modle/bridge_script.dart` / `html_modle_view.dart` |
| 适配壳 `_get_config` 三级降级参考实现 | `docs/plugin-registry/examples/example-data-zju_grades/data/scraper.py` |

> **原则**：不确定字段、不确定 key、不确定行为时，先翻源码，别猜。源码即文档。

---

## 五种插件形态（先选型）

| 形态 | `type` | 落盘路径 | 适用 |
|------|--------|---------|------|
| **theme** | `theme` | `plugins/<id>/theme/theme.json` | 换肤主题 |
| **module** | `module` | `plugins/<id>/module/manifest.json` | UI 模块 / 导出工具 |
| **data-source** | `data-source` | `plugins/<id>/data/manifest.json` | 数据爬虫 / API 封装 |
| **agent** | 无 `type`（`name` 必填） | `plugins/<id>/agent/manifest.json` | AI 助手可调用工具（.py 统一主路径） |
| **skin** | `skin` | `plugins/<id>/skin/manifest.json` | AI 视图皮肤包（DIY 外观） |

> 完整参考实现见本 Skill 的 `examples/` 目录（五类各一份），可直接复制对应目录为模板起手。

---

## 工作流程

1. **确认形态**：问清（或根据需求判断）要 theme / module / data-source / agent / skin 中的哪一种。
2. **产出插件本体文件**（见下文各形态契约）。
3. **产出 registry 条目**（`plugins.json` 里 `plugins` 数组新增一项，声明 `install` + `manifest`）。
4. **自检**：按「上架清单」逐项核对。

---

## 一、theme 形态

最小主题声明：`type:"theme"` + `colors` 8 个语义色。

```json
{
  "type": "theme",
  "id": "warm_study",
  "name": "温暖学习",
  "colors": {
    "background": "#FAF3E7", "surface": "#FFF8ED", "border": "#E5D3B8",
    "text": "#3E2723", "textSecondary": "#6D4C41", "accent": "#E07A3F",
    "error": "#D32F2F", "others": "#F2B880"
  }
}
```

落盘：`plugins/<id>/theme/theme.json`。参考：`examples/example-theme-warm_study/`。

---

## 二、module 形态

最小 module manifest（`type`/`id`/`name` 必填）：

```json
{
  "type": "module",
  "id": "zju-ical",
  "name": "ZJU iCal 导出",
  "icon": "calendar_month",
  "route": "/zju-ical",
  "nav": { "sidebar": { "section": "校园", "order": 30 } },
  "process": [
    { "id": "export", "exe": "zjuical", "runtime": "native",
      "protocol": "stdio", "scope": "short", "autoStart": false }
  ]
}
```

- `schemaVersion`：声明式 schema 版本，缺省 `"2.0"`；**HTML 模块（`template:"html"`）必须
  显式声明 `"schemaVersion": "2.0"`**——应用启动时仅提取 `schemaVersion=="2.0"` 的 module
  manifest 进入 HTML 渲染路径（`app_bootstrap.dart`），缺失则页面不渲染。
- 落盘：`plugins/<id>/module/manifest.json`。
- **全字段参考**：`lib/core/module/docs/plugin-module.md`（含 `ui` 范式、`chat`/`spreadsheet`/
  `document`/`presentation` 专属配置、`layout`、`data`、`actions`、`input`、`media`、`process`、
  `activateSkills`、`pages[]`+`slots` composite 模式、`secondaryNavs` 子导航等）。
- **HTML 模块**（`template:"html"`）：`module/manifest.json` 声明
  `"schemaVersion":"2.0"` + `"template":"html"` + `module/index.html` 自包含网页。
  网页内用 `--evg-*` 主题变量换肤，`platform.*` bridge 读数据/调 AI/跑 exe。
  参考：`examples/example-html-view/`。

### 2.1 `process`：后端进程（支持 Python 常驻 / 一次性执行）

module 通过 `process` 数组声明后端进程。每个 `ProcessDescriptor` 的完整字段：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | `string` | — | 进程唯一标识（HTML 插件经 `platform.process.run(id)` 按 id 命中白名单） |
| `exe` | `string` | ✅ | 可执行文件（`.exe`）或 `.py` 入口（`runtime:"python"` 时） |
| `runtime` | `string` | `native` | `native`（直接执行 exe）/ `python`（用 Python 解释器跑 `.py`） |
| `protocol` | `string` | `http` | `http`（首行输出 `PORT:<N>` + `/health`）/ `stdio`（标准流） |
| `scope` | `string` | `long` | **`long`（常驻进程）/ `short`（一次性任务，跑完即退出）** |
| `autoStart` | `bool` | `true` | 是否随模块加载自动启动 |
| `autoRestart` | `bool` | `false` | 崩溃后自动重启（仅 `long` 作用域生效） |
| `preferredPort` | `int` | `0` | 首选端口（`http` 协议，0=自动分配） |

**两种进程形态（`scope` 字段决定）**：

1. **常驻进程**（`scope: "long"`）——作为模块的后端服务常驻运行：
   ```json
   { "id": "server", "exe": "server.py", "runtime": "python",
     "protocol": "http", "scope": "long", "autoStart": true, "autoRestart": true }
   ```
   - `http` 协议：进程启动后 stdout 第一行输出 `PORT:<N>`，并响应 `GET /health` → 200。
   - `stdio` 协议：标准流通信，无需端口，直接就绪。
   - 生命周期：模块加载启动 → 卸载停止（`autoRestart` 崩溃自动拉起）。

2. **一次性进程**（`scope: "short"`）——点某个按钮触发、执行完即退出：
   ```json
   { "id": "export", "exe": "export.py", "runtime": "python",
     "protocol": "stdio", "scope": "short", "autoStart": false }
   ```
   - HTML 插件用 `platform.process.run('export', {args:[...]})` 触发，返回 `{stdout, stderr, exitCode}`。

**Python 进程两种写法的差异**：
- `runtime:"python"` + `exe:"xxx.py"` → 平台用嵌入式 Python 执行 `python xxx.py`。
- `runtime:"native"` + `exe:"xxx"` → 直接执行编译好的二进制（如 Go 程序）。
- **推荐外部插件优先用 `.py` + `runtime:"python"`**（跨平台、无需编译、天然契合「全面替代 dart 路线」）。

### 2.2 外部插件的 Python 依赖约束（软性要求）

> ⚠️ **非硬性要求，但强烈建议遵守**，否则部署到用户机器时极易 `ModuleNotFoundError`。

- **尽量只用标准库**（`json`/`os`/`sys`/`urllib`/`http.server`/`re`/`subprocess` 等），零第三方依赖 → 装完即用，无需 pip。
- 若确实需要第三方包，**在 manifest 顶层声明 `requirements`**（见 §3.1），安装器会自动 `pip install`。
- **避免重量级依赖**：`selenium`（要浏览器驱动）、`torch`（几百 MB）、`playwright`（要下浏览器）这类在用户机器上大概率装失败，能不用就不用。
- **优先 `urllib`/`requests` 级别**的轻量依赖；网络爬取优先考虑对方站点的公开 HTTP 接口而非浏览器自动化。
- 依赖声明要**对齐上游 `install_requires` 且别漏隐式 import 的包**（如上游 `setup.cfg` 忘了声明但代码里 `import` 了某个包，你也要补进 `requirements`）。

### 2.3 HTML 能力补强方向（替代 Dart 路线的长期目标）

HTML 模块（`template:"html"`）是「全面替代 Dart 路线」的载体，bridge 能力持续扩展中：

**已具备**（`platform.*` JS bridge，见 `lib/renderer/templates/html_modle/bridge_script.dart`）：
- `platform.data.get/list/refresh/subscribe` —— 读数据中枢
- `platform.ai.chat` —— 调 AI
- `platform.api.call` —— 通用 core 服务转发（agent/config/data/module/theme/core）
- `platform.settings.get/set` —— 读写设置
- `platform.theme.getColors` + `--evg-*` 主题变量 —— 主题换肤
- `platform.emit/on` —— 页内事件总线
- `platform.process.run` —— 跑本插件 manifest 声明的进程（白名单，一次性）

**规划增强方向**（源码权威以 `html_modle_view.dart` / `bridge_script.dart` 为准）：
- **常驻终端**：HTML 页内嵌入可交互终端，连到 `scope:"long"` 的 Python 常驻进程（stdio 双向流 + 实时 stdout/stderr 回显），而非当前的一次性 `process.run`。
- **进程生命周期桥接**：`platform.process.start/stop/write` 对齐 `ProcessManager` 四级作用域（模块/页面/栏位/动作）。
- 更多 `platform.*` API 随需求暴露，逐步让「纯 HTML+Python 插件」覆盖原 Dart 渲染的能力面。

> 新增 bridge 能力时，务必同步 `bridge_script.dart`（生成 JS）+ `html_modle_view.dart`（Dart 侧 `_executePlatformApi`）两处，二者必须一致。

---

## 三、data-source 形态

### 3.1 manifest 契约

```json
{
  "type": "data-source",
  "id": "<id>",
  "name": "<显示名>",
  "script": "<适配壳文件名>",
  "runtime": "python",
  "androidSupport": false,
  "auth": {
    "sessionProvider": "zju",
    "credentialKeys": ["ZJU_USERNAME", "ZJU_PASSWORD"]
  },
  "requirements": ["aiohttp", "pytz", "selenium>=4.0"],
  "dataTypes": [
    {
      "name": "<DataType 唯一名，如 zju_gpa>",
      "typeArg": "<传给适配壳的 --type 值>",
      "category": "<分类>",
      "displayName": "<显示名>",
      "ttl": "30m",
      "persistentKey": "<持久化缓存 key>",
      "stream": { "enabled": true, "protocol": "hls", "mime": "application/vnd.apple.mpegurl", "credentialed": true },
      "file": { "enabled": true, "downloadEndpoint": "/file" },
      "fallbackJson": { "items": [] }
    }
  ]
}
```

落盘：`plugins/<id>/data/manifest.json`。参考：`examples/example-data-zju_grades/`（模型 A + 登录）、
`examples/example-data-video_stream/`（模型 A + `auth`/`stream` 声明）。

**可选段说明**（缺省零行为变化，详见 `lib/core/data/plugin/data_source_manifest.dart`）：
- `androidSupport`：**严格 bool**（仅真实 `true`/`false` 有效），缺省 `true`；字符串/数字等
  非 bool 值一律视为 `false`——Android 上该数据源被跳过（fail-closed）。依赖 C 扩展的插件
  （OCR/翻译/PDF/ML）应显式置 `false`，纯 Python 数据源用 `true`。
- `auth`：`{sessionProvider:"zju", credentialKeys:[...]}`——仅**引用** `config/config.json` 已声明的
  凭据 key（复用 `isSecure`），不在此重复声明凭据值（避免双真相源）。
- `dataTypes[].stream`：声明为「可播放视频流」。`protocol` 可选：`hls`（`.m3u8`，配
  `mime:"application/vnd.apple.mpegurl"`）/ `mp4` / `http-flv`（配 `mime:"video/x-flv"`）/ `sse` /
  `stdio-jsonl`；`credentialed:true` = 拉流需携带凭据头。
- `dataTypes[].file`：声明文件下载能力，`downloadEndpoint` 含 `{port}` 占位符（平台替换实际端口）。
- `dataTypes[].fallbackJson`：拉取失败且无旧缓存时由 orchestrator 返回的静态兜底 JSON。
- `dataTypes[].persistentKey`：持久化缓存键。
- `script` 与顶层 `process` 互斥二选一：模型 A = CLI 一次性脚本（`script`）；模型 B = HTTP 常驻进程
  （`process`，`dataTypes[].endpoint` 必填）。

**`requirements`（可选，Python 依赖声明）**：适配壳若依赖第三方 Python 包（如 `aiohttp`、
`selenium`），在 manifest 顶层声明 `requirements` 数组。安装器会在插件落盘后自动
`python -m pip install <packages>`（见 `lib/core/utils/python_env.dart` 的 `pipInstallPackages`），
补齐嵌入式 Python 缺失的依赖。**不声明 → 运行时 `ModuleNotFoundError`**。

### 3.2 适配壳 CLI 契约（适配壳 = 把「库」包装成 Evergreen 认识的 CLI）

```
适配壳 --type <typeArg> --project-root <root> --greenix-config <cfg>
```

- **stdout** 输出**纯 JSON**（结果对象）；exit code 0 = 成功，非 0 = 失败。
- 失败时 stdout 输出 `{"error": "<人类可读信息>"}` + exit code 非 0。
- 凭证走 `_get_config(key)` **三级降级**读取（`.greenix/config.json` → 环境变量 → 报错），**绝不硬编码**。
- 任何异常都收敛为错误 JSON，**不得让进程崩溃输出堆栈污染 stdout**。

### 3.3 `_get_config` 三级降级（凭证读取的唯一正确姿势）

适配壳读取任何凭证/配置，**必须**走 `_get_config(key)`，逐级降级：

1. **Tier 1（主）**：`.greenix/config.json` 本地文件（路径由环境变量 `GREENIX_CONFIG_PATH` 指定）。
2. **Tier 2（降级）**：HTTP 从 `ConfigHttpServer` 读（读 `.config_port` → `http://127.0.0.1:PORT/config/settings/<key>`）。
3. **Tier 3（兜底）**：系统环境变量 `os.environ[key]`。
4. 三级全空 → 抛 `RuntimeError`，给人类可读的「请先在设置面板配置 X」提示。

> 完整可复制实现见 `examples/example-data-zju_grades/data/scraper.py` 的 `_get_config` 函数。

### 3.4 内置可复用配置 key（优先复用，别重复造）

以下 key 是平台**已内置注册**的设置项（定义于 `lib/core/config/builtins/config.json`）。
适配壳或模块**优先复用**它们，避免新增重复设置项。

**AI / DeepSeek 相关**：

| key | 类型 | 说明 |
|-----|------|------|
| `DEEPSEEK_API_KEY` | string(secure) | DeepSeek API Key（AI 对话/翻译/生成通用） |
| `DEEPSEEK_MODEL` | string | DeepSeek 模型名，默认 `deepseek-v4-flash` |
| `DEEPSEEK_BASE_URL` | string | DeepSeek API 地址（自定义端点时），默认 `https://api.deepseek.com/v1` |
| `DEEPSEEK_THINKING` | bool | 深度思考开关 |
| `DEEPSEEK_REASONING_EFFORT` | option | 推理强度档位：`off`/`low`/`medium`/`high`/`max`（OpenAI o 系列映射顶层 `reasoning_effort`；DeepSeek 不发送该参数） |

**浙大统一认证（zju）**：

| key | 类型 | 说明 |
|-----|------|------|
| `ZJU_USERNAME` | string | 学号（浙大统一认证账号） |
| `ZJU_PASSWORD` | string(secure) | 统一认证密码 |

**爬虫通用凭证**：

| key | 类型 | 说明 |
|-----|------|------|
| `SCRAPER_USERNAME` | string | 爬虫目标站点用户名 |
| `SCRAPER_PASSWORD` | password(secure) | 爬虫目标站点密码 |

**其它内置项**：

| key | 类型 | 说明 |
|-----|------|------|
| `PTA_SESSION` | string(secure) | PTA 平台 Session |
| `DINGTALK_WEBHOOK` | string | 钉钉机器人 Webhook |
| `MATERIAL_DOWNLOAD_PATH` | path | 资料下载目录 |
| `VIDEO_OPENER` | path | 视频播放器路径 |
| `TRANSLATE_LANG_OUT` | string | 翻译目标语言，默认 `zh` |
| `TRANSLATE_LANG_IN` | string | 翻译源语言，默认 `en` |
| `PYTHON_EXE` | path | Python 解释器路径 |

> ⚠️ **注意**：AI 相关 key 在 `lib/core/module/builtins/agent/config/config.json` 声明
> （`DEEPSEEK_*` + `OUTPUT_STYLE` + `DEEP_THINKING` + `WEB_SEARCH_ENABLED`），其余内置项在
> `lib/core/config/builtins/config.json` 声明；`ZJU_USERNAME` / `ZJU_PASSWORD` 走的是**应用启动时兜底注入**
> （`app_bootstrap.dart`），确保两 key 一定存在。具体注册路径以源码为准。凡是要**新增** key，必须走下一节「config.json 声明」。

### 3.5 新增 key：config.json 声明机制

若内置 key 不满足需求，需要**新增设置项**，必须在插件的 `config/config.json`（或根目录 `config.json`）
里声明，否则平台不注册该 key，`_get_config` 三级降级会全失败。

**config.json 结构**（顶层 `schemaVersion: "2.0"` 为约定标记——本 Skill 的 `examples/`
config.json 均带此字段；解析器 `_tryLoad`（`settings.dart`）只消费 `settings`/`permissions`/
`id`，不读取 `schemaVersion`，缺失不影响注册；`id`/`name` 可选）：

```json
{
  "schemaVersion": "2.0",
  "id": "my_plugin",
  "name": "我的插件",
  "settings": [
    { "key": "MY_API_KEY",  "label": "API 密钥",  "type": "string", "isSecure": true, "hint": "从开发者后台获取" },
    { "key": "MY_FEATURE",  "label": "高级功能",  "type": "bool",   "default": "false" },
    { "key": "MY_DATA_DIR", "label": "数据目录",  "type": "path" },
    {
      "key": "MY_MODE", "label": "运行模式", "type": "option", "default": "normal",
      "options": [ { "value": "fast", "label": "快速" }, { "value": "normal", "label": "标准" } ]
    }
  ],
  "permissions": [
    { "key": "NETWORK",   "label": "网络访问", "description": "访问互联网获取实时数据", "default": true },
    { "key": "FILE_READ", "label": "读取文件", "description": "读取用户文档目录下的文件", "default": false }
  ]
}
```

**settings 条目字段**：

| 字段 | 必填 | 说明 |
|------|------|------|
| `key` | ✅ | 存储键，**全局唯一**（建议加插件前缀，如 `MYPLUGIN_API_KEY`） |
| `label` | ✅ | UI 标签 |
| `type` | — | `string`（默认）/ `bool` / `path` / `option` |
| `default` | — | 默认值（**统一字符串**，bool 写 `"true"`/`"false"` 非 JSON bool） |
| `isSecure` | — | 敏感字段，UI 密码框 + 日志脱敏（仅 `string` 生效） |
| `hint` | — | 输入框下方帮助文本 |
| `options` | option 时✅ | 下拉选项 `[{ "value": "存储值", "label": "显示文本" }]` |

**4 种设置类型**：`string`（密钥/URL）、`bool`（开关，拒绝非 `"true"/"false"`）、
`path`（路径）、`option`（下拉，拒绝列表外值）。

**permissions 权限声明**（可选，需授权才能用的能力）：

| 字段 | 必填 | 说明 |
|------|------|------|
| `key` | ✅ | 权限标识，`UPPER_SNAKE_CASE`（`NETWORK`/`FILE_READ`/`CAMERA`） |
| `label` | ✅ | 短标签 |
| `description` | ✅ | 用途 + 风险提示（展示在授权弹窗） |
| `default` | — | 默认授权状态，默认 `true` |

> 详情见 `lib/core/config/docs/plugin-authoring-guide-config.md`。
> 插件 `.exe` 读写配置通过 `ConfigHttpServer`（读 `.config_port` → `http://127.0.0.1:PORT/config/...`），
> 不要直接访问 SharedPreferences。

---

## 四、agent 形态（AI 助手可调用工具）

agent 型插件把「工具脚本」暴露给 AI 助手：放入 `plugins/<id>/agent/` 后由 `PluginBridge`
在启动及刷新时**自动扫描注册**为 Agent 工具（`PluginTool`），无需重启。AI 决定何时调用，
平台运行并把 stdout 返回给 AI。

### 4.1 目录结构（.py 统一主路径）

```
plugins/<id>/agent/
  manifest.json    # 工具元数据（必写）
  tool.py          # Python 脚本（统一主路径；.exe 仅存量 legacy，新插件不要产出）
  README.md        # 插件说明（可选）
```

- 入口：必须有至少一个入口文件，**`.py` 优先**（同名 `<目录名>.py` 最高优先）；
  仅当无任何 `.py` 且 manifest 未声明 `"runtime":"python"` 时才回退 `.exe` legacy。
- manifest 建议显式声明 `"runtime":"python"`（亦可由 `.py` 扩展名自动推断）。

### 4.2 manifest 契约（`PluginManifest`）

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `name` | string | ✅ | — | 蛇形命名，Agent 调用的工具标识符。空字符串 → 插件被跳过 |
| `description` | string | ✅ | — | 给 LLM 看的用途说明，决定 AI 何时调用 |
| `schema` | object | ✅ | — | JSON Schema 参数定义，`type:"object"` + `properties` + `required` |
| `readOnly` | bool | — | `false` | `true`=只读（可并行）；`false`=写操作（串行） |
| `argMode` | string | — | `"stdin"` | `"stdin"`：JSON 写入标准输入；`"args"`：命令行参数传递 |
| `argSpec` | object | — | `{"style":"json"}` | 仅 `argMode="args"` 时生效，控制命令行构造方式（flag/positional/json） |
| `runtime` | string | — | `"native"` | `"native"`=直接执行（legacy .exe）；`"python"`=用 Python 解释器执行（`.py`，推荐） |
| `lifetime` | string | — | `"once"` | `"once"`=一次性（AI 调用后进程即被回收，默认，向后兼容）；`"resident"`=常驻（持续运行并登记到后台进程注册表，直到 `kill_process` 结束）。缺省/未知值静默回退 `"once"` |

最小示例（stdin 模式）：

```json
{
  "name": "date",
  "description": "返回当前日期。",
  "schema": {
    "type": "object",
    "properties": {
      "format": { "type": "string", "description": "日期格式：cn=中文, iso=ISO8601" }
    }
  },
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once"
}
```

调用方式：Agent 启动 `date.py`（`runtime:"python"`），将 `{"format":"cn"}` 写入 stdin，读取 stdout。

### 4.3 `lifetime`：一次性 vs 常驻

| 值 | 语义 | 行为 |
|----|------|------|
| `"once"`（**默认**） | 一次性 | AI 调用该 tool 后走 `runOnce`：进程运行、收集 stdout 返回给 AI，进程随即被回收 |
| `"resident"` | 常驻 | AI 调用后走 `startLong`：进程持续运行并登记到**后台进程注册表**（`AgentProcessRegistry`）；`execute` 立即返回「已后台启动」占位文本，输出在后台累积，AI 可经内置工具 `list_processes` 查看累积输出、`kill_process` 结束 |

- **缺省 = `once`，未知值静默回退 `once`**（项目铁律「未知静默忽略」）——旧插件不声明该字段行为不变。
- 两种形态的 `tool.py` 写法差异：一次性脚本打印结果后正常退出；常驻脚本在打印首行后保持运行
  （如 `while True: time.sleep(1)`），直到被 `kill_process` 结束。

### 4.4 stdout 约定

- 成功：exit code 0，stdout 内容即返回给 Agent 的文本（无输出显示 `_(no output)_`）。
- 失败：非零 exit code → Agent 报告 `[plugin "name" exited with code N]`；stderr 自动追加到输出末尾。
- 建议纯文本 / Markdown，避免超长（>4096 字符可能被截断）；中文输出用 UTF-8
  （`sys.stdout.reconfigure(encoding='utf-8')`）。

落盘：`plugins/<id>/agent/manifest.json` + `tool.py`。参考：`examples/example-agent-current_time/`。
完整规范：`lib/core/agent/docs/plugin-agent-tool.md`。

---

## 五、skin 形态（AI 视图皮肤包）

skin 型插件声明「DIY your own greenix」外观 DIY 段，**只覆盖 AI 视图内部消费点的功能色与
局部渲染，绝不触碰 `ThemeData`/`ColorScheme` 语义色**。放入 `plugins/<id>/skin/` 后由
`SkinLoader` 扫描加载，设置面板「外观 · 皮肤包」一键切换，ChangeNotifier 热生效。

### 5.1 manifest 契约（`SkinDescriptor`）

`type:"skin"` 必填，其余 DIY 段全部可选，未知键静默忽略（未配置 → 渲染层回退默认值）：

| 段 | 键 | 说明 |
|----|----|------|
| `assets` | `emptyIcon`（横竖屏一致的单一图标）、`logoDesktop`/`logoMobile`（旧，向后兼容读）、`backgroundImage` | 图片资源引用（相对 manifest 路径） |
| `background` | `type`(`solid`/`gradient`/`image`)、`color`、`gradient.from/to/angle`、`imageDesktop`/`imageMobile` | 对话背景（分横竖屏） |
| `buttons` | `inputBar.{workspace,webSearch,thinkingEffort,tools,bgProcess,skills,clear}`、`messageActions.{copy,regenerate,edit}` | 按钮显隐（`null`=未配置→显示） |
| `thinking` | `title`、`visible`、`colors.{header,containerBackground,containerBorder,contentText,chipMemoryBg/Fg,chipSkillBg/Fg,chipToolBg/Fg,chipToolResultBg/Fg}` | 思考栏配色 + 标题 |
| `bubble` | `userBackgroundColor`/`userTextColor`/`assistantBackground`/`assistantTextColor`/`borderRadius`/`maxWidthRatio` | 消息气泡样式 |
| `avatar` | `user`/`assistant`（hex 颜色**或皮肤内 SVG/图片资源引用**）、`userBackgroundColor` | 头像 DIY |
| `emptyState` | `logo`（hex 或图片引用）、`title` | 空状态欢迎区 |
| 顶层 | `effortColor`、`toolActiveColor`、`codeInline`、`codeBlockBackground` | 功能色快捷覆盖 |

最小声明：

```json
{
  "type": "skin",
  "id": "my-skin",
  "name": "我的皮肤",
  "background": { "type": "gradient", "gradient": { "from": "#1B8A4F", "to": "#0F9D58" } },
  "bubble": { "userBackgroundColor": "#DCEDC8", "borderRadius": 18 },
  "avatar": { "user": "avatar_user.svg", "userBackgroundColor": "#C8E6C9" }
}
```

落盘：`plugins/<id>/skin/manifest.json` + 引用的 SVG/图片资源（相对 manifest 路径）。
参考：`examples/example-skin-evergreen-logo/`（含 SVG 资源）。解析源码：`lib/core/skin/skin_descriptor.dart`。

---

## 六、registry 条目（plugins.json）

在 `docs/plugin-registry/plugins.json` 的 `plugins` 数组新增一项。

### 6.1 条目字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | ✅ | 全局唯一，如 `zjucrawler` |
| `name` | `string` | ✅ | 展示名 |
| `description` | `string` | — | 一句话描述 |
| `longDescription` | `string` | — | 长描述 |
| `author` | `string` | — | GitHub 用户名 |
| `version` | `string` | — | 版本号 |
| `repo` | `string` | — | GitHub 仓库 URL |
| `homepage` | `string` | — | 主页 |
| `license` | `string` | — | 许可证 |
| `lattice` | `string` | — | 格：`module` / `data-source` / `theme` / `skin` / `agent` 等（plugins.json 现有取值见下） |
| `dimensions` | `string[]` | — | 能力维度：`data` / `agent` / `ui` 等 |
| `install` | `object` | — | **下载办法**（见 6.2） |
| `manifest` | `object` | — | **manifest 获取办法**（见 6.3） |
| `stars` | `int` | — | 静态 star 数 |

### 6.2 `install`：下载办法

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `string` | ✅ | 固定 `github` |
| `url` | `string` | ✅ | 仓库 URL（`https://github.com/owner/repo`） |
| `strategy` | `string` | — | `source`（默认，clone 源码）或 `release`（下载二进制） |
| `assetPattern` | `string` | — | `release` 下筛选 asset 的子串 |
| `platforms` | `string[]` | — | `release` 下支持的平台白名单 |

**`strategy: "source"`**（适合无 release 二进制的库，如 Python 包）：

```json
"install": {
  "type": "github",
  "url": "https://github.com/cubicYYY/ZJUCrawler",
  "strategy": "source"
}
```

**`strategy: "release"`**（适合发布二进制的程序，如 Go 程序）：

```json
"install": {
  "type": "github",
  "url": "https://github.com/cxz66666/zju-ical",
  "strategy": "release",
  "platforms": ["windows", "macos", "linux"],
  "assetPattern": "zjuical {platform}_{arch}!srv"
}
```

`assetPattern` 规则（务必记住）：
- 平台占位符：`{platform}` → `windows`/`darwin`/`linux`，`{arch}` → `amd64`/`arm64`/`386`。
- **空格 = AND**：空格分隔的多个词必须**同时**命中 asset 名。
- **`!` = 排除词**：`!` 后是排除词（多个用 `,` 分隔），命中即剔除。
- `platforms` 白名单：当前平台不在白名单内时**安装直接报错**。
- `assetPattern` 为空时，下载器按当前平台推断。

### 6.3 `manifest`：manifest 获取办法

**这是解决「外部仓库没有 Evergreen manifest」协议鸿沟的关键**——外部仓库本身不是 Evergreen 插件，
作者通过本字段声明一份 manifest，Evergreen 据此把它变成插件。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source` | `string` | ✅ | `inline` / `local` / `github` |
| `json` | `object` | inline 时 ✅ | 内嵌完整 manifest |
| `path` | `string` | local / github 时 ✅ | 资源路径 |
| `repo` | `string` | github 时 ✅ | 仓库全名 `owner/repo` |

**`inline`**（manifest 稳定、无额外资源文件）：

```json
"manifest": {
  "source": "inline",
  "json": { "type": "module", "id": "x", "name": "X" }
}
```

**`local`**（指向 `docs/plugin-registry/` 下的静态资源目录，安装时整目录复制）：

```json
"manifest": {
  "source": "local",
  "path": "assets/zjucrawler"
}
```

**`github`**（指向 GitHub 仓库内的**资源目录**）：

```json
"manifest": {
  "source": "github",
  "repo": "owner/repo",
  "path": "plugins/zju_autosign"
}
```

- `repo`：仓库全名 `owner/repo`；`path`：仓库内资源目录相对路径（**非单个文件**）。
- 安装时 `git clone` 整个仓库到 `plugins/<id>/`，再按 `path` 把资源目录内容上移到根，
  使 `module/`/`data/`/`config/` 正确落盘（与 `local` 源结果一致）。
- **前提**：需 `install.strategy:"source"`（有完整仓库）。`release` 策略请用 `inline`/`local`。

---

## 七、落盘与生命周期（理解即可）

1. **下载**：按 `install.strategy` 拉取到 `plugins/<id>/`（source → clone；release → 下载 asset）。
2. **manifest 落盘**：按 `manifest.source` 得到 manifest → 写到 `plugins/<id>/<type>/manifest.json`。
3. **加载**：`ModuleLoader` / `registerDataSourcesFromManifest` 扫描 `plugins/<id>/` 自动加载。
4. **删除**：删除 `plugins/<id>/` 目录即完成卸载。

---

## 八、上架清单（交付前逐项核对）

- [ ] 在 `plugins.json` 的 `plugins` 数组里新增一个条目
- [ ] 填 `id` / `name` / `author` / `repo` / `description`
- [ ] 声明 `install`（下载办法）——**可省略**：插件文件随安装包分发（无需网络下载）时不写 `install`，安装器跳过下载直走 `manifest` 落盘
- [ ] 声明 `manifest`（inline / local / github）
- [ ] 若仓库是「库」形态，额外提供适配壳（符合 data-source CLI 契约）
- [ ] theme：`theme/theme.json` 含 `type` + 8 个语义色
- [ ] module：`module/manifest.json` 含 `type`/`id`/`name` 必填项
- [ ] data-source：`data/manifest.json` + 适配壳 + （如需）`config/config.json`；`script` 与 `process` 二选一
- [ ] agent：`agent/manifest.json`（`name`/`description`/`schema` 必填，`runtime:"python"`，`lifetime` 一次性/常驻）+ `tool.py`
- [ ] skin：`skin/manifest.json`（`type:"skin"` + DIY 段）+ 引用的 SVG/图片资源
- [ ] 凭证：适配壳走 `_get_config` 三级降级，不硬编码；优先复用内置 key
- [ ] 新增设置项：在 `config/config.json` 声明 `settings[]`（key 全局唯一 + 前缀）
- [ ] Python 依赖：manifest 顶层声明 `requirements`（安装器自动 pip 装）
- [ ] module 进程：`process[]` 声明正确（`scope:long` 常驻 / `scope:short` 一次性、`runtime:python/native`）
- [ ] Python 依赖优先标准库/轻量包，避免重量级依赖（selenium/torch/playwright）

---

## 红线（禁止事项）

- ❌ registry 条目里**硬编码敏感信息**（凭证/密钥/token）。
- ❌ 适配壳**硬编码凭证**——必须走 `_get_config` 三级降级。
- ❌ 适配壳 stdout **混入非 JSON**（日志走 stderr）。
- ❌ module manifest 缺 `type`/`id`/`name`（会抛 `FormatException`）。
- ❌ 重复 `id`（`ModuleRegistry.register` 抛 `ArgumentError`）。
- ❌ 需要网络下载的插件却漏写 `install` 声明——安装器按「`install` 为空=随包分发」跳过下载，将导致文件缺失无法加载。
- ❌ 随包分发的内置插件仍写 `install.type:github` 指向本仓库——会误触发整仓 clone（历史错误行为，已废弃），应省略 `install`。
- ❌ 新增 key 但**不在 config.json 声明**——`_get_config` 三级降级全失败，读不到值。
- ❌ 适配壳依赖第三方包但**不声明 `requirements`**——运行时 `ModuleNotFoundError`。
- ❌ `default` 值用 JSON bool（`true`）而非字符串（`"true"`）——bool 写入校验会拒绝。
- ❌ 常驻进程 `protocol:"http"` 却**不输出 `PORT:<N>` 首行**——`ProcessManager` 端口探测超时 → 被杀。
- ❌ 常驻进程**不提供 `GET /health`**——health check 3 次失败 → 被杀。
- ❌ `runtime:"python"` 但 exe 写编译二进制（或反之）——首参拼接错误，进程起不来。
- ❌ HTML 插件 `process.run` 调**未在 manifest 声明的 exe**——白名单 fail-closed，直接抛异常。
- ❌ agent manifest 缺 `name` / `description` / `schema`——插件被跳过（fail 可见而非误跑）。
- ❌ agent manifest 声明 `"runtime":"python"` 却只提供 `.exe`——声明错配，插件被跳过。
- ❌ 新 agent 工具产出 `.exe`——统一 `.py` 主路径（.exe 仅存量 legacy）。
- ❌ skin manifest `type` 不是 `"skin"`——`SkinDescriptor` 抛 `FormatException`。

---

## 参考实现索引（`examples/`）

| 目录 | 形态 | 关键文件 |
|------|------|---------|
| `examples/example-theme-warm_study/` | theme | `theme/theme.json` |
| `examples/example-html-view/` | module（HTML） | `module/manifest.json` + `module/index.html` |
| `examples/example-data-zju_grades/` | data-source | `data/manifest.json` + `data/scraper.py` + `config/config.json` |
| `examples/example-data-video_stream/` | data-source（auth + stream） | `data/manifest.json` + `data/fetch.py` + `config/config.json` |
| `examples/example-agent-current_time/` | agent | `agent/manifest.json` + `agent/tool.py` |
| `examples/example-skin-evergreen-logo/` | skin | `skin/manifest.json` + `skin/*.svg` |

> 创作新插件时，优先复制对应 `examples/` 目录为模板，替换 `id`/`name` 与业务逻辑，避免从零拼字段。
