#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""单位换算（真实计算，纯标准库）：
长度/质量/数据量/面积/体积/速度/时间（线性系数）+ 温度（c/f/k 特判）。
修复：温度单位此前未注册进类别导致永远走「未知单位」死分支；现温度 6 组换算全部可达。
value 必填且为数字；from/to 必填；未知单位 / 跨类别 → 结构化错误。
"""
import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
import json

UNITS = {
    "length": {"m": 1.0, "km": 1000.0, "cm": 0.01, "mm": 0.001, "mi": 1609.344, "ft": 0.3048, "in": 0.0254},
    "mass": {"kg": 1.0, "g": 0.001, "mg": 1e-6, "t": 1000.0, "lb": 0.45359237, "oz": 0.028349523125},
    "data": {"b": 1.0, "kb": 1024.0, "mb": 1048576.0, "gb": 1073741824.0, "tb": 1099511627776.0},
    "area": {"m2": 1.0, "km2": 1e6, "cm2": 1e-4, "ha": 10000.0, "acre": 4046.8564224},
    "volume": {"l": 1.0, "ml": 0.001, "m3": 1000.0, "gal": 3.785411784},
    "speed": {"mps": 1.0, "kmh": 0.277777778, "mph": 0.44704},
    "time": {"s": 1.0, "min": 60.0, "h": 3600.0, "d": 86400.0, "ms": 0.001},
    "temperature": {"c": None, "f": None, "k": None},  # 非线性，走 temp_convert
}
CATEGORY = {}
for cat, units in UNITS.items():
    for u in units:
        CATEGORY[u] = cat

def temp_convert(v, frm, to):
    if frm == to:
        return v
    if frm == 'c' and to == 'f':
        return v * 9 / 5 + 32
    if frm == 'f' and to == 'c':
        return (v - 32) * 5 / 9
    if frm == 'c' and to == 'k':
        return v + 273.15
    if frm == 'k' and to == 'c':
        return v - 273.15
    if frm == 'f' and to == 'k':
        return (v - 32) * 5 / 9 + 273.15
    if frm == 'k' and to == 'f':
        return (v - 273.15) * 9 / 5 + 32
    return None

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
        v = float(args.get('value'))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'value 必填且为数字'}, ensure_ascii=False))
        return
    frm, to = args.get('from'), args.get('to')
    if not frm or not to:
        print(json.dumps({'error': 'from 与 to 必填'}, ensure_ascii=False))
        return
    if frm not in CATEGORY or to not in CATEGORY:
        print(json.dumps({'error': '未知单位 %s/%s，支持：%s' % (frm, to, ', '.join(sorted(CATEGORY)))}, ensure_ascii=False))
        return
    if CATEGORY[frm] != CATEGORY[to]:
        print(json.dumps({'error': '单位类别不同：%s(%s) vs %s(%s)' % (frm, CATEGORY[frm], to, CATEGORY[to])}, ensure_ascii=False))
        return
    if CATEGORY[frm] == 'temperature':
        result = temp_convert(v, frm, to)
        if result is None:
            print(json.dumps({'error': '不支持的换算 %s -> %s' % (frm, to)}, ensure_ascii=False))
            return
    else:
        base = UNITS[CATEGORY[frm]]
        result = v * base[frm] / base[to]
    print(json.dumps({'value': v, 'from': frm, 'to': to, 'result': round(result, 8), 'category': CATEGORY[frm]}, ensure_ascii=False))

if __name__ == '__main__':
    main()
