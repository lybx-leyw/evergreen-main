#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""浙大校车时刻 数据源适配壳（模型 A CLI，真实抓取）。

数据来源：浙江大学生活平台「班次查询」lightapp 的 shuttlebus 公开 REST API
（www.life.zju.edu.cn，免登录）。该接口为校内班车/校车班次的官方数据源，
页面入口：/_web/_apps/lightapp/busQuery/mobile/pc/pub/shiftManage.html。

接口（均为 GET，无鉴权）：
  /_web/_apps/lightapp/shuttlebus/station/api/lists.rst  站点列表
  /_web/_apps/lightapp/shuttlebus/bus/api/lists.rst      班车列表
  /_web/_apps/lightapp/shuttlebus/busflight/api/lists.rst 班次列表（核心）

契约（模型 A CLI）：
  - 参数：--type <typeArg> --project-root <root> --greenix-config <cfg>（空格分隔）
  - stdout 只输出纯 JSON（顶层 Map）；失败输出 {"error": "..."} 且 exit code 非 0
  - 凭证走 _get_config 三级降级（本数据源公开免登录，不强制需要凭证）
  - 纯 Python 标准库，双平台（Windows 桌面 / Android Chaquopy）兼容

可选配置（config.json / 环境变量，非必需）：
  - ZJU_BUS_API_BASE：API 基址覆盖（默认 http://www.life.zju.edu.cn/_web/_apps/lightapp/shuttlebus）
