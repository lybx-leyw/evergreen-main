# ═══════════════════════════════════════════════════════════
# EVERGREEN CONFIG TEMPLATE (LOCKED — DO NOT MODIFY)
# ═══════════════════════════════════════════════════════════
import json, os, sys, urllib.request, urllib.error
from pathlib import Path

def _get_config(key):
    """从平台配置读取凭证（三级降级）。

    策略1（主）：.greenix/config.json 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 环境变量指定）
    策略2（降级）：HTTP 从 ConfigHttpServer 读取
    策略3（兜底）：系统环境变量
    """
    sys.stderr.write(f'[CONFIG] _get_config(key="{key}") 开始\n'); sys.stderr.flush()
    # ── 策略1：.greenix/config.json 本地文件直接读取 ──
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            config_path = Path(greenix_path)
            sys.stderr.write(f'[CONFIG] 策略1 GREENIX_CONFIG_PATH={config_path}\n'); sys.stderr.flush()
            if config_path.exists():
                with open(config_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                sys.stderr.write(f'[CONFIG] 策略1 config.json keys={list(cfg.keys())}\n'); sys.stderr.flush()
                if key in cfg:
                    val = cfg[key]
                    if val:
                        sys.stderr.write(f'[CONFIG] 策略1(本地) 成功: key="{key}" → len={len(val)}\n'); sys.stderr.flush()
                        return val
                    else:
                        sys.stderr.write(f'[CONFIG] 策略1 key="{key}" 存在但值为空，降级\n'); sys.stderr.flush()
                else:
                    val = ''
                    sys.stderr.write(f'[CONFIG] 策略1 config.json 中无 key="{key}"\n'); sys.stderr.flush()
            else:
                sys.stderr.write(f'[CONFIG] 策略1 GREENIX_CONFIG_PATH 指向的文件不存在: {config_path}\n'); sys.stderr.flush()
        except Exception as e:
            sys.stderr.write(f'[CONFIG] 策略1(本地) 异常: {e}\n'); sys.stderr.flush()
    else:
        sys.stderr.write(f'[CONFIG] 策略1 GREENIX_CONFIG_PATH 未设置（桌面端可能未传参）\n'); sys.stderr.flush()

    # ── 策略2：HTTP 从 ConfigHttpServer 读取 ──
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
            sys.stderr.write(f'[CONFIG] 策略2 找到 .config_port={port}\n'); sys.stderr.flush()
            url = f'http://127.0.0.1:{port}/config/settings/{key}'
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                val = data.get('value', '')
                if val:
                    sys.stderr.write(f'[CONFIG] 策略2(HTTP) 成功: key="{key}" → len={len(val)}\n'); sys.stderr.flush()
                    return val
    except Exception as e:
        sys.stderr.write(f'[CONFIG] 策略2(HTTP) 异常: {e}\n'); sys.stderr.flush()

    # ── 策略3：系统环境变量 ──
    val = os.environ.get(key)
    if val:
        sys.stderr.write(f'[CONFIG] 策略3(环境变量) 成功: key="{key}"\n'); sys.stderr.flush()
        return val
    sys.stderr.write(f'[CONFIG] 策略3(环境变量) key="{key}" 未设置\n'); sys.stderr.flush()

    raise RuntimeError(
        f'无法获取配置 "{key}"：\n'
        f'  1. .greenix/config.json 不存在或无此 key（GREENIX_CONFIG_PATH={os.environ.get("GREENIX_CONFIG_PATH", "未设置")}）\n'
        f'  2. ConfigHttpServer 不可用（检查 .config_port）\n'
        f'  3. 环境变量未设置\n'
        f'  → 请在设置面板注册此配置项，或设置环境变量 {key}'
    )


# ═══════════════════════════════════════════════════════════
# CREDENTIALS — 延迟加载（避免模块级调用 _get_config 导致
# Android 上 import 时 ConfigHttpServer 不可用而崩溃）
# ═══════════════════════════════════════════════════════════
_CREDENTIAL_CACHE = None

def _get_credentials():
    """延迟加载凭证（首次访问时从配置系统获取）。"""
    global _CREDENTIAL_CACHE
    if _CREDENTIAL_CACHE is None:
        _CREDENTIAL_CACHE = {
            'USERNAME': _get_config('ZJU_USERNAME'),
            'PASSWORD': _get_config('ZJU_PASSWORD'),
        }
    return _CREDENTIAL_CACHE

# ═══════════════════════════════════════════════════════════
# BUSINESS CODE
# ═══════════════════════════════════════════════════════════
import requests
import re
import sys
import time
import json
import argparse


# ── ZDBK 业务常量（与 cp_evergreen_push 的 zdbk_service.dart 端点对齐）──
_ZDBK_BASE = 'https://zdbk.zju.edu.cn/jwglxt'
_UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
       '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
_REFERER_INDEX = f'{_ZDBK_BASE}/xtgl/index_initMenu.html'


def rsa_encrypt_zju(password, modulus_hex, exponent_hex):
    """
    模拟 ZJU CAS 的 RSA 加密：
    1. 反转密码
    2. 取 charCode
    3. 每 2 字节 pack 为 16-bit digit (little-endian)
    4. 填充到 chunkSize
    5. modular exponentiation
    """
    # 1. 反转密码
    reversed_pwd = password[::-1]
    
    # 2. 取 char codes
    a = [ord(c) for c in reversed_pwd]
    
    # 3. 计算 chunkSize
    # modulus_hex 是 128 hex chars = 512 bits
    # BigInt: 每个 digit 16 bits, 所以 512/16 = 32 digits
    # biHighIndex = 32 - 1 = 31
    # chunkSize = 2 * 31 = 62
    modulus_bytes = len(modulus_hex) // 2
    modulus_digits = modulus_bytes // 2  # 每个 digit 2 字节
    bi_high_index = modulus_digits - 1
    chunk_size = 2 * bi_high_index
    
    # 4. 填充到 chunkSize 的倍数
    while len(a) % chunk_size != 0:
        a.append(0)
    
    # 5. RSA 加密
    modulus = int(modulus_hex, 16)
    exponent = int(exponent_hex, 16)
    
    result_parts = []
    for i in range(0, len(a), chunk_size):
        chunk = a[i:i + chunk_size]
        
        # 将 chars 打包为 BigInt 值
        # 每 2 个 char 组成一个 16-bit digit (little-endian)
        block_value = 0
        for j in range(len(chunk) // 2):
            low = chunk[j * 2]
            high = chunk[j * 2 + 1]
            digit_val = low + (high << 8)
            block_value |= digit_val << (16 * j)
        
        # 模幂运算
        encrypted = pow(block_value, exponent, modulus)
        
        # 转 hex
        hex_str = format(encrypted, 'x')
        result_parts.append(hex_str)
    
    return ' '.join(result_parts)


def cas_login(session, username, password):
    """ZJU CAS Login"""
    service = 'https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html'
    login_url = f'https://zjuam.zju.edu.cn/cas/login?service={requests.utils.quote(service)}'
    
    headers = {
        'User-Agent': _UA,
    }
    session.headers.update(headers)
    
    # Step 1: 获取 CAS 登录页面
    sys.stderr.write('[Step 1] 获取 CAS 登录页面...\n')
    r = session.get(login_url)
    
    match = re.search(r'name="execution" value="([^"]+)"', r.text)
    if not match:
        raise Exception("未找到 execution token")
    execution = match.group(1)
    
    # Step 2: 获取 RSA 公钥
    sys.stderr.write('[Step 2] 获取 RSA 公钥...\n')
    r = session.get('https://zjuam.zju.edu.cn/cas/v2/getPubKey')
    pub_key = r.json()
    modulus = pub_key['modulus']
    exponent = pub_key['exponent']
    
    # Step 3: RSA 加密密码 (ZJU 方式)
    sys.stderr.write('[Step 3] RSA 加密密码(ZJU算法)...\n')
    enc_password = rsa_encrypt_zju(password, modulus, exponent)
    
    # Step 4: 提交登录
    sys.stderr.write('[Step 4] 提交登录...\n')
    data = {
        'username': username,
        'password': enc_password,
        'authcode': '',
        'rememberMe': 'true',
        'execution': execution,
        '_eventId': 'submit',
        'geolocation': '',
    }
    
    r = session.post(login_url, data=data, allow_redirects=False)
    sys.stderr.write(f'[Step 4] 状态码: {r.status_code}\n')
    
    if r.status_code in (301, 302, 303, 307, 308):
        redirect_url = r.headers.get('Location')
        sys.stderr.write(f'[Step 4] 登录成功! 重定向到: {redirect_url[:80]}...\n')
        r = session.get(redirect_url, allow_redirects=True)
        sys.stderr.write(f'[Step 4] 最终 URL: {r.url}\n')
    else:
        err = None
        error_match = re.search(r'<div[^>]*id="errormsg"[^>]*>([^<]+)', r.text)
        if error_match:
            err = error_match.group(1)
        else:
            error_match = re.search(r'<span[^>]*id="msg"[^>]*>([^<]+)', r.text)
            if error_match:
                err = error_match.group(1)
        sys.stderr.write(f'[Error] 登录失败: {err}\n')
        raise Exception(f"CAS 登录失败: {err}" if err else "CAS 登录失败")
    
    return session


def _verify_zdbk_session(session):
    """登录后确认 CAS ticket 被 zdbk 接受（落在 index_initMenu 而非 login_slogin）。

    对齐参考 ZdbkService.login 对 JSESSIONID/route 的校验：SSO 偶发拒收 ticket，
    此时需重登。返回 False 即触发重试。补 Referer 以匹配参考的请求头。
    """
    r = session.get(f'{_ZDBK_BASE}/xtgl/index_initMenu.html',
                    headers={'User-Agent': _UA, 'Referer': _REFERER_INDEX},
                    allow_redirects=True)
    return not _is_session_expired(r.text)


# ── 通用请求 / 解析原语（对齐 zdbk_service.dart 的 _zdbkPost / HtmlParser）──

def _zdbk_headers(referer):
    """ZDBK 数据接口请求头（对齐参考 _zdbkSetHeaders）。

    含 X-Requested-With + Accept: application/json，使 JSON 接口返回数据而非整页。
    """
    return {
        'User-Agent': _UA,
        'Referer': referer,
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
        'Connection': 'close',
    }


def _zdbk_post(session, url, referer, form=None):
    """POST 一个 ZDBK 数据接口，返回响应文本。"""
    headers = _zdbk_headers(referer)
    if form:
        headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8'
    r = session.post(url, data=form or {}, headers=headers)
    return r.text


def _extract_bracketed_array(text, key='"items"'):
    """从 ZDBK 响应（HTML 或 JSON）中提取名为 key 的 JSON 数组（支持嵌套数组）。

    对齐参考 ZdbkPatterns.itemsWithLimit / itemsWithTotalResult，但用括号深度扫描
    替代非贪婪正则，避免数组内含 ']' 时截断。
    """
    marker = key + ':'
    idx = text.find(marker)
    if idx < 0:
        return None
    start = text.find('[', idx)
    if start < 0:
        return None
    depth = 0
    in_str = False
    esc = False
    for j in range(start, len(text)):
        c = text[j]
        if in_str:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    return None


def _extract_items(text):
    """从 HTML/JSON 响应提取 items 数组（对齐 HtmlParser.extractItems）。"""
    arr = _extract_bracketed_array(text, '"items"')
    if arr is None:
        return []
    try:
        items = json.loads(arr)
    except Exception:
        return []
    return [it for it in items if isinstance(it, dict)]


def _is_session_expired(html):
    """检测响应是否为 CAS 登录页（会话过期，对齐 HtmlParser.isSessionExpired）。"""
    return ('login_ssologin' in html or 'cas/login' in html
            or 'idp.zju.edu.cn' in html or '统一身份认证' in html
            or '统一认证' in html or '/cas/' in html)


def _strip_tags(s):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', s or '')).strip()


# ── 各数据类型抓取（对齐 zdbk_service.dart 各 public 方法）──

def get_course_schedule(session, student_id):
    """获取学生课表数据（已验证可用，保留原始实现）"""
    # Step 5: 访问课表查询页面
    sys.stderr.write('[Step 5] 访问课表查询页面...\n')
    index_url = (f'{_ZDBK_BASE}/kbcx/xskbcx_cxXskbcxIndex.html'
                 f'?gnmkdm=N253508&layout=default&su={student_id}')
    r = session.get(index_url)
    sys.stderr.write(f'[Step 5] 状态码: {r.status_code}\n')
    
    # Step 6: 调用课表数据 API
    sys.stderr.write('[Step 6] 获取课表数据...\n')
    data_url = f'{_ZDBK_BASE}/kbcx/xskbcx_cxXsKb.html'
    form_data = {'xnm': '', 'xqm': ''}
    params = {'gnmkdm': 'N253508', 'su': student_id}
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Referer': (f'{_ZDBK_BASE}/kbcx/xskbcx_cxXskbcxIndex.html'
                    f'?gnmkdm=N253508&layout=default&su={student_id}'),
        'User-Agent': _UA,
    }
    r = session.post(data_url, data=form_data, headers=headers, params=params)
    sys.stderr.write(f'[Step 6] 状态码: {r.status_code}\n')
    
    if r.status_code != 200:
        raise Exception(f"获取课表失败，状态码: {r.status_code}")
    try:
        return r.json()
    except Exception:
        sys.stderr.write(f'[Debug] 响应内容(前300字): {r.text[:300]}\n')
        raise Exception("课表数据不是 JSON 格式")


