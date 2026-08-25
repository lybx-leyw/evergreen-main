# 服务

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | services（OCR/更新/安装/同步中心） |

> 源码 `ocr_pipeline.dart` `deepseek_ocr_service.dart` `update_service.dart` `plugin_installer.dart` `core_http_server.dart` `github_stars.dart` `sync_import_service.dart`、测试 `../test/`
>
> **HTML-first 事实**：用户 HTML 插件通过 `platform.api.call("core", ...)` 访问 Core 服务；本目录的 OCR/更新/安装服务仍由平台内部与开发者模式插件使用。
>
> **barrel 说明**：`services.dart` 导出纯 Dart 服务（OCR/更新/安装/Core HTTP/GitHub stars/同步导入）；
> `github_clone.dart` / `github_metadata.dart` / `release_downloader.dart` / `ui_operation_log.dart`
> 含 Flutter 依赖或独立契约，按需直接 import 对应文件。

平台级基础服务——OCR 文字识别、应用更新、插件安装管理、HTTP API、GitHub 集成、同步中心导入。外部插件可直接调用。

---

## 〇、服务清单

| 服务 | 文件 | 说明 | 是否 barrel 导出 |
|------|------|------|-----------------|
| `OcrPipeline` | `ocr_pipeline.dart` | 两级降级 OCR + 并行 + 就绪诊断 | ✅ |
| `DeepSeekOcrService` | `deepseek_ocr_service.dart` | DeepSeek Vision API 封装 | ✅ |
| `UpdateService` | `update_service.dart` | 宿主/插件更新检查 | ✅ |
| `PluginInstaller` | `plugin_installer.dart` | 插件安装/卸载/校验/崩溃监控 | ✅ |
| `CoreHttpServer` | `core_http_server.dart` | REST 端点微服务网格 | ✅ |
| `GithubStarsFetcher` | `github_stars.dart` | star 数数据中枢接入（DataType） | ✅ |
| `SyncImportService` | `sync_import_service.dart` | .egsync.zip 导入：fail-closed 校验 + 版本感知冲突 + 注册回放（t-C3） | ✅ |
| `GithubCloner` | `github_clone.dart` | GitHub 源克隆（git clone 子进程） | 直接 import |
| `GithubMetadata` | `github_metadata.dart` | 仓库元数据抓取（市场卡片实时 star） | 直接 import |
| `ReleaseDownloader` | `release_downloader.dart` | GitHub release 二进制下载/解压 | 直接 import |
| `UIOperationLog` | `ui_operation_log.dart` | UI 操作日志（DebugErrorBar 实时显示） | 直接 import |

---

## 一、OCR 文字识别（I20）

两级降级管线：DeepSeek 云端 → Tesseract 本地。

```
  图片/文件输入
    └─ OcrPipeline.recognizeFile(path)
         ├─ Level 1: DeepSeek-OCR（云端，高精度）
         └─ 失败 → Level 2: Tesseract/Python（本地，离线可用）
```

```dart
import 'package:evergreen_base/core/services/services.dart';
import 'package:dio/dio.dart';

// 两级降级 OCR（推荐）
final pipeline = OcrPipeline(Dio());                 // apiKey 缺省回退环境变量 DEEPSEEK_OCR_API_KEY
final text = await pipeline.recognizeFile(path);     // → String?，失败返回 null
final text2 = await pipeline.recognizeUrl(url);      // → String，失败返回空字符串
final texts = await pipeline.recognizeFiles([p1, p2]); // → List<String?>，多文件并行
final report = await pipeline.checkReadiness();      // → OcrReadinessReport 环境诊断

// 仅云端 OCR
final svc = DeepSeekOcrService(Dio(), apiKey);
final text = await svc.recognize(File(path));     // → String?，失败返回 null
final result = await svc.testConnection();        // → Result<String>
```