"""
import json
import os
import sys
import urllib.parse
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

DEFAULT_API_BASE = 'http://www.life.zju.edu.cn/_web/_apps/lightapp/shuttlebus'
QUERY_PAGE_URL = ('http://www.life.zju.edu.cn/_web/_apps/lightapp/busQuery/'
                  'mobile/pc/pub/shiftManage.html')
USER_AGENT = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36')
TIMEOUT_SECONDS = 15

_DAY_NAMES = {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'}


def _get_config(key, project_root=None, greenix_config=None):
    """三级降级读取配置（凭证/可选参数），返回字符串或 None。

    1. --greenix-config 指向的 config.json（或 GREENIX_CONFIG_PATH 环境变量）
    2. ConfigHttpServer（读 projectRoot/.config_port → http://127.0.0.1:PORT/config/settings/<key>）
    3. 系统环境变量 os.environ[key]
    """
    # Tier 1: config.json 文件
    cfg_path = greenix_config or os.environ.get('GREENIX_CONFIG_PATH')
    if cfg_path and os.path.exists(cfg_path):
        try:
            with open(cfg_path, 'r', encoding='utf-8') as f:
                val = json.load(f).get(key)
            if val is not None:
                return str(val)
        except Exception:
            pass
    # Tier 2: ConfigHttpServer（平台运行期服务）
    if project_root:
        port_file = os.path.join(project_root, '.config_port')
        if os.path.exists(port_file):
            try:
                with open(port_file, 'r', encoding='utf-8') as f:
                    port = f.read().strip()
                if port:
                    url = 'http://127.0.0.1:{}/config/settings/{}'.format(
                        port, urllib.parse.quote(key))
                    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
                    with urllib.request.urlopen(req, timeout=3) as r:
                        data = json.loads(r.read().decode('utf-8', 'replace'))
                    if isinstance(data, dict) and data.get(key) is not None:
                        return str(data[key])
            except Exception:
                pass
    # Tier 3: 环境变量
    val = os.environ.get(key)
    if val is not None:
        return val
    return None


def _http_get(url, timeout=TIMEOUT_SECONDS):
    """GET 请求，返回解码后的文本；异常向上抛（统一收敛为错误 JSON）。"""
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode('utf-8', 'replace')


def _api_json(base, path, params):
    """调用 shuttlebus REST 接口，返回 result.data（resultCode==0 时）。"""
    qs = urllib.parse.urlencode(params)
    text = _http_get('{}/{}?{}'.format(base, path, qs))
    try:
        payload = json.loads(text)
    except ValueError as e:
        raise RuntimeError('接口返回非 JSON（{}）：{}'.format(path, text[:120])) from e
    if not isinstance(payload, dict) or payload.get('resultCode') != 0:
        err = payload.get('errorMsg') if isinstance(payload, dict) else None
        raise RuntimeError('接口调用失败（{}）：{}'.format(path, err or text[:120]))
    result = payload.get('result')
    if not isinstance(result, dict):
        raise RuntimeError('接口返回结构异常（{}）'.format(path))
    return result.get('data')


def _fmt_time(raw):
    """'810' / '1100' → '08:10' / '11:00'；无法解析时原样返回。"""
    s = str(raw).strip()
    if not s:
        return ''
    if s.isdigit():
        s = s.zfill(4)
    if len(s) == 4 and s.isdigit():
        return '{}:{}'.format(s[:2], s[2:])
    return str(raw)


def _cycle_label(cycle):
    """运行周期码 → 中文可读标签。cycle 为逗号分隔的星期码（1=周一 … 7=周日）。"""
    if not cycle:
        return ''
    try:
        days = [int(x) for x in str(cycle).split(',') if str(x).strip()]
    except ValueError:
        return str(cycle)
    if not days:
        return ''
    if days == [1, 2, 3, 4, 5]:
        return '周一至周五'
    if days == [6, 7]:
        return '周六、周日'
    if days == [1, 2, 3, 4, 5, 6, 7]:
        return '每天'
    names = [_DAY_NAMES.get(d, str(d)) for d in days]
    return '、'.join(names)


def _normalize_shift(raw):
    """班次记录 → 输出 schema（时间规范化 + 周期标签）。"""
    return {
        'id': str(raw.get('id', '')),
        'busName': raw.get('busName', ''),
        'lineName': raw.get('lineName', ''),
        'startStationName': raw.get('startStationName', ''),
        'startTime': _fmt_time(raw.get('startTime')),
        'endStationName': raw.get('endStationName', ''),
        'endTime': _fmt_time(raw.get('endTime')),
        'cycle': str(raw.get('cycle', '')),
        'cycleLabel': _cycle_label(raw.get('cycle')),
        'remark': raw.get('remark', '') or '',
    }


def fetch_bus(type_arg, project_root=None, greenix_config=None):
    """抓取班车时刻 → 顶层 Map JSON。"""
    base = _get_config('ZJU_BUS_API_BASE', project_root, greenix_config) \
        or DEFAULT_API_BASE
    base = base.rstrip('/')

    # 1) 站点列表（供消费方做站点名映射/筛选）
    stations = _api_json(base, 'station/api/lists.rst',
                         {'state': 1, 'page': 0, 'rows': 99999})
    # 2) 班车列表（班车元信息/备注）
    buses = _api_json(base, 'bus/api/lists.rst',
                      {'state': 1, 'page': 0, 'rows': 99999})
    # 3) 班次列表（核心：全周期、全天时段）
    shifts = _api_json(base, 'busflight/api/lists.rst',
                       {'id': -1, 'startStationId': -1, 'endStationId': -1,
                        'zj': '1,2,3,4,5,6,7', 'startTime': '0000',
                        'endTime': '2359', 'page': 0, 'rows': 99999})

    items = [_normalize_shift(s) for s in shifts]
    items.sort(key=lambda x: (x['startTime'], x['busName'], x['startStationName']))

    def _brief(rows, name_key):
        return [{'id': str(r.get('id', '')), 'name': r.get(name_key, '')}
                for r in rows]

    return {
        'type': type_arg,
        'source': '浙江大学生活平台·班次查询（shuttlebus 公开 API）',
        'source_url': QUERY_PAGE_URL,
        'fetched_at': _now_iso(),
        'count': len(items),
        'items': items,
        'stations': _brief(stations, 'name'),
        'buses': _brief(buses, 'name'),
    }


def _now_iso():
    import datetime
    return datetime.datetime.now().isoformat(timespec='seconds')


def _parse_args(argv):
    """解析 --type/--project-root/--greenix-config（支持 '--k v' 与 '--k=v'）。"""
    args = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith('--') and '=' in arg:
            k, v = arg[2:].split('=', 1)
            args[k] = v
            i += 1
        elif arg.startswith('--') and i + 1 < len(argv):
            args[arg[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return args


def main():
    args = _parse_args(sys.argv[1:])
    type_arg = args.get('type') or 'zju_bus'
    project_root = args.get('project-root')
    greenix_config = args.get('greenix-config')
    try:
        result = fetch_bus(type_arg, project_root=project_root,
                           greenix_config=greenix_config)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error': '校车时刻获取失败：{}'.format(e)},
                         ensure_ascii=False))
        sys.exit(1)


if __name__ == '__main__':
    main()
