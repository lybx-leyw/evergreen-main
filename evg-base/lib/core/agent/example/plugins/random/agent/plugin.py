"""Random Plugin — Python 标准库实现（原 C 源码 plugin.c 的等价物）。

原 C 实现：`./random.exe --min 1 --max 100` → stdout 随机整数。
本 .py 为统一 python 唯一路径下的标准库版本（纯标准库：argparse + random），
manifest `runtime: "python"`，经 PluginBridge args+flag 模式调用。

命令行：python plugin.py --min 1 --max 100
stdout：42（[min, max] 闭区间随机整数）
"""
import argparse
import random


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=int, default=1, help="最小值，默认 1")
    parser.add_argument("--max", type=int, default=100, help="最大值，默认 100")
    args = parser.parse_args()

    lo, hi = args.min, args.max
    if lo > hi:  # 边界保护（与原 C 实现一致：交换）
        lo, hi = hi, lo

    print(random.randint(lo, hi))


if __name__ == "__main__":
    main()
