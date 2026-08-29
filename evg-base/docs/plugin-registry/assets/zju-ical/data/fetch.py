#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zju-ical 数据源适配壳（模型 A：CLI 一次性脚本）——浙大课表 → iCalendar（RFC 5545）。

数据链路（真实抓取，绝不伪造）：
  1. 凭据：`_get_config(key)` 三级降级读取（--greenix-config 文件 → GREENIX_CONFIG_PATH
     → ConfigHttpServer（.config_port）→ 环境变量），key 复用平台内置 ZJU_USERNAME /
     ZJU_PASSWORD（浙大统一认证账号）。
  2. CAS 登录（zjuam.zju.edu.cn）：RSA 加密密码（教科书式无填充 modpow）→ 提交登录表单
     → 换取 `iPlanetDirectoryPro` SSO cookie（与平台 zju_modle/zju_auth 同一流程）。
  3. ZDBK 教务会话（zdbk.zju.edu.cn）：CAS service validation → 跟随 Location 至
     `login_ssologin.html` → 收集 `JSESSIONID` + `route` cookie。
  4. 课表接口：POST `jwglxt/kbcx/xskbcx_cxXsKb.html`（body `xnm=<学年>&xqm=<学期码>`）
     → 解析 `kbList`（课程名/教师/地点/星期/节次/周次/学期标记），与平台
     `ZjuTimetableSession.fromZdbkJson` 同构。
  5. 日期换算：周次+星期+节次 → 具体日期时间。学期第 1 周周一取自内置「校历学期起始
     日表」（公开校历事实，含来源标注），节次时间取自「浙大作息时间表」（45 分钟/节，
     与社区 zju-ical / zju-ical-py 项目一致）；均可用 `--term-start` 覆盖。
     调休/节假日对调未处理（在输出 note 中如实说明）。
  6. 输出：stdout 顶层 Map（含完整 `ics` 文本）；失败输出 `{"error": ...}` + 非零退出。

