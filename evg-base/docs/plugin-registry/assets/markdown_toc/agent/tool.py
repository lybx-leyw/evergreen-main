#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Markdown TOC 提取（真实解析，纯标准库 re）：
匹配 ATX 标题（# 到 ######），返回 {level, title} 列表。markdown 缺失返回结构化错误。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import re

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
    md = args.get('markdown')
    if md is None:
        print(json.dumps({'error': 'markdown 必填'}, ensure_ascii=False))
        return
    if not isinstance(md, str):
        print(json.dumps({'error': 'markdown 必须是字符串'}, ensure_ascii=False))
        return
    toc = []
    for line in md.splitlines():
        m = re.match(r'^(#{1,6})\s+(.*)', line)
        if m:
            title = m.group(2).strip()
            # 去掉行尾的闭合 #（如 "## 标题 #"）
            title = re.sub(r'\s+#+\s*$', '', title).strip()
            toc.append({'level': len(m.group(1)), 'title': title})
    print(json.dumps({'toc': toc, 'count': len(toc)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
