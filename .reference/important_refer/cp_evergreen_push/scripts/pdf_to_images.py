#!/usr/bin/env python3
"""
pdf_to_images.py — 将 PDF 转换为 JPEG 图片列表。

依赖:
  pip install pdf2image Pillow

用法:
  python pdf_to_images.py --path "C:/path/to/file.pdf" --output_dir "C:/temp/"

输出:
  JSON: {"pages": [{"page": 1, "path": "C:/temp/page_1.jpg"}, ...]}
"""

import argparse
import json
import os
import sys
import tempfile

try:
    from pdf2image import convert_from_path
except ImportError:
    print(json.dumps({"error": "请安装 pdf2image: pip install pdf2image"}), file=sys.stderr)
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print(json.dumps({"error": "请安装 Pillow: pip install Pillow"}), file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="PDF → JPEG 图片")
    parser.add_argument("--path", required=True, help="PDF 文件路径")
    parser.add_argument("--output_dir", default="", help="输出目录（默认临时目录）")
    parser.add_argument("--dpi", type=int, default=200, help="渲染 DPI")
    parser.add_argument("--skip-ocr", action="store_true", help="保留参数：调用方通过此标志表明仅需 PDF 转图片，无需 OCR")
    args = parser.parse_args()

    if not os.path.isfile(args.path):
        print(json.dumps({"error": f"文件不存在: {args.path}"}), file=sys.stderr)
        sys.exit(1)

    output_dir = args.output_dir or tempfile.mkdtemp(prefix="pyfa_")
    os.makedirs(output_dir, exist_ok=True)

    images = convert_from_path(args.path, dpi=args.dpi)

    pages = []
    for i, img in enumerate(images, start=1):
        img_path = os.path.join(output_dir, f"page_{i}.jpg")
        img.save(img_path, "JPEG", quality=90)
        pages.append({"page": i, "path": img_path})
        print(f"[pdf_to_images] 第 {i}/{len(images)} 页 → {img_path}", file=sys.stderr)

    print(json.dumps({"pages": pages}, ensure_ascii=False))


if __name__ == "__main__":
    main()
