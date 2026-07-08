"""zdbk_notifications_data.exe — 教务通知数据拉取（CLI 一次性执行）。

用法:
  zdbk_notifications_data.exe --type=zdbk_notifications   → 教务通知列表(stdout JSON)

完全移植自 .reference 的 zdbk_service.getNotifications + parseZdbkNotifications。
认证链路与 scores 一致：CAS 登录 → ZDBK SSO(JSESSIONID + route cookie)。
通知接口为 HTML，需用与参考一致的正则解析（id/title/publisher/publishDate/viewCount/content）。

输出 JSON:
{
  "notifications": [ { id, title, publisher, publishDate, viewCount, content } ],
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


def _strip_html(s):
    if not s:
        return ""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", s)).strip()


# ── 解析（移植自 parseZdbkNotifications） ──
def parse_notifications(html):
    results = []

    item_re = re.compile(
        r'<li>\s*<a[^>]*data-xwbh="([^"]+)"[^>]*>.*?<label>(.*?)</label>',
        re.DOTALL,
    )
    for m in item_re.finditer(html):
        nid = m.group(1) or ""
        title = _strip_html(m.group(2) or "").strip()
        if not nid:
            continue
        results.append({"id": nid, "title": title})

    pane_re = re.compile(
        r'<div[^>]*id="tabNews(\d+)"[^>]*class="tab-pane tab-pane-news"[^>]*>'
        r'(.*?)发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)'
        r'.*?<div class="news_con">(.*?)</div>\s*</div>',
        re.DOTALL,
    )
    i = 0
    for m in pane_re.finditer(html):
        if i >= len(results):
            break
        results[i] = {
            "id": results[i]["id"],
            "title": results[i]["title"],
            "publisher": (m.group(3) or "").strip(),
            "publishDate": (m.group(4) or "").strip(),
            "viewCount": int(m.group(5)) if m.group(5) else None,
            "content": (m.group(6) or "").strip(),
        }
        i += 1

    if i == 0:
        detail_re = re.compile(
            r'发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)',
            re.DOTALL,
        )
        for m in detail_re.finditer(html):
            if i >= len(results):
                break
            results[i] = {
                "id": results[i]["id"],
                "title": results[i]["title"],
                "publisher": (m.group(1) or "").strip(),
                "publishDate": (m.group(2) or "").strip(),
                "viewCount": int(m.group(3)) if m.group(3) else None,
                "content": results[i].get("content"),
            }
            i += 1

    # content 存原始 HTML（明细展示用）；列表展示用纯文本
    for r in results:
        r["contentText"] = _strip_html(r.get("content") or "")
    return results


def fetch_notifications():
    u = _get_config("ZJU_USERNAME")
    if not u:
        raise Exception("未设置学号（请在设置中配置 ZJU_USERNAME）")
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    import time
    t = int(time.time() * 1000)
    url = (f"https://zdbk.zju.edu.cn/jwglxt/xtgl/index_cxTctxNews.html"
           f"?time={t}&gnmkdm=index&su={urllib.parse.quote(u)}")
    html = _zdbk_post(cj, op, url)
    items = parse_notifications(html)
    return {"notifications": items, "total": len(items)}


HANDLERS = {"zdbk_notifications": fetch_notifications}

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
        sys.stderr.write(f"[zdbk-notifications] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
