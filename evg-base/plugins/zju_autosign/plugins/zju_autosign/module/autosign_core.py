#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
autosign_core.py — 学在浙大自动签到 · 共享核心（纯标准库，零第三方依赖）

供两个入口复用：
  - module/worker.py     长驻监控进程（Evergreen module.process，scope=long）
  - data/autosign.py     数据源适配壳（Evergreen data-source，ttl=0s）

功能（移植自 ZJU-live-better-main/courses.zju/autosign.js）：
  1. ZJU 统一认证登录（courses.zju → CAS 跳转 → execution + RSA 密码 → ticket 收尾）
  2. 轮询 GET /api/radar/rollcalls 发现进行中的点名
  3. 雷达点名：优先使用配置地点坐标，失败遍历 12 个已知点位，再三点定位（球面高斯-牛顿）
  4. 数字点名：先读 student_rollcalls 拿现成 code，拿不到则 0000-9999 并发穷举
  5. 结果推送钉钉机器人（可选，支持加签）

平台契约：
  - 凭证一律走 _get_config 三级降级（.greenix/config.json → ConfigHttpServer → 环境变量）
  - 绝不硬编码任何凭证；stdout 只允许输出约定的内容（worker=PORT 行，data=纯 JSON）
  - 日志全部走 stderr
