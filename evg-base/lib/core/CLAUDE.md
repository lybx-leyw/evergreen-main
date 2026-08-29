# Core 层 — 共享基础设施 + 服务层 + 工具层

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | AI 协作者（core 层） |

> **模块定位**：Evergreen 三层架构（`core/` → `plugins/` → `renderer/`）的上游基础设施层。
> **责任人**：Core 工程师
>
> **用户插件方向（当前事实）**：面向用户侧的插件创作已明确以 **HTML 为主**——用户自写 HTML/CSS/JS，
> 平台通过 `html-creator` 提供创作中心、实时预览、AI 辅助生成和一键导出。
> 导出的插件是 `plugins/<id>/module/index.html + manifest.json`（`"template":"html"`），
> 运行时由 `html_modle` 以 WebView 加载，并通过 `platform.*` JS Bridge 调用 core 服务。
> Dart/JSON 模块声明、`.exe` 数据源/Agent 工具仍是开发者模式/高级能力，不应作为用户创作的主要入口。

---

## 一、目录结构

```
lib/core/
├── errors.dart              # AppError 基类 + 种子类错误
├── log.dart                 # Log 单例（debug→stderr, release→文件轮转）
├── result.dart              # Result<T> sealed class（Ok / Err）
├── agent/                   # AI Agent 运行时 + 工具 + 记忆 + Skill + 守护
├── config/                  # 设置/权限/插件源 + ConfigHttpServer
├── data/                    # 数据谱仪器：DataType/Orchestrator/Cache + 数据源
├── module/                  # 模块描述符/注册表/加载器/进程管理
├── theme/                   # 主题描述符/Store/Loader + ThemeHttpServer
├── services/                # 平台级基础服务
│   ├── services.dart        #   barrel 导出（纯 Dart 服务）
│   ├── core_http_server.dart #   微服务网格（REST 端点）
│   ├── plugin_installer.dart #   插件生命周期管理
│   ├── update_service.dart  #   应用更新检查
│   ├── github_stars.dart    #   GitHub star 数据中枢接入（DataType）
│   ├── github_clone.dart    #   GitHub 源克隆（git clone 子进程）
│   ├── github_metadata.dart #   GitHub 仓库元数据抓取
│   ├── release_downloader.dart # GitHub release 二进制下载
│   ├── data_file_service.dart  #   文件下载服务（headers/超时/重试/沙箱，T8a）
│   └── ui_operation_log.dart #   UI 操作日志（UIOperationLog）
├── utils/                   # 通用工具
│   ├── safe_parse.dart      #   安全类型转换
│   ├── token_estimator.dart #   Token 估算
│   ├── python_env.dart      #   Python 环境：统一解释器路径发现（PythonInterpreter 单例）+ 依赖安装
│   ├── greenix_path.dart    #   运行时路径管理（路径唯一真理来源）
│   ├── path_sandbox.dart    #   路径沙箱
│   ├── file_utils.dart      #   文件管理器
│   └── plugin_asset_releaser.dart # 插件/脚本资产释放（幂等）
├── plugin/                  # 插件运行器（plugin_runner.dart：runOnce(可选 timeout，超时 kill 子进程)/startLong；python_session.dart：PythonSession 常驻 stdio JSON Lines 会话，T5）
├── feedback/                # 用户反馈（feedback_bar/feedback_dialog/feedback_writer/github_issue_publisher/screenshot）
├── example/                 # 跨模块联动示例
│   ├── example.dart         #   交互式菜单
│   └── plugins/             #   示例插件（mesh_demo / ocean_theme / super_app）
├── core_text_app.dart       # 文本版 Core 自证应用（命令行交互验证）
├── test/                    # 测试
│   ├── installer_test.dart  #   插件安装/卸载/校验/崩溃/沙箱
│   ├── path_sandbox_test.dart # 路径沙箱越界防护
│   ├── python_env_test.dart #   PythonInterpreter 统一解析/哨兵/双真理源合并
│   ├── signature_test.dart  #   签名计算 + 常数时间比较
│   ├── update_service_test.dart # 更新检查降级
│   └── widget_test.dart     #   errors / result 模块验证
├── lib/                     # Stub 隔离层（独立 Dart package）
│   ├── archive_stub/        #   archive 包 stub（ZipDecoder / Archive）
│   ├── crypto_stub/         #   crypto 包 stub（Sha256 / Digest）
│   ├── dio_stub/            #   dio 包 stub（Dio / Response / Options）
│   └── core/                #   stub 配套（log.dart 独立版，仅 stderr）
├── docs/
│   ├── plugin-format.md     #   .plugin 包格式规范
│   └── plugin-authoring-guide-core-services.md # 插件打包与分发指南
├── pubspec.yaml             # 依赖声明（stub 指向 lib/）
├── README.md                # 模块总览
└── CLAUDE.md                # 本文件
```

