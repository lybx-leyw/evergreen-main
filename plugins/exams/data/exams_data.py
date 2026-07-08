"""exams_data.exe — 考试日程数据拉取（CLI 一次性执行）。

用法:
  exams_data.exe --type=exams   → 考试列表(stdout JSON)

完全移植自 .reference 的 zdbk_service.getExams + exam.dart(Exam.fromZdbk)。
认证链路与 scores 一致：CAS 登录 → ZDBK SSO(JSESSIONID + route cookie)。

输出 JSON 结构:
{
  "exams": [
    {
      "id": "选课课号",
      "name": "课程名",
      "location": "考场",
      "seatNumber": "座位号",
      "startTime": "2025-08-23T14:00:00",   # ISO8601, 可能为 null
      "endTime":   "2025-08-23T16:40:00",   # 可能为 null
      "date": "2025-08-23",                  # YYYY-MM-DD, 用于日历/排序
      "time": "14:00-16:40",                # 人类可读时间段
      "daysUntil": 7,                        # 距今天数(无时间则为 999)
      "urgency": "critical"                  # past|critical|soon|future
    }
  ],
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


def _urlopen(req, timeout=10):
    try:
        return urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
    except Exception:
        return urllib.request.urlopen(req, timeout=timeout,
                                       context=ssl._create_unverified_context())


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


def _zdbk_post(cj, op, url, timeout=15):
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


# ── ZDBK 时间解析（移植自 exam.dart _parseKssj/_parseJssj） ──
def _safe_dt(year, month, day, hour, minute):
    year = max(2000, min(2100, year))
    month = max(1, min(12, month))
    day = max(1, min(31, day))
    hour = max(0, min(23, hour))
    minute = max(0, min(59, minute))
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:00"


def _parse_kssj(kssj):
    """返回 (start_iso, end_iso, time_range_str)。kssj 形如 '2025年08月23日(14:00-16:40)'。"""
    if not kssj or kssj == "null":
        return None, None, ""
    m = re.search(r'(\d{4})年(\d{1,2})月(\d{1,2})日\((\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})\)', kssj)
    if m:
        y, mo, d, h1, mi1, h2, mi2 = (int(x) for x in m.groups())
        start = _safe_dt(y, mo, d, h1, mi1)
        end = _safe_dt(y, mo, d, h2, mi2)
        return start, end, f"{h1:02d}:{mi1:02d}-{h2:02d}:{mi2:02d}"
    # 退化：仅日期
    m2 = re.search(r'(\d{4})年(\d{1,2})月(\d{1,2})日', kssj)
    if m2:
        y, mo, d = (int(x) for x in m2.groups())
        return _safe_dt(y, mo, d, 0, 0), None, ""
    return None, None, ""


def _days_until(start_iso):
    if not start_iso:
        return 999
    try:
        dt = _parse_iso(start_iso)
    except Exception:
        return 999
    return (dt - _now()).days


def _urgency(days):
    if days < 0:
        return "past"
    if days <= 7:
        return "critical"
    if days <= 30:
        return "soon"
    return "future"


def _parse_iso(s):
    return __import__("datetime").datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")


def _now():
    return __import__("datetime").datetime.now()


def _str(v, default=""):
    if v is None:
        return default
    return str(v)


# ── 解析 ──
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


def _exam_from_json(j):
    kssj = _str(j.get("kssj"))
    jssj = _str(j.get("jssj"))
    start_iso, end_iso, time_range = _parse_kssj(kssj)
    # 若 kssj 解析失败但 jssj 为标准 ISO，则尝试用 jssj
    if start_iso is None and jssj and jssj != "null":
        try:
            start_iso = _parse_iso(jssj).strftime("%Y-%m-%dT%H:%M:%S")
            end_iso = None
            time_range = ""
        except Exception:
            pass
    date = start_iso[:10] if start_iso else ""
    days = _days_until(start_iso)
    return {
        "id": _str(j.get("xkkh")),
        "name": _str(j.get("kcmc"), "未命名考试"),
        "location": _str(j.get("cdmc")),
        "seatNumber": _str(j.get("zwh")),
        "startTime": start_iso,
        "endTime": end_iso,
        "date": date,
        "time": time_range,
        "daysUntil": days,
        "urgency": _urgency(days),
    }


# ── 数据拉取 ──
def fetch_exams():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    url = ("https://zdbk.zju.edu.cn/jwglxt/xskscx/kscx_cxXsgrksIndex.html"
           "?doType=query&queryModel.showCount=5000")
    html = _zdbk_post(cj, op, url)
    items = _extract_items(html)
    if not items:
        try:
            obj = json.loads(html)
            items = obj.get("items", []) if isinstance(obj, dict) else []
        except Exception:
            items = []
    exams = [_exam_from_json(it) for it in items if it.get("xkkh")]
    # 按考试日期升序排序（无日期的排最后）
    exams.sort(key=lambda e: (e["date"] == "", e["date"], e["name"]))
    return {"exams": exams, "total": len(exams)}


HANDLERS = {"exams": fetch_exams}

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
        sys.stderr.write(f"[exams] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
