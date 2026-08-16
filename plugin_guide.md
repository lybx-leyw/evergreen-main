# Evergreen 插件开发指南（两套路径）

> 适用版本：v2.0（beta 之后、正式版之前的代码基线）
> 面向读者：不太熟悉编程、但想给 Evergreen 加一个自己插件的同学
> 说明：本指南只讲「怎么开发插件」，不要求你改 Dart 框架代码（除非你选路径 A 的自写模板档位）。

---

## 0. 先看懂三句话

Evergreen 是一个**本地优先、AI 原生**的桌面工具平台。它本身几乎是空的，所有功能都由**插件（plugin）**提供。插件放在仓库的：

```
evg-base/plugins/<你的插件id>/
```

平台启动时会自动扫描 `plugins/` 下的每个子目录，找到里面的 `module/manifest.json`，就知道「有这么一个插件、它叫什么、长什么样、点开它在哪个位置」。

插件分两条创作路径，你可以任选一条：

| 路径 | 你写什么 | 适合谁 | 优点 | 缺点 |
|------|----------|--------|------|------|
| **A. Dart 内置** | Dart 界面（复用模板则免写）+ 一个 manifest | 想要最快、最丝滑的体验 | 全链路 Dart 直通，性能高，UI 和系统完全一体化 | 要会 Dart（或只复用现有模板）；完全自定义界面要碰构建 |
| **B. HTML 插件** | 普通网页（`.html`/`.css`/`.js`）+ 一个 manifest | 会一点前端 / 想要完全自由的界面 | 用你熟悉的网页技术，界面想怎么画怎么画 | 跑在网页容器里，比 Dart 略慢一丢丢 |

两条路径**共享同一套「插件目录 + manifest 声明 + 数据中枢」机制**，差别只在「界面由谁画、数据怎么来」。

---

## 1. 一个插件的目录长什么样（两条路径都一样）

无论选哪条路径，你的插件都是一个文件夹。最小骨架：

```
evg-base/plugins/my-first-tool/
├── module/                ← 必须有：告诉平台「这是一个模块」
│   └── manifest.json      ← 必须有：插件的身份证
├── data/                  ← 可选：如果你要自带数据源（见 §6）
│   └── manifest.json
└── index.html             ← 仅路径 B 需要：你的网页界面
```

> 注意：插件的正式身份证号是 manifest 里的 `"id"` 字段（平台扫描时读的是它，见 `module_loader.dart`）。但**强烈建议**让文件夹名和 `id` 保持一致（都用 `my-first-tool`），否则自己和别人都会看晕。一旦定下就不要随便改 id，改了等于换了一个新插件。

平台扫描规则（来自 `lib/core/module/module_loader.dart`）：
- 只认 `plugins/<id>/module/manifest.json` 这个文件。
- 文件里 `"type"` 必须是 `"module"`，否则被忽略。
- 解析失败会在日志里警告，但**不会**让整个程序崩溃——所以写错了也能安全重试。

---

## 2. Path A：Dart 内置插件（高性能、一体化）

Path A 用 Dart（Flutter）画界面。**先记住一个核心认知**：

> 平台靠 manifest 里的 **`template` 字段**决定「用哪个渲染器」来画你（默认 `'v4'`），**不是**靠 `renderMode` 字段。

平台已经内置了 8 个模板渲染器（来自 `lib/renderer/templates/generated/template_registry.g.dart`）：

| `template` 值 | 渲染器 | 用途 |
|---------------|--------|------|
| `v4`（默认，可不写） | V4ModleTemplate | 通用复合视图：`pages` 多页 + 组件槽位（数据面板/卡片/表格/表单…） |
| `zju` / `classroom` / `zdbk` | ZjuModleTemplate | 浙大场景 |
| `paper_reading` | PaperReadingModleTemplate | 论文阅读 |
| `html` | HtmlModleTemplate | 网页容器（这就是路径 B，见 §3） |
| `scraper` | ScraperTemplate | 爬虫 |
| `theme-creator` | ThemeCreatorModleTemplate | 主题创作 |

