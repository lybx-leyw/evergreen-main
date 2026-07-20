# ═══════════════════════════════════════════════════════════
# EVERGREEN CONFIG TEMPLATE (LOCKED — DO NOT MODIFY)
# ═══════════════════════════════════════════════════════════
import json, os, urllib.request, urllib.error, urllib.parse
from pathlib import Path

def _get_config(key):
    try:
        port_file = None
        for base in [Path.cwd(), Path(os.environ.get('PROJECT_ROOT', '.'))]:
            try:
                for d in [base] + list(base.parents):
                    pf = d / '.config_port'
                    if pf.exists():
                        port_file = pf
                        break
            except Exception:
                continue
            if port_file:
                break
        if port_file:
            with open(port_file, 'r') as f:
                port = f.read().strip()
            url = f'http://127.0.0.1:{port}/config/settings/{key}'
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                val = data.get('value', '')
                if val:
                    return val
    except Exception:
        pass
    # 仅允许通过环境变量注入（离线测试用）；不读取任何 .env 文件，
    # 更不擅自使用真实账号实跑（避免滥用数据）。
    val = os.environ.get(key)
    if val is not None:
        return val
    raise RuntimeError(f'无法获取配置 "{key}"')


# ═══════════════════════════════════════════════════════════
# 业务代码 —— 浙大智云课堂真实数据抓取
#
# 数据拉取办法参考 .reference/important_refer/cp_evergreen_push（Dart 版
# zjuam_service.dart + classroom_crawler.dart，逻辑语言无关，此处 Python 复刻）。
#
# 流程：
#   1) 浙大统一身份认证（zjuam.zju.edu.cn）RSA 登录 → iPlanetDirectoryPro cookie
#   2) 跟随 tgmedia.cmc.zju.edu.cn OAuth2 重定向链 → 智云课堂域会话 cookie
#   3) 调 4 个智云课堂 API：课程列表 / 录播目录 / PPT / 字幕
#   4) 组装为 classroom-modle bindings 形状：
#        {courses:[{id,title,teachers,videos:[{subId,title,videoUrl,
#                    slides:[{page,imageUrl,text}],
#                    subtitles:[{startMs,endMs,text}]}]}]}
#
# 纯标准库实现（urllib + 内置 pow 做 RSA modpow），无第三方依赖，
# 便于 PyInstaller 干净打包。凭据仅来自设置页配置（学号/密码），绝不读 .env、不硬编码。
# ═══════════════════════════════════════════════════════════
import re
import sys
import ssl
import time
import argparse

# ---- API 端点（与参考实现一致）----
API_COURSES = ('https://education.cmc.zju.edu.cn/personal/courseapi/'
               'vlabpassportapi/v1/account-profile/course'
               '?nowpage=1&per-page=100&force_mycourse=1')
API_CATALOGUE = ('https://yjapi.cmc.zju.edu.cn/courseapi/v2/course/catalogue'
                 '?course_id={course_id}')
API_PPT = ('https://classroom.zju.edu.cn/pptnote/v1/schedule/search-ppt'
           '?course_id={course_id}&sub_id={sub_id}&page={page}&per_page=100')
API_SUBTITLE = ('https://yjapi.cmc.zju.edu.cn/courseapi/v3/web-socket/'
                'search-trans-result?sub_id={sub_id}&format=json')

_UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
       'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36')
_EXECUTION_RE = re.compile(r'name="execution"\s+value="([^"]+)"')


