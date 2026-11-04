# AMD ROSS 使用心得：从“会写代码”到“能够稳定走通流程”

使用 AMD ROSS 之后，我最明显的感受不是 AI 突然变得更会写 RTL，而是 **Vivado 的调用方式开始变得规范、稳定、可复核**。此前使用 Claude 或 ChatGPT（Codex）时，最常见的问题并不是完全没有设计思路，而是模型不熟悉真实工具链：该用工程模式时用了非工程模式，该检查输入和依赖时直接启动构建，该保留日志和状态时只留下一个“成功”的结论。结果常常出现“设计思路可能正确，但流程先把项目卡住”的情况。

ROSS 带来的最大改变，就是把自然语言任务接到真实的 Vivado 会话和结构化工具上。AI 不再只是生成一段看似合理的 Tcl，而是可以通过 MCP 执行命令、读取状态、检查日志并保留命令回放。对我而言，这种变化比单纯提高代码生成能力更有价值。

## 一、从“流程错误导致返工”到“按正确的流程推进”

原来的 Agent 很容易出现两类问题：一是把 Vivado 当成普通命令行程序，想到什么就先跑什么；二是忽略工程状态、输入制品和工具之间的约束，导致流程本身不成立。此时即使 RTL 设计方向正确，也会因为仿真环境、IP 依赖、文件路径或会话管理错误而停滞。

ROSS 的官方 Skill 与 MCP 会话机制把这些步骤组织起来：先明确会话和工作目录，再执行结构化操作，随后读取状态和日志，最后保存可回放的证据。它使我开始更多关注“这次操作是否属于正确的流程”，而不是只看“这段命令能不能运行”。

