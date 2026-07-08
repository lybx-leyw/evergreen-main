"""downloads.exe — 下载管理（列出学在浙大课程资料/作业附件，纯 JSON API 代理）。

复刻参考：`.reference/.../features/downloads/`（download_provider 读课程 activities 资料/附件）
复刻目标：`.refer_ui/.../features/downloads/`（课程下拉 + 文件卡片列表 + 下载进度）

实现：courses SSO 实时拉取每门课 activities，抽取 material.uploads[] 与 homework.attachments[]
的 {name,size,url}，由 data-table 呈现；实际二进制下载由运行态触发（插件仅代理清单）。
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
    hd = {"User-Agent": "Mozilla/5.0"}
    op.open(urllib.request.Request("https://courses.zju.edu.cn/user/index", headers=hd),
            timeout=15).read()
    return cj, op


def _collect_files(acts):
    files = []
    if isinstance(acts, dict):
        acts = acts.get("activities", [])
    for a in acts:
        if not isinstance(a, dict):
            continue
        t = str(a.get("type", "")).lower()
        if t == "material":
            for up in a.get("uploads", []):
                files.append(up)
        elif t == "homework":
            for up in a.get("attachments", []):
                files.append(up)
    return files


def fetch_downloads():
    iplanet = _cas_login()
    cj, op = _courses_session(iplanet)
    hd = {"User-Agent": "Mozilla/5.0", "Content-Type": "application/json"}
    data = json.loads(op.open(urllib.request.Request(
        "https://courses.zju.edu.cn/api/my-courses", headers=hd), timeout=15).read().decode("utf-8"))
    courses = data.get("courses", data.get("data", []))
    out = []
    for c in courses:
        cid = c.get("id")
        if not cid:
            continue
        try:
            ad = json.loads(op.open(urllib.request.Request(
                f"https://courses.zju.edu.cn/api/courses/{cid}/activities", headers=hd),
                timeout=15).read().decode("utf-8"))
        except Exception:
            continue
        for f in _collect_files(ad):
            if not isinstance(f, dict):
                continue
            out.append({
                "name": f.get("name", f.get("fileName", "未命名文件")),
                "size": f.get("size", f.get("fileSize", "")),
                "url": f.get("url", ""),
                "course": c.get("name", ""),
            })
    return {"files": out, "total": len(out)}


HANDLERS = {"downloads": fetch_downloads}


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
        sys.stderr.write(f"[downloads] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