（`renderMode: "dart"` / `"html"` 是 V2 清单里的顶层元数据字段，当前调度器实际上不读它做决定——真正的路由看 `template` / `pages` / `workspace` / id 特判。所以新手**认准 `template` 字段即可**，`renderMode` 可写可不写。）

Path A 再分两种「子模式」：

### A 的两种子模式

| 子模式 | 代表例子 | 怎么被平台发现 | 要不要写 Dart | 改完要不要重编译 |
|--------|----------|----------------|---------------|------------------|
| **A1 硬编码内置** | `zju_modle`（浙大模块） | 写在框架代码 `registerZjuBuiltinModules()` 里 | 要，且要改框架文件 | 要 |
| **A2 声明式 Dart 模块** | `data-dashboard`（数据中枢）、`ai-assistant`（AI 助手） | `plugins/<id>/module/manifest.json` 声明，靠 `template`/`pages` 决定渲染 | 可选（复用模板则 0 行 Dart） | 不用（热加载） |

> 一句话：
> - **A1** 是把模块「焊死」在程序里，性能最高最稳，但只有框架维护者才适合做，普通开发者**不建议**碰。
> - **A2** 是「用一个 manifest 声明模块，界面由某个 Dart 模板来画」。它分两档：**复用现有模板（写 0 行 Dart）** 或 **自写新模板（写 Dart）**。这是普通开发者推荐的高性能做法。

### A2 档位一：复用现有模板（写 0 行 Dart，最推荐）

如果你的工具本质上是「多页数据面板 / 卡片 / 表格 / 表单」这类，直接复用 `v4` 模板——**只写 manifest，不写任何 Dart**。真实例子 `plugins/data-dashboard/module/manifest.json`（数据中枢面板，已完整照抄）：

```json
{
  "schemaVersion": "2.0",
  "renderMode": "dart",
  "type": "module",
  "id": "my-data-panel",
  "name": "我的数据面板",
  "description": "一句话说明这个插件干嘛的",
  "icon": "storage",
  "route": "/my-data-panel",
  "version": "1.0.0",
  "dependencies": [],
  "nav": {
    "sidebar": { "section": "base系统", "order": 20 }
  },
  "pages": [
    {
      "id": "main",
      "label": "📊 我的面板",
      "default": true,
      "layout": {
        "type": "grid",
        "preset": { "columns": 1, "gap": 0 },
        "slots": {
          "dashboard": {
            "component": {
              "type": "data-dashboard",
              "config": { "dataSource": { "endpoint": "orch://my_source" } }
            }
          }
        }
      }
    }
  ]
}
```

要点：
- **没写 `template` 字段** → 默认 `v4` → 走 `pages` 调度，界面由 v4 模板 + 你声明的 `pages`/`slots` 自动拼出来。
- `pages[].layout.slots.<id>.component.type` 是组件名（如 `data-dashboard`、`card-list` 等）；`config.dataSource.endpoint` 写 `orch://<数据源名>` 就能把数据灌进去（数据源见 §6）。
- `route` 不能和已有插件重复。可以去 `plugins/` 下翻一圈，避开 `/ai-assistant`、`/data-dashboard` 等。
- 这套「只写 JSON、不写代码」的玩法，正是平台自带插件设计器（plugin-designer）在做的事——你甚至可以在应用里用可视化向导生成这份 manifest。

### A2 档位二：自写全新 Dart 模板（要写 Dart）

如果你要的是独一无二、v4 给不了的界面，才需要写一个全新的 Dart 模板，并把它注册进 `TemplateRegistry`。分三步：

**第 1 步**，在 `lib/renderer/templates/<你的模板名>_modle/` 新建一个 Dart 文件，实现 `ModleRenderer`（参考 `zju_modle_template.dart`）：

