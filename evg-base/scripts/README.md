# Scripts

Python 管线（OCR）、嵌入式运行时、安装包配置。

> 这些脚本属于平台/开发者管线（OCR、打包）。普通用户 HTML 插件不直接调用，
> 如需 OCR 能力请通过平台 `platform.api.call` 或内置模块使用。

## 文件

| 文件 | 说明 |
|------|------|
| `ocr_file.py` | 本地文件 OCR（Tesseract），输出 JSON |
| `ocr_slides.py` | 课件 URL 批量 OCR（下载→识别），输出 JSON 数组 |
| `pdf_to_images.py` | PDF 转 JPEG 图片列表 |
| `paper_reader.py` | PDF 文本提取 CLI（pymupdf/fitz，仅 `extract` 命令；skill_creator 的 `pdf_extract_text` 工具依赖，stdin/stdout JSON Lines 协议） |
| `requirements.txt` | **嵌入式 Python 唯一依赖真源**（setup_python.cmd / CI 均按此安装）：pytesseract / Pillow / requests / pdf2image / pymupdf |
| `setup_python.cmd` | 下载嵌入式 Python 3.10.11（embeddable）+ 启用 pip + 安装 `requirements.txt` |
| `reload.cmd` | 重新编译辅助：`flutter pub get` + `flutter build windows --release` |
| `installer.iss` | Inno Setup 安装包脚本（双版 × 双模式，CI 传参区分） |
| `installer_platform.iss` | 平台参数（include，遗留文件，CI 未引用） |
| `test_pomodoro.py` | `pomodoro.exe` 模块 server 冒烟测试 |
| `evg_lib/`（T5 新增） | **平台 Python 库**（可选 import，存量插件零影响）：`config.py`（`_get_config` 三级降级：config.json→ConfigHttpServer→env）、`cas.py`（`cas_login`+`_rsa_encrypt`，ZJU CAS，依赖 requests）、`jsonio.py`（`emit`/`fail`/`validate_and_output` 输出契约 + 声明式 `__json_ops__` 管道）；经 `bundle_scripts.dart` 镜像到 `.greenix/scripts/evg_lib/`，子进程 `PYTHONPATH` 注入后 `import evg_lib` 可用 |

> **2026-08-25 T5 平台 Python 库**：新增 `evg_lib/`（见上表）。用途：把「单 python 从账号到数据」
> 链路中每插件重复的 `_get_config`/`cas_login`/stdout JSON 封装提取为平台库；插件侧
> `try: from evg_lib.config import _get_config except ImportError: <内联 fallback>` 优雅降级。
> Dart 侧常驻会话封装 `PythonSession`（stdio JSON Lines + 阶梯终止）见 `core/plugin/python_session.dart`。
> 零新第三方依赖（requests 已内置）。

> **2026-08-25 撤销记录**：PDF 翻译（`pdf_translate.py` / `pdf_translate_pure.py`）与论文阅读
> （`pdf2zh_next/`、`paper_vision.py`、`test_paper_vision.py`、`verify_pipeline.py` 及其测试资产
> `_test_paper.pdf` / `_test_work/`）已整体删除（用户决策，减少内存占用）；`paper_reader.py`
> 保留 `extract` 命令供 skill_creator 使用。

## Python 环境（嵌入式）

- `scripts/python/` 为本地构建期嵌入式 Python 3.10.11（**.gitignore，不入库**）；CI 在构建前经
  `setup_python.cmd` 同款流程重建到 `build/greenix_dist/python`（installer.iss 打包进 `{app}\.greenix\python`）。
- **依赖真源 = `requirements.txt`**：`setup_python.cmd` 与 CI 均只按它安装，其余包一律视为非受控
  环境残留。2026-08-25 已做一轮瘦身：site-packages 从 **~748 MB → ~91 MB**（移除撤销功能遗留的
  cv2/scipy/sklearn/skimage/sympy/onnx/onnxruntime/networkx/numpy、babeldoc、openai 系、
  selenium、PyInstaller、cryptography、lxml 等死重及其传递依赖；**保留** pytesseract/Pillow/
  pdf2image/pymupdf/requests/Crypto 与 pip/setuptools/wheel）。
- `pymupdf` 已于 2026-08-25 补入 `requirements.txt`（此前为手动安装；paper_reader.py extract 与
  skill_creator `pdf_extract_text` 依赖 fitz，须随受控环境分发）。

## 构建 / 打包

