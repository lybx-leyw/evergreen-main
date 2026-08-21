# 服务

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 1.0 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | services（OCR/翻译/安装/更新） |

> 源码 `ocr_pipeline.dart` `deepseek_ocr_service.dart` `update_service.dart` `plugin_installer.dart` `core_http_server.dart`、测试 `../test/`
>
> **HTML-first 事实**：用户 HTML 插件通过 `platform.api.call("core", ...)` 访问 Core 服务；本目录的 OCR/更新/安装服务仍由平台内部与开发者模式插件使用。

平台级基础服务——OCR 文字识别、应用更新、插件安装管理、HTTP API。外部插件可直接调用。

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
final pipeline = OcrPipeline(Dio());
final text = await pipeline.recognizeFile(path);  // → String?，失败返回 null
final text2 = await pipeline.recognizeUrl(url);   // → String，失败返回空字符串

// 仅云端 OCR
final svc = DeepSeekOcrService(Dio(), apiKey);
final text = await svc.recognize(File(path));     // → String?，失败返回 null
final result = await svc.testConnection();        // → Result<String>
```

### OcrPipeline

| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `OcrPipeline(dio, [pythonEnv])` | `dio: Dio`, `pythonEnv: PythonEnv?` | `OcrPipeline` | 构造 |
| `.recognizeFile(path)` | `path: String` 本地文件路径 | `Future<String?>` | 图片/PDF→文字，失败 null |
| `.recognizeUrl(url)` | `url: String` 图片 URL | `Future<String>` | 下载+OCR，失败抛异常 |
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

8 个 REST 端点，绑定 `127.0.0.1` 随机端口，端口号写入 `.core_port` 供插件 `.exe` 发现。

```dart
import 'package:evergreen_base/core/services/services.dart';

final server = CoreHttpServer(installer, ocrPipeline, updateService);
final port = await server.start();    // 启动 → 返回端口号
// 插件 .exe 读取 .core_port 文件 → http://127.0.0.1:$port/core/...

await server.stop();                  // 关闭 + 清理 .core_port
print(server.isRunning);              // 运行状态
```

### CoreHttpServer

| 方法 | 说明 |
|------|------|
| `CoreHttpServer(installer, ocrPipeline, updateService, {port})` | 构造，默认 port=0 自动分配 |
| `.start()` → `Future<int>` | 启动监听，返回端口号，写入 `.core_port` |
| `.stop()` → `Future<void>` | 关闭服务器，清理 `.core_port` 文件 |
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

## 依赖

| 依赖 | 说明 |
|------|------|
| `scripts/python/python.exe` | 嵌入式 Python（Tesseract 降级链） |
| `scripts/ocr_slides.exe` | OCR 子进程 |
| `scripts/pdf_to_images.py` | PDF 拆页脚本 |
| `scripts/ocr_file.py` | 本地 OCR 脚本 |
| DeepSeek API Key | `DEEPSEEK_API_KEY` 设置项（OCR 云端链） |

## 规则

- `OcrPipeline` 两级降级——优先云端，失败回退本地。
- `recognizeFile` 返回 `null` 表示全部降级失败。
- `UpdateService` 网络错误静默返回 `(false, null, null)`。
- `PluginInstaller.install()` 签名不匹配→拒绝、3 次重试(1s/3s/5s)、ZIP slip 防护。
- `PluginInstaller` 崩溃阈值 10 分钟内 ≥3 次→`isUnstable=true`。
- `CoreHttpServer` 端口写入 `.core_port` 文件供插件发现。
- 所有服务通过 `services.dart` barrel 统一导出。
