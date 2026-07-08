import os, ssl, json, urllib.request
envp = r"c:\Users\19389\Desktop\Evergreen-Multi-Tools\core\Win\evergreen-base - 副本\.env"
for line in open(envp, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

# 复用 library_data 中已验证可用的 CAS 登录
from library_data import _cas_login, _SSL_CONTEXT

ip = _cas_login()
print("IPLANET_LEN", len(ip) if ip else 0)
if not ip:
    print("CAS login failed")
    raise SystemExit(1)

cands = [
    "api.lib.zju.edu.cn/aleph/bor-info?CON_LNG=chi&library=ZJU50",
    "api.lib.zju.edu.cn/aleph/bor-info",
    "api.lib.zju.edu.cn/aleph/bor-info/",
    "api.lib.zju.edu.cn/rest/borrowed",
    "api.lib.zju.edu.cn/aleph/bor-row?CON_LNG=chi&library=ZJU50",
    "api.lib.zju.edu.cn/aleph/bor-info?CON_LNG=CHI&library=ZJU50",
]
for c in cands:
    try:
        req = urllib.request.Request("https://" + c, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json,*/*", "Cookie": "iPlanetDirectoryPro=" + ip, "Connection": "close"})
        r = urllib.request.urlopen(req, timeout=15, context=_SSL_CONTEXT)
        txt = r.read().decode("utf-8", "ignore")
        print("OK", c, "len", len(txt), "snip", txt[:140].replace("\n", " "))
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, c)
    except Exception as e:
        print("ERR", type(e).__name__, c, str(e)[:80])
