"""scheduler_data 自包含测试（R3）：
- 模式 A（离线）：直接调用 _schedule，校验返回结构与算法正确性。
- 模式 B（真实）：用 --project-root 指向本插件目录，运行 CLI 校验 stdout JSON。
"""
import json
import os
import subprocess
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

import scheduler_data as S  # noqa: E402


class TestSchedulerOffline(unittest.TestCase):
    def test_demo_schedule_has_blocks(self):
        res = S.fetch_scheduler_plan()
        self.assertTrue(res["isValid"])
        self.assertGreaterEqual(res["taskCount"], 1)
        self.assertIsInstance(res["blocks"], list)
        for b in res["blocks"]:
            self.assertIn("startTime", b)
            self.assertIn("endTime", b)
            self.assertIn("description", b)
            self.assertIn("isRest", b)

    def test_deadline_ordering(self):
        tasks = [
            {"id": "a", "description": "早截止", "timeNeededMinutes": 30, "deadline": "2026-07-08T10:00"},
            {"id": "b", "description": "晚截止", "timeNeededMinutes": 30, "deadline": "2026-07-09T10:00"},
        ]
        blocks = S._schedule(tasks)["blocks"]
        tasks_blocks = [b for b in blocks if not b["isRest"]]
        self.assertEqual(tasks_blocks[0]["description"], "早截止")
        self.assertEqual(tasks_blocks[1]["description"], "晚截止")

    def test_cli_unknown_type(self):
        r = subprocess.run(
            [sys.executable, os.path.join(_HERE, "scheduler_data.py"),
             "--type", "nope", "--project-root", _HERE],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        out = json.loads(r.stdout)
        self.assertIn("error", out)

    def test_cli_real_plan(self):
        r = subprocess.run(
            [sys.executable, os.path.join(_HERE, "scheduler_data.py"),
             "--type", "scheduler_plan", "--project-root", _HERE],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        out = json.loads(r.stdout)
        self.assertTrue(out["isValid"])
        self.assertGreaterEqual(out["taskCount"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
