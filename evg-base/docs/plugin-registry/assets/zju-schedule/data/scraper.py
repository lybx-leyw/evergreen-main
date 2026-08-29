#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ZJU 课表数据源适配壳（zju-schedule，data-source 插件）。

逆向对齐 evg-base zju_modle 的真实接线（B4-fix 版，2026-08-13），非占位实现：
- CAS 统一认证登录：lib/renderer/templates/zju_modle/zju_auth/zjuam_service.dart
- ZDBK 教务会话换取：lib/renderer/templates/zju_modle/zju_auth/zju_session.dart
- 课表接口 getTimetable：lib/renderer/templates/zju_modle/zdbk/services/zdbk_service.dart
- 课表条目模型/字段语义：lib/renderer/templates/zju_modle/shared/models/zju_timetable_session.dart
  （fromZdbkJson → toJson 的字段与语义逐字段对齐）

链路：CAS（zjuam.zju.edu.cn）→ ZDBK（zdbk.zju.edu.cn）→ kbcx 课表接口。
输出 JSON 顶层 Map，结构对齐平台 Dart fetcher `zju_timetable`：
  {"type": ..., "sessions": [{course_id, course_name, teacher, location,
    day_of_week, periods, week_range, semester, course_year, is_ended, credit}],
   "year": <学年起始年>, "semester": <学期码>, "count": n, "fetched_at": ...}

