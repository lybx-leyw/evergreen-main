/// 文件型数据源 slot —— 把 `orch://<name>` 拉到的文件清单渲染成
/// **选择性下载列表**（[FileSourceList]）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §6 P2 接线。
///
/// 继承 [DataSourceSlot]，**免费获得**三步骤管道与优雅降级：
/// 归一化 → 字段映射 → 注入 `cfg[targetKey]`（默认 `'data'`）；
/// 拉取失败 / 返回 null 时保留静态 config，**绝不白屏**。
///
/// # 声明方式（插件 manifest 组件）
/// ```json
/// { "type": "file-source", "config": { "dataSource": { "endpoint": "orch://lecture_materials" } } }
/// ```
///
/// # 「打开」动作
/// 已落盘项经 [openLocalFile]（`url_launcher`）交给系统默认应用，跨平台
/// （Windows/macOS/Linux/Android Intent），无需自定义平台通道。
library;

import 'package:flutter/material.dart';

import 'package:evergreen_base/core/data/file_source_entries.dart';
import 'package:evergreen_base/core/services/data_file_service.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/file_opener.dart';
import 'package:evergreen_base/renderer/components/shared/file_source_list.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';

class FileSourceSlot extends DataSourceSlot {
  const FileSourceSlot({super.key, required super.config});

  @override
  DataSourceSlotState<FileSourceSlot> createState() => _FileSourceSlotState();
}

class _FileSourceSlotState extends DataSourceSlotState<FileSourceSlot> {
  /// 拉取到的 payload 落在 `cfg['data']`（[DataMapping] 默认 targetKey）。
  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final payload = cfg['data'] ?? cfg;
    final entries = parseFileSourceEntries(payload);

    // 落盘目标 = 内容寻址缓存目录，与 Python 侧 `evg_lib.download` 同一目录
    // （F1 跨冷热插件共享；见 file-data-plugin-protocol-v1.md §2）。
    final targetDir = greenixFileCacheDir;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: FileSourceList(
        entries: entries,
        service: DataFileService(sandboxRoot: targetDir),
        targetDir: targetDir,
        // 大文件：给足超时（避免默认 30s 杀掉下载）。理想应由
        // files[].timeoutSeconds 逐类型传递，但 slot 层拿不到该声明，取安全上限。
        timeout: const Duration(minutes: 30),
        emptyHint: '该数据源未返回可下载文件',
        // 已落盘项：交给系统默认应用打开（url_launcher，跨平台，无需平台分支）。
        onOpen: (e) async {
          final path = e.path;
          if (path == null || path.isEmpty) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          final r = await openLocalFile(path);
          r.fold(
            (_) => null,
            (err) => messenger?.showSnackBar(
              SnackBar(content: Text('打开失败：$err')),
            ),
          );
        },
      ),
    );
  }
}