> 注：论文/翻译等 Python 脚本本体位于 `evg-base/scripts/`（platform OWNER 管辖），
> 运行期由资产释放填充到 `.greenix/scripts`（`greenixScriptsDir`）。
> `lib/core/CLAUDE.md` 不直接涉及这些脚本的维护。（OCR 管线已移除，见 R3-4。）

---

## 二、核心设计决策

### 2.1 AppError 体系（分层错误码）

```dart
AppError                    // 抽象基类（userMessage + debugMessage + recoveryHint + source）
├── NetworkError            // 网络不可达 / HTTP 状态异常
├── AuthError               // 登录失败 / 会话过期
├── ParseError              // HTML/JSON/iCal/YAML 语法层解析失败
├── DataIntegrityError      // 数据解析成功但结构/类型不符合预期（语义层）
├── CacheError              // 缓存读写失败
├── TimeoutError            // 请求超时
├── ValidationError         // 用户输入不合法
├── MediaError              // 媒体播放失败（视频/音频/PPT）
├── AiModelError            // AI 模型 API 调用失败（限流/认证/不可用）
├── ContextExceededError    // AI 上下文超出窗口限制
├── ConfigError             // 配置缺失或无效
├── FileError               // 文件读写失败（磁盘满/权限/格式）
├── RenderError             // Widget 渲染失败
└── UnknownError            // 未分类错误（兜底）
```

**设计理由**：
- 每个错误同时携带 `userMessage`（中文，可直接展示 UI）和 `debugMessage`（英文，技术细节），避免 UI 层再做错误消息翻译。
- `source` 通过 `StackTrace.current` 自动捕获调用位置，无需手动传参。
- `recoveryHint` 可动态设置，UI 层可据此展示操作建议。

**如何新增 AppError 子类**：
1. 在 `errors.dart` 中创建子类，实现所有抽象 getter
2. 提供语义化 `factory` 构造函数
3. 在 `AppError` 基类添加对应的 `factory` 快捷方法

### 2.2 Result\<T\> 使用约定

```dart
sealed class Result<T> {
  // Ok(T value)  — 成功携带值
  // Err(AppError) — 失败携带错误
}
```

**设计理由**：
- 使用 Dart 3 `sealed class`，编译器穷尽检查 `Ok` / `Err` 分支。
- **强制约定**：所有 Service 公开方法返回 `Result<T>`，禁止 `throw`。
- 提供 `fromThrowable` 适配器用于渐进迁移旧代码。
- 链式调用：`.map()` / `.flatMap()` / `.fold()` 避免嵌套 if-else。

### 2.3 Log 双模式

- **Debug 模式**：输出到 `stderr`（同步，不丢日志）
- **Release 模式**：写入文件（`AppData/Local/evergreen/logs/`），单文件最大 5MB，保留最近 5 个文件
- **内存缓冲**：保留最近 500 条日志，`exportRecent()` 用于用户反馈附到 GitHub Issue
- **模块标签**：自动从调用栈提取类名作为日志标签

### 2.4 OCR 已移除（R3-4）