适配壳契约（plugin-registry-spec-v1 §六 + core data 模块）：
- 空格分隔参数：--type <typeArg> --project-root <root> --greenix-config <cfg>
- stdout 输出纯 JSON（顶层 Map）；exit 0 = 成功，非 0 = 失败
- 失败时 stdout 输出 {"error": <人类可读信息>, "error_type": <分类>, "detail": ...} + 非零退出
- 凭证：ZJU_USERNAME / ZJU_PASSWORD，三级降级读取（--greenix-config → 环境变量 → 报错）
- 纯标准库（urllib / re / json / http 等），零第三方依赖，UTF-8，绝不伪造课表数据
"""
import json
import os
import re
import socket
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

# ── 常量（逆向自 zju_modle，勿随意改动）────────────────────────────────
CAS_BASE = 'https://zjuam.zju.edu.cn'
CAS_LOGIN = CAS_BASE + '/cas/login'
CAS_PUBKEY = CAS_BASE + '/cas/v2/getPubKey'
ZDBK_BASE = 'https://zdbk.zju.edu.cn'
ZDBK_HOST = 'zdbk.zju.edu.cn'
# SSO cookie 注入父域（对齐 zju_session._injectSsoCookie 的 .zju.edu.cn）
SSO_COOKIE_DOMAIN = 'zju.edu.cn'
ZDBK_SSO_SERVICE = ZDBK_BASE + '/jwglxt/xtgl/login_ssologin.html'
ZDBK_TIMETABLE = ZDBK_BASE + '/jwglxt/kbcx/xskbcx_cxXsKb.html'
ZDBK_REFERER = ZDBK_BASE + '/jwglxt/xtgl/index_initMenu.html'

UA_FULL = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
)
UA_SHORT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

# ZDBK 标准请求头（对齐 zdbk_service._zdbkSetHeaders）
ZDBK_HEADERS = {
    'Referer': ZDBK_REFERER,
    'Connection': 'close',
    'User-Agent': UA_SHORT,
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'X-Requested-With': 'XMLHttpRequest',
}

# CAS 登录页 execution 参数（对齐 zdbk_patterns.executionToken）
EXECUTION_RE = re.compile(r'name="execution"\s+value="([^"]+)"')
# 课表响应 kbList JSON 数组（对齐 zdbk_patterns.timetableKbList）
KBLIST_RE = re.compile(r'(?<="kbList":)\[(.*?)\](?=,"xh")', re.S)
# 从选课课号 (2025-2026-2)-... 提取学年起始年（对齐 ZjuTimetableSession.fromZdbkJson）
COURSE_YEAR_RE = re.compile(r'\((\d{4})')

# 会话过期特征（对齐 zju_session.zjuIsSessionExpiredError 的 CAS 页特征）
_SESSION_EXPIRED_MARKERS = ('cas/login', 'login_ssologin', '统一身份认证')

# 学期码：秋冬=3，春夏=12（对齐 _currentZjuSemester）
_SEMESTER_AUTUMN_WINTER = 3
_SEMESTER_SPRING_SUMMER = 12


# ── 错误分类（契约：错误分类 + 非零退出）───────────────────────────────
class ScraperError(Exception):
    """适配壳错误基类：error_type 分类 + exit_code 非零退出。"""

    error_type = 'unknown'
    exit_code = 1

    def __init__(self, message, detail=None):
        super().__init__(message)
        self.message = message
        self.detail = detail


class ConfigError(ScraperError):
    error_type = 'config_missing'
    exit_code = 2


class AuthError(ScraperError):
    error_type = 'auth_failed'
    exit_code = 3


class SessionExpiredError(ScraperError):
    error_type = 'session_expired'
    exit_code = 3


class NetworkError(ScraperError):
    error_type = 'network'
    exit_code = 4


class FetchTimeoutError(ScraperError):
    error_type = 'timeout'
    exit_code = 4


class HttpError(ScraperError):
    error_type = 'http_error'
    exit_code = 4


class ParseError(ScraperError):
    error_type = 'parse_error'
    exit_code = 5


class InvalidInputError(ScraperError):
    error_type = 'invalid_input'
    exit_code = 5


# ── HTTP 会话（手动 cookie + 手动重定向，对齐 Dart followRedirects=false）──
class _Redirect(Exception):
    """捕获重定向（code / location / headers），而非由 urllib 自动跟随。"""

    def __init__(self, code, location, headers):
        self.code = code
        self.location = location
        self.headers = headers


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """重定向处理器：把 3xx 转成 _Redirect 异常。

    原因：urllib 的 CookieProcessor 在默认处理链中收不到 3xx 响应的
    Set-Cookie（跨域跳转时 CookieJar 会漏 cookie），而 ZDBK 会话
    （JSESSIONID / route）恰恰经 CAS→zdbk 的 302 链路下发。手动接管
    重定向后可逐跳收集 Set-Cookie，行为对齐 Dart 参考实现。
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if fp is not None:
            try:
                fp.close()
            except Exception:
                pass
        raise _Redirect(code, newurl, headers)


def _domain_match(cookie_domain, host):
    """cookie 域匹配（前导点忽略，后缀匹配）。"""
    if not cookie_domain or not host:
        return False
    cd = cookie_domain.lower()
    h = host.lower()
    if cd.startswith('.'):
        cd = cd[1:]
    return h == cd or h.endswith('.' + cd)


def _path_match(cookie_path, url_path):
    if cookie_path in ('', '/'):
        return True
    return url_path == cookie_path or url_path.startswith(cookie_path.rstrip('/') + '/')


def _ssl_context():
    """默认校验证书链；个别 Windows Python 发行版证书库损坏时优雅降级。

    注意：降级为不校验会削弱传输保护（RSA 加密的密码可缓解，但会话 cookie
    为明文）。仅在 `ssl.create_default_context()` 直接抛错（如 Conda 版
    Python 加载 Windows 证书库失败）时才启用降级，对齐 zju-grades 同款策略。
    """
    try:
        return ssl.create_default_context()
    except Exception:
        return ssl._create_unverified_context()  # noqa: S323