"""
import base64
import hashlib
import hmac
import http.cookiejar
import json
import math
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

# ═══════════════════════════════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════════════════════════════

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0")

COURSES_BASE = "https://courses.zju.edu.cn"
CAS_LOGIN = "https://zjuam.zju.edu.cn/cas/login"
PUBKEY_URL = "https://zjuam.zju.edu.cn/cas/v2/getPubKey"
ROLLCALLS_URL = COURSES_BASE + "/api/radar/rollcalls"
API_VERSION = "1.1.2"

# 已知雷达点位（紫金港/玉泉/之江/华家池），与 autosign.js RadarInfo 一致
RADAR_LOCATIONS = {
    "ZJGD1": [120.089136, 30.302331],   # 紫金港·东一教学楼
    "ZJGX1": [120.085042, 30.30173],    # 紫金港·西教学楼
    "ZJGB1": [120.077135, 30.305142],   # 紫金港·段永平教学楼
    "ZJG4":  [120.073427, 30.299757],   # 紫金港·大西区
    "YQ4":   [120.122176, 30.261555],   # 玉泉·教四
    "YQ1":   [120.123853, 30.262544],   # 玉泉·教一
    "YQ7":   [120.120344, 30.263907],   # 玉泉·教七
    "YQSS":  [120.124001, 30.265735],   # 玉泉·宿舍区
    "ZJ1":   [120.126008, 30.192908],   # 之江校区 1
    "ZJ2":   [120.124267, 30.19139],    # 之江校区 2
    "HJC1":  [120.195939, 30.272068],   # 华家池校区 1
    "HJC2":  [120.198193, 30.270419],   # 华家池校区 2
}

EARTH_R = 6372999.26  # 与原脚本一致

# 脚本所在目录（plugins/<id>/module）
MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_DIR = os.path.dirname(MODULE_DIR)
STATE_PATH = os.path.join(MODULE_DIR, "state.json")


def _log(msg):
    """日志走 stderr，绝不污染 stdout。"""
    try:
        sys.stderr.write("[autosign] %s\n" % msg)
        sys.stderr.flush()
    except Exception:
        pass


def _build_ssl_context():
    """构建 HTTPS 上下文。

    1. 默认证书库损坏（部分 Windows Python 抛 ASN1 错误）→ 降级为不校验并告警；
    2. ZJU 校园服务器使用旧式 TLS（小 DH 参数），现代 OpenSSL 默认拒绝
       （DH_KEY_TOO_SMALL）→ 降低本地安全级别兼容（不影响证书校验）。
    """
    try:
        ctx = ssl.create_default_context()
    except Exception as e:
        _log("系统证书库不可用（%s），本次会话回退为不校验服务器证书" % e)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    try:
        ctx.minimum_version = ssl.TLSVersion.TLSv1
    except Exception:
        pass
    try:
        ctx.set_ciphers("DEFAULT:@SECLEVEL=0")
    except Exception as e:
        _log("设置宽松密码套件失败: %s" % e)
    return ctx


def _now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


# ═══════════════════════════════════════════════════════════════════
# 配置读取：_get_config 三级降级（平台契约，锁定模板勿改语义）
# ═══════════════════════════════════════════════════════════════════

def _get_config(key, default=None):
    """从平台配置读取凭证（三级降级）。找不到时返回 default（不抛错）。"""
    # Tier 1（主）：.greenix/config.json 本地文件（GREENIX_CONFIG_PATH 指定）
    greenix_path = os.environ.get("GREENIX_CONFIG_PATH")
    if greenix_path:
        try:
            p = os.path.join(greenix_path, "config.json") \
                if os.path.isdir(greenix_path) else greenix_path
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                val = cfg.get(key, "")
                if val:
                    return val
        except Exception:
            pass
    # Tier 2（降级）：HTTP 从 ConfigHttpServer 读（.config_port 发现端口）
    try:
        port_file = None
        for base in [os.getcwd(), os.environ.get("PROJECT_ROOT", "."), PLUGIN_DIR]:
            cur = base
            while True:
                pf = os.path.join(cur, ".config_port")
                if os.path.exists(pf):
                    port_file = pf
                    break
                parent = os.path.dirname(cur)
                if parent == cur:
                    break
                cur = parent
            if port_file:
                break
        if port_file:
            with open(port_file, "r") as f:
                port = f.read().strip()
            url = "http://127.0.0.1:%s/config/settings/%s" % (port, key)
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                val = data.get("value", "")
                if val:
                    return val
    except Exception:
        pass
    # Tier 3（兜底）：系统环境变量
    val = os.environ.get(key)
    if val:
        return val
    return default


def load_config():
    """读取全部运行配置，缺省值兜底，绝不抛错。"""
    enabled_raw = _get_config("AUTOSIGN_ENABLED", "true") or "true"
    return {
        "username": (_get_config("ZJU_USERNAME", "") or "").strip(),
        "password": _get_config("ZJU_PASSWORD", "") or "",
        "webhook": (_get_config("DINGTALK_WEBHOOK", "") or "").strip(),
        "secret": (_get_config("DINGTALK_SECRET", "") or "").strip(),
        "enabled": str(enabled_raw).strip().lower() in ("1", "true", "yes", "on"),
        "location": (_get_config("AUTOSIGN_RADAR_LOCATION", "ZJGD1") or "ZJGD1").strip(),
        "interval": _to_int(_get_config("AUTOSIGN_POLL_INTERVAL", "4"), 4),
    }


def _to_int(v, default):
    try:
        return int(str(v).strip())
    except Exception:
        return default


# ═══════════════════════════════════════════════════════════════════
# 钉钉通知（支持加签）
# ═══════════════════════════════════════════════════════════════════

def notify_dingtalk(cfg, msg):
    hook = cfg.get("webhook") or ""
    if not hook:
        return False
    url = hook
    secret = cfg.get("secret") or ""
    if secret:
        ts = str(int(time.time() * 1000))
        sign = base64.b64encode(
            hmac.new(secret.encode("utf-8"), ("%s\n%s" % (ts, secret)).encode("utf-8"),
                     hashlib.sha256).digest()).decode("utf-8")
        url = "%s&timestamp=%s&sign=%s" % (hook, ts, urllib.parse.quote(sign, safe=""))
    body = json.dumps({"msgtype": "text", "text": {"content": msg}},
                      ensure_ascii=False).encode("utf-8")
    try:
        req = urllib.request.Request(
            url, data=body,
            headers={"Content-Type": "application/json", "User-Agent": UA})
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()
        return True
    except Exception as e:
        _log("钉钉推送失败: %s" % e)
        return False


# ═══════════════════════════════════════════════════════════════════
# CAS 登录（移植自 login-zju：courses 跳转 → CAS execution+RSA → ticket 收尾）
# ═══════════════════════════════════════════════════════════════════

class _ManualRedirect(urllib.request.HTTPRedirectHandler):
    """禁止自动跟随重定向：3xx 一律抛 HTTPError，由调用方读取 Location。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class ZJUCoursesSession:
    """学在浙大会话：统一认证登录 + 带 Cookie 的 API 请求。"""

    def __init__(self, username, password):
        self.username = username
        self.password = password
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar),
            urllib.request.HTTPSHandler(context=_build_ssl_context()),
            _ManualRedirect(),
        )
        self.logged_in = False

    # -- 底层请求：follow=True 时手动跟随 3xx（最多 10 跳） --
    def _open(self, url, data=None, method=None, headers=None,
              timeout=30, follow=True):
        hdrs = {"User-Agent": UA}
        if headers:
            hdrs.update(headers)
        current = url
        hops = 10 if follow else 1
        for _ in range(hops):
            req = urllib.request.Request(current, data=data, headers=hdrs, method=method)
            try:
                resp = self.opener.open(req, timeout=timeout)
                return resp.status, resp.headers, resp.read()
            except urllib.error.HTTPError as e:
                code, h, body = e.code, e.headers, e.read()
                if follow and code in (301, 302, 303, 307, 308):
                    loc = h.get("Location")
                    if not loc:
                        return code, h, body
                    current = urllib.parse.urljoin(current, loc)
                    continue
                return code, h, body
        return 0, None, b""  # 重定向过多

    def login(self):
        # ── 1. courses.zju 入口 → 跟随 302 直到 CAS（拿到 service 参数）──
        current = COURSES_BASE + "/user/index"
        reached_cas = False
        for _ in range(12):
            status, h, _body = self._open(current, follow=False)
            if status not in (301, 302, 303, 307, 308):
                raise RuntimeError("courses.zju 未重定向到统一认证（HTTP %s）" % status)
            loc = h.get("Location") if h else None
            if not loc:
                raise RuntimeError("登录重定向链断裂（无 Location）")
            current = urllib.parse.urljoin(current, loc)
            if urllib.parse.urlparse(current).hostname == "zjuam.zju.edu.cn":
                reached_cas = True
                break
        if not reached_cas:
            raise RuntimeError("未能进入统一认证页面")
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(current).query)
        service = (qs.get("service") or [""])[0]

        # ── 2. CAS 登录页：提取 execution，拿 RSA 公钥，提交表单 ──
        full = CAS_LOGIN + "?service=" + urllib.parse.quote(service, safe="")
        status, _h, body = self._open(full)
        html = body.decode("utf-8", "replace")
        m = re.search(r'name="execution"\s+value="([^"]+)"', html)
        if not m:
            raise RuntimeError("CAS 登录页缺少 execution 字段（登录流程可能已变化）")
        execution = m.group(1)

        status, _h, body = self._open(PUBKEY_URL)
        pub = json.loads(body.decode("utf-8", "replace"))
        enc_pwd = _rsa_encrypt(self.password, pub["modulus"], pub["exponent"])

        form = urllib.parse.urlencode({
            "username": self.username,
            "password": enc_pwd,
            "execution": execution,
            "_eventId": "submit",
            "authcode": "",
        }).encode("utf-8")
        status, h, body = self._open(
            full, data=form, method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            follow=False)
        if status == 302:
            loc = h.get("Location") if h else None
            if not loc:
                raise RuntimeError("统一认证登录失败（无跳转地址）")
            current = urllib.parse.urljoin(full, loc)
        elif status == 200:
            text = body.decode("utf-8", "replace")
            msg = re.search(r'<span id="msg">([^<]+)</span>', text)
            raise RuntimeError("统一认证登录失败：%s"
                               % (msg.group(1) if msg else "用户名或密码错误"))
        else:
            raise RuntimeError("统一认证登录失败（HTTP %s）" % status)

        # ── 3. ticket 收尾：跟随重定向 + meta refresh 直到就绪 ──
        for _ in range(16):
            status, h, body = self._open(current, follow=False)
            if status in (301, 302, 303, 307, 308):
                loc = h.get("Location") if h else None
                if not loc:
                    break
                current = urllib.parse.urljoin(current, loc)
                continue
            if status == 200:
                text = body.decode("utf-8", "replace")
                m2 = re.search(
                    r'meta\s+http-equiv="refresh"\s+content="0;\s*URL=([^"]+)"',
                    text, re.IGNORECASE)
                if m2:
                    current = urllib.parse.urljoin(current, m2.group(1))
                    continue
            break

        self.logged_in = True
        _log("登录成功: %s" % self.username)
        return True

    def fetch(self, url, method="GET", body=None, timeout=30):
        """带会话的 API 请求，返回 (status, text)。会话失效时自动重登并重试一次。"""
        if not self.logged_in:
            self.login()
        for attempt in range(2):
            hdrs = {"User-Agent": UA}
            data = None
            if body is not None:
                data = json.dumps(body).encode("utf-8")
                hdrs["Content-Type"] = "application/json"
            status, _h, raw = self._open(url, data=data, method=method,
                                         headers=hdrs, timeout=timeout, follow=False)
            if status in (401, 403) and attempt == 0:
                _log("会话失效（HTTP %s），重新登录后重试" % status)
                self.logged_in = False
                self.login()
                continue
            return status, raw.decode("utf-8", "replace")
        return status, raw.decode("utf-8", "replace")


