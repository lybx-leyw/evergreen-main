# -*- coding: utf-8 -*-
"""evg_lib.download — 文件型数据源的统一下载与内容寻址缓存。

协议：`docs/plugin-registry/file-data-plugin-protocol-v1.md`。

核心不变量 F1：**同 HEAD 指纹的文件绝不重新下载**。
所有文件型 data 插件（冷插件/热插件、模型 A/B）共用本实现 + 共用同一缓存
目录，因此插件 A 下过的文件，插件 B 命中即复用。

设计要点（对应协议 §1/§3/§4）：
  1. 文件名即指纹（内容寻址）—— **无索引文件**，命中判定 = 文件是否存在。
     → 无锁、无并发冲突、崩溃安全。
  2. HEAD 指纹优先级链：ETag → Last-Modified → Content-Length → nofp。
     源站不支持 HEAD（405/501/403）或网络失败 → 降级 nofp（弱键），不阻断。
  3. 流式落盘到 `.part.<pid>` → `os.replace` 原子改名。
     → 脚本被平台 60s 超时 kill 时，半成品不污染缓存。
  4. 缓存目录从 `--greenix-config` 派生，**无需新增命令行参数**。

用法：
    from evg_lib import download
    from evg_lib.jsonio import emit

    emit(download.ensure("https://example.com/lecture01.mp4"))

    # 校验版
    emit(download.ensure(
        url,
        headers={"Referer": "https://example.com"},
        expected_size=12345678,
        sha256="9f86d081884c7d65...",
    ))

零新第三方依赖：仅标准库（urllib / hashlib / os / json / argparse 语义靠手写解析）。
"""

import hashlib
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

__all__ = ['ensure', 'cache_dir', 'resolve_cache_dir', 'clear_partials', 'cache_key']

# ── 超时（秒）：HEAD 短、GET 长（大文件） ──
DEFAULT_HEAD_TIMEOUT = 15
DEFAULT_GET_TIMEOUT = 300
# ── 流式读取块大小：64 KiB ──
CHUNK_SIZE = 64 * 1024
# ── UA：与 DataFileService 对齐，便于服务端识别 ──
DEFAULT_UA = 'evergreen-data-file'


# ═══════════════════════════════════════════════════════════════════════
# 路径解析（协议 §2）
# ═══════════════════════════════════════════════════════════════════════

def _greenix_config_path():
    """解析 `.greenix/config.json` 绝对路径。

    优先 `--greenix-config <path>`（桌面 argv），回退环境变量
    `GREENIX_CONFIG_PATH`（安卓 Kotlin 注入）。两者皆无 → None。
    """
    argv = sys.argv
    for i, a in enumerate(argv):
        if a == '--greenix-config' and i + 1 < len(argv):
            return argv[i + 1]
    env = os.environ.get('GREENIX_CONFIG_PATH')
    return env if env else None


def resolve_cache_dir():
    """解析缓存目录 = `dirname(greenix_config)/file_cache`（协议 §2）。

    `--greenix-config` 指向 `.greenix/config.json`，故父目录即 `.greenix`。
    两者皆不可得时回退 `PROJECT_ROOT/.greenix/file_cache`，最后回退 CWD。
    返回 `Path`（不保证存在）。
    """
    cfg = _greenix_config_path()
    if cfg:
        return Path(cfg).parent / 'file_cache'
    root = os.environ.get('PROJECT_ROOT')
    if root:
        return Path(root) / '.greenix' / 'file_cache'
    return Path.cwd() / '.greenix' / 'file_cache'


def cache_dir(create=True):
    """返回缓存目录 `Path`；`create=True` 时幂等创建。"""
    d = resolve_cache_dir()
    if create:
        d.mkdir(parents=True, exist_ok=True)
    return d


# ═══════════════════════════════════════════════════════════════════════
# 指纹与命名（协议 §3）
# ═══════════════════════════════════════════════════════════════════════

def _norm_url(url):
    """规范化 URL：去 fragment（保留 query 与大小写，path 大小写敏感）。"""
    return url.split('#', 1)[0]