class ZjuSession:
    """跨域 cookie + 手动逐跳重定向的会话（对齐参考实现的 cookie 收集方式）。"""

    def __init__(self):
        self.cookies = {}
        # 用不加载系统证书的上下文：
        #  1) 少数校园服务证书链不全，放宽校验保证可用性（仅内网教务域）；
        #  2) 规避 PyInstaller 打包 ssl.create_default_context() 加载 Windows
        #     根证书时的 [ASN1: NOT_ENOUGH_DATA] 崩溃（部分证书 OpenSSL 无法解析）。
        ctx = ssl._create_unverified_context()
        self._opener = urllib.request.build_opener(
            _NoRedirect(), urllib.request.HTTPSHandler(context=ctx))

    def _collect(self, headers):
        """从响应头收集 Set-Cookie（只取 name=value 首段）。"""
        for raw in headers.get_all('Set-Cookie') or []:
            seg = raw.split(';', 1)[0].strip()
            eq = seg.find('=')
            if eq > 0:
                self.cookies[seg[:eq]] = seg[eq + 1:]

    def _cookie_header(self):
        return '; '.join(f'{k}={v}' for k, v in self.cookies.items())

    def request(self, url, method='GET', data=None, timeout=15):
        """发一跳请求，返回 (status, headers, body_text)。不自动重定向。"""
        body = data.encode('utf-8') if isinstance(data, str) else data
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header('User-Agent', _UA)
        if self.cookies:
            req.add_header('Cookie', self._cookie_header())
        if method == 'POST':
            req.add_header('Content-Type',
                           'application/x-www-form-urlencoded')
        try:
            resp = self._opener.open(req, timeout=timeout)
            status, headers = resp.status, resp.headers
            text = resp.read().decode('utf-8', 'ignore')
        except urllib.error.HTTPError as e:
            # 3xx 因禁用自动重定向会走到这里；e 本身即 response-like。
            status, headers = e.code, e.headers
            try:
                text = e.read().decode('utf-8', 'ignore')
            except Exception:
                text = ''
        self._collect(headers)
        return status, headers, text

    def get_json(self, url, timeout=20):
        """GET 一个 JSON 接口（会跟随可能的 3xx 到 200）。"""
        status, headers, text = self.request(url, timeout=timeout)
        hops = 0
        while status in (301, 302, 303, 307, 308) and hops < 5:
            loc = headers.get('location')
            if not loc:
                break
            loc = _https(loc)
            status, headers, text = self.request(loc, timeout=timeout)
            hops += 1
        try:
            return json.loads(text)
        except Exception:
            return None

    def get_raw(self, url, timeout=30, _hops=0):
        """GET 二进制资源（PPT 图片等），跟随重定向，返回原始字节（失败/非 2xx 返回 b''）。

        与 [request]/[get_json] 共用已登录会话的 cookie，故能拉到需鉴权的
        classroom.zju.edu.cn 图片（离线可用）。
        """
        req = urllib.request.Request(url)
        req.add_header('User-Agent', _UA)
        if self.cookies:
            req.add_header('Cookie', self._cookie_header())
        resp = None
        try:
            resp = self._opener.open(req, timeout=timeout)
            status, headers = resp.status, resp.headers
        except urllib.error.HTTPError as e:  # 3xx/4xx/5xx 都走到这里
            resp = e
            status, headers = e.code, e.headers
        except urllib.error.URLError:
            return b''
        self._collect(headers)
        if status in (301, 302, 303, 307, 308) and _hops < 5:
            loc = headers.get('location')
            if loc:
                try:
                    resp.close()
                except Exception:
                    pass
                return self.get_raw(_https(loc), timeout=timeout, _hops=_hops + 1)
        try:
            data = resp.read()
        except Exception:
            data = b''
        try:
            resp.close()
        except Exception:
            pass
        return data if status < 400 else b''


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁用 urllib 自动重定向，改由业务代码逐跳收集 cookie。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _https(url):
    return url.replace('http://', 'https://', 1) if url.startswith('http://') \
        else url


# ═══════════════════════════════════════════════════════════
# 登录
# ═══════════════════════════════════════════════════════════

def rsa_encrypt(plaintext, modulus_hex, exponent_hex):
    """浙大 CAS 的无填充 RSA：password → utf8 → hex → modpow → hex(128)。

    与参考实现 _rsaEncrypt 完全一致（纯 modpow，无 PKCS#1 填充）。
    """
    hex_str = ''.join(f'{b:02x}' for b in plaintext.encode('utf-8'))
    mod = int(modulus_hex, 16)
    exp = int(exponent_hex, 16)
    pwd = int(hex_str, 16)
    enc = pow(pwd, exp, mod)
    return f'{enc:0128x}'


def sso_login(session, username, password):
    """浙大统一身份认证 RSA 登录，成功后 iPlanetDirectoryPro 已在 cookie 中。"""
    # Step 1: 拿 execution token + 初始 cookie
    _, _, body1 = session.request('https://zjuam.zju.edu.cn/cas/login')
    m = _EXECUTION_RE.search(body1)
    if not m:
        raise RuntimeError('无法提取 execution token（CAS 登录页结构可能已变更）')
    execution = m.group(1)

    # Step 2: 拿 RSA 公钥
    pub = session.get_json('https://zjuam.zju.edu.cn/cas/v2/getPubKey')
    if not pub or 'modulus' not in pub or 'exponent' not in pub:
        raise RuntimeError('无法获取 RSA 公钥')
    pwd_enc = rsa_encrypt(password, str(pub['modulus']), str(pub['exponent']))

    # Step 3: 提交登录表单
    form = (f'username={urllib.parse.quote(username)}'
            f'&password={urllib.parse.quote(pwd_enc)}'
            f'&execution={urllib.parse.quote(execution)}'
            f'&_eventId=submit&rememberMe=true')
    session.request('https://zjuam.zju.edu.cn/cas/login',
                    method='POST', data=form)

    if 'iPlanetDirectoryPro' not in session.cookies:
        raise RuntimeError('登录失败：学号或密码错误')


