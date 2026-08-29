#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""文本 sha256 摘要（真实哈希，纯标准库 hashlib）。
用于数据源增量判断 / 缓存指纹。text 缺失返回结构化错误。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import hashlib

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
    text = args.get('text')
    if text is None:
        print(json.dumps({'error': 'text 必填'}, ensure_ascii=False))
        return
    if not isinstance(text, str):
        print(json.dumps({'error': 'text 必须是字符串'}, ensure_ascii=False))
        return
    h = hashlib.sha256(text.encode('utf-8')).hexdigest()
    print(json.dumps({'sha256': h}, ensure_ascii=False))

if __name__ == '__main__':
    main()
