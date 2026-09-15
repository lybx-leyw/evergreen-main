# 示例：文件型数据源（`file-source`）

演示 `plugins/<id>/files/` 形态——**数据主体是文件**（而非业务 JSON）。

- 清单：`files/manifest.json`（`"type": "file-source"`）
- 脚本：`files/discover.py`
- 协议：`docs/plugin-registry/file-source-plugin-protocol-v1.md`（待补）
        + `file-data-plugin-protocol-v1.md`（输出契约）
- 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md`

安装到 `plugins/example-file-source/` 后，启动期由
`scanAndLoadFileSources()` 注册为 `orch://lecture_materials`。
