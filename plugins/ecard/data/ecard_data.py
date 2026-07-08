"""ecard.exe — 一卡通余额（elife.zju.edu.cn BlueWare 校园卡平台，ZJU CAS SSO）。

复刻参考：`.reference/.../features/ecard/`（ecard_provider → getCampusCards, 端点为推测）
复刻目标：`.refer_ui/.../features/ecard/`（单卡余额大号展示）

实现：CAS → elife SSO 跳转获取会话，带 synjones-auth bearer 拉取 getCampusCards。
注：参考实现明确指出该端点为"推测，成功率低"（官方无公开 API）。本插件完整实现认证与
解析链路；若上游端点不可用，优雅返回 unavailable=True 空态（与目标 UI 空态一致），不中断管道。
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


def _elife_session(iplanet):
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    cj.set_cookie(http.cookiejar.Cookie(
        version=0, name="iPlanetDirectoryPro", value=iplanet,
        port=None, port_specified=False,
        domain=".zju.edu.cn", domain_specified=True, domain_initial_dot=True,
        path="/", path_specified=True, secure=True, expires=None,
        discard=False, comment=None, comment_url=None, rest={}))
    op.open(urllib.request.Request("https://elife.zju.edu.cn/",
            headers={"User-Agent": "Mozilla/5.0"}), timeout=15).read()
    return cj, op


def fetch_ecard():
    # 认证失败（缺凭据）属配置错误，硬失败 exit 1；仅余额接口本身不可用时优雅空态。
    iplanet = _cas_login()
    cj, op = _elife_session(iplanet)
    # 提取 synjones-auth token（来自 cookie 或响应头）
    token = None
    for c in cj:
        if c.name.lower().startswith("synjones") or c.name.lower() == "synjones-auth":
            token = c.value
    if not token:
        # 退而求其次：用 elife 的 JSESSIONID 作为会话标识（端点可能接受）
        for c in cj:
            if c.name == "JSESSIONID":
                token = c.value
    hd = {"User-Agent": "Mozilla/5.0",
          "Referer": "https://elife.zju.edu.cn/plat-pc/",
          "X-Requested-With": "XMLHttpRequest",
          "synAccessSource": "pc"}
    if token:
        hd["synjones-auth"] = f"bearer {token}"
    url = "https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards?synAccessSource=pc"
    try:
        resp = op.open(urllib.request.Request(url, headers=hd), timeout=15)
        data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return {"cards": [], "total": 0, "unavailable": True,
                "message": f"余额接口不可用（推测端点）: {e}"}
    cards = []
    node = data.get("data", data)
    raw_cards = node.get("card", []) if isinstance(node, dict) else []
    for c in raw_cards:
        if not isinstance(c, dict):
            continue
        bal = c.get("db_balance", c.get("card_balance", c.get("amount", c.get("total"))))
        try:
            bal = float(bal) / 100.0 if bal is not None else None
        except Exception:
            bal = None
        cards.append({
            "card_name": c.get("name", c.get("card_name", "校园卡")),
            "balance": bal,
            "account": c.get("account", c.get("card_no", c.get("card_number"))),
        })
    return {"cards": cards, "total": len(cards), "unavailable": False}


HANDLERS = {"ecard": fetch_ecard}


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
        sys.stderr.write(f"[ecard] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
