"""quick_connect_data 自包含测试（R3）：
- 模式 A（离线）：校验 _probe 对不可达端口返回 ok=False；对结构校验。
- 模式 B（真实）：用 --project-root 指向本插件目录运行 CLI，校验连通性结构。
"""
import json
import os
import subprocess
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

import quick_connect_data as Q  # noqa: E402


class TestQuickConnectOffline(unittest.TestCase):
    def test_probe_dead_port(self):
        ok, elapsed, msg = Q._probe(1, timeout=0.5)  # 端口 1 几乎必然不可达
        self.assertFalse(ok)
        self.assertGreaterEqual(elapsed, 0)

    def test_cli_unknown_type(self):
        r = subprocess.run(
            [sys.executable, os.path.join(_HERE, "quick_connect_data.py"),
             "--type", "nope", "--project-root", _HERE],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        out = json.loads(r.stdout)
        self.assertIn("error", out)

    def test_cli_real_connectivity_structure(self):
        r = subprocess.run(
            [sys.executable, os.path.join(_HERE, "quick_connect_data.py"),
             "--type", "connectivity", "--project-root", _HERE],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        out = json.loads(r.stdout)
        self.assertIn("services", out)
        self.assertIn("connectedCount", out)
        self.assertIn("totalCount", out)
        self.assertEqual(out["totalCount"], len(out["services"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
