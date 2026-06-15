/// 记忆的作用域——决定存储位置和生命周期。
///
/// ```
/// conversation  → 内存 Map（会话结束即丢弃）
/// feature       → Drift SQLite（App 运行期间持久）
/// global        → 文件系统 Markdown（永久）
/// ```
enum MemoryScope {
  conversation,
  feature,
  global,
}
