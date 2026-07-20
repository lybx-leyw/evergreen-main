/// AI 设计生成引擎 —— 自然语言 → 合法 [DesignDocument]。
///
/// 把"想法"转换为可被 A-P2 编译器（[DesignToManifest]）与 A-P3 运行闭环
/// （[ModuleDescriptor] / [ModuleRegistry]）消费的 [DesignDocument]。
///
/// 设计要点：
/// 1. 依赖抽象 [agent.Provider]（而非具体 [agent.DeepSeekProvider]），便于测试注入 fake。
/// 2. AI 输出 JSON 字段名严格对齐 [DesignDocument.fromJson]（见 [_buildSystemPrompt]）。
/// 3. 组件类型强制白名单约束（[ComponentRegistry.knownTypes]），越界 type 降级为未绑定占位。
/// 4. 三级降级：API 失败 / 非 JSON / 缺页面 → 统一抛 [AiGenerateException]，不崩溃设计器。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/component_picker.dart';

/// AI 生成失败异常 —— 统一承载各类降级错误，供渲染层展示友好提示。
class AiGenerateException implements Exception {
  /// 错误原因机器码（api_error / provider_error / empty_response /
  /// invalid_json / parse_error / no_pages）。
  final String reason;

  /// 人类可读信息。
  final String message;

  const AiGenerateException({required this.reason, required this.message});

  @override
  String toString() => 'AiGenerateException($reason): $message';
}

/// AI 设计生成器。
///
/// 用法：
/// ```dart
/// final provider = agent.DeepSeekProvider(dio: dio, apiKey: key);
/// final doc = await AiDesignGenerator(provider).generate('做一个课程表插件');
/// // 改稿模式：
/// final revised = await AiDesignGenerator(provider).generate('把首页改成网格', base: doc);
/// ```
class AiDesignGenerator {
  /// LLM 通道（抽象，便于测试注入 fake）。
  final agent.Provider provider;

  const AiDesignGenerator(this.provider);

  /// 数据类组件（其 [DesignComponent.config] 可能含 `dataSource`）。
  static const Set<String> _dataComponentTypes = {
    'data-dashboard',
    'data-table',
    'card-list',
    'chart',
    'stat-tile',
    'kanban',
    'tree',
    'timeline',
    'map',
    'calendar',
    'timetable',
  };