class Session:
    """手动管理的 cookie 会话（纯标准库，无 CookieJar 3xx 漏收问题）。"""

    def __init__(self, timeout=20.0, max_redirects=5):
        self.timeout = timeout
        self.max_redirects = max_redirects
        self._cookies = {}  # (name, domain, path) -> {'value': str, 'secure': bool}
        self._opener = urllib.request.build_opener(
            _NoRedirectHandler(),
            urllib.request.HTTPSHandler(context=_ssl_context()),
        )

    # ── cookie ────────────────────────────────────────────────────
    def set_cookie(self, name, value, domain=None, path='/', secure=False):
        key = (name, domain, path)
        self._cookies[key] = {'value': value, 'secure': bool(secure)}

    def get_cookie(self, name, host):
        """按 name + 域匹配查 cookie 值（**不限 path**）。

        真实 ZDBK 的 JSESSIONID 经 Set-Cookie 以 `Path=/jwglxt` 下发（Dart
        参考 `_jSessionId = res2.cookies.firstWhere((c) => c.name ==
        'JSESSIONID' && c.path == '/jwglxt')` 同款），若此处限制 path=='/'
        会查不到而误报「缺少 JSESSIONID cookie」——修复点（队长真实凭据实测
        发现：CAS 成功但 ZDBK 会话建立误报失败）。
        """
        for (cname, cdomain, cpath), c in self._cookies.items():
            if cname == name and _domain_match(cdomain, host):
                return c['value']
        return None

    def _cookie_header(self, url):
        parts = urllib.parse.urlparse(url)
        host = (parts.hostname or '').lower()
        url_path = parts.path or '/'
        is_https = parts.scheme == 'https'
        pairs = []
        for (name, domain, cpath), c in self._cookies.items():
            if not _domain_match(domain, host):
                continue
            if not _path_match(cpath, url_path):
                continue
            if c['secure'] and not is_https:
                continue
            pairs.append('%s=%s' % (name, c['value']))
        return '; '.join(pairs)

    def _ingest(self, headers, host):
        """解析响应 Set-Cookie 头并入库（2xx 与 3xx 统一处理）。"""
        if headers is None:
            return
        for raw in headers.get_all('Set-Cookie') or []:
            raw = raw.strip()
            if not raw:
                continue
            first, _, rest = raw.partition(';')
            name, _, value = first.partition('=')
            name = name.strip()
            value = value.strip()
            if not name:
                continue
            domain = None
            path = '/'
            secure = False
            for attr in rest.split(';'):
                attr = attr.strip()
                low = attr.lower()
                if low.startswith('domain='):
                    d = attr[len('domain='):].strip().lstrip('.')
                    if d:
                        domain = d
                elif low.startswith('path='):
                    p = attr[len('path='):].strip()
                    if p:
                        path = p
                elif low == 'secure':
                    secure = True
            self.set_cookie(name, value, domain if domain else host, path, secure)

    # ── 请求 ──────────────────────────────────────────────────────
    def request(self, method, url, data=None, headers=None,
                content_type=None, allow_redirects=True):
        """发请求；返回 (body|None, status|None, location|None)。

        - 2xx：body 为解码文本，location 为 None
        - 3xx 且 allow_redirects=False：body/status 为 None，location 为跳转地址
        - 3xx 且 allow_redirects=True：手动跟随（最多 max_redirects 跳）
        """
        headers = dict(headers or {})
        headers.setdefault('User-Agent', UA_FULL)
        body_bytes = None
        if data is not None:
            body_bytes = data if isinstance(data, bytes) else data.encode('utf-8')
            if content_type:
                headers['Content-Type'] = content_type

        current = url
        hops = 0
        while True:
            req_headers = dict(headers)
            cookie = self._cookie_header(current)
            if cookie:
                req_headers['Cookie'] = cookie
            req = urllib.request.Request(current, data=body_bytes,
                                         headers=req_headers, method=method)
            try:
                with self._opener.open(req, timeout=self.timeout) as resp:
                    self._ingest(resp.headers, urllib.parse.urlparse(current).hostname)
                    body = resp.read().decode('utf-8', errors='replace')
                    return body, resp.status, None
            except _Redirect as r:
                self._ingest(r.headers, urllib.parse.urlparse(current).hostname)
                if not allow_redirects:
                    return None, r.code, r.location
                if not r.location:
                    raise ParseError('响应缺少 Location 重定向地址')
                nxt = r.location
                parsed = urllib.parse.urlparse(nxt)
                if nxt.startswith('//'):
                    nxt = urllib.parse.urlparse(current).scheme + ':' + nxt
                elif not parsed.scheme:
                    nxt = urllib.parse.urljoin(current, nxt)
                if nxt.startswith('http://'):
                    nxt = 'https://' + nxt[len('http://'):]
                hops += 1
                if hops > self.max_redirects:
                    raise NetworkError('重定向次数过多（超过 %d 次）' % self.max_redirects)
                current = nxt
            except urllib.error.HTTPError as e:
                self._ingest(e.headers, urllib.parse.urlparse(current).hostname)
                try:
                    detail = e.read().decode('utf-8', errors='replace')[:200]
                except Exception:
                    detail = None
                raise HttpError('教务网返回 HTTP %s' % e.code, detail=detail)
            except urllib.error.URLError as e:
                raise NetworkError('网络请求失败：%s' % getattr(e, 'reason', e))
            except (TimeoutError, socket.timeout):
                raise FetchTimeoutError('请求超时（%.0fs）' % self.timeout)
            except OSError as e:
                raise NetworkError('网络异常：%s' % e)


