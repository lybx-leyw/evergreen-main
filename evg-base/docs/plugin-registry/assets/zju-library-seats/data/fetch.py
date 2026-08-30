#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大图书馆座位实时状态 —— 数据源适配壳（真实抓取，公开接口免登录）。

数据源：浙江大学图书馆空间预约系统（https://booking.lib.zju.edu.cn，
浙大图书馆「空间预约」H5，厂商为「我来/智位云」同源系统）。
本适配壳直接抓取该系统公开（免登录）的 REST 接口，返回：
  1. 12 个馆舍列表（/api/Study/libinfo）
  2. 各区域实时座位余量（空闲/占用/总数，/api/Seat/date + /api/Seat/seat）
  3. 预约规则（/api/index/booking_rules）
  4. 最新馆内通知（/api/index/notice）

实测验证（2026-08-29，全部免登录、POST JSON）：
  POST /api/Study/libinfo          → code:1, 12 馆舍
  POST /api/Seat/date  {"build_id"}→ code:1, 开放日期+时段
  POST /api/Seat/seat  {area,segment,day,startTime,endTime}
                                    → code:1, 座位状态（status==1 空闲）
  POST /api/index/booking_rules {} → code:1, 预约规则 HTML
  POST /api/index/notice {}        → code:1, 通知列表
完整区域树（/api/Seat/tree）需登录（code 10001/201），本插件使用
公开接口实测枚举出的区域 id 表（可经配置 ZJU_LIB_SEAT_AREAS 覆盖）。
绝不伪造数据：任何区域抓取失败即跳过并标注，不填充假数字。

