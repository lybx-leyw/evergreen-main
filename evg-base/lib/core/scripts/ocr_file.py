"""OCR 文件脚本——OcrPipeline Level 2 (Tesseract) 调用入口。

用法: python ocr_file.py <image_path>
输出: {"pages":[{"page":1,"text":"..."}]}
"""
import json
import sys

try:
    from PIL import Image
    import pytesseract
except ImportError as e:
    print(json.dumps({"error": f"依赖缺失: {e}"}))
    sys.exit(1)


def main():
    # 支持 --path <value> 或直接传路径
    if '--path' in sys.argv:
        idx = sys.argv.index('--path')
        path = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
    elif len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = None

    if not path:
        print(json.dumps({"error": "缺少图片路径参数 (--path <path> 或直接 <path>)"}))
        sys.exit(1)
    try:
        img = Image.open(path)
        text = pytesseract.image_to_string(img, lang='chi_sim+eng')
        result = {
            "pages": [
                {"page": 1, "text": text.strip()}
            ]
        }
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == '__main__':
    main()
