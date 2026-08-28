---
name: evergreen-auto-workflow
description: >
  Evergreen 插件「自动工作流」技能：先 GitHub 调研 zju 相关项目 → 评估时效性与可移植性 →
  通过则改造移植为 Evergreen 插件，否则舍弃换下一个；也可从零创作贴合大学生生活的插件
  （skin+theme 配套包 / agent skill 话术与能力边界 / agent tool / 休闲 module 等）。
  当用户要求「开发/拓展 Evergreen 插件」「调研并改造 zju 项目」「做新皮肤/新主题/新技能/
  新工具/新模块」时使用。包含并扩展自 docs/plugin-registry/skill/SKILL.md（五类插件创作契约）。
---

# Evergreen 插件自动工作流 Skill

你是 **Evergreen 平台的自动化插件产线**：不满足于按单一需求手搓插件，而是主动
**调研 → 评估 → 改造/创作 → 验证** 一条龙产出。本技能 = 原插件创作技能
（`docs/plugin-registry/skill/SKILL.md`，五类形态契约）** + 完整工作流 + 创意方向库
+ 双平台能力边界**。

读者（你）按本技能走完流程，即可交付：registry 条目 + `install` 下载声明 +
`manifest` + 适配壳 / 入口文件，且**同时支持 Android 与 Windows**。

---

## 0. 铁律：双平台支持（先读，贯穿一切）

> **任何形态的插件，必须同时支持 Android 与 Windows。这是硬性门槛，不是加分项。**

| 维度 | 怎么做 |
|------|--------|
| Python 运行时 | `runtime:"python"` 统一走 `.py`：Windows 用平台 Python 环境，Android 用 Chaquopy 进程内解释器。**禁止产出 `.exe`/外部二进制**（Android 无法执行，仅存量 legacy 例外） |
| Python 依赖 | **只用标准库或纯 Python 轻量包**。`numpy`/`pandas`/`lxml`/`python-pptx`/`python-docx`/`openpyxl`/`selenium`/`playwright` 等含原生扩展或过重的包，**Android（Chaquopy）装不上或不可靠**。确需 `requirements` 时逐包评估双平台可安装性 |
| 文件写入 | 适配壳/工具脚本**不直接 `open()` 写任意路径**（安全沙箱限制，双平台行为也不一致）。产物用**内存对象（`BytesIO`）+ `zipfile` 打包**，再经平台导出通道落盘；写工作区文件走平台路径服务 |
| 子进程 | **禁止 spawn 外部 exe / shell 命令依赖**（Android 无对等语义）。需要常驻能力用 `process`（Win 子进程 / Android ChaquopyLongProcess，manifest 声明一致） |
| 路径 | 不硬编码 `C:\`、`/tmp`、`/home`。临时目录、工作区目录一律从平台上下文取；路径拼接用 `os.path.join`/`pathlib` |
| 编码 | 所有脚本 `sys.stdout.reconfigure(encoding='utf-8')`；文本文件 UTF-8，杜绝 GBK 依赖 |
| UI 形态 | HTML module（WebView）天然双平台一致，**优先选它**；不依赖 Flutter 专属能力 |
| 网络 | `dio` 双平台一致；Android 模拟器访问宿主机用 `10.0.2.2` 而非 `localhost`（仅调试提示，插件代码不写死） |
| 验收 | 交付前按「§9 双平台验证清单」逐项过：两平台各自能装、能加载、能跑通核心路径 |

**双平台自检口诀**：*纯 Python、无原生依赖、无子进程、无裸路径、UTF-8、UI 走 HTML。*

---

## 1. 工作流总览（闭环）

```
┌──────────────────────────────────────────────────────────────────┐
│  0. 目标确认：本次是「改造 zju 项目」还是「从零创作」？           │
└───────────────┬──────────────────────────────────┬───────────────┘
                │ 改造路线                          │ 创作路线
                ▼                                  ▼
   ┌───────────────────────┐          ┌─────────────────────────┐
   │ A. GitHub 调研         │          │ D. 从零创作（§5 创意库） │
   │   发现 zju 候选项目    │          │   skin+theme / agent     │
   └───────────┬───────────┘          │   skill / agent tool /   │
               ▼                      │   module / data-source   │
   ┌───────────────────────┐          └────────────┬────────────┘
   │ B. 时效性×可移植性评估 │◄────────── 不 OK ──────┘
   │   （决策门）           │            舍弃，换下一个
   └───────────┬───────────┘
               │ OK
               ▼
   ┌───────────────────────┐
   │ C. 改造移植            │
   │   形态映射→manifest→   │
   │   适配壳→双平台自检    │
   └───────────┬───────────┘
               ▼
   ┌───────────────────────┐
   │ E. 交付               │
   │   上架清单+双平台验证  │
   └───────────────────────┘
