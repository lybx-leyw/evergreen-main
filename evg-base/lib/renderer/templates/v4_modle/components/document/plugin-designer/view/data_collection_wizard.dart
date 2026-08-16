/// 数据采集向导 —— 节点1四步向导 + 节点2三件套 + 节点3热注册检验。
///
/// 对标 规划A-可视化.html v5 节点1-3：
///   ① 引导页（简短说明 + 开始按钮，不填任何表单）
///   ② 嵌入 ScraperGeneratorView（零改动复用）
///   ③ 三件套生成（scraper.py + data/manifest.json + config/config.json）
///   ④ 热注册检验（registerDataSourcesFromManifest → 自动拉取验证）
///
/// 用法：
/// ```dart
/// DataCollectionWizard(
///   pluginsDir: resolvePluginsRoot(),
///   orch: dataOrchestrator,
///   projectRoot: projectRoot,
///   onCompleted: (result) { /* 全部完成 */ },
/// )
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/view/scraper_generator_view.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_exporter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/config_register.dart';
import 'package:evergreen_base/core/config/register_config.dart';
import 'package:evergreen_base/core/config/config_http_server.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 数据采集结果（节点 2 产出）
// ═══════════════════════════════════════════════════════════════════════════

/// 节点 2 三件套产出结果。
class DataCollectionResult {
  final String typeName;
  final String outputDir;
  final String? pyPath;
  final String? dataManifestPath;
  final String? configPath;
  final InferredSchema schema;
  final List<FileOutput> files;

  const DataCollectionResult({
    required this.typeName,
    required this.outputDir,
    this.pyPath,
    this.dataManifestPath,
    this.configPath,
    required this.schema,
    this.files = const [],
  });
}

/// 单个产出文件。
class FileOutput {
  final String path;
  final String label;
  final bool exists;

  const FileOutput({required this.path, required this.label, required this.exists});
}

// ═══════════════════════════════════════════════════════════════════════════
// 向导步骤枚举（三步）
// ═══════════════════════════════════════════════════════════════════════════

enum _WizardStep {
  intro('开始', Icons.play_circle_outline),
  scraper('抓包', Icons.wifi_find_rounded),
  generate('生成', Icons.auto_awesome),
  register('注册', Icons.cloud_done);

  final String label;
  final IconData icon;
  const _WizardStep(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════
// 数据采集向导
// ═══════════════════════════════════════════════════════════════════════════

/// 数据采集四步向导（节点1-3）。
class DataCollectionWizard extends StatefulWidget {
  final String? pluginsDir;
  final DataOrchestrator? orch;
  final ConfigHttpServer? configServer;
  final String? projectRoot;
  final void Function(DataCollectionResult result)? onCompleted;

  const DataCollectionWizard({
    super.key,
    this.pluginsDir,
    this.orch,
    this.configServer,
    this.projectRoot,
    this.onCompleted,
  });

  @override
  State<DataCollectionWizard> createState() => _DataCollectionWizardState();
}

class _DataCollectionWizardState extends State<DataCollectionWizard> {
  _WizardStep _currentStep = _WizardStep.intro;
  final List<_WizardStep> _completedSteps = [];

  /// Key to access the embedded ScraperGeneratorView's workflow.
  final _scraperKey = GlobalKey<ScraperGeneratorViewState>();

  // ── 步骤③ 生成状态 ──
  bool _generating = false;
  DataCollectionResult? _result;
  String? _generateError;
  String _generateStatus = '';

  // ── 步骤④ 注册检验状态 ──
  bool _registering = false;
  bool _registerDone = false;
  String? _registerError;
  String _registerStatus = '';
  List<String>? _registeredTypes;

  // ── 周期刷新：scraper workflow 不是 ChangeNotifier，wizard 定时拉取状态变化 ──
  Timer? _pollTimer;
  int _lastPhase = -1;
  String _lastCode = '';
  bool _lastPyExists = false;

  @override
  void initState() {
    super.initState();
    // 每 500ms 拉取一次 scraper workflow 状态，触发 wizard rebuild
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final wf = _scraperKey.currentState?.workflow;
      if (wf == null) return;
      final phase = wf.phase.index;
      final code = wf.pythonCode;
      final pyPath = p.join(greenixWorkspaceDir('__wizard_scraper__/scraper_output'), 'scraper.py');
      final pyExists = File(pyPath).existsSync();
      if (phase != _lastPhase || code != _lastCode || pyExists != _lastPyExists) {
        _lastPhase = phase;
        _lastCode = code;
        _lastPyExists = pyExists;
        setState(() {}); // 触发 wizard 重建，让 _step2Ready 重算
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 步骤导航 ──

  void _goNext() {
    final next = _WizardStep.values.firstWhere(
      (s) => s.index == _currentStep.index + 1,
      orElse: () => _currentStep,
    );
    if (next != _currentStep) {
      setState(() {
        if (!_completedSteps.contains(_currentStep)) {
          _completedSteps.add(_currentStep);
        }
        _currentStep = next;
      });
      if (next == _WizardStep.generate) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _generateAll());
      }
      if (next == _WizardStep.register) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _registerAndVerify());
      }
    }
  }