def get_transcript(session, student_id):
    """成绩单（全部学期成绩），返回 items 列表。"""
    url = (f'{_ZDBK_BASE}/cxdy/xscjcx_cxXscjIndex.html'
           f'?doType=query&queryModel.showCount=5000')
    html = _zdbk_post(session, url, _REFERER_INDEX)
    if _is_session_expired(html):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    return _extract_items(html)


def get_major_grade(session, student_id):
    """主修成绩，返回 items 列表。"""
    url = (f'{_ZDBK_BASE}/zycjtj/xszgkc_cxXsZgkcIndex.html'
           f'?doType=query&queryModel.showCount=5000')
    html = _zdbk_post(session, url, _REFERER_INDEX)
    if _is_session_expired(html):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    return _extract_items(html)


def get_exams(session, student_id):
    """考试安排，返回 items 列表。"""
    url = (f'{_ZDBK_BASE}/xskscx/kscx_cxXsgrksIndex.html'
           f'?doType=query&queryModel.showCount=5000')
    html = _zdbk_post(session, url, _REFERER_INDEX)
    if _is_session_expired(html):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    return _extract_items(html)


def get_course_offerings(session, student_id, year=2025, semester=12):
    """开课情况，返回 items 列表。year/semester 可通过参数覆盖。"""
    zju_sem = '1' if semester == 3 else '2'
    sem_range = f'{year}-{year + 1}{zju_sem}'
    url = (f'{_ZDBK_BASE}/jxzlpj/jszlpj_cxKkqkIndex.html'
           f'?gnmkdm=N159035&doType=query'
           f'&tjksxq={sem_range}&tjjsxq={sem_range}'
           f'&cxType=jxrw&queryModel.showCount=10000')
    text = _zdbk_post(session, url, _REFERER_INDEX)
    if _is_session_expired(text):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    try:
        data = json.loads(text)
    except Exception:
        return []
    return data.get('items') or data.get('data') or []


