#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ocr_file — OCR 插件「标准插件格式」文档示例（Task 四决策 4.2）。

运行期说明
----------
真实 OCR 能力由平台**内置 `ocr_file` 工具**提供（Dart / core `OcrPipeline`，
DeepSeek 云端 → Tesseract 本地两级降级）。本脚本是插件形态示例 / 未来
Python 化占位——因 `ocr_file` 已作为内置工具在三处注册点注册，PluginBridge
扫描到本插件后按「同名跳过」处理，运行期不会产生重复工具、不会干扰内置工具。

若未来 OCR 引擎整体 Python 化，把本脚本替换为真实实现即可：读 stdin JSON
参数 → 执行 OCR → stdout 输出识别文本（约定见 docs/plugin-agent-tool.md）。

当前行为（优先纯标准库，不给用户增加依赖负担）
------------------------------------------------
1. 读 stdin JSON，取 file_path；
2. 文件存在性检查；
3. PDF：若已安装 pymupdf（可选依赖，未装则跳过）提取文本层——仅覆盖
   「数字型 PDF（有文本层）」，扫描版仍需内置 ocr_file；
4. 图片 / 无法处理：返回提示，引导使用内置 ocr_file 工具。
"""
import json
import os
import sys


def _ext(path: str) -> str:
    return os.path.splitext(path)[1].lower()


def _extract_pdf_text_layer(path: str):
    """尝试用 pymupdf 提取 PDF 文本层；未安装或失败返回 None。"""
    try:
        import fitz  # pymupdf（可选依赖，不强制安装）
    except Exception:
        return None
    try:
        doc = fitz.open(path)
        texts = []
        for page in doc:
            t = page.get_text().strip()
            if t:
                texts.append(t)
        doc.close()
        return "\n".join(texts) if texts else None
    except Exception:
        return None


def main() -> int:
    raw = sys.stdin.read() if not sys.stdin.isatty() else "{}"
    try:
        args = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        print(json.dumps({"error": "stdin 不是合法 JSON"}, ensure_ascii=False))
        return 1

    path = str(args.get("file_path") or "").strip()
    if not path:
        print(json.dumps({"error": "file_path 必填"}, ensure_ascii=False))
        return 1
    if not os.path.exists(path):
        print(json.dumps({"error": "文件不存在: %s" % path}, ensure_ascii=False))
        return 1

    ext = _ext(path)
    if ext == ".pdf":
        text = _extract_pdf_text_layer(path)
        if text:
            preview = text[:6000]
            print(json.dumps({
                "ok": True,
                "note": "pymupdf 文本层提取（非 OCR；扫描版请用内置 ocr_file）",
                "total_chars": len(text),
                "text": preview,
            }, ensure_ascii=False))
            return 0

    print(json.dumps({
        "ok": False,
        "error": ("当前为格式示例：真实 OCR 由平台内置 ocr_file 工具提供"
                  "（Dart / OcrPipeline，DeepSeek 云端 → Tesseract 本地降级）。"
                  "请改用内置 ocr_file 工具。"),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