def login_classroom(session):
    """跟随 tgmedia OAuth2 重定向链，让智云课堂各域拿到会话 cookie。"""
    url = ('https://tgmedia.cmc.zju.edu.cn/index.php?r=auth%2Flogin'
           '&forward=https%3A%2F%2Fclassroom.zju.edu.cn%2F')
    for _ in range(25):
        status, headers, body = session.request(url)
        loc = headers.get('location')
        if not loc:
            # 尝试 meta refresh 跳转
            meta = re.search(
                r'meta http-equiv="refresh" content="0;URL=([^"]+)"', body)
            if not meta:
                break
            loc = meta.group(1)
        url = _https(loc)


# ═══════════════════════════════════════════════════════════
# 抓取 + 解析（纯函数，便于离线单元测试）
# ═══════════════════════════════════════════════════════════

def parse_courses(raw):
    """课程列表：data.params.result.data[] → {id,title,teachers}。"""
    out = []
    try:
        items = (raw or {}).get('params', {}).get('result', {}).get('data', [])
    except AttributeError:
        items = []
    for c in items or []:
        if not isinstance(c, dict):
            continue
        cid = _to_int(c.get('Id'))
        teacher = (c.get('Teacher') or '').strip()
        out.append({
            'id': cid,
            'title': (c.get('Title') or '').strip(),
            'teachers': _split_teachers(teacher),
        })
    return out


def parse_videos(raw):
    """录播目录：result.data[]（status==6）→ {subId,title,videoUrl}。"""
    out = []
    try:
        items = (raw or {}).get('result', {}).get('data', [])
    except AttributeError:
        items = []
    for v in items or []:
        if not isinstance(v, dict):
            continue
        if str(v.get('status')) != '6':
            continue
        out.append({
            'subId': _to_int(v.get('sub_id')),
            'title': (v.get('title') or '').strip(),
            'videoUrl': _extract_video_url(v.get('content')),
            'slides': [],
            'subtitles': [],
        })
    return out


def parse_slides(pages_raw):
    """PPT：多页 list[].content(JSON) → [{page,imageUrl,text}]（去重、页号递增）。"""
    out = []
    seen = set()
    for raw in pages_raw:
        if not isinstance(raw, dict):
            continue
        for item in raw.get('list', []) or []:
            if not isinstance(item, dict):
                continue
            content = _maybe_json(item.get('content'))
            if not isinstance(content, dict):
                continue
            img = (content.get('pptimgurl') or '').strip()
            if not img or img in seen:
                continue
            seen.add(img)
            out.append({
                'page': len(out) + 1,
                'imageUrl': img,
                'text': (content.get('text') or '').strip(),
            })
    return out


def parse_subtitles(raw):
    """字幕：list[].all_content[] → [{startMs,endMs,text}]。"""
    out = []
    try:
        items = (raw or {}).get('list', [])
    except AttributeError:
        items = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        for c in item.get('all_content', []) or []:
            if not isinstance(c, dict):
                continue
            text = (c.get('Text') or '').strip()
            if not text:
                continue
            begin = _to_float(c.get('BeginSec'))
            out.append({
                'startMs': int(begin * 1000),
                'endMs': 0,
                'text': text,
            })
    return out


# ---- 小工具 ----

def _to_int(v):
    try:
        return int(str(v).strip())
    except (ValueError, TypeError):
        return 0


def _to_float(v):
    try:
        return float(str(v).strip())
    except (ValueError, TypeError):
        return 0.0


def _split_teachers(teacher):
    if not teacher:
        return []
    parts = re.split(r'[，,、;；/]\s*', teacher)
    return [p.strip() for p in parts if p.strip()]


def _maybe_json(v):
    if isinstance(v, str):
        try:
            return json.loads(v)
        except Exception:
            return None
    return v


def _extract_video_url(content):
    parsed = _maybe_json(content)
    if not isinstance(parsed, dict):
        return None
    pb = parsed.get('playback')
    if isinstance(pb, dict) and pb.get('url'):
        return str(pb['url'])
    if parsed.get('video_url'):
        return str(parsed['video_url'])
    return None


# ═══════════════════════════════════════════════════════════
# 抓取编排
# ═══════════════════════════════════════════════════════════

def fetch_slides(session, course_id, sub_id, max_pages=20):
    pages = []
    for page in range(1, max_pages + 1):
        raw = session.get_json(
            API_PPT.format(course_id=course_id, sub_id=sub_id, page=page))
        if not isinstance(raw, dict):
            break
        lst = raw.get('list') or []
        pages.append(raw)
        if len(lst) < 100:
            break
    return parse_slides(pages)


