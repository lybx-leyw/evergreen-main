#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""学期/DDL 倒计时（真实计算，纯标准库 datetime）：
end_date 必填，格式 YYYY-MM-DD；返回距今天数（可为负=已过期）。
非法日期格式返回结构化错误而非崩溃。
"""
import sys
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
    end_date = args.get('end_date')
    if not end_date:
        print(json.dumps({'error': 'end_date 必填（格式 YYYY-MM-DD）'}, ensure_ascii=False))
        return
    try:
        end = datetime.date.fromisoformat(end_date)
    except ValueError:
        print(json.dumps({'error': 'end_date 格式非法（应为 YYYY-MM-DD）: %s' % end_date}, ensure_ascii=False))
        return
    days = (end - datetime.date.today()).days
    print(json.dumps({'days_left': days, 'end_date': end.isoformat()}, ensure_ascii=False))

if __name__ == '__main__':
    main()
