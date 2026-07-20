// slot 版工作区导航回归测试（纯 Dart，不 pump 任何 widget，不会挂）。
//
// 背景：AI 助手以 slot 形式嵌入宿主模块（如 showcase-v4）时，ChatControllerView 的
// widget.descriptor.id 是宿主模块 id（showcase-v4），而非 'ai-assistant'。Agent 工具
// 把工作区文件写到 greenixWorkspaceDir('ai-assistant')，UI 抽屉若用宿主 id 扫描会命中
// 空目录——表现为"似乎没有文件"（见 test/feedback/20260715_075749_showcase-v4_🐛_Bug）。
//
// 本测试锁定契约：UI 读取端统一使用 [aiAssistantWorkspaceModuleId]，与 Agent 写入端
// 指向同一 greenix 工作区目录，且绝不等于宿主模块 id。
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/interaction/chat/chat_controller_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI 助手 slot 工作区导航', () {
    test('UI 读取端工作区 id 恒为 ai-assistant', () {
      expect(aiAssistantWorkspaceModuleId, equals('ai-assistant'));
    });

    test('UI 读取路径与 Agent 写入路径一致（greenixWorkspaceDir 唯一真相）', () {
      expect(
        greenixWorkspaceDir(aiAssistantWorkspaceModuleId),
        equals(greenixWorkspaceDir('ai-assistant')),
      );
    });

    test('UI 不会误用宿主模块 id（如 showcase-v4）扫描工作区', () {
      const hostModuleId = 'showcase-v4';
      expect(aiAssistantWorkspaceModuleId, isNot(equals(hostModuleId)));
      expect(
        greenixWorkspaceDir(aiAssistantWorkspaceModuleId),
        isNot(equals(greenixWorkspaceDir(hostModuleId))),
      );
    });
  });
}