### OcrPipeline

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `OcrPipeline(dio, [pythonEnv, apiKey])` | `dio: Dio`, `pythonEnv: PythonEnv?`, `apiKey: String?` | `OcrPipeline` | 构造；apiKey 缺省读 `DEEPSEEK_OCR_API_KEY` |
| `.recognizeFile(path)` | `path: String` 本地文件路径 | `Future<String?>` | 图片/PDF→文字，失败 null |
| `.recognizeFiles(paths)` | `paths: List<String>` | `Future<List<String?>>` | 多文件并行，单文件失败不影响其他 |
| `.recognizeUrl(url)` | `url: String` 图片 URL | `Future<String>` | 下载+OCR，失败返回空字符串 |
| `.checkReadiness()` | — | `Future<OcrReadinessReport>` | Python/脚本/Key/Tesseract 就绪诊断 |
| `pageConcurrency` | `int`（默认 4） | 属性 | PDF 逐页 OCR 并行度 |
| `parsePageOutput(stdout)` | `stdout: String` | `String?` | 解析子进程 JSON 输出（公开静态方法） |

### DeepSeekOcrService

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `DeepSeekOcrService(dio, apiKey)` | `dio: Dio`, `apiKey: String` | `DeepSeekOcrService` | 构造 |
| `.recognize(imageFile)` | `imageFile: File` 图片文件 | `Future<String?>` | OCR 识别，失败 null |
| `.testConnection()` | — | `Future<Result<String>>` | 用 1×1 PNG 测试 API 连通性 |
| `mimeFromPath(path)` | `path: String` | `String` | 扩展名→MIME（公开静态方法） |

---

## 二、应用更新（I19 宿主端）

```dart
import 'package:evergreen_base/core/services/services.dart';
import 'package:dio/dio.dart';

final updater = UpdateService(Dio(), repo: 'org/repo');
final (hasUpdate, version, url) = await updater.checkForUpdate();
if (hasUpdate) print('新版本: $version → $url');
```

### UpdateService

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `UpdateService(dio, {repo})` | `dio: Dio`, `repo: String` | `UpdateService` | 构造，默认 `evergreen-multi-tools/...` |
| `.checkForUpdate()` | — | `Future<(bool, String?, String?)>` | 返回 (有更新, 最新版本号, 下载 URL) |

查询 GitHub Release API，比较当前版本与 latest tag。版本号按语义版本比较（major.minor.patch）。网络错误静默返回 `(false, null, null)`。

---

## 三、插件安装管理（I17 / I18 / I19）

```dart
import 'package:evergreen_base/core/services/services.dart';
import 'package:dio/dio.dart';

final installer = PluginInstaller(pluginsDir: 'plugins/', dio: Dio());

// I17: 安装（本地路径或远程 URL，自动识别）
final result = await installer.install('/path/to/plugin.plugin');
final result2 = await installer.install('https://example.com/plugin.plugin');

// I18: 卸载
await installer.uninstall('my_plugin');

// I19: 检查插件更新
final check = await installer.checkUpdate('my_plugin');
if (check.hasUpdate) print('新版本: ${check.latestVersion}');

// 启动时校验所有插件完整性
final corrupt = await installer.verifyAll();  // → List<String> 损坏的插件 ID

// 崩溃监控（由进程管理器调用）
installer.recordCrash('my_plugin');
if (installer.isUnstable('my_plugin')) print('插件已标记为不稳定');

// 通知回调（全局工程师在启动管线中绑定）
installer.onInstall = (pluginId) => print('已安装: $pluginId');
installer.onUninstall = (pluginId) => print('已卸载: $pluginId');

// 状态查询
final plugins = installer.listPlugins();          // → List<PluginStatus>
final status = installer.pluginStatus('my_plugin'); // → PluginStatus?
```

