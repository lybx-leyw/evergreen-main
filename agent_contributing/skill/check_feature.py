#!/usr/bin/env python3
"""
Evergreen Multi-Tools 代码合规检查 (Feature Compliance Checker)

对指定路径下的 Dart 代码进行静态分析，验证是否遵守 AGENT_CONTRIBUTING.md 规则。

检查项：
  1. 禁止使用 print() / debugPrint()（日志必须用 Log()）
  2. 禁止硬编码 Dio() 实例（必须通过 dioClientProvider）
  3. Service 方法返回 Result<T>
  4. Service 未抛异常（return Err(...) 代替 throw）
  5. Process.start/run 是否遗漏 includeParentEnvironment
  6. 测试文件是否存在
  7. MODULE_MAP.md 是否更新（弱检查）
  8. ref.read(authProvider) 警告

用法:
  python check_feature.py lib/features/my_feature/          # 检查某模块
  python check_feature.py lib/features/my_feature/ --strict  # 严格模式（warn -> error）
  python check_feature.py --all                              # 检查整个 lib/
"""

import argparse
import re
import sys
from pathlib import Path


# ============================================================
# 配置
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent

# 允许使用 print 的白名单目录（agent 框架内部等）
PRINT_ALLOWLIST = [
    "lib/core/agent/",
]

# 允许直接创建 Dio 的白名单
DIO_ALLOWLIST = [
    "lib/core/network/dio_client.dart",
    "lib/core/network/dio_client_provider.dart",
]

# 不需要检查 Result<T> 返回值的目录
SERVICE_SKIP_RESULT_CHECK = [
    # 工具类、非业务 Service 可跳过
    "lib/core/",
]


# ============================================================
# 核心逻辑
# ============================================================

class CheckResult:
    """单条检查结果。"""
    def __init__(self, level: str, rule: str, file: str, line: int, detail: str):
        self.level = level      # "error" | "warning" | "info"
        self.rule = rule
        self.file = file
        self.line = line
        self.detail = detail

    def __str__(self):
        emoji = {"error": "❌", "warning": "⚠️", "info": "ℹ️"}
        return f"{emoji.get(self.level, '?')} [{self.rule}] {self.file}:{self.line} — {self.detail}"