纯 Python 标准库（urllib/json/re/datetime/zipfile），零第三方依赖，Windows/Android 双端可用。
"""
import sys
import os
import re
import json
import zipfile
import io
import urllib.request
import urllib.parse
import urllib.error
import http.cookiejar
from datetime import date, datetime, timedelta, timezone

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

# ─────────────────────────────────────────────────────────────────────────────
# 常量：站点 / 接口
# ─────────────────────────────────────────────────────────────────────────────
CAS_BASE = 'https://zjuam.zju.edu.cn'
CAS_LOGIN = CAS_BASE + '/cas/login'
CAS_PUBKEY = CAS_BASE + '/cas/v2/getPubKey'
ZDBK_BASE = 'https://zdbk.zju.edu.cn'
ZDBK_SSO_SERVICE = ZDBK_BASE + '/jwglxt/xtgl/login_ssologin.html'
ZDBK_TIMETABLE = ZDBK_BASE + '/jwglxt/kbcx/xskbcx_cxXsKb.html'
ZDBK_REFERER = ZDBK_BASE + '/jwglxt/xtgl/index_initMenu.html'

DEFAULT_TYPE = 'zju_ical'
DEFAULT_TIMEOUT = 15  # 秒；整条链路 < 60s（平台 CLI 超时阈值）

UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

# ─────────────────────────────────────────────────────────────────────────────
# 校历学期起始日（公开事实数据，来源标注如下；可经 --term-start 覆盖）
#   - (学年起始年, FW|SS) → 该学期「第 1 周周一」
#   - 来源：浙江大学校历（ugrs.zju.edu.cn 校历公告；intl.zju.edu.cn 学术日历；
#     《浙江大学2025-2026学年校历》（浙江大学网站发布，搜狐转载）；社区项目
#     cxz66666/zju-ical、Xecades/zju-ical-py 依据校历维护的学期配置）。
#   - 冬/夏学期 = 秋/春学期第 1 周 + 8 周（2023-2026 各学年均符合，见社区配置）。
# ─────────────────────────────────────────────────────────────────────────────
TERM_START_MONDAYS = {
    (2022, 'FW'): date(2022, 9, 12),   # 2022-2023 秋冬（zju-ical config）
    (2023, 'FW'): date(2023, 9, 18),   # 2023-2024 秋冬（zju-ical-py config.2023-2024.FW）
    (2024, 'FW'): date(2024, 9, 9),    # 2024-2025 秋冬（zju-ical-py config.2024-2025.FW）
    (2024, 'SS'): date(2025, 2, 17),   # 2024-2025 春夏（zju-ical config.json：春 2025-02-17）
    (2025, 'FW'): date(2025, 9, 15),   # 2025-2026 秋冬（官方校历：9月15日秋学期开课）
    (2025, 'SS'): date(2026, 3, 2),    # 2025-2026 春夏（官方校历：3月2日春学期开课）
    (2026, 'FW'): date(2026, 9, 14),   # 2026-2027 秋冬（intl 官方校历：2026-09-14 开课）
    (2026, 'SS'): date(2027, 2, 22),   # 2026-2027 春夏（intl 官方校历：2027-02-22 开课）
}

# 浙大作息时间表：节次 → 开始时刻（45 分钟/节）。
# 与社区项目 cxz66666/zju-ical、Xecades/zju-ical-py 的节次表一致（两者均源自浙大作息时间）。
PERIOD_START = {
    1: (8, 0), 2: (8, 50), 3: (10, 0), 4: (10, 50), 5: (11, 40),
    6: (13, 25), 7: (14, 15), 8: (15, 5), 9: (16, 15), 10: (17, 5),
    11: (18, 50), 12: (19, 40), 13: (20, 30), 14: (21, 20), 15: (22, 10),
}
PERIOD_MINUTES = 45

# 学期位掩码（与平台 ZjuTimetableSession 一致）：春=1 夏=2 短=4|32 秋=8 冬=16 暑=64
SEM_BIT_SPRING = 1
SEM_BIT_SUMMER = 2
SEM_BIT_AUTUMN = 8
SEM_BIT_WINTER = 16
SEM_BIT_SHORT = 4 | 32
SEM_BIT_VACATION = 64
SEM_GROUP_FW = SEM_BIT_AUTUMN | SEM_BIT_WINTER   # 秋冬
SEM_GROUP_SS = SEM_BIT_SPRING | SEM_BIT_SUMMER   # 春夏


# ═══════════════════════════════════════════════════════════════════════════
# 配置读取：三级降级（协议要求）
# ═══════════════════════════════════════════════════════════════════════════
def _get_config(key, args):
    """从平台配置读取凭据/参数（三级降级），全空抛 RuntimeError（可读中文提示）。"""
    # Tier 1：--greenix-config <cfg>（平台传入的配置文件路径）或 GREENIX_CONFIG_PATH
    for cfg in (args.get('greenix-config'), os.environ.get('GREENIX_CONFIG_PATH')):
        if cfg and os.path.exists(cfg):
            try:
                with open(cfg, 'r', encoding='utf-8') as f:
                    val = json.load(f).get(key)
                if val:
                    return val
            except Exception:
                pass
    # Tier 2：ConfigHttpServer（读 .config_port 端口文件 → GET /config/settings/<key>）
    try:
        port = _find_config_port(args.get('project-root'))
        if port:
            url = 'http://127.0.0.1:{0}/config/settings/{1}'.format(port, urllib.parse.quote(key))
            with urllib.request.urlopen(url, timeout=5) as r:
                data = json.loads(r.read().decode('utf-8', 'replace'))
            val = data.get('value')
            if val:
                return val
    except Exception:
        pass
    # Tier 3：系统环境变量
    val = os.environ.get(key)
    if val:
        return val
    raise RuntimeError(
        '未获取到配置项 {0}：请先在「设置」中配置（或设置环境变量 {0}）'.format(key))


def _find_config_port(project_root):
    """从当前目录 / --project-root 及父目录查找 .config_port 端口文件。"""
    bases = [os.getcwd()]
    if project_root:
        bases.append(project_root)
    seen = set()
    for base in bases:
        d = os.path.abspath(base)
        while d not in seen:
            seen.add(d)
            pf = os.path.join(d, '.config_port')
            if os.path.exists(pf):
                try:
                    with open(pf, 'r', encoding='utf-8') as f:
                        v = f.read().strip()
                    if v.isdigit():
                        return int(v)
                except Exception:
                    return None
            parent = os.path.dirname(d)
            if parent == d:
                break
            d = parent
    return None


# ═══════════════════════════════════════════════════════════════════════════
# 参数解析：协议为「空格分隔」`--type <t> --project-root <root> --greenix-config <cfg>`；
# 兼容 `--key=value` 与裸 `key=value` 旧写法。
# ═══════════════════════════════════════════════════════════════════════════
def _parse_args(argv):
    args = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith('--'):
            body = a[2:]
            if '=' in body:
                k, _, v = body.partition('=')
                args[k] = v
                i += 1
            elif i + 1 < len(argv) and not argv[i + 1].startswith('--'):
                args[body] = argv[i + 1]
                i += 2
            else:
                args[body] = ''
                i += 1
        elif '=' in a:  # 旧式 `key=value`
            k, _, v = a.partition('=')
            args[k.lstrip('-')] = v
            i += 1
        else:
            i += 1
    return args


# ═══════════════════════════════════════════════════════════════════════════
# HTTP 工具（纯标准库，带 CookieJar 会话）
# ═══════════════════════════════════════════════════════════════════════════
class _RedirectCaptured(Exception):
    def __init__(self, new_url):
        super().__init__('redirect: ' + new_url)
        self.new_url = new_url


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """捕获 3xx 的 Location，不自动跟随（用于 CAS service validation）。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise _RedirectCaptured(newurl)


