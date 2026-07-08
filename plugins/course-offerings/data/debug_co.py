"""临时调试：遍历多个学期/参数组合，定位有数据的开课查询。"""
import os
import sys
import json

sys.path.insert(0, os.path.dirname(__file__))
import course_offerings_data as C

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
with open(os.path.join(ROOT, ".env"), encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())
C._PROJECT_ROOT = ROOT

iplanet = C._cas_login()
print("[DBG] iplanet:", bool(iplanet), file=sys.stderr)
cj, op = C._zdbk_session(iplanet)

init_url = ("https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html"
           "?gnmkdm=N159035&layout=default")
try:
    C._zdbk_post(cj, op, init_url)
except Exception as e:
    print("[DBG] init err:", repr(e), file=sys.stderr)

sems = ["2025-2026-1", "2025-2026-2", "2024-2025-1", "2024-2025-2",
        "2026-2027-1", "2026-2027-2"]
for sem in sems:
    for cx in ["jxrw", "kch", "kcmc", ""]:
        q = ("?gnmkdm=N159035&doType=query"
             f"&tjksxq={sem}&tjjsxq={sem}&queryModel.showCount=10000")
        if cx:
            q += f"&cxType={cx}"
        url = ("https://zdbk.zju.edu.cn/jwglxt/jxzlpj/jszlpj_cxKkqkIndex.html" + q)
        try:
            html = C._zdbk_post(cj, op, url)
            obj = json.loads(html)
            tc = obj.get("totalCount", "?")
            n = len(obj.get("items", []) or [])
            if tc not in (0, "?", 0.0) or n:
                print(f"[HIT] sem={sem} cx={cx!r} totalCount={tc} items={n}", file=sys.stderr)
        except Exception as e:
            print(f"[ERR] sem={sem} cx={cx!r}: {e}", file=sys.stderr)
print("[DBG] scan done", file=sys.stderr)
