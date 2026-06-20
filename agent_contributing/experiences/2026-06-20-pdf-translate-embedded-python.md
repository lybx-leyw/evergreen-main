---
task_type: feature
tags: [python, subprocess, bundle, embed, translate, config, ux]
files_touched:
  - lib/core/services/pdf_translate_service.dart
  - lib/core/utils/python_env.dart
  - lib/core/config/app_config.dart
  - lib/core/config/app_config_model.dart
  - lib/core/config/app_config_notifier.dart
  - lib/core/storage/settings_service.dart
  - lib/features/translate/providers/translate_provider.dart
  - lib/features/translate/screens/translate_screen.dart
  - lib/features/translate/models/translation_job.dart
  - lib/features/translate/widgets/pdf_preview_widget.dart
  - lib/features/settings/screens/settings_screen.dart
  - scripts/pdf_translate.py
  - scripts/installer.iss
  - .gitignore
difficulty: hard
outcome: success
date: 2026-06-20
related_pr: 2026-06-20-修复PDF翻译体验.md
---

## 做了什么

修复 PDF 翻译的用户体验问题：安装包自带嵌入式 Python（零配置），进度信息从技术 stage 名改为中文提示，增加阶段管线可视化。

## 关键决策

- **嵌入式 Python 方案**：下载 python-3.11.9-embed-amd64.zip → 解压到 `scripts/python/`，配置 `import site` + pip + babeldoc/pymupdf/openai/tomlkit。Inno Setup 打包时一同分发。
- **自动发现优先级**：自带 Python → 用户配置 → 系统 python3 → python → py -3
- `pythonExe = null` 语义从"默认 'python'"改为"自动检测"——更符合用户预期
- Stage 映射在 Python 侧（`pdf_translate.py`），UI 侧只管展示

## 踩过的坑

### tomlkit 依赖遗漏
- babeldoc 需要 `tomlkit`（pdf2zh config 解析），原 `pip install babeldoc pymupdf openai` 不包含
- 已在 `checkEnvironment()` 和 `installPdf2zhDeps()` 中补全

### Riverpod StateNotifier + 可变对象 = 不刷新
- `TranslationJob` 原本是可变类（`..field = value`），`state = job..field = x` → `oldState === newState` → Riverpod 跳过通知
- **修复**：改不可变 + `copyWith()`，每次创建新实例触发 `!=` 比较
- **教训**：StateNotifier 的 state 必须是不可变值对象，否则状态更新不触发 UI 重建

### Dart 记录类型不能 .property 访问
- 记录 `(TranslateStage, IconData, String)` 只能用 `$1`/`$2`/`$3` 位置访问，不能用 `.stage`/`.icon`/`.label`
- 编译错误：`The getter 'stage' isn't defined for the type '(TranslateStage, IconData, String)'`

## 可复用的模式

### 嵌入式 Python 构建模式
```powershell
# 1. 下载
Invoke-WebRequest https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip -OutFile python.zip
# 2. 解压
Expand-Archive python.zip scripts/python/
# 3. 配置
echo "Lib\site-packages" >> scripts/python/python311._pth
echo "import site" >> scripts/python/python311._pth
# 4. 安装 pip + 依赖
scripts/python/python.exe get-pip.py
scripts/python/python.exe -m pip install babeldoc pymupdf openai tomlkit -t scripts/python/Lib/site-packages
```

### AppConfig 五处同步速查
`app_config_model.dart` (字段+copyWith+toString) → `app_config.dart` (env/prefs/set/saveToEnvFile) → `app_config_notifier.dart` (env/prefs/persist/configToMap/applyUpdates) → `settings_service.dart` (keys) → `settings_screen.dart` (UI)

## 注意事项

- 嵌入 Python 不入 git（.gitignore），每次 Release 构建前自动下载
- `pythonExe` 不是敏感字段，不用 `@Secure()`
- Android 不适用（已有 WIP 占位）
- babeldoc 版本升级可能新增 stage → fallback 显示英文原文
