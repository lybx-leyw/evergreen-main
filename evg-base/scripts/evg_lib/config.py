# -*- coding: utf-8 -*-
"""evg_lib.config — 平台配置读取（三级降级）。

从锁定模板 `scraper_exporter.dart` 的 `scraperConfigTemplate` 提取，保持与
存量模板**行为一致**（含非空值保护等语义）。平台锁定：本文件由
`bundle_scripts.dart --check` 纯镜像门禁管理，AI/插件不可在插件侧改写。

三级降级：
  策略1（主）  ：`.greenix/config.json` 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 指定）
  策略2（降级）：HTTP 从 ConfigHttpServer 读取（`.config_port` 端口文件发现）
  策略3（兜底）：系统环境变量 `os.environ`

用法：
    from evg_lib.config import _get_config
    USERNAME = _get_config('ZJU_USERNAME')

存量插件兼容：存量 scraper.py 已内联 `_get_config`，本模块是「可选 import」的
共享实现；插件可用 `try: from evg_lib.config import _get_config
except ImportError: <内联 fallback>` 优雅降级。
"""

import json
import os
import urllib.request
import urllib.error
from pathlib import Path


def _get_config(key):
    """从平台配置读取凭证（三级降级）。

    策略1（主）：.greenix/config.json 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 环境变量指定）
    策略2（降级）：HTTP 从 ConfigHttpServer 读取
    策略3（兜底）：系统环境变量
    """
    # ── 策略1：.greenix/config.json 本地文件直接读取 ──
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            config_path = Path(greenix_path)
            if config_path.exists():
                with open(config_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass

    # ── 策略2：HTTP 从 ConfigHttpServer 读取 ──
    try:
        port_file = None
        for base in [Path.cwd(), Path(os.environ.get('PROJECT_ROOT', '.'))]:
            try:
                for d in [base] + list(base.parents):
                    pf = d / '.config_port'
                    if pf.exists():
                        port_file = pf
                        break
            except Exception:
                continue
            if port_file:
                break

        if port_file:
            with open(port_file, 'r') as f:
                port = f.read().strip()
            url = f'http://127.0.0.1:{port}/config/settings/{key}'
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                val = data.get('value', '')
                if val:
                    return val
    except Exception:
        pass

    # ── 策略3：系统环境变量 ──
    val = os.environ.get(key)
    if val:
        return val

    raise RuntimeError(
        f'无法获取配置 "{key}"：\n'
        f'  1. .greenix/config.json 不存在或无此 key\n'
        f'  2. ConfigHttpServer 不可用（检查 .config_port）\n'
        f'  3. 环境变量未设置\n'
        f'  → 请在设置面板注册此配置项，或设置环境变量 {key}'
    )
