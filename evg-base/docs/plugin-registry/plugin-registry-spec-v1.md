# Evergreen 插件规范 v1

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-24 |
| 适用 | 插件市场 registry 条目作者 / 第三方插件上架者 |

> 本文定义「外部 GitHub 仓库如何被 Evergreen 市场自动发现、下载、加载为插件」的**上架协议**。
> 覆盖：registry 条目字段、`install` 下载办法、`manifest` 获取办法、适配壳契约、落盘规则。
> 读者读完本文即可让一个第三方仓库被 Evergreen 市场收录并真正跑起来。

---

## 一、背景：飞轮模型

Evergreen 插件市场采用 dsh-market 的「飞轮」模式：

```
第三方作者向 registry 仓库提 PR（新增/更新 plugins.json 条目）
        ↓
市场每次打开时读取 registry（plugins.json）
        ↓
自动发现并展示所有条目（作者 + star 数）
        ↓
用户点「安装」→ 按条目声明的下载办法拉取 → 按 manifest 落盘 → 插件被系统加载
```

**核心原则**：registry 条目是「协议声明」，不是「代码」。作者只需声明
「我的插件从哪下载、manifest 从哪来」，Evergreen 就能自动完成下载与加载。

---

## 二、registry 文件

- 路径：`docs/plugin-registry/plugins.json`（打包为 Flutter asset）。
- 顶层结构：`{ "plugins": [ {条目}, ... ] }`。
- fail-closed：非法条目抛 `FormatException`，不会静默变空列表；重复 `id` 保留首次。

### 条目字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | `string` | ✅ | 全局唯一，如 `zjucrawler` |
| `name` | `string` | ✅ | 展示名 |
| `description` | `string` | — | 一句话描述 |
| `longDescription` | `string` | — | 长描述 |
| `author` | `string` | — | GitHub 用户名（市场卡片展示作者） |
| `version` | `string` | — | 版本号 |
| `repo` | `string` | — | GitHub 仓库 URL |
| `homepage` | `string` | — | 主页 |
| `license` | `string` | — | 许可证 |
| `lattice` | `string` | — | 格：`module` / `data-source` / `agent` 等 |
| `dimensions` | `string[]` | — | 能力维度：`data` / `agent` / `ui` 等 |
| `install` | `object` | — | **下载办法**（见 §三） |
| `manifest` | `object` | — | **manifest 获取办法**（见 §四） |
| `stars` | `int` | — | 静态 star 数（市场打开时会被实时 GitHub star 覆盖） |

---

## 三、`install`：下载办法

声明「这个插件怎么拿到它的文件」。两个策略：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | `string` | ✅ | 固定 `github` |
| `url` | `string` | ✅ | 仓库 URL（`https://github.com/owner/repo`） |
| `strategy` | `string` | — | `source`（默认）或 `release` |
| `assetPattern` | `string` | — | `release` 策略下筛选 asset 的子串（支持平台占位符） |
| `platforms` | `string[]` | — | `release` 策略下支持的平台白名单（`windows`/`macos`/`linux`） |

### 3.1 `strategy: "source"`（clone 源码）

适合**无 release 二进制的库**（如 Python 包）。安装时 `git clone` 到 `plugins/<id>/`。

```json
"install": {
  "type": "github",
  "url": "https://github.com/cubicYYY/ZJUCrawler",
  "strategy": "source"
}
```

### 3.2 `strategy: "release"`（下载 release 二进制）

适合**发布二进制的程序**（如 Go 程序）。安装时查 `releases/latest`，选匹配 `assetPattern`
的 asset 下载（zip / tar.gz 解压 / 单文件直放）到 `plugins/<id>/`。

```json
"install": {
  "type": "github",
  "url": "https://github.com/cxz66666/zju-ical",
  "strategy": "release",
  "platforms": ["windows", "macos", "linux"],
  "assetPattern": "zjuical {platform}_{arch}!srv"
}
```

