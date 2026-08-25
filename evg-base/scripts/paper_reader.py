#!/usr/bin/env python3
"""Paper Reader CLI — PDF 文本提取（pymupdf/fitz）。

2026-08-25：论文阅读功能撤销，仅保留 `extract` 命令（skill_creator 的
`pdf_extract_text` 工具（PymupdfTool）依赖）。翻译相关命令与 pdf2zh_next
引擎已移除。

通信协议：stdin 读 JSON 命令 → stdout 写 JSON 响应（JSON Lines）。

支持命令：
  {"command":"extract",  "args":{"input":"/path/to/file.pdf"}}
  {"command":"exit"}
"""

import sys
import json
import os


# ═══════════════════════════════════════════════════
# pymupdf PDF 文本提取
# ═══════════════════════════════════════════════════

def _extract_pdf_text(file_path: str) -> dict:
    """使用 pymupdf (fitz) 提取 PDF 纯文本并按段落分割。"""
    import fitz  # pymupdf

    doc = fitz.open(file_path)
    full_text_parts = []
    for page in doc:
        text = page.get_text()
        if text:
            full_text_parts.append(text)
    doc.close()

    full_text = '\n'.join(full_text_parts)

    # 按空行拆分为段落，过滤空白段落
    raw = full_text.split('\n\n')
    segments = [s.strip() for s in raw if s.strip() and len(s.strip()) > 10]

    return {
        'full_text': full_text,
        'segments': segments,
        'page_count': len(full_text_parts),
    }


# ═══════════════════════════════════════════════════
# 主循环 — JSON Lines 协议
# ═══════════════════════════════════════════════════

def main():
    handlers = {
        'extract': _handle_extract,
    }

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            _write_error(f'Invalid JSON: {e}')
            continue

        cmd = msg.get('command', '')
        if cmd == 'exit':
            break

        if cmd in handlers:
            handlers[cmd](msg.get('args', {}))
        else:
            _write_error(f'Unknown command: {cmd}')

    sys.exit(0)


def _handle_extract(args: dict):
    file_path = args.get('input', '')
    if not file_path or not os.path.isfile(file_path):
        _write_error(f'File not found: {file_path}')
        return
    try:
        result = _extract_pdf_text(file_path)
        _write_result(result)
    except Exception as e:
        _write_error(f'Extract failed: {e}')


def _write_result(data: dict):
    msg = json.dumps({'type': 'result', 'data': data}, ensure_ascii=False)
    sys.stdout.write(msg + '\n')
    sys.stdout.flush()


def _write_error(message: str):
    msg = json.dumps({'type': 'error', 'message': message}, ensure_ascii=False)
    sys.stdout.write(msg + '\n')
    sys.stdout.flush()


if __name__ == '__main__':
    main()