```dart
import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart'; // ModleRenderer

class MyToolTemplate extends ModleRenderer {
  const MyToolTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    // descriptor 里带着 manifest 的全部信息（name/route/...）
    return Scaffold(                // 你的界面从这开始画
      body: Center(child: Text(descriptor.name)),
    );
  }
}
```

**第 2 步**，注册这个模板。参考 `template_registry.dart` 顶部注释：正式做法是编辑 `templates/templates_index.json` 与 `build_profiles/<profile>.json`，然后运行 `dart tool/gen_template_registry.dart --profile <name>` 重新生成 `template_registry.g.dart`；开发期也可以临时用 `TemplateRegistry.register('my-tool', const MyToolTemplate())` 注册。

**第 3 步**，你的 manifest 里写 `"template": "my-tool"`（对齐第 2 步注册的 key）。

> ⚠️ 新手提示：档位二需要能跑起 Flutter 构建（`dart analyze` / `flutter build`）。如果只是想「加个功能」，优先档位一或路径 B。

### 特例：ai-assistant 为什么不能「复制改名」？

你可能看到 `ai-assistant` 的 manifest 只有 `renderMode:"dart"`、没有 `template` 字段，就想「复制它、改个 id 不就又有一个 Dart 模块了？」——**不行**。

`ai-assistant` 是平台自带的 AI 助手，调度器 `module_dispatch.dart` 里把它**按 id 硬编码**跳转到聊天视图（`if (descriptor.id == 'ai-assistant') → ChatControllerView`）。它的 manifest 只负责提供名字/图标/路由/工作区这些元信息，界面是框架里写死的。

所以对普通开发者来说，真正可复用的 Dart 路径是上面两个档位（复用 v4 模板 / 自写新模板），而不是复制 ai-assistant。

### A1（硬编码内置）一句话说明

如果你看到 `lib/renderer/templates/zju_modle/zju_builtin_modules.dart` 用 `registerZjuBuiltinModules()` 把一堆 `ModuleDescriptor` 直接焊进框架——那就是 A1。普通开发者**不要**用这种方式：它改的是框架本身、每次改动都要重新编译整个程序，而且容易和其它内置模块冲突。只有「平台自带的核心模块」才走这里。

---

## 3. Path B：HTML 插件（自由界面、网页技术）

这一条路径最适合「我会写网页（HTML/CSS/JS），想做个漂亮界面」的同学。你的插件界面就是一个网页，平台用内置浏览器把它显示出来，并给你一套 `platform.*` 接口去读数据、调 AI、读设置。

### B 步骤一：写 manifest（身份证）

新建 `evg-base/plugins/my-first-tool/module/manifest.json`：

```json
{
  "schemaVersion": "2.0",
  "type": "module",
  "id": "my-first-tool",
  "name": "我的数据面板",
  "template": "html",            // ← 关键：告诉平台「用网页来画我」
  "version": "1.0.0",
  "route": "/my-first-tool",
  "nav": {
    "sidebar": {
      "section": "自定义",         // 放左侧「自定义」分组
      "sectionOrder": 99,
      "order": 99
    }
  }
}
```

对照真实例子 `plugins/html-creator/my-plugin/module/manifest.json`：
- `template: "html"` 是路径 B 的灵魂（对照路径 A 的 `template: "v4"` 默认值）。平台看到它，就把这个模块交给 `HtmlModleTemplate` 渲染。
- 没有 `renderMode` 字段、没有 `template:"zju"` 之类，平台就按 `html` 去加载 `module/index.html`。

### B 步骤二：写 index.html（你的网页）

在 `module/` 旁边放一个 `index.html`（也就是 `module/index.html`）。这是一个**完整的普通网页**，你可以用任何前端写法。真实例子见 `plugins/html-creator/my-plugin/module/index.html`（一个成绩单可视化面板，约 1000 行，包含完整的 CSS 和 JS）。

