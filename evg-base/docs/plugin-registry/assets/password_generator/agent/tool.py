#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""密码生成器（真实随机，纯标准库 random.SystemRandom）：
长度 8-64（默认 16，越界钳制）、可选特殊符号、可选可读字符集（去除混淆字符 Il1O0o）、
熵计算。symbols / readable 必须为布尔。一次性工具。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import random
import string
import math

AMBIGUOUS = "Il1O0o"

def entropy(length, pool_size):
    return round(length * math.log2(pool_size), 1)

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
        length = int(args.get('length', 16))
    except (TypeError, ValueError):
        print(json.dumps({'error': 'length 必须是整数'}, ensure_ascii=False))
        return
    length = max(8, min(64, length))
    use_symbols = args.get('symbols', True)
    readable = args.get('readable', False)
    if not isinstance(use_symbols, bool) or not isinstance(readable, bool):
        print(json.dumps({'error': 'symbols / readable 必须是布尔值'}, ensure_ascii=False))
        return
    pool = string.ascii_letters + string.digits
    if use_symbols:
        pool += "!@#$%^&*()-_=+"
    if readable:
        pool = "".join(c for c in pool if c not in AMBIGUOUS)
    rng = random.SystemRandom()
    pw = "".join(rng.choice(pool) for _ in range(length))
    print(json.dumps({
        'password': pw,
        'length': length,
        'entropy_bits': entropy(length, len(pool)),
        'pool_size': len(pool),
        'symbols': use_symbols,
        'readable': readable,
    }, ensure_ascii=False))

if __name__ == '__main__':
    main()