### PluginInstaller

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `PluginInstaller({pluginsDir, dio})` | `pluginsDir: String`, `dio: Dio` | `PluginInstaller` | 构造 |
| `.install(packagePath)` | `packagePath: String` (本地路径或 URL) | `Future<Result<InstallResult>>` | 下载→签名→解压→通知 |
| `.uninstall(pluginId)` | `pluginId: String` | `Future<Result<void>>` | 删除目录→通知 |
| `.checkUpdate(pluginId)` | `pluginId: String` | `Future<UpdateCheck>` | 版本比较 |
| `.verifyAll()` | — | `Future<List<String>>` | 校验所有插件，返回损坏列表 |
| `.recordCrash(pluginId)` | `pluginId: String` | `void` | 记录一次崩溃 |
| `.isUnstable(pluginId)` | `pluginId: String` | `bool` | 10 分钟内 ≥3 次→不稳定 |
| `.listPlugins()` | — | `List<PluginStatus>` | 列出所有已安装插件 |
| `.pluginStatus(pluginId)` | `pluginId: String` | `PluginStatus?` | 单个插件状态 |
| `onInstall` / `onUninstall` | 回调 | — | 安装/卸载后通知（全局绑定） |

### 安装流程

```
URL → download (3 次重试: 1s/3s/5s) → ZIP 解压 → manifest.json 校验
  → SHA-256 签名比对 → plugins/<id>/ 落盘 → .manifest + .signature 元数据
  → onInstall 回调
```

### 类型

| 类型 | 字段 |
|------|------|
| `InstallResult` | `success`, `pluginId`, `error`, `errorType` |
| `InstallErrorType` | `downloadFailed` / `signatureInvalid` / `extractFailed` / `diskFull` / `manifestInvalid` / `alreadyInstalled` |
| `UpdateCheck` | `hasUpdate`, `currentVersion`, `latestVersion`, `downloadUrl` |
| `PluginStatus` | `id`, `name`, `version`, `isUnstable`, `crashCount`, `installedAt`, `subComponents` |

---

## 四、Core HTTP Server（I++ 微服务端点）

REST 端点（见下表），绑定 `127.0.0.1` 随机端口。端口发现文件由启动器（`app_bootstrap.dart`）统一写入
projectRoot 下的 `.core_port` 供插件 `.exe` 发现（server 自身不再写端口文件）。

```dart
import 'package:evergreen_base/core/services/services.dart';

final server = CoreHttpServer(installer, ocrPipeline, updateService);
final port = await server.start();    // 启动 → 返回端口号
// 插件 .exe 读取 projectRoot/.core_port 文件 → http://127.0.0.1:$port/core/...

await server.stop();                  // 关闭服务器
print(server.isRunning);              // 运行状态
```

### CoreHttpServer

| 方法 | 说明 |
|------|------|
| `CoreHttpServer(installer, ocrPipeline, updateService, {port})` | 构造，默认 port=0 自动分配 |
| `.start()` → `Future<int>` | 启动监听，返回端口号 |
| `.stop()` → `Future<void>` | 关闭服务器 |
| `isRunning` → `bool` | 是否正在监听 |
| `port` → `int` | 实际端口号（未启动=0） |

### 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/core/health` | `{status, pluginsCount, ocrAvailable, timestamp}` |
| `POST` | `/core/install` | Body `{path}` 或 `{url}` → 安装插件 |
| `POST` | `/core/uninstall/:id` | 卸载指定插件 |
| `GET` | `/core/plugins` | `{plugins: [PluginStatus...]}` |
| `GET` | `/core/update/check/:id` | 检查单个插件更新 |
| `GET` | `/core/update/check` | 检查宿主更新 |
| `POST` | `/core/ocr` | Body `{path}` → OCR 识别 |
| `GET` | `/core/ocr/status` | `{deepseekAvailable, tesseractAvailable}` |

---

## 五、同步中心导入（SyncImportService，t-C3）

> 契约：`docs/superpowers/specs/egsync-sync-center-spec-v1.md`（§十二 导入端）。
> 把 `.egsync.zip` fail-closed 校验后落盘并注册（插件 / 数据源 / 主题）。