def get_training_plans(session, student_id):
    """培养方案列表，返回 items 列表（JSON 或 HTML 自适应）。"""
    index = (f'{_ZDBK_BASE}/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html'
             f'?gnmkdm=N153020&layout=default')
    session.get(index, headers={'User-Agent': _UA, 'Referer': _REFERER_INDEX})
    url = (f'{_ZDBK_BASE}/pyfagl/pyfaxxcx_cxPyfaxscxIndex.html'
           f'?gnmkdm=N153020&layout=default&doType=query&queryModel.showCount=5000')
    text = _zdbk_post(session, url, index)
    if _is_session_expired(text):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    try:
        data = json.loads(text)
        return data.get('items') or data.get('data') or []
    except Exception:
        return _extract_items(text)


def _parse_practice_scores(html):
    """从第二/三/四课堂页面解析成绩（对齐 ZdbkPatterns.practiceScoreRow）。"""
    row_re = re.compile(
        r'<tr>.*?<td[^>]*>.*?</td>.*?<td[^>]*>(.*?)</td>'
        r'.*?<td[^>]*>(.*?)</td>.*?</tr>', re.DOTALL)
    scores = {'pt2': 0.0, 'pt3': 0.0, 'pt4': 0.0}
    for m in row_re.finditer(html):
        t = _strip_tags(m.group(1))
        s = _strip_tags(m.group(2))
        try:
            v = float(s)
        except Exception:
            continue
        if '第二课堂' in t:
            scores['pt2'] = v
        elif '第三课堂' in t:
            scores['pt3'] = v
        elif '第四课堂' in t:
            scores['pt4'] = v
    return scores


