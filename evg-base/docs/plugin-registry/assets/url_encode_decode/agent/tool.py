#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""URL 编码 / 解码（真实实现，纯标准库 urllib.parse）：
text 必填；mode=encode（默认，urllib.parse.quote）或 decode（unquote）。
mode 非法 / text 缺失 → 结构化错误。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import urllib.parse

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
    t = args.get('text')
    if t is None:
        print(json.dumps({'error': 'text 必填'}, ensure_ascii=False))
        return
    if not isinstance(t, str):
        print(json.dumps({'error': 'text 必须是字符串'}, ensure_ascii=False))
        return
    mode = args.get('mode', 'encode')
    if mode == 'encode':
        out = urllib.parse.quote(t)
    elif mode == 'decode':
        out = urllib.parse.unquote(t)
    else:
        print(json.dumps({'error': 'mode 仅支持 encode 或 decode'}, ensure_ascii=False))
        return
    print(json.dumps({'result': out, 'mode': mode}, ensure_ascii=False))

if __name__ == '__main__':
    main()
