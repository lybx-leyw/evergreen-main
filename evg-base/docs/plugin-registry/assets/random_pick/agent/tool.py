#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""随机抽取（真实随机，纯标准库 random.SystemRandom.sample）：
items（必填，非空字符串列表）+ count（默认 1，1 <= count <= len(items)）。
抽取不重复（按索引无放回）。count 越界 / items 为空 / 含非字符串 → 结构化错误。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import random

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
    items = args.get('items')
    if not isinstance(items, list) or not items:
        print(json.dumps({'error': 'items 必填且为至少 1 项的字符串数组'}, ensure_ascii=False))
        return
    if not all(isinstance(x, str) for x in items):
        print(json.dumps({'error': 'items 的每个元素必须是字符串'}, ensure_ascii=False))
        return
    try:
        count = int(args.get('count', 1))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'count 必须是整数'}, ensure_ascii=False))
        return
    if count < 1:
        print(json.dumps({'error': 'count 必须 >= 1'}, ensure_ascii=False))
        return
    if count > len(items):
        print(json.dumps({'error': 'count（%d）不能大于候选数（%d）' % (count, len(items))}, ensure_ascii=False))
        return
    picked = random.SystemRandom().sample(items, count)
    print(json.dumps({'picked': picked, 'count': len(picked), 'total': len(items)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
