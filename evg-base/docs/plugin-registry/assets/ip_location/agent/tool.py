#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""IP 地理位置查询（纯标准库，真实在线查询）。

流程：校验 IP 合法性（ipaddress）→ 依次尝试公开查询 API：
  1) ip-api.com（HTTP，免证书，免 key）
  2) ipinfo.io（HTTPS，免 key 配额）
网络不可达 / 超时 / API 返回失败 → 结构化 {"error": ...} + 非零退出（不伪造数据）。
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
import json
import ipaddress
import urllib.request

TIMEOUT = 5  # 秒，单次请求；总耗时 <= ~10s < Agent 30s 超时

def _fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'evergreen-agent-tool/1.0'})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode('utf-8'))

def _query_ip_api(ip):
    url = 'http://ip-api.com/json/%s?lang=zh-CN&fields=status,message,country,regionName,city,isp,org,as,lat,lon,timezone,query' % ip
    data = _fetch(url)
    if data.get('status') != 'success':
        raise RuntimeError(data.get('message') or 'ip-api.com 查询失败')
    return {
        'ip': ip,
        'country': data.get('country'),
        'region': data.get('regionName'),
        'city': data.get('city'),
        'isp': data.get('isp'),
        'org': data.get('org'),
        'as': data.get('as'),
        'lat': data.get('lat'),
        'lon': data.get('lon'),
        'timezone': data.get('timezone'),
        'source': 'ip-api.com',
    }

def _query_ipinfo(ip):
    url = 'https://ipinfo.io/%s/json' % ip
    data = _fetch(url)
    if 'error' in data:
        raise RuntimeError(data['error'].get('message') or 'ipinfo.io 查询失败')
    loc = data.get('loc', '').split(',')
    lat = float(loc[0]) if len(loc) == 2 else None
    lon = float(loc[1]) if len(loc) == 2 else None
    return {
        'ip': ip,
        'country': data.get('country'),
        'region': data.get('region'),
        'city': data.get('city'),
        'isp': None,
        'org': data.get('org'),
        'as': None,
        'lat': lat,
        'lon': lon,
        'timezone': data.get('timezone'),
        'source': 'ipinfo.io',
    }

def main():
    raw = sys.stdin.read()
    if not raw.strip():
        print(json.dumps({'error': '缺少参数 JSON'}, ensure_ascii=False))
        return
    try:
        args = json.loads(raw)
    except Exception as e:
        print(json.dumps({'error': '参数不是合法 JSON: %s' % e}, ensure_ascii=False))
        return
    if not isinstance(args, dict):
        print(json.dumps({'error': '参数必须是 JSON 对象'}, ensure_ascii=False))
        return
    ip = (args.get('ip') or '').strip()
    if not ip:
        print(json.dumps({'error': 'ip 必填'}, ensure_ascii=False))
        return
    try:
        ipaddress.ip_address(ip)  # IPv4/IPv6 校验；非法地址报错而非伪造
    except ValueError:
        print(json.dumps({'error': '非法 IP 地址: %s' % ip}, ensure_ascii=False))
        return
    last_err = None
    for fn in (_query_ip_api, _query_ipinfo):
        try:
            out = fn(ip)
            print(json.dumps(out, ensure_ascii=False))
            return
        except Exception as e:
            last_err = e
    # 两个 API 均失败（网络不可达 / 超时 / 服务端错误）→ 结构化错误 + 非零退出
    print(json.dumps({'error': 'IP 查询失败（网络不可达或服务不可用）: %s' % last_err, 'ip': ip}, ensure_ascii=False))
    sys.exit(1)

if __name__ == '__main__':
    main()
