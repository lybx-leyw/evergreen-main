# -*- coding: utf-8 -*-
"""evg_lib — Evergreen 平台 Python 库（随解释器分发的平台级共享代码）。

把「单 python 从账号到数据」端到端链路中每个数据插件重复复制的部分收敛为
平台级共享库，插件可 `import evg_lib` 复用（零影响存量插件：存量插件已内联
等价实现，`import evg_lib` 失败时可 `try/except ImportError` 优雅降级）。

子模块：
  - evg_lib.config : `_get_config(key)` 三级降级（config.json → ConfigHttpServer → env）
  - evg_lib.cas    : `cas_login(session, username, password)` + `_rsa_encrypt`
                     （ZJU CAS + RSA no-padding；依赖 requests）
  - evg_lib.jsonio : stdout JSON 输出契约（`emit` / `fail` / `validate_and_output`）

零新第三方依赖：config / jsonio 仅用标准库；cas 额外用 requests（平台嵌入式
Python 已内置）。

分发：本目录随 `scripts/` 镜像为 flutter 资产（`assets/scripts_bundle/evg_lib/`），
运行期释放到 `.greenix/scripts/evg_lib/`；平台在启动 Python 子进程时把
`.greenix/scripts/` 注入 `PYTHONPATH`，使 `import evg_lib` 无需拷贝即可用。
"""

from evg_lib.config import _get_config  # noqa: F401

__all__ = ['_get_config']

# 可选模块：jsonio 仅标准库，始终可导入；cas 依赖 requests，导入失败时不阻断
# `import evg_lib`（避免 evg_lib 顶层 import 因缺 requests 而整体失败）。
try:
    from evg_lib import jsonio  # noqa: F401
    __all__ += ['jsonio']
except Exception:  # pragma: no cover - 标准库，理论不会失败
    pass

try:
    from evg_lib import cas  # noqa: F401
    __all__ += ['cas']
except Exception:  # requests 缺失等场景：不阻断 config/jsonio 可用
    pass