def _rsa_encrypt(password, modulus_hex, exponent_hex):
    """ZJU CAS RSA 加密密码（教科书式无填充），密文补齐 modulus 位长。
    与 login-zju / jwglxt 实现逐字节一致。"""
    m = int.from_bytes(password.encode("utf-8"), "big")
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    c = pow(m, e, n)
    hex_len = (n.bit_length() + 3) // 4
    return format(c, "x").zfill(hex_len)


# ═══════════════════════════════════════════════════════════════════
# 点名应答
# ═══════════════════════════════════════════════════════════════════

def _uuid():
    return str(uuid.uuid4())


def _distance_of(outcome):
    """从应答结果里提取距离（米）。兼容多种字段路径。"""
    if not isinstance(outcome, dict):
        return None
    for path in (("distance",), ("data", "distance"), ("result", "distance")):
        cur = outcome
        ok = True
        for p in path:
            if not isinstance(cur, dict):
                ok = False
                break
            cur = cur.get(p)
        if ok and isinstance(cur, (int, float)):
            try:
                d = float(cur)
                return d if d > 0 else None
            except Exception:
                return None
    return None


def _radar_answer(session, rid, lon, lat):
    status, text = session.fetch(
        COURSES_BASE + "/api/rollcall/%s/answer?api_version=%s" % (rid, API_VERSION),
        method="PUT",
        body={
            "deviceId": _uuid(),
            "latitude": lat,
            "longitude": lon,
            "speed": None,
            "accuracy": 68,
            "altitude": None,
            "altitudeAccuracy": None,
            "heading": None,
        })
    try:
        return json.loads(text)
    except Exception:
        _log("雷达应答 JSON 解析失败 rid=%s: %s" % (rid, text[:200]))
        return None