def _new_opener():
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(),
    )
    return opener, jar


def _headers(extra=None, referer=None):
    h = {
        'User-Agent': UA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
    }
    if referer:
        h['Referer'] = referer
    if extra:
        h.update(extra)
    return h


def _http_get(opener, url, headers=None, timeout=DEFAULT_TIMEOUT):
    req = urllib.request.Request(url, headers=headers or _headers())
    with opener.open(req, timeout=timeout) as r:
        return r.status, r.read()


def _http_post(opener, url, data, headers=None, timeout=DEFAULT_TIMEOUT):
    req = urllib.request.Request(url, data=data, headers=headers or _headers())
    with opener.open(req, timeout=timeout) as r:
        return r.status, r.read()


# ═══════════════════════════════════════════════════════════════════════════
# 浙大统一认证（CAS）登录 —— 与平台 zju_modle/zju_auth/zjuam_service.dart 同流程
# ═══════════════════════════════════════════════════════════════════════════
def _rsa_encrypt(password, modulus_hex, exponent_hex):
    """RSA 加密密码（教科书式 no-padding），密文按 modulus 位长补齐十六进制。"""
    m = int.from_bytes(password.encode('utf-8'), 'big')
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    c = pow(m, e, n)
    hex_len = (n.bit_length() + 3) // 4
    return format(c, 'x').zfill(hex_len)


def _execution_token(html):
    m = re.search(r'name=["\']execution["\']\s+value=["\']([^"\']+)["\']', html)
    if not m:
        m = re.search(r'value=["\']([^"\']+)["\']\s+name=["\']execution["\']', html)
    return m.group(1) if m else None


def _cookie_value(jar, name):
    for c in jar:
        if c.name == name:
            return c.value
    return None