  /// 由自然语言 [prompt] 生成 [DesignDocument]。
  ///
  /// [base] 非空时进入"改稿模式"：把现有设计 JSON 一并喂给 AI，
  /// 要求其只改指定部分、返回完整新 JSON。
  /// [onToken] 可选，用于流式展示 AI 输出增量（[agent.ProviderEventKind.content]）。
  Future<DesignDocument> generate(
    String prompt, {
    DesignDocument? base,
    void Function(String delta)? onToken,
  }) async {
    final messages = [
      agent.Message.system(_buildSystemPrompt()),
      agent.Message.user(_buildUserPrompt(prompt, base: base)),
    ];

    final buf = StringBuffer();
    try {
      await for (final ev in provider.chat(messages: messages)) {
        if (ev.kind == agent.ProviderEventKind.content && ev.text != null) {
          buf.write(ev.text);
          onToken?.call(ev.text!);
        } else if (ev.kind == agent.ProviderEventKind.error) {
          throw AiGenerateException(
            reason: 'provider_error',
            message: ev.error ?? 'AI 服务返回错误',
          );
        }
      }
    } catch (e) {
      if (e is AiGenerateException) rethrow;
      throw AiGenerateException(
        reason: 'api_error',
        message: 'AI 调用失败: $e',
      );
    }

    final raw = buf.toString().trim();
    if (raw.isEmpty) {
      throw const AiGenerateException(
        reason: 'empty_response',
        message: 'AI 未返回任何内容，请重试',
      );
    }

    // 剥离 ```json ... ``` 代码块（AI 常包裹 markdown）
    String jsonText = raw;
    final codeMatch =
        RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(raw);
    if (codeMatch != null) {
      jsonText = codeMatch.group(1)!.trim();
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (e) {
      throw AiGenerateException(
        reason: 'invalid_json',
        message: 'AI 返回的不是合法 JSON: $e',
      );
    }

    DesignDocument doc;
    try {
      doc = DesignDocument.fromJson(map);
    } catch (e) {
      throw AiGenerateException(
        reason: 'parse_error',
        message: '设计文档解析失败（字段缺失或类型错误）: $e',
      );
    }

    // A2：组件白名单约束（越界 type 降级为未绑定占位）
    _enforceWhitelist(doc);

    // A3：缺页面视为失败（避免产出空壳 doc）
    if (doc.pages.isEmpty) {
      throw const AiGenerateException(
        reason: 'no_pages',
        message: 'AI 未生成任何页面',
      );
    }

    // D1：数据绑定轻校验（仅记录，不阻断）
    _validateDataBindings(doc);

    debugPrint(
      '[AiDesignGenerator] ✅ 生成成功: "${doc.pluginName}"'
      ' · ${doc.pages.length} 页 / ${doc.slotCount} Slot'
      '${base != null ? ' · 改稿模式' : ''}',
    );
    return doc;
  }

  /// A2：遍历所有 slot，将白名单外的组件 type 降级为未绑定（component = null）。
  void _enforceWhitelist(DesignDocument doc) {
    for (final page in doc.pages) {
      for (final slot in page.slots) {
        final comp = slot.component;
        if (comp == null) continue;
        if (!ComponentRegistry.isKnownType(comp.type)) {
          debugPrint(
            '[AiDesignGenerator] ⚠ 越界组件 type="${comp.type}"'
            ' (slot=${slot.id}) → 降级为未绑定占位',
          );
          slot.component = null;
        }
      }
    }
  }

  /// D1：扫描数据类组件，记录含合法 `dataSource`（[DataSourceDescriptor] 对象形态）的绑定数量。
  ///
  /// 与运行期契约对齐：`dataSource` 必须是对象且含非空 `endpoint`
  /// （推荐 `orch://<dataType>` 指向 A-P1 已注册数据源），见 [data_source_resolver.dart]。
  void _validateDataBindings(DesignDocument doc) {
    var count = 0;
    for (final page in doc.pages) {
      for (final slot in page.slots) {
        final comp = slot.component;
        if (comp != null && _dataComponentTypes.contains(comp.type)) {
          final ds = comp.config['dataSource'];
          if (ds is Map && ds['endpoint'] is String &&
              (ds['endpoint'] as String).isNotEmpty) {
            count++;
          }
        }
      }
    }
    if (count > 0) {
      debugPrint(
          '[AiDesignGenerator] 📊 生成了 $count 个数据绑定 (DataSourceDescriptor.endpoint)');
    }
  }

  // ── Prompt 构建 ──

  String _buildSystemPrompt() {
    final types = ComponentRegistry.knownTypes.toList()..sort();
    return '''
你是一个插件架构师，负责把用户的自然语言需求转换为一份**插件设计 JSON**。
这份 JSON 会被程序直接反序列化，因此你必须**严格**遵守下方字段名与结构，不得增删字段、不得改名。

## 顶层字段（key 必须完全一致）
- plugin_id: string，插件唯一标识，用小写中划线，如 "my-plugin"
- plugin_name: string，显示名称
- icon: string（可选），Material Icons 名称，如 "dashboard" / "school" / "psychology"
- description: string（可选），一句话描述
- route: string（可选），路由如 "/my-plugin"
- version: string（可选），默认 "1.0.0"
- dependencies: string[]（可选），依赖的模块 id 列表
- nav: object（可选）: { "section": string, "sectionOrder": int, "order": int, "badge": bool }
- process: object[]（可选）: [{ "exe": string, "protocol": string }]
- pages: array（必填，至少 1 个），页面列表

## pages[] 每个元素字段
- id: string，如 "page_0"
- label: string，页面标签
- layout_preset: string，取值只能是 fullscreen / grid / dock / flex（四选一）
- default: bool，是否为默认首页（建议恰有一个 true）
- hideTab: bool，是否隐藏 Tab 栏
- slots: array，该页面的槽位列表

## pages[].slots[] 每个元素字段
- id: string，如 "slot_0"
- label: string，槽位标签
- region: string，取值只能是 top / left / center / right / bottom（五选一）
- rect: number[]（可选），[x, y, w, h] 像素坐标，不填则使用默认
- component: object（可选，不绑定组件时省略）:
    - type: string，**必须**来自下方组件白名单
    - config: object，组件配置（字段名需符合该组件运行期期望；数据类组件用 "dataSource" 声明数据来源，见下方规则）

## 组件白名单（type 只能取以下之一）
${types.join(', ')}

## 规则
- 只输出 JSON（可放在 ```json 代码块内），不要输出任何解释性文字、前言或后缀。
- 组件 type 必须来自白名单；不确定时用 "custom" 或 "markdown"。
- 若需求涉及数据展示（数据仪表盘/数据表格/卡片列表/图表/日历/课表/看板/树/时间线/地图），在组件 config 中给出 **"dataSource" 对象**（与运行期 DataSourceDescriptor 契约一致）：
    "dataSource": { "endpoint": "orch://<dataType>" }
  其中 <dataType> 是与该数据对应的数据源标识（如 courses / scores / cards），指向已注册的数据源。
  **必须写成对象，不要写成字符串**；可附带 "dataPath"（JSONPath）与 "refreshInterval"（秒，0=不刷新）。
- 不要编造白名单外的组件类型。
''';
  }

  String _buildUserPrompt(String prompt, {DesignDocument? base}) {
    if (base != null) {
      final baseJson =
          const JsonEncoder.withIndent('  ').convert(base.toJson());
      return '''
请修改现有插件设计。**只按下面的修改指令改动指定部分，其余结构原样保留**，返回**完整**的新设计 JSON（字段规则同系统提示）。

## 现有设计（JSON）
$baseJson

## 修改指令
$prompt

只输出 JSON（可放在 ```json 代码块内），不要任何解释。
''';
    }
    return '''
请根据以下需求描述，生成一个完整的插件设计 JSON（字段规则见系统提示）。

## 需求描述
$prompt

只输出 JSON（可放在 ```json 代码块内），不要任何解释。
''';
  }
}