def _sha16(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def _ext_from_url(url):
    """从 URL path 末段派生扩展名（含点）。无扩展名或过长 → `.bin`。"""
    try:
        path = urllib.request.urlparse(url).path
    except Exception:
        path = url
    name = path.rsplit('/', 1)[-1]
    if '.' in name:
        ext = '.' + name.rsplit('.', 1)[-1]
        if 1 < len(ext) <= 10 and ext[1:].isalnum():
            return ext.lower()
    return '.bin'


def _fingerprint_string(head_headers):
    """HEAD 指纹优先级链（协议 §3.2）。返回 (fingerprint_string, weak)。"""
    etag = head_headers.get('ETag')
    if etag:
        return 'etag:%s' % etag, False
    lm = head_headers.get('Last-Modified')
    if lm:
        return 'lm:%s' % lm, False
    cl = head_headers.get('Content-Length')
    if cl:
        return 'cl:%s' % cl, True
    return 'nofp', True


def cache_key(url, head_headers=None):
    """计算缓存文件名（不含目录）。

    `head_headers` 为 None → 按 `nofp` 弱键命名。
    """
    url_key = _sha16(_norm_url(url))
    if head_headers is None:
        fp = 'nofp'
    else:
        fp, _ = _fingerprint_string(head_headers)
    return '%s-%s%s' % (url_key, _sha16(fp), _ext_from_url(url))


# ═══════════════════════════════════════════════════════════════════════
# HTTP（HEAD / 流式 GET）
# ═══════════════════════════════════════════════════════════════════════

def _build_headers(extra=None):
    h = {'User-Agent': DEFAULT_UA}
    if extra:
        for k, v in extra.items():
            if v is not None:
                h[str(k)] = str(v)
    return h


def _head(url, headers, timeout):
    """发 HEAD。

    返回 `(headers_dict, degraded)`：
      - 成功 → (`{ETag/Last-Modified/Content-Length/Content-Type}`, False)
      - 源站不支持（405/501/403/404 以外）或网络失败 → (`{}`, True) 降级，不抛
    """
    req = urllib.request.Request(url, headers=headers, method='HEAD')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            hdrs = {k: v for k, v in resp.headers.items()}
            hdrs['_status'] = str(resp.status)
            return hdrs, False
    except Exception:
        # 405/501/403/4xx/5xx/URLError/超时 → 一律降级，不阻断（协议 §3.3）
        return {}, True


def _stream_download(url, headers, timeout, target_path):
    """流式下载 → `.part.<pid>` → 原子改名。

    返回 `(size, sha256_hex, content_type)`。失败时清理 `.part` 并抛出。
    """
    part = '%s.part.%d' % (target_path, os.getpid())
    h = hashlib.sha256()
    size = 0
    ctype = None
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            ctype = resp.headers.get('Content-Type')
            with open(part, 'wb') as f:
                while True:
                    chunk = resp.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    f.write(chunk)
                    h.update(chunk)
                    size += len(chunk)
                f.flush()
                os.fsync(f.fileno())
        # 原子改名（同目录同设备 → 原子）
        os.replace(part, target_path)
        return size, h.hexdigest(), ctype
    except Exception:
        try:
            if os.path.exists(part):
                os.unlink(part)
        except Exception:
            pass
        raise


# ═══════════════════════════════════════════════════════════════════════
# 公开 API
# ═══════════════════════════════════════════════════════════════════════

def _ok(path, size, mime, source_url, head_headers, sha256_hex,
        cached, weak_cache, fetched_at):
    """构造 `status: ready` 输出（协议 §5.1）。"""
    out = {
        'status': 'ready',
        'path': str(path),
        'size': size,
        'source_url': source_url,
        'cached': bool(cached),
        'fetched_at': fetched_at,
    }
    if mime:
        out['mime'] = mime
    if sha256_hex:
        out['sha256'] = sha256_hex
    if head_headers:
        if head_headers.get('ETag'):
            out['etag'] = head_headers['ETag']
        if head_headers.get('Last-Modified'):
            out['last_modified'] = head_headers['Last-Modified']
    if weak_cache:
        out['weak_cache'] = True
    return out


def ensure(url, headers=None, head_timeout=DEFAULT_HEAD_TIMEOUT,
           timeout=DEFAULT_GET_TIMEOUT, expected_size=None, sha256=None,
           force=False):
    """确保 `url` 已落盘到内容寻址缓存，返回协议 §5 契约 dict。

    本函数**不抛异常**：任何失败都转换为 `status` 为 `missing` / `failed`
    的字典，便于脚本直接 `emit()`。

    参数：
      url           源地址（必填）
      headers       额外请求头（凭据/Referer/UA 等）
      head_timeout  HEAD 超时秒数（默认 15）
      timeout       GET 超时秒数（默认 300）
      expected_size 期望字节数；不符则视为失败并清理
      sha256        期望 SHA-256（十六进制）；不符则视为失败并清理
      force         True 时跳过缓存命中判定，强制重下（仍用指纹命名）

    返回 `status`：
      ready   文件已落盘（`cached=True` 表示直接复用，未发 GET）
      missing 无缓存且无法获取（离线/源站不可达）—— 降级，非错误
      failed  源站明确报错（403/404 等）或校验失败
    """
    url = (url or '').strip()
    if not url:
        return {'status': 'failed', 'path': None, 'error': 'url 为空'}

    hdrs = _build_headers(headers)
    d = cache_dir(create=True)

    # ── 1) HEAD 取指纹（force 时同样取，仅跳过命中判定） ──
    head_headers, degraded = {}, False
    if url.startswith(('http://', 'https://')):
        head_headers, degraded = _head(url, hdrs, head_timeout)
    else:
        degraded = True  # 本地路径/非 http：无 HEAD 语义 → 弱键
    if force:
        head_headers = {}

    name = cache_key(url, head_headers if head_headers else None)
    target = d / name
    weak = degraded or not head_headers

    # ── 2) 命中判定（F1 核心：存在即复用，绝不重下） ──
    if not force and target.exists():
        size = target.stat().st_size
        # 有 Content-Length 时必须一致，否则视为坏缓存 → 重下
        cl = head_headers.get('Content-Length') if head_headers else None
        if cl is None or not str(cl).isdigit() or int(cl) == size:
            mtime = int(target.stat().st_mtime)
            return _ok(target, size, head_headers.get('Content-Type'),
                       url, head_headers, None, True, weak,
                       time.strftime('%Y-%m-%dT%H:%M:%SZ',
                                     time.gmtime(mtime)))

    # ── 3) 未命中 → 流式下载 ──
    if not url.startswith(('http://', 'https://')):
        # 本地文件：直接拷入内容寻址缓存（同样遵守 F1）
        try:
            src = Path(url)
            if not src.exists():
                return {'status': 'failed', 'path': None,
                        'error': '本地文件不存在: %s' % url}
            if target.exists() and not force:
                return _ok(target, target.stat().st_size, None, url,
                           head_headers, None, True, weak,
                           time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
            part = '%s.part.%d' % (target, os.getpid())
            h = hashlib.sha256()
            with open(src, 'rb') as fi, open(part, 'wb') as fo:
                while True:
                    chunk = fi.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    fo.write(chunk)
                    h.update(chunk)
                fo.flush()
                os.fsync(fo.fileno())
            os.replace(part, target)
            size = target.stat().st_size
            return _ok(target, size, None, url, head_headers, h.hexdigest(),
                       False, weak,
                       time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
        except Exception as e:
            return {'status': 'failed', 'path': None, 'error': str(e)}

    try:
        size, digest, ctype = _stream_download(url, hdrs, timeout, str(target))
    except urllib.error.HTTPError as e:
        # 源站明确响应错误（403 登录态失效 / 404 等）→ failed
        return {'status': 'failed', 'path': None, 'source_url': url,
                'error': 'HTTP %s %s' % (e.code, e.reason)}
    except Exception as e:
        # 网络不可达/超时/DNS → missing（降级，不报错）
        return {'status': 'missing', 'path': None, 'source_url': url,
                'reason': 'unreachable: %s' % (e.__class__.__name__)}

    # ── 4) 校验 ──
    if expected_size is not None and int(expected_size) != size:
        try:
            os.unlink(str(target))
        except Exception:
            pass
        return {'status': 'failed', 'path': None, 'source_url': url,
                'error': '大小不符：期望 %s，实际 %s' % (expected_size, size)}
    if sha256 and str(sha256).lower() != digest.lower():
        try:
            os.unlink(str(target))
        except Exception:
            pass
        return {'status': 'failed', 'path': None, 'source_url': url,
                'error': 'SHA-256 校验失败'}

    return _ok(target, size, ctype, url, head_headers, digest, False, weak,
               time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))


def clear_partials(max_age_seconds=3600):
    """清理超过 `max_age_seconds` 的 `.part*` 残留（协议 §9）。

    仅清 `.part` 临时文件，**不动**任何正式缓存文件。返回清理数量。
    """
    n = 0
    now = time.time()
    try:
        for f in cache_dir(create=False).glob('*.part*'):
            try:
                if now - f.stat().st_mtime > max_age_seconds:
                    f.unlink()
                    n += 1
            except Exception:
                pass
    except Exception:
        pass
    return n
