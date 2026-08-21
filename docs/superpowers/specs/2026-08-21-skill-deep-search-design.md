# Skill 创作中心 A 阶段：深度搜索协议升级

## 范围

第一阶段只支持现有 DeepSeek 与 OpenAI-compatible Provider。未配置 API Key 或未接入 Provider 时，界面必须明确提示需要接入，不得伪装成搜索失败。

## 方案

- 保留现有 DeepSearchRunner 和 SkillCreatorOrchestrator，新增协议适配与结构化证据层。
- 统一工具名为 `web_search`、`web_fetch`、`download_file`、`pdf_extract_text`、`ocr_file`，提示词与 whitelist 必须使用同一名称。
- 深寻结果保留现有 `DeepSearchResult` 兼容接口，同时为材料增加来源 URL、抓取时间、原文片段、引用 ID、可信度和去重指纹。
- Provider 能力不足、未配置或工具调用失败时返回可识别的连接状态与重试信息；不自动接入其他服务。

## 验收

- DeepSeek/OpenAI-compatible 配置有效时能完成搜索、网页获取和结构化材料输出。
- 未配置时 UI 显示明确接入提示。
- Tool 名称不再出现 `fetch_url`/`web_fetch` 不一致。
- 搜索失败、空结果、Provider 不支持工具调用均有可读错误和可重试状态。

