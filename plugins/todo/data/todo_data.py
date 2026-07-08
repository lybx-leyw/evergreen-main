"""todo.exe — 待办（聚合学在浙大课程作业/考试，无需 PTA Cookie 也可运行）。

复刻参考：`.reference/.../features/todo/`（todoListProvider 聚合 courses + pintia）
复刻目标：`.refer_ui/.../features/todo/`（卡片列表 + 平台筛选 + 优先级色条）

实现（R6 换法复刻）：PTA 题集需用户粘贴 PTASession Cookie，无法在无凭据时复刻，
故本插件复刻"学在浙大"来源的作业/考试待办（courses SSO 实时拉取），
pintia 来源留待用户配置 Cookie 后扩展。渲染用 data-table（renderer 无 list slot）。
"""
import argparse
import json
import os
import re
import ssl
import sys
import urllib.request
import urllib.parse
import http.cookiejar


_PROJECT_ROOT = ""

_SSL_CONTEXT = ssl._create_unverified_context()
try:
    _SSL_CONTEXT.set_ciphers("ALL:@SECLEVEL=0")
except Exception:
    pass


def _urlopen(req, timeout=10):
    try:
        return urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
    except Exception:
        ctx = ssl._create_unverified_context()
        try:
            ctx.set_ciphers("ALL:@SECLEVEL=0")
        except Exception:
            pass
        return urllib.request.urlopen(req, timeout=timeout, context=ctx)


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


def _build_opener(cj):
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=_SSL_CONTEXT),
        urllib.request.HTTPRedirectHandler(),
    )


def _rsa_encrypt(plaintext, modulus_hex, exponent_hex):
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    m = int(plaintext.encode("utf-8").hex(), 16)
    if m >= n:
        raise ValueError("Message too large")
    h = hex(pow(m, e, n))[2:]
    return "0" + h if len(h) % 2 else h


def _cas_login():
    u = _get_config("ZJU_USERNAME")
    pw = _get_config("ZJU_PASSWORD")
    if not u or not pw:
        raise Exception("未设置学号/密码（请在设置中配置 ZJU_USERNAME 和 ZJU_PASSWORD）")
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    hd = {"User-Agent": "Mozilla/5.0"}
    r1 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login", headers=hd)
    b1 = op.open(r1, timeout=15).read().decode("utf-8")
    m = re.search(r'name="execution"\s+value="([^"]+)"', b1)
    if not m:
        raise Exception("CAS 登录页结构异常（execution token 未找到，可能页面已更新）")
    execution = m.group(1)
    r2 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/v2/getPubKey", headers=hd)
    pk = json.loads(op.open(r2, timeout=10).read().decode("utf-8"))
    pwd_enc = _rsa_encrypt(pw, pk["modulus"], pk["exponent"])
    body = (f"username={urllib.parse.quote(u)}"
            f"&password={urllib.parse.quote(pwd_enc)}"
            f"&execution={urllib.parse.quote(execution)}"
            f"&_eventId=submit&rememberMe=true")
    r4 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login",
                                data=body.encode("utf-8"),
                                headers={"Content-Type": "application/x-www-form-urlencoded", **hd})
    op.open(r4, timeout=15).read()
    for c in cj:
        if c.name == "iPlanetDirectoryPro":
            return c.value
    raise Exception("登录失败：学号或密码错误（未获取到 CAS 会话凭证）")


def _courses_session(iplanet):
    """courses.zju.edu.cn 独立 SSO：用 iPlanet 触发 /user/index 的 CAS→Keycloak 跳转链，
    捕获 courses 专用 session cookie（op.open 自动带上 CookieJar）。"""
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    cj.set_cookie(http.cookiejar.Cookie(
        version=0, name="iPlanetDirectoryPro", value=iplanet,
        port=None, port_specified=False,
        domain=".zju.edu.cn", domain_specified=True, domain_initial_dot=True,
        path="/", path_specified=True, secure=True, expires=None,
        discard=False, comment=None, comment_url=None, rest={}))
    hd = {"User-Agent": "Mozilla/5.0"}
    req = urllib.request.Request("https://courses.zju.edu.cn/user/index", headers=hd)
    try:
        op.open(req, timeout=15).read()
    except Exception as e:
        raise Exception(f"courses SSO 跳转失败: {e}")
    return cj, op


def _has_deadline(a):
    for k in ("deadline", "end_time", "endTime", "due_date", "dueDate"):
        if a.get(k):
            return True
    return False


def fetch_todos():
    iplanet = _cas_login()
    cj, op = _courses_session(iplanet)
    hd = {"User-Agent": "Mozilla/5.0", "Content-Type": "application/json"}
    req = urllib.request.Request("https://courses.zju.edu.cn/api/my-courses", headers=hd)
    try:
        data = json.loads(op.open(req, timeout=15).read().decode("utf-8"))
    except Exception as e:
        raise Exception(f"获取课程列表失败: {e}")
    courses = data.get("courses", data.get("data", []))
    todos = []
    for c in courses:
        cid = c.get("id")
        if not cid:
            continue
        areq = urllib.request.Request(f"https://courses.zju.edu.cn/api/courses/{cid}/activities", headers=hd)
        try:
            ad = json.loads(op.open(areq, timeout=15).read().decode("utf-8"))
        except Exception:
            continue
        acts = ad.get("activities", ad.get("data", []))
        if isinstance(acts, dict):
            acts = acts.get("activities", [])
        for a in acts:
            if not isinstance(a, dict):
                continue
            t = str(a.get("type", "")).lower()
            if t not in ("homework", "exam", "interactive", "assignment") and not _has_deadline(a):
                continue
            deadline = (a.get("deadline") or a.get("end_time") or a.get("endTime")
                        or a.get("due_date") or a.get("dueDate") or "")
            todos.append({
                "id": str(a.get("id", "")),
                "title": a.get("title", a.get("name", "")),
                "courseName": c.get("name", ""),
                "type": t or "homework",
                "deadline": deadline,
                "isSubmitted": bool(a.get("is_submitted")
                                    or str(a.get("submission_status", "")).lower() == "submitted"),
                "source": "courses",
            })
    todos.sort(key=lambda x: x.get("deadline") or "9999")
    return {"todos": todos, "total": len(todos)}


HANDLERS = {"todos": fetch_todos}


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
        sys.stderr.write(f"[todo] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