def answer_radar(session, rid, configured_xy):
    """雷达点名：配置地点 → 遍历点位 → 三点定位。返回 (ok, how, detail)。"""
    outcomes = []

    # 1. 配置地点
    if configured_xy:
        o = _radar_answer(session, rid, configured_xy[0], configured_xy[1])
        if o and o.get("status_name") == "on_call_fine":
            return True, "configured", configured_xy
        outcomes.append((configured_xy, o))

    # 2. 全部已知点位
    for key, xy in RADAR_LOCATIONS.items():
        o = _radar_answer(session, rid, xy[0], xy[1])
        if o and o.get("status_name") == "on_call_fine":
            return True, "beacon:%s" % key, xy
        outcomes.append((xy, o))

    # 3. 三点定位（球面最小二乘）
    pts = []
    for xy, o in outcomes:
        d = _distance_of(o)
        if d:
            pts.append({"lon": xy[0], "lat": xy[1], "d": d})
    if len(pts) >= 3:
        est = _sphere_fit(pts)
        if est:
            o = _radar_answer(session, rid, est["lon"], est["lat"])
            if o and o.get("status_name") == "on_call_fine":
                return True, "sphere-fit", est
    return False, "failed", None


def _sphere_fit(points):
    """球面三点定位：浮点高斯-牛顿（haversine 距离残差最小化）。"""
    lon0 = sum(p["lon"] for p in points) / len(points)
    lat0 = sum(p["lat"] for p in points) / len(points)

    def haversine(lon, lat, lon_i, lat_i):
        dlon = math.radians(lon_i - lon)
        dlat = math.radians(lat_i - lat)
        a = (math.sin(dlat / 2.0) ** 2 +
             math.cos(math.radians(lat)) * math.cos(math.radians(lat_i)) *
             math.sin(dlon / 2.0) ** 2)
        return 2 * EARTH_R * math.asin(math.sqrt(a))

    def residuals(lon, lat):
        return [p["d"] - haversine(lon, lat, p["lon"], p["lat"]) for p in points]

    def jacobian(lon, lat):
        eps = 1e-9
        base = residuals(lon, lat)
        rl = residuals(lon + eps, lat)
        ra = residuals(lon, lat + eps)
        return [((rl[i] - base[i]) / eps, (ra[i] - base[i]) / eps)
                for i in range(len(points))]

    lon, lat = lon0, lat0
    for _ in range(30):
        r = residuals(lon, lat)
        J = jacobian(lon, lat)
        jtj = [[0.0, 0.0], [0.0, 0.0]]
        jtr = [0.0, 0.0]
        for i in range(len(points)):
            j0, j1 = J[i]
            jtj[0][0] += j0 * j0
            jtj[0][1] += j0 * j1
            jtj[1][0] += j1 * j0
            jtj[1][1] += j1 * j1
            jtr[0] += j0 * r[i]
            jtr[1] += j1 * r[i]
        det = jtj[0][0] * jtj[1][1] - jtj[0][1] * jtj[1][0]
        if abs(det) < 1e-20:
            break
        dlon = (jtj[1][1] * jtr[0] - jtj[0][1] * jtr[1]) / det
        dlat = (-jtj[1][0] * jtr[0] + jtj[0][0] * jtr[1]) / det
        lon += dlon
        lat += dlat
        if abs(dlon) < 1e-12 and abs(dlat) < 1e-12:
            break
    rms = math.sqrt(sum(x * x for x in residuals(lon, lat)) / len(points))
    _log("三点定位估计 lon=%.6f lat=%.6f rms=%.2fm" % (lon, lat, rms))
    return {"lon": lon, "lat": lat, "rms": rms}


