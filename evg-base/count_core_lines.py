#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
统计当前项目"核心代码"总行数。

核心代码 = lib/ 目录下的 Dart 源码（排除内嵌子包的 build / .dart_tool / test /
example / docs 等非核心内容）。会区分 代码行 / 注释行 / 空行，并按分层给出明细。

用法：
    python count_core_lines.py                # 统计默认核心范围（lib/）
    python count_core_lines.py --root lib     # 指定统计根目录
    python count_core_lines.py --all          # 顺带列出每个文件的行数
    python count_core_lines.py --json         # 以 JSON 输出，便于其他脚本消费

只依赖标准库，Python 3.7+ 可直接运行。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# 配置区：按需修改即可
# ---------------------------------------------------------------------------

# 统计入口目录（相对脚本所在目录）。核心代码只看 lib/。
DEFAULT_ROOT = "lib"

# 纳入统计的文件后缀（核心代码就是 Dart）。
CODE_EXTENSIONS = {".dart"}

# 目录名黑名单：出现在路径任意一段即整目录跳过（子包内的构建/工具/测试等产物）。
EXCLUDE_DIR_NAMES = {
    "build",
    ".dart_tool",
    ".idea",
    ".claude",
    ".codebuddy",
    ".greenix",
    "generated",   # 代码生成产物，不算手写核心代码
    "test",        # 测试代码单独看，不计入核心
    "example",     # 示例代码
    "docs",        # 文档
    ".git",
}

# 文件名黑名单：生成代码通常带这些后缀。
EXCLUDE_FILE_SUFFIXES = (
    ".g.dart",       # json_serializable / built_value 等生成
    ".freezed.dart", # freezed 生成
    ".gr.dart",      # auto_route 生成
)


# ---------------------------------------------------------------------------
# 统计逻辑
# ---------------------------------------------------------------------------

@dataclass
class Counts:
    files: int = 0
    code: int = 0     # 有效代码行
    comment: int = 0  # 注释行
    blank: int = 0    # 空行

    @property
    def total(self) -> int:
        return self.code + self.comment + self.blank

    def add(self, other: "Counts") -> None:
        self.files += other.files
        self.code += other.code
        self.comment += other.comment
        self.blank += other.blank


@dataclass
class FileStat:
    path: str
    counts: Counts = field(default_factory=Counts)


def is_excluded_dir(dirname: str) -> bool:
    return dirname in EXCLUDE_DIR_NAMES


def is_excluded_file(filename: str) -> bool:
    if not any(filename.endswith(ext) for ext in CODE_EXTENSIONS):
        return True
    return any(filename.endswith(suf) for suf in EXCLUDE_FILE_SUFFIXES)


def count_file(path: str) -> Counts:
    """统计单个 Dart 文件：区分代码 / 注释 / 空行，正确处理块注释 /* */。"""
    c = Counts(files=1)
    in_block_comment = False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.strip()

                if not line:
                    c.blank += 1
                    continue

                if in_block_comment:
                    c.comment += 1
                    if "*/" in line:
                        in_block_comment = False
                        # 块注释结束后若同行还有代码，粗略仍按注释计，保持简单可预期
                    continue

                if line.startswith("/*"):
                    c.comment += 1
                    if "*/" not in line:
                        in_block_comment = True
                    continue

                if line.startswith("//"):
                    c.comment += 1
                    continue

                c.code += 1
    except OSError as exc:
        print(f"[warn] 无法读取 {path}: {exc}", file=sys.stderr)
    return c


def walk_core(root: str) -> list[FileStat]:
    stats: list[FileStat] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # 原地裁剪，避免进入被排除目录
        dirnames[:] = [d for d in dirnames if not is_excluded_dir(d)]
        for name in filenames:
            if is_excluded_file(name):
                continue
            full = os.path.join(dirpath, name)
            stats.append(FileStat(path=full, counts=count_file(full)))
    return stats


def group_by_layer(root: str, stats: list[FileStat]) -> dict[str, Counts]:
    """按 root 下的第一级子目录（分层）聚合。"""
    layers: dict[str, Counts] = {}
    root_norm = os.path.normpath(root)
    for st in stats:
        rel = os.path.relpath(st.path, root_norm)
        parts = rel.split(os.sep)
        layer = parts[0] if len(parts) > 1 else "(root)"
        layers.setdefault(layer, Counts()).add(st.counts)
    return layers


# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

def fmt(n: int) -> str:
    return f"{n:,}"


def print_report(root: str, stats: list[FileStat], show_files: bool) -> None:
    total = Counts()
    for st in stats:
        total.add(st.counts)

    layers = group_by_layer(root, stats)

    print("=" * 64)
    print(f"核心代码统计  root = {os.path.normpath(root)}")
    print("=" * 64)
    header = f"{'分层':<20}{'文件':>8}{'代码':>10}{'注释':>10}{'空行':>10}{'总行':>10}"
    print(header)
    print("-" * 68)
    for layer in sorted(layers):
        c = layers[layer]
        print(f"{layer:<20}{fmt(c.files):>8}{fmt(c.code):>10}"
              f"{fmt(c.comment):>10}{fmt(c.blank):>10}{fmt(c.total):>10}")
    print("-" * 68)
    print(f"{'合计':<20}{fmt(total.files):>8}{fmt(total.code):>10}"
          f"{fmt(total.comment):>10}{fmt(total.blank):>10}{fmt(total.total):>10}")
    print("=" * 64)
    print(f"核心代码有效代码行（不含注释/空行）：{fmt(total.code)}")
    print(f"核心代码物理总行数（含注释/空行）：  {fmt(total.total)}")

    if show_files:
        print("\n每个文件明细（按代码行降序）：")
        for st in sorted(stats, key=lambda s: s.counts.code, reverse=True):
            c = st.counts
            print(f"  {fmt(c.code):>7} 代码  {st.path}")


def build_json(root: str, stats: list[FileStat]) -> dict:
    total = Counts()
    for st in stats:
        total.add(st.counts)
    layers = group_by_layer(root, stats)
    return {
        "root": os.path.normpath(root),
        "total": total.__dict__ | {"total_lines": total.total},
        "layers": {
            k: v.__dict__ | {"total_lines": v.total} for k, v in sorted(layers.items())
        },
        "files": [
            {"path": st.path, **st.counts.__dict__, "total_lines": st.counts.total}
            for st in stats
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="统计核心代码总行数")
    parser.add_argument("--root", default=DEFAULT_ROOT,
                        help=f"统计根目录（默认 {DEFAULT_ROOT}）")
    parser.add_argument("--all", action="store_true",
                        help="额外列出每个文件的行数")
    parser.add_argument("--json", action="store_true",
                        help="以 JSON 格式输出")
    args = parser.parse_args()

    # 以脚本所在目录为基准，保证在任意 CWD 下都能正确统计
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root = args.root if os.path.isabs(args.root) else os.path.join(script_dir, args.root)

    if not os.path.isdir(root):
        print(f"[error] 目录不存在：{root}", file=sys.stderr)
        return 1

    stats = walk_core(root)
    if not stats:
        print(f"[warn] 在 {root} 下未找到核心代码文件", file=sys.stderr)
        return 0

    if args.json:
        print(json.dumps(build_json(root, stats), ensure_ascii=False, indent=2))
    else:
        print_report(root, stats, show_files=args.all)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
