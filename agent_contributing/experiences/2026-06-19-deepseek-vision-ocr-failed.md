---
task_type: experiment
tags: [ocr, deepseek, huggingface, tesseract, ai]
difficulty: hard
outcome: abandoned
date: 2026-06-19
superseded_by: 本地 Tesseract OCR（`--psm 6` 纯文本模式）
---

## 尝试了什么

为 Evergreen 的 OCR 功能寻找云端高精度方案，依次尝试了两个路径：

1. **DeepSeek Chat Vision API** — 直接发送图片给 DeepSeek 的视觉模型做 OCR
2. **HuggingFace InferenceClient + DeepSeek-OCR-2** — 通过 HuggingFace 托管的 DeepSeek-OCR-2 模型做 OCR

## 为什么失败 / 为什么废弃

### DeepSeek Vision API
- **根本原因**：DeepSeek Chat API 的 `/chat/completions` 端点**不支持 `image` 类型的 content**。虽然部分文档暗示支持多模态，但实际 API（deepseek-chat / deepseek-reasoner）都是纯文本模型。
- **具体错误**：API 返回 `400 - Invalid content type: image_url`
- **尝试过的 workaround**：base64 编码图片 → 以文本形式传入 → 模型完全不理解图片内容

### HuggingFace DeepSeek-OCR-2
- **根本原因**：HuggingFace InferenceClient 需要 **HF Token** + 国内用户需要**镜像站点**才能访问
- **具体问题**：
  - 免费版 HuggingFace Inference API 队列时间长（> 30s）
  - Pro 版需要付费 Token
  - 国内直连 `api-inference.huggingface.co` 不稳定、频繁超时
  - 镜像配置复杂，且镜像站不一定托管了 DeepSeek-OCR-2 模型
- **性能**：即使在网络通畅时，一张 A4 页面的 OCR 耗时 8-15 秒，token 消耗约 2000-5000 tokens/页

## 发现的问题

| 方案 | 准确率 | 速度 | 成本 | 网络要求 |
|------|--------|------|------|---------|
| DeepSeek Vision API | N/A（不支持） | N/A | N/A | 需联网 |
| HuggingFace OCR-2 | 高（预期） | 慢（8-15s/页） | 中等 | 需 HF Token + 镜像 |
| Tesseract 本地 | 中 | 快（1-3s/页） | 免费 | 无 |

## 学到什么

1. **先验证 API 是否真的支持多模态，不要看文档推测** — DeepSeek 的 vision 能力只在特定端点可用，通用 chat 端点不行
2. **国内网络是硬约束** — 任何需要直连 HuggingFace 的方案都要先考虑镜像可行性
3. **云端 OCR 的延迟不适合交互式场景** — 用户期望秒级响应，8-15 秒太慢
4. **两级 OCR 策略是对的** — 云端做高精度、本地做快速兜底。但云端选型必须考虑国内网络可达性

## 最终采用了什么替代方案

**本地 Tesseract OCR** + 可选的 **DashScope DeepSeek-OCR API**（阿里云国内节点，延迟 < 3s）。

架构变为两级 pipeline：
- 优先：DashScope DeepSeek-OCR（云端高精度，国内可达）
- 降级：本地 Tesseract（`--psm 6` 纯文本模式，离线可用）

> ⚠️ 如果将来有人提议"试一下 xxx Vision API 做 OCR"，先看这条经验——大概率会遇到同样的问题。