def cas_login(opener, jar, username, password):
    """统一认证登录 → 返回 iPlanetDirectoryPro cookie 值；失败抛可读 RuntimeError。"""
    # 1) 打开 CAS 登录页，提取 execution
    try:
        status, body = _http_get(opener, CAS_LOGIN)
    except urllib.error.HTTPError as e:
        raise RuntimeError('统一认证登录页请求失败（HTTP {0}）'.format(e.code))
    except Exception as e:
        raise RuntimeError('无法连接浙大统一认证（zjuam.zju.edu.cn）——请确认网络或校园网环境: {0}'.format(_err(e)))
    html = body.decode('utf-8', 'replace')
    execution = _execution_token(html)
    if not execution:
        raise RuntimeError('统一认证登录页解析失败（未找到 execution 字段）——CAS 页面结构可能已变更')

    # 2) RSA 公钥
    try:
        status, body = _http_get(opener, CAS_PUBKEY)
        pub = json.loads(body.decode('utf-8', 'replace'))
        enc_pwd = _rsa_encrypt(password, pub['modulus'], pub['exponent'])
    except Exception as e:
        raise RuntimeError('获取统一认证 RSA 公钥失败: {0}'.format(_err(e)))

    # 3) 提交登录表单
    form = urllib.parse.urlencode({
        'username': username,
        'password': enc_pwd,
        'execution': execution,
        '_eventId': 'submit',
        'rememberMe': 'true',
    }).encode('utf-8')
    try:
        _http_post(opener, CAS_LOGIN, form,
                   headers=_headers({'Content-Type': 'application/x-www-form-urlencoded'},
                                    referer=CAS_LOGIN))
    except Exception as e:
        raise RuntimeError('统一认证登录提交失败: {0}'.format(_err(e)))

    sso = _cookie_value(jar, 'iPlanetDirectoryPro')
    if not sso:
        raise RuntimeError('统一认证登录失败：学号或密码错误（或账号触发验证码/风控）')
    return sso


def zdbk_login(opener, jar, sso_value):
    """用 SSO cookie 换取 ZDBK 教务会话（JSESSIONID + route）。"""
    # 手动把 SSO cookie 注入 zdbk 域（CookieJar 按域过滤，跨域不会自动携带）
    jar.set_cookie(http.cookiejar.Cookie(
        version=0, name='iPlanetDirectoryPro', value=sso_value,
        port=None, port_specified=False,
        domain='zdbk.zju.edu.cn', domain_specified=True, domain_initial_dot=False,
        path='/', path_specified=True, secure=True,
        expires=None, discard=True, comment=None, comment_url=None,
        rest={'HttpOnly': None}, rfc2109=False))

    # Step 1: CAS service validation（302 → 取 Location）
    url = CAS_LOGIN + '?service=' + urllib.parse.quote(ZDBK_SSO_SERVICE, safe='')
    req = urllib.request.Request(url, headers=_headers())
    opener_no_redir = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar), _NoRedirect())
    try:
        with opener_no_redir.open(req, timeout=DEFAULT_TIMEOUT) as r:
            location = r.headers.get('Location')
    except _RedirectCaptured as rc:
        location = rc.new_url
    except Exception as e:
        raise RuntimeError('教务系统 SSO 跳转失败: {0}'.format(_err(e)))
    if not location:
        raise RuntimeError('教务系统 SSO 未返回跳转地址——SSO 会话可能已失效')
    if location.startswith('http://'):
        location = location.replace('http://', 'https://')

    # Step 2: 跟随 Location 至 zdbk 域，收集 JSESSIONID + route
    try:
        with opener.open(urllib.request.Request(location, headers=_headers()),
                         timeout=DEFAULT_TIMEOUT) as r:
            r.read()
    except Exception as e:
        raise RuntimeError('教务系统登录落地页失败: {0}'.format(_err(e)))
    if not _cookie_value(jar, 'JSESSIONID') or not _cookie_value(jar, 'route'):
        raise RuntimeError('教务系统会话建立失败（未取得 JSESSIONID/route）——SSO 可能已失效')


# ═══════════════════════════════════════════════════════════════════════════
# 课表拉取与解析（与平台 ZjuTimetableSession.fromZdbkJson 同构）
# ═══════════════════════════════════════════════════════════════════════════
def _current_semester(now=None):
    """当前教务学年+学期码（与平台 zju_modle `_currentZjuSemester` 一致：秋冬=3/春夏=12）。"""
    now = now or datetime.now()
    aw = now.month >= 9 or now.month <= 2
    return (now.year if aw else now.year - 1), (3 if aw else 12)


