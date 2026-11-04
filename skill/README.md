# skill/ —— 技能包（大模型协作的方法沉淀）

本目录是工程两个月过程中，把"失败/观察 → 规则 → 验证 → 边界"沉淀为可复用
技能包的成果。技能以 SKILL.md 为主件（触发条件、步骤、**失效/停止条件**、证据
要求），部分带 references/ 与 scripts/。

## 分层与来源

工程内技能分三层维护：复用正典层（git 管理）→ 项目活动层（`.codex/skills/`，
项目路径覆盖）→ 会话层（`.claude/skills/`）。本目录收录其中的可迁移十件：

| 技能 | 一句话职责 | 提炼来源（代表性） |
|---|---|---|
| `zynq-pynq-overlay-workflow` | 现有 Linux/PYNQ 镜像上的 Overlay 部署、诊断与恢复 | 热加载、复位极性、DMA 所有权与首帧超时 |
| `vivado-ai-workflow` | Vivado 批处理构建/IP 排障铁律（先翻 PG/UG 逐引脚核对契约） | IP 使能/复位/极性类静默错误 |
| `claude-ross-delegation` | 官方 ROSS MCP 的受权调起、会话互斥与回退 | 10-03 ROSS 部署与 rtl-lint 实跑 |
| `eng-pitfall-ledger` | 工程坑账台账规范（现象/根因/修复律三段式） | 全工程 318 条实点 |
| `rtl-coding-standards` | RTL 编码红线（复位/跨时钟/阻塞赋值等） | 仿真与上板差异类缺陷 |
| `modelsim-local-sim` | 本地 ModelSim 批处理仿真与产物归位 | 字体/标签类 TB 三律案例 |
| `daily-engineering-log` | 每日四件套日志纪律 | 62 个活跃工程日的执行记录 |
| `engineering-organization` | 证据目录与归档纪律（run 目录/runNN 编号） | 1300+ run 目录的存档治理 |
| `key-action-audit` | 关键动作独立审计（呈批→复核→留档） | 多代理并行时的权限与事故防控 |
| `mineru-doc-reader` | 文档解析统一走本地 MinerU 管线（哈希复用） | 赛题/模版/论文多轮解析防漂移 |

**提炼方法**：每条规则必须能指回一次真实失败或观察（工程坑账 318 条为底座），
写明验证方式与**失效/停止条件**才准入技能；技能三副本（正典层/活动层/会话层）
SHA 齐一性作为变更纪律。边界：本目录技能含本工程路径示例（如 `E:\competition`、
本地工具路径），迁移到他机时需按各 SKILL.md 首节重定向路径；含本机私有配置的
技能（如上传凭据策略类）未收录。

与报告的对应：设计报告 3.4 节"大模型协作与技能包"给出协作机制全景
（三方制衡、技能三层、坑账制度）；ROSS 使用心得见 `report/amd_ross_reflections.md`。

## 本次执行验证与迁移

逐项状态见 [validation_matrix.md](validation_matrix.md)。本轮实测了 overlay、MinerU 与 Vivado/XSim 入口；没有调用 ModelSim 或 ROSS，不能把历史记录当作其当前可用性证明。

迁移时先配置工作区、日志根、工具安装路径、目标板卡和镜像；参考文件里的 EES-331 地址、哈希与时钟是 profile 数据。overlay 通用流程可复用，两个实测脚本会拒绝不匹配基线，换板须先建立自己的恢复制品与所有权/DMA 合同。该技能不用于任意 SD 重刷。

MinerU 的 PowerShell 入口支持 -WorkspaceRoot、-MineruExe、-MineruApiExe、-PythonExe，输出必须位于配置工作区的 4_metrics/logs 下。默认值属于本机配置，其他机器应显式提供。已修复 Office 结果目录识别；auto/office 同时出现或 JSON 无效时拒绝 PASS。

本目录是交付副本。工作区 `.codex` 活动技能的 MinerU Office 目录识别也已修复；两个副本的适用边界分别保留，发布前须复核其行为一致，不以文件存在代替实际解析验证。
