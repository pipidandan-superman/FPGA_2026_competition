---
name: eng-pitfall-ledger
description: Development pitfall sedimentation ledger. Whenever a build fails, sim hangs, board misbehaves, or a toolchain/env trap is confirmed - first grep this ledger for a same-type entry before improvising a debug path; after resolving, backfill a new entry in the mandated format. Use whenever debugging failures, before Vivado/board/toolchain operations, or when a defect root cause is confirmed.
---

# 开发易错点沉淀台账（Eng Pitfall Ledger）

目的：**同一个坑不踩第二次**。所有开发过程中踩过的错误 + 根因 + 解决方案沉淀为台账条目；排查任何异常前第一步是检索本台账。

## 台账实体位置

- 主台账：`references/pitfalls.md`（本 skill 目录下）。
- 条目按 **领域分区**（vivado-bd / vivado-build / vivado-sim / rtl / board / toolchain / env-path），区内按日期倒序。

## 排查纪律（先查后走）

1. 遇到失败/挂死/异常，**第一反应** = Grep 本台账 `references/pitfalls.md` 的关键词（错误码、现象、工具名），而不是直接重试或临场推导。
2. 命中同型条目 → 按该条目的「检测门/修复」执行，并在条目「复发计数」+1（回填日期）。
3. 3–5 轮解不开 → 停等审核（升级规则），把已试路径写进会话，不要硬凿。

## 新条目格式（解决后必须回填）

```markdown
### [YYYY-MM-DD] <领域>: <一句话缺陷>
- 症状: <观测到的行为 vs 预期，含关键错误码/指纹>
- 根因: <真正的底层原因，不是表象>
- 修复: <实际生效的动作>
- 检测门: <下次如何在砸片上板前抓住它（脚本门/检查命令/指纹）>
- 预防规则: <一句话律条，写进 CLAUDE 决策路径>
- 复发: 0
```

要求：
- 根因必须到**底层机制**（例：不写「wrapper 是旧的」，写「module_ref 接口缓存 .xci 是权威源，改 RTL 不刷新它」）。
- 检测门必须可执行（命令/正则/门脚本），不许写「仔细检查」。
- 复发一次就在原条目更新「复发 + 日期」并强化检测门，**不建新条目**。
- 变体例外（审计 2026-10-22 旁注）：同族缺陷的**注入路径/机制面实质不同**（如使用点 `$signed()` vs 声明层 `reg signed`）允许建独立变体条目，但必须双向互链、原条目复发计数照常 +1；机制面无实质差异的复发一律并回原条目。
- 与具体工程/IP 强绑定的细节（地址、批次名）放 run 证据层，台账只记机制级内容。

## 同步律

skill 有多个副本（`6_skill/eng-pitfall-ledger/` 主副本 + `~/.claude/skills/eng-pitfall-ledger/` 运行副本），任何改动必须**同批**同步全部副本并用 SHA256 逐对校验（certutil 正典），在会话报告中报 SHA 对账结果。工程镜像 `E:\competition\1_docs\eng_pitfall_ledger.md` 随提交时点同步（设计如此，非实时）。
**正典纪律（b6 R50 裁定）**：新条目**先落 1_docs（repo 持久正典）**再同批同步各 skill 副本；1_docs 与各副本必须保持并集一致，禁「skill 副本领先、1_docs 落后」的反向漂移（10-23 已两次实案）；引号形态正典=直双引号 `""。