不过，ROSS 并没有消除流程约束。实际使用中仍需要注意重复命令的幂等去重、会话与项目归属、输入文件路径以及版本差异。相同字符串命令在短时间内可能返回前一次结果，因此重跑时必须显式区分轮次，不能因为界面显示成功就当作新结果。[daily](kimi-cite://md-line?path=E%3A%2Fcompetition%2F7_logs%2F2026-10-14%2Fdaily.md&line=78&text=MCP%20vivado_execute "citation")

## 二、最直观的提升：Vivado 仿真从繁琐配合变成顺畅执行

此前使用 Claude 或 ChatGPT（Codex）时，启动 Vivado 仿真经常需要很多额外配合。有时必须提前打开一个 Vivado GUI 界面，有时虽然会话能够建立，`launch_simulation` 仍然在编译子进程阶段失败。项目记录中的 `Common 17-180 Spawn failed` 就说明，问题并不一定是测试平台写错，而可能发生在仿真器调起方式上。[03_validation_summary](kimi-cite://md-line?path=E%3A%2Fcompetition%2F7_logs%2F2026-10-11%2F03_validation_summary.md&line=94&text=launch_simulation "citation")

使用 ROSS 后，最突出的体验是仿真流程明显顺畅了。通过 `vivado_execute` 按 `xvlog → xelab → xsim` 的顺序执行，不再依赖我预先打开 GUI，也不再把 `launch_simulation` 当作唯一入口。M9.1 Face B 最终完成 15 帧测试并出现 `TB_M91_LADDER_B_PASS`，M9.2 trace／engine 也分别通过，说明这条调用链不仅能启动仿真，还能支撑真实的分层验证。[03_validation_summary](kimi-cite://md-line?path=E%3A%2Fcompetition%2F7_logs%2F2026-10-11%2F03_validation_summary.md&line=102&text=xvlog "citation")

这次经历让我认识到，所谓“AI 仿真能力强”，首先不是它会写测试平台，而是它能不能正确调起真实工具、正确选择库和顶层、正确处理错误并留下终止标志。比如这次 XSim 还需要显式使用 `库名.顶层`，并链接真实的 BMG 与 unisim 行为模型；这些细节如果靠模型凭空猜，仍然可能失败。[STATUS](kimi-cite://md-line?path=E%3A%2Fcompetition%2F4_metrics%2Flogs%2F2026-10-11_m9_faceb_xsim3step_run01%2FSTATUS.md&line=22&text=%E6%9C%AC%20run%20%E8%B7%91%E6%B3%95 "citation")

## 三、IP 例化从“凭印象写端口”到“以 .veo 和实际配置为准”

原来的 AI 有时会凭记忆编写 IP 例化端口，名字、位宽或连接方式看似合理，却不一定与当前 IP 配置一致。这种问题在仿真和综合阶段非常隐蔽，排查成本也很高。

使用 ROSS 后，IP 相关操作明显更规范：可以围绕实际 IP 配置和生成文件开展，而不是自由发挥。项目中也一直要求从 `.veo` 逐端口核对，不能把模型记忆中的端口表当作事实。[06_run27_closeout](kimi-cite://md-line?path=E%3A%2Fcompetition%2F7_logs%2F2026-09-20%2F06_run27_closeout.md&line=47&text=.veo "citation")

至于是 ROSS 套件本身带来的规范，还是项目 Skill 起了决定作用，我目前不能简单归因。更合理的理解是：**官方 Skill 提供通用方法，项目 Skill 规定工程边界和验收规则，人工再通过 `.veo` 做最终核对。**三者是叠加关系，而不是互相替代。官方部署文档也明确提出，IP 配置结果仍须遵守项目的 `.veo` 核对铁律。[AMD_Ross_AgenticAI_部署与应用报告_2026-10-03](kimi-cite://md-line?path=E%3A%2Fcompetition%2F1_docs%2Fdoc%2FAMD_Ross_AgenticAI_%E9%83%A8%E7%BD%B2%E4%B8%8E%E5%BA%94%E7%94%A8%E6%8A%A5%E5%91%8A_2026-10-03.md&line=125&text=.veo "citation")

## 四、我为 ROSS 套件补充的工程化 Skill 规范

我并不是只安装了 ROSS 官方 Skill，还针对本工程的使用方式补充了专门的自定义规范。官方套件解决“有哪些能力可以调用”，我的 Skill 则进一步规定“在本工程中应当怎样安全、规范、可复现地调用”。

### 1. 调用授权与失败回退

明确规定只有在用户授权的场景下才能委派 Claude 执行任务；当 Claude 不可用、限流或未通过认证时，可以改用结构化 Vivado MCP 直接操作，但不能退回无约束的 Vivado／XSim 原始命令。MCP 未连接、会话归属不清或证据不完整时，应停止而不是盲目重试。[claude-ross-delegation](kimi-cite://md-line?path=E%3A%2Fcompetition%2F.claude%2Fskills%2Fclaude-ross-delegation%2FSKILL.md&line=12&text=Authorization "citation")

### 2. 会话互斥与工程归属

对 Vivado 会话、工作目录和修改权限进行约束，禁止不同任务并发修改同一工程、同一位流或同一证据目录，并避免 VS Code 扩展与独立 MCP 二进制重复启动服务。这样可以从流程上减少工程被交叉写入、状态互相覆盖的问题。

### 3. 固定证据目录与制品哈希

每次仿真、构建或审计都分配独立证据目录，保存控制台输出、脚本、日志、报告、输入哈希和结果标记。冻结工程默认只读，任何新输出都必须进入指定证据目录，而不是散落在工程根目录或覆盖原始制品。[claude-ross-delegation](kimi-cite://md-line?path=E%3A%2Fcompetition%2F.claude%2Fskills%2Fclaude-ross-delegation%2FSKILL.md&line=18&text=Preflight "citation")

### 4. 仿真与 IP 的操作正典

仿真不依赖预先打开 GUI，也不把 `launch_simulation` 当作唯一入口，而是根据实际场景采用 `xvlog → xelab → xsim` 的分段流程，检查库名、顶层、输入文件和终止标志。IP 例化必须以当前配置的 `.veo` 为核对依据，不能由模型凭记忆补写端口。针对重复命令，还增加了显式轮次变量，避免把缓存结果误当成新一轮执行。

### 5. 分层验收，禁止结果越级

把 `CLIENT_READY`、`MCP_CONNECTED`、`READ_ONLY_PASS`、`FLOW_PASS` 和 `BOARD_PASS` 分开管理：服务连接正常只代表工具可用，仿真启动成功只代表流程可走通，只有完成规定的输出对照才能形成对应级别的通过结论。任何一级都不得由前一级自动晋升。[claude-ross-delegation](kimi-cite://md-line?path=E%3A%2Fcompetition%2F.claude%2Fskills%2Fclaude-ross-delegation%2FSKILL.md&line=64&text=Safety "citation")

这些自定义规范使我能够把一次成功经验变成可重复的工作方式。ROSS 提供官方工具和通用方法，项目 Skill 再把授权、路径、证据、回退和验收固定下来；两者结合，才形成了适合本工程的完整使用流程。

## 五、其他实际收获

### 1. 错误能够更早暴露

过去很多问题要到仿真甚至综合后才暴露。结合 RTL lint 和 elaborate 分析后，可以在更早阶段排除语法、层次和基础结构问题。项目中的 `yolo_silu_lut` 已在 Vivado 2025.2 下完成 lint，结果为 0 error、0 warning、0 violation。这个案例不能证明所有设计都正确，但说明“先检查、再仿真”的流程是可执行的。[rtl_lint_report](kimi-cite://md-line?path=E%3A%2Fcompetition%2F11_AMD_Ross_AgenticAI%2Fevidence%2F2026-10-03_rtl-lint%2Frtl_lint_report.md&line=13&text=PASSED "citation")

### 2. 从依赖模型记忆转向查询官方资料

ROSS 的文档检索和官方 Skill 让我减少了对模型记忆的依赖。遇到工具命令、IP 配置或方法学问题时，更合理的做法是先查 AMD 官方资料，再决定操作，而不是让 AI 自行补全一个看似合理的答案。对于 Vivado 这种版本和配置都很敏感的工具，这一点尤其重要。

### 3. 验证结果更容易复核和复现

MCP 会话、命令回放、日志和结果文件使验证过程能够留下来。我可以在之后复查当时执行了什么、为什么通过、失败发生在哪一步，而不是只保留一张“仿真成功”的截图。项目中的 `READ_ONLY_PASS`、`FLOW_PASS` 和 `BOARD_PASS` 也应继续保持分层，不能因为 ROSS 调用成功就把早期状态晋升成最终硬件通过。

### 4. 自有 Skill 与官方 Skill 可以形成互补

官方 Skill 更擅长通用 Vivado 方法学，项目 Skill 则更适合约束冻结工程、证据目录、文件哈希、回退条件和人工审核点。前者解决“怎样正确使用工具”，后者解决“本工程允许怎样修改和验收”。两者结合后，AI 才能从单纯执行命令，转变为在明确边界内完成工程任务。

## 六、ROSS 并不是自动正确的保证

使用过程中也需要保留几个清醒认识：

- 套件顺畅不代表测试平台、RTL 或 golden 一定正确，功能结果仍须逐字节或按明确指标验收。
- MCP 会话健康不代表仿真一定成功，库、顶层、依赖和输入制品仍需核对。
- 官方 Skill 是方法指导，不是强制替代工程规则；项目的冻结边界、回退和人工审核仍然必要。
- Early Access 阶段的版本兼容、重复部署和命令去重问题仍需人工留意，不能把工具返回直接等同于新一轮实测。

总体而言，ROSS 给我最大的价值是：**让 AI 从“会描述 Vivado 操作”变成“能够按照规范实际执行 Vivado 操作”**。它减少的是流程性错误和无意义返工，而不是替我完成工程判断。对我这种需要同时推进 RTL、仿真、IP、综合和板级验证的项目来说，这种流程可靠性和可复现性，正是最直接、最实用的提升。
