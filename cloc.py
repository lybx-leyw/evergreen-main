#!/usr/bin/env python3
"""
cloc.py — 统计 Evergreen Multi-Tools 核心代码行数。

用法:
  python cloc.py                    # 统计所有核心模块
  python cloc.py --by-type          # 按文件类型分组
  python cloc.py --verbose          # 显示每个文件详情

依赖: 无（仅标准库）
"""

import argparse
import os
from collections import defaultdict
from pathlib import Path

# ── 项目根目录 ────────────────────────────────────────────────────────────
ROOT = Path(__file__).parent.resolve()

# ── 需要统计的目录和文件类型 ──────────────────────────────────────────────
TARGETS = [
    ("lib/", [".dart"]),
    ("scripts/", [".py"]),
    ("test/", [".dart"]),
    ("assets/prompts/", [".md", ".txt"]),
]

# ── 排除的目录/文件 ──────────────────────────────────────────────────────
EXCLUDE_DIRS = {
    ".dart_tool", ".idea", ".env", ".cookies", ".reasonix",
    "build", "windows", ".github", ".reference", ".achieve",
    "__pycache__", ".claude", ".vscode", ".git",
    "node_modules", ".pub-cache",
}

EXCLUDE_FILES = {
    "pubspec.lock", ".metadata", ".flutter-plugins-dependencies",
    "evergreen_multi_tools.iml",
}


def count_lines(filepath: Path) -> int:
    """统计文件行数（含空行和注释）。"""
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for _ in f)
    except Exception:
        return 0


def should_exclude(path: Path, root: Path) -> bool:
    """判断路径是否应排除。"""
    rel = path.relative_to(root)
    parts = rel.parts
    # 排除隐藏目录（以 . 开头）
    if any(p.startswith(".") and p != "." for p in parts):
        return True
    # 排除目标目录
    if any(p in EXCLUDE_DIRS for p in parts):
        return True
    return False


def scan() -> dict:
    """扫描项目，返回 {目录: [(文件路径, 行数), ...]} 的嵌套结构。"""
    result = defaultdict(list)

    for target_dir, extensions in TARGETS:
        full_path = ROOT / target_dir
        if not full_path.exists():
            continue

        for fpath in full_path.rglob("*"):
            if not fpath.is_file():
                continue
            if fpath.suffix not in extensions:
                continue
            if fpath.name in EXCLUDE_FILES:
                continue
            if should_exclude(fpath, ROOT):
                continue

            lines = count_lines(fpath)
            result[target_dir].append((fpath.relative_to(ROOT), lines))

    return dict(result)


def print_summary(data: dict, by_type: bool = False, verbose: bool = False):
    """打印统计结果。"""
    total_files = 0
    total_lines = 0
    grand_by_type = defaultdict(lambda: [0, 0])  # ext -> [files, lines]

    for directory, files in data.items():
        files.sort(key=lambda x: x[1], reverse=True)
        dir_lines = sum(f[1] for f in files)
        dir_files = len(files)
        total_files += dir_files
        total_lines += dir_lines

        # 按类型累计
        for fpath, lines in files:
            ext = fpath.suffix
            grand_by_type[ext][0] += 1
            grand_by_type[ext][1] += lines

        # 打印目录标题
        print(f"\n{'=' * 55}")
        print(f"  {directory}")
        print(f"  文件: {dir_files}  |  行数: {dir_lines:,}")
        print(f"{'=' * 55}")

        if verbose:
            for fpath, lines in files:
                pct = lines / max(dir_lines, 1) * 100
                print(f"  {pct:5.1f}%  {lines:>6,}  {fpath}")
        else:
            # 只显示Top-5
            shown = set()
            for fpath, lines in files[:5]:
                pct = lines / max(dir_lines, 1) * 100
                print(f"  {pct:5.1f}%  {lines:>6,}  {fpath}")
                shown.add(str(fpath))
            remaining = [f for f in files[5:] if str(f[0]) not in shown] + \
                        [f for f in files[:5] if str(f[0]) in shown and f not in files[:5]]
            remaining = [f for f in files if str(f[0]) not in {str(s[0]) for s in files[:5]}]
            if remaining:
                print(f"  {'':>5}  {sum(f[1] for f in remaining):>6,}  ... 还有 {len(remaining)} 个文件")

    # 总计
    print(f"\n{'=' * 55}")
    print(f"  {'总计':^12}")
    print(f"{'=' * 55}")
    print(f"  文件: {total_files}  |  行数: {total_lines:,}")

    if by_type:
        print(f"\n{'─' * 40}")
        print(f"  按文件类型")
        print(f"{'─' * 40}")
        for ext in sorted(grand_by_type.keys(), key=lambda e: grand_by_type[e][1], reverse=True):
            f, ln = grand_by_type[ext]
            pct = ln / max(total_lines, 1) * 100
            print(f"  {ext:<8}  {f:>4} 个文件  {ln:>8,} 行  ({pct:5.1f}%)")


def main():
    parser = argparse.ArgumentParser(description="统计 Evergreen 核心代码行数")
    parser.add_argument("--by-type", action="store_true", help="按文件类型分组")
    parser.add_argument("--verbose", action="store_true", help="显示每个文件详情")
    args = parser.parse_args()

    print(f"{' Evergreen Multi-Tools 代码统计 ':=^55}")
    print(f"  根目录: {ROOT}")

    data = scan()
    print_summary(data, by_type=args.by_type, verbose=args.verbose)


if __name__ == "__main__":
    main()