def get_practice_scores(session, student_id):
    """第二/三/四课堂成绩，返回 {pt2, pt3, pt4}。"""
    url = (f'{_ZDBK_BASE}/dessktgl/dessktcx_cxDessktcxIndex.html'
           f'?gnmkdm=N108001&layout=default&su={student_id}')
    r = session.get(url, headers={'User-Agent': _UA, 'Referer': _REFERER_INDEX})
    html = r.text
    if _is_session_expired(html):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    return _parse_practice_scores(html)


def _parse_notifications(html):
    """解析通知公告（对齐 parseZdbkNotifications）。"""
    item_re = re.compile(
        r'<li>\s*<a[^>]*data-xwbh="([^"]+)"[^>]*>.*?<label>(.*?)</label>',
        re.DOTALL)
    results = []
    for m in item_re.finditer(html):
        nid = m.group(1)
        title = _strip_tags(m.group(2))
        if not nid:
            continue
        results.append({'id': nid, 'title': title})
    pane_re = re.compile(
        r'<div[^>]*id="tabNews(\d+)"[^>]*class="tab-pane tab-pane-news"[^>]*>'
        r'(.*?)发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)'
        r'.*?<div class="news_con">(.*?)</div>\s*</div>', re.DOTALL)
    i = 0
    for m in pane_re.finditer(html):
        if i >= len(results):
            break
        results[i].update({
            'publisher': m.group(3).strip(),
            'publishDate': m.group(4).strip(),
            'viewCount': int(m.group(5) or 0),
            'content': m.group(6).strip(),
        })
        i += 1
    if i == 0:
        detail_re = re.compile(
            r'发布人[：:]\s*([^<]+).*?发布时间[：:]\s*([^<]+).*?浏览人数[：:]\s*(\d+)',
            re.DOTALL)
        for m in detail_re.finditer(html):
            if i >= len(results):
                break
            results[i].update({
                'publisher': m.group(1).strip(),
                'publishDate': m.group(2).strip(),
                'viewCount': int(m.group(3) or 0),
            })
            i += 1
    return results