  void _goBack() {
    if (_currentStep.index > 0) {
      setState(() => _currentStep = _WizardStep.values[_currentStep.index - 1]);
    }
  }

  bool get _canGoNext {
    switch (_currentStep) {
      case _WizardStep.intro:
        return true;
      case _WizardStep.scraper:
        return _step2Ready;
      case _WizardStep.generate:
        return _result != null && !_generating;
      case _WizardStep.register:
        return false;
    }
  }

  bool get _canGoBack => _currentStep.index > 0;

  // ═════════════════════════════════════════════════════════════════════════
  // 步骤③：三件套生成（节点2）
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _generateAll() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _generateError = null;
      _generateStatus = '正在生成数据插件…';
    });

    try {
      final scraper = _scraperKey.currentState!;
      final workflow = scraper.workflow;
      final pythonCode = workflow.pythonCode;
      if (pythonCode.isEmpty) throw Exception('爬虫代码为空。请先在步骤②中完成 AI 生成。');

      // 推断 schema（从 logs + AI 面板的 facade）
      final facade = ScraperFlowFacade(workflow: workflow);
      final schema = await facade.analyzeSelection(workflow.logs);

      // 插件名：从 schema.title 推断，默认 "custom-scraper"
      final pluginName = (schema.title != null && schema.title!.isNotEmpty)
          ? schema.title!
          : 'custom-scraper';

      final pluginsDir = widget.pluginsDir ?? resolvePluginsRoot();
      final outputDir = p.join(pluginsDir, pluginName);
      final files = <FileOutput>[];

      // 确保 data/ 目录存在
      final dataDir = Directory(p.join(outputDir, 'data'));
      if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

      // ── 第 1 件：scraper.py（统一 .py 契约，不再编译 .exe）──
      _updateStatus('正在导出 scraper.py…');
      final pyResult = await exportAsPython(pythonCode, outputDir);
      String? pyPath;
      if (pyResult.success && pyResult.filePath != null) {
        pyPath = pyResult.filePath;
        // 复制到 data/ 对齐 register_data_source.dart 的 script 解析
        final dstPy = p.join(dataDir.path, 'scraper.py');
        try {
          File(pyResult.filePath!).copySync(dstPy);
          pyPath = dstPy;
          debugPrint('[DataCollectionWizard] 📋 scraper.py → data/');
        } catch (e) {
          debugPrint('[DataCollectionWizard] ⚠ 复制 scraper.py 到 data/ 失败: $e');
        }
        files.add(FileOutput(path: pyPath!, label: 'scraper.py (data/)', exists: true));
      }

      // ── 第 2 件：data/manifest.json ──
      _updateStatus('正在生成 data/manifest.json…');
      final dataPluginer = DataPluginer();
      final dataResult = await dataPluginer.registerDataPlugin(
        name: pluginName, outputDir: outputDir, schema: schema);
      String? dataManifestPath;
      if (dataResult.success && dataResult.manifestPath != null) {
        dataManifestPath = dataResult.manifestPath;
        files.add(FileOutput(path: dataManifestPath!, label: 'data/manifest.json', exists: true));
      }

      // ── 第 3 件：config/config.json（仅敏感字段时生成）──
      _updateStatus('正在分析配置字段…');
      final configRegister = ConfigRegister();
      final fieldMaps = schema.fields.map((f) => f.toJson()).toList();
      final configResult = await configRegister.generateConfig(
        pluginDir: outputDir, fields: fieldMaps);
      String? configPath;
      if (configResult.success && configResult.configPath != null) {
        configPath = configResult.configPath;
        files.add(FileOutput(path: configPath!, label: 'config/config.json', exists: true));
      } else {
        debugPrint('[DataCollectionWizard] ℹ 无敏感字段，跳过 config.json');
      }

      _updateStatus('生成完毕');

      final result = DataCollectionResult(
        typeName: pluginName,
        outputDir: outputDir,
        pyPath: pyPath,
        dataManifestPath: dataManifestPath,
        configPath: configPath,
        schema: schema,
        files: files,
      );

      setState(() { _result = result; _generating = false; });
      debugPrint('[DataCollectionWizard] ✅ 三件套生成完毕: $pluginName → $outputDir');
    } catch (e) {
      debugPrint('[DataCollectionWizard] ❌ 生成失败: $e');
      setState(() { _generating = false; _generateError = '生成失败: $e'; });
    }
  }

  void _updateStatus(String msg) {
    if (mounted) setState(() => _generateStatus = msg);
  }

  void _updateRegisterStatus(String msg) {
    if (mounted) setState(() => _registerStatus = msg);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 步骤④：热注册 + 自动检验（节点3）
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _registerAndVerify() async {
    if (_registering || _result == null) return;
    setState(() {
      _registering = true;
      _registerError = null;
      _registerStatus = '正在注册数据源…';
    });

    try {
      final result = _result!;
      final orch = widget.orch;
      if (orch == null) {
        setState(() {
          _registerError = 'DataOrchestrator 未注入，无法注册。';
          _registering = false;
        });
        return;
      }

      final projectRoot = widget.projectRoot ?? Directory.current.path;

      // ① 热注册
      _updateRegisterStatus('正在注册 orch://${result.typeName}…');
      final registered = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: result.outputDir,
        projectRoot: projectRoot,
        onlyType: result.typeName,
      );

      if (!registered.contains(result.typeName)) {
        setState(() {
          _registerError = '注册失败：${result.typeName} 未在 manifest 中找到或脚本不存在。';
          _registering = false;
        });
        return;
      }
      _registeredTypes = registered;
      debugPrint('[DataCollectionWizard] ✅ 节点3注册 orch://${result.typeName}');

      // ①b 热注册配置项到 ConfigHttpServer
      if (widget.configServer != null) {
        final configPath = p.join(result.outputDir, 'config', 'config.json');
        if (File(configPath).existsSync()) {
          _updateRegisterStatus('正在注册配置项…');
          final cfg = registerConfigFromManifest(
            configServer: widget.configServer!,
            pluginDir: result.outputDir,
          );
          if (cfg.count > 0) {
            debugPrint('[DataCollectionWizard] ✅ 配置项注册: ${cfg.count} 项');
            if (cfg.savedDefaults.isNotEmpty) {
              debugPrint('[DataCollectionWizard] 📋 配置项含默认值: ${cfg.savedDefaults.join(', ')}（需调用方通过 POST /config/settings 写入）');
            }
          }
        }
      }

      // ② 自动检验：通过 CLI fetcher 直接调用验证脚本能正常运行
      _updateRegisterStatus('正在检验数据脚本…');
      try {
        final scriptPath = p.join(result.outputDir, 'data',
            File(p.join(result.outputDir, 'data', 'scraper.exe')).existsSync()
                ? 'scraper.exe'
                : 'scraper.py');
        if (File(scriptPath).existsSync()) {
          final processResult = await Process.run(
            scriptPath,
            ['--type', result.typeName, '--project-root', projectRoot],
            workingDirectory: p.join(result.outputDir, 'data'),
          ).timeout(const Duration(seconds: 30));
          if (processResult.exitCode == 0) {
            final stdout = (processResult.stdout as String).trim();
            if (stdout.isNotEmpty) {
              _updateRegisterStatus('检验通过 ✅ — 脚本成功拉取到数据');
              debugPrint('[DataCollectionWizard] ✅ 检验通过: ${result.typeName}');
            } else {
              _updateRegisterStatus('检验警告 ⚠ — 脚本运行成功但返回空数据');
              debugPrint('[DataCollectionWizard] ⚠ 检验空数据: ${result.typeName}');
            }
          } else {
            _updateRegisterStatus('检验失败 ❌ — 脚本退出码 ${processResult.exitCode}');
            debugPrint('[DataCollectionWizard] ❌ 检验失败: ${result.typeName} code=${processResult.exitCode}');
          }
        } else {
          _updateRegisterStatus('检验跳过 — 脚本文件不存在: $scriptPath');
          debugPrint('[DataCollectionWizard] ⚠ 检验跳过: 脚本不存在 $scriptPath');
        }
      } catch (e) {
        _updateRegisterStatus('检验异常 — $e（注册已成功，可后续手动验证）');
        debugPrint('[DataCollectionWizard] ⚠ 检验异常: ${result.typeName} → $e');
        // 不阻断流程——注册已成功，脚本问题用户可后续排查
      }

      setState(() { _registerDone = true; _registering = false; });
    } catch (e) {
      debugPrint('[DataCollectionWizard] ❌ 注册异常: $e');
      setState(() {
        _registering = false;
        _registerError = '注册异常: $e';
      });
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 构建
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据采集向导'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildStepIndicator(),
        ),
      ),
      body: _buildStepContent(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _WizardStep.values.map((step) {
          final isActive = step == _currentStep;
          final isCompleted = _completedSteps.contains(step);
          final isClickable = isCompleted || step.index <= _currentStep.index;
          return Expanded(
            child: InkWell(
              onTap: isClickable ? () => setState(() => _currentStep = step) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCompleted ? Icons.check_circle : step.icon, size: 18,
                    color: isActive ? Theme.of(context).colorScheme.primary
                        : isCompleted ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 2),
                  Text(step.label, style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? Theme.of(context).colorScheme.primary
                        : isCompleted ? Colors.green.shade700 : Colors.grey,
                  )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStepContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_currentStep) {
        _WizardStep.intro => _buildStep1(key: const ValueKey('s1')),
        _WizardStep.scraper => _buildStep2(key: const ValueKey('s2')),
        _WizardStep.generate => _buildStep3(key: const ValueKey('s3')),
        _WizardStep.register => _buildStep4(key: const ValueKey('s4')),
      },
    );
  }

  // ═══════ 步骤①：引导页 ═══════

  Widget _buildStep1({Key? key}) {
    final theme = Theme.of(context);
    return Center(
      key: key,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(48),
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.wifi_find_rounded, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text('开始采集数据', style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                '接下来你将在浏览器中操作目标网站。\nCDP 后台自动截获全部 HTTP 请求与响应体。\nAI 会分析日志并自动生成爬虫代码。',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildInfoCard(theme, Icons.language, '输入目标网站地址',
                  '在下一步的浏览器地址栏中直接输入'),
              const SizedBox(height: 8),
              _buildInfoCard(theme, Icons.login, '登录并操作',
                  '正常登录、导航、触发需要抓取的 API'),
              const SizedBox(height: 8),
              _buildInfoCard(theme, Icons.auto_awesome, 'AI 自动生成',
                  '点击「分析日志」，AI 分析请求并生成爬虫代码'),
              const SizedBox(height: 8),
              _buildInfoCard(theme, Icons.terminal, '终端执行验证',
                  'AI 自动执行并调试爬虫，直到成功为止'),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _goNext,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('开始'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, IconData icon, String title, String desc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════ 步骤②：ScraperGeneratorView（零改动嵌入）═══════

  /// 检查步骤②是否完成：workflow.pythonCode 非空 且 工作区目录下存在 scraper.py。
  bool get _step2Ready {
    final scraper = _scraperKey.currentState;
    if (scraper == null) return false;
    final wf = scraper.workflow;
    // 不再依赖 wf.phase == ScraperPhase.done（因为 phase 转换依赖 AI 字符串匹配，易失败）
    if (wf.pythonCode.isEmpty) return false;
    // ScraperGeneratorView 用 descriptor.id 构造 workspaceDir:
    //   greenixWorkspaceDir('${moduleId}/scraper_output')
    // descriptor.id = '__wizard_scraper__'
    final workspacePath = greenixWorkspaceDir('__wizard_scraper__/scraper_output');
    final pyPath = p.join(workspacePath, 'scraper.py');
    return File(pyPath).existsSync();
  }

  Widget _buildStep2({Key? key}) {
    debugPrint('[DataCollectionWizard] 步骤② 嵌入 ScraperGeneratorView');

    const stubDescriptor = ModuleDescriptor(
      id: '__wizard_scraper__', name: 'Data Collection Wizard');
    const stubConfig = ComponentDescriptor(type: 'scraper-generator');

    final ready = _step2Ready;
    final scraper = _scraperKey.currentState;
    final phase = scraper?.workflow.phase;
    final hasCode = (scraper?.workflow.pythonCode ?? '').isNotEmpty;
    final pyExists = File(p.join(
        greenixWorkspaceDir('__wizard_scraper__/scraper_output'),
        'scraper.py')).existsSync();

    return Container(
      key: key,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // 顶部提示栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('在下方浏览器中登录并操作，AI 将自动分析生成爬虫',
                          style: TextStyle(fontSize: 12)),
                      if (phase != null)
                        Text(
                          '状态: ${_phaseLabel(phase)}'
                          '${hasCode ? " · 代码已生成" : ""}'
                          '${pyExists ? " · scraper.py ✓" : ""}',
                          style: TextStyle(
                            fontSize: 10,
                            color: ready ? Colors.green : Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!ready && (hasCode || pyExists)) ...[
                  // 兜底按钮：scraper.py 已生成但 phase 未转 done 时允许用户强制进入下一步
                  Tooltip(
                    message: 'scraper.py 已生成但 phase 未转 done，强制标记完成',
                    child: TextButton.icon(
                      onPressed: () {
                        scraper?.workflow.markDone();
                        // 主动触发状态更新（不依赖 _pollTimer）
                        setState(() {
                          _lastPhase = scraper!.workflow.phase.index;
                          _lastCode = scraper.workflow.pythonCode;
                          _lastPyExists = true;
                        });
                        // 强制刷新一次（计算 ready）
                        Future.microtask(() { if (mounted) setState(() {}); });
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 14),
                      label: const Text('标记完成', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                FilledButton.icon(
                  onPressed: ready ? _goNext : null,
                  icon: Icon(ready ? Icons.arrow_forward : Icons.hourglass_empty, size: 16),
                  label: Text(ready ? '下一步：生成三件套' : '等待 AI 完成并导出…'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // 完整 ScraperGeneratorView
          Expanded(
            child: ScraperGeneratorView(
              key: _scraperKey,
              descriptor: stubDescriptor,
              config: stubConfig,
              slotKey: 'wizard-capture',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════ 步骤③：三件套生成（节点2）═══════

  Widget _buildStep3({Key? key}) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: SizedBox(
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('一次性产出三件套',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('scraper.exe + data/manifest.json + config/config.json',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              if (_generating) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(_generateStatus, textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.primary)),
                const SizedBox(height: 24),
              ],
              if (_result != null) ...[
                _buildResultCard(theme),
                const SizedBox(height: 24),
              ],
              if (_generateError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.error, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_generateError!,
                        style: TextStyle(color: theme.colorScheme.error))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              if (!_generating && _result == null)
                FilledButton.icon(
                  onPressed: _generateAll,
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('开始生成'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                ),
              if (_result != null)
                FilledButton.icon(
                  onPressed: _goNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('下一步：注册检验'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final result = _result!;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text('生成完毕', style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            Text('数据源: orch://${result.typeName}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            const SizedBox(height: 8),
            Text('输出目录: ${result.outputDir}',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(height: 24),
            Text('产出文件 (${result.files.length}):', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            ...result.files.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(f.exists ? Icons.check_circle : Icons.cancel, size: 14,
                    color: f.exists ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(f.label,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                if (f.exists) Text('✓', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  // ═══════ 步骤④：热注册检验（节点3）═══════

  Widget _buildStep4({Key? key}) {
    final theme = Theme.of(context);
    final result = _result;
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: SizedBox(
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.cloud_done, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('注册并检验数据源',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('将 orch://${result?.typeName ?? '...'} 注册到 DataOrchestrator\n并自动拉取数据验证脚本可用性',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),

              // 进度
              if (_registering) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(_registerStatus, textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.primary)),
                const SizedBox(height: 24),
              ],

              // 完成状态
              if (_registerDone) ...[
                _buildRegisterResultCard(theme),
                const SizedBox(height: 24),
              ],

              // 错误
              if (_registerError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.error, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_registerError!,
                        style: TextStyle(color: theme.colorScheme.error))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              if (!_registering && !_registerDone && _registerError == null)
                FilledButton.icon(
                  onPressed: _registerAndVerify,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('开始注册检验'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                ),

              if (_registerDone)
                FilledButton.icon(
                  onPressed: () {
                    widget.onCompleted?.call(_result!);
                    Navigator.of(context).pop(_result);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('完成，返回设计器'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterResultCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_registerStatus.contains('✅') ? Icons.check_circle : Icons.warning_amber,
                  color: _registerStatus.contains('✅') ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(_registerStatus,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            if (_registeredTypes != null && _registeredTypes!.isNotEmpty) ...[
              Text('已注册类型:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              ..._registeredTypes!.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('  • orch://$t',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              )),
            ],
          ],
        ),
      ),
    );
  }

  // ── 底部导航栏 ──

  Widget _buildBottomBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_canGoBack)
              OutlinedButton.icon(
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('上一步'),
              ),
            const Spacer(),
            if (_currentStep != _WizardStep.generate) ...[
              Text('步骤 ${_currentStep.index + 1} / ${_WizardStep.values.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _canGoNext ? _goNext : null,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(_nextLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _phaseLabel(ScraperPhase p) => switch (p) {
    ScraperPhase.idle => '待机', ScraperPhase.capturing => '抓包中',
    ScraperPhase.analyzing => '分析中', ScraperPhase.questioning => '追问中',
    ScraperPhase.generating => '生成中', ScraperPhase.running => '运行中',
    ScraperPhase.debugging => '调试中', ScraperPhase.done => '✅ 完成',
    ScraperPhase.failed => '❌ 失败',
  };

  String get _nextLabel => switch (_currentStep) {
    _WizardStep.intro => '开始',
    _WizardStep.scraper => '下一步：生成',
    _WizardStep.generate => '下一步：注册',
    _WizardStep.register => '完成',
  };
}
