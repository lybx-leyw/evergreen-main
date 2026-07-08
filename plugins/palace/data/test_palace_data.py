"""palace_data 自包含测试（R3）：
- 模式 A（离线）：构造临时 .greenix/palace/events 文件，校验解析与读取。
- 模式 B（真实）：无事件目录时返回空列表（优雅降级），CLI 结构正确。
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
import shutil

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

import palace_data as P  # noqa: E402


class TestPalaceOffline(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        P._PROJECT_ROOT = self.tmp
        ev_dir = os.path.join(self.tmp, ".greenix", "palace", "events", "2026", "07")
        os.makedirs(ev_dir, exist_ok=True)
        with open(os.path.join(ev_dir, "e1.md"), "w", encoding="utf-8") as f:
            f.write("---\ntype: lesson\ntitle: 测试事件\ntags: a,b\n---\n正文内容\n")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_parse_frontmatter(self):
        fm, body = P._parse_frontmatter("---\ntype: thought\ntitle: x\n---\nhello")
        self.assertEqual(fm["type"], "thought")
        self.assertEqual(fm["title"], "x")
        self.assertEqual(body, "hello")

    def test_read_events(self):
        res = P.fetch_palace_events()
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["events"][0]["title"], "测试事件")
        self.assertEqual(res["events"][0]["type"], "lesson")

    def test_empty_dir(self):
        P._PROJECT_ROOT = tempfile.mkdtemp()
        res = P.fetch_palace_events()
        self.assertEqual(res["total"], 0)
        self.assertEqual(res["events"], [])

    def test_cli_unknown_type(self):
        r = subprocess.run(
            [sys.executable, os.path.join(_HERE, "palace_data.py"),
             "--type", "nope", "--project-root", _HERE],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        out = json.loads(r.stdout)
        self.assertIn("error", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
