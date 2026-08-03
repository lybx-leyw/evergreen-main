#!/usr/bin/env python3
"""纯 Python PDF 翻译（安卓专用）—— pdfminer.six 读布局 + pdf2zh_next 翻译引擎 + reportlab 写双语 PDF。

pymupdf 无 Chaquopy 安卓 wheel，babeldoc（依赖 pymupdf/freetype/cv2 等 C 库）无法在安卓
构建期安装。本脚本改用纯 Python 栈，同时**复用 pdf2zh_next 的翻译引擎**（DeepSeek 配置、
思考模式、术语支持）以保留 babeldoc 的翻译质量：

  1. pdfminer.six   读 PDF 布局：LTTextBox → 段落（text + bbox + 字号）
  2. pdf2zh_next    翻译引擎：DeepSeekSettings → get_translator → translate(段落)
  3. reportlab      生成译文 PDF（mono）→ pypdf 与原页交替合并（dual, alternating_pages）

stdout 输出 JSON Lines，协议与 scripts/pdf_translate.py 完全兼容
（type: stage / progress / finish / error）。

用法：
  python pdf_translate_pure.py --input in.pdf --output out/ \
      --api-key <KEY> --lang-in en --lang-out zh [--model deepseek-chat] [--thinking enabled|disabled]
"""
import argparse
import json
import os
import sys
import time
import traceback


def _emit(event: dict):
    print(json.dumps(event, ensure_ascii=False), flush=True)


def _emit_stage(stage: str, message: str):
    _emit({"type": "stage", "stage": stage, "message": message, "current": 0, "total": 0})


def _emit_progress(current: int, total: int, message: str):
    _emit({"type": "progress", "current": current, "total": total, "message": message})


def _emit_error(message: str, error_type: str = "PureTranslateError", details: str = ""):
    _emit({"type": "error", "message": message, "error_type": error_type, "details": details})


# ═══════════════ 1. 读布局：pdfminer.six ═══════════════

def parse_layout(pdf_path: str):
    """提取每页文本块。返回 (pages, page_sizes)。

    pages: list[list[dict]]，每页含 {'text','bbox':(x0,y0,x1,y1),'size'}
    page_sizes: list[(width, height)]（PDF 坐标，原点左下角）
    """
    from pdfminer.high_level import extract_pages
    from pdfminer.layout import LTChar, LTTextBox, LAParams

    pages = []
    page_sizes = []
    for page in extract_pages(pdf_path, laparams=LAParams()):
        page_sizes.append((float(page.width), float(page.height)))
        blocks = []
        for element in page:
            if not isinstance(element, LTTextBox):
                continue
            text = element.get_text().strip()
            if not text:
                continue
            font_size = None
            for line in element:
                for char in line:
                    if isinstance(char, LTChar):
                        font_size = char.size
                        break
                if font_size:
                    break
            blocks.append({
                "text": text,
                "bbox": (element.x0, element.y0, element.x1, element.y1),
                "size": font_size or 10.0,
            })
        blocks.sort(key=lambda b: (-b["bbox"][1], b["bbox"][0]))
        pages.append(blocks)
    return pages, page_sizes


# ═══════════════ 2. 翻译：复用 pdf2zh_next 引擎 ═══════════════

def make_translator(api_key: str, model: str, lang_in: str, lang_out: str, thinking: str | None):
    """构造 pdf2zh_next 的 DeepSeek 翻译器（与 babeldoc 相同的引擎配置）。

    DeepSeek 走 OpenAI 兼容通道：DeepSeekSettings.transform() → OpenAISettings
    （仓库版 pdf2zh_next 无 translator_impl/deepseek.py，故显式 transform）。
    """
    # pdf2zh_next 在 scripts/ 下，需加入 sys.path（runScript 已加 entry 父目录；本机测试补一下）
    _ensure_pdf2zh_next()
    from pdf2zh_next.config.model import SettingsModel, TranslationSettings
    from pdf2zh_next.config.translate_engine_model import DeepSeekSettings
    from pdf2zh_next.translator import get_translator

    deepseek = DeepSeekSettings(
        deepseek_model=model,
        deepseek_api_key=api_key,
        deepseek_thinking_mode=thinking if thinking in ("enabled", "disabled") else None,
    )
    settings = SettingsModel(
        translation=TranslationSettings(
            lang_in=lang_in,
            lang_out=lang_out,
        ),
        translate_engine_settings=deepseek.transform(),
    )
    return get_translator(settings)


