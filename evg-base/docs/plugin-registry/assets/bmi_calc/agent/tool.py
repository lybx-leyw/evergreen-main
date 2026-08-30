#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BMI 计算（真实计算）：height_cm（厘米）+ weight_kg（千克）→ BMI + 体型建议。
非法输入（缺失 / 非数字 / 非正数）返回结构化错误而非崩溃。纯标准库。
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
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
    try:
        h = float(args.get('height_cm'))
        w = float(args.get('weight_kg'))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'height_cm 与 weight_kg 必填且为数字'}, ensure_ascii=False))
        return
    if h <= 0 or w <= 0:
        print(json.dumps({'error': '身高与体重必须为正数'}, ensure_ascii=False))
        return
    hm = h / 100.0
    bmi = w / (hm * hm)
    if bmi < 18.5:
        level = '偏瘦'
    elif bmi < 24:
        level = '正常'
    elif bmi < 28:
        level = '偏胖'
    else:
        level = '肥胖'
    print(json.dumps({'bmi': round(bmi, 1), 'level': level}, ensure_ascii=False))

if __name__ == '__main__':
    main()
