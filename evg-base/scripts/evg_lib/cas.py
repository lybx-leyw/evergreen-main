# -*- coding: utf-8 -*-
"""evg_lib.cas — 浙江大学统一认证（CAS）登录工具。

适用域：浙江大学统一身份认证（https://zjuam.zju.edu.cn/cas），采用「RSA
no-padding」教科书式加密提交密码（`_rsa_encrypt`），覆盖浙大教务（zdbk）、
智云课堂（classroom）等所有走 zjuam CAS SSO 的业务系统。提取自
`docs/plugin-registry/examples/example-data-zju_grades/data/scraper.py` 与
`scraper_skill_const.dart` 的模板，保持登录流程语义一致。

用法（session 由调用方持有，便于跨请求复用 / 持久化 cookie）：
    import requests
    from evg_lib.cas import cas_login, _rsa_encrypt
    from evg_lib.config import _get_config

    session = requests.Session()
    final_url = cas_login(
        session,
        username=_get_config('ZJU_USERNAME'),
        password=_get_config('ZJU_PASSWORD'),
        service='https://zdbk.zju.edu.cn/jwglxt/xtgl/login_ssologin.html',
    )
    # 登录失败：final_url 仍停留在 /cas/login 且不含 ticket= 参数

依赖：requests（平台嵌入式 Python 已内置）。**无 requests 时 `import evg_lib.cas`
会抛 ImportError**，插件应 `try: from evg_lib.cas import cas_login
except ImportError: ...` 降级（存量插件已内联等价实现，零影响）。

零新第三方依赖：仅标准库 + requests。
"""

import re
import urllib.parse

import requests

CAS = 'https://zjuam.zju.edu.cn/cas'

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
}


def _rsa_encrypt(password, modulus_hex, exponent_hex):
    """ZJU CAS RSA 加密密码（教科书式 no-padding），密文补齐 modulus 位长。

    直接把密码字节按大端解释为整数 m，用 CAS 下发的公钥 (n, e) 做
    `c = m^e mod n`，再把密文格式化为与 n 位长相等的十六进制串（zfill 补齐）。
    与 `docs/plugin-registry/examples/.../scraper.py` 的 `_rsa_encrypt` 一致。
    """
    m = int.from_bytes(password.encode('utf-8'), 'big')
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    c = pow(m, e, n)
    hex_len = (n.bit_length() + 3) // 4
    return format(c, 'x').zfill(hex_len)


def _extract_hidden_inputs(html):
    """从 CAS 登录页提取所有 type="hidden" 输入（execution/lt 等）为表单字典。"""
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
    return form_data


def cas_login(session, username, password, service=None, cas=CAS, timeout=30):
    """浙大统一认证登录，返回登录后重定向的最终 URL。

    参数：
        session:  requests.Session（调用方持有，便于复用 / 持久化 cookie）
        username: CAS 用户名（学号 / 工号）
        password: CAS 明文密码（仅内存中 RSA 加密，不落盘）
        service:  登录后跳回的业务系统 service 地址；None 时仅登录 CAS 门户
        cas:      CAS 基地址（默认 https://zjuam.zju.edu.cn/cas）
        timeout:  单次 HTTP 请求超时（秒）

    返回：requests 跟随重定向后的最终 URL。若仍停留在 CAS 登录页
    （含 `/cas/login` 且无 `ticket=`），说明用户名/密码错误或需要验证码。

    与存量模板（zdbk 教务示例）的对应：存量示例先开教务登录页并调
    `login_cxSsoLoginUrl.html` 发现 SSO 跳转地址，失败时回退到
    `CAS + '/login?service=' + quote(SERVICE)`——本函数直接采用该回退路径作为
    通用入口，登录提交（hidden 字段 → getPubKey → RSA → POST）与模板一致。
    """
    # 1. 打开 CAS 登录页，提取 hidden 字段（execution 等）
    login_url = cas + '/login'
    if service:
        login_url += '?service=' + urllib.parse.quote(service, safe='')
    r = session.get(login_url, headers=HEADERS, timeout=timeout)
    form_data = _extract_hidden_inputs(r.text)

    # 2. 获取 RSA 公钥并加密密码
    r = session.get(cas + '/v2/getPubKey', headers=HEADERS, timeout=timeout)
    pub = r.json()
    enc_pwd = _rsa_encrypt(password, pub['modulus'], pub['exponent'])

    # 3. 提交登录表单
    form_data['username'] = username
    form_data['password'] = enc_pwd
    form_data.setdefault('authcode', '')
    form_data.setdefault('_eventId', 'submit')
    r = session.post(login_url, data=form_data, headers={
        **HEADERS,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': login_url,
    }, timeout=timeout, allow_redirects=True)
    return r.url