def fetch_timetable(opener, year, sem_code):
    """POST 课表接口 → kbList 原始条目列表。"""
    body = urllib.parse.urlencode({'xnm': str(year), 'xqm': str(sem_code)}).encode('utf-8')
    headers = _headers({
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    }, referer=ZDBK_REFERER)
    try:
        status, resp = _http_post(opener, ZDBK_TIMETABLE, body, headers=headers)
    except urllib.error.HTTPError as e:
        if e.code == 302:
            raise RuntimeError('教务会话已过期，请重新登录后再试（HTTP 302）')
        raise RuntimeError('课表接口请求失败（HTTP {0}）'.format(e.code))
    except Exception as e:
        raise RuntimeError('无法连接教务网 zdbk.zju.edu.cn（可能不在校园网环境）: {0}'.format(_err(e)))
    text = resp.decode('utf-8', 'replace')
    if '登录' in text[:200] and 'login' in text[:200].lower():
        raise RuntimeError('教务会话已过期（响应为登录页），请重新登录后再试')

    # 响应通常为 JSON 对象，但含 kbList 的变体需正则兜底（平台 ZdbkPatterns.timetableKbList 同款）
    kb = None
    if text.strip().startswith('{'):
        try:
            j = json.loads(text)
            kb = j.get('kbList')
        except Exception:
            kb = None
    if kb is None:
        m = re.search(r'"kbList":(\[.*?\])(?=,"xh")', text, re.S)
        if not m:
            m = re.search(r'"kbList":(\[.*?\])', text, re.S)
        if not m:
            raise RuntimeError('课表接口响应结构异常（未找到 kbList）——教务页面可能已改版')
        try:
            kb = json.loads(m.group(1))
        except Exception as e:
            raise RuntimeError('课表 kbList 解析失败: {0}'.format(_err(e)))
    if kb == 'null':
        return []
    return kb or []


def _semester_bits(week_info):
    """从 kcb 周次信息段提取学期位掩码（镜像平台 ZjuTimetableSession.fromZdbkJson）。"""
    bits = 0
    if '春' in week_info:
        bits |= SEM_BIT_SPRING
    if '夏' in week_info:
        bits |= SEM_BIT_SUMMER
    if '秋' in week_info:
        bits |= SEM_BIT_AUTUMN
    if '冬' in week_info:
        bits |= SEM_BIT_WINTER
    if '短' in week_info:
        bits |= SEM_BIT_SHORT
    if '暑' in week_info:
        bits |= SEM_BIT_VACATION
    return bits


def parse_week_range(raw):
    """周次字符串 → (weeks 集合, 单双周模式)。

    '1-16周' → ({1..16}, None)；'1-8,11-16周' → 两段并集；
    '1-15周(单)' → ({1,3,..15}, 'odd')；'2-16周(双)' → ({2,4,..16}, 'even')。
    """
    if not raw:
        return set(), None
    odd = '单' in raw and '双' not in raw
    even = '双' in raw and '单' not in raw
    weeks = set()
    for seg in re.split(r'[,，、;；]', raw):
        seg = re.sub(r'[^0-9\-]', '', seg)
        if not seg:
            continue
        m = re.fullmatch(r'(\d+)-(\d+)', seg)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if a <= b:
                weeks.update(range(a, b + 1))
        elif seg.isdigit():
            weeks.add(int(seg))
    return weeks, ('odd' if odd else ('even' if even else None))


def _course_year_from_xkkh(xkkh):
    m = re.search(r'\((\d{4})', xkkh or '')
    return int(m.group(1)) if m else None


