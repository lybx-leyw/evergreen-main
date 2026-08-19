/// 多画板容器视图（Phase 2 · A21-A24 + Phase 5 · D3/D4 画板-数据源树状左栏）。
///
/// 布局：左侧竖排侧边栏（IDE 风格）+ 右侧当前画板工作区。
/// - 每个画板 = 独立 [ScraperGeneratorView] 实例（独立 WebView/会话/快照，任务绝不交叉）
/// - 画板元数据持久化到 [BoardStore]（重启恢复 A24）
/// - D3：左栏支持「画板 / 数据源」双视图；画板节点下缩进显示绑定数据源
///   （manifest.boardId / boundBoardId 命中画板 id）；无画板的数据源归入「未绑定数据源」
/// - D4：数据源视图点击 → 弹真实 JSON → 已有画板直接切换 / 无画板确认建立
///   （建板 = capture 模式 + 拷贝 source/ + 写 workflow.json / resume_prompt.txt /
///    bound_sources.json + 回写 manifest boundBoardId）
library board_container_view;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/providers.dart';

import 'scraper_board.dart';
import 'data_source_binding.dart';
import '../view/scraper_generator_view.dart';

/// 侧边栏视图模式（D3）。
enum _SidebarView { boards, sources }

/// 多画板容器。
///
/// Phase 4：改为 [ConsumerStatefulWidget]，数据源弹窗「拉取示例」需要读
/// `dataOrchestratorProvider` 获取真实数据。
class BoardContainerView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor config;
  final String slotKey;
  final String projectRoot;
  final String workspaceDir;
  final String? initialUrl;

  const BoardContainerView({
    super.key,
    required this.descriptor,
    required this.config,
    required this.slotKey,
    required this.projectRoot,
    required this.workspaceDir,
    this.initialUrl,
  });

  @override
  ConsumerState<BoardContainerView> createState() => BoardContainerViewState();
}

class BoardContainerViewState extends ConsumerState<BoardContainerView> {
  late BoardStore _store;
  List<ScraperBoard> _boards = [];
  int _currentIdx = 0;

  /// D3：侧边栏视图（画板树 / 数据源）。
  _SidebarView _viewMode = _SidebarView.boards;

  /// D2/D3：扫描到的已注册数据源（建板/绑定后刷新）。
  List<DataSourceInfo> _dataSources = [];

  @override
  void initState() {
    super.initState();
    _store = BoardStore(workspaceDir: widget.workspaceDir);
    // 重启恢复（A24）+ 孤儿过滤：缓存里「没绑定会话的画板」不承认、不显示。
    // 双向绑定：画板 ↔ 会话。只有 loadBoardSessionIds 非空的画板才保留。
    final loaded = _store.load();
    _boards = loaded
        .where((b) => _store.loadBoardSessionIds(b.id).isNotEmpty)
        .toList();
    if (_boards.isEmpty) {
      // 首次：默认建一个画板（会话由 ScraperAIPanel initState 自动分配，
      // 落盘 <board>/session.json 后即满足双向绑定）。
      _boards = [ScraperBoard.create('画板 1')];
      _persist();
    }
    if (_currentIdx >= _boards.length) _currentIdx = 0;
    _dataSources = scanDataSourcePlugins();
  }

  void _persist() {
    _store.save(_boards);
  }

  /// 刷新数据源扫描（建板/删板/切视图后调用，反映最新 manifest 溯源状态）。
  void _refreshDataSources() {
    _dataSources = scanDataSourcePlugins();
  }

  void _selectBoard(int idx) {
    if (idx < 0 || idx >= _boards.length || idx == _currentIdx) return;
    setState(() => _currentIdx = idx);
  }

