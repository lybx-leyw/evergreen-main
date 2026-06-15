# 构建指南 — Evergreen Multi-Tools Flutter 桌面应用

## 前置要求

- **Flutter SDK** >= 3.4.0（[安装指南](https://docs.flutter.dev/get-started/install/windows)）
- **Visual Studio 2022** 或 Build Tools（C++ 桌面开发工作负载）
- **Windows 10** 或更高版本

## 首次构建

```powershell
# 1. 进入项目目录
cd evergreen-multi-tools

# 2. 生成 Windows 平台文件（如果 windows/ 目录不存在 runner/*.cpp）
flutter create --platforms=windows .

# 3. 安装依赖
flutter pub get

# 4. 配置环境变量
copy .env.example .env
# 编辑 .env 文件，填入你的学号和密码

# 5. 构建 Release 版本
flutter build windows --release

# 6. 运行（Debug 模式，带热重载）
flutter run -d windows
```

## 构建产物

Release 构建产物位于：
```
build/windows/x64/runner/Release/evergreen_multi_tools.exe
```

## 开发模式

```powershell
# 启动开发模式（带 DevTools）
flutter run -d windows

# 热重载：在终端按 r
# 热重启：在终端按 R
# 退出：按 q
```

## 平台支持

| 平台 | 状态 | 说明 |
|------|------|------|
| Windows | ✅ 完整支持 | 14 个功能模块可用 |
| Android | 🔴 可构建，未测试 | `flutter build apk --release`（Python 脚本不可用） |

## Windows 安装包

```powershell
# 1. 构建 Release
flutter build windows --release

# 2. 安装 Inno Setup (https://jrsoftware.org/isdownload.php)

# 3. 编译安装包
cd scripts
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

# 产物: build/installer/EvergreenSetup-1.0.0.exe
```

## Android 构建

```powershell
# 构建 APK
flutter build apk --release

# 产物: build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ **Android 限制**：当前 Android 版本**不支持 Python OCR 脚本**及本地 Tesseract。Android 端无法调用 `scripts/` 下的 `.py` 文件（`pdf_to_images.py`、`ocr_file.py`、`ocr_slides.py`），涉及 OCR 的功能（AI 笔记、文件识别、培养方案 PDF 解析等）仅桌面端可用。Python 脚本目前仅通过 Windows Inno Setup 安装包打包，Android 端需未来引入 Chaquopy 等方案嵌入 CPython 运行时。

## 自动更新

`UpdateService`（`lib/core/services/update_service.dart`）通过 GitHub Release API 检查更新。

## 环境变量

应用启动时按以下优先级读取配置：
1. 系统环境变量
2. `evergreen-multi-tools/.env` 文件（由 settings screen 自动管理）
3. 应用内设置界面（Settings screen → SharedPreferences）

## 已知限制

| 功能 | 限制 | 解决方案 |
|------|------|---------|
| 背词词典 | 本地词典 JSON 文件需单独下载 | 使用 AI 词源分析作为替代（需配置 DeepSeek API Key） |
| 查老师评分 | chalaoshi.de 是 React SPA，HTML 抓取不可靠 | 仅作参考，数据可能不完整 |
