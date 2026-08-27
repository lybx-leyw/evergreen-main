# 服务

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | services（更新/安装/同步中心） |

> 源码 `update_service.dart` `plugin_installer.dart` `core_http_server.dart` `github_stars.dart` `sync_import_service.dart`、测试 `../test/`
>
> **HTML-first 事实**：用户 HTML 插件通过 `platform.api.call("core", ...)` 访问 Core 服务；本目录的更新/安装服务仍由平台内部与开发者模式插件使用。
>
> **barrel 说明**：`services.dart` 导出纯 Dart 服务（更新/安装/Core HTTP/GitHub stars/同步导入）；
> `github_clone.dart` / `github_metadata.dart` / `release_downloader.dart` / `ui_operation_log.dart`
> 含 Flutter 依赖或独立契约，按需直接 import 对应文件。

平台级基础服务——应用更新、插件安装管理、HTTP API、GitHub 集成、同步中心导入。外部插件可直接调用。（OCR 管线已移除，见 R3-4。）

---

## 〇、服务清单

| 服务 | 文件 | 说明 | 是否 barrel 导出 |
|------|------|------|-----------------|
| `UpdateService` | `update_service.dart` | 宿主/插件更新检查 | ✅ |
| `PluginInstaller` | `plugin_installer.dart` | 插件安装/卸载/校验/崩溃监控 | ✅ |
| `CoreHttpServer` | `core_http_server.dart` | REST 端点微服务网格 | ✅ |
| `GithubStarsFetcher` | `github_stars.dart` | star 数数据中枢接入（DataType） | ✅ |
| `SyncImportService` | `sync_import_service.dart` | .egsync.zip 导入：fail-closed 校验 + 版本感知冲突 + 注册回放（t-C3） | ✅ |
| `DataFileService` | `data_file_service.dart` | 文件下载：headers/超时/退避重试 + 路径沙箱（T8a） | ✅ |
| `GithubCloner` | `github_clone.dart` | GitHub 源克隆（git clone 子进程） | 直接 import |
| `GithubMetadata` | `github_metadata.dart` | 仓库元数据抓取（市场卡片实时 star） | 直接 import |
| `ReleaseDownloader` | `release_downloader.dart` | GitHub release 二进制下载/解压 | 直接 import |
| `UIOperationLog` | `ui_operation_log.dart` | UI 操作日志（DebugErrorBar 实时显示） | 直接 import |

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

final server = CoreHttpServer(installer, updateService);
final port = await server.start();    // 启动 → 返回端口号
// 插件 .exe 读取 projectRoot/.core_port 文件 → http://127.0.0.1:$port/core/...

await server.stop();                  // 关闭服务器
print(server.isRunning);              // 运行状态
```

### CoreHttpServer

| 方法 | 说明 |
|------|------|
| `CoreHttpServer(installer, updateService, {port})` | 构造，默认 port=0 自动分配 |
| `.start()` → `Future<int>` | 启动监听，返回端口号 |
| `.stop()` → `Future<void>` | 关闭服务器 |
| `isRunning` → `bool` | 是否正在监听 |
| `port` → `int` | 实际端口号（未启动=0） |

### 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/core/health` | `{status, pluginsCount, timestamp}` |
| `POST` | `/core/install` | Body `{path}` 或 `{url}` → 安装插件 |
| `POST` | `/core/uninstall/:id` | 卸载指定插件 |
| `GET` | `/core/plugins` | `{plugins: [PluginStatus...]}` |
| `GET` | `/core/update/check/:id` | 检查单个插件更新 |
| `GET` | `/core/update/check` | 检查宿主更新 |

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

## 六、文件下载（DataFileService，T8a）

> 面向验收目标 4（PDF/文件导出到用户自选路径）core 侧：把「数据源声明 file 类型 → 返回文件清单/下载端点
> → 平台可下载到本地文件」链路落地。T8b 导出 UI（renderer）直接消费本服务。

```dart
import 'package:evergreen_base/core/services/services.dart';

final svc = DataFileService(
  sandboxRoot: '/path/to/export-root', // 可选：设置后 targetPath 必须在其内（防目录穿越）
  timeout: const Duration(seconds: 30), // 默认 30s
  retryBackoff: const [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 5)], // 默认
);

// 单文件：返回 Result<String>（Ok = 本地绝对路径）
final result = await svc.downloadFile(
  url: 'https://…/a.pdf',
  targetPath: '/path/to/export-root/a.pdf',
  headers: {'Cookie': 'session=…', 'Referer': '…'}, // 凭据头（T2 会话中心导出注入）
  maxRetries: 3,
);

// 批量（串行）：逐项 Result<String>，文件名自 URL 末段派生
final results = await svc.downloadFiles(
  urls: ['https://…/a.pdf', 'https://…/b.pdf'],
  targetDir: '/path/to/export-root',
  headers: {'Cookie': '…'},
);
```

| API | 说明 |
|------|------|
| `DataFileService({sandboxRoot?, timeout?, retryBackoff?})` | 构造；`sandboxRoot` 设置后经 `path_sandbox` 校验 `targetPath`，越界拒绝写入 |
| `.downloadFile({url, targetPath, headers?, timeout?, maxRetries})` → `Future<Result<String>>` | 下载单文件；成功返回本地绝对路径，失败返回 `Err(AppError)` |
| `.downloadFiles({urls, targetDir, headers?, timeout?, maxRetries})` → `Future<List<Result<String>>>` | 串行批量下载（并发度 = 1：确定性 + 避免并发磁盘写竞争 + 天然限流） |

- **重试语义**（对齐 T4/PluginInstaller「3 次重试 1s/3s/5s」）：网络/连接错误、超时、HTTP `429`/`5xx` 视为
  瞬态可重试；其它 `4xx`（如 `404`）确定性客户端错误**不重试**（fail-fast）。超时 → `Err(AppError.timeout)`，
  HTTP 状态 → `Err(AppError.httpStatus)`，其它 → `Err(AppError.downloadFailed)`，非法 URL/越界 → `Err(AppError.validationError)`。
- **实现**：`dart:io` 的 `HttpClient`（零新依赖，纯 Dart，可独立 `dart test`）；复用 `release_downloader.dart`
  的 `_download` 模式，但服务化 + `Result` + headers + 沙箱。

---

## 依赖

| 依赖 | 说明 |
|------|------|
| 嵌入式 Python 运行时 | 由安装包预置 / 资产释放提供（`paper_reader.py` 等平台脚本，非仓库资产） |

> 脚本运行期路径：由资产释放填充到 `.greenix/scripts`（`greenixScriptsDir`），
> 本体维护在 `evg-base/scripts/`（platform OWNER 管辖）。

## 规则

- `recognizeFile` 返回 `null` 表示全部降级失败；`recognizeUrl` 失败返回空字符串（不抛异常）。
- `UpdateService` 网络错误静默返回 `(false, null, null)`。
- `PluginInstaller.install()` 签名不匹配→拒绝、3 次重试(1s/3s/5s)、ZIP slip 防护。
- `PluginInstaller` 崩溃阈值 10 分钟内 ≥3 次→`isUnstable=true`。
- 端口发现文件由 `app_bootstrap.dart` 统一写入 projectRoot（`.core_port` 等端口文件）。
- `services.dart` barrel 仅导出纯 Dart 服务；含 Flutter 依赖的服务按需直接 import（见文件头说明）。
