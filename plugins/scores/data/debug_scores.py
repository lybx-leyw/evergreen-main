"""临时调试脚本：复现 scores 拉取链路，打印每一步的 cookie 与错误信息。"""
import os
import sys
import http.cookiejar
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import scores_data as S

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
# 载入根目录 .env
with open(os.path.join(ROOT, ".env"), encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

S._PROJECT_ROOT = ROOT

iplanet = S._cas_login()
print("[DBG] iplanet captured:", bool(iplanet), file=sys.stderr)

cj, op = S._zdbk_session(iplanet)
print("[DBG] cookies after zdbk_session:",
      [(c.name, c.domain, c.path) for c in cj], file=sys.stderr)

url = ("https://zdbk.zju.edu.cn/jwglxt/cxdy/xscjcx_cxXscjIndex.html"
       "?doType=query&queryModel.showCount=5000")
try:
    html = S._zdbk_post(cj, op, url)
    print("[DBG] POST ok, len=", len(html), file=sys.stderr)
    print("[DBG] preview:", html[:400], file=sys.stderr)
except Exception as e:
    print("[DBG] POST err:", repr(e), "url=", getattr(e, "url", None), file=sys.stderr)
    try:
        body = e.read().decode("utf-8", "ignore")
        print("[DBG] body preview:", body[:600], file=sys.stderr)
    except Exception:
        pass