```dart
import 'package:evergreen_base/core/services/services.dart';

final service = SyncImportService(
  registry: moduleRegistry,            // 插件注册回放（reloadModule）
  themeStore: themeStore,              // 主题热注册
  orch: dataOrchestrator,              // 数据源（模型 A）热注册
  configImporter: importConfigAndSync, // core-config 配置导入回调
);
final result = await service.importZip('sync.egsync.zip');
if (result.isErr) {
  // 包级 fail-closed 拒绝（type/version 非法、zip-slip 越界）
} else if (result.value.hasConflicts) {
  // 冲突清单（SyncConflict）→ UI 展示，用户确认后以 applyConflicts 重导
} else {
  // result.value.items：imported / noop / skipped / error
}
```

| API | 说明 |
|------|------|
| `SyncImportService({registry, themeStore, orch, projectRoot, pluginsRoot, sessionsRoot, memoriesRoot, configImporter})` | 构造；缺省根走 `resolvePluginsRoot()`（跨平台） |
| `.importZip(path, {policy})` → `Future<Result<SyncImportResult>>` | 包级违规整体拒绝（Err）；资源级问题记 item error/conflict |
| `SyncImportPolicy` | `overwriteNewer`（默认 true，备份旧 config）/ `overwriteSameVersion` / `allowDowngrade` / `applyConflicts` / `overwriteThemes` / `overwriteRuntimeData` |
| `SyncImportResult` | `items` / `conflicts`（`SyncConflict`）/ `counts`；`hasConflicts` / `hasErrors` |
| `SyncResourceType` | `config` / `sessions` / `memories` / `plugins` / `data` / `themes` |

- 冲突默认策略：同内容 no-op / 新版覆盖（备份+恢复旧 config/）/ 同版本不同内容与版本回退 → 冲突清单不自动破坏。
- 注册回放：插件 `ModuleRegistry.reloadModule`；数据源模型 A `registerDataSourcesFromManifest`、模型 B（HTTP .exe）`DataSourceLoader` best-effort 回放（失败降级仅提示，不阻断包）；主题 `ThemeStore.register`；sessions/memories 原样落盘（合并 t-C4）；config 交接 core-config。
- 冒烟验证：`evg-base/test/sync_import_smoke_test.dart`（8 用例：导入注册 / no-op / 冲突与覆盖 / type 拒绝 / zip-slip 拒绝 / 信封哈希 / 目录缺失隔离 / 模型 B 降级）。

---

## 依赖

| 依赖 | 说明 |
|------|------|
| 嵌入式 Python 运行时 | Tesseract 降级链解释器（由安装包预置 / 资产释放提供，非仓库资产） |
| `scripts/ocr_slides.py` | OCR 子进程（URL 输入） |
| `scripts/pdf_to_images.py` | PDF 拆页脚本 |
| `scripts/ocr_file.py` | 本地 OCR 脚本 |
| DeepSeek OCR API Key | 环境变量 `DEEPSEEK_OCR_API_KEY`（OCR 云端链；`OcrPipeline` 构造可注入 apiKey 覆盖） |

> 脚本运行期路径：由资产释放填充到 `.greenix/scripts`（`greenixScriptsDir`），
> 本体维护在 `evg-base/scripts/`（platform OWNER 管辖）。

## 规则

- `OcrPipeline` 两级降级——优先云端，失败回退本地。
- `recognizeFile` 返回 `null` 表示全部降级失败；`recognizeUrl` 失败返回空字符串（不抛异常）。
- `UpdateService` 网络错误静默返回 `(false, null, null)`。
- `PluginInstaller.install()` 签名不匹配→拒绝、3 次重试(1s/3s/5s)、ZIP slip 防护。
- `PluginInstaller` 崩溃阈值 10 分钟内 ≥3 次→`isUnstable=true`。
- 端口发现文件由 `app_bootstrap.dart` 统一写入 projectRoot（`.core_port` 等端口文件）。
- `services.dart` barrel 仅导出纯 Dart 服务；含 Flutter 依赖的服务按需直接 import（见文件头说明）。
