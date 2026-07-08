"""autosign.exe — 自动签到（courses.zju.edu.cn 雷达签到轮询 + 自动应答，纯 JSON 代理）。

复刻参考：`.reference/.../features/autosign/`（AutosignService 每 4s 轮询 radar/rollcalls）
复刻目标：`.refer_ui/.../features/autosign/`（控制面板 + 日志流）

实现（R6 换法复刻）：renderer 无"后台定时进程"槽，故本插件复刻"单次主动轮询+签到"能力——
拉取当前进行中的签到，植入参考实现中的固定坐标应答，返回签到日志；持续性后台调度由运行态负责。
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
from datetime import datetime


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


def _build_opener(cj):
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=_SSL_CONTEXT),
        urllib.request.HTTPRedirectHandler(),
    )


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
    b1 = op.open(urllib.request.Request("https://zjuam.zju.edu.cn/cas/login", headers=hd),
                 timeout=15).read().decode("utf-8")
    m = re.search(r'name="execution"\s+value="([^"]+)"', b1)
    if not m:
        raise Exception("CAS 登录页结构异常（execution token 未找到）")
    execution = m.group(1)
    pk = json.loads(op.open(urllib.request.Request("https://zjuam.zju.edu.cn/cas/v2/getPubKey",
                                                   headers=hd), timeout=10).read().decode("utf-8"))
    pwd_enc = _rsa_encrypt(pw, pk["modulus"], pk["exponent"])
    body = (f"username={urllib.parse.quote(u)}&password={urllib.parse.quote(pwd_enc)}"
            f"&execution={urllib.parse.quote(execution)}&_eventId=submit&rememberMe=true")
    r4 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login", data=body.encode("utf-8"),
                                headers={"Content-Type": "application/x-www-form-urlencoded", **hd})
    op.open(r4, timeout=15).read()
    for c in cj:
        if c.name == "iPlanetDirectoryPro":
            return c.value
    raise Exception("登录失败：学号或密码错误（未获取到 CAS 会话凭证）")


def _courses_session(iplanet):
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    cj.set_cookie(http.cookiejar.Cookie(
        version=0, name="iPlanetDirectoryPro", value=iplanet,
        port=None, port_specified=False,
        domain=".zju.edu.cn", domain_specified=True, domain_initial_dot=True,
        path="/", path_specified=True, secure=True, expires=None,
        discard=False, comment=None, comment_url=None, rest={}))
    op.open(urllib.request.Request("https://courses.zju.edu.cn/user/index",
            headers={"User-Agent": "Mozilla/5.0"}), timeout=15).read()
    return cj, op


# 参考实现中植入的固定坐标（杭州紫金港附近）
_FAKE_COORDS = [120.089136, 30.302331]


def fetch_autosign():
    iplanet = _cas_login()
    cj, op = _courses_session(iplanet)
    hd = {"User-Agent": "Mozilla/5.0", "Content-Type": "application/json",
          "Accept": "application/json, text/plain, */*"}
    logs = []
    now = datetime.now().strftime("%H:%M:%S")
    try:
        resp = op.open(urllib.request.Request(
            "https://courses.zju.edu.cn/api/radar/rollcalls", headers=hd), timeout=15)
        data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        logs.append({"time": now, "message": f"查询签到失败: {e}"})
        return {"logs": logs, "signed": 0, "total": 0}
    rollcalls = data.get("rollcalls", data.get("data", []))
    if not isinstance(rollcalls, list):
        rollcalls = []
    signed = 0
    for rc in rollcalls:
        rid = rc.get("id") or rc.get("rollcallId")
        name = rc.get("name", rc.get("courseName", "签到"))
        if not rid:
            continue
        try:
            put_url = (f"https://courses.zju.edu.cn/api/rollcall/{rid}/answer"
                       f"?api_version=1.1.2")
            put_body = json.dumps({
                "deviceId": "evergreen-auto",
                "latitude": _FAKE_COORDS[1], "longitude": _FAKE_COORDS[0],
                "accuracy": 68,
            }).encode("utf-8")
            preq = urllib.request.Request(put_url, data=put_body,
                                          headers={**hd, "Content-Type": "application/json"})
            op.open(preq, timeout=15).read()
            logs.append({"time": datetime.now().strftime("%H:%M:%S"),
                         "message": f"✅ 已签到：{name}"})
            signed += 1
        except Exception as e:
            logs.append({"time": datetime.now().strftime("%H:%M:%S"),
                         "message": f"❌ 签到失败 {name}: {e}"})
    if not rollcalls:
        logs.append({"time": now, "message": "当前无进行中的签到（空闲）"})
    return {"logs": logs, "signed": signed, "total": len(rollcalls)}


HANDLERS = {"autosign": fetch_autosign}


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
        sys.stderr.write(f"[autosign] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
