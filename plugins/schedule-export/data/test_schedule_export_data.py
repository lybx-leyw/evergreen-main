"""schedule_export_data 自包含测试。
模式 A：无凭据时 CLI 报配置缺失错误（exit 1）。
模式 B：有 .env 凭据时真实拉取 ZDBK 课表并生成 .ics 落盘。
"""
import json
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))


def _load_env():
    env_path = os.path.join(_ROOT, ".env")
    if not os.path.isfile(env_path):
        return
    with open(env_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _run(args):
    return subprocess.run([sys.executable, os.path.join(_HERE, "schedule_export_data.py"), *args],
                          capture_output=True, text=True, cwd=_HERE)


def test_cli_unknown_type():
    r = _run(["--type", "nope", "--project-root", _ROOT])
    assert r.returncode == 1
    assert "error" in json.loads(r.stdout)


def test_cli_missing_config():
    saved = {k: os.environ.pop(k, None) for k in ("ZJU_USERNAME", "ZJU_PASSWORD")}
    try:
        r = _run(["--type", "schedule_export", "--project-root", _ROOT])
        assert r.returncode == 1
        assert "error" in json.loads(r.stdout)
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v


def test_real_pull():
    _load_env()
    if not os.environ.get("ZJU_USERNAME") or not os.environ.get("ZJU_PASSWORD"):
        print("[SKIP] 无 .env 凭据，跳过真实拉取")
        return
    r = _run(["--type", "schedule_export", "--project-root", _ROOT])
    assert r.returncode == 0, f"stderr={r.stderr}, stdout={r.stdout[:200]}"
    obj = json.loads(r.stdout)
    assert "export" in obj and isinstance(obj["export"], dict)
    assert os.path.isfile(obj["export"]["path"]), "应生成 .ics 文件"


if __name__ == "__main__":
    test_cli_unknown_type(); print("[PASS] test_cli_unknown_type")
    test_cli_missing_config(); print("[PASS] test_cli_missing_config")
    test_real_pull(); print("[PASS] test_real_pull")
    print("全部 schedule-export 测试通过 ✅")
