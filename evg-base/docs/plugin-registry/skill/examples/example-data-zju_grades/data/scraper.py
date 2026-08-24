# ═══════════════════════════════════════════════════════════
# EVERGREEN CONFIG TEMPLATE (LOCKED — DO NOT MODIFY)
# ═══════════════════════════════════════════════════════════
import json, os, urllib.request, urllib.error
from pathlib import Path

def _get_config(key):
    """从平台配置读取凭证（三级降级）。

    策略1（主）：.greenix/config.json 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 环境变量指定）
    策略2（降级）：HTTP 从 ConfigHttpServer 读取
    策略3（兜底）：系统环境变量
    """
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            config_path = Path(greenix_path)
            if config_path.exists():
                with open(config_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass
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
    val = os.environ.get(key)
    if val:
        return val
    raise RuntimeError(
        f'无法获取配置 "{key}"：\n'
        f'  1. .greenix/config.json 不存在或无此 key\n'
        f'  2. ConfigHttpServer 不可用（检查 .config_port）\n'
        f'  3. 环境变量未设置\n'
        f'  → 请在设置面板注册此配置项，或设置环境变量 {key}'
    )


# ═══════════════════════════════════════════════════════════
# CREDENTIALS — AI 填空区
USERNAME = _get_config('ZJU_USERNAME')
PASSWORD = _get_config('ZJU_PASSWORD')
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
# 业务代码：浙江大学教务系统（zdbk.zju.edu.cn）历年成绩爬虫
# 数据源：成绩查询页面 N5083 的 xscjcx_cxXscjIndex.html?doType=query 接口
# ═══════════════════════════════════════════════════════════
import sys
import re
import time
import requests
import urllib.parse

JWGLXT = 'https://zdbk.zju.edu.cn/jwglxt'
CAS = 'https://zjuam.zju.edu.cn/cas'
SERVICE = 'https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html'

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}


def _rsa_encrypt(password, modulus_hex, exponent_hex):
    """ZJU CAS RSA 加密密码（教科书式 no-padding），密文补齐 modulus 位长。"""
    m = int.from_bytes(password.encode('utf-8'), 'big')
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    c = pow(m, e, n)
    hex_len = (n.bit_length() + 3) // 4
    return format(c, 'x').zfill(hex_len)


def cas_login(session):
    """浙大统一认证登录，返回登录后教务系统 URL。"""
    # 1. 打开教务登录页建立会话
    session.get(JWGLXT + '/xtgl/login_slogin.html?language=zh_CN', headers=HEADERS, timeout=30)

    # 2. 获取 SSO 跳转地址
    sso_url = None
    try:
        r = session.post(
            JWGLXT + '/xtgl/login_cxSsoLoginUrl.html',
            data={},
            headers={**HEADERS, 'Referer': JWGLXT + '/xtgl/login_slogin.html?language=zh_CN'},
            timeout=30,
        )
        txt = r.text.strip()
        if txt.startswith('{'):
            try:
                data = json.loads(txt)
                for key in ('url', 'loginUrl', 'ssoUrl', 'redirectUrl'):
                    if data.get(key):
                        sso_url = data[key]
                        break
            except Exception:
                pass
        if not sso_url:
            m = re.search(r'https://zjuam\.zju\.edu\.cn/cas/login\?service=[^"\'\s]+', txt)
            if m:
                sso_url = m.group(0)
    except Exception as e:
        sys.stderr.write('获取 SSO 地址异常: %s\n' % e)
    if not sso_url:
        sso_url = CAS + '/login?service=' + urllib.parse.quote(SERVICE, safe='')

    # 3. 打开 CAS 登录页，提取 hidden 字段（execution 等）
    r = session.get(sso_url, headers=HEADERS, timeout=30)
    html = r.text
    form_data = {}
    for tag in re.finditer(r'<input[^>]*>', html):
        tag = tag.group(0)
        if 'type="hidden"' not in tag and "type='hidden'" not in tag:
            continue
        name_m = re.search(r'name=["\']([^"\']+)["\']', tag)
        if not name_m:
            continue
        value_m = re.search(r'value=["\']([^"\']*)["\']', tag)
        form_data[name_m.group(1)] = value_m.group(1) if value_m else ''

    # 4. 获取 RSA 公钥并加密密码
    r = session.get(CAS + '/v2/getPubKey', headers=HEADERS, timeout=30)
    pub = r.json()
    enc_pwd = _rsa_encrypt(PASSWORD, pub['modulus'], pub['exponent'])

    # 5. 提交登录表单
    form_data['username'] = USERNAME
    form_data['password'] = enc_pwd
    form_data.setdefault('authcode', '')
    form_data.setdefault('_eventId', 'submit')
    r = session.post(sso_url, data=form_data, headers={
        **HEADERS,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': sso_url,
    }, timeout=30, allow_redirects=True)
    return r.url


