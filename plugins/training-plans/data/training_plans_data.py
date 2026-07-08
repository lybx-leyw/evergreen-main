"""training_plans_data.exe — 培养方案数据拉取（CLI 一次性执行）。

用法:
  training_plans_data.exe --type=training_plans   → 培养方案列表(stdout JSON)

完全移植自 .reference 的 zdbk_service.getTrainingPlans + training_plan.dart。
认证链路与 scores 一致：CAS 登录 → ZDBK SSO(JSESSIONID + route cookie)。
列表查询前先 GET 索引页建立模块会话（与参考实现一致）。

输出 JSON:
{
  "plans": [ { planNo, pyfaxxId, planName, major, grade, college, level,
               duration, minCredits, earnedCredits, status, remarks } ],
  "total": N
}
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
    _SSL_CONTEXT.set_ciphers("DEFAULT:@SECLEVEL=1")
except Exception:
    pass


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
            url = f"http://127.0.0.1:{port}/config/settings/{key}"
            req = urllib.request.Request(url)
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
    p = _get_config("ZJU_PASSWORD")
    if not u or not p:
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
    pwd_enc = _rsa_encrypt(p, pk["modulus"], pk["exponent"])
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


def _zdbk_session(iplanet):
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    cj.set_cookie(http.cookiejar.Cookie(
        version=0, name="iPlanetDirectoryPro", value=iplanet,
        port=None, port_specified=False,
        domain=".zju.edu.cn", domain_specified=True, domain_initial_dot=True,
        path="/", path_specified=True,
        secure=True, expires=None, discard=False,
        comment=None, comment_url=None, rest={}, rfc2109=False,
    ))
    url = ("https://zjuam.zju.edu.cn/cas/login"
           "?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html")
    r = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    op.open(r, timeout=15).read()
    for c in cj:
        if c.name == "JSESSIONID":
            return cj, op
    raise Exception("ZDBK 登录失败（未获取到 JSESSIONID，可能是教务系统维护中）")


def _zdbk_cookies(cj):
    jsession = None
    route = None
    for c in cj:
        if c.name == "JSESSIONID" and c.path == "/jwglxt":
            jsession = c.value
        elif c.name == "route":
            route = c.value
    return jsession, route


def _zdbk_get(cj, op, url, timeout=15):
    jsession, route = _zdbk_cookies(cj)
    cookie = "; ".join([f"JSESSIONID={jsession}", f"route={route}"]) if (jsession and route) else ""
    hd = {
        "Referer": "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Connection": "close",
    }
    if cookie:
        hd["Cookie"] = cookie
    req = urllib.request.Request(url, headers=hd)
    op.open(req, timeout=timeout).read()


def _zdbk_post(cj, op, url, timeout=15):
    jsession, route = _zdbk_cookies(cj)
    cookie = "; ".join([f"JSESSIONID={jsession}", f"route={route}"]) if (jsession and route) else ""
    hd = {
        "Referer": "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
        "Connection": "close",
    }
    if cookie:
        hd["Cookie"] = cookie
    req = urllib.request.Request(url, data=b"", headers=hd)
    resp = op.open(req, timeout=timeout)
    return resp.read().decode("utf-8")


def _first_of(j, keys):
    for k in keys:
        v = j.get(k)
        if v is not None and str(v).strip() != "":
            return str(v)
    return None


def _dbl(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _extract_items(html):
    m = re.search(r'"items":\[(.*?)\](?=,"limit")', html, re.DOTALL)
    if not m:
        m = re.search(r'"items":\[(.*?)\](?=,"totalResult")', html, re.DOTALL)
    if not m:
        m = re.search(r'"items":\[(.*?)\]', html, re.DOTALL)
    if not m:
        return []
    try:
        arr = json.loads("[" + m.group(1) + "]")
        return [x for x in arr if isinstance(x, dict)]
    except Exception:
        return []


def _plan_from_json(j):
    return {
        "planNo": _first_of(j, ["jxjhh", "pyfaxx_id", "pyfabh", "planNo"]),
        "pyfaxxId": _first_of(j, ["pyfaxx_id"]),
        "planName": _first_of(j, ["pyfamc"]) or "未命名方案",
        "major": _first_of(j, ["zymc", "zymc_mc", "major", "zy_mc"]),
        "grade": _first_of(j, ["synj", "nj", "grade"]),
        "college": _first_of(j, ["xy", "xymc", "kkxy", "xy_mc", "college", "dept"]),
        "level": _first_of(j, ["pycc"]),
        "duration": _first_of(j, ["xz"]),
        "minCredits": _dbl(j.get("minxf")),
        "earnedCredits": _dbl(j.get("yxxf")),
        "status": _first_of(j, ["zt"]),
        "remarks": _first_of(j, ["bz"]),
    }


def fetch_training_plans():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    # 先 GET 索引页建立模块会话（与参考 getTrainingPlans 一致）
    idx = ("https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html"
           "?gnmkdm=N153020&layout=default")
    try:
        _zdbk_get(cj, op, idx)
    except Exception:
        pass
    url = ("https://zdbk.zju.edu.cn/jwglxt/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html"
           "?gnmkdm=N153020&layout=default&doType=query&queryModel.showCount=5000")
    html = _zdbk_post(cj, op, url)
    items = _extract_items(html)
    if not items:
        try:
            obj = json.loads(html)
            items = (obj.get("items") or obj.get("data") or []) if isinstance(obj, dict) else []
        except Exception:
            items = []
    plans = [_plan_from_json(it) for it in items]
    return {"plans": plans, "total": len(plans)}


HANDLERS = {"training_plans": fetch_training_plans}

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
        sys.stderr.write(f"[training-plans] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
