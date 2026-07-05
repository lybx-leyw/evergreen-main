# Scripts

Python OCR 脚本、嵌入式运行时、安装包配置。

## 文件

| 文件 | 说明 |
|------|------|
| `ocr_file.py` | 本地文件 OCR（Tesseract） |
| `ocr_slides.py` | 课件 URL OCR（下载→识别） |
| `pdf_to_images.py` | PDF 转图片 |
| `requirements.txt` | Python 依赖：pytesseract / Pillow / requests / pdf2image |
| `installer.iss` | Inno Setup 安装包脚本 |
| `installer_platform.iss` | 平台参数（include） |

## 目录

| 目录 | 说明 |
|------|------|
| `python/` | 嵌入式 Python 3.10 + site-packages |
| `__pycache__/` | Python 缓存 |

## 打包

```bash
# 1. 构建 Flutter
flutter build windows --release

# 2. 打包安装程序（需安装 Inno Setup 6+）
ISCC.exe scripts\installer.iss
# 输出: build\installer\EvergreenSetup-0.0.0.exe
```

## 规则

- 嵌入式 Python 已自带，用户无需安装 Python。
- OCR 依赖已预装到 `python/Lib/site-packages/`。
- `installer.iss` 的 `Excludes` 过滤 `.env`、`.cookies` 等用户数据。