def _number_answer(session, rid, code):
    status, text = session.fetch(
        COURSES_BASE + "/api/rollcall/%s/answer_number_rollcall" % rid,
        method="PUT",
        body={"deviceId": _uuid(), "numberCode": code})
    if status == 200:
        try:
            j = json.loads(text)
            if j.get("status") == "on_call" or j.get("id"):
                return True
        except Exception:
            pass
    return False


def get_number_code(session, rid):
    """先尝试直接读取学生点名信息里的现成数字码。"""
    try:
        status, text = session.fetch(
            COURSES_BASE + "/api/rollcall/%s/student_rollcalls" % rid)
        if status == 200:
            j = json.loads(text)
            if isinstance(j, dict) and j.get("number_code"):
                return str(j["number_code"])
    except Exception as e:
        _log("读取数字码失败 rid=%s: %s" % (rid, e))
    return None


def bruteforce_number(session, rid):
    """0000-9999 并发穷举数字点名码（分批 200，命中即停）。"""
    found = {"code": None}

    def _try(code):
        if found["code"]:
            return
        try:
            if _number_answer(session, rid, code):
                found["code"] = code
        except Exception:
            pass

    with ThreadPoolExecutor(max_workers=24) as ex:
        for start in range(0, 10000, 200):
            if found["code"]:
                break
            codes = [str(c).zfill(4) for c in range(start, min(start + 200, 10000))]
            futs = [ex.submit(_try, c) for c in codes]
            for _ in as_completed(futs):
                if found["code"]:
                    break
    return found["code"]


