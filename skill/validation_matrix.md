# 技能实际验证矩阵

这里记录交付目录中的具体技能与执行结果，不把文字说明的存在视为技能可用，也不把历史调用当作当前环境通过。

| 技能/入口 | 已执行的验证 | 边界与迁移要求 |
|---|---|---|
| zynq-pynq-overlay-workflow | EES-331 基线配对 BIT/HWH 热加载、41 个变化帧、两路停稳及恢复，现场 HDMI 确认；赛题旧位流另有变化输入推理 | 通用流程可迁移；脚本是固定 EES-331 profile，换板须重新建立恢复制品和合同 |
| overlay 异常生命周期 | 5 项主机故障注入：已停、复位后停、复位后未停、读失败、复位失败 | 失败分支持有进程及缓冲并阻止重载；软件控制流测试不替代真实硬件停止门 |
| overlay 恢复策略 | 捕获原服务 1 秒稳定等待造成的首帧失败；10 秒/30 秒副本恢复并现场确认 HDMI | 独立恢复成功不覆盖原失败；临时服务配置仅本次开机有效 |
| mineru-doc-reader | 最新技术报告与协作记录 pipeline 解析 PASS；Office 输出位于 `office/` 而非 `auto/` 的识别缺陷已修复 | 需要本地模型、MinerU、Python；哈希、非空 Markdown/JSON 和中文质量门缺一不可；auto/office 同时完整时拒绝 PASS |
| Vivado 构建入口 | 一B/三完整 BIT/XSA 重建通过；一A两版、二、AC1 真实 Vivado 工程验证通过；AC1 模块引用 XCI 已复核 | validate 不等于 BIT 通过；未约束 I/O、CDC 和时钟告警须另行分析 |
| OSD 仿真入口 | 当前包复跑：XSim 冒烟、COCO/姿态正向 PASS、历史字体错误负控被检出，总标记 `OSD_REGRESSION_PASS` | 只验证测试台覆盖的字体/框/标签/透传行为，不等于完整摄像头/HDMI 验收 |
| 形态二固定输入入口 | 脚本语法、相对路径、共享黄金资产和部署树通过 | 尚未实际板测；成功必须同时满足 21/21 平面比对与原服务恢复 |
| daily-engineering-log / engineering-organization | 本次工程与证据分目录留档 | 外部队伍必须配置自己的日志/证据根；本工程只用 `7_logs` 与 `4_metrics/logs` |
| key-action-audit | 独立审计发现实时输入门与 DMA 生命周期缺口，整改后故障注入复核 | 需要可用的独立审计者；其意见不是扩大操作权限的授权 |
| modelsim-local-sim | 本轮未执行 ModelSim | 本轮仿真使用 XSim，不能写成 ModelSim 技能验证通过 |
| claude-ross-delegation | 本轮未调用外部 ROSS | 历史记录只证明当时调用，不代表当前账号、服务或权限可用 |
| rtl-coding-standards / eng-pitfall-ledger | 本轮用于检查规则及失败回填 | 不是自动全 RTL 形式验证，也不替代 CDC/时序分析 |

最小复用流程：先读各 `SKILL.md` 的适用范围，配置工具/证据目录和板卡 profile，再运行最小冒烟。失败日志保留；只有预期标记、输入身份和运行证据一致才更新结论。

代表性复验命令见包根 `README.md` 与 `build/README.md`。精选原始证据见 `board/skill_validation/`。大模型提示词、回答及自我纠错历史见 `report/ai_collaboration_records_summary.md`。