**平台占位符**（`assetPattern` 内）：
- `{platform}` → `windows` / `darwin` / `linux`（按当前平台）
- `{arch}` → `amd64` / `arm64` / `386`（按当前架构）

**空格分隔多个包含词**：`assetPattern` 里空格分隔的多个词必须**同时**命中 asset 名
（AND）。因为品牌词（`zjuical`）与平台词（`windows_amd64`）之间往往隔着版本号，
用空格拆开各自匹配才能命中。例：`zjuical {platform}_{arch}` 展开为
`zjuical windows_amd64`，两个词独立匹配。

**`!` 排除词**：`assetPattern` 里的 `!` 后是排除词（可多个用 `,` 分隔），
命中即剔除。例：`zjuical {platform}_{arch}!srv` 排除服务端 `zjuicalsrv` 产物。

**`platforms` 白名单**：声明该 release 支持哪些平台。当前平台不在白名单内时，
**安装直接报错**（如安卓遇桌面专用 CLI 插件 → 「该插件不支持当前平台」），
而非下载失败或误下其它平台产物。

`assetPattern` 为空时，下载器按当前平台推断（`windows` / `darwin` / `linux`）。

---

## 四、`manifest`：manifest 获取办法

声明「这个插件的 manifest 从哪来」。**这是解决『外部仓库没有 Evergreen manifest』协议鸿沟的关键**：
外部仓库本身不是 Evergreen 插件，作者通过本字段声明一份 manifest，Evergreen 据此把它变成插件。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `source` | `string` | ✅ | `inline` / `local` / `github` |
| `json` | `object` | inline 时 ✅ | 内嵌的完整 manifest |
| `path` | `string` | local / github 时 ✅ | 资源路径（见下） |
| `repo` | `string` | github 时 ✅ | 仓库全名 `owner/repo` |

### 4.1 `source: "inline"`（硬编码内嵌）

manifest 直接写在 registry 条目里。适合 manifest 稳定、无额外资源文件的情况。

```json
"manifest": {
  "source": "inline",
  "json": { "type": "module", "id": "x", "name": "X" }
}
```

### 4.2 `source: "local"`（本地静态资源）

指向 `docs/plugin-registry/` 下的**资源目录**（相对路径）。目录内放完整的插件静态资源
（`data/manifest.json` + 适配壳 `.py`，或 `module/manifest.json`）。安装时整个目录复制到
`plugins/<id>/`。

```json
"manifest": {
  "source": "local",
  "path": "assets/zjucrawler"
}
```

对应目录结构：

```
docs/plugin-registry/assets/zjucrawler/
├── data/manifest.json          ← data-source manifest
└── data/crawler_adapter.py     ← 适配壳
```

> **前提**：`local` 源安装时经 `AssetManifest` 枚举资源前缀，因此
> `docs/plugin-registry/assets/` 目录必须已声明为 Flutter asset（pubspec.yaml
> `flutter.assets`），否则复制报「本地资源目录为空」。

#### 4.2.1 内置插件登记为 local 资源条目

平台内置插件同样可以登记进 registry，让「发现插件」页能发现并（重新）安装它们。
条目形态与第三方条目一致，区别仅在于：`manifest.source` 用 `local` 指向
`docs/plugin-registry/assets/<id>/`，`install` 指向本仓库（内置插件随仓库分发）。

`view`（module · HTML 插件）条目：

```json
{
  "id": "view",
  "name": "我的成绩单",
  "lattice": "module",
  "dimensions": ["ui"],
  "install": {
    "type": "github",
    "url": "https://github.com/lybx-leyw/evergreen-main",
    "strategy": "source"
  },
  "manifest": { "source": "local", "path": "assets/view" }
}
```

对应目录结构（与 `plugins/view/` 保持一致）：

```
docs/plugin-registry/assets/view/
└── module/
    ├── manifest.json    ← template:"html"，复制后 → plugins/view/module/manifest.json
    └── index.html       ← HTML 页面，复制后 → plugins/view/module/index.html
```

