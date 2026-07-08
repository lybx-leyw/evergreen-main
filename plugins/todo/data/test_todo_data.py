"""todo_data 自包含测试。

模式 A（离线结构校验）：无凭据时，断言 CLI 能正确报出配置缺失错误（exit 1 + error JSON）。
模式 B（真实拉取）：若项目根存在 .env（ZJU_USERNAME/ZJU_PASSWORD），注入环境变量后
真实调用 courses 接口聚合待办，断言管道成功且返回结构合法。

运行: python test_todo_data.py
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
    return subprocess.run(
        [sys.executable, os.path.join(_HERE, "todo_data.py"), *args],
        capture_output=True, text=True, cwd=_HERE,
    )


def test_cli_unknown_type():
    r = _run(["--type", "nope", "--project-root", _ROOT])
    assert r.returncode == 1, f"未知 type 应 exit 1, got {r.returncode}: {r.stdout}"
    obj = json.loads(r.stdout)
    assert "error" in obj, f"应返回 error JSON, got {r.stdout}"


def test_cli_missing_config():
    saved = {k: os.environ.pop(k, None) for k in ("ZJU_USERNAME", "ZJU_PASSWORD")}
    try:
        r = _run(["--type", "todos", "--project-root", _ROOT])
        assert r.returncode == 1, f"无凭据应 exit 1, got {r.returncode}: {r.stdout}"
        obj = json.loads(r.stdout)
        assert "error" in obj, f"应返回 error, got {r.stdout}"
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v


def test_real_pull():
    _load_env()
    if not os.environ.get("ZJU_USERNAME") or not os.environ.get("ZJU_PASSWORD"):
        print("[SKIP] 无 .env 凭据，跳过真实拉取测试")
        return
    r = _run(["--type", "todos", "--project-root", _ROOT])
    assert r.returncode == 0, f"真实拉取应成功, stderr={r.stderr}, stdout={r.stdout[:300]}"
    obj = json.loads(r.stdout)
    assert "todos" in obj, f"响应缺少 todos: {r.stdout[:300]}"
    assert isinstance(obj["todos"], list), "todos 应为列表"
    assert "total" in obj, f"响应缺少 total: {r.stdout[:300]}"
    if obj["todos"]:
        t0 = obj["todos"][0]
        for key in ("id", "title", "courseName", "type", "deadline"):
            assert key in t0, f"todo 缺少字段 {key}: {t0}"


if __name__ == "__main__":
    test_cli_unknown_type()
    print("[PASS] test_cli_unknown_type")
    test_cli_missing_config()
    print("[PASS] test_cli_missing_config")
    test_real_pull()
    print("[PASS] test_real_pull")
    print("全部 todo 测试通过 ✅")