OCR 路径（`OcrPipeline` / `DeepSeekOcrService` / 内置 `ocr_file` 工具 / OCR 脚本 /
`/core/ocr` 端点 / `DEEPSEEK_OCR_API_KEY` 设置项 / `plugins/ocr` 示例插件）已于 R3-4
整体砍除——本地 OCR（tesseract/poppler）在安卓无可行打包路径，云端 OCR 由未来
API-OCR 插件工具承接（另行规划）。`python_env.dart` 保留 `pipInstallPackages` 与
解释器解析（`resolve` / `bundledPathSync`），移除 `runOcrProcess` 与 `PythonEnv` 类。

### 2.5 PluginInstaller 安全模型

```
URL → download（3 次重试: 1s/3s/5s）→ ZIP 解压 → manifest.json 校验
  → SHA-256 签名比对（常数时间比较）→ ZIP slip 防护
  → plugins/<id>/ 落盘 → .manifest + .signature 元数据 → onInstall 回调
```

- **签名校验**：SHA-256 hex（64 字符小写），签名内容为 `manifest.json` 原始字节
- **崩溃监控**：10 分钟窗口内 ≥ 3 次崩溃 → `isUnstable = true`
- **沙箱隔离**：`isWithinPluginDir()` 防止插件 A 读取插件 B 目录
- **配置回退**：`_withRollback()` 操作前备份 config/，失败自动恢复（S3 预留）

### 2.6 CoreHttpServer 微服务网格

REST 端点（见下表），绑定 `127.0.0.1` 随机端口。端口发现文件由启动器（`app_bootstrap.dart`）统一
写入 projectRoot 下的 `.core_port`，供插件 `.exe` / HTML 插件 bridge 发现（server 自身不再写端口文件）：

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/core/health` | 健康检查 |
| POST | `/core/install` | 安装插件 |
| POST | `/core/uninstall/:id` | 卸载插件 |
| GET | `/core/plugins` | 列出已安装插件 |
| GET | `/core/update/check/:id` | 检查单个插件更新 |
| GET | `/core/update/check` | 检查宿主更新 |

> 端口文件契约：`.agent_port` / `.config_port` / `.data_port` / `.module_port` /
> `.theme_port` / `.core_port` 均由 `app_bootstrap.dart` 的 `_stepServersStart()` 统一写入
> projectRoot（`ModuleHttpServer` 仍自写 `.module_port`，见其源码注释）。

---

## 三、开发约定

### 3.1 新增 Service

1. 在 `services/` 下创建新文件
2. 若为纯 Dart 服务（无 Flutter 依赖），在 `services/services.dart` 中添加 `export` 语句；含 Flutter 依赖的服务（如 `release_downloader.dart`）保持直接 import，不进 barrel
3. 公开方法返回 `Result<T>`（不抛异常）
4. 使用 `Log()` 记录关键操作
5. 在 `test/` 下添加对应测试

### 3.2 新增 Util

1. 在 `utils/` 下创建新文件
2. 纯函数优先，避免引入 Flutter 依赖
3. 更新 `utils/README.md` 添加文档
4. 所有 JSON 解析使用 `SafeParse` 统一入口

### 3.3 依赖管理

- 所有外部包通过 `lib/<name>_stub/` 隔离，`pubspec.yaml` 指向 stub 路径
- `dependency_overrides` 指定实际版本号
- 新增外部依赖时同步创建对应的 stub 包（`pubspec.yaml` + `lib/<name>.dart`）

### 3.4 测试策略

| 测试文件 | 覆盖范围 |
|----------|---------|
| `installer_test.dart` | 安装/卸载/签名/校验/崩溃/沙箱/版本比较 |
| `path_sandbox_test.dart` | 路径沙箱越界防护（`../../../` 等绕过） |
| `python_env_test.dart` | PythonInterpreter 统一解析（configuredPath/greenix 绑定/缓存）、哨兵常量、bundledPathSync |
| `signature_test.dart` | SHA-256 计算/常数时间比较/签名场景 |
| `update_service_test.dart` | 网络错误降级/自定义 repo |
| `data_file_service_test.dart` | DataFileService：成功/404 不重试/5xx 重试/超时/headers 透传/沙箱越界拒绝/批量（本地临时 HttpServer） |
| `widget_test.dart` | AppError 工厂方法/Result\<T\> 完整 API |

运行：`dart test`（在 `lib/core/` 目录下）

---

## 四、Stub 隔离说明

Core 层是纯 Dart 层，不依赖 Flutter Widget。所有外部包依赖通过 stub 隔离：

| Stub | 路径 | 提供 |
|------|------|------|
| `archive` | `lib/archive_stub/` | `ZipDecoder`, `Archive`, `ArchiveFile` |
| `crypto` | `lib/crypto_stub/` | `Sha256`, `Digest` |
| `dio` | `lib/dio_stub/` | `Dio`, `Response`, `Options`, `DioException` |

Stub 模式：
- 每个 stub 是一个独立的 Dart package（`pubspec.yaml` + `lib/<name>.dart`）
- Stub 提供编译所需的最小类型定义
- 真实环境通过 `dependency_overrides` 替换为实际包

---

## 五、跨模块接口契约

### 5.1 CoreHttpServer 端点签名

```dart
CoreHttpServer(PluginInstaller installer, UpdateService updateService, {int port = 0})
  .start() → Future<int>          // 启动，返回端口号
  .stop()  → Future<void>         // 关闭
  .isRunning → bool               // 运行状态
  .port → int                     // 实际端口（未启动=0）