```

- **改造路线优先**：有合适的 zju 项目时优先走 A→B→C（用户偏好：为 zju 设计的 GitHub 项目改造更好）。
- **创作路线兜底**：调研无果或全部被 B 阶段否决时，转入 D 从零创作；D 的创意也**优先贴合大学生生活**。
- **闭环纪律**：B 阶段被否的项目**记录原因后立即舍弃**，不允许「勉强改造」；把评估结论写入交付说明，供后续复用。

---

## 2. 阶段 A：GitHub 调研（zju 相关）

### 2.1 检索策略

用 GitHub 搜索 API（或网页检索）按以下维度找候选：

| 维度 | 关键词示例 |
|------|-----------|
| 校园生活 | `zju` / `ZJU` / `浙大` / `浙江大学` / `zju university` |
| 场景细分 | `zju course`、`zju schedule`、`zju grades`、`zju classroom`、`zju 选课`、`zju 成绩`、`zju 图书馆`、`zju 校车`、`zju 讲座`、`zju 二手`、`zju 表白墙`、`zju 树洞`、`zju 保研`、`zju 竞赛` |
| topic | `topic:zju`、`topic:zju-course`、`topic:edu-cn` |
| 已收录参考 | 仓库内 `docs/plugin-registry/plugins.json` 已收录的 zju 条目（`zju-ical`、`zjucrawler` 等），可作基线：它们证明了「zju 项目 → Evergreen 插件」路径可行 |

已知的真实候选基线（已在 Evergreen 内部被引用/测试过，可信）：

| 项目 | 形态方向 | 说明 |
|------|---------|------|
| `cubicYYY/ZJUCrawler` | data-source | 浙大教务/课程数据爬虫，可改造为 `data/manifest.json` + `scraper.py` 适配壳 |
| `cxz66666/zju-ical` | data-source / module | 浙大课表 → iCal 导出，release 资产可走 `install.strategy:"release"` |

> 调研时不只盯这俩：持续扩充候选池，覆盖「上课、吃饭、自习、出行、社团、考试、毕业、求职」全链路。

### 2.2 候选清单产出

对每个候选记录：`repo`、star、最近提交日期、语言、license、README 摘要、可能映射的插件形态。
产出**候选清单**（建议 3~6 个，按契合度排序），供阶段 B 逐个过门。

---

## 3. 阶段 B：时效性 × 可移植性评估（决策门）

对候选清单逐项打分，**任一硬性指标不通过即舍弃**，不进入改造。

### 3.1 时效性（这个项目还「活着」吗）

| 检查项 | 通过标准 |
|--------|---------|
| 最近提交 | 1~2 年内有活跃提交；长期无人维护（>2 年）需谨慎，除非功能稳定且无外部依赖 |
| 依赖的外部服务 | 项目依赖的教务系统 / API / 网站**仍可访问**（必要时实际请求一次）；接口是否变更 |
| 数据有效性 | 样例数据（课程、成绩、校历）与当前学期/学年吻合 |
| 环境依赖 | 依赖的 Python 版本、系统库在 2025+ 环境仍可运行 |

### 3.2 可移植性（能搬进 Evergreen 双平台吗）

| 检查项 | 通过标准 |
|--------|---------|
| 实现语言 | Python / JS / HTML / 纯算法优先（可平移为 `.py` 适配壳或 HTML module）；C/C++/Go 编译型、iOS 原生、浏览器扩展**移植成本高，默认否决**（除非有官方 release 资产走 `strategy:"release"`） |
| 依赖面 | 只用标准库 / 轻量纯 Python 依赖（对照 §0 铁律）；出现 `selenium`/`torch`/`playwright`/`opencv` 等 → 否决或重写核心逻辑 |
| 平台耦合 | 无 `win32`/`osascript`/`apt`/shell 脚本硬依赖；路径、编码跨平台可迁移 |
| 许可证 | MIT/Apache/BSD 等宽松许可（可再分发）；GPL 需标注并评估合规 |
| 改造量 | 核心逻辑可在**一次会话内**剥离重写（通常 ≤ 500 行有效逻辑）；动辄数千行胶水代码 → 否决 |

### 3.3 决策

- **全部通过 → 阶段 C 改造移植。**
- **任一硬性不通过 → 在候选清单上标注否决原因，舍弃，取下一个候选（回到阶段 A/B）。**
- 全部候选被否 → 转阶段 D 从零创作。

> 评估结论要**写下来**（否决原因、判断依据），这是工作流可追溯的一部分，也是向用户解释「为什么换下一个」的证据。

---

## 4. 阶段 C：改造移植（外部项目 → Evergreen 插件）

### 4.1 形态映射（先决定搬成什么）

| 外部项目长相 | Evergreen 形态 | 做法 |
|-------------|---------------|------|
| 爬虫 / API 封装（CLI 脚本、库） | **data-source** | 抽核心取数逻辑 → `data/scraper.py` 或 `fetch.py` 适配壳（`_get_config` 三级降级读凭证），`data/manifest.json` 声明 `script` 或 `process` |
| 网页应用 / 前端工具 | **module（HTML）** | 保留 HTML/CSS/JS 交互，改造为 `module/index.html` + `module/manifest.json`，数据经 `platform.data.get()` 接平台数据中枢 |
| 命令行小工具 / 脚本 | **agent tool** | 包装为 `agent/tool.py` + `agent/manifest.json`（`name`/`description`/`schema`/`runtime:"python"`），AI 可调用 |
| 知识 / 规则 / 话术 / 操作手册 | **agent skill** | 整理为 `skill/*.md`（SkillLoader 扫描加载），教 AI 何时用、怎么用 |
| 视觉 / 主题资源 | **theme + skin** | 语义色 → `theme/theme.json`；AI 视图 DIY → `skin/manifest.json` + SVG 资源 |
| 配置文件 / 设置项 | **config** | `config/config.json` 声明 `settings[]`，key 全局唯一 + 前缀 |

### 4.2 移植五步

1. **读源码**：定位核心数据流（输入 → 处理 → 输出），剥离 UI / 平台胶水。
2. **重写依赖面**：把不满足 §0 铁律的依赖替换为纯 Python 标准库实现（示例见 §6 组合效应库）。
3. **产出插件本体**：按 §7 对应形态契约写 `manifest` + 适配壳 / 入口 / 资源。
4. **产 registry 条目**：`docs/plugin-registry/plugins.json` 新增（§8）；外部仓库用 `install.strategy:"source"` + `manifest.source:"github"` 桥接，或整包落 `docs/plugin-registry/assets/` 走 `manifest.source:"local"`。
5. **双平台自检**：过 §0 铁律 + §9 验证清单。

### 4.3 桥接外部仓库的两种姿势

**姿势一：整仓引用（不动上游）** —— 上游仓库无 Evergreen 结构时：

```json
{
  "id": "zju_xxx",
  "name": "浙大 XXX",
  "repo": "https://github.com/owner/zju-xxx",
  "install": { "type": "github", "url": "https://github.com/owner/zju-xxx", "strategy": "source" },
  "manifest": { "source": "github", "repo": "owner/zju-xxx", "path": "evergreen" }
}
```

要求上游仓库内有 `evergreen/` 目录（`module/`、`data/`、`config/` 正确落盘）。

**姿势二：本仓托管（改造产物入库）** —— 上游不便改动时，把改造后的插件本体放进
`docs/plugin-registry/assets/<id>/`，registry 条目用 `manifest.source:"local"` + `path`：

```json
{
  "id": "zju_xxx",
  "name": "浙大 XXX",
  "repo": "https://github.com/owner/zju-xxx",
  "install": { "type": "github", "url": "https://github.com/owner/zju-xxx", "strategy": "source" },
  "manifest": { "source": "local", "path": "assets/zju_xxx" }
}
```

> 两种姿势都**不改动上游代码**，只做「协议桥接 + 适配壳」——这是 Evergreen 的核心哲学：registry 条目是协议声明，不是代码。

---

## 5. 阶段 D：从零创作（创意方向库）

> 全部创意**必须贴合大学生生活**；zju 场景优先。每个方向给出「形态 + 落盘 + 要点」。

### D1. skin + theme 配套包（强烈推荐成套设计）

theme 换语义色（全局），skin 改 AI 视图 DIY（对话背景/气泡/头像/思考栏）。**配套设计、同一插件包**：
`plugins/<id>/theme/theme.json` + `plugins/<id>/skin/manifest.json` + SVG 资源，registry 一个条目搞定两件套。

| 创意 | 主题色（8 语义色示例方向） | skin 要点 |
|------|--------------------------|----------|
| 求是蓝（zju 校色） | `accent` 用求是蓝 `#0057A8`，背景米白 | 渐变背景 + 校徽风 SVG 头像 |
| 西溪湿地 / 西湖烟雨 | 青灰 + 黛色，低饱和 | 水墨风气泡、渐变背景 |
| 樱花季 | 粉白系 | 樱花 SVG 背景、圆角气泡 |
| 图书馆深夜 | 深色 + 暖黄台灯 | 深色背景、低亮度、护眼 |
| 咖啡店自习 | 暖棕 + 奶咖 | 圆角卡片、咖啡色气泡 |
| 荧光夜跑 | 深底 + 高饱和霓虹 | `effortColor`/`toolActiveColor` 亮色 |

落盘与契约见 §7.1（theme）/ §7.5（skin）。参考：`../skill/examples/example-theme-warm_study/`、`../skill/examples/example-skin-evergreen-logo/`。

### D2. agent skill（两种子类）

**D2a. 能力边界 / 组合效应教学 skill** —— 教 AI 理解平台各 tool 的能力边界与组合效应。
直接以本技能 §6「能力边界与组合效应」为内容底稿，整理为 `skill/*.md`：
- 每个 tool 的**能力边界**（能做什么、不能做什么、在哪个平台受限）；
- **组合模式**（哪些 tool 拼起来能解锁新能力，见 §6.2）；
- 触发条件（AI 在什么场景下应想起这条知识）。

落盘：`plugins/<id>/skill/<name>.md`（SkillLoader 自动扫描加载，无需 manifest；支持按插件目录/技能名禁用过滤）。

**D2b. 话术合集 skill** —— 教 AI「像人一样说话」：

| 创意 | 内容要点 | 落盘 |
|------|---------|------|
| 开心话术合集 | 用户分享好消息时的接法：先共情后庆祝，不扫兴不比较，具体到细节 | `skill/celebration.md` |
| 伤心话术合集 | 用户低落时的接法：先接住情绪，不急着给建议，不评判不否定 | `skill/comfort.md` |
| 安慰表达手册 | 安慰 ≠ 讲道理；句式模板：确认感受 → 陪伴 → 可选项支持 | `skill/comfort.md` |
| 说人话手册 | 去 AI 腔：少用「首先/其次/综上所述」，短句、口语、少感叹号、不滥用 emoji | `skill/human_talk.md` |
| 考试周安抚 | 考前焦虑话术、考后对答案的边界感、出分后的接法 | `skill/exam_week.md` |

> 话术 skill 的判别标准：**能直接复用的句子/句式**，不是抽象原则。每篇给足模板句，AI 才能「说人话」。

### D3. agent tool（AI 可调用的小工具）

`plugins/<id>/agent/manifest.json` + `tool.py`（`runtime:"python"`、`lifetime:"once"`、`readOnly` 只读可并行）。

| 创意 | `name` | `schema` | 实现要点 |
|------|--------|---------|---------|
| 当前时间 | `current_time` | `{format: cn/iso}` | `datetime.now()`，时区按用户设置；`readOnly:true` |
| 当前日期 | `current_date` | `{withWeekday: bool}` | 含星期、农历可后续加；`readOnly:true` |
| 学期倒计时 | `semester_countdown` | `{endDate}` | 距 DDL / 期末还有多少天，大学生刚需 |
| 随机推荐 | `random_pick` | `{items[], count}` | 食堂选哪个、今天学什么，`random.sample` |
| 番茄钟换算 | `pomodoro_planner` | `{minutes, break}` | 学习计划分块建议 |

参考：`../skill/examples/example-agent-current_time/`（最小可复制模板）。

### D4. module（休闲 / 实用小模块，HTML 优先）

`plugins/<id>/module/manifest.json` + `index.html`（WebView 渲染，双平台一致；无后端时不用 `process`）。

| 创意 | 玩法/功能 | 实现要点 |
|------|----------|---------|
| 睡前数羊 | 动态羊群逐只跳过栅栏并计数，配呼吸引导 | HTML/CSS 动画 + 轻量 JS；可选番茄钟式呼吸节奏 |
| 西西弗斯推石 | 推石上山小游戏（重力/点击），滚落重来，附加缪语录 | Canvas 小游戏，`requestAnimationFrame` |
| 易经 64 卦 + 解读 | 起卦（手动/随机三枚硬币逻辑）→ 卦象 → 卦辞/爻辞 + 白话解读 | 纯静态数据内嵌 JSON；随机用 `crypto` 或平台取数 |
| 背单词翻卡 | 词卡正反面翻转 + 间隔重复提示 | 纯前端，词库内嵌或接数据源 |
| 自习番茄钟 | 25min 专注 + 白噪音开关 + 统计 | `platform.settings` 存偏好 |
| 课表周视图 | 本周课表可视化（数据接 zju data-source） | 配合 D 阶段 data-source 的组合玩法 |

要点：HTML module 的 `manifest.json` 至少含 `type`/`id`/`name`；交互数据用 `platform.*` bridge（`platform.data.get()` / `platform.settings` / `platform.emit`）；**不声明 `process` 就不需要进程**，纯静态最稳。

### D5. data-source（zju 场景数据源）

| 创意 | 数据 | 形态 |
|------|------|------|
| 浙大课表 | 教务系统课程 | `data/scraper.py` + `_get_config` 读 `ZJU_USERNAME`/`ZJU_PASSWORD` |
| 图书馆座位 | 座位预约实时余量 | `data/fetch.py`（API 封装，`auth` 段） |
| 校车时刻 | 各校区班车时间表 | 静态 JSON + 简单抓取兜底 |
| 讲座/活动 | 校内讲座日历 | API 轮询 + `stream` 段推送 |

契约见 §7.3；`_get_config` 三级降级是凭证读取的唯一正确姿势（§7.3.3）。

---

## 6. 能力边界与工具组合效应（agent skill 的内容底稿）

> 本章既服务于创作（写插件时对照），也可**整章复制进 `skill/*.md`** 作为「教 AI 用平台」的 agent skill 底稿。

### 6.1 平台工具能力边界速查

| 工具/能力 | Windows | Android（Chaquopy） | 替代方案 |
|-----------|:-------:|:-------------------:|---------|
| Python 解释器 | ✅ 平台 Python env | ✅ 进程内 Chaquopy | 无 |
| pip 安装第三方包 | ⚠️ 可装（需联网） | ❌ 不可靠 | 只用标准库 / 纯 Python 轻量包 |
| `python-pptx` / `python-docx` / `openpyxl` | ⚠️ 可装 | ❌ **不支持** | `zipfile` + `BytesIO` 手工构造 OOXML（见 §6.2 例 1） |
| `open()` 写任意文件 | ❌ 沙箱限制 | ❌ 沙箱限制 | 内存打包 → 平台导出通道；工作区文件走平台路径服务 |
| spawn 外部 exe / shell | ⚠️ 白名单 fail-closed | ❌ 无对等语义 | 全部 `.py` + Chaquopy；需要服务用 `process` 常驻 |
| 网络请求 | ✅ `dio` | ✅ `dio` | — |
| UI | ✅ Flutter / WebView | ✅ Flutter / WebView | HTML module 优先（双平台一致） |
| SVG 资源 | ✅ | ✅ | skin/theme 资源用 SVG |
| 常驻进程 | ✅ `subprocess` + `startLong` | ✅ `ChaquopyLongProcess` | manifest `runtime` 声明一致，两者皆走 `.py` |
| 时间/随机/哈希 | ✅ | ✅ | 标准库 `datetime`/`random`/`hashlib` |

### 6.2 组合效应模式库（标准库拼出新能力）

**例 1：无 `python-pptx` 造 PPT**（Android 铁律场景）
```python
import io, zipfile
# pptx 本质是 OOXML zip：用标准库直接拼最小可打开文件
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', CONTENT_TYPES)
    z.writestr('ppt/presentation.xml', PRESENTATION)
    z.writestr('ppt/slides/slide1.xml', SLIDE1)
    z.writestr('ppt/slides/slide2.xml', SLIDE2)
    z.writestr('docProps/core.xml', CORE)
bytes_out = buf.getvalue()   # 纯内存产物，无磁盘写入、无第三方包
```
同样的 `zipfile + BytesIO` 组合可构造 docx/xlsx/zip 导出——**双平台通吃**。

**例 2：数据源 → 展示**：data-source 适配壳（`scraper.py`）取数 → `platform.data.get(name)` 供 HTML module / AI 消费。取数一次、多处复用。

**例 3：agent tool + data-source**：AI 调 `agent/tool.py` 实时取数，绕过 module 的定时刷新，适合「现在还有没有座位」这类实时问题。

**例 4：theme + skin 配套**：一个插件包双 manifest，用户一次安装同时换全局语义色 + AI 视图外观，体验一致性远好于单配。

**例 5：常驻 process + HTML module**：`process` 声明 `scope:"long"` + `protocol:"http"`，Python 常驻服务**首行必须输出 `PORT:<N>`** 且提供 `GET /health`，HTML 侧经 bridge 调用；适合需要状态保持的本地服务（如投票、队列）。

**例 6：内存哈希 + 缓存**：`hashlib.sha256` 对取数结果做指纹，`platform.settings` 存指纹做增量判断——省流量省时间，数据源刷新更聪明。

---

## 7. 五种插件形态契约（继承自原 skill，完整可用）

> 字段级疑问以权威为准：`../skill/SKILL.md`（完整版）+ `docs/plugin-registry/plugin-registry-spec-v1.md` + 源码
> （`lib/core/module/plugin_registry.dart`、`lib/core/data/plugin/data_source_manifest.dart`、
> `lib/core/agent/docs/plugin-agent-tool.md`、`lib/core/skin/skin_descriptor.dart`）。
> **不确定字段、不确定 key、不确定行为时，先翻源码，别猜。源码即文档。**

### 7.1 theme 形态

最小声明：`type:"theme"` + `colors` **8 个语义色**：

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

落盘：`plugins/<id>/theme/theme.json`。参考：`../skill/examples/example-theme-warm_study/`。

### 7.2 module 形态

最小 manifest（`type`/`id`/`name` 必填）：

```json
{
  "type": "module",
  "id": "sleep_sheep",
  "name": "睡前数羊",
  "pages": [{ "id": "main", "title": "数羊", "template": "html" }]
}
```

- **HTML 是用户侧主路径**：`module/index.html` + `manifest.json` 中 `"template":"html"`，由 WebView 加载并注入 `platform.*` JS Bridge（`platform.data.get/refresh/subscribe`、`platform.settings`、`platform.ai.chat`、`platform.theme.getColors()`、`platform.emit/on` 等）。
- 页面自动获得 `--evg-*` CSS 变量（主题色），主题切换实时更新。
- 后端进程：`process[]` 声明（`scope:"long"` 常驻 / `scope:"short"` 一次性，`runtime:"python/native"`、`protocol`）。**无后端就省略 `process`**。

### 7.3 data-source 形态

落盘：`plugins/<id>/data/manifest.json` + 适配壳（`scraper.py` / `fetch.py`）+ （如需）`config/config.json`。

**manifest 要点**：`type:"data-source"`、`id`、`name` 必填；`script`（一次性取数）与 `process`（常驻流）二选一；`auth`/`stream`/`file` 可选段。

**适配壳 = 把「库」包装成 Evergreen 认识的 CLI**：
- stdin 收 JSON 参数（`argMode:"stdin"` 默认），stdout **只输出 JSON**（日志走 stderr）；
- 退出码 0 = 成功，非 0 = 失败（stderr 追加给调用方）。

**`_get_config` 三级降级（凭证读取的唯一正确姿势）**：
1. 环境变量 → 2. 平台 config 服务 → 3. 插件目录 `config/config.json`。
**绝不硬编码凭证**。参考实现：`../skill/examples/example-data-zju_grades/data/scraper.py`。

**内置可复用配置 key（优先复用，别重复造）**：`ZJU_USERNAME` / `ZJU_PASSWORD` 等（zju 场景直接复用，避免新增同义 key）。

### 7.4 agent 形态（AI 助手可调用工具）

落盘：`plugins/<id>/agent/manifest.json` + `tool.py`（`.py` 统一主路径；`.exe` 仅存量 legacy）。

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | ✅ | 蛇形命名，Agent 调用标识符 |
| `description` | ✅ | 给 LLM 看的用途说明，决定 AI 何时调用 |
| `schema` | ✅ | JSON Schema 参数（`type:"object"` + `properties` + `required`） |
| `readOnly` | — | `true`=只读（可并行）；`false`=写操作（串行） |
| `argMode` | — | `"stdin"`（默认）/ `"args"` |
| `runtime` | — | `"python"`（推荐，自动从 `.py` 推断） |
| `lifetime` | — | `"once"`（默认，一次性）/ `"resident"`（常驻，配 `list_processes`/`kill_process`） |

stdout 约定：exit 0 + 纯文本/Markdown 返回 AI；非 0 → `[plugin "name" exited with code N]`；中文输出 `sys.stdout.reconfigure(encoding='utf-8')`；输出别超 ~4096 字符。

参考：`../skill/examples/example-agent-current_time/`。

### 7.5 skin 形态（AI 视图皮肤包）

落盘：`plugins/<id>/skin/manifest.json` + 引用的 SVG/图片资源（相对 manifest 路径）。

`type:"skin"` 必填，DIY 段全部可选、未知键静默忽略：

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

DIY 段：`assets`（emptyIcon/logo/backgroundImage）、`background`（solid/gradient/image）、`buttons`（inputBar/messageActions 显隐）、`thinking`（标题+配色）、`bubble`（气泡样式）、`avatar`（hex 或 SVG）、`emptyState`、顶层功能色（`effortColor`/`toolActiveColor`/`codeInline`/`codeBlockBackground`）。
**只覆盖 AI 视图内部消费点，绝不触碰 `ThemeData`/`ColorScheme` 语义色**。

参考：`../skill/examples/example-skin-evergreen-logo/`（含 SVG）。

---

## 8. registry 条目（plugins.json）

在 `docs/plugin-registry/plugins.json` 的 `plugins` 数组新增一项。核心字段：

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | ✅ | 全局唯一 |
| `name` / `author` / `repo` / `description` | ✅ | 展示信息（`author` 用 GitHub 用户名） |
| `lattice` | — | `module` / `data-source` / `theme` / `skin` / `agent` |
| `dimensions` | — | `data` / `agent` / `ui` 等 |
| `install` | — | 下载办法（§8.1）；随包分发可省略 |
| `manifest` | — | manifest 获取办法（§8.2） |

### 8.1 `install`（下载办法）

| 字段 | 说明 |
|------|------|
| `type` | 固定 `github` |
| `url` | 仓库 URL |
| `strategy` | `source`（默认，clone 源码）/ `release`（下载二进制 asset） |
| `assetPattern` | `release` 下筛 asset：空格=AND、`!`=排除词、`{platform}`/`{arch}` 占位符 |
| `platforms` | `release` 下平台白名单（**双平台铁律：至少含 `windows` 与 Android 对应值**） |

```json
"install": { "type": "github", "url": "https://github.com/cxz66666/zju-ical", "strategy": "release", "platforms": ["windows", "linux", "macos"], "assetPattern": "zjuical {platform}_{arch}!srv" }
```

### 8.2 `manifest`（manifest 获取办法）

| source | 场景 | 示例 |
|--------|------|------|
| `inline` | manifest 稳定、无额外资源 | `"manifest": { "source": "inline", "json": { "type": "module", "id": "x", "name": "X" } }` |
| `local` | 指向 `docs/plugin-registry/` 下静态资源目录 | `"manifest": { "source": "local", "path": "assets/zju_xxx" }` |
| `github` | 指向 GitHub 仓库内资源目录 | `"manifest": { "source": "github", "repo": "owner/repo", "path": "plugins/zju_autosign" }`（需 `install.strategy:"source"`） |

---

## 9. 交付（上架清单 + 双平台验证清单）

### 9.1 上架清单（逐项核对）

- [ ] 在 `plugins.json` 的 `plugins` 数组里新增一个条目，填 `id`/`name`/`author`/`repo`/`description`
- [ ] 声明 `install`（需要网络下载时；随包分发省略）+ `manifest`（inline / local / github）
- [ ] 外部仓库是「库」形态时提供适配壳（符合 data-source CLI 契约）
- [ ] theme：`theme/theme.json` 含 `type` + 8 个语义色
- [ ] module：`module/manifest.json` 含 `type`/`id`/`name`；HTML 插件 `"template":"html"`
- [ ] data-source：`data/manifest.json` + 适配壳 + （如需）`config/config.json`；`script` 与 `process` 二选一
- [ ] agent：`agent/manifest.json`（`name`/`description`/`schema` 必填，`runtime:"python"`）+ `tool.py`
- [ ] skin：`skin/manifest.json`（`type:"skin"` + DIY 段）+ 引用的 SVG/图片资源
- [ ] 凭证：适配壳走 `_get_config` 三级降级，不硬编码；优先复用内置 key（如 `ZJU_USERNAME`）
- [ ] 新增设置项：在 `config/config.json` 声明 `settings[]`（key 全局唯一 + 前缀）
- [ ] Python 依赖：仅标准库 / 纯 Python 轻量包；确需第三方时 manifest 顶层声明 `requirements`
- [ ] module 进程：`process[]` 声明正确（`scope:long` / `scope:short`、`runtime`、`protocol`）
- [ ] 常驻进程：首行输出 `PORT:<N>`（`protocol:"http"` 时）且提供 `GET /health`

### 9.2 双平台验证清单（铁律验收）

- [ ] **Android**：插件能安装、能加载、核心路径能跑通（Python 走 Chaquopy，无第三方原生依赖）
- [ ] **Windows**：插件能安装、能加载、核心路径能跑通（Python 走平台 env）
- [ ] 无 `.exe` / 外部二进制依赖（agent 新产出统一 `.py`）
- [ ] 无 `open()` 直接写任意路径（产物内存打包或走平台通道）
- [ ] 无 `C:\` / `/tmp` 等硬编码路径；无 GBK 等非 UTF-8 编码假设
- [ ] UI 形态（若有）为 HTML module，双平台渲染一致
- [ ] 常驻进程在两平台都能启动、health 通过、可被终止

---

## 红线（禁止事项）

**双平台铁律相关：**
- ❌ 产出 `.exe` / 外部二进制 agent 工具（Android 无法执行）。
- ❌ agent/data-source 脚本依赖 `python-pptx` / `numpy` / `selenium` 等 Android 不可用包——用标准库组合替代。
- ❌ 脚本直接 `open()` 写任意路径 / 硬编码 `C:\`、`/tmp`——内存打包 + 平台通道。
- ❌ 只验证了单平台就交付。

**原 skill 继承红线（保持有效）：**
- ❌ registry 条目 / 适配壳硬编码敏感信息（凭证/密钥/token）。
- ❌ 适配壳 stdout 混入非 JSON（日志走 stderr）。
- ❌ module manifest 缺 `type`/`id`/`name`；重复 `id`。
- ❌ 需要网络下载的插件漏写 `install`；随包分发插件却写 `install.type:github` 指向本仓库（误触发整仓 clone）。
- ❌ 新增 key 但不在 `config.json` 声明；`default` 用 JSON bool 而非字符串。
- ❌ 常驻进程 `protocol:"http"` 不输出 `PORT:<N>` 首行 / 无 `GET /health`。
- ❌ agent manifest 缺 `name`/`description`/`schema`；声明 `runtime:"python"` 却只给 `.exe`。
- ❌ skin manifest `type` 不是 `"skin"`。
- ❌ **B 阶段不通过仍强行改造**——工作流纪律：舍弃换下一个。

---

## 参考实现索引（复用 `../skill/examples/`）

| 目录 | 形态 | 关键文件 | 可复用于 |
|------|------|---------|---------|
| `../skill/examples/example-theme-warm_study/` | theme | `theme/theme.json` | D1 主题 |
| `../skill/examples/example-html-view/` | module（HTML） | `module/manifest.json` + `index.html` | D4 小模块 |
| `../skill/examples/example-data-zju_grades/` | data-source | `data/manifest.json` + `scraper.py` + `config/config.json` | A→C zju 爬虫改造 |
| `../skill/examples/example-data-video_stream/` | data-source（auth + stream） | `data/manifest.json` + `fetch.py` + `config/config.json` | D5 实时数据源 |
| `../skill/examples/example-agent-current_time/` | agent | `agent/manifest.json` + `tool.py` | D3 小工具 |
| `../skill/examples/example-skin-evergreen-logo/` | skin | `skin/manifest.json` + `*.svg` | D1 皮肤 |

> 创作时优先复制对应 `examples/` 目录为模板，替换 `id`/`name` 与业务逻辑，避免从零拼字段。
> 本技能与 `../skill/SKILL.md` 的关系：**超集**。原技能的五类契约、registry、红线全部继承（上表章节）；本技能新增「工作流闭环、双平台铁律、能力边界与组合效应、创意方向库」。字段级权威仍是原技能 + 源码。