`warm_study`（theme 型）条目：

```json
{
  "id": "warm_study",
  "name": "温暖学习",
  "lattice": "theme",
  "dimensions": ["ui"],
  "install": {
    "type": "github",
    "url": "https://github.com/lybx-leyw/evergreen-main",
    "strategy": "source"
  },
  "manifest": { "source": "local", "path": "assets/warm_study" }
}
```

对应目录结构：

```
docs/plugin-registry/assets/warm_study/
└── theme/
    └── theme.json       ← 主题声明（type:"theme" + 8 色），复制后 → plugins/warm_study/theme/theme.json
```

> **theme 型说明**：`local` 复制的是整个资源目录（含 `theme/theme.json`），主题插件按
> `plugins/<id>/theme/theme.json` 契约正确落盘，无需 `manifest.json`（registry 的
> `manifestRelativePath` 仅服务于 module/data-source 的 `manifest.json` 落盘与依赖补齐）。
> `install.strategy` 保持 `source`（先 clone 仓库、再覆盖式落盘 local 资源）；`install`
> 指向本仓库时克隆体量较大，属既有机制行为。

### 4.3 `source: "github"`（指向 GitHub 仓库路径）

指向 GitHub 仓库内的**资源目录**，安装时从仓库拉取。

```json
"manifest": {
  "source": "github",
  "repo": "owner/repo",
  "path": "plugins/zju_autosign"
}
```

- `repo`：仓库全名 `owner/repo`（用于校验 `install.url` 是否同源）。
- `path`：仓库内**资源目录**的相对路径（非单个 manifest 文件）。安装时把该目录下的
  全部内容复制到 `plugins/<id>/` 根，使 `module/`、`data/`、`config/` 等子目录正确落盘
  （与 `source:"local"` 的落盘结果一致）。
- **前提**：`github` 源依赖 `install.strategy:"source"`（先 `git clone` 整个仓库到
  `plugins/<id>/`，再从 clone 结果里按 `path` 提取资源目录）。若 `install.strategy` 是
  `release`（下载二进制 asset，无完整仓库），请改用 `source:"inline"` 或 `source:"local"`。

对应目录结构（仓库内）：

```
plugins/zju_autosign/            ← path 指向这里（资源目录）
├── module/manifest.json         ← 复制后 → plugins/<id>/module/manifest.json
├── module/index.html
├── data/manifest.json
└── config/config.json
```

---

## 五、manifest 的两种类型

manifest 的 `type` 决定落盘路径与加载方式：

| `type` | 落盘路径 | 加载方式 | 适用 |
|--------|---------|---------|------|
| `module` | `plugins/<id>/module/manifest.json` | `ModuleLoader` 扫描 → 注册模块 → 侧边栏/路由 | UI 模块、导出工具 |
| `data-source` | `plugins/<id>/data/manifest.json` | `registerDataSourcesFromManifest` → 注册进数据中枢 | 数据爬虫、API 封装 |

### 5.1 `data-source` manifest 契约

```json
{
  "type": "data-source",
  "id": "<id>",
  "name": "<显示名>",
  "script": "<适配壳文件名>",
  "runtime": "python",
  "androidSupport": false,
  "dataTypes": [
    {
      "name": "<DataType 唯一名，如 zju_gpa>",
      "typeArg": "<传给适配壳的 --type 值>",
      "category": "<分类>",
      "displayName": "<显示名>",
      "ttl": "30m"
    }
  ]
}
```

### 5.2 `module` manifest 契约

最小 module manifest（`ModuleDescriptor` 解析，`type`/`id`/`name` 必填）：

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

完整 module 字段参考见 `lib/core/module/docs/plugin-module.md`。

---

## 六、适配壳契约（data-source 型）

对于「库」形态的仓库（如 Python 包），需提供一个**适配壳**，把库包装成 Evergreen 认识的 CLI。

### CLI 契约