  void _addBoard() {
    // Phase 4（A23）：新建画板时选择模式（定向 / 探索）
    final nameCtrl = TextEditingController(text: '画板 ${_boards.length + 1}');
    var mode = ScraperBoardMode.capture;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建画板'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '画板名称'),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    _createBoard(ctx, v.trim(), mode);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('模式',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      )),
                  const SizedBox(width: 12),
                  SegmentedButton<ScraperBoardMode>(
                    segments: const [
                      ButtonSegment(
                        value: ScraperBoardMode.capture,
                        icon: Icon(Icons.radar_rounded, size: 14),
                        label: Text('定向抓取', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: ScraperBoardMode.explore,
                        icon: Icon(Icons.travel_explore_rounded, size: 14),
                        label: Text('AI 探索', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        setDialogState(() => mode = s.first),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = nameCtrl.text.trim();
                if (v.isNotEmpty) _createBoard(ctx, v, mode);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  void _createBoard(BuildContext ctx, String name, ScraperBoardMode mode) {
    final board = ScraperBoard.create(name, mode: mode);
    setState(() {
      _boards.add(board);
      _currentIdx = _boards.length - 1;
    });
    _persist();
    Navigator.pop(ctx);
  }

  /// 画板模式切换（Phase 4 · A23/D9：手动选择模式）。
  ///
  /// 模式变更会重建该画板工作区（两套工作流/harness 无法热切换），
  /// 先弹确认框防误触丢状态。
  Future<void> _toggleMode(int idx) async {
    final board = _boards[idx];
    final target = board.mode == ScraperBoardMode.capture
        ? ScraperBoardMode.explore
        : ScraperBoardMode.capture;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换画板模式？'),
        content: Text(
            '「${board.name}」将切换为${target == ScraperBoardMode.explore ? 'AI 探索' : '定向抓取'}模式。\n\n'
            '两种模式是不同的工作流与守卫约束，切换会重建该画板工作区'
            '（当前未提交的会话/日志状态将重置）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      board.mode = target;
      board.updatedAt = DateTime.now();
    });
    _persist();
  }

  void _removeBoard(int idx) {
    if (_boards.length <= 1) {
      // 至少保留一个画板
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个画板')),
      );
      return;
    }
    final board = _boards[idx];
    setState(() {
      _boards.removeAt(idx);
      if (_currentIdx >= _boards.length) _currentIdx = _boards.length - 1;
    });
    _store.deleteBoard(board.id); // 删除画板数据（含快照）
    _persist();
    // 删板后原绑定数据源可能变为未绑定 → 刷新
    _refreshDataSources();
  }

  void _renameBoard(int idx) {
    final board = _boards[idx];
    final ctrl = TextEditingController(text: board.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名画板'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '画板名称'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              setState(() {
                board.name = v.trim();
                board.updatedAt = DateTime.now();
              });
              _persist();
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) {
                setState(() {
                  board.name = v;
                  board.updatedAt = DateTime.now();
                });
                _persist();
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ═══════ D3 · 数据源交互 ═══════

  /// 绑定到指定画板的源。
  List<DataSourceInfo> _boundSourcesOf(String boardId) =>
      _dataSources.where((ds) => ds.boardId == boardId).toList();

  /// 未绑定数据源：无 boardId，或 boardId 找不到对应画板。
  List<DataSourceInfo> get _unboundSources => _dataSources
      .where((ds) =>
          ds.boardId == null || !_boards.any((b) => b.id == ds.boardId))
      .toList();

  String _createdByLabel(DataSourceInfo ds) => switch (ds.createdBy) {
        'scraper-explore' => '探索创建',
        'scraper-capture' => '定向创建',
        _ => '非爬虫',
      };

  /// D3/D4 数据源点击：先弹真实 JSON（SelectableText），
  /// 已有画板 → 直接切换；无画板 → 「建立画板？」确认后建板。
  Future<void> _handleDataSourceTap(DataSourceInfo ds) async {
    final boundBoardIdx = _boards.indexWhere((b) => b.id == ds.boardId);
    final hasBoard = boundBoardIdx >= 0;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ds.displayName),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              ds.truncatedJson(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'sample'),
            child: const Text('拉取示例'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          if (hasBoard)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'open'),
              child: const Text('打开画板'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'create'),
              child: const Text('建立画板'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'sample') {
      await _showDataSample(ds);
    } else if (action == 'open' && hasBoard) {
      setState(() {
        _viewMode = _SidebarView.boards;
        _currentIdx = boundBoardIdx;
      });
    } else if (action == 'create') {
      await _confirmAndCreateBoard(ds);
    }
  }

  /// Phase 4：拉取数据源真实数据示例并展示（非 manifest 死 JSON）。
  Future<void> _showDataSample(DataSourceInfo ds) async {
    String body;
    try {
      final orch = ref.read(dataOrchestratorProvider);
      if (orch.status(ds.name) == null) {
        body = '该数据源尚未热注册到数据中心（重启应用，或从画板重新注册后可用）。';
      } else {
        final data = await orch
            .get(DataType<Map<String, dynamic>>(name: ds.name));
        if (data == null) {
          final st = orch.status(ds.name);
          body = '拉取返回 null${st?.lastError != null ? ' · lastError: ${st!.lastError}' : ''}';
        } else {
          body = const JsonEncoder.withIndent('  ').convert(data);
          if (body.length > 4000) {
            body = '${body.substring(0, 4000)}\n…(截断)';
          }
        }
      }
    } catch (e) {
      body = '拉取失败: $e';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ds.displayName} · 数据示例'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndCreateBoard(DataSourceInfo ds) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('建立画板？'),
        content: Text(
            '为数据源「${ds.displayName}」建立画板（定向抓取模式）？\n\n'
            '画板将以现有脚本为起点进入调试模式：脚本/配置将拷贝到画板 '
            'source/ 目录并注入续作 prompt，原数据源插件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('建立'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _createBoardForDataSource(ds);
  }

  /// D4：为数据源建立画板并初始化调试工作区。
  ///
  /// a. 创建画板（capture 模式，名 = displayName）
  /// b. 拷贝 data/ 目录内容 + config/config.json → boards/<id>/source/
  /// c. 写 workflow.json（phase=debugging + pythonCode + dataName + pluginDir）
  /// d. 写 resume_prompt.txt（以现有脚本为起点调试，禁止重头演示抓包）
  /// e. 写 bound_sources.json（数据状态告知 AI）
  /// f. 回写 manifest boundBoardId（绑定≠创建，创建者字段不动）
  /// g. 选中新画板 + 刷新数据源
  Future<void> _createBoardForDataSource(DataSourceInfo ds) async {
    try {
      // a. 创建画板
      final board = ScraperBoard.create(ds.displayName,
          mode: ScraperBoardMode.capture);
      setState(() {
        _boards.add(board);
        _currentIdx = _boards.length - 1;
      });
      _persist();

      final boardDir = _store.boardDir(board.id);

      // b. 拷贝脚本/JSON 到 source/
      final sourceDir = p.join(boardDir, 'source');
      Directory(sourceDir).createSync(recursive: true);
      final srcDataDir = Directory(p.join(ds.pluginDir, 'data'));
      if (srcDataDir.existsSync()) {
        _copyDirSync(srcDataDir, Directory(p.join(sourceDir, 'data')));
      }
      final srcConfig = File(p.join(ds.pluginDir, 'config', 'config.json'));
      if (srcConfig.existsSync()) {
        final cfgDst = Directory(p.join(sourceDir, 'config'));
        cfgDst.createSync(recursive: true);
        srcConfig.copySync(p.join(cfgDst.path, 'config.json'));
      }

      // c. 写 workflow.json（调试态种子：GeneratorView 恢复后不再自动抓包）
      final scriptName = ds.rawManifest['script'] as String? ?? 'scraper.py';
      final scriptFile = File(p.join(ds.pluginDir, 'data', scriptName));
      final pythonCode = scriptFile.existsSync()
          ? scriptFile.readAsStringSync()
          : '';
      File(p.join(boardDir, 'workflow.json')).writeAsStringSync(jsonEncode({
        'workflow': {
          'phase': 'debugging',
          'pythonCode': pythonCode,
        },
        'dataName': ds.name,
        'pluginDir': ds.pluginDir,
      }));

      // d. 写 resume_prompt.txt
      final resumePrompt = '''
你是 Evergreen 爬虫调试 Agent。本画板已从现有数据源插件载入调试工作区。
插件目录: ${ds.pluginDir}
画板目录: $boardDir

## 当前任务
直接以现有脚本为起点调试，**禁止重头演示抓包流程**。

1. 先读取画板目录下 source/manifest.json 与 source/scraper.py，做一致性检查
   （manifest 声明的 dataTypes / script 与实际脚本是否匹配）。
2. 用 run_terminal_command 执行/调试脚本（必要时先 \`cd $boardDir/source\`），
   修复错误直到能产出与 manifest 一致的合法 JSON。
3. 调试通过后调用 export_and_register_scraper 完成注册（data_name 使用「${ds.name}」）。

## 约束
- 不要重新演示抓包/从头生成脚本——已有可用脚本，只需调试与注册。
- 修改脚本后保持 manifest 同步；输出字段与 manifest 一致。
''';
      File(p.join(boardDir, 'resume_prompt.txt'))
          .writeAsStringSync(resumePrompt);

      // e. 写 bound_sources.json
      File(p.join(boardDir, 'bound_sources.json'))
          .writeAsStringSync(jsonEncode([ds.toSummaryJson()]));

      // f. 回写 manifest boundBoardId（绑定≠创建，创建者字段不动）
      final manifestFile =
          File(p.join(ds.pluginDir, 'data', 'manifest.json'));
      if (manifestFile.existsSync()) {
        final manifest =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        manifest['boundBoardId'] = board.id;
        manifestFile.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(manifest));
      }

      // g. 切到画板视图并选中新画板 + 刷新数据源
      setState(() {
        _viewMode = _SidebarView.boards;
        _currentIdx = _boards.length - 1;
      });
      _refreshDataSources();
      _persist();
    } catch (e) {
      debugPrint('[BoardContainerView] ⚠ 为数据源建立画板失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('建立画板失败: $e')));
      }
    }
  }

  /// 递归复制目录。
  static void _copyDirSync(Directory src, Directory dst) {
    dst.createSync(recursive: true);
    for (final entity in src.listSync()) {
      if (entity is File) {
        entity.copySync(p.join(dst.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        _copyDirSync(entity, Directory(p.join(dst.path, p.basename(entity.path))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── 左侧侧边栏（画板树 / 数据源）──
        _buildSidebar(context),
        // ── 分割线 ──
        Container(width: 1, color: Theme.of(context).dividerColor),
        // ── 右侧：当前画板工作区（IndexedStack 保状态）──
        Expanded(
          child: IndexedStack(
            index: _currentIdx,
            children: [
              for (var i = 0; i < _boards.length; i++)
                ScraperGeneratorView(
                  // key 含 mode：切换模式重建画板工作区（两套 harness，D9）
                  key: ValueKey('board-${_boards[i].id}-${_boards[i].mode.name}'),
                  descriptor: widget.descriptor,
                  config: widget.config,
                  slotKey: widget.slotKey,
                  initialUrl: widget.initialUrl,
                  mode: _boards[i].mode,
                  boardId: _boards[i].id,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 左侧侧边栏（IDE 风格；D3 双视图）。
  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildSidebarHeader(context),
          Expanded(
            child: _viewMode == _SidebarView.boards
                ? _buildBoardTree(context)
                : _buildDataSourceList(context),
          ),
        ],
      ),
    );
  }

  /// 头部：画板 / 数据源 SegmentedButton + 新建画板按钮（D3.4）。
  Widget _buildSidebarHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_SidebarView>(
              segments: const [
                ButtonSegment(
                  value: _SidebarView.boards,
                  label: Text('画板', style: TextStyle(fontSize: 10.5)),
                ),
                ButtonSegment(
                  value: _SidebarView.sources,
                  label: Text('数据源', style: TextStyle(fontSize: 10.5)),
                ),
              ],
              selected: {_viewMode},
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10, vertical: 2)),
                textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 10.5)),
              ),
              onSelectionChanged: (s) {
                setState(() => _viewMode = s.first);
                if (s.first == _SidebarView.sources) _refreshDataSources();
              },
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 16),
            tooltip: '新建画板',
            onPressed: _addBoard,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// D3：画板树——画板节点下缩进显示绑定源；无画板的数据源归入「未绑定数据源」。
  Widget _buildBoardTree(BuildContext context) {
    final theme = Theme.of(context);
    final unbound = _unboundSources;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (var i = 0; i < _boards.length; i++) ...[
          _buildBoardTile(context, i),
          for (final ds in _boundSourcesOf(_boards[i].id))
            _buildBoundSourceTile(context, ds),
        ],
        if (unbound.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Text(
              '未绑定数据源 (${unbound.length})',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final ds in unbound) _buildUnboundSourceTile(context, ds),
        ],
      ],
    );
  }

  Widget _buildBoardTile(BuildContext context, int i) {
    final theme = Theme.of(context);
    final board = _boards[i];
    final active = i == _currentIdx;
    return InkWell(
      onTap: () => _selectBoard(i),
      onLongPress: () => _renameBoard(i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // 模式标识（点击切换模式，A23/D9）
            Tooltip(
              message: board.mode == ScraperBoardMode.explore
                  ? 'AI 探索模式（点击切换为定向抓取）'
                  : '定向抓取模式（点击切换为 AI 探索）',
              child: InkWell(
                onTap: () => _toggleMode(i),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    board.mode == ScraperBoardMode.explore
                        ? Icons.travel_explore_rounded
                        : Icons.radar_rounded,
                    size: 14,
                    color: board.mode == ScraperBoardMode.explore
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                board.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            // 绑定源计数
            if (_boundSourcesOf(board.id).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${_boundSourcesOf(board.id).length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            // 关闭按钮（悬停显示）
            if (_boards.length > 1)
              InkWell(
                onTap: () => _removeBoard(i),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 画板节点下缩进的绑定源子节点（点击 → 切到该画板）。
  Widget _buildBoundSourceTile(BuildContext context, DataSourceInfo ds) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        final idx = _boards.indexWhere((b) => b.id == ds.boardId);
        if (idx >= 0) _selectBoard(idx);
      },
      child: Container(
        margin: const EdgeInsets.only(left: 22, right: 6, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.link_rounded,
                size: 12, color: theme.colorScheme.tertiary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                ds.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (ds.category.isNotEmpty)
              Text(
                ds.category,
                style: TextStyle(
                  fontSize: 9.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 未绑定数据源子节点（点击 → JSON 弹窗 → 建立画板）。
  Widget _buildUnboundSourceTile(BuildContext context, DataSourceInfo ds) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _handleDataSourceTap(ds),
      child: Container(
        margin: const EdgeInsets.only(left: 22, right: 6, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.storage_rounded,
                size: 12, color: theme.colorScheme.outline),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                ds.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '未绑定',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D3.5：数据源视图——平铺全部已注册数据源，显示来源徽标与绑定状态。
  Widget _buildDataSourceList(BuildContext context) {
    final theme = Theme.of(context);
    if (_dataSources.isEmpty) {
      return Center(
        child: Text(
          '暂无数据源插件\n（plugins/data-*/data/manifest.json）',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _dataSources.length,
      itemBuilder: (ctx, i) => _buildDataSourceTile(ctx, _dataSources[i]),
    );
  }

  Widget _buildDataSourceTile(BuildContext context, DataSourceInfo ds) {
    final theme = Theme.of(context);
    final boardIdx = _boards.indexWhere((b) => b.id == ds.boardId);
    final hasBoard = boardIdx >= 0;
    final active = hasBoard && boardIdx == _currentIdx;
    return InkWell(
      onTap: () => _handleDataSourceTap(ds),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              ds.scraperMade
                  ? Icons.auto_awesome_rounded
                  : Icons.storage_rounded,
              size: 14,
              color: ds.scraperMade
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ds.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${_createdByLabel(ds)}'
                    '${ds.category.isNotEmpty ? ' · ${ds.category}' : ''}'
                    '${hasBoard ? ' · ${_boards[boardIdx].name}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!hasBoard)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '未绑定',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
