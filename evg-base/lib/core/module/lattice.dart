/// 六格契约（contract lattice）——插件运行时信任等级。
///
/// # [Lattice] —— 六格枚举
///
/// | wire 值（连字符） | [Lattice]（小驼峰） |
/// |---|---|
/// | `static-web` | [Lattice.staticWeb] |
/// | `web-bridged` | [Lattice.webBridged] |
/// | `data-source` | [Lattice.dataSource] |
/// | `sidecar` | [Lattice.sidecar] |
/// | `agent-tool` | [Lattice.agentTool] |
/// | `external-app` | [Lattice.externalApp] |
///
/// 解析规则：
/// - 大小写不敏感；连字符 `-` 与下划线 `_` 等价（`web_bridged` == `web-bridged`）。
/// - 缺失 → 由 [inferLattice] 按信号推断（见 §2.4）。
/// - 存在但非法 → 抛 [FormatException]（fail-closed：安全相关字段不静默降级为高权限格）。
///
/// 设计上游：`evg-base/docs/m0-lattice-contract-design.md`。
library;

/// 六格运行时契约等级（从最安全到最外置）。
enum Lattice {
  /// 纯静态 HTML/CSS/JS，无 bridge，零权限。
  staticWeb,

  /// HTML + JS Bridge，按 capability 开票。
  webBridged,

  /// 数据源声明（`orch://`），由 DataHttpServer 服务。
  dataSource,

  /// 独立语言运行时进程（Node/Python/Deno），RPC + 能力沙箱。
  sidecar,

  /// Agent 工具声明，PluginBridge / skill 激活。
  agentTool,

  /// 外部应用，深链，不内嵌。
  externalApp,
}

/// wire 值（连字符）↔ [Lattice] 映射表。
const Map<Lattice, String> _latticeWire = {
  Lattice.staticWeb: 'static-web',
  Lattice.webBridged: 'web-bridged',
  Lattice.dataSource: 'data-source',
  Lattice.sidecar: 'sidecar',
  Lattice.agentTool: 'agent-tool',
  Lattice.externalApp: 'external-app',
};

/// 解析 wire 值为 [Lattice]。
///
/// 接受连字符或下划线形式，大小写不敏感。非法值抛 [FormatException]（fail-closed）。
Lattice parseLattice(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  for (final entry in _latticeWire.entries) {
    if (entry.value == normalized) return entry.key;
  }
  throw FormatException(
      '非法的 lattice 值 "$value"：必须是 ${_latticeWire.values.join(' / ')} 之一');
}

/// [Lattice] → wire 值（连字符形式）。
String formatLattice(Lattice lattice) => _latticeWire[lattice]!;

/// 缺省 lattice 推断信号源（[inferLattice] 使用）。
///
/// 与 [ModuleDescriptor] 的现有字段对应。为避免在纯契约模块反向依赖重描述符，
/// 这里用一个轻量数据持有类传递信号，[inferLattice] 据此推断。
class LatticeSignals {
  /// 是否声明了 `runtime`（→ 推断 sidecar，最高优先级）。
  final bool hasRuntime;

  /// `template` 字段值（如 `'html'` / `'scraper'`）。
  final String? template;

  /// 是否声明了 `dataSource` 或 `dataSources`。
  final bool hasDataSource;

  /// `activateSkills` 是否非空。
  final bool hasActivateSkills;

  /// 是否纯 v4 声明式页面（无上述任何信号）。
  final bool isPlainV4;

  const LatticeSignals({
    this.hasRuntime = false,
    this.template,
    this.hasDataSource = false,
    this.hasActivateSkills = false,
    this.isPlainV4 = false,
  });
}

/// 按 §2.4 优先级表推断缺省 lattice。
///
/// 优先级（高→低）：
/// 1. `runtime` 存在 → [Lattice.sidecar]
/// 2. `template == 'html'` → [Lattice.webBridged]
/// 3. `template == 'scraper'` → [Lattice.dataSource]
/// 4. `dataSource` / `dataSources` 存在 → [Lattice.dataSource]
/// 5. `activateSkills` 非空 → [Lattice.agentTool]
/// 6. 其它（v4 及内置声明式模板）→ [Lattice.staticWeb]（最安全兜底）
Lattice inferLattice(LatticeSignals s) {
  if (s.hasRuntime) return Lattice.sidecar;
  final t = s.template;
  if (t == 'html') return Lattice.webBridged;
  if (t == 'scraper') return Lattice.dataSource;
  if (s.hasDataSource) return Lattice.dataSource;
  if (s.hasActivateSkills) return Lattice.agentTool;
  return Lattice.staticWeb;
}
