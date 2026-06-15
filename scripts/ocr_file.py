#!/usr/bin/env python3
"""
ocr_file.py — 对图片或 PDF 文件运行 OCR，输出 JSON。

依赖:
  pip install pytesseract Pillow pdf2image

用法:
  python ocr_file.py --path "C:/path/to/file.pdf"
  python ocr_file.py --path "C:/path/to/image.png"

输出:
  {"pages": [{"page": 1, "text": "..."}, ...]}
"""

import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    from PIL import Image
except ImportError:
    print(json.dumps({"error": "请安装 Pillow: pip install Pillow", "action": "pip"}), file=sys.stderr)
    sys.exit(1)

try:
    import pytesseract
except ImportError:
    print(json.dumps({"error": "请安装 pytesseract: pip install pytesseract", "action": "pip"}), file=sys.stderr)
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
    from pdf2image import convert_from_path  # noqa: F401 — 顶部统一检查，避免处理 PDF 时才报错
except ImportError:
    print(json.dumps({
        "error": "处理 PDF 需要 pdf2image: pip install pdf2image",
        "action": "pip"
    }), file=sys.stderr)
    sys.exit(1)

_MAX_OCR_WORKERS = min(os.cpu_count() or 4, 8)


def ocr_image(image, lang: str = "chi_sim+eng") -> str:
    """对 PIL Image 或文件路径运行 OCR。"""
    try:
        if isinstance(image, str):
            img = Image.open(image)
        else:
            img = image
        if img.mode == "RGBA":
            img = img.convert("RGB")
        text = pytesseract.image_to_string(img, lang=lang)
        return text.strip()
    except Exception:
        return ""


def process_file(file_path: str, lang: str = "chi_sim+eng") -> list:
    """处理文件，返回每页 OCR 结果列表。"""
    ext = os.path.splitext(file_path)[1].lower()

    if ext in ('.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp'):
        text = ocr_image(file_path, lang)
        return [{"page": 1, "text": text}] if text else []

    elif ext == '.pdf':
        images = convert_from_path(file_path, dpi=200)
        total = len(images)

        max_dim = 1500
        for i in range(total):
            w, h = images[i].size
            if w > max_dim or h > max_dim:
                scale = min(max_dim / w, max_dim / h)
                images[i] = images[i].resize((int(w * scale), int(h * scale)))

        results = []
        batch_size = 30

        def _ocr_page(page_num, image):
            text = ocr_image(image, lang)
            print(f"[ocr_file] 第 {page_num}/{total} 页 OCR 完成", file=sys.stderr)
            return {"page": page_num, "text": text}

        for start in range(0, total, batch_size):
            batch_end = min(start + batch_size, total)
            batch = [(i + 1, images[i]) for i in range(start, batch_end)]
            workers = min(len(batch), _MAX_OCR_WORKERS)
            with ThreadPoolExecutor(max_workers=workers) as executor:
                futures = {executor.submit(_ocr_page, pn, img): pn for pn, img in batch}
                for future in as_completed(futures):
                    results.append(future.result())

        results.sort(key=lambda r: r["page"])
        return [r for r in results if r["text"]]

    else:
        print(json.dumps({"error": f"不支持的文件格式: {ext}"}), file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="对图片/PDF 文件运行 OCR")
    parser.add_argument("--path", required=True, help="文件路径")
    parser.add_argument("--lang", default="chi_sim+eng", help="OCR 语言")
    args = parser.parse_args()

    if not os.path.isfile(args.path):
        print(json.dumps({"error": f"文件不存在: {args.path}"}), file=sys.stderr)
        sys.exit(1)

    pages = process_file(args.path, args.lang)
    print(json.dumps({"pages": pages}, ensure_ascii=False))


if __name__ == "__main__":
    main()