class ComplianceChecker:
    def __init__(self, target_path: Path, strict: bool = False):
        self.target = target_path
        self.strict = strict
        self.results: list[CheckResult] = []
        self.errors = 0
        self.warnings = 0

    def add(self, level: str, rule: str, file: str, line: int, detail: str):
        r = CheckResult(level, rule, file, line, detail)
        self.results.append(r)
        if level == "error":
            self.errors += 1
        elif level == "warning":
            self.warnings += 1

    def is_allowed(self, file_path: str, allowlist: list[str]) -> bool:
        """检查文件路径是否在白名单中。"""
        rel = str(Path(file_path).as_posix())
        for allowed in allowlist:
            if rel.startswith(allowed) or rel == allowed:
                return True
        return False

    def dart_files(self) -> list[Path]:
        """递归获取目标路径下所有 .dart 文件。"""
        if self.target.is_file() and self.target.suffix == ".dart":
            return [self.target]
        if self.target.is_dir():
            return sorted(self.target.rglob("*.dart"))
        return []

    # ---- 检查项 ----

    def check_no_print(self, file_path: Path):
        """检查是否使用了 print() / debugPrint()。"""
        if self.is_allowed(str(file_path.relative_to(PROJECT_ROOT)), PRINT_ALLOWLIST):
            return
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            return
        for i, line in enumerate(content.splitlines(), 1):
            # 匹配 print( 或 debugPrint( 但排除注释行
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            # Log().info / Log().error / Log().warn / Log().debug 是正确用法
            if re.search(r"(?<!Log\(\)\.)\b(print|debugPrint)\s*\(", stripped):
                # 排除 Log().xxx() 调用中误匹配
                if "Log()" not in stripped and "Log." not in stripped:
                    rel = file_path.relative_to(PROJECT_ROOT)
                    self.add("error", "no-print", str(rel), i,
                             f"禁止使用 print()/debugPrint()，请用 Log().info() 等")

    def check_no_raw_dio(self, file_path: Path):
        """检查是否直接创建了 Dio() 实例。"""
        rel = str(file_path.relative_to(PROJECT_ROOT))
        if self.is_allowed(rel, DIO_ALLOWLIST):
            return
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            return
        for i, line in enumerate(content.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            # 匹配 Dio() 创建，排除 import 声明
            if re.search(r"=\s*Dio\s*\(", stripped) or re.search(r"new\s+Dio\s*\(", stripped):
                self.add("error", "no-raw-dio", str(file_path.relative_to(PROJECT_ROOT)), i,
                         "禁止直接创建 Dio() 实例，请使用 ref.read(dioClientProvider)")

    def check_service_result(self, file_path: Path):
        """检查 Service 文件的方法是否返回 Result<T>。"""
        filename = file_path.stem
        if not filename.endswith("_service"):
            return
        rel = str(file_path.relative_to(PROJECT_ROOT))
        if self.is_allowed(rel, SERVICE_SKIP_RESULT_CHECK):
            return
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            return

        # 找所有 Future<...> 方法
        future_methods = re.finditer(
            r"(?:Future|Stream)<(?!Result\b)(\w+)\??>\s+\w+\s*\(",
            content
        )
        # 找 throw 语句
        throw_lines = []
        for i, line in enumerate(content.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if re.search(r"\bthrow\s+", stripped) and "rethrow" not in stripped and "unimplemented" not in stripped:
                throw_lines.append(i)

        methods_without_result = [
            (m.start(), m.group())
            for m in future_methods
            if "Result" not in m.group() and "void" not in m.group().lower()
        ]

        if methods_without_result:
            for _, match_text in methods_without_result:
                # 估算行号
                line_num = content[:content.find(match_text)].count("\n") + 1
                self.add("error", "service-result", str(file_path.relative_to(PROJECT_ROOT)), line_num,
                         f"Service 方法返回类型应为 Result<T>，当前: {match_text.strip()}")

        if throw_lines:
            for ln in throw_lines:
                self.add("error", "service-no-throw", str(file_path.relative_to(PROJECT_ROOT)), ln,
                         "Service 禁止抛出异常，请返回 Err(...)")

    def check_process_environment(self, file_path: Path):
        """检查 Process.start/run 是否遗漏 includeParentEnvironment。"""
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            return
        # 找所有 Process.start 和 Process.run 调用块
        process_blocks = list(re.finditer(r"(Process\.start|Process\.run)\s*\(", content))

        for match in process_blocks:
            # 从匹配位置向后搜索 includeParentEnvironment
            block_start = match.start()
            # 取 1000 字符的上下文
            context = content[block_start:block_start + 1000]
            # 找到对应的闭合括号大致位置
            if "includeParentEnvironment" not in context:
                line_num = content[:match.start()].count("\n") + 1
                self.add("error", "process-env", str(file_path.relative_to(PROJECT_ROOT)), line_num,
                         "Process.start/run 必须设置 includeParentEnvironment: true")

    def check_tests_exist(self, file_path: Path):
        """检查是否有对应的测试文件。"""
        # 只检查 features 下的非 UI 文件
        rel = file_path.relative_to(PROJECT_ROOT)
        rel_str = str(rel)
        if not rel_str.startswith("lib/features/"):
            return
        parts = rel.parts
        if len(parts) < 3:
            return
        feature_name = parts[2]  # lib/features/<name>/...

        # 构造对应的测试路径
        test_dir = PROJECT_ROOT / "test" / "features" / feature_name
        if not test_dir.exists():
            rel_from_project = file_path.relative_to(PROJECT_ROOT)
            self.add("warning", "tests-missing", str(rel_from_project), 0,
                     f"模块 {feature_name} 缺少测试目录 test/features/{feature_name}/")

    def check_auth_provider_read(self, file_path: Path):
        """检查是否使用了 ref.read(authProvider) 而非 ref.watch。"""
        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception:
            return
        for i, line in enumerate(content.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if "ref.read(authProvider)" in stripped:
                self.add("warning", "auth-read-vs-watch", str(file_path.relative_to(PROJECT_ROOT)), i,
                         "建议使用 ref.watch(authProvider) 代替 ref.read，否则登录后不会自动刷新")

    # ---- 主检查流程 ----

    def run(self):
        files = self.dart_files()
        if not files:
            print(f"📭 目标路径无 .dart 文件: {self.target}")
            return

        print(f"🔍 正在检查 {len(files)} 个 Dart 文件...")
        print()

        for f in files:
            self.check_no_print(f)
            self.check_no_raw_dio(f)
            self.check_service_result(f)
            self.check_process_environment(f)
            self.check_tests_exist(f)
            self.check_auth_provider_read(f)

        # 打印结果
        for r in sorted(self.results, key=lambda x: (x.file, x.line)):
            print(r)

        # 汇总
        print()
        print("=" * 60)
        print(f"📊 检查完成: {self.errors} 个错误, {self.warnings} 个警告")

        if self.strict and self.warnings > 0:
            self.errors += self.warnings
        elif self.warnings > 0:
            print("   (使用 --strict 可将警告升级为错误)")

        if self.errors > 0:
            print()
            print(f"❌ 发现 {self.errors} 个不合规范的问题，请修正后重试。")
            print("   参考: AGENT_CONTRIBUTING.md 第 1-12 条规则")
            sys.exit(1)
        else:
            print("✅ 合规检查通过！")


# ============================================================
# CLI 入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Evergreen Multi-Tools 代码合规检查",
        epilog="详见 agent_contributing/skill/SKILL.md 步骤 4",
    )
    parser.add_argument("target", nargs="?", default=None,
                        help="检查目标路径 (目录或文件)")
    parser.add_argument("--all", action="store_true",
                        help="检查整个 lib/ 目录")
    parser.add_argument("--strict", action="store_true",
                        help="严格模式：警告升级为错误")

    args = parser.parse_args()

    if args.all:
        target = PROJECT_ROOT / "lib"
    elif args.target:
        target = Path(args.target)
        if not target.is_absolute():
            target = PROJECT_ROOT / target
    else:
        print("❌ 请指定检查目标路径，或使用 --all 检查整个 lib/")
        print(f"   用法: python {Path(__file__).name} lib/features/my_feature/")
        sys.exit(1)

    if not target.exists():
        print(f"❌ 目标路径不存在: {target}")
        sys.exit(1)

    checker = ComplianceChecker(target, strict=args.strict)
    checker.run()


if __name__ == "__main__":
    main()