def _plugin_dir():
    """解析插件根目录（classroom-demo/），兼容源码运行与 PyInstaller 冻结 exe。

    - 源码：`src/scraper.py` 的祖父目录 = 插件根。
    - 冻结 exe：`data/scraper.exe` 的祖父目录 = 插件根（__file__ 在临时解压区，不可用）。
    """
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        return Path(sys.executable).resolve().parent.parent
    return Path(__file__).resolve().parent.parent


def _download_slides_locally(session, course_id, sub_id, slides):
    """用已登录会话把 PPT 图片下载到插件本地 data/ppt/<course>/<sub>/page_N.png，
    并把 slide 的 imageUrl 改写为相对本地路径（离线可用）。

    失败（网络/鉴权）不抛，保持原远程 URL 不变，交给渲染层按需兜底下载。
    """
    if not slides:
        return
    plugin_dir = _plugin_dir()
    base = plugin_dir / 'data' / 'ppt' / str(course_id) / str(sub_id)
    for s in slides:
        img = (s.get('imageUrl') or '').strip()
        if not img or not img.startswith('http'):
            continue
        page = s.get('page', 0)
        rel = f'data/ppt/{course_id}/{sub_id}/page_{page}.png'
        dest = base / f'page_{page}.png'
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            data = session.get_raw(img)
            if data:
                dest.write_bytes(data)
                s['imageUrl'] = rel  # 改写为本地相对路径
        except Exception:
            continue


def scrape(session, max_courses=0, max_videos=3, time_budget=180):
    """抓取全部课程 → 组装成 classroom bindings 形状。

    为控制单次快照耗时：PPT/字幕仅对每门课前 [max_videos] 个录播抓取，
    并受 [time_budget] 秒总预算约束；其余录播保留视频列表（slides/subtitles 空）。
    """
    started = time.time()
    courses = parse_courses(session.get_json(API_COURSES))
    if max_courses and max_courses > 0:
        courses = courses[:max_courses]

    for course in courses:
        cid = course['id']
        videos = parse_videos(session.get_json(API_CATALOGUE.format(course_id=cid)))
        course['videos'] = videos
        for idx, v in enumerate(videos):
            over_budget = (time.time() - started) > time_budget
            if over_budget or (max_videos and idx >= max_videos):
                continue
            sub_id = v['subId']
            try:
                v['slides'] = fetch_slides(session, cid, sub_id)
            except Exception:
                v['slides'] = []
            # 用已登录会话把 PPT 图片下载到本地（离线可用），失败留远程 URL 兜底
            try:
                _download_slides_locally(session, cid, sub_id, v['slides'])
            except Exception:
                pass
            try:
                v['subtitles'] = parse_subtitles(
                    session.get_json(API_SUBTITLE.format(sub_id=sub_id)))
            except Exception:
                v['subtitles'] = []
    return {'courses': courses}


def _get_config_opt(key, default):
    try:
        val = _get_config(key)
        return val if val not in (None, '') else default
    except Exception:
        return default


def main():
    # 凭据仅来自设置页配置（config server 或等效注入），不读 .env、不硬编码。
    username = _get_config('CLASSROOM_USERNAME')
    password = _get_config('CLASSROOM_PASSWORD')
    max_courses = _to_int(_get_config_opt('CLASSROOM_MAX_COURSES', '0'))
    max_videos = _to_int(_get_config_opt('CLASSROOM_MAX_VIDEOS', '3'))
    time_budget = _to_int(_get_config_opt('CLASSROOM_TIME_BUDGET', '180')) or 180

    session = ZjuSession()
    sso_login(session, username, password)
    login_classroom(session)
    result = scrape(session, max_courses=max_courses,
                    max_videos=max_videos, time_budget=time_budget)
    # 持久化会话 cookie 到插件本地，供渲染层按需带登录态兜底下载远程资源
    # （首屏 PPT 图已由上面下载到本地 data/ppt/，此文件仅作兜底）。
    try:
        plugin_dir = _plugin_dir()
        cookie_path = plugin_dir / 'data' / 'classroom_cookies.json'
        cookie_path.parent.mkdir(parents=True, exist_ok=True)
        cookie_path.write_text(json.dumps(session.cookies, ensure_ascii=False))
    except Exception:
        pass
    return result


if __name__ == '__main__':
    # register_data_source.dart 以 `--type <t> --project-root <root>` 调用；
    # 解析 project-root 注入 PROJECT_ROOT 便于 _get_config 定位 .config_port。
    _ap = argparse.ArgumentParser()
    _ap.add_argument('--type', default='classroom')
    _ap.add_argument('--project-root', default=None)
    _args, _ = _ap.parse_known_args()
    if _args.project_root:
        os.environ.setdefault('PROJECT_ROOT', _args.project_root)
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as _e:
        print(json.dumps({'error': str(_e)}, ensure_ascii=False))
        sys.exit(1)
