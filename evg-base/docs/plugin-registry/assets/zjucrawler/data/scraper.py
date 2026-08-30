#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ZJU 教务数据源适配壳（zjucrawler）——纯标准库、真实数据、绝不伪造。

逆向接线（逐段对齐 evg-base 内置 Dart fetcher，参考
`lib/renderer/templates/zju_modle/`）：
  zju_data_sources.dart `_fetchZjuCourses`
    → ensureZjuSession（zju_session.dart：SSO cookie 复用 / 凭证登录）
    → ZjuAmService.login（zjuam_service.dart：CAS RSA 登录）
    → AuthService.loginCourses（auth_service.dart：courses 域会话换取）
    → CoursesApiService.getMyCourses（courses_api_service.dart：POST
      https://courses.zju.edu.cn/api/my-courses）

本脚本用 Python 标准库逐段复刻该链路：
  0. 会话复用（对齐 ensureZjuSession Tier 1）：本账号持久化 cookie jar
     （.greenix/zjucrawler_cookies_<hash>.txt）有效时直接取数；接口判
     「会话过期」才走完整登录。
  1. CAS 统一认证登录（https://zjuam.zju.edu.cn）：
     GET /cas/login 取 execution → GET /cas/v2/getPubKey 取 RSA 公钥
     → RSA 加密密码（对齐 zjuam_service.rsaEncrypt）→ POST /cas/login
     （_eventId=submit&rememberMe=true）→ 捕获 iPlanetDirectoryPro
     会话 cookie，以 .zju.edu.cn 域级注入 jar（对齐 zju_session._injectSsoCookie）。
  2. courses 域会话换取（https://courses.zju.edu.cn）：
     GET /user/index 沿 CAS 跳转链换取 courses 域会话 cookie
     （对齐 auth_service._loginCourses）。
  3. 取数：POST /api/my-courses（Content-Type: application/json）
     → 解析 `courses` 列表 → 归一化为内置 ZjuCourse.toJson 同款字段
     （id/name/course_code/class_name/teacher_name/teaching_place/
     course_type_name/is_started/is_closed/credits）。

契约（data-source 模型 A / CLI，见 lib/core/data/register_data_source.dart）：
  - 参数空格分隔：--type <typeArg> --project-root <root> --greenix-config <cfg>
  - stdout 只输出单个顶层 JSON Map（UTF-8）；日志一律走 stderr。
  - 成功：exit 0，顶层 Map（{"courses": [...], "count": N}）。
  - 失败：stdout 输出 {"error": "<中文信息>", "error_code": "<分类>", "code": <退出码>}
    且 exit code 非 0；任何异常都收敛为错误 JSON，绝不裸崩污染 stdout。
  - 凭证只经 _get_config 多级降级读取（--greenix-config 文件 → GREENIX_CONFIG_PATH
    文件 → ConfigHttpServer(.config_port) → 环境变量），绝不硬编码。

错误分类（error_code → exit code）：
  missing_config   → 2   未配置 ZJU_USERNAME / ZJU_PASSWORD
  auth_failed      → 3   CAS 登录被拒绝（学号/密码错误、登录页解析失败）
  session_expired  → 4   SSO 会话未被目标站接受（落在登录页/接口返回网页）
  network_error    → 5   网络不可达 / 超时 / TLS 失败 / HTTP 4xx/5xx
  parse_error      → 6   接口返回非预期格式
  unsupported_type → 7   --type 不在支持列表
  unknown          → 1   未分类异常兜底

历史说明：旧版把 zju_course 映射到 jwbinfosys 成绩页并泛泛解析 HTML 表格
（登录参数与数据形态均与真实接口不符）。本次改为只支持「我的课程」
（courses.zju.edu.cn/api/my-courses）；其它 --type 一律诚实报 unsupported_type，
绝不返回占位/伪造数据。

