"""quick_connect.exe — 数据状态/快速连接（本地服务连通性探测，无需联网）。

复刻参考：`.reference/.../features/connectivity/`（ConnectionManager.checkAll）
复刻目标：`.refer_ui/.../features/connectivity/`（汇总卡片 + 服务连通性列表 + 新鲜度列表）

实现（R6 换法复刻）：renderer 无后台探活 slot，本插件改为读取项目根目录下所有
端口文件（`.config_port` 与 `*.port`），对每个本地 HTTP 服务做健康检查（GET /），
返回 [{service, port, ok, elapsedMs, message}]，由 data-table 呈现连通性状态。
"""
import argparse
import glob
import json
import os
import sys
import time
import urllib.request
import urllib.error


_PROJECT_ROOT = ""


def _probe(port, timeout=2.0):
    url = f"http://127.0.0.1:{port}/"
    t0 = time.time()
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            elapsed = int((time.time() - t0) * 1000)
            return True, elapsed, f"HTTP {resp.status}"
    except urllib.error.HTTPError as e:
        elapsed = int((time.time() - t0) * 1000)
        # 能连上但返回非 2xx 也算服务存活（端口在监听）
        return True, elapsed, f"HTTP {e.code}"
    except Exception as e:
        elapsed = int((time.time() - t0) * 1000)
        return False, elapsed, str(e)


def fetch_connectivity():
    root = _PROJECT_ROOT
    files = [os.path.join(root, ".config_port")]
    files += glob.glob(os.path.join(root, "*.port"))
    results = []
    for f in files:
        if not os.path.isfile(f):
            continue
        name = os.path.basename(f)
        try:
            with open(f) as fh:
                port = fh.read().strip()
        except Exception:
            continue
        if not port.isdigit():
            continue
        ok, elapsed, msg = _probe(port)
        results.append({
            "service": name,
            "port": int(port),
            "ok": ok,
            "elapsedMs": elapsed,
            "message": msg,
        })
    connected = sum(1 for r in results if r["ok"])
    return {
        "services": results,
        "connectedCount": connected,
        "totalCount": len(results),
    }


HANDLERS = {"connectivity": fetch_connectivity}


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
        sys.stderr.write(f"[quick-connect] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