```mermaid
flowchart LR
    A["flutter pub get"] --> B["tool/gen_template_registry.dart --profile<br/>release_full（浙大版）/ release_std（通用版）"]
    B --> C["tool/bundle_plugins.dart --check（O4 门禁）<br/>→ tool/bundle_plugins.dart + tool/bundle_scripts.dart"]
    C --> D{"目标平台"}
    D -->|Windows| E["flutter build windows --release<br/>--dart-define=EVERGREEN_ZJU=true<br/>--no-tree-shake-icons"]
    E --> F["预置嵌入 Python 3.10.11 到<br/>build/greenix_dist/python"]
    F --> G["ISCC.exe scripts/installer.iss<br/>/DMyAppSuffix=-Zju /DMyBuildMode=Release"]
    D -->|Android| H["flutter build apk --debug|--release<br/>--dart-define=EVERGREEN_ZJU=true"]
    H --> I["Chaquopy 构建期编译 Python 3.11<br/>+ pip 依赖进 APK"]
```

### Windows 安装包（CI：`.github/workflows/release.yml`）

```bash
# 1. 生成模板注册表（profile 二选一）+ bundle --check 门禁 + 插件/脚本资产
dart run tool/gen_template_registry.dart --profile release_full   # 浙大专用版；通用版用 release_std
dart run tool/bundle_plugins.dart --check   # O4 门禁：校验提交态一致性（pubspec 标记块 + 本地镜像），不一致退出非 0
dart run tool/bundle_plugins.dart
dart run tool/bundle_scripts.dart --check   # O4 扩展（t27）：脚本资产 bundle 同款门禁
dart run tool/bundle_scripts.dart

# 2. 构建 Flutter（双版由 EVERGREEN_ZJU 区分；release 需 --no-tree-shake-icons）
flutter build windows --release --dart-define=EVERGREEN_ZJU=true --no-tree-shake-icons

# 3. 预置嵌入式 Python（installer 打包进 {app}\.greenix\python）
#    build\greenix_dist\python\ = Python 3.10.11 embeddable + pip install -r scripts/requirements.txt

# 4. 打包安装程序（需安装 Inno Setup 6+）
ISCC.exe scripts\installer.iss "/DMyAppName=Evergreen" "/DMyAppSuffix=-Zju" "/DMyBuildMode=Release"
# 双版：-Zju（浙大专用版）/ -Std（通用版）；双模式：Release / Debug
# 输出: build\installer\EvergreenSetup{Zju|Std}-{Release|Debug}-<ver>.exe
```

### Android APK

```bash
# 1. 生成模板注册表 + bundle --check 门禁 + 插件/脚本资产（同 Windows 步骤 1）
# 2. 构建 APK（Chaquopy 在构建期把 Python 3.11 与 pip 依赖编译进 APK）
flutter build apk --debug --dart-define=EVERGREEN_ZJU=true
# 注意：buildPython 缺失时 chaquopy 会静默跳过 src/main/python 打包，
# 请确保本机有 Python 3.11 或设置 CHAQUOPY_BUILD_PYTHON（见 android/app/build.gradle.kts）。
```

## 规则

- 嵌入式 Python 已自带，用户无需安装 Python。
- **`assets/plugins_bundle/` 是 `plugins/` 的纯镜像不变式**：仅由 `tool/bundle_plugins.dart` 生成；运行期代码（renderer 导出等）禁止直写 bundle。校验用 `dart run tool/bundle_plugins.dart --check`（O4 门禁，CI 构建前执行；`assets/plugins_bundle/` 被 .gitignore，CI 首建场景只校验 pubspec 提交态）。修复漂移：重跑 `bundle_plugins.dart` 并把 pubspec.yaml 变更一并提交。
- **`assets/scripts_bundle/` 同理是 `scripts/` 的纯镜像**（按 `bundle_scripts.dart` 排除规则），校验用 `dart run tool/bundle_scripts.dart --check`（O4 扩展，t27；CI 构建前执行，与 bundle_plugins 同款语义）。
- 排除规则含任意层级的 `AGENT.md`（OWNER 职责书，非运行期资源）、顶层 `README.md`、`.exe`、点文件、Python 缓存等（详见 `tool/bundle_plugins.dart` 的 `_shouldSkip`）。
- Windows：OCR 依赖由 `setup_python.cmd` 预装到嵌入式 Python；Android：依赖由 Chaquopy 构建期安装（`android/app/build.gradle.kts` 的 `chaquopy.pip` 声明）。
- 修改 `plugins/` 或 `scripts/` 资产后必须重跑 `tool/bundle_plugins.dart` / `tool/bundle_scripts.dart`，否则 APK / 安装包打入旧文件。
- `pubspec.yaml` 资产声明分两类：`assets/plugins_bundle/`、`assets/scripts_bundle/` 由上述工具写入各自标记块（`>>>PLUGIN_ASSETS_START>>>` / `>>>SCRIPTS_ASSETS_START>>>`，重跑即整体重写）；`docs/plugin-registry/`（registry 清单 + `assets/` 本地资源）为手写声明，须保持标记块外、逐文件显式声明（目录声明不递归子目录），勿放入自动生成块。
- 用户数据（`.env`、`.cookies` 等）在运行时生成于 `.greenix/`，不在打包产物内。
