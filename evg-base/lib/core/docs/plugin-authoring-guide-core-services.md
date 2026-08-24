# 插件打包与分发指南

| 元信息 | 值 |
| --- | --- |
| 状态 | active |
| 版本 | 以根 `README.md` 为准 |
| 日期 | 2026-08-02 |
| 负责人 | 待补充 |
| 适用 | 插件打包作者 |

> **面向**：插件开发者 / 插件商城工程师
> **关联**：`PluginInstaller` / `UpdateService` / `OcrPipeline`
> **定位**：本指南不是插件"撰写"规范（撰写规范见各维度详细指南），而是插件**打包、签名、分发、安装**的操作指南。

---

## 一、概述

Evergreen 平台通过 `.plugin` 包分发插件。插件安装后，Core 层的 `PluginInstaller` 自动完成下载、签名校验、解压和注册。插件开发者无需关心这些底层细节，只需按规范打包即可。

本文档涵盖插件开发中涉及 Core 服务的三个主要场景：
1. **PluginInstaller** — 插件的安装/卸载/更新机制
2. **UpdateService** — 宿主和插件的版本检查
3. **OcrPipeline** — 在插件中调用 OCR 能力

---

## 二、PluginInstaller 使用指南

### 2.1 .plugin 包制作

`.plugin` 是一个 ZIP 压缩包，包含以下结构：

```
my_plugin.plugin
├── manifest.json       # 必填：插件元数据
├── .signature          # 必填：SHA-256 签名（manifest.json 的 hex）
├── agent/              # 可选：AI 工具
│   ├── manifest.json
│   └── my_tool.exe
├── module/             # 可选：UI 模块
│   └── manifest.json
├── data/               # 可选：数据源
│   ├── manifest.json
│   └── data_source.exe
├── theme/              # 可选：主题
│   └── theme.json
├── config/             # 可选：设置项
│   └── config.json
└── skill/              # 可选：AI Skill
    └── my_skill.md
```

### 2.2 manifest.json 必填字段

```json
{
  "type": "plugin",
  "id": "my_plugin",
  "name": "我的插件",
  "version": "1.0.0"
}
```

### 2.3 签名生成

```bash
# Linux/macOS
sha256sum manifest.json | cut -d' ' -f1 > .signature

# Windows PowerShell
(Get-FileHash -Algorithm SHA256 manifest.json).Hash.ToLower() | Out-File -Encoding ascii .signature
```

### 2.4 打包命令

```bash
# 将插件目录打包为 .plugin
zip -r my_plugin.plugin manifest.json .signature agent/ module/ data/ theme/ config/ skill/
```

### 2.5 安装流程

平台通过 `PluginInstaller.install()` 安装插件：

```
URL 下载 → 3 次重试 (1s/3s/5s)
  → 本地 .plugin 文件
    → ZIP 解压
      → 读取 manifest.json → 校验 id/name/version
        → 读取 .signature → SHA-256 签名校验
          → 解压到 plugins/<id>/
            → 写入 .manifest + .signature 元数据
              → onInstall 回调 → 通知各 Registry 刷新
```

### 2.6 安装后目录结构

```
plugins/<plugin_id>/
├── .manifest           # manifest.json 副本（用于完整性校验）
├── .signature          # 签名副本
├── agent/              # 各能力子目录（原样解压）
├── module/
├── data/
├── theme/
├── config/
└── skill/
```

### 2.7 常见安装失败原因

| 错误类型 | 原因 | 解决方法 |
|----------|------|---------|
| `signatureInvalid` | `.signature` 与 `manifest.json` 不匹配 | 重新生成签名 |
| `manifestInvalid` | 缺少 `id`/`name`/`version` | 补全必填字段 |
| `alreadyInstalled` | 同 `id` 插件已安装 | 先卸载旧版本 |
| `downloadFailed` | 网络不可达或 URL 无效 | 检查下载地址 |
| `extractFailed` | ZIP 损坏或磁盘满 | 重新打包或清理磁盘 |

### 2.8 更新机制

插件可在 `manifest.json` 中指定 `updateUrl`：

```json
{
  "updateUrl": "https://plugins.example.com/my_plugin/latest.json"
}
```

更新端点需返回：
```json
{
  "version": "1.1.0",
  "downloadUrl": "https://plugins.example.com/my_plugin/1.1.0.plugin"
}
```

平台通过 `PluginInstaller.checkUpdate(pluginId)` 自动比较版本号。

---

## 三、UpdateService 使用指南

### 3.1 宿主更新检查

```dart
final updater = UpdateService(Dio(), repo: 'my-org/my-app');
final (hasUpdate, version, downloadUrl) = await updater.checkForUpdate();
if (hasUpdate) {
  print('新版本: $version → $downloadUrl');
}
```

### 3.2 工作原理

1. 读取当前版本（`package_info_plus` 或 `.version` 文件）
2. 查询 `https://api.github.com/repos/{repo}/releases/latest`
3. 比较版本号（语义化版本：major.minor.patch）
4. 网络错误静默返回 `(false, null, null)`

### 3.3 版本号格式

- 支持标准语义化版本：`1.2.3`
- pre-release 后缀被忽略：`1.0.0-beta` 视为 `1.0.0`
- 缺失段视为 0：`1` = `1.0.0`

---

## 四、OCR Pipeline 调用指南

### 4.1 插件内调用 OCR

插件 `.exe` 通过 CoreHttpServer 的 HTTP API 调用 OCR：

```bash
# 读取 .core_port 发现服务
PORT=$(cat .core_port)

# OCR 识别本地文件
curl -X POST http://127.0.0.1:$PORT/core/ocr \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/image.png"}'

# 返回: {"text": "识别到的文字内容"}
```

### 4.2 OCR 服务状态检查

```bash
curl http://127.0.0.1:$PORT/core/ocr/status
# 返回: {"deepseekAvailable": true, "tesseractAvailable": true}
```

### 4.3 降级策略

OCR 管线自动执行两级降级：

1. **Level 1: DeepSeek-OCR**（云端，高精度）
   - 需要配置环境变量 `DEEPSEEK_OCR_API_KEY`
   - 支持格式：jpg / png / bmp / webp / tiff / pdf
   
2. **Level 2: Tesseract**（本地，离线可用）
   - 自动检测 Python 环境和依赖
   - 支持格式：图片文件 + PDF

### 4.4 依赖要求（Level 2）

| 依赖 | 说明 |
|------|------|
| Python 3.8+ | 系统 PATH，或嵌入式 Python 运行时（由安装包预置 / 资产释放提供） |
| pytesseract | `pip install pytesseract` |
| Pillow | `pip install Pillow` |
| pdf2image | `pip install pdf2image`（PDF 支持） |
| Tesseract-OCR | 系统级安装 |

平台在首次 OCR 调用时自动检查和安装 Python 依赖。

---

## 五、安全注意事项

1. **签名校验**：所有 `.plugin` 必须包含有效签名，篡改的包会被拒绝安装
2. **ZIP slip 防护**：`PluginInstaller` 自动检测并拒绝越界路径
3. **沙箱隔离**：插件 A 无法访问插件 B 的文件
4. **崩溃监控**：10 分钟内崩溃 ≥3 次的插件自动标记为"不稳定"
5. **下载重试**：URL 下载失败自动重试 3 次（间隔 1s / 3s / 5s）

---

## 六、参考

- `.plugin` 包格式完整规范：`docs/plugin-format.md`
- Core 服务 API 文档：`services/README.md`
- Core 工具 API 文档：`utils/README.md`
- 跨模块联动示例：`example/example.dart`