最小可运行例子：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>我的面板</title>
  <style>
    body { font-family: sans-serif; padding: 24px; }
    h1 { color: #5c7f66; }
  </style>
</head>
<body>
  <h1 id="title">你好，Evergreen</h1>
  <button onclick="loadData()">加载数据</button>
  <pre id="out"></pre>

  <script>
    // platform 是平台自动注入的桥接对象（见 §5）
    async function loadData() {
      try {
        const d = await platform.data.get('my_source');  // 读数据源
        document.getElementById('out').textContent =
          JSON.stringify(d, null, 2);
      } catch (e) {
        document.getElementById('out').textContent = '出错：' + e.message;
      }
    }
  </script>
</body>
</html>
```

### B 步骤三：让网页读平台能力（JS 桥接）

平台会在网页加载时自动注入一个全局对象 **`platform`**。你的 JS 通过它「借用」Evergreen 的能力，而不用自己写后端。详见 §5。

最关键的一行是读数据：

```js
const data = await platform.data.get('数据源名字');
```

这个「数据源名字」要么是**你自己注册的**（§6），要么是**平台已有的**（比如浙大相关数据源，或别人插件注册过的）。如果名字不存在，会走兜底逻辑，界面可能空白——所以先确认名字对得上。

---

## 4. 两条路径怎么选（决策小抄）

- 你想要**丝滑、和系统长得一样、性能最好** → 选 **A2 档位一（复用 v4 模板）**，只写 manifest 就能有数据面板；想要更独特的 Dart 界面再上档位二。
- 你想要**完全自由的界面、会用网页技术、不想碰 Flutter 构建** → 选 **B（HTML 插件）**。
- 你是**框架维护者、在做平台核心模块** → 才可能用到 **A1（硬编码内置）**，普通开发者跳过。

记忆口诀（核心就一条：看 `template` 字段）：
- `template: "html"` + `module/index.html` → 路径 B（网页画）。
- `template` 指向某个 **Dart 模板名**（默认 `v4`，可不写）→ 路径 A（Dart 画）；要全新界面就自写并注册一个新模板。

---

## 5. Path B 的 JS 桥接 API（`platform.*` 速查）

网页里能用的 `platform` 对象，来自 `lib/renderer/templates/html_modle/bridge_script.dart`。它同时兼容 Windows 和安卓的底层通道，你不用管差异，统一用下面的写法。

### 5.1 读数据 `platform.data`

| 方法 | 作用 | 示例 |
|------|------|------|
| `data.get(name)` | 拉取某个数据源（优先缓存） | `const d = await platform.data.get('my_source')` |
| `data.list()` | 列出所有已注册数据源 | `const all = await platform.data.list()` |
| `data.refresh(name)` | 强制重新拉取 | `await platform.data.refresh('my_source')` |
| `data.testConnectivity()` | 测试**全部**数据源的连通性（不带参数） | `const ok = await platform.data.testConnectivity()` |
| `data.subscribe(name, cb)` | 订阅变化（约 5 秒轮询一次；变化时回调收到 `{ name, data }` 对象） | `platform.data.subscribe('my_source', evt => render(evt.data))` |

数据返回结构取决于数据源本身。比如成绩单例子里约定返回 `{ items: [...] }`，所以代码写 `d.items`。

### 5.2 调 AI `platform.ai`

```js
const reply = await platform.ai.chat('帮我总结这段数据');
// 可选风格（style 参数）：platform.ai.chat(prompt, style)
// style 取值：explanatory（讲解）/ learning（学习）/ concise（简洁）/ socratic（苏格拉底式追问）
```

### 5.3 调核心接口 `platform.api`

```js
// 直接打平台的 6 个核心 HTTP 服务之一
const r = await platform.api.call('core', '/core/plugins');
// service 取值：agent / module / data / theme / config / core
```

这些服务地址由平台写进项目根目录的 `.agent_port` / `.config_port` / `.data_port` / `.module_port` / `.theme_port` / `.core_port` 文件，`CoreApiDiscovery` 会自动读，你不用关心端口号。

### 5.4 读/写设置 `platform.settings`

```js
const v = await platform.settings.get('someKey');
await platform.settings.set('someKey', 'newValue');
```

### 5.5 读主题色 `platform.theme`

```js
const colors = await platform.theme.getColors();
// 平台也会往网页注入 CSS 变量（--evg-*），你可以在 CSS 里直接用，随全局主题自动换肤：
//   --evg-background 页面背景     --evg-surface 卡片/面板底色
//   --evg-border 边框/分隔线       --evg-text 主文字
//   --evg-text-secondary 次级文字  --evg-accent 强调/品牌色
//   --evg-accent-bg 强调色半透明底 --evg-accent-border 强调色半透明边框
//   --evg-error 错误态            --evg-others 其余杂色
// 用法：body { background: var(--evg-background); }
```

### 5.6 事件 `platform.emit` / `platform.on`

同一页面内不同组件之间发消息：

```js
platform.emit('my-event', { value: 1 });
platform.on('my-event', (payload) => console.log(payload));
```

---

## 6. 数据源：让你的插件「有数据」（两条路径共用）

无论 A 还是 B，如果你要展示真实数据，数据都来自 **数据中枢（DataOrchestrator）**。你可以：

- **(a) 复用已有数据源**：直接用别人/平台已经注册好的 `orch://<名字>`。路径 B 里就是 `platform.data.get('名字')`。
- **(b) 自己注册一个新数据源**：写一个 `plugins/<id>/data/manifest.json` + 一个后端程序（`.exe` / `.py`），平台启动时会把它注册进数据中枢。

### 6.1 data/manifest.json 长什么样

格式来自 `lib/core/data/plugin/data_source_manifest.dart` 和 data 模块的 CLAUDE.md：

```json
{
  "type": "data-source",          // ← 必须是 data-source
  "id": "my-first-tool",
  "name": "我的数据源",
  "process": "fetcher.exe",        // 你的后端程序文件名（放在 data/ 目录下）
  "preferredPort": 0,              // 0 = 让平台分配随机端口
  "dataTypes": [
    {
      "name": "my_source",         // ← 全局唯一，后面 platform.data.get('my_source') 用的就是它
      "category": "自定义",
      "displayName": "我的数据",
      "ttl": "5m",                 // 缓存有效期：5m / 1h / 30s 等
      "persistentKey": "my_source_cache",
      "endpoint": "/api/data"       // 你的后端上提供数据的 HTTP 路径
    }
  ]
}
```

要点：
- `dataTypes[].name` 必须全局唯一。建议用「插件id_业务名」前缀，避免撞车（例如 `zju_zdbk_transcript`）。
- `endpoint` 里的 `{port}` 占位符会被平台自动替换成实际端口，你一般直接写 `/api/data` 这种相对路径即可。

### 6.2 后端程序（`.exe` / `.py`）要满足的契约

平台会帮你启动这个程序，但它要求程序「讲规矩」（来自 data 模块 CLAUDE.md 的「插件 .exe 行为契约」）：

1. 监听 `127.0.0.1` 上的某个端口（端口号随意，平台会探测）。
2. 启动后往**标准输出**打印一行：`PORT:12345`（数字随便，`PORT:` 后跟端口，必须 flush）。
3. 提供 `GET /health` → 返回 `200 OK`（平台用来确认你准备好了）。
4. 提供数据接口（就是上面 `endpoint` 写的路径），返回 `200 OK` + JSON 正文。
5. 收到系统终止信号（SIGTERM）后干净退出（平台给 2 秒，超时强杀）。

> 你可以用 Python（Flask/FastAPI）、Go、Rust、Node 任何语言写这个后端，只要编译/打包成平台能跑起来的程序，并满足上面 5 条。

### 6.3 一个完整 Path B 插件的最小全貌

```
evg-base/plugins/my-first-tool/
├── module/
│   ├── manifest.json        ← template:"html"，声明这是一个网页模块
│   └── index.html           ← 你的界面，里面调 platform.data.get('my_source')
└── data/
    ├── manifest.json        ← type:"data-source"，声明数据源 my_source
    └── fetcher.py           ← 后端：打印 PORT:、提供 /health 和 /api/data
```

这样平台启动后：自动注册 `my_source` 数据源 → 你的网页打开 → `platform.data.get('my_source')` 就能拿到 `fetcher.py` 返回的数据。

---

## 7. 常见问题（给新手的避坑）

**Q1：我改了 manifest，界面没变？**
平台是「扫描式」加载，一般重启应用即可生效。若是 `template:"html"`，改 `index.html` 通常热刷新就能看到；若是 Dart（A2），可能需要重新构建。

**Q2：我的 route 填什么？**
以 `/` 开头、`plugins/` 下唯一即可，例如 `/my-first-tool`。不要和已有插件撞（`/ai-assistant`、`/data-dashboard` 等已占用）。

**Q3：左侧栏分组怎么选？**
`nav.sidebar.section` 填 `"base主功能"`、`"base系统"` 或 `"自定义"`。前两者是平台主功能区，新插件建议先用 `"自定义"` 避免打乱官方布局。

**Q4：我不会 Dart，能走 Path A 吗？**
可以走 **A2 档位一**（复用 v4 模板，靠 manifest 的 `pages`/布局声明来定制，不写 Dart 代码）。但如果要**完全自定义界面**，档位二必须写 Dart——那种情况建议直接选 Path B。

**Q5：数据名字写错了会怎样？**
`platform.data.get('错误名字')` 会解析不到，界面可能空白或报错。先用 `platform.data.list()` 打印出所有已注册名字，确认后再填。

**Q6：后端程序一定要 `.exe` 吗？**
不一定。`manifest` 的 `process` 字段写文件名，平台按以下规则决定怎么运行它（来自 `lib/core/plugin/plugin_runner.dart`）：
- 扩展名是 `.py`，或显式写了 `runtime: "python"` → 自动用 Python 解释器跑（`python <你的脚本>`）。
- 其它（如 `.exe`）→ 直接当作可执行文件跑。

所以你可以用 Python（Flask/FastAPI 等）写后端，放到 `data/` 下即可。核心始终是满足 §6.2 的 5 条契约。

---

## 8. 关键文件索引（想深入看代码时）

| 你想了解 | 看这个文件 |
|----------|------------|
| 插件是怎么被扫描发现的 | `evg-base/lib/core/module/module_loader.dart` |
| manifest 有哪些字段 | `evg-base/lib/core/module/module_descriptor.dart` |
| 调度逻辑（决定用哪个模板画） | `evg-base/lib/renderer/module/module_dispatch.dart` |
| 8 个模板的注册清单 | `evg-base/lib/renderer/templates/generated/template_registry.g.dart` |
| 模板路由注册表 | `evg-base/lib/renderer/templates/template_registry.dart` |
| 一个 Dart 模板长啥样 | `evg-base/lib/renderer/templates/zju_modle/zju_modle_template.dart` |
| HTML 插件的桥接 API | `evg-base/lib/renderer/templates/html_modle/bridge_script.dart` |
| 数据中枢怎么工作 | `evg-base/lib/core/data/orchestrator.dart` |
| 数据源 manifest 格式 | `evg-base/lib/core/data/plugin/data_source_manifest.dart` |
| 现成的 HTML 插件例子 | `evg-base/plugins/html-creator/my-plugin/` |
| 现成的 Dart 模块例子 | `evg-base/plugins/ai-assistant/`、`evg-base/plugins/data-dashboard/` |

---

> 小结：两条路都从 `plugins/<id>/module/manifest.json` 出发。**A 路**靠 `template` 指向某个 Dart 模板（默认 `v4`，配合 `pages` 布局声明，可以一行 Dart 都不写）来画界面；**B 路**靠 `template: "html"` + `module/index.html` 用网页画界面，通过 `platform.*` 桥接读数据/调 AI。数据不管是哪条路，最终都汇到数据中枢 `orch://<名字>`，你可以复用别人的，也可以自己在 `data/manifest.json` + 后端程序里注册新的。
