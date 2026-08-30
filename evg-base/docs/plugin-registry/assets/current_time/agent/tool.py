#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""当前时间（真实计算）：cn=中文格式 / iso=ISO 8601。纯标准库。"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
import json
import datetime

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
    fmt = args.get('format', 'cn')
    now = datetime.datetime.now()
    if fmt == 'iso':
        out = now.isoformat()
    elif fmt == 'cn':
        out = now.strftime('%Y年%m月%d日 %H:%M:%S')
    else:
        print(json.dumps({'error': 'format 仅支持 cn 或 iso'}, ensure_ascii=False))
        return
    print(json.dumps({'now': out}, ensure_ascii=False))

if __name__ == '__main__':
    main()
