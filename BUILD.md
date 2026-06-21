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
| Windows | ✅ 完整支持 | 16 个功能模块可用 |
| Android | 🟡 可编译 | 可构建 APK，但**不承诺任何功能可用** |

## Windows 安装包

```powershell
# 1. 构建 Release
flutter build windows --release

# 2. 清理 Python site-packages 中不需要的文件
#    （避免 MAX_PATH 260 字符限制导致 Inno Setup 编译失败）
$pkg = "build\windows\x64\runner\Release\scripts\python\Lib\site-packages"
if (Test-Path $pkg) {
  Remove-Item -Recurse -Force "$pkg\onnx\backend\test" -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force "$pkg\onnxruntime\tools" -ErrorAction SilentlyContinue
  Get-ChildItem -Path $pkg -Directory -Recurse -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
}

# 3. 安装 Inno Setup (https://jrsoftware.org/isdownload.php)

# 4. 编译安装包
cd scripts
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

# 产物: build/installer/EvergreenSetup-1.2.0.exe
```

## Android 构建

```powershell
# 安装依赖
flutter pub get

# 构建 APK
flutter build apk --release

# 产物: build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ **Android 状态**：Android 版本可编译构建 APK，但**不承诺任何功能可用**。OCR、AI 助手等高级功能尚未适配移动端，存在已知问题。推荐使用 Windows 桌面版获得完整体验。

## 自动更新

`UpdateService`（`lib/core/services/update_service.dart`）通过 GitHub Release API 检查更新。

## Python 依赖

### 嵌入 Python（推荐，用户无需安装）

Release 安装包自带 Python 3.11 运行时，用户**无需手动安装 Python**。

如需在开发环境构建嵌入 Python：
```powershell
# 1. 下载 Python embeddable
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile "$env:TEMP\python-embed.zip"

# 2. 解压到 scripts/python/
Expand-Archive -Path "$env:TEMP\python-embed.zip" -DestinationPath scripts\python\ -Force

# 3. 配置 site-packages
Add-Content scripts\python\python311._pth "Lib\site-packages`nimport site"

# 4. 安装 pip
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$env:TEMP\get-pip.py"
scripts\python\python.exe $env:TEMP\get-pip.py

# 5. 安装翻译依赖
scripts\python\python.exe -m pip install babeldoc pymupdf openai tomlkit -t scripts\python\Lib\site-packages
```

> `scripts/python/` 已加入 `.gitignore`，不上传 Git。CI/Release 流程中自动执行上述步骤。

### OCR（系统 Python 备选）

若未使用嵌入 Python，可用系统 Python 安装 OCR 依赖：
```powershell
pip install -r scripts/requirements.txt
```

### PDF 翻译
PDF 翻译引擎源码已内置于 `scripts/pdf2zh_next/`（精简版，仅保留核心）。首次使用时 **自动检测并安装依赖**（babeldoc, pymupdf, openai），无需手动 pip。启动时 `_healLegacyPrefs()` 自动修复旧版本 SharedPreferences 类型残留。

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