契约：stdout 顶层 Map JSON（UTF-8）；失败输出 {"error": ...} + 非零退出；
纯 Python 标准库；凭证走 _get_config 三级降级（本插件无强制凭证）。
性能：http.client keep-alive（线程级连接池）+ 区域并行抓取，控制整体耗时
在平台 60s CLI 超时内。
"""
import sys
import os
import re
import json
import ssl
import html as html_lib
import http.client
import threading
import concurrent.futures
import datetime
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

BASE_URL = "https://booking.lib.zju.edu.cn"
SITE_NAME = "浙大图书馆空间预约系统"

# 默认区域 id 表 —— 公开接口实测枚举（2026-08-29 验证可免登录拉取到座位状态）。
# 每个区域名（如「三层300阅览室」）取自接口响应 area_name 字段，不在此硬编码。
DEFAULT_AREAS = ["7", "8", "9", "10", "11", "12", "13", "21", "26", "38", "39", "40"]

HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
    "Referer": BASE_URL + "/h5/index.html",
    "Accept": "application/json",
    "Content-Type": "application/json",
}

_REQUEST_TIMEOUT = 12       # 单请求超时（秒）
_AREA_WORKERS = 6           # 区域并行抓取线程数


# ═══════════════════════════════════════════════════════════════
# 配置读取（三级降级，参考平台 data-source 适配壳规范）
# ═══════════════════════════════════════════════════════════════
def _get_config(key):
    """从平台配置读取（三级降级）：.greenix/config.json → ConfigHttpServer → 环境变量。"""
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            cfg_path = os.path.join(greenix_path, 'config.json')
            if os.path.exists(greenix_path) and os.path.isfile(greenix_path):
                cfg_path = greenix_path
            if os.path.exists(cfg_path):
                with open(cfg_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass
    try:
        port_file = None
        for base in [os.getcwd(), os.environ.get('PROJECT_ROOT', '.')]:
            try:
                for d in [base] + list(__path_parents(base)):
                    pf = os.path.join(d, '.config_port')
                    if os.path.exists(pf):
                        port_file = pf
                        break
            except Exception:
                continue
            if port_file:
                break
        if port_file:
            with open(port_file, 'r') as f:
                port = f.read().strip()
            url = 'http://127.0.0.1:{0}/config/settings/{1}'.format(port, key)
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                val = data.get('value', '')
                if val:
                    return val
    except Exception:
        pass
    val = os.environ.get(key)
    if val:
        return val
    return None


def __path_parents(path):
    cur = path
    while True:
        parent = os.path.dirname(cur)
        if parent == cur:
            return
        yield parent
        cur = parent


# ═══════════════════════════════════════════════════════════════
# TLS 上下文（严格校验优先，失败降级不校验并如实标注）
# ═══════════════════════════════════════════════════════════════
# 实测发现：目标站点证书链在部分 Python/OpenSSL 组合下无法被严格解析
# （Schannel/curl 均可正常校验证书，属本机 OpenSSL 或证书存储问题），
# 且部分 Windows 机器本地 CA 存储本身存在不可解析条目（create_default_context
# 直接抛 [ASN1: NOT_ENOUGH_DATA]）。因此采用「严格验证 → 降级不校验」策略，
# 输出中如实标注 tlsVerified 状态——绝不静默绕过证书校验。
_SSL_VERIFIED = True
_SSL_CONTEXT = None
_SSL_LOCK = threading.Lock()


def _ssl_context():
    """返回全局 SSL 上下文（首次构建；严格校验失败则降级并记录）。"""
    global _SSL_VERIFIED, _SSL_CONTEXT
    if _SSL_CONTEXT is not None:
        return _SSL_CONTEXT
    with _SSL_LOCK:
        if _SSL_CONTEXT is not None:
            return _SSL_CONTEXT
        try:
            ctx = ssl.create_default_context()
            # 预检：一次真实握手验证证书链可被本机 OpenSSL 解析
            conn = http.client.HTTPSConnection(
                "booking.lib.zju.edu.cn", 443, timeout=10, context=ctx)
            try:
                conn.request('POST', '/api/index/time',
                             body=b'{}', headers=HEADERS)
                conn.getresponse().read()
            finally:
                conn.close()
            _SSL_VERIFIED = True
            _SSL_CONTEXT = ctx
        except (ssl.SSLError, OSError, http.client.HTTPException):
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            _SSL_VERIFIED = False
            _SSL_CONTEXT = ctx
        return _SSL_CONTEXT


def tls_verified() -> bool:
    """当前请求链路是否完成 TLS 证书校验（供输出如实标注）。"""
    return _SSL_VERIFIED


# ═══════════════════════════════════════════════════════════════
# HTTP 辅助（线程级 keep-alive 连接池）
# ═══════════════════════════════════════════════════════════════
_thread_local = threading.local()


def _get_conn():
    """获取当前线程的 keep-alive 连接（懒创建 + 断线自动重建）。"""
    conn = getattr(_thread_local, 'conn', None)
    if conn is None:
        conn = http.client.HTTPSConnection(
            "booking.lib.zju.edu.cn", 443,
            timeout=_REQUEST_TIMEOUT, context=_ssl_context())
        _thread_local.conn = conn
    return conn


def _post_json(path, payload, timeout=_REQUEST_TIMEOUT):
    """POST JSON → 解析响应 JSON。网络/HTTP/解析异常向上抛（由调用方收敛）。"""
    body = json.dumps(payload).encode('utf-8')
    last_err = None
    for attempt in range(2):  # 连接重建重试一次
        conn = _get_conn()
        try:
            conn.request('POST', path, body=body, headers=HEADERS)
            resp = conn.getresponse()
            raw = resp.read()
            # 非 2xx 也读完整响应体再判错，便于拿到 JSON 错误信息
            if resp.status >= 400:
                raise urllib_http_error(resp.status, path)
            return json.loads(raw.decode('utf-8'))
        except (http.client.HTTPException, ssl.SSLError, OSError) as e:
            last_err = e
            # 连接已失效：关闭后下次重建
            try:
                conn.close()
            except Exception:
                pass
            _thread_local.conn = None
            if attempt == 1:
                raise
    raise last_err


class urllib_http_error(Exception):
    """HTTP 非 2xx 状态错误（避免依赖 urllib.error 的模块纠缠）。"""

    def __init__(self, status, path):
        super().__init__('HTTP {0} for {1}'.format(status, path))
        self.status = status
        self.path = path


def _strip_html(raw):
    """HTML → 纯文本（去标签 + 解实体 + 压缩空白）。"""
    if not raw:
        return ''
    text = re.sub(r'<script[\s\S]*?</script>', ' ', raw, flags=re.I)
    text = re.sub(r'<style[\s\S]*?</style>', ' ', text, flags=re.I)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = html_lib.unescape(text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


# ═══════════════════════════════════════════════════════════════
# 业务抓取
# ═══════════════════════════════════════════════════════════════
def _fetch_libraries():
    """POST /api/Study/libinfo → 12 馆舍列表。"""
    j = _post_json('/api/Study/libinfo', {})
    if not isinstance(j, dict) or j.get('code') != 1:
        raise RuntimeError('libinfo 接口异常: {0}'.format(
            j.get('msg') if isinstance(j, dict) else j))
    data = j.get('data') or []
    libs = []
    for it in data:
        if isinstance(it, dict) and it.get('libPlace'):
            libs.append({'libPlace': str(it['libPlace']),
                         'name': it.get('description', '')})
    return libs


def _fetch_area(area_id):
    """抓取单个区域实时座位状态：date(时段) → seat(状态) → 统计。

    返回 dict 或抛异常（区域失败由调用方捕获标注，绝不伪造）。
    """
    # 1. 开放日期 + 时段
    dj = _post_json('/api/Seat/date', {'build_id': str(area_id)})
    if not isinstance(dj, dict):
        raise RuntimeError('date 响应非法')
    code = dj.get('code')
    if code == 10001:
        raise RuntimeError('date 需登录（10001）')
    if code == 201:
        raise RuntimeError('date 服务器异常（201）')
    if code != 1:
        raise RuntimeError('date 失败: {0}'.format(dj.get('msg')))
    days = dj.get('data') or []
    # 取第一个有有效时段的日期
    day = None
    segment = None
    for d in days:
        if not isinstance(d, dict):
            continue
        times = d.get('times') or []
        for t in times:
            if isinstance(t, dict) and t.get('id'):
                day = d.get('day')
                segment = t
                break
        if segment:
            break
    if not segment:
        return {
            'area': str(area_id),
            'name': '',
            'day': '',
            'segment': None,
            'total': 0,
            'free': 0,
            'occupied': 0,
            'freeRatio': 0,
            'note': '今日无开放时段',
        }

    # 2. 实时座位状态
    sj = _post_json('/api/Seat/seat', {
        'area': str(area_id),
        'segment': str(segment['id']),
        'day': day,
        'startTime': segment.get('start', ''),
        'endTime': segment.get('end', ''),
    })
    if not isinstance(sj, dict):
        raise RuntimeError('seat 响应非法')
    if sj.get('code') == 10001:
        raise RuntimeError('seat 需登录（10001）')
    if sj.get('code') == 201:
        raise RuntimeError('seat 服务器异常（201）')
    if sj.get('code') != 1:
        raise RuntimeError('seat 失败: {0}'.format(sj.get('msg')))
    seats = sj.get('data') or []
    total = len(seats)
    free = 0
    occupied = 0
    area_name = ''
    for s in seats:
        if not isinstance(s, dict):
            continue
        if not area_name and s.get('area_name'):
            area_name = s['area_name']
        if str(s.get('status')) == '1':
            free += 1
        else:
            occupied += 1
    return {
        'area': str(area_id),
        'name': area_name,
        'day': day,
        'segment': {
            'id': str(segment['id']),
            'start': segment.get('start', ''),
            'end': segment.get('end', ''),
        },
        'total': total,
        'free': free,
        'occupied': occupied,
        'freeRatio': round(free / total, 4) if total else 0,
        'note': '',
    }


def _fetch_booking_rules():
    """POST /api/index/booking_rules → 预约规则纯文本（截断防爆）。"""
    try:
        j = _post_json('/api/index/booking_rules', {})
        if not isinstance(j, dict) or j.get('code') != 1:
            return ''
        data = j.get('data') or {}
        if isinstance(data, dict) and data.get('seat'):
            return _strip_html(str(data['seat']))[:2000]
        if isinstance(data, str):
            return _strip_html(data)[:2000]
        return ''
    except Exception:
        return ''


def _fetch_notices(limit=5):
    """POST /api/index/notice → 最新通知。"""
    try:
        j = _post_json('/api/index/notice', {})
        if not isinstance(j, dict) or j.get('code') != 1:
            return []
        data = j.get('data') or {}
        items = data.get('data') if isinstance(data, dict) else data
        if not isinstance(items, list):
            return []
        out = []
        for it in items[:limit]:
            if isinstance(it, dict):
                out.append({
                    'id': str(it.get('id', '')),
                    'title': it.get('title', ''),
                    'date': it.get('create_time', ''),
                })
        return out
    except Exception:
        return []


# ═══════════════════════════════════════════════════════════════
# 参数解析（空格分隔 --key value，兼容 --key=value）
# ═══════════════════════════════════════════════════════════════
def _parse_args(argv):
    args = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith('--'):
            name = tok[2:]
            if '=' in name:
                k, v = name.split('=', 1)
                args[k] = v
                i += 1
            elif i + 1 < len(argv):
                args[name] = argv[i + 1]
                i += 2
            else:
                args[name] = ''
                i += 1
        else:
            args.setdefault('_positional', []).append(tok)
            i += 1
    return args


def _resolve_areas(args):
    """区域 id 列表：--areas 参数 > 配置 ZJU_LIB_SEAT_AREAS > 默认实测表。"""
    raw = None
    if args.get('areas'):
        raw = args['areas']
    if not raw:
        raw = _get_config('ZJU_LIB_SEAT_AREAS')
    if raw:
        ids = [a.strip() for a in re.split(r'[,\s]+', raw) if a.strip()]
        if ids:
            return ids
    return list(DEFAULT_AREAS)


def main():
    args = _parse_args(sys.argv[1:])
    type_arg = args.get('type') or 'zju_library_seats'

    libraries = []
    areas = []
    skipped = []
    try:
        # 0. 先触发一次握手，确定 TLS 校验状态（严格优先，失败降级并标注）
        _ssl_context()

        # 1. 馆舍列表（失败则整体失败 —— 这是主数据）
        libraries = _fetch_libraries()

        # 2. 各区域实时座位（并行抓取；单区域失败不拖垮整体，跳过并标注）
        area_ids = _resolve_areas(args)
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=_AREA_WORKERS) as pool:
            futures = {pool.submit(_fetch_area, aid): aid for aid in area_ids}
            for fut in concurrent.futures.as_completed(futures):
                aid = futures[fut]
                try:
                    areas.append(fut.result())
                except Exception as e:
                    skipped.append({'area': aid, 'reason': str(e)})

        # 3. 预约规则 + 通知（尽力而为，失败为空）
        booking_rules = _fetch_booking_rules()
        notices = _fetch_notices()

        total = sum(a['total'] for a in areas)
        free = sum(a['free'] for a in areas)
        occupied = sum(a['occupied'] for a in areas)

        note = ('区域枚举基于公开接口实测区域表（可通过配置 ZJU_LIB_SEAT_AREAS 覆盖）；'
                '完整区域树（/api/Seat/tree）需登录。所有座位数字均来自实时接口，未做任何伪造。')
        if not tls_verified():
            note += (' 提示：本机 OpenSSL 无法严格解析站点证书链（Schannel/curl 可正常校验），'
                     '本次请求降级为不校验证书（tlsVerified=false）。')

        result = {
            'type': type_arg,
            'source': '{0}（{1}，公开接口免登录）'.format(SITE_NAME, BASE_URL),
            'fetchedAt': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
            'tlsVerified': tls_verified(),
            'libraries': libraries,
            'areas': areas,
            'summary': {
                'areas': len(areas),
                'totalSeats': total,
                'freeSeats': free,
                'occupiedSeats': occupied,
                'freeRatio': round(free / total, 4) if total else 0,
            },
            'bookingRules': booking_rules,
            'notices': notices,
            'skippedAreas': skipped,
            'note': note,
        }
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as e:
        print(json.dumps({'error': '抓取失败: {0}'.format(e)}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