def get_notifications(session, student_id):
    """通知公告，返回通知列表。"""
    t = int(time.time() * 1000)
    url = (f'{_ZDBK_BASE}/xtgl/index_cxTctxNews.html'
           f'?time={t}&gnmkdm=index&su={student_id}')
    html = _zdbk_post(session, url, _REFERER_INDEX)
    if _is_session_expired(html):
        raise RuntimeError('ZDBK 会话已过期，请重新登录')
    return _parse_notifications(html)


# ── 分派表（--type 值 = manifest 中 dataTypes[].typeArg）──
_DISPATCH = {
    'zdbk_timetable': get_course_schedule,
    'zdbk_transcript': get_transcript,
    'zdbk_major_grade': get_major_grade,
    'zdbk_exams': get_exams,
    'zdbk_course_offerings': get_course_offerings,
    'zdbk_training_plans': get_training_plans,
    'zdbk_practice_scores': get_practice_scores,
    'zdbk_notifications': get_notifications,
}


def main(type_arg='all', max_attempts=4):
    """抓取指定类型数据，SSO 偶发拒收 ticket 时自动重登重试。

    - type_arg='all'（默认，即不传 --type）时一次登录后依次抓取全部类型，
      返回 {typeArg: data} 字典；
    - type_arg 为某个具体类型时返回该类型原始对象（保持平台单类型契约不变）。
    - 真实凭证错误（用户名或密码错误 / execution 缺失）不重试，直接报错；
    - SSO 未落地、会话过期、数据非 JSON 等可恢复错误最多重试 max_attempts 次。
    """
    if type_arg != 'all' and type_arg not in _DISPATCH:
        raise ValueError(f'未知数据类型: {type_arg}（可选: {", ".join(sorted(_DISPATCH))} / all）')

    types = list(_DISPATCH) if type_arg == 'all' else [type_arg]

    last_err = None
    for attempt in range(1, max_attempts + 1):
        try:
            session = requests.Session()
            creds = _get_credentials()
            cas_login(session, creds['USERNAME'], creds['PASSWORD'])
            if not _verify_zdbk_session(session):
                raise RuntimeError('ZDBK SSO 未落地（落在 login_slogin.html），需重试')
            results = {t: _DISPATCH[t](session, creds['USERNAME']) for t in types}
            if type_arg == 'all':
                return results
            out = results[type_arg]
            # 平台单类型契约：register_data_source 把 scraper stdout 强转
            # Map<String, dynamic>。timetable/practice 本就是 Map，但 transcript/
            # major_grade/exams/course_offerings/training_plans/notifications 这些
            # 列表型数据需包进 {"items": [...]} 顶层 Map，否则裸 List 触发
            # `List<dynamic> is not Map<String, dynamic>` 类型转换异常。
            if isinstance(out, list):
                return {'items': out}
            return out
        except Exception as e:
            last_err = e
            msg = str(e)
            # 真实凭证/结构错误，重试无意义
            if '用户名或密码错误' in msg or '未找到 execution' in msg:
                sys.stderr.write(f'错误: {msg}\n')
                raise
            sys.stderr.write(f'[retry {attempt}/{max_attempts}] {type(e).__name__}: {msg}\n')
            # 退避拉长，给 ZJU CAS 服务端喘息，避免连续登录被软限流（落在
            # login_slogin.html / ticket 被拒）。
            time.sleep(2 * attempt + 1)
    sys.stderr.write(f'错误: 重试 {max_attempts} 次仍失败: {last_err}\n')
    raise last_err