def _ensure_pdf2zh_next():
    """确保 scripts/ 在 sys.path（pdf2zh_next 与脚本同目录）。"""
    d = os.path.dirname(os.path.abspath(__file__))
    if d not in sys.path:
        sys.path.insert(0, d)


def translate_paragraphs(pages, translator, lang_out: str):
    """逐段翻译，填充 block['translation']。返回总 token（粗略计为字符数/4）。"""
    total = sum(len(p) for p in pages)
    done = 0
    for pi, page in enumerate(pages):
        for block in page:
            src = block["text"]
            try:
                block["translation"] = translator.translate(src)
            except Exception as e:
                block["translation"] = src  # 单段失败保留原文
                _emit_error(f"第 {pi + 1} 页某段翻译失败，已保留原文: {e}",
                            error_type="TranslateCallError", details=str(e))
            done += 1
            _emit_progress(done, total, f"正在翻译第 {done}/{total} 段...")
    return 0


# ═══════════════ 3. 写 PDF：reportlab（mono）+ pypdf（dual） ═══════════════

def _register_cjk_font():
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    try:
        pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
        return "STSong-Light"
    except Exception:
        return "Helvetica"


def write_mono_pdf(pages, page_sizes, out_path, font_name):
    from reportlab.pdfgen import canvas
    c = canvas.Canvas(out_path)
    for blocks, (w, h) in zip(pages, page_sizes):
        c.setPageSize((w, h))
        for block in blocks:
            x0, y0, x1, y1 = block["bbox"]
            size = max(6.0, min(float(block.get("size", 10.0)), 32.0))
            text = block.get("translation") or block["text"]
            c.setFont(font_name, size)
            c.drawString(x0, y1 - size, text[:500])
        c.showPage()
    c.save()


def write_dual_pdf(input_path, mono_path, dual_path):
    from pypdf import PdfReader, PdfWriter
    reader_orig = PdfReader(input_path)
    reader_trans = PdfReader(mono_path)
    writer = PdfWriter()
    n = max(len(reader_orig.pages), len(reader_trans.pages))
    for i in range(n):
        if i < len(reader_orig.pages):
            writer.add_page(reader_orig.pages[i])
        if i < len(reader_trans.pages):
            writer.add_page(reader_trans.pages[i])
    with open(dual_path, "wb") as f:
        writer.write(f)


# ═══════════════ main ═══════════════

def main():
    parser = argparse.ArgumentParser(description="纯 Python PDF 翻译（安卓）")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", default="deepseek-chat")
    parser.add_argument("--lang-in", default="en")
    parser.add_argument("--lang-out", default="zh")
    parser.add_argument("--thinking", default=None)
    args = parser.parse_args()

    t0 = time.time()
    stem = os.path.splitext(os.path.basename(args.input))[0]
    mono_pdf = os.path.join(args.output, f"{stem}.{args.lang_out}.mono.pdf")
    dual_pdf = os.path.join(args.output, f"{stem}.{args.lang_out}.dual.pdf")

    try:
        os.makedirs(args.output, exist_ok=True)

        _emit_stage("stage_parse", "正在解析 PDF 文件...")
        pages, page_sizes = parse_layout(args.input)
        total_blocks = sum(len(p) for p in pages)
        if total_blocks == 0:
            raise RuntimeError("未从 PDF 提取到可翻译文本（可能是扫描件，暂不支持 OCR）")

        _emit_stage("stage_init", "正在初始化翻译引擎...")
        translator = make_translator(args.api_key, args.model,
                                     args.lang_in, args.lang_out, args.thinking)

        _emit_stage("stage_translate", "正在调用 AI 翻译...")
        translate_paragraphs(pages, translator, args.lang_out)

        _emit_stage("stage_output", "正在生成输出文件...")
        font_name = _register_cjk_font()
        write_mono_pdf(pages, page_sizes, mono_pdf, font_name)
        write_dual_pdf(args.input, mono_pdf, dual_pdf)

        _emit({
            "type": "finish",
            "total_seconds": round(time.time() - t0, 2),
            "mono_pdf": mono_pdf,
            "dual_pdf": dual_pdf,
            "tokens": {"total": 0},
        })
    except Exception as e:
        _emit_error(f"翻译失败: {e}", error_type=type(e).__name__,
                    details=traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()