def parse_kb_sessions(kb):
    """kbList → 结构化 session 列表（过滤已结束/无课名的占位行）。"""
    sessions = []
    for it in kb or []:
        if not isinstance(it, dict):
            continue
        raw_kcb = str(it.get('kcb') or '')
        parts = [p.strip() for p in raw_kcb.split('<br>')]
        name = parts[0] if parts and parts[0] else ''
        if not name:
            continue  # 占位行（无课程名）
        if str(it.get('sfyjskc')) == '1':
            continue  # 已结束课程（与平台过滤一致）
        week_info = parts[1] if len(parts) >= 2 else ''
        teacher = parts[2] if len(parts) >= 3 else ''
        raw_loc = parts[3] if len(parts) >= 4 else ''
        zwf = raw_loc.find('zwf')
        if zwf > 0:
            raw_loc = raw_loc[:zwf]
        try:
            day = int(it.get('xqj'))
        except (TypeError, ValueError):
            day = 1
        day = max(1, min(7, day))
        try:
            start_period = int(it.get('djj'))
        except (TypeError, ValueError):
            start_period = 0
        try:
            period_len = int(it.get('skcd'))
        except (TypeError, ValueError):
            period_len = 0
        periods = list(range(start_period, start_period + (period_len or 1))) if start_period > 0 else []
        dsz = str(it.get('dsz') or '').strip()
        if not dsz and week_info:
            dsz = week_info  # 周次兜底：kcb 第 2 段
        sessions.append({
            'course_id': str(it.get('xkkh') or ''),
            'name': name,
            'teacher': teacher,
            'location': raw_loc.strip(),
            'day': day,
            'periods': periods,
            'week_range_raw': dsz,
            'semester_bits': _semester_bits(week_info),
            'course_year': _course_year_from_xkkh(str(it.get('xkkh') or '')),
        })
    return sessions


# ═══════════════════════════════════════════════════════════════════════════
# 周次/星期/节次 → 日期时间 + iCalendar 生成
# ═══════════════════════════════════════════════════════════════════════════
def resolve_term_base(session, query_year, query_group, term_start_override):
    """计算该课程所属学期的「第 1 周周一」基准日。

    - 秋(8)/春(1) → FW/SS 起始日
    - 仅冬(16)（无秋）→ 若周次 ≤8 视为相对冬学期 → FW 起始日 + 8 周；否则相对秋冬 → FW 起始日
    - 仅夏(2)（无春）→ 同理基于 SS 起始日
    """
    bits = session['semester_bits']
    year = session['course_year'] or query_year
    if bits & SEM_BIT_AUTUMN:
        base = _term_start(year, 'FW', term_start_override, query_group)
        return base, 0
    if bits & SEM_BIT_WINTER:
        base = _term_start(year, 'FW', term_start_override, query_group)
        max_week = max(session['weeks']) if session['weeks'] else 0
        return base, (56 if max_week <= 8 else 0)
    if bits & SEM_BIT_SPRING:
        base = _term_start(year, 'SS', term_start_override, query_group)
        return base, 0
    if bits & SEM_BIT_SUMMER:
        base = _term_start(year, 'SS', term_start_override, query_group)
        max_week = max(session['weeks']) if session['weeks'] else 0
        return base, (56 if max_week <= 8 else 0)
    return None, 0  # 仅短/暑学期 → 无法可靠换算，跳过


def _term_start(year, group, term_start_override, query_group):
    """学期起始日：--term-start 覆盖（仅对本次查询学期生效）；否则查内置校历表。"""
    if term_start_override is not None and group == query_group:
        return term_start_override
    key = (year, group)
    if key not in TERM_START_MONDAYS:
        raise RuntimeError(
            '内置校历表缺少 {0}-{1}{2} 学期起始日（{3} 学年），无法换算课程日期；'
            '请用 --term-start YYYYMMDD 指定该学期第 1 周周一（见浙江大学校历）'.format(
                year, year + 1, '秋冬' if group == 'FW' else '春夏', key))
    return TERM_START_MONDAYS[key]


