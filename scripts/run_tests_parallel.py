#!/usr/bin/env python3
"""Parallel Flutter test runner — mirrors CI job split for local speed.

Groups: analyze | core | features | services | widgets | root

Usage:
  python scripts/run_tests_parallel.py              # all groups
  python scripts/run_tests_parallel.py --no-analyze # skip analyze (fastest)
  python scripts/run_tests_parallel.py -j 4          # limit concurrency
  python scripts/run_tests_parallel.py --group core  # single group

Requires: flutter in PATH (or set FLUTTER=path/to/flutter.bat).
"""

import argparse
import concurrent.futures
import os
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _find_flutter() -> str:
    """Resolve flutter executable. Checks: FLUTTER env → PATH → common locations.
    Returns the path if found, or empty string if not (caller should handle)."""
    env = os.environ.get("FLUTTER", "")
    if env:
        return env

    import shutil
    # Try PATH first
    found = shutil.which("flutter")
    if found:
        return found

    # Common per-platform install paths
    candidates: list[str] = []
    if sys.platform == "win32":
        candidates = [
            r"C:\flutter\bin\flutter.bat",
            r"C:\src\flutter\bin\flutter.bat",
            os.path.expandvars(r"%LOCALAPPDATA%\flutter\bin\flutter.bat"),
            os.path.expandvars(r"%USERPROFILE%\flutter\bin\flutter.bat"),
        ]
    elif sys.platform == "darwin":
        candidates = [
            os.path.expanduser("~/flutter/bin/flutter"),
            "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter",
        ]
    else:  # linux
        candidates = [
            os.path.expanduser("~/flutter/bin/flutter"),
            "/usr/local/bin/flutter",
            os.path.expanduser("~/snap/flutter/common/flutter/bin/flutter"),
        ]

    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    return ""


FLUTTER = _find_flutter()


# ── Job definitions (aligned with .github/workflows/test.yml) ──────────
@dataclass
class Job:
    name: str
    args: list[str] = field(default_factory=list)
    timeout_minutes: int = 10

JOBS: list[Job] = [
    Job("analyze",     ["analyze", "--no-fatal-infos", "--no-fatal-warnings"], timeout_minutes=5),
    Job("core",        ["test", "test/core/"],                                 timeout_minutes=10),
    Job("features",    ["test", "test/features/"],                             timeout_minutes=10),
    Job("services",    ["test", "test/services/"],                             timeout_minutes=10),
    Job("widgets",     ["test", "test/widgets/"],                              timeout_minutes=10),
    Job("root",        ["test", "test/widget_test.dart", "test/agent_test.dart"], timeout_minutes=10),
]

# ── Output helpers ──────────────────────────────────────────────────────
_print_lock = threading.Lock()


def _tagged_print(tag: str, line: str):
    """Thread-safe tagged line output."""
    prefix = f"[{tag}]".ljust(14)
    with _print_lock:
        sys.stdout.write(f"{prefix} {line.rstrip()}\n")
        sys.stdout.flush()


@dataclass
class JobResult:
    name: str
    passed: bool
    elapsed: float
    total_tests: int = 0
    failed_tests: list[str] = field(default_factory=list)
    output_lines: list[str] = field(default_factory=list)


# ── Output parsing ─────────────────────────────────────────────────────

# flutter test failure line:  "HH:MM +P -F: path/to/file_test.dart: Test description"
import re as _re

_FAIL_LINE_RE = _re.compile(
    r"^\d{2}:\d{2}\s+\+\d+\s+-(\d+):\s+(.+?\.dart):\s+(.*)"
)
# flutter analyze error/warning line: "  error • message • path.dart:line:col • description"
_ANALYZE_ISSUE_RE = _re.compile(
    r"^\s*(error|warning)\s*[•·]\s*(.+?)\s*[•·]\s*(.+?\.dart):(\d+):(\d+)\s*[•·]\s*(.*)"
)


def _parse_failed_tests(lines: list[str]) -> list[str]:
    """Extract individual failed test names from flutter test output."""
    failures: list[str] = []
    for line in lines:
        m = _FAIL_LINE_RE.search(line)
        if m and int(m.group(1)) > 0:
            failures.append(f"  {m.group(2)}  —  {m.group(3)}")
    return failures


def _parse_analyze_issues(lines: list[str]) -> list[str]:
    """Extract error/warning lines from flutter analyze output."""
    issues: list[str] = []
    for line in lines:
        m = _ANALYZE_ISSUE_RE.search(line)
        if m:
            kind = m.group(1)
            desc = m.group(6) if m.group(6) else m.group(2)
            issues.append(f"  {kind}: {desc}")
    return issues


def _parse_test_counts(lines: list[str]) -> int:
    """Extract total test count from last line like 'HH:MM +N: All tests passed!' or '+N -M: Some tests failed.'"""
    for line in reversed(lines):
        m = _re.match(r"^\d{2}:\d{2}\s+\+(\d+)(?:\s+-(\d+))?:", line)
        if m:
            total = int(m.group(1))
            failed = int(m.group(2) or 0)
            return total + failed
    return 0