if __name__ == '__main__':
    # 平台以 `--type <typeArg> --project-root <root>` 调用；project-root 注入
    # PROJECT_ROOT 便于 _get_config 定位 .config_port。不传 --type 时默认打印全部类型。
    _ap = argparse.ArgumentParser()
    _ap.add_argument('--type', default='all')
    _ap.add_argument('--project-root', default=None)
    _args, _ = _ap.parse_known_args()
    if _args.project_root:
        os.environ.setdefault('PROJECT_ROOT', _args.project_root)
    try:
        result = main(_args.type)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as _e:
        print(json.dumps({'error': str(_e)}, ensure_ascii=False))
        sys.exit(1)

# ==== EVERGREEN JSON VALIDATOR (auto-injected) ====
# DO NOT MODIFY — generated by scraper_json_validator.dart

import json, sys, re
from typing import Any

def validate_and_output(data: Any):
    """验证并输出数据为合法 JSON 到 stdout。

    规则：
    1. data 必须是 dict 或 list（顶层容器）
    2. 所有值必须是 JSON 可序列化类型
    3. 若 data 含 __json_ops__ 键，执行声明式数据处理（过滤/计算等）
    4. 输出到 stdout 的必须是合法 JSON 字符串
    """
    # 1) 验证顶层类型
    if not isinstance(data, (dict, list)):
        print(json.dumps({"error": f"scraper 输出类型错误: {type(data).__name__}，必须是 dict 或 list"}, ensure_ascii=False))
        sys.exit(1)

    # 2) 执行声明式数据处理（如果存在 __json_ops__）
    if isinstance(data, dict) and "__json_ops__" in data:
        ops = data.pop("__json_ops__")
        data = _apply_ops(data, ops)

    # 3) 序列化验证
    try:
        result = json.dumps(data, ensure_ascii=False, default=str)
        # 二次解析确认可逆
        json.loads(result)
        print(result)
    except (TypeError, json.JSONDecodeError) as e:
        print(json.dumps({"error": f"JSON 序列化失败: {e}"}, ensure_ascii=False))
        sys.exit(1)