# ═══════════════════════════════════════════════════════════════════
# 单轮检查 + 状态持久化
# ═══════════════════════════════════════════════════════════════════

def run_cycle(session, cfg, state):
    """执行一轮：拉取点名列表 → 应答所有进行中的点名 → 更新状态。

    返回新的 state 字典（不原地修改传入对象）。
    """
    state = dict(state)
    state["lastPoll"] = _now()
    state["pollCount"] = int(state.get("pollCount", 0)) + 1
    history = list(state.get("history", []))
    events = []

    status, text = session.fetch(ROLLCALLS_URL)
    if status != 200:
        raise RuntimeError("轮询接口返回 HTTP %s" % status)
    try:
        payload = json.loads(text)
    except Exception:
        raise RuntimeError("轮询接口返回非 JSON: %s" % text[:200])
    rollcalls = payload.get("rollcalls") or []
    if rollcalls:
        _log("发现 %d 个点名" % len(rollcalls))

    for rc in rollcalls:
        rid = rc.get("rollcall_id")
        if not rid:
            continue
        st = rc.get("status") or rc.get("status_name") or ""
        if st in ("on_call_fine", "on_call"):
            continue
        title = rc.get("title", "")
        course = rc.get("course_title", "")
        by = rc.get("created_by_name", "")
        entry = {
            "rid": rid, "title": title, "course": course, "by": by,
            "at": _now(), "type": "unknown", "ok": False, "detail": "",
        }
        if rc.get("is_radar"):
            entry["type"] = "radar"
            ok, how, detail = answer_radar(session, rid, cfg.get("radar_xy"))
            entry["ok"] = ok
            entry["detail"] = "configured" if how == "configured" else how
            msg = "[自动签到] 雷达点名 #%s《%s》%s %s" % (
                rid, course, title, "✅ 已签到（%s）" % how if ok else "❌ 签到失败")
            entry["msg"] = msg
        elif rc.get("is_number"):
            entry["type"] = "number"
            code = get_number_code(session, rid)
            if not code:
                code = bruteforce_number(session, rid)
            entry["ok"] = bool(code)
            entry["detail"] = code or ""
            msg = "[自动签到] 数字点名 #%s《%s》%s %s" % (
                rid, course, title,
                "✅ 已签到（code=%s）" % code if code else "❌ 未找到有效数字码")
            entry["msg"] = msg
        else:
            msg = "[自动签到] 点名 #%s《%s》类型暂不支持（is_radar=%s is_number=%s）" % (
                rid, title, rc.get("is_radar"), rc.get("is_number"))
            entry["msg"] = msg
        events.append(msg)
        history.append(entry)
        _log(msg)
        notify_dingtalk(cfg, msg)

    state["answered"] = [e for e in history if e.get("type") != "unknown"][-10:]
    state["history"] = history[-30:]
    state["events"] = events[-10:]
    state["checkedAt"] = _now()
    state.pop("error", None)
    return state


# ═══════════════════════════════════════════════════════════════════
# 状态文件（worker 与 data 适配壳共享）
# ═══════════════════════════════════════════════════════════════════

def load_state():
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as f:
            st = json.load(f)
        if isinstance(st, dict):
            return st
    except Exception:
        pass
    return {"history": [], "pollCount": 0, "startedAt": None}


def save_state(state):
    try:
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
        os.replace(tmp, STATE_PATH)
    except Exception as e:
        _log("状态写入失败: %s" % e)
