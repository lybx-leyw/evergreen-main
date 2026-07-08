"""course_offerings_data.exe — 开课情况数据拉取（CLI 一次性执行）。

用法:
  course_offerings_data.exe --type=course_offerings   → 开课列表(stdout JSON)

移植自 .reference 的 zdbk_service.getCourseOfferings。
认证链路：CAS 登录 → ZDBK SSO(JSESSIONID + route cookie)。
参照 courses / scores 已验证范式：CookieJar 挂载于 opener，数据 POST 仅带
JSESSIONID(/jwglxt) + route（绝不带 CAS iPlanet，否则 ZDBK 返回 HTTP 901）。
"""
import argparse
import datetime
import json
import os
import re
import ssl
import sys
import urllib.request
import urllib.parse
import http.cookiejar

_PROJECT_ROOT = ""


def _make_ssl_ctx():
    # ZJU 服务器使用弱 DH 密钥（< 2048 bits），需降低安全级别；同时不验证证书（内网）。
    ctx = ssl._create_unverified_context()
    try:
        ctx.set_ciphers("DEFAULT:@SECLEVEL=1")
    except Exception:
        pass
    return ctx


_SSL_CONTEXT = _make_ssl_ctx()


def _build_opener(cj):
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=_SSL_CONTEXT),
        urllib.request.HTTPRedirectHandler(),
    )


# ── 配置读取：优先 .config_port（生产），回退环境变量/.env（测试） ──
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
    # 将 CAS 会话凭证写入 CookieJar（domain=.zju.edu.cn），确保 CAS→ZDBK 重定向时
    # HTTPCookieProcessor 自动将 iPlanetDirectoryPro 附带到跳转请求，并捕获回写的 JSESSIONID。
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


def _zdbk_post(cj, op, url, timeout=15):
    # 仅携带 ZDBK 会话 cookie（JSESSIONID[path=/jwglxt] + route），绝不携带 CAS iPlanet。
    jsession = None
    route = None
    for c in cj:
        if c.name == "JSESSIONID" and c.path == "/jwglxt":
            jsession = c.value
        elif c.name == "route":
            route = c.value
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


# ── 当前学期区间（与参考实现一致：秋季 code=1，春季 code=2） ──
def _current_semester_range():
    override = os.environ.get("COURSE_OFFERINGS_SEMESTER")
    if override:
        return override
    now = datetime.datetime.now()
    # 与 .refer_ui 原 UI 一致：秋冬(semester=3, code=1) 覆盖 9~12 月与 1~2 月；
    # 春夏(semester=12, code=2) 覆盖 3~8 月。base year 取 Fall 学年起点。
    if now.month >= 9 or now.month <= 2:
        code = 1
        base = now.year if now.month >= 9 else now.year - 1
    else:
        code = 2
        base = now.year - 1
    return f"{base}-{base + 1}-{code}"


def _str(v, default=""):
    if v is None:
        return default
    return str(v)


def _dbl(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def _offering_from_json(j):
    return {
        "courseCode": _str(j.get("kcdm")),
        "courseName": _str(j.get("kcmc"), "未命名课程"),
        "teacher": _str(j.get("jsxm")),
        "location": _str(j.get("skdd")),
        "schedule": _str(j.get("sksj")),
        "credits": _dbl(j.get("xf")),
        "totalHours": _int(j.get("zxss")),
        "college": _str(j.get("kkxy")),
        "courseType": _str(j.get("kcxz")),
        "courseCategory": _str(j.get("kclb")),
        "courseBelong": _str(j.get("kcgs")),
        "academicYear": _str(j.get("xn")),
        "semester": _str(j.get("xxq")),
        "examTime": _str(j.get("kssj")),
        "major": _str(j.get("zymc")),
        "planNo": _str(j.get("jxjhh")),
        "courseSelectNo": _str(j.get("xkkh")),
    }


def fetch_offerings():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    sem = _current_semester_range()
    url = ("https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html"
           f"?gnmkdm=N159035&doType=query&tjksxq={sem}&tjjsxq={sem}"
           "&cxType=jxrw&queryModel.showCount=10000")
    html = _zdbk_post(cj, op, url)
    try:
        obj = json.loads(html)
    except Exception:
        raise Exception("开课情况接口返回非 JSON（可能会话失效或接口变更）")
    items = obj.get("items") if isinstance(obj, dict) else None
    if not isinstance(items, list):
        items = obj.get("data") if isinstance(obj, dict) else []
    if not isinstance(items, list):
        items = []
    offerings = [_offering_from_json(it) for it in items if isinstance(it, dict)]
    return {"offerings": offerings, "semester": sem, "total": len(offerings)}


HANDLERS = {"course_offerings": fetch_offerings}

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
        sys.stderr.write(f"[course-offerings] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