def _apply_ops(data: dict, ops: dict) -> dict:
    """声明式数据处理管道。

    支持的 ops:
      - filter: {"field": "name", "keep": ["value1", "value2"]}  保留匹配项
      - filter: {"field": "name", "regex": "pattern"}            正则匹配保留
      - filter: {"field": "name", "min": 0, "max": 100}         数值范围
      - compute: {"field": "new_field", "op": "add|sub|mul|div", "a": "field1", "b": 100}  四则运算
      - compute: {"field": "new_field", "op": "concat", "a": "field1", "b": "field2"}      字符串拼接
      - sort: {"field": "name", "reverse": false}                排序
      - limit: 10                                                截取前 N 条
      - map: {"field": "name", "to": "new_name"}                 重命名字段
    """
    items = data if isinstance(data, list) else [data]
    is_single = not isinstance(data, list)

    for op_key, op_val in ops.items():
        if op_key == "filter" and isinstance(op_val, list):
            for f in op_val:
                items = _apply_filter(items, f)
        elif op_key == "compute" and isinstance(op_val, list):
            for c in op_val:
                items = _apply_compute(items, c)
        elif op_key == "sort" and isinstance(op_val, dict):
            items = sorted(items, key=lambda x: x.get(op_val.get("field", ""), ""), reverse=op_val.get("reverse", False))
        elif op_key == "limit" and isinstance(op_val, int):
            items = items[:op_val]
        elif op_key == "map" and isinstance(op_val, list):
            for m in op_val:
                items = _apply_map(items, m)

    return items[0] if is_single and items else items


def _apply_filter(items: list, f: dict) -> list:
    field = f.get("field", "")
    if not field: return items
    if "keep" in f:
        keep_vals = set(f["keep"])
        return [item for item in items if str(item.get(field, "")) in keep_vals]
    if "regex" in f:
        pattern = re.compile(f["regex"])
        return [item for item in items if pattern.search(str(item.get(field, "")))]
    if "min" in f or "max" in f:
        result = []
        for item in items:
            val = item.get(field)
            if val is None: continue
            try:
                num = float(val)
                if "min" in f and num < float(f["min"]): continue
                if "max" in f and num > float(f["max"]): continue
                result.append(item)
            except (ValueError, TypeError):
                continue
        return result
    return items


def _apply_compute(items: list, c: dict) -> list:
    field = c.get("field", "")
    op = c.get("op", "")
    a = c.get("a", "")
    b = c.get("b", "")
    if not field or not op: return items
    for item in items:
        va = item.get(a, a) if isinstance(a, str) else a
        vb = item.get(b, b) if isinstance(b, str) else b
        try:
            if op == "add": item[field] = float(va) + float(vb)
            elif op == "sub": item[field] = float(va) - float(vb)
            elif op == "mul": item[field] = float(va) * float(vb)
            elif op == "div": item[field] = float(va) / float(vb) if float(vb) != 0 else 0
            elif op == "concat": item[field] = str(va) + str(vb)
        except (ValueError, TypeError):
            item[field] = None
    return items


def _apply_map(items: list, m: dict) -> list:
    old_field = m.get("field", "")
    new_field = m.get("to", "")
    if not old_field or not new_field: return items
    for item in items:
        if old_field in item:
            item[new_field] = item.pop(old_field)
    return items


# ==== END VALIDATOR ====