def sessions_to_events(sessions, query_year, query_group, filter_group, term_start_override):
    """session 列表 → ICS 事件字典列表。

    filter_group：'FW'/'SS'/'ALL' —— 默认只导出本次查询学期（秋冬或春夏）。
    """
    events = []
    skipped = []
    for s in sessions:
        bits = s['semester_bits']
        in_fw = bool(bits & SEM_GROUP_FW)
        in_ss = bool(bits & SEM_GROUP_SS)
        if filter_group == 'FW' and not in_fw:
            continue
        if filter_group == 'SS' and not in_ss:
            continue
        if filter_group == 'ALL' and not (in_fw or in_ss):
            skipped.append('{0}（仅短/暑学期，未换算）'.format(s['name']))
            continue
        weeks, parity = parse_week_range(s['week_range_raw'])
        if not weeks:
            skipped.append('{0}（周次解析为空: {1}）'.format(s['name'], s['week_range_raw'] or '无'))
            continue
        s['weeks'] = weeks
        base, offset_days = resolve_term_base(s, query_year, query_group, term_start_override)
        if base is None:
            skipped.append('{0}（仅短/暑学期，未换算）'.format(s['name']))
            continue
        base = base + timedelta(days=offset_days)
        start_period = s['periods'][0] if s['periods'] else 1
        end_period = s['periods'][-1] if s['periods'] else start_period
        st = PERIOD_START.get(start_period)
        if not st:
            skipped.append('{0}（节次 {1} 超出作息表范围）'.format(s['name'], start_period))
            continue
        for week in sorted(weeks):
            if parity == 'odd' and week % 2 == 0:
                continue
            if parity == 'even' and week % 2 == 1:
                continue
            d = base + timedelta(days=(week - 1) * 7 + (s['day'] - 1))
            start_dt = datetime(d.year, d.month, d.day, st[0], st[1])
            end_dt = start_dt + timedelta(minutes=PERIOD_MINUTES * (end_period - start_period + 1))
            events.append({
                'name': s['name'],
                'location': s['location'],
                'teacher': s['teacher'],
                'week_desc': '{0}周'.format(s['week_range_raw']) if s['week_range_raw'] else '第{0}周'.format(week),
                'period_desc': '第{0}-{1}节'.format(start_period, end_period) if end_period != start_period
                               else '第{0}节'.format(start_period),
                'start': start_dt,
                'end': end_dt,
            })
    return events, skipped


def _ics_escape(s):
    return s.replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n')


def _fold_line(line):
    """RFC 5545 §3.1：内容行不超过 75 octets（不含 CRLF），超出用 CRLF+空格续行折叠。

    按 UTF-8 字节数切分，保证不截断多字节字符。
    """
    if len(line.encode('utf-8')) <= 75:
        return line
    out = []
    cur = ''
    cur_len = 0
    for ch in line:
        bl = len(ch.encode('utf-8'))
        if cur_len + bl > 73:  # 预留 1 字节续行前缀空格
            out.append(cur)
            cur = ' ' + ch
            cur_len = 1 + bl
        else:
            cur += ch
            cur_len += bl
    if cur:
        out.append(cur)
    return '\r\n'.join(out)


def build_ics(events):
    """事件列表 → RFC 5545 iCalendar 文本（Asia/Shanghai 本地时间，无夏令时）。

    每个 VEVENT 为单次显式发生（非 RRULE），导入兼容性最好；长行按 RFC 折叠。
    """
    lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Evergreen//ZJU iCal//CN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VTIMEZONE',
        'TZID:Asia/Shanghai',
        'BEGIN:STANDARD',
        'DTSTART:19700101T000000',
        'TZOFFSETFROM:+0800',
        'TZOFFSETTO:+0800',
        'END:STANDARD',
        'END:VTIMEZONE',
    ]
    # DTSTAMP 必须为 UTC（RFC 5545 §3.8.7.2）
    dtstamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    for i, e in enumerate(events):
        desc = '教师: {0}\\n周次: {1}\\n节次: {2}'.format(
            _ics_escape(e['teacher'] or '未知'), _ics_escape(e['week_desc']), e['period_desc'])
        for raw in [
            'BEGIN:VEVENT',
            'UID:zju-ical-{0}@evergreen.local'.format(i),
            'DTSTAMP:{0}'.format(dtstamp),
            'DTSTART;TZID=Asia/Shanghai:{0}'.format(e['start'].strftime('%Y%m%dT%H%M%S')),
            'DTEND;TZID=Asia/Shanghai:{0}'.format(e['end'].strftime('%Y%m%dT%H%M%S')),
            'SUMMARY:{0}'.format(_ics_escape(e['name'])),
            'DESCRIPTION:{0}'.format(desc),
        ] + (['LOCATION:{0}'.format(_ics_escape(e['location']))] if e['location'] else []) + [
            'END:VEVENT',
        ]:
            lines.append(_fold_line(raw))
    lines.append('END:VCALENDAR')
    return '\r\n'.join(lines) + '\r\n'


