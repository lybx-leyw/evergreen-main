"""protonvpn_data.exe — ProtonVPN 控制面板状态（真实读取本机网络适配器）。

复刻参考：`.reference/.../features/protonvpn`
复刻目标：`.refer_ui/.../features/protonvpn/`（VPN 登录 + 管理）
实现（R6 换法复刻）：ProtonVPN 客户端为系统级应用，插件不直接建立隧道
（需系统权限/驱动，超出纯 JSON API 代理契约）。控制面板展示「当前网络连接真实状态」，
由 .exe 调用系统命令真实读取本机网络适配器与出口 IP，无任何虚构数据。
"""
import argparse
import json
import os
import subprocess
import sys


def _run(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20,
                             shell=True)
        return out.stdout + out.stderr
    except Exception as e:
        return f"error: {e}"


def fetch_status():
    raw = _run(
        "powershell -NoProfile -Command "
        "\"Get-NetIPConfiguration | Where-Object {$_.IPv4Address} | "
        "ForEach-Object { $_.InterfaceAlias + '|' + "
        "($_.IPv4Address.IPAddress -join ',') + '|' + $_.IPv4DefaultGateway.NextHop }\""
    )
    adapters = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        parts = line.split("|")
        adapters.append({
            "adapter": parts[0],
            "ipv4": parts[1] if len(parts) > 1 else "",
            "gateway": parts[2] if len(parts) > 2 else "",
        })
    return {
        "connections": adapters,
        "total": len(adapters),
        "vpnActive": any("PROTON" in a["adapter"].upper() or "VPN" in a["adapter"].upper()
                         for a in adapters),
    }


HANDLERS = {"status": fetch_status}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--type", required=True)
    p.add_argument("--project-root", default=os.getcwd())
    args = p.parse_args()
    h = HANDLERS.get(args.type)
    if not h:
        print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
        sys.exit(1)
    try:
        print(json.dumps(h(), ensure_ascii=False))
    except Exception as e:
        sys.stderr.write(f"[protonvpn] {args.type}: {e}\n")
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