# ── RSA（对齐 zjuam_service.rsaEncrypt，纯标准库 pow）──────────────────
def rsa_encrypt(password, modulus_hex, exponent_hex):
    """ZJU CAS RSA 加密：UTF-8 字节 → 大整数 → c = m^e mod n → 十六进制补足 modulus 位长。"""
    m = int.from_bytes(password.encode('utf-8'), 'big')
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    c = pow(m, e, n)
    return format(c, 'x').zfill((n.bit_length() + 3) // 4)


# ── 登录链路 ──────────────────────────────────────────────────────────
def cas_login(sess, username, password):
    """CAS 统一认证登录，返回 iPlanetDirectoryPro cookie 值。

    对齐 zjuam_service.login：GET /cas/login 取 execution → GET /cas/v2/getPubKey
    取 RSA 公钥 → POST /cas/login（RSA 加密密码）→ 校验 iPlanetDirectoryPro。
    """
    body, status, _ = sess.request('GET', CAS_LOGIN)
    m = EXECUTION_RE.search(body or '')
    if not m:
        raise ParseError('无法从 CAS 登录页提取 execution 参数（页面结构可能已变更）',
                         detail=(body or '')[:200])
    execution = m.group(1)

    pub_body, status, _ = sess.request('GET', CAS_PUBKEY)
    try:
        pub = json.loads(pub_body or '')
    except Exception:
        raise ParseError('getPubKey 返回非 JSON（页面结构可能已变更）',
                         detail=(pub_body or '')[:200])
    modulus = pub.get('modulus')
    exponent = pub.get('exponent')
    if not modulus or not exponent:
        raise ParseError('getPubKey 缺少 modulus/exponent 字段')

    form = urllib.parse.urlencode({
        'username': username,
        'password': rsa_encrypt(password, modulus, exponent),
        'execution': execution,
        '_eventId': 'submit',
        'rememberMe': 'true',
    })
    # 成功 = 302 + iPlanetDirectoryPro；失败 = 200 登录页（无 cookie）
    sess.request('POST', CAS_LOGIN, data=form,
                 content_type='application/x-www-form-urlencoded',
                 allow_redirects=False)
    sso = sess.get_cookie('iPlanetDirectoryPro',
                          urllib.parse.urlparse(CAS_BASE).hostname)
    if not sso:
        raise AuthError('学号或密码错误（或需要验证码/二次认证）',
                        detail='CAS 登录未返回 iPlanetDirectoryPro cookie')
    return sso


def zdbk_login(sess, sso_value):
    """用 SSO cookie 换取 ZDBK 教务会话（JSESSIONID + route）。

    对齐 ZjuZdbkService.login：GET cas/login?service=<zdbk sso 落地页> 携带
    iPlanetDirectoryPro（父域 cookie）→ 跟随 302 至 zdbk 域 → 收集
    JSESSIONID / route。注意 JSESSIONID 以 `Path=/jwglxt` 下发（Dart 参考
    按 `c.path == '/jwglxt'` 匹配），get_cookie 按 name+域匹配、不限 path。
    """
    sess.set_cookie('iPlanetDirectoryPro', sso_value,
                    domain=SSO_COOKIE_DOMAIN, path='/')
    service = urllib.parse.quote(ZDBK_SSO_SERVICE, safe='')
    sess.request('GET', CAS_LOGIN + '?service=' + service)
    jsession = sess.get_cookie('JSESSIONID', ZDBK_HOST)
    route = sess.get_cookie('route', ZDBK_HOST)
    if not jsession or not route:
        raise SessionExpiredError('ZDBK 教务会话建立失败（缺少 JSESSIONID/route cookie）',
                                  detail='SSO 会话可能已失效，请重新配置凭证后刷新')
    return jsession, route


# ── 课表抓取与解析 ─────────────────────────────────────────────────────
def _check_session(body):
    """命中 CAS 登录页特征 → 会话过期（对齐 _checkSession）。"""
    for marker in _SESSION_EXPIRED_MARKERS:
        if marker in body:
            raise SessionExpiredError('教务会话已过期，请重新配置凭证后刷新')


def _transform(item):
    """ZDBK 原始课表条目 → 平台 ZjuTimetableSession.toJson 形态（字段/语义逐一对齐）。"""
    kcb = str(item.get('kcb') or '')
    parts = kcb.split('<br>')

    course_name = parts[0].strip() if parts and parts[0].strip() else '未命名课程'
    teacher = ''
    location = ''
    semester_bits = 0
    if len(parts) >= 2:
        week_info = parts[1] or ''
        if '春' in week_info:
            semester_bits |= 1
        if '夏' in week_info:
            semester_bits |= 2
        if '秋' in week_info:
            semester_bits |= 8
        if '冬' in week_info:
            semester_bits |= 16
        if '短' in week_info:
            semester_bits |= 4 | 32
        if '暑' in week_info:
            semester_bits |= 64
    if len(parts) >= 3:
        teacher = parts[2].strip()
    if len(parts) >= 4:
        raw_loc = parts[3].strip()
        zwf_idx = raw_loc.find('zwf')
        if zwf_idx > 0:
            # 参考实现用 'zwf' 作分隔：raw_loc[:zwf_idx]。
            # 实际数据形如 "东1A-201[zwf...]"（方括号分隔），这里再剥掉残留的
            # '['，避免地点带出 '['（对参考实现的刻意微修，展示更干净）。
            raw_loc = raw_loc[:zwf_idx].rstrip('[')
        location = raw_loc

    try:
        start = int(item.get('djj') or 0)
    except (TypeError, ValueError):
        start = 0
    try:
        length = int(item.get('skcd') or 0)
    except (TypeError, ValueError):
        length = 0
    periods = list(range(start, start + (length if length > 0 else 1))) if start > 0 else []

    try:
        dow = int(item.get('xqj') or 1)
    except (TypeError, ValueError):
        dow = 1
    dow = max(1, min(7, dow))

    week_range = item.get('dsz') or None
    course_id = item.get('xkkh') or None
    course_year = None
    if course_id:
        mm = COURSE_YEAR_RE.search(str(course_id))
        if mm:
            course_year = int(mm.group(1))
    try:
        credit = float(item.get('xf') or 0)
    except (TypeError, ValueError):
        credit = 0.0

    return {
        'course_id': course_id,
        'course_name': course_name,
        'teacher': teacher,
        'location': location,
        'day_of_week': dow,
        'periods': periods,
        'week_range': week_range,
        'semester': semester_bits,
        'course_year': course_year,
        'is_ended': False,
        'credit': credit,
    }


def fetch_timetable(sess, year, semester):
    """拉取课表（对齐 getTimetable：POST xskbcx_cxXsKb.html，body xnm/xqm）。

    ZDBK 忽略 xqm 返回整个学年课表；'null' 响应 = 无课程；
    过滤缺 kcb 与 sfyjskc=1（已结束）的条目（对齐 parseTimetable）。
    """
    body, status, _ = sess.request(
        'POST', ZDBK_TIMETABLE,
        data='xnm=%d&xqm=%d' % (year, semester),
        headers=ZDBK_HEADERS,
        content_type='application/x-www-form-urlencoded; charset=utf-8',
        allow_redirects=False,
    )
    if body is None and status in (301, 302, 303):
        raise SessionExpiredError('教务会话已失效（响应为重定向），请重新配置凭证后刷新')
    text = (body or '').strip()
    _check_session(text)
    if text == 'null':
        return []
    m = KBLIST_RE.search(text)
    if not m:
        raise ParseError('课表 kbList 解析失败——教务页面结构可能已变更',
                         detail=text[:200])
    try:
        raw = json.loads(m.group(0))
    except Exception as e:
        raise ParseError('课表 kbList 非合法 JSON：%s' % e, detail=text[:200])
    sessions = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        if item.get('kcb') is None or item.get('sfyjskc') == '1':
            continue
        sessions.append(_transform(item))
    return sessions


# ── 参数 / 凭证 / 学期 ─────────────────────────────────────────────────
def _parse_args(argv):
    """空格分隔参数：--key value（兼容 --key=value 与裸 flag）。

    参数名归一化：平台契约传 `--greenix-config`/`--project-root`（连字符），
    内部统一存为下划线形式（greenix_config / project_root）。
    """
    args = {'type': None, 'project_root': None, 'greenix_config': None,
            'year': None, 'semester': None, 'check': False, 'help': False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith('--'):
            body = a[2:]
            if '=' in body:
                k, _, v = body.partition('=')
                args[k.replace('-', '_')] = v
                i += 1
            elif i + 1 < len(argv) and not argv[i + 1].startswith('--'):
                args[body.replace('-', '_')] = argv[i + 1]
                i += 2
            else:
                args[body.replace('-', '_')] = True
                i += 1
        else:
            i += 1
    return args


def _config_paths(args):
    paths = []
    if args.get('greenix_config'):
        paths.append(args['greenix_config'])
    env = os.environ.get('GREENIX_CONFIG_PATH')
    if env:
        paths.append(env)
    return [p for p in paths if p and os.path.isfile(p)]


def _get_config(key, args):
    """三级降级读凭证：--greenix-config（.greenix/config.json）→ 环境变量 → 报错。

    兼容配置 JSON 顶层扁平键或嵌套 {"settings": {...}} 形态。
    """
    for path in _config_paths(args):
        try:
            # utf-8-sig 兼容 Windows 编辑器可能写入的 UTF-8 BOM
            with open(path, 'r', encoding='utf-8-sig') as f:
                cfg = json.load(f)
        except Exception:
            continue
        if isinstance(cfg, dict):
            v = cfg.get(key)
            if isinstance(v, str) and v:
                return v
            settings = cfg.get('settings')
            if isinstance(settings, dict):
                v = settings.get(key)
                if isinstance(v, str) and v:
                    return v
    v = os.environ.get(key)
    if v:
        return v
    raise ConfigError(
        '未配置浙大统一认证凭证：请在设置面板填写 ZJU_USERNAME / ZJU_PASSWORD，'
        '或提供 --greenix-config（.greenix/config.json），或设置环境变量'
    )


def _current_semester():
    """当前教务学年起始年 + 学期码（对齐 _currentZjuSemester：9-2 月秋冬，3-8 月春夏）。"""
    now = datetime.now()
    is_autumn_winter = now.month >= 9 or now.month <= 2
    if is_autumn_winter:
        return now.year, _SEMESTER_AUTUMN_WINTER
    return now.year - 1, _SEMESTER_SPRING_SUMMER


# ── 输出 / 检查模式 ────────────────────────────────────────────────────
def _emit(obj):
    print(json.dumps(obj, ensure_ascii=False))


def _emit_error(err):
    payload = {'error': err.message, 'error_type': err.error_type}
    if err.detail:
        payload['detail'] = str(err.detail)
    print(json.dumps(payload, ensure_ascii=False))


def _usage_json():
    return {
        'type': 'help',
        'usage': 'scraper.py --type zju_schedule --project-root <root> --greenix-config <cfg>',
        'params': [
            '--type <typeArg>       数据源类型（本插件仅支持 zju_schedule）',
            '--project-root <root>  平台项目根目录（契约参数，本插件不使用）',
            '--greenix-config <cfg> 平台配置 JSON 路径（读取 ZJU_USERNAME / ZJU_PASSWORD）',
            '--year YYYY            教务学年起始年（默认按当前日期推算）',
            '--semester 3|12        教务学期码（3=秋冬，12=春夏；默认按当前日期推算）',
            '--check                连通性检查（无需凭证，验证 zjuam.zju.edu.cn 可达性）',
            '--help                 输出本说明',
        ],
        'exit_codes': {
            '0': '成功',
            '2': 'config_missing 凭证缺失',
            '3': 'auth_failed / session_expired 登录失败或会话失效',
            '4': 'network / timeout / http_error 网络或服务端错误',
            '5': 'parse_error / invalid_input 解析或参数错误',
            '1': 'unknown 未知错误',
        },
    }


def _run_check():
    """连通性检查：GET getPubKey 验证 zjuam 可达 + RSA 公钥服务正常（无需凭证）。"""
    sess = Session()
    body, status, _ = sess.request('GET', CAS_PUBKEY)
    try:
        pub = json.loads(body or '')
    except Exception:
        raise ParseError('getPubKey 返回非 JSON', detail=(body or '')[:200])
    ok = bool(pub.get('modulus') and pub.get('exponent'))
    _emit({
        'ok': ok,
        'zjuam_reachable': True,
        'message': ('浙大统一认证（zjuam.zju.edu.cn）可达，getPubKey 正常'
                    if ok else 'getPubKey 响应异常'),
    })
    return 0 if ok else 1


def main(argv=None):
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.get('help'):
            _emit(_usage_json())
            return 0
        if args.get('check'):
            return _run_check()

        type_arg = args.get('type') or 'zju_schedule'
        if type_arg != 'zju_schedule':
            raise InvalidInputError('未知 --type：%s（本插件仅支持 zju_schedule）' % type_arg)

        year, semester = _current_semester()
        if args.get('year'):
            year = int(args['year'])
        if args.get('semester'):
            semester = int(args['semester'])

        username = _get_config('ZJU_USERNAME', args)
        password = _get_config('ZJU_PASSWORD', args)

        sess = Session()
        sso = cas_login(sess, username, password)
        zdbk_login(sess, sso)
        sessions = fetch_timetable(sess, year, semester)

        _emit({
            'type': type_arg,
            'sessions': sessions,
            'year': year,
            'semester': semester,
            'count': len(sessions),
            'fetched_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        })
        return 0
    except ScraperError as e:
        _emit_error(e)
        return e.exit_code
    except Exception as e:  # 兜底：任何异常收敛为错误 JSON，不污染 stdout
        _emit_error(ScraperError('未知错误：%s' % e, detail=repr(e)))
        return 1


if __name__ == '__main__':
    sys.exit(main())
