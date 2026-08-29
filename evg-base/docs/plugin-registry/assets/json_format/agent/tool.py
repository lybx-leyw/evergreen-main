#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JSON 格式化 / 压缩（真实解析，纯标准库）。
json 必填且必须为合法 JSON 字符串；indent 0-8 的整数（0 = 压缩单行）。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json

def _load_args():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        d = json.loads(raw)
    except Exception as e:
        print(json.dumps({'error': '参数不是合法 JSON: %s' % e}, ensure_ascii=False))
        return None
    if not isinstance(d, dict):
        print(json.dumps({'error': '参数必须是 JSON 对象'}, ensure_ascii=False))
        return None
    return d

def main():
    args = _load_args()
    if args is None:
        return
    text = args.get('json')
    if text is None:
        print(json.dumps({'error': 'json 必填'}, ensure_ascii=False))
        return
    if not isinstance(text, str):
        print(json.dumps({'error': 'json 必须是字符串'}, ensure_ascii=False))
        return
    try:
        data = json.loads(text)
    except Exception as e:
        print(json.dumps({'error': 'JSON 解析失败: %s' % e}, ensure_ascii=False))
        return
    try:
        indent = int(args.get('indent', 2))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'indent 必须是整数（0-8，0 = 压缩）'}, ensure_ascii=False))
        return
    indent = max(0, min(8, indent))
    out = json.dumps(data, ensure_ascii=False, indent=None if indent == 0 else indent)
    print(json.dumps({'formatted': out}, ensure_ascii=False))

if __name__ == '__main__':
    main()
