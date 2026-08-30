#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""当前日期（真实计算）：YYYY-MM-DD，可选附带星期几。纯标准库。"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
import json
import datetime

WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日']

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
    today = datetime.date.today()
    out = today.strftime('%Y-%m-%d')
    wd = args.get('with_weekday', True)
    if not isinstance(wd, bool):
        print(json.dumps({'error': 'with_weekday 必须是布尔值'}, ensure_ascii=False))
        return
    if wd:
        out = '%s 星期%s' % (out, WEEKDAYS[today.weekday()])
    print(json.dumps({'date': out}, ensure_ascii=False))

if __name__ == '__main__':
    main()
