# Core 层 — 共享基础设施 + 服务层 + 工具层

> **模块定位**：Evergreen 三层架构（`core/` → `plugins/` → `renderer/`）的上游基础设施层。
> **责任人**：Core 工程师

---

## 一、目录结构

```
lib/core/
├── errors.dart              # AppError 基类 + 13 种子类错误
├── log.dart                 # Log 单例（debug→stderr, release→文件轮转）
├── result.dart              # Result<T> sealed class（Ok / Err）
├── services/                # 平台级基础服务
│   ├── services.dart        #   barrel 导出
│   ├── core_http_server.dart #   微服务网格（8 REST 端点）
│   ├── ocr_pipeline.dart    #   两级 OCR 降级管线
│   ├── deepseek_ocr_service.dart # DeepSeek Vision API 封装
│   ├── plugin_installer.dart #   插件生命周期管理
│   └── update_service.dart  #   应用更新检查
├── utils/                   # 通用工具
│   ├── safe_parse.dart      #   安全类型转换
│   ├── token_estimator.dart #   Token 估算
│   ├── python_env.dart      #   Python 环境管理
│   ├── greenix_path.dart    #   运行时路径管理
│   ├── path_sandbox.dart    #   路径沙箱
│   └── file_utils.dart      #   文件管理器
├── example/                 # 跨模块联动示例
│   ├── example.dart         #   交互式菜单（15 功能）
│   └── plugins/             #   示例插件（mesh_demo / ocean_theme / super_app）
├── test/                    # 测试
│   ├── installer_test.dart  #   插件安装/卸载/校验/崩溃/沙箱
│   ├── ocr_pipeline_test.dart # OCR 管线 + parsePageOutput
│   ├── signature_test.dart  #   签名计算 + 常数时间比较
│   ├── update_service_test.dart # 更新检查降级
│   └── widget_test.dart     #   errors / result 模块验证
├── lib/                     # Stub 隔离层
│   ├── archive_stub/        #   archive 包 stub（ZipDecoder / Archive）
│   ├── crypto_stub/         #   crypto 包 stub（Sha256 / Digest）
│   ├── dio_stub/            #   dio 包 stub（Dio / Response / Options）
│   └── core/                #   文本版 Core 自证应用
├── docs/
│   └── plugin-format.md     #   .plugin 包格式规范 v1.0
├── scripts/                 # OCR 子进程脚本
├── pubspec.yaml             # 依赖声明（stub 指向 lib/）
├── README.md                # 模块总览
├── CLAUDE.md                # 本文件
└── FAIL.md                  # 踩坑记录
```

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

### 2.4 OCR 两级降级策略

```
OcrPipeline.recognizeFile(path)
  ├── Level 1: DeepSeek-OCR（DashScope API, vanchin/deepseek-ocr）
  │   ├── 图片：直接 base64 发送
  │   └── PDF：pdf_to_images.py 拆页 → 逐页 OCR → 合并
  └── Level 2: Tesseract 本地（Python 子进程）
      ├── ocr_file.py（单文件）
      └── ocr_slides.exe / ocr_slides.py（URL 输入）
```

- API Key 通过环境变量 `DEEPSEEK_OCR_API_KEY` 配置
- `recognizeFile` 失败返回 `null`（全部降级失败）
- `recognizeUrl` 失败返回空字符串
- `parsePageOutput` 解析 `{"pages": [{"page": N, "text": "..."}]}` 格式

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

8 个 REST 端点，绑定 `127.0.0.1` 随机端口，端口写入 `.core_port` 供插件 `.exe` 发现：

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/core/health` | 健康检查 |
| POST | `/core/install` | 安装插件 |
| POST | `/core/uninstall/:id` | 卸载插件 |
| GET | `/core/plugins` | 列出已安装插件 |
| GET | `/core/update/check/:id` | 检查单个插件更新 |
| GET | `/core/update/check` | 检查宿主更新 |
| POST | `/core/ocr` | OCR 识别 |
| GET | `/core/ocr/status` | OCR 服务状态 |

---

## 三、开发约定

### 3.1 新增 Service

1. 在 `services/` 下创建新文件
2. 在 `services/services.dart` 中添加 `export` 语句
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
| `installer_test.dart` | 安装/卸载/签名/校验/崩溃/沙箱/版本比较（22 用例） |
| `ocr_pipeline_test.dart` | 文件不存在/空路径/parsePageOutput 多格式（9 用例） |
| `signature_test.dart` | SHA-256 计算/常数时间比较/签名场景（10 用例） |
| `update_service_test.dart` | 网络错误降级/自定义 repo（2 用例） |
| `widget_test.dart` | AppError 13 工厂/Result\<T\> 完整 API（41 用例） |

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
CoreHttpServer(PluginInstaller installer, OcrPipeline ocrPipeline, UpdateService updateService, {int port = 0})
  .start() → Future<int>          // 启动，返回端口号
  .stop()  → Future<void>         // 关闭
  .isRunning → bool               // 运行状态
  .port → int                     // 实际端口（未启动=0）
```

### 5.2 服务间调用约定

- `PluginInstaller.install()` → `Result<InstallResult>`
- `PluginInstaller.uninstall()` → `Result<void>`
- `OcrPipeline.recognizeFile()` → `Future<String?>`
- `UpdateService.checkForUpdate()` → `Future<(bool, String?, String?)>`
- `DeepSeekOcrService.testConnection()` → `Future<Result<String>>`

---

## 六、子模块文档引用

| 模块 | 文档 | 负责人 |
|------|------|--------|
| `agent/` | `agent/README.md` | Agent 工程师 |
| `config/` | `config/README.md` | Config 工程师 |
| `data/` | `data/README.md` | Data 工程师 |
| `module/` | `module/README.md` | Module 工程师 |
| `theme/` | `theme/README.md` | Theme 工程师 |

---

## 七、版本历史

| 日期 | 变更 |
|------|------|
| 2026-07-06 | 初始版本：创建 CLAUDE.md，修复 dio stub 路径，全量测试通过（84 用例），README 审核同步 |
