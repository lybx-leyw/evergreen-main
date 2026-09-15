#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""文件型数据源示例：发现 → 落盘（F1 去重）→ 返回 files[] 清单。

契约：`docs/plugin-registry/file-data-plugin-protocol-v1.md` §5
方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §2.3

两种输出形态（同一 `files[]` 数组，由是否含 `path` 区分）：
  - 含 `path`  → 已落盘，UI 直接「播放/打开」
  - 含 `url`   → 未下载，UI 列出并让用户**选择性下载**

本示例演示**第一种**（先下载再返回路径）——利用 `evg_lib.download` 的
内容寻址缓存，**同 HEAD 指纹绝不重下**（冷/热插件共享同一 file_cache）。
"""

import os
import sys

from evg_lib import download
from evg_lib.jsonio import emit


def arg(flag):
    """从 argv 取参数（桌面）。安卓另有 PROJECT_ROOT/GREENIX_CONFIG_PATH 环境变量。"""
    a = sys.argv
    for i, x in enumerate(a):
        if x == flag and i + 1 < len(a):
            return a[i + 1]
    return None


# 平台调用参数：--type <typeArg> --project-root <root> --greenix-config <cfg>
which = arg('--type') or 'lecture_materials'
search_page = os.environ.get('LECTURE_MATERIALS_PAGE', '')

# ── 1) 发现：真实插件在此解析页面/接口，取出可下载文件 URL ──
#    本示例用环境变量注入，便于离线演示与独立测试。
urls = [u for u in search_page.split(',') if u.strip()]
if not urls:
    # 无 URL ⇒ 优雅降级（协议 §5.2），不报错
    emit({'status': 'missing', 'path': None, 'files': [],
          'reason': 'no_source_configured'})
    sys.exit(0)

# ── 2) 落盘：逐个 ensure()，命中缓存则毫秒返回（F1）──
files = []
failed = []
for u in urls:
    r = download.ensure(u, timeout=1800)
    if r.get('status') == 'ready':
        files.append({
            'path': r['path'],
            'size': r['size'],
            'mime': r.get('mime', ''),
        })
    else:
        failed.append({'url': u, 'error': r.get('error') or r.get('reason')})

# ── 3) 输出：部分成功也返回 ready（UI 列出可用项 + 失败原因）──
if files:
    emit({
        'status': 'ready',
        'files': files,
        if failed:
            'errors': failed,
    })
else:
    emit({
        'status': 'failed',
        'path': None,
        'files': [],
        'error': '；'.join(str(f.get('error')) for f in failed) or '全部下载失败',
    })
