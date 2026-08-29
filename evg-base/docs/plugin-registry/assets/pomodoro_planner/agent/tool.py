#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""番茄钟学习计划（真实计算，纯标准库）：
minutes（必填，>=1 的整数）拆分为 focus 分钟专注（默认 25）+ 5 分钟休息，
输出块数与余数。focus 为 0/负数/非数字时返回结构化错误而非崩溃。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json

REST_MIN = 5

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
    try:
        total = int(args.get('minutes'))
        focus = int(args.get('focus', 25))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'minutes 与 focus 必须是整数'}, ensure_ascii=False))
        return
    if total < 1:
        print(json.dumps({'error': 'minutes 必须 >= 1'}, ensure_ascii=False))
        return
    if focus < 1:
        print(json.dumps({'error': 'focus 必须 >= 1'}, ensure_ascii=False))
        return
    blocks = total // focus
    remainder = total % focus
    print(json.dumps({
        'blocks': blocks,
        'focus_min': focus,
        'rest_min': REST_MIN,
        'remainder_min': remainder,
        'total_min': total,
    }, ensure_ascii=False))

if __name__ == '__main__':
    main()