# ── Runner ─────────────────────────────────────────────────────────────
def run_job(job: Job) -> JobResult:
    """Run a single Flutter command, tee stdout/stderr with tags."""
    cmd = [FLUTTER, *job.args]
    _tagged_print(job.name, f"▶ START  {' '.join(cmd)}")

    t0 = time.monotonic()
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(PROJECT_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        _tagged_print(job.name, "✗ ERROR  flutter not found")
        return JobResult(name=job.name, passed=False, elapsed=0)

    output_lines: list[str] = []

    def _reader():
        assert proc.stdout is not None
        for line in proc.stdout:
            output_lines.append(line)
            stripped = line.rstrip()
            if stripped:
                _tagged_print(job.name, stripped)
        proc.stdout.close()

    reader_thread = threading.Thread(target=_reader, daemon=True)
    reader_thread.start()

    try:
        returncode = proc.wait(timeout=job.timeout_minutes * 60)
        reader_thread.join(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        _tagged_print(job.name, f"✗ TIMEOUT ({job.timeout_minutes} min)")
        return JobResult(name=job.name, passed=False, elapsed=time.monotonic() - t0)

    elapsed = time.monotonic() - t0
    passed = returncode == 0
    status = "✔ PASS" if passed else "✗ FAIL"
    _tagged_print(job.name, f"{status}   ({elapsed:.1f}s)")

    failed_tests = _parse_failed_tests(output_lines) if not passed else []
    total = _parse_test_counts(output_lines)

    return JobResult(
        name=job.name,
        passed=passed,
        elapsed=elapsed,
        total_tests=total,
        failed_tests=failed_tests,
        output_lines=output_lines,
    )


# ── Main ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Parallel Flutter test runner")
    parser.add_argument("-j", "--jobs", type=int, default=0,
                        help="Max parallel jobs (default: run all simultaneously)")
    parser.add_argument("--no-analyze", action="store_true",
                        help="Skip flutter analyze (faster)")
    parser.add_argument("--group", type=str, default="",
                        help="Run a single group by name (analyze|core|features|services|widgets|root)")
    parser.add_argument("--list", action="store_true", help="List groups and exit")
    args = parser.parse_args()

    if args.list:
        for j in JOBS:
            print(f"  {j.name:12s} → {' '.join(j.args)}")
        return

    # ── Pre-flight check ────────────────────────────────────────────
    if not FLUTTER:
        print("ERROR: flutter not found.")
        print("  • Add flutter to PATH, or")
        print("  • Set FLUTTER environment variable to the full path, e.g.:")
        if sys.platform == "win32":
            print("      set FLUTTER=C:\\flutter\\bin\\flutter.bat")
        else:
            print("      export FLUTTER=$HOME/flutter/bin/flutter")
        sys.exit(1)

    # Filter jobs
    jobs_to_run = [j for j in JOBS if not (args.no_analyze and j.name == "analyze")]
    if args.group:
        jobs_to_run = [j for j in jobs_to_run if j.name == args.group]
        if not jobs_to_run:
            print(f"Unknown group: {args.group}")
            print(f"Available: {', '.join(j.name for j in JOBS)}")
            sys.exit(1)

    max_workers = args.jobs if args.jobs > 0 else len(jobs_to_run)

    print(f"{'═' * 60}")
    print(f"  Parallel Flutter Test Runner")
    print(f"  Groups : {', '.join(j.name for j in jobs_to_run)}")
    print(f"  Workers: {max_workers}")
    print(f"  Root   : {PROJECT_ROOT}")
    print(f"{'═' * 60}\n")

    t_start = time.monotonic()
    results: dict[str, JobResult] = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(run_job, job): job for job in jobs_to_run}
        for future in concurrent.futures.as_completed(futures):
            jr: JobResult = future.result()
            results[jr.name] = jr

    total = time.monotonic() - t_start

    # ── Summary ────────────────────────────────────────────────────
    passed = sum(1 for r in results.values() if r.passed)
    failed = len(results) - passed
    print(f"\n{'═' * 60}")
    print(f"  Results ({passed} passed, {failed} failed, {total:.1f}s total)")
    print(f"{'═' * 60}")
    for jr in results.values():
        mark = "✔" if jr.passed else "✗"
        test_str = f" ({jr.total_tests} tests)" if jr.total_tests else ""
        print(f"  {mark} {jr.name:12s}  {jr.elapsed:.1f}s{test_str}")

    # ── Failed Tests Detail ────────────────────────────────────────
    if failed > 0:
        print(f"\n{'─' * 60}")
        print(f"  Failed Tests Detail")
        print(f"{'─' * 60}")
        any_fail_detail = False
        for jr in results.values():
            if jr.passed:
                continue
            if jr.failed_tests:
                print(f"\n  [{jr.name}]")
                for ft in jr.failed_tests:
                    print(ft)
                any_fail_detail = True
            elif jr.name == "analyze":
                # analyze group uses _parse_analyze_issues
                issues = _parse_analyze_issues(jr.output_lines)
                if issues:
                    print(f"\n  [{jr.name}]")
                    for issue in issues:
                        print(issue)
                    any_fail_detail = True
        if not any_fail_detail:
            print(f"  (no individual test details available)")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
