# Evergreen 通用插件化工程规划（探索汇总 v1）

> 状态：**✅ 全部 10 个实现任务已完成（2026-08-25）**，三大主题 + 高优优化点均已落地；遗留项与 backlog 见 §7/§5
> 发起：root 总工程师（队长） · 参与：evergreen-owners-v2 团队 8 名 OWNER 成员
> 依据：8 份只读探索报告（t1-t8，均写入团队任务 output，未改任何代码）
> 本文档是同步中心与插件工程化的总规划/实施依据；实现结果已回写（t9-t18）。

---

## 0. 目标总览（用户三大诉求 + 强制约束）

1. **主题 1 · Agent 工具 exe → 统一 Python 唯一路径**：替换 agent tool 插件的 `.exe` 优先执行方式，统一为唯一 python 解释器路径，且**最好只用标准库**（减少平台二进制依赖、提升跨平台一致性）。
2. **主题 2 · 安卓 HTML 插件导出路径修复**：排查并修复安卓版 HTML 插件「导出后找不到」，确保 HTML 插件导出路径与**主题插件导出路径一致**。
3. **主题 3 · 远程同步中心（.egsync）**：支持把所有配置、AI 助手对话历史、断点、插件等资源导出为 `.zip` 并跨平台加载；**同步选项由用户自行选择**。合并语义：AI 助手全局记忆同步时**直接拼接**；对话历史**若某会话历史完全包含于另一会话历史则删除小的，若存在路径分化则两个都保留**。
4. **强制约束 · 文档同步**：组员任何变更完成之后必须更新对应的文档文件（CLAUDE.md / README.md / docs/*.md / AGENT.md）。

---

## 1. 主题 1：Agent 工具 exe → 统一 Python 唯一路径

### 1.1 探索结论（t1 core-agent / t2 core / t6 core-data / t8 plugins 交叉验证）

**执行链（4 层）**：
`PluginBridge._findEntry`（`lib/core/agent/tools/plugin_bridge.dart:265`，**`.exe` 优先于 `.py`**）→ `PluginTool` → `PluginRunner`（`plugin_runner.dart`：SubprocessRunner 桌面 / ChaquopyRunner 安卓，`runtime` 字段已支持）→ 三个注册点。

**现状评估**：
- ✅ 统一执行层（PluginRunner 抽象 + `runtime:"python"` 字段 + .py 契约）**P0-P3 已全部落地**（见 `.history_docs/统一py插件-安卓适配规划.md`）
- ✅ Agent 域 8 个 .exe（`date/time/weather/random` + `mesh_discover/agent_bridge/mesh_server/plugin`）**全部可用纯 Python 标准库替换**（random 为 C 源码，需补写 plugin.py）
- ✅ 全仓生产二进制仅 2 个：`settings.exe`、`agent_bridge.exe`（均带 .py 源可移除）
- ⚠️ OCR/翻译/论文脚本的第三方依赖（pytesseract/Pillow/pdf2zh/pymupdf）属**服务层**，与 agent 工具无关，不在本次替换范围
- ⚠️ agent 工具 manifest **无** process 白名单（那是 HTML 插件 `platform.process.*` 与模块/数据源的 fail-closed 机制）；agent 域安全网是 Gate + readOnly + StormBreaker

**核心缺口（实施点）**：
1. `_findEntry` 仍 `.exe` 优先于 `.py`（`plugin_bridge.dart:265`）
2. Python 解释器解析：`resolvePythonExe()`（`core/utils/python_env.dart`）是唯一公共 API，但存在 **5+ 处重复探测**（agent_runtime/agent_factory/skill_creator/pdf_translate/paper_reading 各自 `?? 'python'` 兜底）+
   **双真理来源**（cwd 路径 vs `greenix_path` 的 greenixPythonDir）+ 安卓返回 **哨兵字符串 `'chaquopy'`** 风险
3. 三处 python 解析入口不一致：`agent_runtime`/`agent_factory` 硬编码 bundledPython 无回退 vs `app_bootstrap` 多级回退 vs `sharedPluginRunner`
4. 存量 .exe 兼容策略需产品决策（保留 native 分支 vs 拒绝迁移）
5. douban 数据源是唯一 .exe 示例（模型 B，PyInstaller 产物）

### 1.2 实施要点

- **第一步（纯 core 域，独立推进）**：`PythonInterpreter.resolve()` 单例收敛 + `'chaquopy'` 哨兵改造 + 双真理源合并
- 去 `.exe` 优先：`_findEntry` 改为 `.py` 优先（或 runtime 字段决定）
- 8 个 .exe 提供纯标准库 .py 实现（含 random 补 plugin.py）
- douban 迁移模型 A(.py)，清理 25.71MB 构建产物
- settings 遗留 exe 形态清理；python-runner manifest 补 runtime 字段

---

## 2. 主题 2：安卓 HTML 插件导出路径修复

### 2.1 探索结论（t3 renderer / t4 platform / t8 plugins / t7 core-module 交叉验证，根因已确认）

**两条导出链路对比**：

| 维度 | HTML 插件（html-creator） | 主题插件（theme-creator） |
|---|---|---|
| 导出入口 | `HtmlExportService.export`（手动）+ `ExportHtmlPluginTool`（AI） | `ThemeExporter.export`（`theme_exporter.dart`） |
| 落盘路径 | `pluginsDirProvider`（失败回退**硬编码 `'plugins/'`**，安卓解析到只读 `/plugins/`） | `resolvePluginsRoot()`（平台正确） |
| 附加写入 | **双写** `assets/plugins_bundle/<id>/module/`（构建期直写） | 单目标（热注册 ThemeStore） |
| 发现机制 | 插件中心只列 `docs/plugin-registry/plugins.json` 注册表条目，本地导出插件不在其中 | 设置页下拉 |
| 错误处理 | 全部静默（仅 debugPrint） | — |

**根因（按可能性排序）**：
- **RC-1（架构性）**：路径解析链不一致 + 安卓回退路径损坏——html-creator 导出走 `pluginsDirProvider`（回退 `'plugins/'`），theme-creator 走 `resolvePluginsRoot()`；正常启动同值，脱离标准注入即静默落错地方/失败
- **RC-2（安卓特有·直接证据链）**：APK 内 `assets/plugins_bundle` 冻结副本 vs 运行期 `.greenix/plugins` 两套真相。实证：`assets/plugins_bundle/5/`（用户导出的"画布 5"）未注入 pubspec → APK 不打包 → **安卓"导出后找不到"**；`html-creator/{my-plugin,zdbk-transcript,zdbk-transcript-v2}` 在 pubspec 但源已删 → 每启动释放成 `.greenix/plugins/html-creator/<sub>` 僵尸死重（一层扫描扫不到）
- **RC-3（发现面）**：本地导出插件不在插件中心可见列表
- **RC-4**：导出/热注册错误全被吞

**不变式**：`assets/plugins_bundle/` = `plugins/` 纯镜像，**仅由 `tool/bundle_plugins.dart` 生成**；HtmlExportService 双写违反此不变式（bundle 污染根源）。

### 2.2 实施要点

1. HtmlExportService **单目标化**（与主题范式一致）：统一走 `resolvePluginsRoot()` + `p.join`/`path_sandbox` + **原子导出** + **id 校验** + 导出后 `registerInstalled`
2. 清陈旧 bundle 副本（`assets/plugins_bundle/5`、`my-plugin`、`zdbk-transcript*`、`data-scraper`）+ 重跑 `bundle_plugins.dart` 重写 pubspec
3. `bundle_plugins.dart` 加 **`--check` 门禁进 CI**（防本地构建漂移，CI 构建前重跑可自愈）
4. releaseBundledAssets 版本快照（防每启动覆盖用户改动）
5. 导出错误用户可见化

---

## 3. 主题 3：远程同步中心（.egsync）

### 3.1 探索结论（t5 core-config / t6 core-data / t7 core-module / t1 core-agent / t8 plugins / t2 core 汇总）

**配置**：
- 可导出：声明式设置 + 动态注册设置 + 权限（`perm.*`）+ 插件源 + 未声明应用偏好（active_theme_id 等）+ `.greenix` 下 sessions/workspaces/plugins/themes/skills/memories/env.json
- 不应导出：`.greenix/config.json` 镜像、web_cache、scripts/python 运行时资产、端口文件、日志、cookie（默认）、.config_backup
- 现有能力：`exportConfig/importConfig`（`.evgconfig` v1）已有但**仅测试/example 使用、无 UI 入口、无 zip 打包**
- **关键缺陷（O1）**：权限导出类型错误（`perm.*` 存 bool 却走 getString）；动态注册项 `_dynamicSettings` 私有无法导出；extra 无白名单过滤；无 version 校验；导入后不触发 greenix 同步；isSecure 明文

**记忆（AI 助手全局记忆）**：
- 存储：`.greenix/memories/*.md`（frontmatter + body + 自动索引）
- **"直接拼接"合并完全可行** ✅

**对话历史**：
- 存储：`.greenix/sessions/{id}.json`，**线性 List，无分支/checkpoint**
- **"包含则删小"仅启发式可行**（前缀比较）；建议先补 `parent_id + fork_turn` 元数据，再实现完整语义（路径分化都保留）

**插件**：
- 导出复用 `.plugin` 信封：根 manifest + `files:{relPath:sha256}` + `platforms` 字段（可选）
- 导入 fail-closed：type 校验 + ModuleDescriptor 可解析 + 越界整体拒绝 + 内容寻址完整性
- 版本感知冲突策略：同内容 no-op / 新版覆盖 / 备份 config
- 已安装目录结构：`plugins/<id>/`（module/、agent/、data/、theme/、config/、skill/、icon）；排除 `.manifest`/`.signature`（重新生成）、`.released_manifest.json`、`__pycache__/build/dist/node_modules/.dart_tool/*.spec/.git`、嵌套草稿
- 安装器：PluginInstaller（.plugin ZIP + `.signature` SHA-256 常数时间比对 + zip-slip 防护），无覆盖路径（已存在直接拒绝）→ 同步导入需补冲突策略

**数据源**：
- zip 结构 `data-source/<pluginId>/{data/,config/}`；导入 = 落 pluginsRoot + `registerDataSourcesFromManifest`（模型 A，与 `POST /data/register` 同契约，无需新端点）/ DataSourceLoader（模型 B）
- Python 解释器路径运行时解析（resolvePythonExe），无需序列化
- **python 统一联动**：导出以模型 A(.py) 为规范化形态可跨平台（桌面 + 安卓 Chaquopy 同一份 .py）；模型 B .exe 需 platform 标记，仅同平台回放
- 契约缺口：无 per-数据源 dependencies 声明（跨机导入缺依赖）

### 3.2 设计草案（.egsync.zip）

> 📄 **契约层已落地**：完整规格见 [`docs/superpowers/specs/egsync-sync-center-spec-v1.md`](superpowers/specs/egsync-sync-center-spec-v1.md)（2026-08-25，core-config 产出，含包结构/manifest 契约/config v2/同步选项模型/路径规则/会话元数据/合并语义/安全模型）。下表为规格摘要。

```
.egsync.zip
├── manifest.json          # {type:"egsync", version, exportedAt, platform, resources:[...], options:{...}}
├── config/
│   └── config.evgconfig   # v2 格式（= v1 + dynamicSettings/permissions/appPrefs 可选段，向后兼容）
├── sessions/              # 对话历史（合并后）
├── memories/              # 全局记忆（直接拼接后）
├── plugins/<pluginId>/    # 插件（.plugin 信封布局，含能力子目录）
├── data/<pluginId>/       # 数据源（data/ + config/）
└── themes/<pluginId>/     # 主题
```

- **同步选项**：资源类型（配置/对话历史/记忆/插件/数据源/主题）× 插件分组 **双维勾选**，用户自选
- **版本兼容**：导出格式 version 字段；v2 可选段向后兼容 v1；导入旧版本降级处理
- **跨平台**：路径全部走 `resolvePluginsRoot()` / greenix_path 相对化，不序列化绝对路径

### 3.3 合并语义（用户指定）

| 资源 | 合并策略 |
|---|---|
| 全局记忆 | **直接拼接**（frontmatter+body 追加，自动索引重建） |
| 对话历史 | 会话 A 完全包含于 B（前缀比较）→ 删 A 保留 B；路径分化（fork）→ 两个都保留（需先补 `parent_id + fork_turn` 元数据） |
| 配置 | 按 key 合并，冲突以用户选择为准（覆盖/保留/备份） |
| 插件/数据源/主题 | 版本感知冲突策略（同内容 no-op / 新版覆盖 / 备份 config） |

---

## 4. 顺带发现的优化点汇总（探索期间收集，按优先级）

| # | 优化点 | 发现者 | 优先级 |
|---|--------|--------|--------|
| O1 | 权限导出类型缺陷（bool 走 getString）+ 动态项枚举 + extra 白名单 | core-config | 🔴 高（同步中心前置） |
| O2 | HtmlExportService 双写致用户画布泄漏进 APK bundle | plugins/platform | 🔴 高（主题2前置） |
| O3 | releaseBundledAssets 每启动覆盖 plugins/<id>，覆盖用户改动 | core-module/platform | 🔴 高 |
| O4 | `bundle_plugins.dart --check` CI 门禁（防本地构建漂移） | platform | 🔴 高 |
| O5 | 插件 id 校验过松（纯数字 "5" 通过） | plugins | 🟡 中 |
| O6 | douban 25.71MB 构建产物清理 + README cp 目录错位 + exePath 命名过时 | core-data | 🟡 中 |
| O7 | PluginExporter.exportAsZip 无排除清单且 shell 出 PowerShell | core-module | 🟡 中 |
| O8 | verifyAll 误判创作中心直导插件损坏 | core-module | 🟡 中 |
| O9 | `.module_port` 相对路径与 app_bootstrap 契约不一致 | core-module | 🟡 中 |
| O10 | `_extractTo` 越界静默跳过（应报错） | core-module | 🟡 中 |
| O11 | 导出/热注册错误全被吞（仅 debugPrint）→ 需用户可见错误 | renderer | 🟡 中 |
| O12 | python-runner manifest 缺 runtime 字段且无入口文件 | plugins | 🟡 中 |
| O13 | 无 per-数据源 dependencies 声明（跨机导入缺依赖，契约缺口） | core-data | 🟢 低 |
| O14 | 桌面 release 冗余释放、release 版本戳、ABI 裁剪、路由净化 | platform | 🟢 低 |

---

## 5. 实施阶段与任务分派

**阶段 0（契约登记，队长 root）**：登记跨 OWNER 契约变更（HtmlExportService 单目标化、.egsync 新契约）→ 更新 AGENT.md 契约表

**阶段 1 · 主题 1（python 统一）**
- ✅ t-A1 core：`PythonInterpreter.resolve()` 单例收敛 + `PythonRuntime`/`kChaquopySentinel` 哨兵常量 + `bindGreenixPythonDir()` 双真理源合并；收敛 13 文件（ocr_pipeline/pdf_translate/plugin_runner/app_bootstrap/agent_runtime/agent_factory/paper_reading/skill_creator/translate_slot + agent/data 子包副本）；core 101 + data 70 + agent 235 用例全绿 ✅ 2026-08-25
- ✅ t-A2 core-agent：`_findEntry` 去 .exe 优先（同名 `<目录名>.py` 最高优先 → 其余 .py → 仅无 .py 且未声明 runtime:"python" 才回退 .exe legacy；runtime 声明错配跳过）+ 8 个 .py 纯标准库实现（random 补写 plugin.py，mesh 系列 stdlib-only）+ 删除 8 个 PyInstaller .exe + 4 个 .spec + __pycache__ + 8 manifest runtime:"python"；smoke 实测跑通；agent 255 用例全过 ✅ 2026-08-25 —— 遗留：存量 .exe 最终拒绝与否待产品决策（代码保留 legacy 回退）
- ✅ t-A3 core-data：douban 迁移模型 A（`data/plugin.py` urllib 纯标准库 + manifest script/runtime:"python"，删 process/endpoint）+ PyInstaller 产物清理（25.71MB → 7.08KB）+ exePath→scriptPath 命名修正（register_data_source 6 处）；本机实跑 25 条真实豆瓣数据 exit 0 ✅ 2026-08-25
- ✅ t-A4 plugins：settings 遗留 exe 清理（settings.py/.spec/.exe 死代码 git rm，module+config 保留）+ python-runner manifest 补 `runtime:"python"`+`implementation:"builtin-dart"` + 重跑 bundle 移除两条资产 + 全仓 plugins 域 .exe 残留=0（主题 1 达成）✅ 2026-08-25 —— 遗留：存量 .exe 最终拒绝策略待产品决策（代码保留 legacy 回退）；SKILL.md 少量 legacy .exe 示例不阻塞

**阶段 2 · 主题 2（安卓导出路径）**
- ✅ t-B1 renderer：HtmlExportService 单目标化（resolvePluginsRoot + path_sandbox + 原子导出 + id 校验 + registerInstalled + 错误可见化；O2/O5/O11 一并处理，31/31 测试通过）✅ 2026-08-25
- ✅ t-B2 platform：清陈旧 bundle 副本（assets/plugins_bundle 重建后仅 15 真实内置镜像）+ bundle_plugins.dart --check 门禁（pubspec 提交态 + 文件清单 + 逐字节比对）+ release.yml 构建前门禁（O4；负向测试验证门禁有效）✅ 2026-08-25
- ✅ t-B3 错误可见化（O11）：已并入 t-B1 实现（Log + SnackBar），无需单列

**阶段 3 · 主题 3（同步中心）**
- ✅ t-C1 core-config（牵头）：.egsync.zip 规范（`docs/superpowers/specs/egsync-sync-center-spec-v1.md`）+ config v2（O1 六缺陷全修，77+23 用例通过）+ 会话 parent_id/fork_turn 元数据契约定义 ✅ 2026-08-25
- ✅ t-C2 core-config：导出端 pack_sync（`core/config/sync_export_service.dart`，.egsync.zip 打包 + 双维勾选过滤，4 冒烟用例 + 81 用例通过；规格 v1.1 §十一）✅ 2026-08-25 —— 遗留：勾选 UI（renderer 域）待协调
- ✅ t-C3 core-module：导入端 sync_import（`core/services/sync_import_service.dart` SyncImportService：包级 fail-closed 校验（type/version/zip-slip 整体拒绝）+ 资源级校验（插件 manifest 可解析/.plugin 信封 files 哈希与签名/数据源/主题）+ 版本感知冲突策略（同内容 no-op/新版覆盖备份 config/冲突清单 SyncConflict）+ 注册回放（插件 reloadModule/数据源模型 A registerDataSourcesFromManifest + **模型 B DataSourceLoader best-effort 回放**（失败降级不阻断包，覆盖安卓无法 exec 桌面 PE）/主题 ThemeStore.register；sessions/memories 原样落盘交 t-C4 产物；config 交 core-config configImporter）；冒烟 `evg-base/test/sync_import_smoke_test.dart` 8 用例通过；规格 v1.3 §十二）✅ 2026-08-25 —— 遗留：勾选/导入 UI 属 renderer 域待协调；data manifest 无 version（冲突退化为指纹比较，后续补 version 戳）
- ✅ t-C4 core-agent：记忆直接拼接 + 会话合并（`session_merge.dart` mergeSessions 包含删小/分化都保留 + `memory/memory_merge.dart` mergeMemories 直接拼接 + `Session.parentId/forkTurn` 模型落地 + `forkSessionProvider` 写入；agent 子包 251 用例通过，含新增 16 合并用例；规格 v1.2 §七/§十）✅ 2026-08-25 —— t-C3 可调用 mergeSessions/mergeMemoriesIntoStore

**阶段 4 · 文档更新（强制约束）**：每个任务完成后必须更新对应 CLAUDE.md/README.md/docs/AGENT.md（各成员已提交文档清单，见各任务 output）

**可选 backlog**：O7-O10、O13-O14（视资源安排）

---

## 6. 文档更新清单（各成员探索产出）

- **core**：core/CLAUDE.md、core/README.md、services/README.md、utils/README.md、services/AGENT.md、utils/AGENT.md
- **core-agent**：agent/CLAUDE.md、agent/README.md、docs/api-contracts.md、docs/agent-http-api.md、docs/plugin-agent-tool.md、docs/plugin-authoring-guide-agent.md
- **core-config**：config/CLAUDE.md、config/README.md、docs/plugin-config.md、theme/CLAUDE.md、theme/README.md、core/CLAUDE.md、utils/README.md
- **core-data**：data/CLAUDE.md、data/README.md、docs/plugin-data-source.md、docs/plugin-authoring-guide-data.md、douban/README.md
- **core-module**：module/CLAUDE.md、module/README.md、docs/plugin-module.md、core/docs/plugin-format.md、services/README.md
- **renderer**：renderer/CLAUDE.md、renderer/README.md、lib/README.md、lib/AGENT.md、templates/AGENT.md、renderer/AGENT.md
- **platform**：scripts/README.md、scripts/AGENT.md、evg-base/README.md、platform AGENT.md
- **plugins**：plugins/README.md、docs/plugin-architecture.md、plugin-registry-spec-v1.md（补导出格式节）、core/docs/plugin-format.md（agent/ 补 .py 形态）、docs/plugin-agent-tool.md、SKILL.md、theme/docs/plugin-theme.md
- **root**：根 README.md、根 CLAUDE.md、根 AGENT.md（契约表）、docs/plugin-architecture.html、本文档（回写结果）

---

## 7. 风险与待决策项

1. **存量 .exe 兼容策略**：保留 native 分支 vs 拒绝迁移（需产品决策）
2. **会话合并语义**："完全包含"的判定标准（前缀 vs 全量逐事件）——契约已定义 parent_id/fork_turn（规格 §七），判定标准由 t-C4 落地时按契约实现，启发式仅作兜底
3. **同步导入冲突**：同名插件/数据源/主题的覆盖策略需用户确认界面（t-C3 导入端返回冲突清单，UI 后续接入）
4. **安卓 pip 禁用**：第三方依赖在安卓不可安装 → 纯标准库是安卓同步的硬约束
5. **版本差**：桌面嵌入式 python 3.10.11 vs 安卓 Chaquopy Python 3.11，脚本需双版本兼容
6. ~~config v2 格式风险~~ ✅ 已随 t-C1 解决（v2 向后兼容 v1，version 校验 [1..2]）
