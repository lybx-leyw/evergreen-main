"""scores_data.exe — 成绩数据拉取（CLI 一次性执行）。

用法:
  scores_data.exe --type=scores_transcript   → 成绩单列表(stdout JSON)
  scores_data.exe --type=scores_summary      → GPA 概览 + 成绩单(stdout JSON)

完全移植自 .reference 的 zdbk_service.getTranscript / GpaCalculator / Grade，
认证链路与 courses 一致：CAS 登录 → ZDBK SSO(JSESSIONID + route cookie)。
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

def _make_ssl_ctx():
    # ZJU 服务器使用弱 DH 密钥（< 2048 bits），需降低安全级别；同时不验证证书（内网）。
    ctx = ssl._create_unverified_context()
    try:
        ctx.set_ciphers("DEFAULT:@SECLEVEL=1")
    except Exception:
        pass
    return ctx


_SSL_CONTEXT = _make_ssl_ctx()


def _urlopen(req, timeout=10):
    try:
        return urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
    except Exception:
        return urllib.request.urlopen(req, timeout=timeout,
                                       context=ssl._create_unverified_context())


def _build_opener(cj):
    # 同时挂载 CookieJar（捕获会话 cookie）与降级 SSL 上下文。
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
    # 测试回退：环境变量
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
    # 仅携带 ZDBK 会话 cookie（JSESSIONID[path=/jwglxt] + route），
    # 绝不携带 CAS 的 iPlanetDirectoryPro —— 两者同时存在会让 ZDBK 会话/路由绑定
    # 冲突并返回 HTTP 901（会话失效）。这与参考实现 _zdbkPost 一致。
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


# ── 解析 ──
def _extract_items(html):
    m = re.search(r'"items":\[(.*?)\](?=,"limit")', html, re.DOTALL)
    if not m:
        m = re.search(r'"items":\[(.*?)\](?=,"totalResult")', html, re.DOTALL)
    if not m:
        return []
    try:
        arr = json.loads("[" + m.group(1) + "]")
        return [x for x in arr if isinstance(x, dict)]
    except Exception:
        return []


def _strip_html(s):
    if not s:
        return ""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", s)).strip()


# ── GPA 计算（移植自 Grade / GpaCalculator） ──
_CN_TO_HUNDRED = {
    "A+": 95, "A": 90, "A-": 87, "B+": 83, "B": 80, "B-": 77,
    "C+": 73, "C": 70, "C-": 67, "D": 60, "F": 0,
    "优秀": 90, "良好": 80, "中等": 70, "及格": 60, "不及格": 0,
    "合格": 75, "不合格": 0, "弃修": 0, "缺考": 0, "缓考": 0,
    "待录": 0, "无效": 0,
}
_FIVE_TO_43 = {5.0: 4.3, 4.8: 4.2, 4.5: 4.1, 4.2: 4.0}


def _score_to_five_point(score):
    if score in ("优", "优秀"):
        return 5.0
    if score in ("良", "良好"):
        return 4.0
    if score in ("中", "中等"):
        return 3.0
    if score in ("及格", "合格"):
        return 2.0
    if score in ("不及格", "不合格"):
        return 0.0
    try:
        n = float(score)
    except (TypeError, ValueError):
        return 0.0
    if n >= 90:
        return 5.0
    if n >= 80:
        return 4.0
    if n >= 70:
        return 3.0
    if n >= 60:
        return 2.0
    return 0.0


def _hundred_point(original):
    if original in _CN_TO_HUNDRED:
        return _CN_TO_HUNDRED[original]
    try:
        return int(float(original))
    except (TypeError, ValueError):
        mm = re.search(r"(\d+)", original or "")
        return int(mm.group(1)) if mm else 0


def _is_valid_number(v):
    if isinstance(v, (int, float)):
        return True
    if isinstance(v, str) and v not in (None, "") and _re_num(v):
        return True
    return False


def _re_num(s):
    try:
        float(s)
        return True
    except (TypeError, ValueError):
        return False


def _grade_from_json(j):
    jd_raw = j.get("jd")
    if _is_valid_number(jd_raw):
        try:
            fp = float(jd_raw)
        except (TypeError, ValueError):
            fp = _score_to_five_point(_str(j.get("cj")))
        source = "jd"
    else:
        fp = _score_to_five_point(_str(j.get("cj")))
        source = "fallback"
    original = _str(j.get("cj"))
    credit = _dbl(j.get("xf"))
    five_point = fp
    four_point = _FIVE_TO_43.get(five_point, four_point if five_point <= 4.0 else 4.0) if five_point > 4.0 else five_point
    four_legacy = 4.0 if five_point > 4.0 else five_point
    hundred = _hundred_point(original)
    excluded = original in ("弃修", "待录", "缓考", "无效", "合格", "不合格") or "xtwkc" in _str(j.get("xkkh")) or credit <= 0
    earned = credit if (original not in ("弃修", "待录", "缓考", "无效") and (five_point != 0 or "xtwkc" in _str(j.get("xkkh")))) else 0.0
    return {
        "id": _str(j.get("xkkh")),
        "name": _str(j.get("kcmc"), "未命名课程"),
        "credit": credit,
        "original": original,
        "fivePoint": round(five_point, 2),
        "fourPointGpa": round(four_point, 2),
        "fourPointLegacyGpa": round(four_legacy, 2),
        "hundredPoint": hundred,
        "earnedCredit": round(earned, 2),
        "excluded": excluded,
        "fivePointSource": source,
    }


def _str(v, default=""):
    if v is None:
        return default
    return str(v)


def _dbl(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _compute_gpa(grades):
    # first attempt: 同 realId 取首次
    first = {}
    for g in grades:
        rid = re.sub(r"\(.*\)-.*?-.*$", lambda m: m.group(0).rsplit("-", 1)[0], g["id"]) if "(" in g["id"] else g["id"]
        rid = g["id"][:22] if len(g["id"]) >= 22 else g["id"]
        if rid not in first:
            first[rid] = g
    first_list = list(first.values())
    highest = {}
    for g in grades:
        rid = g["id"][:22] if len(g["id"]) >= 22 else g["id"]
        if rid not in highest or g["fivePoint"] > highest[rid]["fivePoint"]:
            highest[rid] = g
    highest_list = list(highest.values())

    def _avg(lst):
        inc = [g for g in lst if not g["excluded"]]
        if not inc:
            return 0.0
        return round(sum(g["fivePoint"] * g["credit"] for g in inc) /
                     max(sum(g["credit"] for g in inc), 1e-9), 4)

    def _avg_scale(lst, key):
        inc = [g for g in lst if not g["excluded"]]
        if not inc:
            return 0.0
        return round(sum(g[key] * g["credit"] for g in inc) /
                     max(sum(g["credit"] for g in inc), 1e-9), 4)

    domestic = _avg(first_list)
    abroad = _avg(highest_list)
    total_credits = round(sum(g["credit"] for g in grades), 2)
    earned_credits = round(sum(g["earnedCredit"] for g in grades), 2)
    # 分学期 GPA 趋势（替代原 fl_chart 折线趋势图；renderer 的 chart slot
    # 实际指向 DashboardView 卡片网格，无法渲染真实折线，故以分学期表呈现趋势）。
    sem_re = re.compile(r"\((\d{4}-\d{4}-[0-9])\)")
    by_sem = {}
    for g in grades:
        m = sem_re.search(g["id"])
        if not m:
            continue
        by_sem.setdefault(m.group(1), []).append(g)
    semester_gpa = []
    for sem in sorted(by_sem.keys()):
        gl = [g for g in by_sem[sem] if not g["excluded"]]
        if not gl:
            continue
        gpa = round(sum(g["fivePoint"] * g["credit"] for g in gl) /
                    max(sum(g["credit"] for g in gl), 1e-9), 4)
        creds = round(sum(g["earnedCredit"] for g in gl), 2)
        semester_gpa.append({"semester": sem, "gpa": gpa, "credits": creds})
    return {
        "domesticGpa": domestic,
        "abroadGpa": abroad,
        "fourPointGpa": _avg_scale(first_list, "fourPointGpa"),
        "fourPointLegacyGpa": _avg_scale(first_list, "fourPointLegacyGpa"),
        "hundredPointAvg": _avg_scale(first_list, "hundredPoint"),
        "totalCredits": total_credits,
        "earnedCredits": earned_credits,
        "semesterGpa": semester_gpa,
    }


# ── 数据拉取 ──
def fetch_transcript():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    url = ("https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html"
           "?doType=query&queryModel.showCount=5000")
    html = _zdbk_post(cj, op, url)
    items = _extract_items(html)
    if not items:
        # 尝试整体 JSON
        try:
            obj = json.loads(html)
            items = obj.get("items", []) if isinstance(obj, dict) else []
        except Exception:
            items = []
    grades = [_grade_from_json(it) for it in items if it.get("xkkh")]
    return {"grades": grades, "total": len(grades)}


def fetch_summary():
    iplanet = _cas_login()
    cj, op = _zdbk_session(iplanet)
    url = ("https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html"
           "?doType=query&queryModel.showCount=5000")
    html = _zdbk_post(cj, op, url)
    items = _extract_items(html)
    try:
        obj = json.loads(html)
        items = obj.get("items", []) if isinstance(obj, dict) else items
    except Exception:
        pass
    grades = [_grade_from_json(it) for it in items if it.get("xkkh")]
    summary = _compute_gpa(grades)
    return {"summary": summary, "grades": grades, "total": len(grades)}


HANDLERS = {"scores_transcript": fetch_transcript, "scores_summary": fetch_summary}

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
        sys.stderr.write(f"[scores] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
