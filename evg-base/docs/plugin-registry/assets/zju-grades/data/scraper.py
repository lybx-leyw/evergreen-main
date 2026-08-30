#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大成绩数据源适配壳（data-source 插件 · 模型 A CLI）——ZDBK 教务网真实成绩单。

逆向接线说明
============
本脚本与平台内置 Dart fetcher 同源同构（同接口、同解析、同 GPA 口径），参考对象：

  zju_modle/zju_data_sources.dart                → zju_scores 数据源（成绩 + 双策略 GPA）
  zju_modle/zdbk/services/zdbk_service.dart      → ZDBK 登录 + getTranscript + 自动重登
  zju_modle/zju_auth/zjuam_service.dart          → CAS SSO 登录 + RSA 公钥加密
  zju_modle/zju_auth/zju_session.dart            → ensureZdbkSession（SSO cookie → ZDBK 会话）
  zju_modle/zju_auth/zdbk_patterns.dart          → items 数组提取正则
  zju_modle/shared/models/zju_grade.dart         → 成绩模型（排除规则 / 映射表）
  zju_modle/shared/utils/zju_gpa_calculator.dart → 双策略 GPA（保研首考 / 出国最高）

登录链路（纯 Python 标准库，零第三方依赖）
------------------------------------------
  1. CAS SSO 登录 zjuam.zju.edu.cn：
     GET  /cas/login           → 解析 execution token
     GET  /cas/v2/getPubKey    → RSA 公钥（modulus/exponent，hex）
     POST /cas/login           → RSA 加密密码 + execution + rememberMe=true
                                → 换取 iPlanetDirectoryPro 会话 cookie
  2. ZDBK 教务会话：
     GET  /cas/login?service=<zdbk sso 落地页>（带 SSO cookie，禁重定向）
                                → 读 302 Location
     GET  Location             → 收集 JSESSIONID(path=/jwglxt) + route cookie
  3. 成绩单（对齐 zdbk_service.getTranscript）：
     POST https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html
          ?doType=query&queryModel.showCount=5000
     标准头（Referer / X-Requested-With / Accept）+ 会话 cookie
     → 响应含 items JSON 数组 → 解析 → grades
  4. 会话过期检测：响应命中 CAS 登录页特征（login_ssologin/cas/login/统一身份认证…）
     → 自动重登 1 次（对齐 zdbk_service._withAutoRelogin）→ 仍失败则报错，
     错误信息含 "ZdbkAuthError"（平台 SessionCoordinator 可据此识别为会话失效
     并走 zju 会话提供者单点重登后重拉，见 zju_session.zjuIsSessionExpiredError）。

契约（docs/plugin-registry/plugin-registry-spec-v1.md §六）
----------------------------------------------------------
  - 调用：scraper.py --type <typeArg> --project-root <root> --greenix-config <cfg>
  - stdout 顶层 Map，UTF-8（ensure_ascii=False）：
      成功：{"grades": [...], "domestic_gpa": {...}, "abroad_gpa": {...}}
      失败：{"error": "<人类可读>", "errorClass": "<分类>"} + 非零退出
  - 凭证：--greenix-config 的 config.json（ZJU_USERNAME / ZJU_PASSWORD）
          → GREENIX_CONFIG_PATH / <project-root>/.greenix/config.json → 环境变量
  - 任何异常收敛为错误 JSON，绝不向 stdout 抛堆栈；stderr 仅诊断信息。

