/// Evidence 系统 — 工具调用证据分类账本。
///
/// 对应 reasonix/internal/evidence/。
/// 记录每个工具调用的事实收据，供 complete_step 验证。
library;

/// 一条工具调用收据。
class Receipt {
  /// 工具名称。
  final String toolName;

  /// 工具参数（JSON 字符串）。
  final String arguments;

  /// 是否成功。
  final bool success;

  /// 执行的命令（仅 bash 类工具）。
  final String? command;

  /// 关联的步骤 ID。
  final String? step;

  /// 影响的文件路径。
  final List<String> paths;

  /// 是否为读操作。
  final bool read;

  /// 是否为写操作。
  final bool write;

  /// 执行结果。
  final String? output;

  const Receipt({
    required this.toolName,
    this.arguments = '{}',
    this.success = true,
    this.command,
    this.step,
    this.paths = const [],
    this.read = false,
    this.write = false,
    this.output,
  });
}

/// 证据分类账本——存储当前回合的所有工具收据。
///
/// 对应 Go 的 evidence.Ledger。
class Ledger {
  final List<Receipt> _receipts = [];

  /// 添加一条收据。
  void add(Receipt receipt) {
    _receipts.add(receipt);
  }

  /// 清空（新回合开始时调用）。
  void reset() {
    _receipts.clear();
  }

  /// 所有收据。
  List<Receipt> get all => List.unmodifiable(_receipts);

  /// 是否有任何写操作。
  bool get hasWrites => _receipts.any((r) => r.write);

  /// 是否有任何读操作。
  bool get hasReads => _receipts.any((r) => r.read);

  /// 是否包含特定工具名的收据。
  bool hasTool(String name) => _receipts.any((r) => r.toolName == name);

  /// 按工具名筛选收据。
  List<Receipt> byTool(String name) =>
      _receipts.where((r) => r.toolName == name).toList();

  /// 按步骤 ID 筛选收据。
  List<Receipt> byStep(String step) =>
      _receipts.where((r) => r.step == step).toList();

  /// 最后一次写操作收据。
  Receipt? get lastWrite {
    for (var i = _receipts.length - 1; i >= 0; i--) {
      if (_receipts[i].write) return _receipts[i];
    }
    return null;
  }

  /// 收据数量。
  int get count => _receipts.length;

  /// 验证步骤是否已执行。
  /// 用于 complete_step 工具。
  bool verifyStepExecuted(String step) {
    return _receipts.any((r) => r.step == step && r.success);
  }
}

/// 可读性审计结果。
class ReadinessAudit {
  final bool passed;
  final String reason;
  final int blockCount;

  const ReadinessAudit({
    required this.passed,
    this.reason = '',
    this.blockCount = 0,
  });

  factory ReadinessAudit.pass() => const ReadinessAudit(passed: true);
  factory ReadinessAudit.block(String reason, {int blocks = 1}) =>
      ReadinessAudit(passed: false, reason: reason, blockCount: blocks);
}
