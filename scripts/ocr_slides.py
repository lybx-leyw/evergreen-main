#!/usr/bin/env python3
"""
ocr_slides.py — 批量 OCR 智云课堂 PPT 截图。

依赖:
  pip install Pillow pytesseract requests

用法:
  python ocr_slides.py --urls "https://img1,https://img2,..."
  python ocr_slides.py --urls_file ./urls.txt

输出:
  JSON 数组: [{"page": 1, "text": "...", "url": "..."}, ...]
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

try:
    from PIL import Image
except ImportError:
    print(json.dumps({"error": "请安装 Pillow: pip install Pillow"}), file=sys.stderr)
    sys.exit(1)

try:
    import pytesseract
except ImportError:
    print(json.dumps({"error": "请安装 pytesseract", "hint": "pip install pytesseract", "action": "pip"}), file=sys.stderr)
    sys.exit(1)

try:
    pytesseract.get_tesseract_version()
except Exception:
    print(json.dumps({
        "error": "未找到 Tesseract OCR 引擎",
        "hint": "下载安装: https://github.com/UB-Mannheim/tesseract/wiki",
        "action": "tesseract"
    }), file=sys.stderr)
    sys.exit(1)

try:
    import requests
except ImportError:
    print(json.dumps({"error": "请安装 requests: pip install requests", "hint": "pip install requests", "action": "pip"}), file=sys.stderr)
    sys.exit(1)

# 智云课堂图片域名白名单
_ALLOWED_DOMAINS = {
    "img.cmc.zju.edu.cn",
    "tgmedia.cmc.zju.edu.cn",
    "education.cmc.zju.edu.cn",
    "classroom.zju.edu.cn",
    "zju.edu.cn",  # 泛域名，子域名也在白名单内
}

# 允许的协议
_ALLOWED_SCHEMES = {"http", "https"}


def _is_url_allowed(url: str) -> bool:
    """校验 URL 是否安全（协议 + 域名白名单）。"""
    # 本地文件路径优先（urlparse 对 Windows 路径会误解析为 scheme='c:'）
    if os.path.isfile(url):
        return True

    parsed = urlparse(url)
    if parsed.scheme not in _ALLOWED_SCHEMES:
        return False
    hostname = parsed.hostname
    if not hostname:
        return False
    # 白名单匹配：精确匹配或 *.zju.edu.cn 匹配
    if hostname in _ALLOWED_DOMAINS:
        return True
    if hostname.endswith(".zju.edu.cn"):
        return True
    return False


def ocr_image(image_path: str, lang: str = "chi_sim+eng") -> str:
    """对单张图片运行 OCR，返回提取的文字。"""
    try:
        img = Image.open(image_path)
        text = pytesseract.image_to_string(img, lang=lang)
        return text.strip()
    except Exception:
        return ""


def download_and_ocr(url: str, page: int, timeout: int = 30) -> dict:
    """下载远程图片 → OCR → 返回结果 dict。"""
    result = {"page": page, "url": url, "text": ""}

    # 本地文件直接 OCR
    if os.path.isfile(url):
        result["text"] = ocr_image(url)
        return result

    # 安全校验
    if not _is_url_allowed(url):
        result["text"] = ""
        print(f"[ocr_slides] 跳过不安全 URL: {url}", file=sys.stderr)
        return result

    tmp_path = None
    try:
        resp = requests.get(url, timeout=timeout, stream=True)
        resp.raise_for_status()

        suffix = Path(urlparse(url).path).suffix or ".jpg"
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(resp.content)
            tmp_path = tmp.name

        result["text"] = ocr_image(tmp_path)

    except requests.RequestException as e:
        print(f"[ocr_slides] 下载失败 第{page}页: {e}", file=sys.stderr)
        result["text"] = ""
    except Exception as e:
        print(f"[ocr_slides] 处理异常 第{page}页: {e}", file=sys.stderr)
        result["text"] = ""
    finally:
        if tmp_path and os.path.isfile(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    return result


def main():
    parser = argparse.ArgumentParser(description="批量 OCR 智云课堂 PPT 截图")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--urls", help="逗号分隔的图片 URL 列表")
    group.add_argument("--urls_file", help="包含图片 URL 的文本文件（每行一个 URL）")
    parser.add_argument("--lang", default="chi_sim+eng", help="OCR 语言 (默认: chi_sim+eng)")
    parser.add_argument("--timeout", type=int, default=30, help="下载超时秒数 (默认: 30)")

    args = parser.parse_args()

    if args.urls is not None:
        raw = args.urls.strip()
        urls = [u.strip() for u in raw.split(",") if u.strip()] if raw else []
    elif args.urls_file is not None:
        with open(args.urls_file, "r", encoding="utf-8") as f:
            urls = [line.strip() for line in f if line.strip()]
    else:
        urls = []

    if not urls:
        print(json.dumps({"error": "没有待处理的图片 URL", "results": []}))
        sys.exit(0)

    results = []
    for i, url in enumerate(urls, start=1):
        result = download_and_ocr(url, page=i, timeout=args.timeout)
        results.append(result)
        text_preview = (result["text"][:40] or "(空)").replace("\n", " ")
        print(f"[ocr_slides] 第 {i}/{len(urls)} 页: {text_preview}...", file=sys.stderr)

    print(json.dumps({"results": results}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
