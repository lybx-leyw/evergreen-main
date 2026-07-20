/// AI 改写提案 → Diff 转换器。
///
/// 将 AI 分析报告中的建议转化为具体的文本改写，
/// 生成原文与改写稿的 diff 对比。
library;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_document.dart';

/// AI Diff 提案器。
///
/// 接收 [TechAnalysisReport] 和原文，生成改写稿。
/// 改写策略：基于盲区补充和新思路，在原文中注入要点。
class AiDiffProposer {
  /// 根据分析报告生成改写稿。
  ///
  /// 改写策略：
  /// - 在文档末尾添加「技术调研附录」章节
  /// - 将盲区补充作为 ## 注意事项 注入
  /// - 将新思路作为 ## 可选方案 注入
  /// - 将可行性支撑作为 ## 技术参考 注入
  /// - 风险作为 ## ⚠️ 风险提醒 注入（仅确凿冲突时）
  static String proposeRevision(
    String originalContent,
    TechAnalysisReport report,
  ) {
    final buf = StringBuffer();

    // 保留原文
    buf.write(originalContent.trimRight());
    buf.writeln();
    buf.writeln();

    // ── 技术调研附录 ──
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 技术调研附录');
    buf.writeln();
    buf.writeln('> 由 AI 技术设计师自动生成，请逐条审阅后 Keep/Discard。');
    buf.writeln();

    // 盲区补充
    if (report.blindSpots.isNotEmpty) {
      buf.writeln('### 注意事项');
      buf.writeln();
      for (final item in report.blindSpots) {
        buf.writeln('- ⚠️ $item');
      }
      buf.writeln();
    }

    // 新思路
    if (report.newIdeas.isNotEmpty) {
      buf.writeln('### 可选方案');
      buf.writeln();
      for (final item in report.newIdeas) {
        buf.writeln('- 💡 $item');
      }
      buf.writeln();
    }

    // 可行性支撑
    if (report.evidence.isNotEmpty) {
      buf.writeln('### 技术参考');
      buf.writeln();
      for (final ev in report.evidence) {
        if (ev.url != null && ev.url!.isNotEmpty) {
          buf.writeln('- **${ev.source}**：${ev.content}（[来源](${ev.url})）');
        } else {
          buf.writeln('- **${ev.source}**：${ev.content}');
        }
      }
      buf.writeln();
    }

    // 风险（仅确凿冲突）
    if (report.risks.isNotEmpty) {
      buf.writeln('### ⚠️ 风险提醒');
      buf.writeln();
      for (final item in report.risks) {
        buf.writeln('- 🔴 $item');
      }
      buf.writeln();
    }

    buf.writeln('---');
    return buf.toString();
  }
}