def _parse_xkkh(xkkh):
    """从选课课号 (2025-2026-1)-XXXX 中解析学年学期。"""
    m = re.match(r'\((\d{4})-(\d{4})-(\d)\)', str(xkkh))
    if m:
        return {
            'xnm': '%s-%s' % (m.group(1), m.group(2)),
            'xqdm': m.group(3),
        }
    return {'xnm': '', 'xqdm': ''}


def fetch_all_grades(session):
    """调用成绩查询接口，拉取所有学年所有学期全部课程成绩。"""
    index_url = JWGLXT + '/cxdy/xscjcx_cxXscjIndex.html?gnmkdm=N5083&layout=default&su=' + USERNAME
    session.get(index_url, headers={**HEADERS, 'Referer': JWGLXT + '/xtgl/index_initMenu.html?jsdm=06'}, timeout=30)

    query_url = JWGLXT + '/cxdy/xscjcx_cxXscjIndex.html?doType=query'
    headers = {
        **HEADERS,
        'Referer': index_url,
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
    }

    def query_page(page, show_count=200):
        data = {
            'xn': '',            # 空 = 全部学年
            'xq': '',            # 空 = 全部学期
            'zscjl': '',         # 成绩段最小值
            'zscjr': '',         # 成绩段最大值
            'page': str(page),
            'rows': str(show_count),
            'sidx': 'xkkh',
            'sord': 'asc',
            '_search': 'false',
            'nd': str(int(time.time() * 1000)),
            'queryModel.currentPage': str(page),
            'queryModel.showCount': str(show_count),
        }
        r = session.post(query_url, data=data, headers=headers, timeout=30)
        return r.json()

    all_items = []
    j = query_page(1)
    total = int(j.get('totalCount') or 0)
    items = j.get('items') or []
    sys.stderr.write('查询 totalCount=%s 首屏 items=%s\n' % (total, len(items)))
    if items:
        all_items.extend(items)
        total_page = int(j.get('totalPage') or 1)
        for p in range(2, total_page + 1):
            jj = query_page(p)
            page_items = jj.get('items') or []
            if not page_items:
                break
            all_items.extend(page_items)
            time.sleep(0.5)

    # 去重并整理输出
    seen = set()
    grades = []
    for it in all_items:
        xkkh = it.get('xkkh', '')
        parsed = _parse_xkkh(xkkh)
        key = (parsed['xnm'], parsed['xqdm'], xkkh, it.get('kcmc', ''), it.get('cj', ''), it.get('xf', ''))
        if key in seen:
            continue
        seen.add(key)
        grades.append({
            'xnm': parsed['xnm'],                 # 学年（如 2025-2026）
            'xqdm': parsed['xqdm'],               # 学期代码（1=秋冬 2=春夏）
            'xkkh': xkkh,                          # 选课课号
            'kcmc': it.get('kcmc', ''),            # 课程名称
            'cj': it.get('cj', ''),                # 成绩
            'xf': it.get('xf', ''),                # 学分
            'jd': it.get('jd', ''),                # 绩点
            'bkcj': it.get('bkcj', ''),            # 备注
        })
    return grades


def main():
    session = requests.Session()
    final_url = cas_login(session)
    sys.stderr.write('登录后 URL: %s\n' % final_url)
    if 'login_slogin.html' in final_url and 'ticket=' not in final_url:
        if '/cas/login' in final_url:
            raise RuntimeError('CAS 登录失败：用户名或密码错误，或需要验证码')
        raise RuntimeError('未进入教务系统，登录可能失败: %s' % final_url)

    grades = fetch_all_grades(session)
    sys.stderr.write('共获取成绩记录: %d 条\n' % len(grades))
    return {
        'student_id': USERNAME,
        'total': len(grades),
        'grades': grades,
    }


if __name__ == '__main__':
    result = main()
    print(json.dumps(result, ensure_ascii=False))

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

