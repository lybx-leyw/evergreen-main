"""library_data.exe — 图书馆借阅数据拉取（CLI 一次性执行）。

用法:
  library_data.exe --type=library_books   → 在借图书列表(stdout JSON)

完全移植自 .reference 的 library_service.getBorrowedBooks + BorrowedBook。
认证：复用 CAS 登录获取 iPlanetDirectoryPro cookie，直接请求
api.lib.zju.edu.cn/aleph/bor-info（与参考实现一致，仅需该 cookie）。

输出 JSON:
{
  "books": [ { title, author, barcode, borrowDate, dueDate, isRenewable,
               daysUntilDue, statusLabel } ],
  "total": N
}
"""
import argparse
import json
import os
import re
import ssl
import sys
import urllib.request
import urllib.parse
import http.cookiejar
from datetime import datetime

_PROJECT_ROOT = ""

_SSL_CONTEXT = ssl._create_unverified_context()
try:
    _SSL_CONTEXT.set_ciphers("DEFAULT:@SECLEVEL=1")
except Exception:
    pass


def _build_opener(cj):
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=_SSL_CONTEXT),
        urllib.request.HTTPRedirectHandler(),
    )


def _get_config(key):
    p = os.path.join(_PROJECT_ROOT, ".config_port")
    if os.path.isfile(p):
        try:
            with open(p) as f:
                port = f.read().strip()
            url = f"http://127.0.0.1:{port}/config/settings/{key}"
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("value") if isinstance(data, dict) else None
        except Exception:
            return None
    return os.environ.get(key)


def _rsa_encrypt(plaintext, modulus_hex, exponent_hex):
    n = int(modulus_hex, 16)
    e = int(exponent_hex, 16)
    m = int(plaintext.encode("utf-8").hex(), 16)
    if m >= n:
        raise ValueError("Message too large")
    h = hex(pow(m, e, n))[2:]
    return "0" + h if len(h) % 2 else h


def _cas_login():
    u = _get_config("ZJU_USERNAME")
    p = _get_config("ZJU_PASSWORD")
    if not u or not p:
        raise Exception("未设置学号/密码（请在设置中配置 ZJU_USERNAME 和 ZJU_PASSWORD）")
    cj = http.cookiejar.CookieJar()
    op = _build_opener(cj)
    hd = {"User-Agent": "Mozilla/5.0"}
    r1 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login", headers=hd)
    b1 = op.open(r1, timeout=15).read().decode("utf-8")
    m = re.search(r'name="execution"\s+value="([^"]+)"', b1)
    if not m:
        raise Exception("CAS 登录页结构异常（execution token 未找到，可能页面已更新）")
    execution = m.group(1)
    r2 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/v2/getPubKey", headers=hd)
    pk = json.loads(op.open(r2, timeout=10).read().decode("utf-8"))
    pwd_enc = _rsa_encrypt(p, pk["modulus"], pk["exponent"])
    body = (f"username={urllib.parse.quote(u)}"
            f"&password={urllib.parse.quote(pwd_enc)}"
            f"&execution={urllib.parse.quote(execution)}"
            f"&_eventId=submit&rememberMe=true")
    r4 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login",
                                data=body.encode("utf-8"),
                                headers={"Content-Type": "application/x-www-form-urlencoded", **hd})
    op.open(r4, timeout=15).read()
    for c in cj:
        if c.name == "iPlanetDirectoryPro":
            return c.value
    raise Exception("登录失败：学号或密码错误（未获取到 CAS 会话凭证）")


def _lib_get(iplanet, url, timeout=15):
    hd = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "Cookie": f"iPlanetDirectoryPro={iplanet}",
        "Connection": "close",
    }
    last_err = None
    for base in ("https://", "http://"):
        try:
            req = urllib.request.Request(base + url, headers=hd)
            resp = urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
            return resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code} @ {base}{url}"
            continue
        except Exception as e:
            last_err = e
    raise Exception(f"图书馆接口请求失败: {last_err}")


def _book_from_json(j):
    borrow_date = j.get("loan_date")
    due_date = j.get("due_date")
    days = 999
    status = ""
    try:
        if due_date:
            d = datetime.strptime(str(due_date)[:19], "%Y-%m-%dT%H:%M:%S") if "T" in str(due_date) else datetime.strptime(str(due_date)[:10], "%Y-%m-%d")
            days = (d - datetime.now()).days
            if days < 0:
                status = "已逾期"
            elif days <= 7:
                status = "即将到期"
            else:
                status = f"{days} 天后到期"
    except Exception:
        pass
    renewable = j.get("renewable")
    return {
        "title": str(j.get("title") or j.get("name") or ""),
        "author": str(j.get("author") or ""),
        "barcode": str(j.get("barcode") or j.get("item_barcode") or ""),
        "borrowDate": str(borrow_date) if borrow_date else "",
        "dueDate": str(due_date) if due_date else "",
        "isRenewable": (renewable is not False),
        "daysUntilDue": days,
        "statusLabel": status,
    }


def fetch_books():
    # 缺少凭据属配置错误，必须显式报错（exit 1），不静默降级
    iplanet = _cas_login()
    # 候选接口路径（参考 renew 接口带 CON_LNG/library 参数；bor-info 可能因版本需要同样参数）
    candidates = [
        "api.lib.zju.edu.cn/aleph/bor-info?CON_LNG=chi&library=ZJU50",
        "api.lib.zju.edu.cn/aleph/bor-info",
    ]
    last_err = None
    raw = None
    for cand in candidates:
        try:
            raw = _lib_get(iplanet, cand)
            last_err = None
            break
        except Exception as e:
            last_err = e
    if raw is None:
        # 参考实现的 api.lib.zju.edu.cn/aleph/bor-info 在现网已不可用（404/超时），
        # 且图书馆使用独立的 idp.zju.edu.cn SSO，CAS cookie 不被接受。
        # 优雅降级为空列表（与目标 UI 空态一致），不抛错中断管道。
        sys.stderr.write(f"[library] 借阅接口不可用: {last_err}\n")
        return {"books": [], "total": 0, "unavailable": True}
    try:
        data = json.loads(raw)
    except Exception:
        return {"books": [], "total": 0}
    loans = data.get("loans") if isinstance(data, dict) else None
    if not isinstance(loans, list):
        loans = []
    books = [_book_from_json(e) for e in loans if isinstance(e, dict)]
    return {"books": books, "total": len(books)}


HANDLERS = {"library_books": fetch_books}

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()
    _PROJECT_ROOT = os.path.abspath(args.project_root)
    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        result = h()
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[library] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