TLS 鲁棒性：个别 Windows 机器系统证书存储损坏会导致
`ssl.create_default_context()` 抛 `[ASN1: NOT_ENOUGH_DATA]`，使所有 https 请求
失败。本脚本自动回退到 OpenSSL 自带 CA bundle（仍严格校验证书，绝不降级为
不校验）；老站点（courses.zju.edu.cn）DH 参数过小被 OpenSSL 3 拒绝时，仅对
该连接降级 SECLEVEL=1 重试一次（证书校验保持不变）。
"""

import hashlib
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import http.cookiejar

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

# ── 端点（对齐 zju_modle 参考实现）─────────────────────────────────────────
ZJUAM_BASE = 'https://zjuam.zju.edu.cn'
CAS_LOGIN_URL = ZJUAM_BASE + '/cas/login'
CAS_PUBKEY_URL = ZJUAM_BASE + '/cas/v2/getPubKey'
COURSES_BASE = 'https://courses.zju.edu.cn'
COURSES_INDEX_URL = COURSES_BASE + '/user/index'
COURSES_API_MY_COURSES_URL = COURSES_BASE + '/api/my-courses'

NET_TIMEOUT = 15.0                # 单请求超时（秒）
TOTAL_DEADLINE_SECONDS = 58.0     # 平台 runOnce 60s 杀掉前自报错误（秒，留 2s 余量）

HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'),
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}

_EXIT_BY_CODE = {
    'missing_config': 2,
    'auth_failed': 3,
    'session_expired': 4,
    'network_error': 5,
    'parse_error': 6,
    'unsupported_type': 7,
    'unknown': 1,
}


class ZjuError(Exception):
    """带分类码的插件错误（error_code → exit code）。"""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code

    @property
    def exit_code(self):
        return _EXIT_BY_CODE.get(self.code, 1)


# ── 全局执行期限（防止平台 60s 超时杀进程时 stdout 为空）───────────────────
_START = None


def _reset_deadline():
    global _START
    _START = time.monotonic()


def _check_deadline():
    if _START is None:
        return
    if time.monotonic() - _START > TOTAL_DEADLINE_SECONDS:
        raise ZjuError('network_error',
                       '执行超时（>%ds），已终止' % int(TOTAL_DEADLINE_SECONDS))


def _log(msg):
    try:
        elapsed = ''
        if _START is not None:
            elapsed = '[%5.1fs] ' % (time.monotonic() - _START)
        sys.stderr.write('[zjucrawler] %s%s\n' % (elapsed, msg))
        sys.stderr.flush()
    except Exception:
        pass


# ── 会话（urllib + cookie jar，自动跟随重定向并收集每跳 cookie）─────────────
_SSL_CONTEXT = None
_SSL_CONTEXT_LEGACY = None


def _fallback_verify_context():
    """Windows 证书存储损坏时的回退：OpenSSL 自带 CA bundle（仍严格校验）。"""
    for cafile, capath in (
        (ssl.get_default_verify_paths().cafile, None),
        (os.environ.get('SSL_CERT_FILE'), None),
        (None, ssl.get_default_verify_paths().capath),
    ):
        try:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            if cafile and os.path.isfile(cafile):
                ctx.load_verify_locations(cafile=cafile)
                return ctx
            if capath and os.path.isdir(capath):
                ctx.load_verify_locations(capath=capath)
                return ctx
        except Exception:
            continue
    raise ZjuError('network_error',
                   '无法加载 TLS 证书信任库（系统证书存储损坏且无 CA bundle 可回退）')


def _make_ssl_context(seclevel1=False):
    """构建带证书校验的 TLS 上下文。

    默认走 `ssl.create_default_context()`；个别 Windows 机器的系统证书存储
    混入损坏证书时 `_load_windows_store_certs` 会抛 `[ASN1: NOT_ENOUGH_DATA]`，
    使**所有** https 请求失败。此时回退到 OpenSSL 自带的 CA bundle
    （get_default_verify_paths / SSL_CERT_FILE），绝不降级为不校验证书。

    [seclevel1]：老站点（如 courses.zju.edu.cn）协商 DH 参数过小会被
    OpenSSL 3.x 默认安全级别（2）拒绝（DH_KEY_TOO_SMALL）——此时回退
    `DEFAULT:@SECLEVEL=1`（允许 ≥1024 位 DH），证书校验保持不变。
    """
    try:
        ctx = ssl.create_default_context()
    except ssl.SSLError:
        _log('系统证书存储异常，回退 OpenSSL CA bundle')
        ctx = _fallback_verify_context()
    if seclevel1:
        try:
            ctx.set_ciphers('DEFAULT:@SECLEVEL=1')
        except ssl.SSLError:
            _log('SECLEVEL=1 设置失败，保持默认密码套件')
    return ctx


def _ssl_context(seclevel1=False):
    global _SSL_CONTEXT, _SSL_CONTEXT_LEGACY
    if seclevel1:
        if _SSL_CONTEXT_LEGACY is None:
            _SSL_CONTEXT_LEGACY = _make_ssl_context(seclevel1=True)
        return _SSL_CONTEXT_LEGACY
    if _SSL_CONTEXT is None:
        _SSL_CONTEXT = _make_ssl_context(seclevel1=False)
    return _SSL_CONTEXT


class _RecordingRedirectHandler(urllib.request.HTTPRedirectHandler):
    """记录 3xx 跳转响应的 Set-Cookie（登录 POST 的会话 cookie 常在 302 上）。"""

    def __init__(self):
        super().__init__()
        self.redirect_set_cookies = []

    def _record(self, fp, code, msg, headers):
        for raw in headers.get_all('Set-Cookie', []) or []:
            self.redirect_set_cookies.append(raw)
        return None

    def http_error_301(self, req, fp, code, msg, headers):
        self._record(fp, code, msg, headers)
        return super().http_error_301(req, fp, code, msg, headers)

    def http_error_302(self, req, fp, code, msg, headers):
        self._record(fp, code, msg, headers)
        return super().http_error_302(req, fp, code, msg, headers)

    def http_error_303(self, req, fp, code, msg, headers):
        self._record(fp, code, msg, headers)
        return super().http_error_303(req, fp, code, msg, headers)

    def http_error_307(self, req, fp, code, msg, headers):
        self._record(fp, code, msg, headers)
        return super().http_error_307(req, fp, code, msg, headers)

    def http_error_308(self, req, fp, code, msg, headers):
        self._record(fp, code, msg, headers)
        return super().http_error_308(req, fp, code, msg, headers)


class Session:
    def __init__(self, jar=None):
        self.cj = jar if jar is not None else http.cookiejar.CookieJar()
        self._redirect = _RecordingRedirectHandler()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cj),
            urllib.request.HTTPSHandler(context=_ssl_context(seclevel1=False)),
            self._redirect,
        )
        self.set_cookie_headers = []  # 本会话所有响应（含 3xx）的 Set-Cookie 原文
        self._legacy_tls = False      # 老站点 DH 过小时降级一次（仍校验证书）

    def _enable_legacy_tls(self):
        """目标站 DH 参数过小（OpenSSL 3 拒绝）→ SECLEVEL=1 重建 opener 重试。"""
        self._legacy_tls = True
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cj),
            urllib.request.HTTPSHandler(context=_ssl_context(seclevel1=True)),
            self._redirect,
        )
        _log('目标站 DH 密钥过小，降级 TLS 安全级别重试（仍严格校验证书）')

    @staticmethod
    def _dh_too_small(exc):
        return 'dh key too small' in str(exc).lower()

    def get(self, url, timeout=NET_TIMEOUT):
        req = urllib.request.Request(url, headers=dict(HEADERS))
        return self._open(req, timeout)

    def post(self, url, data, timeout=NET_TIMEOUT,
             extra_headers=None, raw_body=False):
        """data 为 dict（表单）或 bytes（raw_body=True 时原样发送）。"""
        headers = dict(HEADERS)
        if extra_headers:
            headers.update(extra_headers)
        if raw_body:
            body = data
            headers.setdefault('Content-Type', 'application/x-www-form-urlencoded')
        else:
            body = urllib.parse.urlencode(data).encode('utf-8')
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req = urllib.request.Request(url, data=body, headers=headers)
        return self._open(req, timeout)

    def _open(self, req, timeout):
        _check_deadline()
        try:
            with self.opener.open(req, timeout=timeout) as resp:
                final_url = resp.geturl()
                body = resp.read()
                self.set_cookie_headers.extend(
                    resp.headers.get_all('Set-Cookie', []) or [])
        except urllib.error.HTTPError as e:
            self.set_cookie_headers.extend(
                e.headers.get_all('Set-Cookie', []) or [])
            if e.code in (401, 403, 901):
                raise ZjuError('session_expired',
                               '目标站返回 HTTP %s——SSO 会话可能已过期' % e.code) from None
            raise ZjuError('network_error',
                           'HTTP %s：%s（%s）' % (e.code, e.reason, req.full_url)) from None
        except urllib.error.URLError as e:
            reason = e.reason
            if isinstance(reason, socket.timeout):
                raise ZjuError('network_error',
                               '请求超时：%s' % req.full_url) from None
            if not self._legacy_tls and self._dh_too_small(reason):
                self._enable_legacy_tls()
                return self._open(req, timeout)
            raise ZjuError('network_error',
                           '网络错误：%s（%s）' % (req.full_url, reason)) from None
        except (ssl.SSLError, OSError) as e:
            # 读响应阶段的原生 TLS/IO 错误（握手错误已被 urllib 包装为 URLError）
            if not self._legacy_tls and self._dh_too_small(e):
                self._enable_legacy_tls()
                return self._open(req, timeout)
            raise ZjuError('network_error',
                           '网络/TLS 错误：%s（%s）' % (req.full_url, e)) from None
        _check_deadline()
        return body.decode('utf-8', errors='replace'), final_url


# ── CAS 登录（对齐 ZjuAmService.login + zju_session._injectSsoCookie）────────
def _rsa_encrypt(password, modulus_hex, exponent_hex):
    """RSA 加密密码：UTF-8 bytes → 大整数 → c = m^e mod n → hex（最少 128 位）。

    对齐 zjuam_service.rsaEncrypt：字节先转 hex 再按大整数解析，
    与 int.from_bytes 等价；结果 rjust(128,'0') 与 padLeft(128,'0') 等价。
    """
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    m = int.from_bytes(password.encode('utf-8'), 'big')
    c = pow(m, e, n)
    return format(c, 'x').rjust(128, '0')


def _jar_cookie_value(cj, name):
    for c in cj:
        if c.name == name and c.value:
            return c.value
    return None


def _find_sso_value(session):
    """从已记录的 Set-Cookie 原文 / jar 中取 iPlanetDirectoryPro 值。"""
    for raw in session.set_cookie_headers:
        m = re.search(r'(?:^|;\s*)iPlanetDirectoryPro=([^;]+)', raw)
        if m:
            return m.group(1)
    return _jar_cookie_value(session.cj, 'iPlanetDirectoryPro')


def _inject_sso_cookie(cj, value):
    """以 .zju.edu.cn 域级注入 SSO cookie（对齐 zju_session._injectSsoCookie）。"""
    cookie = http.cookiejar.Cookie(
        version=0, name='iPlanetDirectoryPro', value=value,
        port=None, port_specified=False,
        domain='.zju.edu.cn', domain_specified=True, domain_initial_dot=True,
        path='/', path_specified=True,
        secure=False, expires=None, discard=True,
        comment=None, comment_url=None, rest={}, rfc2109=False,
    )
    cj.set_cookie(cookie)
    # 移除 host-only 副本，避免同名字段重复发送
    try:
        cj.clear(domain='zjuam.zju.edu.cn', path='/', name='iPlanetDirectoryPro')
    except Exception:
        pass


def _sso_login(session, username, password):
    """CAS 统一认证登录，返回 iPlanetDirectoryPro 值（失败抛 ZjuError）。"""
    # 1) GET /cas/login（无 service，对齐参考）→ execution token + 会话 cookie
    page, _ = session.get(CAS_LOGIN_URL)
    m = re.search(r'name="execution"\s+value="([^"]+)"', page)
    if not m:
        raise ZjuError('auth_failed',
                       '无法从 CAS 登录页提取 execution（页面结构可能已变更或被拦截）')
    execution = m.group(1)

    # 2) GET /cas/v2/getPubKey → RSA 公钥
    raw, _ = session.get(CAS_PUBKEY_URL)
    try:
        pub = json.loads(raw)
    except ValueError:
        raise ZjuError('parse_error', 'CAS getPubKey 返回非 JSON 数据')
    modulus = pub.get('modulus') if isinstance(pub, dict) else None
    exponent = pub.get('exponent') if isinstance(pub, dict) else None
    if not modulus or not exponent:
        raise ZjuError('parse_error', 'CAS getPubKey 缺少 modulus/exponent')

    # 3) RSA 加密 + 提交表单（参数对齐 zjuam_service 第 4 步）
    enc_pwd = _rsa_encrypt(password, modulus, exponent)
    session.post(CAS_LOGIN_URL, {
        'username': username,
        'password': enc_pwd,
        'execution': execution,
        '_eventId': 'submit',
        'rememberMe': 'true',
    })

    sso = _find_sso_value(session)
    if not sso:
        raise ZjuError('auth_failed',
                       'SSO 登录失败：CAS 未签发会话（学号或密码错误）')
    _inject_sso_cookie(session.cj, sso)
    return sso


def _login_courses(session):
    """换取 courses.zju.edu.cn 域会话（对齐 auth_service._loginCourses 跳转链）。"""
    _, final_url = session.get(COURSES_INDEX_URL)
    host = urllib.parse.urlparse(final_url).hostname or ''
    if 'courses.zju.edu.cn' not in host:
        raise ZjuError('session_expired',
                       'courses.zju.edu.cn 未接受 SSO 会话（跳转落在 %s）'
                       '——会话可能已过期，请重新登录' % host)


def _normalize_course(raw):
    """归一化单门课程为内置 ZjuCourse.toJson 同款字段（对齐 fromJson 容错）。

    字符串字段统一 str() 化（对齐 Dart `.toString()`），避免数值型
    course_type_name 等造成类型漂移。
    """
    if not isinstance(raw, dict):
        raw = {}

    def raw_first(*keys):
        for k in keys:
            v = raw.get(k)
            if v is not None and v != '':
                return v
        return None

    def str_first(*keys):
        v = raw_first(*keys)
        return str(v) if v is not None else None

    teacher_name = str_first('teacher_name')
    if not teacher_name:
        instructors = raw.get('instructors')
        if isinstance(instructors, list) and instructors:
            first_teacher = instructors[0]
            if isinstance(first_teacher, dict) and first_teacher.get('name'):
                teacher_name = str(first_teacher.get('name'))

    started = raw.get('is_started')
    closed = raw.get('is_closed')
    credits_raw = raw.get('credits')
    credits = float(credits_raw) if isinstance(credits_raw, (int, float)) else 0.0
    course_id = raw_first('id', 'course_id')

    return {
        'id': course_id if course_id is not None else 0,
        'name': str_first('name', 'course_name') or '',
        'course_code': str_first('course_code'),
        'class_name': str_first('class_name'),
        'teacher_name': teacher_name,
        'teaching_place': str_first('teaching_place'),
        'course_type_name': str_first('course_type_name', 'course_type'),
        'is_started': started is True or started == 1,
        'is_closed': closed is True or closed == 1,
        'credits': credits,
    }


def _fetch_my_courses(session):
    """POST /api/my-courses（对齐 CoursesApiService.getMyCourses）。"""
    body, _ = session.post(
        COURSES_API_MY_COURSES_URL,
        b'',
        extra_headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/plain, */*',
        },
        raw_body=True,
    )
    text = body.strip()
    if text.startswith('<'):
        raise ZjuError('session_expired',
                       '课程列表接口返回了网页而非数据——SSO 会话可能已过期，请重新登录')
    try:
        data = json.loads(text)
    except ValueError:
        raise ZjuError('parse_error', '课程列表接口返回了无效 JSON')
    if not isinstance(data, dict):
        raise ZjuError('parse_error', '课程列表接口返回格式异常（非 JSON 对象）')
    raw_courses = data.get('courses')
    if raw_courses is None:
        raise ZjuError('parse_error', '课程列表接口缺少 courses 字段')
    if not isinstance(raw_courses, list):
        raise ZjuError('parse_error', '课程列表接口 courses 字段不是数组')
    courses = [_normalize_course(c) for c in raw_courses]
    return {'courses': courses, 'count': len(courses)}


# ── 持久化会话复用（对齐 ensureZjuSession Tier 1：复用 cookie → 过期重登）──
def _cookie_file_candidates(opts, username):
    """cookie 文件候选路径（按用户名区分，防跨账号串用；与平台 CookieStore
    同目录族，格式为 http.cookiejar Mozilla 格式）。"""
    name = 'zjucrawler_cookies_%s.txt' % hashlib.sha256(
        username.encode('utf-8')).hexdigest()[:8]
    candidates = []
    cfg = opts.get('greenix-config')
    if cfg:
        candidates.append(os.path.join(os.path.dirname(os.path.abspath(cfg)), name))
    root = opts.get('project-root')
    if root:
        candidates.append(os.path.join(root, '.greenix', name))
    return candidates


def _has_courses_cookie(jar):
    for c in jar:
        if 'courses.zju.edu.cn' in (c.domain or ''):
            return True
    return False


def _load_jar(opts, username):
    """读入本账号持久化 cookie jar；无文件或缺失 courses 会话 cookie → None。"""
    for path in _cookie_file_candidates(opts, username):
        if path and os.path.isfile(path):
            jar = http.cookiejar.MozillaCookieJar(path)
            try:
                jar.load(ignore_discard=True, ignore_expires=True)
            except Exception:
                return None
            if _has_courses_cookie(jar):
                _log('复用持久化会话 cookie（%s）' % os.path.basename(path))
                return jar
    return None


def _save_jar(jar, opts, username):
    """持久化登录后的 cookie jar（仅会话 cookie，不含密码）；失败仅记日志。"""
    for path in _cookie_file_candidates(opts, username):
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            mj = http.cookiejar.MozillaCookieJar(path)
            for c in jar:
                mj.set_cookie(c)
            mj.save(ignore_discard=True, ignore_expires=True)
            _log('持久化会话 cookie 已保存（%s）' % os.path.basename(path))
            return
        except Exception as e:
            _log('cookie 持久化失败（%s）：%s' % (path, e))


# ── 配置读取（多级降级，绝不硬编码凭证）─────────────────────────────────────
def _read_port_file(project_root=None):
    """向上查找 .config_port（ConfigHttpServer 端口文件）。"""
    bases = [os.getcwd()]
    if project_root:
        bases.append(project_root)
    seen = set()
    for base in bases:
        d = os.path.abspath(base)
        while d and d not in seen and d != os.path.dirname(d):
            seen.add(d)
            pf = os.path.join(d, '.config_port')
            if os.path.isfile(pf):
                try:
                    with open(pf, 'r') as f:
                        port = f.read().strip()
                    return port if port.isdigit() else None
                except Exception:
                    return None
            d = os.path.dirname(d)
    return None


def _get_config(key, cfg_arg=None, project_root=None):
    """读取配置/凭证（多级降级）。

    Tier 0：--greenix-config 显式文件（平台主通道）
    Tier 1：GREENIX_CONFIG_PATH 环境变量指向的文件
    Tier 2：ConfigHttpServer（.config_port → /config/settings/<key>）
    Tier 3：系统环境变量
    """
    candidates = []
    if cfg_arg:
        candidates.append(cfg_arg)
    env_cfg = os.environ.get('GREENIX_CONFIG_PATH')
    if env_cfg:
        candidates.append(env_cfg)
    for path in candidates:
        try:
            if path and os.path.isfile(path):
                with open(path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key)
                if isinstance(val, str) and val:
                    return val
        except Exception:
            pass
    try:
        port = _read_port_file(project_root)
        if port:
            url = 'http://127.0.0.1:%s/config/settings/%s' % (port, key)
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode('utf-8', errors='replace'))
            val = (data or {}).get('value')
            if isinstance(val, str) and val:
                return val
    except Exception:
        pass
    val = os.environ.get(key)
    return val if val else None


# ── CLI 入口（空格分隔参数）─────────────────────────────────────────────────
def _parse_args(argv):
    opts = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith('--') and '=' in arg:
            k, v = arg[2:].split('=', 1)
            opts[k] = v
            i += 1
        elif arg.startswith('--') and i + 1 < len(argv):
            opts[arg[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return opts


def _fail(err):
    payload = {
        'error': str(err),
        'error_code': err.code,
        'code': err.exit_code,
    }
    print(json.dumps(payload, ensure_ascii=False))
    sys.stderr.write('[zjucrawler] 失败（%s）：%s\n' % (err.code, err))
    sys.stderr.flush()


def main(argv):
    _reset_deadline()
    opts = _parse_args(argv)
    type_arg = opts.get('type', 'zju_course')

    if type_arg not in ('zju_course', 'zju_courses'):
        _fail(ZjuError(
            'unsupported_type',
            '不支持的 --type=%r（本插件仅支持 zju_course 我的课程；'
            '成绩请用 zju-grades 插件，课表请用 zju-schedule 插件）' % type_arg))
        return _EXIT_BY_CODE['unsupported_type']

    creds = {}
    missing = []
    for key in ('ZJU_USERNAME', 'ZJU_PASSWORD'):
        val = _get_config(key,
                          cfg_arg=opts.get('greenix-config'),
                          project_root=opts.get('project-root'))
        if val:
            creds[key] = val
        else:
            missing.append(key)
    if missing:
        _fail(ZjuError(
            'missing_config',
            '未配置浙大统一认证凭据：缺少 %s——请在设置面板填写，'
            '或提供含该 key 的 --greenix-config 配置文件' % '、'.join(missing)))
        return _EXIT_BY_CODE['missing_config']

    try:
        username = creds['ZJU_USERNAME']

        # 1) 快路径：复用本账号持久化会话（对齐 ensureZjuSession Tier 1）。
        #    仅当 API 判「会话过期」才走完整登录，避免慢网下逼近平台 60s 超时，
        #    也减少 CAS 登录挤占。
        reused = _load_jar(opts, username)
        if reused is not None:
            session = Session(jar=reused)
            try:
                result = _fetch_my_courses(session)
                _log('我的课程拉取成功（会话复用）：%d 门' % result['count'])
                print(json.dumps(result, ensure_ascii=False))
                return 0
            except ZjuError as e:
                if e.code != 'session_expired':
                    raise
                _log('持久化会话已过期，执行完整登录…')

        # 2) 完整登录：SSO（CAS RSA）→ courses 会话 → 持久化 → 取数
        session = Session()
        _log('SSO 登录…')
        _sso_login(session, username, creds['ZJU_PASSWORD'])
        _log('SSO 登录成功，换取 courses 会话…')
        _login_courses(session)
        _log('courses 会话就绪，拉取我的课程…')
        _save_jar(session.cj, opts, username)
        result = _fetch_my_courses(session)
        _log('我的课程拉取成功：%d 门' % result['count'])
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except ZjuError as e:
        _fail(e)
        return e.exit_code
    except Exception as e:  # 兜底：绝不裸崩污染 stdout
        _fail(ZjuError('unknown', '未知错误：%s' % e))
        return _EXIT_BY_CODE['unknown']


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
