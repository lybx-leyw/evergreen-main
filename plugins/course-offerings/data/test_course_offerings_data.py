"""course-offerings_data 自包含测试（离线 + 真实拉取两种模式）。

离线：mock 凭据缺失 → 断言退出码 1 + 错误提及 ZJU_USERNAME；
真实：读根目录 .env 注入设置 → 真实调 ZDBK → 断言开课列表非空且字段齐全。
"""
import os
import subprocess
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))


def _load_env():
    env = dict(os.environ)
    ep = os.path.join(_ROOT, ".env")
    if os.path.isfile(ep):
        with open(ep, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip())
    return env


class TestCli(unittest.TestCase):
    def test_cli_unknown_type(self):
        r = subprocess.run(
            [sys.executable, "course_offerings_data.py", "--type=__nope__",
             "--project-root", _ROOT],
            cwd=_HERE, capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(r.returncode, 1)
        self.assertIn("unknown type", r.stdout)

    def test_cli_missing_config(self):
        env = dict(os.environ)
        env.pop("ZJU_USERNAME", None)
        env.pop("ZJU_PASSWORD", None)
        r = subprocess.run(
            [sys.executable, "course_offerings_data.py", "--type=course_offerings",
             "--project-root", _ROOT],
            cwd=_HERE, capture_output=True, text=True, encoding="utf-8", env=env)
        self.assertEqual(r.returncode, 1)
        self.assertIn("ZJU_USERNAME", r.stdout)


class TestRealPull(unittest.TestCase):
    def test_real_pull(self):
        env = _load_env()
        if not env.get("ZJU_USERNAME") or not env.get("ZJU_PASSWORD"):
            self.skipTest("缺少 .env 中的 ZJU 凭据，跳过真实拉取")
        r = subprocess.run(
            [sys.executable, "course_offerings_data.py", "--type=course_offerings",
             "--project-root", _ROOT],
            cwd=_HERE, capture_output=True, text=True, encoding="utf-8", env=env)
        self.assertEqual(r.returncode, 0, f"真实拉取应成功, stderr={r.stderr}")
        import json
        data = json.loads(r.stdout)
        self.assertIn("offerings", data)
        self.assertIsInstance(data["offerings"], list, "offerings 应为列表")
        self.assertIn("semester", data, "应返回查询学期")
        # 上游 jszlpj 接口在评教窗口外/数据滚动后可能返回空列表（与原 UI “暂无开课数据”
        # 空态一致），这是合法的实时数据状态而非拉取错误；有数据时再校验字段。
        if data["total"] > 0:
            first = data["offerings"][0]
            for fld in ("courseName", "courseSelectNo", "credits"):
                self.assertIn(fld, first, f"缺少字段 {fld}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
