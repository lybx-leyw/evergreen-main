/// Greenix 运行时路径——数据目录管理。
///
/// 所有持久化数据统一放在 `.greenix/` 下，与 module/ 的 [WorkspaceDescriptor] 对应。
import 'dart:io';
import 'package:path/path.dart' as p;

/// Greenix 可写基础目录，默认为当前工作目录下的 `.greenix`。
String _greenixBaseDir = '.greenix';

/// 初始化 Greenix 路径——main() 启动时调用一次。
void initGreenixPaths() {
  _greenixBaseDir = p.join(Directory.current.path, '.greenix');
}

/// 记忆存储目录。
String get greenixMemoriesDir => p.join(_greenixBaseDir, 'memories');

/// Skill 文件目录。
String get greenixSkillsDir => p.join(_greenixBaseDir, 'skills');

/// 会话持久化目录。
String get greenixSessionsDir => p.join(_greenixBaseDir, 'sessions');

/// 嵌入式 Python 运行时目录（python.exe + site-packages）。
String get greenixPythonDir => p.join(_greenixBaseDir, 'python');

// ═══════ 文件工作区 ═══════

/// 工作区根目录——每个模块的文件工作区数据存于此。
String get greenixWorkspacesDir => p.join(_greenixBaseDir, 'workspaces');

/// 指定模块的工作区目录。id 为 [ModuleDescriptor.id]。
String greenixWorkspaceDir(String moduleId) =>
    p.join(greenixWorkspacesDir, moduleId);

/// 确保工作区目录存在。模块注册时调用一次。
void ensureWorkspaceDir(String moduleId) {
  final dir = Directory(greenixWorkspaceDir(moduleId));
  if (!dir.existsSync()) dir.createSync(recursive: true);
}

/// 列出工作区目录下的所有文件。
List<FileSystemEntity> listWorkspaceFiles(String moduleId) {
  final dir = Directory(greenixWorkspaceDir(moduleId));
  if (!dir.existsSync()) return [];
  return dir.listSync();
}