诚信底线：本插件只输出教务网真实返回的成绩数据；无法登录/取数时输出明确错误，
绝不伪造成绩。未配置凭证或登录失败均以 error JSON + 非零退出码呈现。
"""
import http.cookiejar
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

try:  # Windows 控制台 / 管道统一 UTF-8
    sys.stdout.reconfigure(encoding='utf-8')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

# ── 端点（对齐 Dart 参考）──────────────────────────────────────────────
ZJUAM_URL = "https://zjuam.zju.edu.cn"
CAS_LOGIN_URL = ZJUAM_URL + "/cas/login"
CAS_PUBKEY_URL = ZJUAM_URL + "/cas/v2/getPubKey"
ZDBK_SSO_SERVICE = "https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html"
ZDBK_URL = "https://zdbk.zju.edu.cn"
ZDBK_TRANSCRIPT_URL = (
    ZDBK_URL + "/jwglxt/cxdy/xscjcx_cxXscjIndex.html"
    "?doType=query&queryModel.showCount=5000"
)
ZDBK_REFERER = "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html"

USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
TIMEOUT = 10  # 每请求超时（秒），对齐 Dart NetworkConfig / 参考实现

# ── 解析正则（对齐 zdbk_patterns.dart）─────────────────────────────────
ITEMS_WITH_LIMIT = re.compile(r'(?<="items":)\[(.*?)\](?=,"limit")', re.S)
ITEMS_WITH_TOTAL_RESULT = re.compile(
    r'(?<="items":)\[(.*?)\](?=,"totalResult")', re.S)
EXECUTION_TOKEN = re.compile(r'name="execution"\s+value="([^"]+)"')
REAL_ID = re.compile(r'(\(.*\)-.*?)-.*')
FIRST_DIGITS = re.compile(r'(\d+)')

# CAS 登录页特征（对齐 html_parser.isSessionExpired）
_SESSION_EXPIRED_MARKERS = (
    'login_ssologin', 'cas/login', 'idp.zju.edu.cn',
    '统一身份认证', '统一认证', '/cas/',
)

# ── 错误分类（stdout errorClass + 非零退出码）───────────────────────────
EXIT_OK = 0
EXIT_UNKNOWN = 1
EXIT_CONFIG = 2
EXIT_NETWORK = 3
EXIT_AUTH = 4
EXIT_PARSE = 5


class ScraperError(Exception):
    error_class = 'unknown'
    exit_code = EXIT_UNKNOWN


class ConfigError(ScraperError):
    error_class = 'config_missing'
    exit_code = EXIT_CONFIG


class NetworkError(ScraperError):
    error_class = 'network'
    exit_code = EXIT_NETWORK


class AuthError(ScraperError):
    error_class = 'auth'
    exit_code = EXIT_AUTH


class SessionExpired(ScraperError):
    """ZDBK 会话失效。消息带 ZdbkAuthError 前缀供平台会话协调器识别重登。"""
    error_class = 'session_expired'
    exit_code = EXIT_AUTH

    def __init__(self, message):
        prefix = 'ZdbkAuthError: '
        super().__init__(prefix + message if not message.startswith(prefix)
                         else message)


class ParseError(ScraperError):
    error_class = 'parse'
    exit_code = EXIT_PARSE


# ── 工具函数 ───────────────────────────────────────────────────────────
def _ssl_context():
    """默认校验 TLS；个别 Windows Python 发行版证书库损坏时优雅降级。

    注意：降级为不校验会在该环境下削弱传输保护（RSA 加密的密码可缓解，
    但会话 cookie 为明文）。仅在 `ssl.create_default_context()` 直接抛错
    （如 Conda 版 Python 加载 Windows 证书库失败）时才启用降级。
    """
    try:
        return ssl.create_default_context()
    except Exception:
        return ssl._create_unverified_context()  # noqa: S323


def rsa_encrypt(password: str, modulus_hex: str, exponent_hex: str) -> str:
    """RSA 公钥加密，逐位对齐 zjuam_service.rsaEncrypt：
    UTF-8 字节 → 大整数 → modPow(e, n) → hex（补零至 128 位）。"""
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    m = int.from_bytes(password.encode('utf-8'), 'big')
    c = pow(m, e, n)
    return format(c, 'x').rjust(128, '0')


def _to_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁重定向：redirect_request 返回 None → urllib 以 HTTPError 暴露 3xx，
    供读取 Location 头（对齐 zdbk_service.login 的 followRedirects=false）。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D102
        return None


# ── ZJU 成绩模型（对齐 zju_grade.dart）────────────────────────────────
_FIVE_POINT_BY_TEXT = {
    '优': 5.0, '优秀': 5.0, '良': 4.0, '良好': 4.0, '中': 3.0, '中等': 3.0,
    '及格': 2.0, '合格': 2.0, '不及格': 0.0, '不合格': 0.0,
}

_FIVE_TO_FOUR = {5.0: 4.3, 4.8: 4.2, 4.5: 4.1, 4.2: 4.0}

_TO_HUNDRED_POINT = {
    'A+': 95, 'A': 90, 'A-': 87, 'B+': 83, 'B': 80, 'B-': 77,
    'C+': 73, 'C': 70, 'C-': 67, 'D': 60, 'F': 0,
    '优秀': 90, '良好': 80, '中等': 70, '及格': 60, '不及格': 0,
    '合格': 75, '不合格': 0, '弃修': 0, '缺考': 0, '缓考': 0, '待录': 0, '无效': 0,
}

_EXCLUDED_TEXTS = ('弃修', '待录', '缓考', '无效', '合格', '不合格')
_NO_EARNED_TEXTS = ('弃修', '待录', '缓考', '无效')


def _score_to_five_point(score: str) -> float:
    """原始成绩串 → 五分制绩点（仅当 ZDBK 权威 jd 字段缺失时回退）。"""
    if score in _FIVE_POINT_BY_TEXT:
        return _FIVE_POINT_BY_TEXT[score]
    num = _to_number(score)
    if num is not None:
        if num >= 90:
            return 5.0
        if num >= 80:
            return 4.0
        if num >= 70:
            return 3.0
        if num >= 60:
            return 2.0
        return 0.0
    return 0.0


class ZjuGrade:
    """一门成绩记录（对齐 ZjuGrade 的字段与派生口径）。"""

    __slots__ = ('id', 'name', 'credit', 'original', 'five_point', 'major')

    def __init__(self, id_, name, credit, original, five_point, major=False):
        self.id = id_                  # 选课课号 xkkh
        self.name = name               # 课程名称 kcmc
        self.credit = credit           # 学分 xf
        self.original = original       # 原始成绩串 cj
        self.five_point = five_point   # 权威绩点 jd（5.0/4.8/4.2/…）
        self.major = major             # 是否主修

    @classmethod
    def from_json(cls, it):
        jd = _to_number(it.get('jd'))
        if jd is not None:
            five_point = jd
        else:
            five_point = _score_to_five_point(str(it.get('cj') or ''))
        return cls(
            id_=str(it.get('xkkh') or ''),
            name=str(it.get('kcmc') or '未命名课程'),
            credit=_to_number(it.get('xf')) or 0.0,
            original=str(it.get('cj') or ''),
            five_point=five_point,
            major=bool(it.get('major')),
        )

    def to_json(self):
        return {'xkkh': self.id, 'kcmc': self.name, 'xf': self.credit,
                'cj': self.original, 'jd': self.five_point, 'major': self.major}

    # ── 派生口径（与 ZjuGrade 一致）────────────────────────────────────
    @property
    def excluded(self):
        return (self.original in _EXCLUDED_TEXTS
                or 'xtwkc' in self.id or self.credit <= 0)

    @property
    def earned_credit(self):
        if (self.original not in _NO_EARNED_TEXTS
                and (self.five_point != 0 or 'xtwkc' in self.id)):
            return self.credit
        return 0.0

    @property
    def four_point(self):
        if self.five_point > 4.0:
            return _FIVE_TO_FOUR.get(self.five_point, 4.0)
        return self.five_point

    @property
    def four_point_legacy(self):
        return 4.0 if self.five_point > 4.0 else self.five_point

    @property
    def hundred_point(self):
        if self.original in _TO_HUNDRED_POINT:
            return _TO_HUNDRED_POINT[self.original]
        num = _to_number(self.original)
        if num is not None:
            return int(round(num))
        m = FIRST_DIGITS.search(self.original)
        if m:
            try:
                return int(m.group(1))
            except ValueError:
                pass
        return 0

    @property
    def real_id(self):
        """真实课程 ID：去掉重修后缀，同一门课的不同修读记录共享分组键。"""
        m = REAL_ID.search(self.id)
        if m:
            return m.group(1)
        return self.id if len(self.id) < 22 else self.id[:22]


class ZjuGpaResult:
    """一套 GPA 计算结果（4 刻度 + 已获学分），对齐 ZjuGpaResult.toJson。"""

    __slots__ = ('five_point', 'four_point', 'four_point_legacy',
                 'hundred_point', 'earned_credits')

    def __init__(self, five_point, four_point, four_point_legacy,
                 hundred_point, earned_credits):
        self.five_point = five_point
        self.four_point = four_point
        self.four_point_legacy = four_point_legacy
        self.hundred_point = hundred_point
        self.earned_credits = earned_credits

    def to_json(self):
        return {'five_point': self.five_point,
                'four_point': self.four_point,
                'four_point_legacy': self.four_point_legacy,
                'hundred_point': self.hundred_point,
                'earned_credits': self.earned_credits}


def calculate_gpa(grades):
    """学分加权 GPA（对齐 ZjuGpaCalculator.calculateGpa）。"""
    earned = sum(g.earned_credit for g in grades)
    filtered = [g for g in grades if not g.excluded]
    if not filtered:
        return ZjuGpaResult(0.0, 0.0, 0.0, 0.0, earned)
    total = sum(g.credit for g in filtered)
    if total <= 0:
        return ZjuGpaResult(0.0, 0.0, 0.0, 0.0, earned)
    w5 = sum(g.five_point * g.credit for g in filtered)
    w4 = sum(g.four_point * g.credit for g in filtered)
    w4l = sum(g.four_point_legacy * g.credit for g in filtered)
    wh = sum(g.hundred_point * g.credit for g in filtered)
    return ZjuGpaResult(w5 / total, w4 / total, w4l / total, wh / total, earned)


def group_by_course_id(grades):
    """按真实课程 ID 分组（重修归一化，保插入顺序）。"""
    groups = {}
    for g in grades:
        groups.setdefault(g.real_id, []).append(g)
    return groups


def pick_first_attempt(grades):
    """每门课首次修读成绩（保研口径）。"""
    return [group[0] for group in group_by_course_id(grades).values()]


def pick_highest_attempt(grades):
    """每门课百分制最高的一次成绩（出国口径，并列取先出现者）。"""
    return [max(group, key=lambda g: g.hundred_point)
            for group in group_by_course_id(grades).values()]


# ── 会话与请求（对齐 zjuam_service / zdbk_service）────────────────────
class ZdbkClient:
    """CAS SSO → ZDBK 会话 → 成绩单请求（单一 cookie jar 贯穿全程）。"""

    def __init__(self):
        self._jar = http.cookiejar.CookieJar()
        ctx = _ssl_context()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self._jar),
            urllib.request.HTTPSHandler(context=ctx),
        )
        # 仅 service validation 用：禁重定向以读取 Location
        self._no_redirect = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self._jar),
            urllib.request.HTTPSHandler(context=ctx),
            _NoRedirect(),
        )
        self._headers = {'User-Agent': USER_AGENT,
                         'Accept-Language': 'zh-CN,zh;q=0.9'}
        self._logged_in = False

    def _reset(self):
        self._jar.clear()
        self._logged_in = False

    # -- 底层请求 -------------------------------------------------------
    def _open(self, url, data=None, headers=None, timeout=TIMEOUT):
        hdrs = dict(self._headers)
        if headers:
            hdrs.update(headers)
        req = urllib.request.Request(url, data=data, headers=hdrs)
        try:
            return self._opener.open(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            raise NetworkError('HTTP %s: %s' % (e.code, url)) from e
        except (urllib.error.URLError, socket.timeout, ssl.SSLError,
                ConnectionError, OSError) as e:
            raise NetworkError('无法连接 %s：%s' % (url, e)) from e

    def _get(self, url, timeout=TIMEOUT):
        with self._open(url, timeout=timeout) as resp:
            return resp.read().decode('utf-8', errors='replace')

    def _get_location(self, url, timeout=TIMEOUT):
        """GET 且不跟随重定向 → 返回 Location 头（无重定向返回 None）。"""
        req = urllib.request.Request(url, headers=dict(self._headers))
        try:
            with self._no_redirect.open(req, timeout=timeout):
                return None
        except urllib.error.HTTPError as e:
            return e.headers.get('Location')
        except (urllib.error.URLError, socket.timeout, ssl.SSLError,
                ConnectionError, OSError) as e:
            raise NetworkError('无法连接 %s：%s' % (url, e)) from e

    def _zdbk_post(self, url, timeout=TIMEOUT):
        """ZDBK 标准头 POST（对齐 _zdbkSetHeaders），会话过期抛 SessionExpired。"""
        headers = {
            'Referer': ZDBK_REFERER,
            'Connection': 'close',
            'User-Agent': USER_AGENT,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
        }
        body = self._open(url, data=b'', headers=headers,
                          timeout=timeout).read().decode('utf-8',
                                                          errors='replace')
        if self._is_session_expired(body):
            raise SessionExpired('ZDBK 会话过期')
        return body

    @staticmethod
    def _is_session_expired(text):
        return any(marker in text for marker in _SESSION_EXPIRED_MARKERS)

    def _has_zdbk_cookies(self):
        j, route = False, False
        for c in self._jar:
            if c.name == 'JSESSIONID' and c.path == '/jwglxt':
                j = True
            if c.name == 'route':
                route = True
        return j and route

    # -- 登录链路 -------------------------------------------------------
    def sso_login(self, username, password):
        """CAS SSO 登录 → iPlanetDirectoryPro cookie 值（对齐 ZjuAmService）。"""
        # 1) 登录页 → execution token
        page = self._get(CAS_LOGIN_URL)
        m = EXECUTION_TOKEN.search(page)
        if not m:
            raise ParseError(
                'CAS 登录页解析失败（execution token 缺失）——页面结构可能已变更')
        execution = m.group(1)

        # 2) RSA 公钥
        pub_body = self._get(CAS_PUBKEY_URL)
        try:
            pub = json.loads(pub_body)
        except ValueError:
            raise ParseError('CAS 公钥接口（getPubKey）返回非 JSON') from None
        modulus = pub.get('modulus')
        exponent = pub.get('exponent')
        if not modulus or not exponent:
            raise ParseError('CAS 公钥接口（getPubKey）返回异常：%r' % (pub,))

        # 3) RSA 加密密码（对齐 rsaEncrypt：hex 补零 128 位）
        enc_pwd = rsa_encrypt(password, str(modulus), str(exponent))

        # 4) 提交表单
        form = urllib.parse.urlencode({
            'username': username,
            'password': enc_pwd,
            'execution': execution,
            '_eventId': 'submit',
            'rememberMe': 'true',
        }).encode('utf-8')
        with self._open(CAS_LOGIN_URL, data=form, headers={
                'Content-Type': 'application/x-www-form-urlencoded'}) as resp:
            resp.read()

        # 5) 提取 iPlanetDirectoryPro
        for c in self._jar:
            if c.name == 'iPlanetDirectoryPro':
                return c.value
        raise AuthError(
            'SSO 登录失败：未获取到 iPlanetDirectoryPro 会话 cookie'
            '（学号或密码错误，或触发了验证码）')

    def zdbk_login(self):
        """SSO cookie（jar 内自动携带）→ ZDBK 会话（对齐 ZjuZdbkService.login）。"""
        service = CAS_LOGIN_URL + '?service=' + urllib.parse.quote(
            ZDBK_SSO_SERVICE, safe='')
        location = self._get_location(service)
        if not location:
            raise SessionExpired(
                'ZDBK 教务登录失败——SSO 会话无效或已过期，请重新登录')
        if location.startswith('http://'):
            location = location.replace('http://', 'https://', 1)
        self._get(location)  # 沿途收集 JSESSIONID(path=/jwglxt) + route
        if not self._has_zdbk_cookies():
            raise SessionExpired(
                'ZDBK 教务登录失败——未获取到 JSESSIONID/route 会话 cookie'
                '（SSO 会话可能已过期）')
        self._logged_in = True

    # -- 取数 -----------------------------------------------------------
    def get_transcript(self):
        """成绩单（对齐 zdbk_service.getTranscript）→ ZjuGrade 列表。"""
        body = self._zdbk_post(ZDBK_TRANSCRIPT_URL)
        items = extract_items(body)
        if not items:
            raise ParseError('成绩单解析为空——教务页面结构可能已变更，请反馈')
        grades = [ZjuGrade.from_json(it) for it in items
                  if it.get('xkkh') is not None]
        return grades

    def fetch_grades(self, username, password):
        """带自动重登的完整取数（对齐 _withAutoRelogin：最多重登 1 次）。"""
        for attempt in range(2):
            try:
                if not self._logged_in:
                    self.sso_login(username, password)
                    self.zdbk_login()
                return self.get_transcript()
            except SessionExpired:
                self._reset()
                if attempt == 1:
                    raise
        raise SessionExpired('ZDBK 会话已过期且自动重登失败')


# ── 响应解析（对齐 zdbk_patterns + html_parser）───────────────────────
def extract_items(body):
    """从 ZDBK 响应提取 items JSON 数组（正则两步，与参考一致）。

    优先 `(?<="items":)\[...\](?=,"limit")`，再试 `,"totalResult"` 后缀；
    最后回退整包 JSON 的 items/data 键。均失败返回空列表。
    """
    for pat in (ITEMS_WITH_LIMIT, ITEMS_WITH_TOTAL_RESULT):
        m = pat.search(body)
        if m:
            try:
                arr = json.loads(m.group(0))
                if isinstance(arr, list):
                    return [x for x in arr if isinstance(x, dict)]
            except ValueError:
                pass
    try:
        obj = json.loads(body)
    except ValueError:
        return []
    if isinstance(obj, dict):
        arr = obj.get('items')
        if arr is None:
            arr = obj.get('data')
        if isinstance(arr, list):
            return [x for x in arr if isinstance(x, dict)]
    return []


# ── 参数与凭证（契约 §六）──────────────────────────────────────────────
def parse_args(argv):
    """支持 `--key value`（平台传参）与 `--key=value`（手工调试）。"""
    out = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith('--'):
            body = tok[2:]
            if '=' in body:
                k, v = body.split('=', 1)
                out[k] = v
            elif i + 1 < len(argv):
                out[body] = argv[i + 1]
                i += 1
            else:
                out[body] = ''
        i += 1
    return out


def _read_config_value(path, key):
    try:
        # utf-8-sig：容忍 Windows 记事本等写入的 UTF-8 BOM，避免误判为未配置
        with open(path, 'r', encoding='utf-8-sig') as f:
            val = json.load(f).get(key)
        return val if isinstance(val, str) and val else None
    except Exception:
        return None


def get_config(key, args):
    """凭证三级降级：--greenix-config 的 config.json → 项目 .greenix →
    环境变量。与平台 `_get_config` 语义一致，绝不硬编码。"""
    cfg_path = args.get('greenix-config') or os.environ.get(
        'GREENIX_CONFIG_PATH')
    if cfg_path and os.path.isfile(cfg_path):
        val = _read_config_value(cfg_path, key)
        if val:
            return val
    project_root = args.get('project-root')
    if project_root:
        val = _read_config_value(
            os.path.join(project_root, '.greenix', 'config.json'), key)
        if val:
            return val
    return os.environ.get(key)


def emit_error(message, error_class, exit_code, extra=None):
    payload = {'error': message, 'errorClass': error_class}
    if extra:
        payload.update(extra)
    try:
        print(json.dumps(payload, ensure_ascii=False))
        print('[zju-grades] errorClass=%s: %s' % (error_class, message),
              file=sys.stderr)
    except Exception:
        pass
    return exit_code


# ── 入口 ───────────────────────────────────────────────────────────────
def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    type_arg = args.get('type') or 'zju_grades'
    if type_arg != 'zju_grades':
        return emit_error('未知类型 %r（本插件仅支持 zju_grades）' % type_arg,
                          'unknown', EXIT_UNKNOWN)

    username = get_config('ZJU_USERNAME', args)
    password = get_config('ZJU_PASSWORD', args)
    if not username or not password:
        return emit_error(
            '未配置浙大学号密码——请先在「设置」中填写 ZJU_USERNAME / ZJU_PASSWORD'
            '（config.json 或环境变量）',
            'config_missing', EXIT_CONFIG,
            extra={'needConfig': True, 'keys': ['ZJU_USERNAME', 'ZJU_PASSWORD']})

    try:
        grades = ZdbkClient().fetch_grades(username, password)
        out = {
            'grades': [g.to_json() for g in grades],
            'domestic_gpa': calculate_gpa(pick_first_attempt(grades)).to_json(),
            'abroad_gpa': calculate_gpa(pick_highest_attempt(grades)).to_json(),
            'authenticated': True,
            'source': 'zdbk',
            'fetched_at': datetime.now(timezone.utc).isoformat(),
        }
        print(json.dumps(out, ensure_ascii=False))
        return EXIT_OK
    except ScraperError as e:
        return emit_error(str(e), e.error_class, e.exit_code)
    except Exception as e:  # 兜底：任何异常收敛为错误 JSON，不污染 stdout
        return emit_error('未知错误：%r' % (e,), 'unknown', EXIT_UNKNOWN)


if __name__ == '__main__':
    sys.exit(main())