```

### 5.2 服务间调用约定

- `PluginInstaller.install()` → `Result<InstallResult>`
- `PluginInstaller.uninstall()` → `Result<void>`
- `UpdateService.checkForUpdate()` → `Future<(bool, String?, String?)>`

---

## 六、子模块文档引用

| 模块 | 文档 | 负责人 |
|------|------|--------|
| `agent/` | `agent/README.md` | Agent 工程师 |
| `config/` | `config/README.md` | Config 工程师 |
| `data/` | `data/README.md` | Data 工程师 |
| `module/` | `module/README.md` | Module 工程师 |
| `theme/` | `theme/README.md` | Theme 工程师 |
| `services/` | `services/README.md` | Core 工程师（core-services） |
| `utils/` + `plugin/` + `feedback/` | `utils/README.md` | Core 工程师（core-infra） |

---

## 七、版本历史

| 日期 | 变更 |
|------|------|
| 2026-08-29 | **T5-storage HTML 插件模块存储器（core 服务层 + data 域）**：新增 `services/module_storage_service.dart`（`ModuleStorageService.forPlugin(pluginId, {pluginsRoot?})`：插件级 JSON 键值存储，落盘 `{resolvePluginsRoot()}/{pluginId}/storage/storage.json`（顶层 Map，值 JSON 可序列化）；同步 `readSync`（内存优先，首次读盘全量）供 localStorage polyfill，异步 write-through `write`/`remove`/`clear`（单 isolate Future 链串行对齐 Cache 互斥队列 + 临时文件 rename 原子写，`write(key, null)`=删 key、`clear` 删文件）；`readAll` 无待落盘写入时重新读盘（跨实例可见）；`pluginId` 校验 `moduleStoragePluginIdError` 对齐 renderer `htmlPluginIdError`（小写 kebab-case、拒绝路径穿越）+ `PathSandbox` confine 双保险；单文件 ≤1MB（`kModuleStorageMaxBytes`）超限拒绝；barrel `services.dart` 导出）。新增 `data/register_module_storage.dart`（`registerModuleStorageSource({orch, pluginId, pluginsRoot?, category?, ttl?})`/`unregisterModuleStorageSource`：把插件 storage.json 全量注册成数据中枢数据源 `name=<pluginId>_storage`、displayName `<pluginId> 存储`、缺省「未分类」、TTL 默认 30s、`persistentKey=null` 不二次缓存；fetcher 只读盘不触网、storage.json 缺失返回 `{}` 幂等（源可达）；barrel `data.dart` 导出）。数据子包独立测试经 `data/lib/core/` 本地副本（新增 `services/module_storage_service.dart`/`utils/greenix_path.dart`，`utils/path_sandbox.dart` 同步为根包版本）。测试：core 子包 +15（module_storage_service_test 14 组用例）、data 子包 +9（register_module_storage_test）；core 115 通过、data 217 通过（6 跳过为既有 python3 不可用） |
| 2026-08-25 | **T5 平台 Python 库 + 常驻会话（core/plugin 域）**：`SubprocessRunner` 对 Python 入口注入 `PYTHONPATH`（`greenixScriptsDir`，`bindGreenixScriptsDir` 由 app_bootstrap 绑定）、`ChaquopyRunner` 透传 `pythonPath`（Kotlin `sys.path.insert`）；`plugin_runner.dart` 三副本（core/agent/data）同步并对齐既有 ChaquopyLongProcess 漂移；新增 `plugin/python_session.dart`（`PythonSession`：stdio JSON Lines 双向会话 + 阶梯终止「退出命令→2s→SIGTERM→2s→SIGKILL」）；平台 Python 库 `scripts/evg_lib/{config,cas,jsonio}.py` 见 platform 域 |
| 2026-08-25 | **T4 降级链 + 进程守护（core 域）**：`PluginRunner.runOnce` 增可选 `timeout`（超时 kill 子进程 + 抛 `TimeoutException`，三副本同步）；`Cache` 写/删/清空路径互斥队列；`DataSourceLoader` 崩溃退避重启（1s/3s/9s×3）+ 手动 `restart()`（详见 data 域 CLAUDE.md） |
| 2026-08-25 | **T8a 文件下载服务（core 服务层）**：新增 `services/data_file_service.dart`（`DataFileService.downloadFile` / `downloadFiles`）：`dart:io` HttpClient 实现（零新依赖），支持自定义 headers（凭据头）、超时、退避重试（对齐 PluginInstaller「3 次重试 1s/3s/5s」，429/5xx 可重试、4xx fail-fast）、路径沙箱（`PathSandbox` 防目录穿越）；返回 core `Result<String>`；barrel `services.dart` 导出；新增 `test/data_file_service_test.dart`（本地临时 HttpServer：成功/404 不重试/5xx 重试/超时/headers 透传/沙箱拒绝越界/批量），core 子包 `dart test -j 1` 全量 110 通过 |
| 2026-08-25 | **t21 PDF 翻译撤销（core 服务层）**：删除 `services/pdf_translate_service.dart` + `services/translate_queue.dart`（用户决定撤销 PDF 翻译以减少内存；renderer t20 已删 translate_slot、plugins t19 已删 pdf_translate 插件）；barrel `services.dart` 本就未导出两者，无需变更；全仓 grep 无遗留引用（paper_reading `paper_service.dart` 仅注释提及，无 import）；pdf2zh_next/paper_reader.py 属 platform 域保留 |
| 2026-08-25 | **t9 统一 Python 解释器路径**：python_env.dart 新增 `PythonInterpreter.resolve()` 单例（解析顺序 configuredPath → greenix 目录 → PATH → 安卓 Chaquopy 枚举）、`PythonRuntime`/`PythonRuntimeKind` 结构化结果、`kChaquopySentinel` 哨兵常量、`bindGreenixPythonDir` 双真理源合并（app_bootstrap 绑定 greenixPythonDir）、`bundledPathSync` 同步探测；core 域调用点（ocr_pipeline/pdf_translate/plugin_runner/app_bootstrap）与跨域已知点（agent_runtime/agent_factory/skill_creator/paper_reading/translate_slot）迁移收敛；新增 python_env_test（14 用例） |
| 2026-08-25 | 文档同步：目录结构补全（services / utils / test 全量文件）、修正端口文件契约（app_bootstrap 统一写）、OCR 脚本名与 Key 环境变量、barrel 导出范围说明；按文档修订三原则去除硬编码数量与版本号 |
| 2026-08-21 | 对齐 HTML-first 插件创作：补充用户侧 HTML 插件路径、更新目录结构与平台 bridge 说明 |
| 2026-07-06 | 初始版本：创建 CLAUDE.md，修复 dio stub 路径，全量测试通过，README 审核同步 |
