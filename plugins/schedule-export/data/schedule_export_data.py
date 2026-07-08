"""schedule_export.exe — 课表导出（由 ZDBK 课表生成 iCalendar .ics 文件，纯本地写文件）。

复刻参考：`.reference/.../features/schedule/`（icalExportProvider 由 Course 派生 ICalExporter）
复刻目标：`.refer_ui/.../features/schedule/`（导出进度 + 成功卡片显示 .ics 路径）

实现（R6 换法复刻）：renderer 无"文件导出"交互槽，故本插件在 .exe 内完成课表→.ics 生成并
落盘到 .greenix/schedule/export.ics，data-table 回显导出结果（路径/课程数），复刻"导出并查看"价值。
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
from datetime import date, timedelta, datetime, time


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


def _zdbk_session(iplanet):
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    cj.set_cookie(http.cookiejar.Cookie(
        version=0, name="iPlanetDirectoryPro", value=iplanet,
        port=None, port_specified=False,
        domain=".zju.edu.cn", domain_specified=True, domain_initial_dot=True,
        path="/", path_specified=True, secure=True, expires=None,
        discard=False, comment=None, comment_url=None, rest={}))
    url = ("https://zjuam.zju.edu.cn/cas/login"
           "?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html")
    op.open(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}),
            timeout=15).read()
    for c in cj:
        if c.name == "JSESSIONID":
            return cj, op
    raise Exception("ZDBK 登录失败（未获取到 JSESSIONID）")


def _zdbk_post(cj, op, url, body=b"", timeout=15):
    jsession = route = None
    for c in cj:
        if c.name == "JSESSIONID" and c.path == "/jwglxt":
            jsession = c.value
        elif c.name == "route":
            route = c.value
    cookie = "; ".join([f"JSESSIONID={jsession}" if jsession else "",
                        f"route={route}" if route else ""]).strip("; ")
    hd = {"User-Agent": "Mozilla/5.0",
          "Referer": "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html",
          "Accept": "application/json, text/javascript, */*; q=0.01",
          "X-Requested-With": "XMLHttpRequest"}
    if cookie:
        hd["Cookie"] = cookie
    req = urllib.request.Request(url, data=body, headers=hd)
    return op.open(req, timeout=timeout).read().decode("utf-8")


# ZJU 节次时间表（起始/结束 HH:MM）
_PERIOD_TIMES = {
    1: ("08:00", "08:45"), 2: ("08:55", "09:40"),
    3: ("10:00", "10:45"), 4: ("10:55", "11:40"),
    5: ("14:00", "14:45"), 6: ("14:55", "15:40"),
    7: ("16:00", "16:45"), 8: ("16:55", "17:40"),
    9: ("19:00", "19:45"), 10: ("19:50", "20:35"), 11: ("20:40", "21:25"),
}


def _semester_start():
    today = date.today()
    if today.month >= 9:
        return date(today.year, 9, 1)
    return date(today.year, 2, 23)


def _ical_dt(d):
    return d.strftime("%Y%m%dT%H%M%S")


def _build_ics(sessions):
    sem = _semester_start()
    # 将开学日对齐到周一
    monday = sem - timedelta(days=sem.weekday())
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Evergreen//Schedule Export//CN",
             "CALSCALE:GREGORIAN"]
    count = 0
    for s in sessions:
        dow = int(s.get("dayOfWeek", 1))
        periods = s.get("periods", [1])
        start_p = periods[0]
        end_p = periods[-1]
        st, _ = _PERIOD_TIMES.get(start_p, ("08:00", "08:45"))
        _, et = _PERIOD_TIMES.get(end_p, ("08:45", "08:45"))
        day = monday + timedelta(days=(dow - 1) + 7 * count // max(len(sessions), 1))
        # 每周重复：用 RRULE 表达（简化：首周日期 + 每周）
        dt_start = datetime.combine(day, _parse_time(st))
        dt_end = datetime.combine(day, _parse_time(et))
        lines += [
            "BEGIN:VEVENT",
            f"UID:evergreen-{count}@zju",
            f"DTSTART:{_ical_dt(dt_start)}",
            f"DTEND:{_ical_dt(dt_end)}",
            f"RRULE:FREQ=WEEKLY;COUNT=16",
            f"SUMMARY:{s.get('courseName','课程')}",
            f"LOCATION:{s.get('location','')}",
            "END:VEVENT",
        ]
        count += 1
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines)


def _parse_time(hhmm):
    from datetime import time
    h, m = hhmm.split(":")
    return time(int(h), int(m))


def _extract_balanced(html, key):
    """提取 "key": [ ... ] 中括号配平的 JSON 数组（应对 kbList 嵌套对象）。"""
    idx = html.find(f'"{key}"')
    if idx < 0:
        return None
    i = html.find("[", idx)
    if i < 0:
        return None
    depth = 0
    for j in range(i, len(html)):
        if html[j] == "[":
            depth += 1
        elif html[j] == "]":
            depth -= 1
            if depth == 0:
                return html[i:j + 1]
    return None


def fetch_schedule_export():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    now = date.today()
    year = now.year if now.month >= 9 else now.year - 1
    body = urllib.parse.urlencode({"xnm": str(year), "xqm": "12"}).encode("utf-8")
    html = _zdbk_post(cj, op,
                      "https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html", body=body)
    arr = _extract_balanced(html, "kbList")
    sessions = []
    if arr:
        for it in json.loads(arr):
            if not it.get("kcb"):
                continue
            kcb = it["kcb"]
            parts = kcb.split("<br>")
            nm = parts[0].strip() if parts else "?"
            t = parts[2].strip() if len(parts) >= 3 else ""
            loc = (parts[3].split("zwf")[0].strip()) if len(parts) >= 4 else ""
            sessions.append({
                "courseName": nm, "teacher": t, "location": loc,
                "dayOfWeek": int(it.get("xqj", 1)),
                "periods": list(range(int(it.get("djj", 1)),
                                     int(it.get("djj", 1)) + int(it.get("skcd", 1)))),
            })
    ics = _build_ics(sessions)
    out_dir = os.path.join(_PROJECT_ROOT, ".greenix", "schedule")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "export.ics")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(ics)
    return {
        "export": {
            "path": out_path,
            "courseCount": len(sessions),
            "icsPreview": ics[:300],
        },
        "total": 1,
    }


HANDLERS = {"schedule_export": fetch_schedule_export}


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
        sys.stderr.write(f"[schedule-export] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
