import os, ssl, urllib.request
from library_data import _cas_login, _SSL_CONTEXT

ip = _cas_login()
print("IPLANET_LEN", len(ip) if ip else 0)

def try_url(url, timeout=20):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json,*/*", "Cookie": "iPlanetDirectoryPro=" + ip, "Connection": "close"})
        r = urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
        txt = r.read().decode("utf-8", "ignore")
        return ("OK", len(txt), txt[:160].replace("\n", " "))
    except urllib.error.HTTPError as e:
        return ("HTTP%d" % e.code, 0, "")
    except Exception as e:
        return ("ERR", 0, str(e)[:60])

# 1) 连通性：根域名
print("ROOT https:", try_url("https://api.lib.zju.edu.cn/"))
print("ROOT http :", try_url("http://api.lib.zju.edu.cn/"))
# 2) 常见 ZJU 图书馆相关端点
for c in [
    "https://www.lib.zju.edu.cn/reader/book_lst.php",
    "https://api.lib.zju.edu.cn/aleph/bor-info?CON_LNG=chi&library=ZJU50",
    "https://api.lib.zju.edu.cn/aleph/bor-info",
    "https://findlib.lib.zju.edu.cn/",
    "https://webpac.zju.edu.cn/",
    "https://opac.lib.zju.edu.cn/",
]:
    print(c, "->", try_url(c))
