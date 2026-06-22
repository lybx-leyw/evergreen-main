# 构建指南 — Evergreen Multi-Tools Flutter 桌面应用

## 前置要求

- **Flutter SDK** >= 3.4.0（[安装指南](https://docs.flutter.dev/get-started/install/windows)）
- **Visual Studio 2022** 或 Build Tools（C++ 桌面开发工作负载）
- **Inno Setup 6**（[下载](https://jrsoftware.org/isdownload.php)）— Windows 安装包编译
- **Windows 10** 或更高版本

## 首次构建

```powershell
# 1. 进入项目目录
cd evergreen-multi-tools

# 2. 生成 Windows 平台文件（如果 windows/ 目录不存在）
flutter create --platforms=windows .

# 3. 安装依赖
flutter pub get

# 4. 配置环境变量
copy .env.example .env
# 编辑 .env 填入学号和密码

# 5. 构建 Release 版本
flutter build windows --release

# 6. 运行（Debug 模式）
flutter run -d windows
```

`flutter build windows --release` 会通过 CMake `POST_BUILD` 自动将 `scripts/` 目录复制到构建产物旁。

```
build/windows/x64/runner/Release/evergreen_multi_tools.exe
```

## 开发模式

```powershell
flutter run -d windows        # 热重载：按 r / 热重启：按 R / 退出：按 q
```

## 平台支持

| 平台 | 状态 | 说明 |
|------|------|------|
| Windows | ✅ 完整支持 | 16 个功能模块可用 |
| Android | 🟡 可编译 | 可构建 APK，但**不承诺任何功能可用** |

---

## 嵌入式 Python 环境（一次性设置）

> `scripts/python/` 已加入 `.gitignore`，不在 Git 中跟踪。全新 clone 后需要执行以下步骤。

### 1. 下载 Python 3.10 embeddable

```powershell
$pythonVersion = "3.10.11"
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-embed-amd64.zip" -OutFile "$env:TEMP\python-embed.zip"

Remove-Item -Recurse -Force scripts\python\ -ErrorAction SilentlyContinue
Expand-Archive -Path "$env:TEMP\python-embed.zip" -DestinationPath scripts\python\ -Force
```

### 2. 配置 site-packages 支持

编辑 `scripts\python\python310._pth`，确保以下内容（取消 `import site` 的注释）：

```
python310.zip
.

# Uncomment to run site.main() automatically
import site
```

### 3. 安装 pip 和依赖

```powershell
# 安装 pip
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$env:TEMP\get-pip.py"
scripts\python\python.exe $env:TEMP\get-pip.py

# 安装所有依赖
scripts\python\python.exe -m pip install -r scripts\requirements.txt
```

### 4. 验证

```powershell
scripts\python\python.exe -m pytest scripts\tests\ -v
```

---

## 构建 Windows 安装包

每当你需要生成 `.exe` 安装包时执行：

### 1. 构建 Flutter + 清理

```powershell
flutter build windows --release

# 清理 Python site-packages 冗余文件（避免 Inno Setup 触发 MAX_PATH 260 字符限制）
$pkg = "scripts\python\Lib\site-packages"
if (Test-Path $pkg) {
    Remove-Item -Recurse -Force "$pkg\onnx\backend\test" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$pkg\onnxruntime\tools" -ErrorAction SilentlyContinue
    Get-ChildItem -Path $pkg -Directory -Recurse -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
}
```

### 2. 编译安装包

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" scripts\installer.iss
```

产物：`build\installer\EvergreenSetup-{version}.exe`（约 170 MB，编译约 4 分钟）

---

## Python 脚本

| 脚本 | 用途 | 关键依赖 |
|------|------|---------|
| `ocr_file.py` | 图片/PDF OCR → JSON | pytesseract, Pillow, pdf2image |
| `ocr_slides.py` | 批量 OCR 智云课堂 PPT 截图 | pytesseract, Pillow, requests |
| `pdf_to_images.py` | PDF → JPEG 图片 | pdf2image, Pillow |
| `pdf_translate.py` | DeepSeek API PDF 翻译 | BabelDOC, PyMuPDF, openai, pydantic, tomlkit, rich |

依赖统一由 `scripts/requirements.txt` 管理，测试套件位于 `scripts/tests/`。

### 新增依赖

```powershell
scripts\python\python.exe -m pip install <new-package>
# 手动编辑 scripts/requirements.txt 添加版本约束
# 手动编辑 scripts/tests/test_deps_verify.py 添加验证项
scripts\python\python.exe -m pytest scripts\tests\test_deps_verify.py -v
```

---

## 环境变量

应用启动时按以下优先级读取配置：
1. 系统环境变量
2. `.env` 文件（由 settings screen 自动管理）
3. 应用内设置界面（Settings screen → SharedPreferences）

---

## Android 构建

```powershell
flutter build apk --release   # 产物: build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ Android 版本可编译但**不承诺任何功能可用**，OCR、AI 助手等功能尚未适配移动端。

## 已知限制

| 功能 | 限制 | 解决方案 |
|------|------|---------|
| 背词词典 | 本地词典 JSON 文件需单独下载 | 使用 AI 词源分析替代（需配置 DeepSeek API Key） |
| 查老师评分 | chalaoshi.de 是 React SPA，HTML 抓取不可靠 | 仅作参考 |