# ═══════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════
def _err(e):
    return getattr(e, 'reason', str(e)) if not isinstance(e, urllib.error.HTTPError) else 'HTTP {0}'.format(e.code)


def _fail(type_arg, message):
    out = {'type': type_arg, 'error': message}
    print(json.dumps(out, ensure_ascii=False))
    sys.stderr.write(message + '\n')
    sys.exit(1)


def _parse_date_arg(raw):
    s = (raw or '').strip().replace('-', '')
    try:
        return datetime.strptime(s, '%Y%m%d').date()
    except ValueError:
        raise RuntimeError('--term-start 格式应为 YYYYMMDD（如 20260914），实际为: {0}'.format(raw))


def main():
    args = _parse_args(sys.argv[1:])
    type_arg = args.get('type') or DEFAULT_TYPE

    # 凭据（三级降级；缺失 → 失败契约）
    try:
        username = _get_config('ZJU_USERNAME', args)
        password = _get_config('ZJU_PASSWORD', args)
    except RuntimeError as e:
        _fail(type_arg, str(e) + '（数据源 zju-ical 需要浙大统一认证账号）')

    # 学期解析：--year/--semester 覆盖，否则取当前（与平台一致）
    try:
        cur_year, cur_sem = _current_semester()
        year = int(args.get('year') or cur_year)
        sem_code = int(args.get('semester') or cur_sem)
        if sem_code not in (3, 12):
            raise RuntimeError('--semester 仅支持 3（秋冬）/ 12（春夏）')
    except (TypeError, ValueError) as e:
        _fail(type_arg, '学年/学期参数无效: {0}'.format(e))

    query_group = 'FW' if sem_code == 3 else 'SS'
    term_start_override = None
    try:
        if args.get('term-start'):
            term_start_override = _parse_date_arg(args['term-start'])
    except RuntimeError as e:
        _fail(type_arg, str(e))

    filter_group = (args.get('semester-filter') or query_group).upper()
    if filter_group not in ('FW', 'SS', 'ALL'):
        _fail(type_arg, '--semester-filter 仅支持 FW / SS / ALL')

    try:
        opener, jar = _new_opener()
        sso = cas_login(opener, jar, username, password)
        zdbk_login(opener, jar, sso)
        kb = fetch_timetable(opener, year, sem_code)
        sessions = parse_kb_sessions(kb)
        events, skipped = sessions_to_events(
            sessions, year, query_group, filter_group, term_start_override)
        ics = build_ics(events)

        # 兼容旧输出：保留 ics + 提供 zip 打包字节数（可选消费）
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('zju-schedule.ics', ics)

        out = {
            'type': type_arg,
            'authenticated': True,
            'course_count': len(sessions),
            'event_count': len(events),
            'ics': ics,
            'zip_bytes': len(buf.getvalue()),
            'semester': {
                'year': year,
                'code': sem_code,
                'name': '秋冬' if query_group == 'FW' else '春夏',
                'term_start': (term_start_override or
                               _term_start(year, query_group, None, query_group)).isoformat(),
            },
            'skipped': skipped[:20],
            'note': ('课表数据来自 ZDBK 教务系统（zdbk.zju.edu.cn/jwglxt/kbcx），'
                     '经浙大统一认证（CAS）登录获取；课程日期按内置校历学期起始日 + 浙大作息时间表'
                     '（45 分钟/节）换算，调休/节假日对调未处理；如需更正学期起始日请传 '
                     '--term-start YYYYMMDD'),
        }
        print(json.dumps(out, ensure_ascii=False))
    except RuntimeError as e:
        _fail(type_arg, str(e))
    except Exception as e:  # 收敛一切异常为错误 JSON（不污染 stdout 堆栈）
        _fail(type_arg, '未预期错误: {0}'.format(_err(e)))


if __name__ == '__main__':
    main()
