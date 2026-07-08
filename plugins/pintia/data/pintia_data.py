"""pintia_data.exe — PTA(拼题A) 题目集列表（Cookie 登录）。

复刻参考：`.reference/.../features/pintia`（PintiaService）
复刻目标：`.refer_ui/.../features/pintia/`（题目集/成绩）
实现：Pintia 用腾讯云验证码，自动登录不可绕过；策略为读已有的 PTASession
cookie（用户浏览器登录后粘贴到设置），用其访问 problem-sets 接口拉取题目集。
无 PTASession 时优雅返回空列表（与目标 UI 未登录态一致），不中断管道。
"""
import argparse
import json
import os
import ssl
import sys
import urllib.request
import urllib.error

_PROJECT_ROOT = ""

# Pintia CDN/证书可能在打包态下 SSL 协商失败（ASN1 NOT_ENOUGH_DATA），
# 与 ZJU 同理：降低安全级别 + 不验证证书（仅用于拉取题目集元信息）。
def _ssl_ctx():
    ctx = ssl._create_unverified_context()
    try:
        ctx.set_ciphers("DEFAULT:@SECLEVEL=1")
    except Exception:
        pass
    return ctx


def _get_config(key):
    p = os.path.join(_PROJECT_ROOT, ".config_port")
    if os.path.isfile(p):
        try:
            with open(p) as f:
                port = f.read().strip()
            req = urllib.request.Request(f"http://127.0.0.1:{port}/config/settings/{key}")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("value") if isinstance(data, dict) else None
        except Exception:
            return None
    return os.environ.get(key)


def _str(v, default=""):
    return default if v is None else str(v)


def fetch_problem_sets():
    session = _get_config("PTASession")
    if not session:
        # 未配置 session：与目标 UI 未登录态一致，返回空列表（不报错）
        return {"problemSets": [], "total": 0,
                "note": "未配置 PTASession，请在设置中粘贴浏览器登录后的 PTASession cookie"}
    req = urllib.request.Request("https://pintia.cn/api/problem-sets")
    req.add_header("Accept", "application/json")
    req.add_header("Cookie", f"PTASession={session}")
    try:
        with urllib.request.urlopen(req, timeout=15, context=_ssl_ctx()) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {"problemSets": [], "total": 0, "note": "PTASession 已失效，请重新粘贴"}
        raise Exception(f"PTA 接口错误 HTTP {e.code}")
    except Exception as e:
        raise Exception(f"PTA 请求失败: {e}")
    sets = data.get("problemSets") if isinstance(data, dict) else None
    if sets is None and isinstance(data, list):
        sets = data
    if not isinstance(sets, list):
        sets = []
    out = [{
        "id": _str(s.get("id")),
        "title": _str(s.get("title") or s.get("name"), "未命名题集"),
        "problemCount": s.get("problemCount", s.get("problem_count", 0)),
        "submissionCount": s.get("submissionCount", s.get("submission_count", 0)),
    } for s in sets if isinstance(s, dict)]
    return {"problemSets": out, "total": len(out)}


HANDLERS = {"problem_sets": fetch_problem_sets}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)
    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        result = h()
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[pintia] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