```
适配壳 --type <typeArg> --project-root <root> --greenix-config <cfg>
```

- **stdout** 输出纯 JSON（结果对象）；exit code 0 = 成功，非 0 = 失败。
- 失败时 stdout 输出 `{"error": "<人类可读信息>"}` + exit code 非 0。
- 凭证走 `_get_config(key)` 三级降级读取（`.greenix/config.json` → 环境变量 → 报错），**不硬编码**。
- 任何异常都收敛为错误 JSON，不得让进程崩溃输出堆栈污染 stdout。

### 凭证 key 约定

浙大统一认证类凭证复用既有 key（无需在适配壳里新增设置项）：

| key | 说明 |
|-----|------|
| `ZJU_USERNAME` | 学号（浙大统一认证账号） |
| `ZJU_PASSWORD` | 密码 |

### 适配壳示例（Python）

适配壳的完整实现见 §九「示例插件」中的 `example-data-zju_grades`（数据源示例）。

---

## 七、落盘与生命周期

1. **下载**：按 `install.strategy` 拉取到 `plugins/<id>/`（source → clone；release → 下载 asset）。
2. **manifest 落盘**：按 `manifest.source` 得到 manifest → 写到 `plugins/<id>/<type>/manifest.json`。
3. **加载**：`ModuleLoader` / `registerDataSourcesFromManifest` 扫描 `plugins/<id>/` 自动加载。
4. **删除**：删除 `plugins/<id>/` 目录即完成卸载（发现页「已安装」卡片提供删除按钮，便于重装）。

---

## 八、上架清单（第三方作者）

提交一个仓库到 registry，需要：

1. 在 `plugins.json` 的 `plugins` 数组里新增一个条目。
2. 填 `id` / `name` / `author` / `repo` / `description`。
3. 声明 `install`（下载办法）。
4. 声明 `manifest`（inline 或 remote）。
5. 若仓库是「库」形态，额外提供适配壳（符合 §六 CLI 契约）。

示例（完整条目）见 `docs/plugin-registry/plugins.json`。

---

## 九、示例插件（参考实现）

`docs/plugin-registry/examples/` 下提供三类插件的**完整参考实现**，覆盖本规范涉及的三种插件形态。第三方作者可复制对应目录为模板起手：

| 示例目录 | 插件形态 | 说明 |
|---------|---------|------|
| `examples/example-theme-warm_study/` | theme | 主题插件：`theme/theme.json` 声明配色（`type:"theme"`） |
| `examples/example-html-view/` | module（HTML） | HTML 模块：`module/manifest.json`（`template:"html"`）+ `module/index.html` |
| `examples/example-data-zju_grades/` | data-source | 数据源插件：`data/manifest.json`（`runtime:"python"` + `script`）+ `data/scraper.py` + `config/config.json` |

### 9.1 theme 示例 —— `example-theme-warm_study`

`theme/theme.json` 是最小主题声明，`type:"theme"` + `colors` 8 个语义色：

```json
{ "type": "theme", "id": "warm_study", "name": "温暖学习",
  "colors": { "background": "#FAF3E7", "surface": "#FFF8ED", "border": "#E5D3B8",
              "text": "#3E2723", "textSecondary": "#6D4C41", "accent": "#E07A3F",
              "error": "#D32F2F", "others": "#F2B880" } }
```

### 9.2 HTML module 示例 —— `example-html-view`

`module/manifest.json` 用 `template:"html"` 声明网页容器，`module/index.html` 是自包含网页（内嵌 CSS/JS，用 `--evg-*` 主题变量 + `platform.*` bridge 读数据/调 AI/跑 exe）。

### 9.3 data-source 示例 —— `example-data-zju_grades`

`data/manifest.json` 声明 `runtime:"python"` + `script:"scraper.py"`，`scraper.py` 是符合 §六 CLI 契约的适配壳（stdout 纯 JSON、失败 `{"error":...}` + exit≠0、凭证三级降级），`config/config.json` 存运行配置。
