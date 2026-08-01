#!/usr/bin/env python3
"""
pdf_translate.py — Translate a PDF file via DeepSeek API, output progress as JSON lines.

The pdf2zh_next engine is bundled alongside this script in the scripts/ directory.
External dependencies (babeldoc, pymupdf, openai, etc.) must be installed via pip.

Usage:
  python pdf_translate.py \
      --input "paper.pdf" \
      --output "C:/output/" \
      --api-key "sk-xxx" \
      --model "deepseek-chat" \
      --thinking "disabled" \
      --lang-in "en" \
      --lang-out "zh"

Output (JSON lines to stdout):
  {"type":"progress","current":1,"total":12,"message":"Translating..."}
  {"type":"finish","mono_pdf":"...","dual_pdf":"...","seconds":45.2,"tokens":{"total":12345}}
  {"type":"error","message":"..."}
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

# This script lives in scripts/; pdf2zh_next is bundled alongside it.
_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))


def check_deps() -> str | None:
    """Check that pdf2zh_next can be imported. Returns error JSON or None."""
    try:
        from pdf2zh_next.high_level import do_translate_async_stream  # noqa: F401
        return None
    except ImportError as e:
        return json.dumps({
            "error": f"pdf2zh 依赖缺失: {e}",
            "action": "pip",
            "hint": "请确认已安装 babeldoc, pymupdf, openai 等依赖",
        })
    except Exception as e:
        return json.dumps({"error": str(e), "action": "pip"})


def build_settings(args):
    """Build a SettingsModel from command-line args for DeepSeek translation."""
    from pdf2zh_next.config.model import (
        BasicSettings,
        PDFSettings,
        SettingsModel,
        TranslationSettings,
    )
    from pdf2zh_next.config.translate_engine_model import DeepSeekSettings

    engine = DeepSeekSettings(
        deepseek_model=args.model,
        deepseek_api_key=args.api_key,
        deepseek_thinking_mode=args.thinking if args.thinking else None,
    )

    basic = BasicSettings(
        debug=False,
        gui=False,
    )

    translation = TranslationSettings(
        lang_in=args.lang_in,
        lang_out=args.lang_out,
        output=args.output,
    )

    pdf = PDFSettings(
        no_dual=False,
        no_mono=False,
    )

    return SettingsModel(
        basic=basic,
        translation=translation,
        pdf=pdf,
        translate_engine_settings=engine,
    )


# Map babeldoc internal stage names to user-friendly Chinese labels.
_STAGE_NAME_MAP = {
    "stage_init": "正在初始化翻译引擎...",
    "stage_parse": "正在解析 PDF 文件...",
    "stage_layout": "正在分析页面布局...",
    "stage_ocr": "正在识别扫描件文字...",
    "stage_translate": "正在调用 AI 翻译...",
    "stage_cache": "正在检查翻译缓存...",
    "stage_summary": "正在生成翻译摘要...",
    "stage_cleanup": "正在清理临时文件...",
    "stage_output": "正在生成输出文件...",
    "stage_merge": "正在合成双语 PDF...",
    "stage_font": "正在匹配字体...",
    "stage_embed": "正在嵌入字体...",
}


def format_event(event: dict, output_dir: Path | None = None,
                input_stem: str = "") -> str:
    """Convert a babeldoc event dict to a JSON line for stdout.

    If output_dir and input_stem are provided for a 'finish' event, the
    function will scan the output directory to verify dual/mono PDF paths.
    """

    raw_type = str(event.get("type", ""))

    # Stage transition events — emit with translated message
    if raw_type.startswith("stage_"):
        friendly = _STAGE_NAME_MAP.get(raw_type, raw_type)
        return json.dumps({
            "type": "stage",
            "stage": raw_type,
            "message": friendly,
            "current": event.get("current", 0),
            "total": event.get("total", 0),
        }, ensure_ascii=False)

    if raw_type == "progress":
        return json.dumps({
            "type": "progress",
            "current": event.get("current", 0),
            "total": event.get("total", 0),
            "message": str(event.get("message", "")),
        }, ensure_ascii=False)

    if raw_type == "finish":
        result = event.get("translate_result")
        token_usage = event.get("token_usage", {})

        payload = {
            "type": "finish",
            "total_seconds": result.total_seconds if result else 0,
        }

        if result:
            mono = str(result.mono_pdf_path) if result.mono_pdf_path else None
            dual = str(result.dual_pdf_path) if result.dual_pdf_path else None
        else:
            mono = None
            dual = None

        # Verify and correct paths by scanning the output directory.
        # pdf2zh may report incorrect paths in some versions—this ensures
        # the Flutter side always receives the correct bilingual/mono file.
        if output_dir is not None and output_dir.is_dir():
            found_mono, found_dual = _find_output_files(output_dir, input_stem)
            if found_mono:
                mono = found_mono
            if found_dual:
                dual = found_dual

        payload["mono_pdf"] = mono
        payload["dual_pdf"] = dual

        if token_usage:
            total_tokens = 0
            for key in ("main", "term"):
                if key in token_usage:
                    total_tokens += token_usage[key].get("total", 0)
            payload["tokens"] = {"total": total_tokens}

        return json.dumps(payload, ensure_ascii=False)

    if raw_type == "error":
        return json.dumps({
            "type": "error",
            "message": str(event.get("error", "Unknown error")),
            "error_type": str(event.get("error_type", "")),
            "details": str(event.get("details", "")),
        }, ensure_ascii=False)

    # Generic event — treat as progress, try to translate stage names
    friendly = _STAGE_NAME_MAP.get(raw_type, str(event.get("message", raw_type)))
    return json.dumps({
        "type": "progress",
        "current": event.get("current", 0),
        "total": event.get("total", 0),
        "message": friendly,
    }, ensure_ascii=False)


def _find_output_files(output_dir: Path, input_stem: str) -> tuple[str | None, str | None]:
    """Scan output directory for actual dual/mono PDF files.

    pdf2zh may report incorrect paths in some versions, so we verify by
    scanning the output directory for files matching known naming patterns:
      - <input>-dual.pdf / <input>_dual.pdf → bilingual
      - <input>-mono.pdf / <input>_mono.pdf → monolingual
    """
    mono = None
    dual = None
    if not output_dir.is_dir():
        return None, None

    for pdf in output_dir.glob("*.pdf"):
        name_lower = pdf.name.lower()
        if "dual" in name_lower:
            dual = str(pdf)
        elif "mono" in name_lower:
            mono = str(pdf)

    return mono, dual


async def main() -> int:
    parser = argparse.ArgumentParser(description="Translate PDF via DeepSeek API")
    parser.add_argument("--input", required=True, help="Input PDF path")
    parser.add_argument("--output", required=True, help="Output directory")
    parser.add_argument("--api-key", required=True, help="DeepSeek API key")
    parser.add_argument("--model", default="deepseek-chat", help="DeepSeek model")
    parser.add_argument("--thinking", default=None,
                        help="Thinking mode: enabled/disabled (v4 models)")
    parser.add_argument("--lang-in", default="en", help="Source language")
    parser.add_argument("--lang-out", default="zh", help="Target language")
    args = parser.parse_args()

    # ── Dependency check ───────────────────────────────────────────────
    err = check_deps()
    if err:
        print(err, file=sys.stderr)
        return 1

    from pdf2zh_next.high_level import do_translate_async_stream

    # Validate paths
    input_file = Path(args.input)
    output_dir = Path(args.output)
    if not input_file.is_file():
        print(json.dumps({"error": f"文件不存在: {args.input}"}), file=sys.stderr)
        return 1
    output_dir.mkdir(parents=True, exist_ok=True)

    # ── Build settings ─────────────────────────────────────────────────
    settings = build_settings(args)

    # ── Translate ──────────────────────────────────────────────────────
    try:
        async for event in do_translate_async_stream(settings, input_file):
            line = format_event(event, output_dir=output_dir,
                              input_stem=input_file.stem)
            print(line, flush=True)
            if event.get("type") in ("finish", "error"):
                break
    except Exception as e:
        print(json.dumps({
            "type": "error",
            "message": str(e),
            "error_type": type(e).__name__,
        }, ensure_ascii=False), flush=True)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
