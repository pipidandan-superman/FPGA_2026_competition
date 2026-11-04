---
name: vivado-ai-workflow
description: AMD/Xilinx Vivado AI MCP-driven workflow. Use whenever Vivado operations are needed — project open/close, synthesis, implementation, bitstream, simulation (xsim via Vivado TCL), IP integration, netlist inspection, timing analysis, board prep, or AMD documentation lookup. Also use for session lifecycle (start/connect/stop/cleanup) and progress tracking (todos). All Vivado/XSim work MUST go through MCP; raw shell invocation of Vivado executables is prohibited.
---

# AMD/Xilinx Vivado AI Workflow

## 何时调起此 skill

以下场景**必须**调起本 skill（而非裸 shell）：

### Vivado 工程与设计操作
| 场景 | 触发词/行为 |
|---|---|
| 创建/打开/关闭 Vivado 工程 | "open_project", "create_project", "close_project" |
| 综合（synth_design / launch_runs synth） | "综合", "synthesize", "synth" |
| 实现（place/route/opt/phys_opt） | "实现", "place", "route", "implementation" |
| 位流生成（write_bitstream） | "位流", "bitstream", "write_bitstream" |
| 工程配置（set_property, add_files） | "add_files", "set_property", "工程配置" |
| IP 管理（create_ip, update_module_reference） | "IP", "create_ip", "update_ip" |
| 网表/时序检查（report_timing, report_utilization） | "时序", "WNS", "timing", "utilization" |
| Checkpoint 读写（open_checkpoint, write_checkpoint） | "checkpoint", "dcp" |
| BD 操作（create_bd, source BD tcl） | "block design", "BD", "create_bd" |
| XSA/HWH 导出（write_hw_platform） | "xsa", "hwh", "export hardware" |

### xsim 仿真（通过 Vivado 会话内 TCL）
| 场景 | 触发词/行为 |
|---|---|
| 编译 Verilog/SystemVerilog | "xvlog", "compile" |
| 编译设计（xelab） | "xelab", "elaborate" |
| 运行仿真（xsim） | "xsim", "simulate", "仿真" |
| source 仿真脚本 | "source run_xsim.tcl" |

**关键：xvlog/xelab/xsim 不是独立可执行体调用——它们是 Vivado TCL 命令，必须通过 `vivado_execute` 在 Vivado 会话内执行。**

### AMD/Xilinx 官方文档查询
| 场景 | 触发词/行为 |
|---|---|
| 查 PG/UG 手册 | "PG", "UG", "product guide", "user guide" |
| 查 IP 引脚/时序/约束 | "IP 文档", "引脚", "port description" |
| 查器件/板卡规格 | "器件", "board part", "XC7Z020" |

→ 使用 `amd-doc-search` MCP 工具（`mcp__amd-doc-search__vivado_doc_search`）

### 会话生命周期
| 场景 | 触发词/行为 |
|---|---|
| 启动 Vivado | "启动 Vivado", "start Vivado", "开 Vivado" |
| 连接已有会话 | "连接 Vivado", "connect" |
| 查看活跃会话 | "Vivado 会话", "list sessions" |
| 清理陈旧会话 | "清理 Vivado", "cleanup" |
| 停止会话 | "关 Vivado", "stop Vivado" |

### 进度追踪
| 场景 | 触发词/行为 |
|---|---|
| 多步 Vivado 工作流 | "build flow", "implementation flow" |
| 里程碑追踪 | "进度", "progress", "todo" |

### 日志与排障
| 场景 | 触发词/行为 |
|---|---|
| 查 Vivado 错误/警告 | "Vivado 错误", "ERROR", "CRITICAL WARNING" |
| 诊断卡住的 run | "stuck", "卡住", "OOC stuck" |
|) 查命令历史 | "Vivado 历史", "history" |

## MCP 工具清单与能力

### 核心工具（全部可用）
| 工具 | 功能 | 使用场景 |
|---|---|---|
| `vivado_start` | 启动新 Vivado 会话（TCL/GUI 模式、general/ipi 类型） | 任何需要 Vivado 的操作 |
| `vivado_connect` | 连接已有 Vivado 实例（通过 webserver+proxy） | 重连断开会话、接手工单 |
| `vivado_execute` | 执行 TCL 命令（支持 batch、长命令自动 handoff） | 所有工程/设计/仿真操作 |
| `vivado_status` | 会话状态、run 进度、健康诊断、卡住恢复 | 监控、排障、恢复 |
| `vivado_log_messages` | 结构化日志（ERROR/WARNING/INFO，按代码+行号） | 排障、门检查 |
| `vivado_history` | 命令历史搜索 | 审计、回溯 |
| `vivado_list_sessions` | 列出活跃会话（PID/版本/模式/运行时间/proxy） | 会话管理 |
| `vivado_stop` | 停止会话（终止进程+webserver） | 收尾、清理 |
| `vivado_todos` | 多步工作流进度追踪（plan/update/read/clear） | 综合→实现→位流链 |
| `vivado_cleanup` | 清理陈旧会话、杀孤儿进程、LSF 孤儿作业 | 环境维护 |
| `vivado_client_info` | MCP 客户端能力+服务端版本 | 调试 MCP 自身 |

### 文档工具
| 工具 | 功能 |
|---|---|
| `mcp__amd-doc-search__vivado_doc_search` | 搜索 AMD/Xilinx 官方文档（跨知识库/PDF/web/wiki/blog/GitHub），可按 family/tool/version 过滤 |

### 不可用工具（当前构建未启用）
| 工具 | 原因 | 影响 |
|---|---|---|
| `vivado_lsf` | `VIVADO_ENABLE_LSF=false` | LSF 集群调度不可用；本地 Vivado 足 |
| `vivado_ssh` | `VIVADO_ENABLE_SSH=false` | 远程 SSH Vivado 不可用；仅本地 |
| `vivado_feedback` | 构建不支持 | 反馈收集不可用 |

### 未覆盖的 AMD 工具（MCP 尚无专用支持）
| 工具 | 当前处理 |
|---|---|
| Vitis (v++) | 诚实报告"MCP 未覆盖 Vitis"；若用户确认裸 shell 必要性→记录例外 |
| Vitis AI (vaic) | 同上 |
| PetaLinux (pn) | 同上 |
| Vitis HLS | 同上 |
| XSCT | 同上 |

**原则：MCP 每扩展一个 AMD 工具，此 skill 同步更新。未覆盖≠禁止——而是"必须先报告 MCP 未覆盖，获用户确认后才可裸 shell"。**

## 铁律（不可违反）

**凡 MCP 工具链可执行的 AMD/Xilinx 操作，必须通过 MCP。禁止裸 shell 直接调用。**

```
✅ vivado_start → vivado_execute("launch_runs synth_1 -jobs 8") → wait_on_run → ...
✅ vivado_execute("xvlog -sv foo.sv") → vivado_execute("xelab ...") → vivado_execute("xsim ...")
✅ amd_doc_search(query="PG132 AXI DMA")
❌ Bash("vivado -mode batch -source build.tcl")
❌ Bash("xvlog ... && xelab ... && xsim ...")
❌ Bash("vivado -mode gui")
```

## 会话管理正典

### Windows XSim 子进程环境检查

在 Windows 上通过 `launch_simulation` 前，必须确认 Vivado MCP 进程环境包含 Vivado 工具目录。`VIVADO_PATH` 只定位 `vivado.bat`，不会自动保证 XSim 子进程能找到 `xvlog`、`xelab` 和 `xsim`。MCP 注册环境应优先把真正的 Windows 可执行目录放在前面，并保留运行库目录：

```text
<Vivado>\bin\unwrapped\win64.o
<Vivado>\bin
<Vivado>\lib\win64.o
```

Windows 安装目录中的 `<Vivado>\bin\xvlog`、`xelab`、`xsim` 可能是 Unix shell wrapper；MCP 启动的 Windows 子进程若优先解析这些无扩展 wrapper，会在 `compile.bat` 阶段报 `ERROR: [Common 17-180] Spawn failed`。因此应让 `bin\unwrapped\win64.o` 排在 `bin` 之前，并在必要时从仿真子进程 `PATH` 中暂时去掉 `bin`，但仍保留 `bin` 和 `lib\win64.o` 供 Vivado 会话本身使用；不要把 `bin\unwrapped\win64.o` 放在 `PATH` 中无关目录之后。用直接 MCP 客户端或已授权的 MCP 配置检查并修复环境后，重新建立 Vivado 会话，再运行 `launch_simulation`。同时保留 `XILINX_VIVADO=<Vivado>`、`COMSPEC=<Windows>\System32\cmd.exe` 和 `SystemRoot=<Windows>`。不要在 Vivado TCL 中调用 `exec xvlog`、`exec xelab` 或 `exec xsim` 作为绕过方案。遇到 `ERROR: [Common 17-180] Spawn failed` 时，先修复 MCP 子进程环境并重新建立会话。

### 启动 TCL 会话（默认，无显示器）
```
vivado_start(working_dir, session_type="general")
```

### 启动 GUI 会话（仅用户明确要求时）
```
vivado_display(action="check")                    # 检查显示器
vivado_display(action="virtual_start")            # 无显示器→VNC（vnc_connection_string 给用户）
vivado_start(working_dir, session_type="general", gui_mode=false, display=":99")
vivado_execute("start_gui", session_id)           # 按需开 GUI
```

### 连接已有会话（优先用 proxy_addr）
```
vivado_list_sessions()                            # 找 proxy_addr + webserver_url
vivado_connect(webserver_url, proxy_addr, session_id)
```

### 会话互斥律（[[vivado-gui-batch-session-lockout]]）
- 同工程双会话 = 旧内存态保存踩掉 .xpr
- 批处理前 GUI 必须关
- 换工程前 `close_project`
- 脚本须显式 `close_project` 防残留

## 综合/实现正典

```tcl
vivado_start(working_dir, session_type="general")
vivado_execute("open_project <path>", session_id)
# 综合（OOC IP 自动先行）
vivado_execute("launch_runs synth_1 -jobs 8", session_id)
vivado_execute("wait_on_run synth_1", session_id)
# 实现
vivado_execute("launch_runs impl_1 -jobs 8", session_id)
vivado_execute("wait_on_run impl_1", session_id)
# 位流
vivado_execute("launch_runs impl_1 -to_step write_bitstream", session_id)
vivado_execute("wait_on_run impl_1", session_id)
# 检查
vivado_log_messages(filter="errors", session_id)
vivado_execute("report_timing -return_string", session_id)
# 收尾
vivado_execute("close_project", session_id)
```

### 长命令 handoff
synth_design/place_design/route_design 等>5min 命令自动 handoff：
- `vivado_status(action="session")` 轮询 is_command_running（每 30-60s）
- `ooc_progress` 显示 IP 编译进度
- 完成后 `last_completed_code`（0=成功）

### 卡住恢复
```
vivado_status(action="health", session_id)       # 诊断
vivado_status(action="reset_run", session_id)    # 重置
vivado_status(action="cancel_and_relaunch", session_id, jobs=8)  # 取消+重跑
vivado_status(action="cancel_queue", session_id) # 丢弃排队命令
```

## xsim 仿真正典

### 方法一：source 仿真脚本
```
vivado_start(working_dir, session_type="general")
vivado_execute("source run_xsim.tcl", session_id)
```

### 方法二：逐步 execute
```
vivado_execute("xvlog -sv foo.sv bar.sv", session_id)
vivado_execute("xelab work.top -debug off", session_id)
vivado_execute("xsim work.top -R", session_id)
```

### xsim 正典（[[xsim-native-sim-canon]]）
- BFM 勿逐拍 `new[n+1]`——内存泄漏
- 等待/ack 任务落定居拍——防竞态
- launcher 分块环境读——防环境污染
- `-debug off` 是大批量前提
- plusarg 走文件（`run_mode.txt`），不走 CLI

## AMD 文档查询

```
mcp__amd-doc-search__vivado_doc_search(
  query="AXI DMA SG mode tready behavior",
  tool=["Vivado Design Suite"],
  family=["Zynq 7000"],
  limit=5
)
```

IP 排障铁律（[[manual-first-ip-diagnosis]]）：**IP 故障第一动作=翻 PG/UG 逐引脚核对使能/复位/极性契约。**

## 命令编写规范

### 保持简单——服务端已处理错误
```tcl
# ❌
if {[catch {set b [get_board_parts]} err]} { return "ERROR: $err" }
# ✅
get_board_parts
```

### 多行→单行（分号）
<parameter name="add_files src/top.v; set_property top top [current_fileset]; update_compile_order -fileset sources_1">
</parameter>

### 长命令独立
synth_design/place_design/route_design/opt_design/phys_opt_design/write_bitstream、
launch_runs/wait_on_run、open_project/open_checkpoint/source、start_gui/stop_gui
——必须独立调用，不与其他命令拼。

### 输出模式
- `verbosity="digest"`（默认）：错误/警告计数+尾行+log_file 路径
- `verbosity="full"`：完整输出（调试用）
- `verbosity="errors"`：仅错误+log_file

## 与其他 skill 的关系

- **[[zynq-pynq-overlay-workflow]]**：板端 overlay 下载（PS Python），不涉及 Vivado
- **[[vivado-bd-bitstream]]**：→ 本 skill 子集（BD+位流走 MCP）
- **vivado-batch-sim-legacy**：→ 本 skill 取代（DEPRECATED）
- **[[rtl-coding-standards]]**：RTL 编码规范，与本 skill 正交

## 环境事实

- Vivado：2025.2（`/f/vivado2025/2025.2/Vivado/`）
- xsim：同 2025.2
- Python：`D:/work/Python/python.exe`（3.13.9）
- 目标器件：XC7Z020 CLG484-1（EES-331）
- MCP server version：2026.9.1 (commit 2c4e86e5)

## Windows 已验证批处理仿真（2026-11-02 用户明确授权的非 MCP 路线）

仅在用户明确要求复用原批处理流程或明确不调用 MCP 时使用本节；默认仍优先 MCP。已实测脚本：`scripts/run_windows_xsim.cmd`。不要再临时重写环境、逐个试验 RDI 变量或仅凭进程返回码判定 PASS。

```text
run_windows_xsim.cmd WORK_DIR TOP PASS_MARKER SOURCE.v [更多 SOURCE.v ...]
```

- 必须保留脚本内 `PROCESSOR_ARCHITECTURE=AMD64`；缺失时 AMD loader 会在架构检查处静默退出。
- 使用干净 Windows／Vivado PATH 和官方 `xvlog.bat／xelab.bat／xsim.bat`，由 loader 设置 RDI／TCL 环境。不要只调用 `settings64.bat` 后再手工猜 `RDI_DATADIR`、`RDI_LIBDIR` 或 `TCL_LIBRARY`。
- Git Bash 使用 `cmd.exe //c <script>`；Windows CMD 使用 `cmd.exe /c <script>`。
- 工作目录必须包含 `$readmemh` 所需 HEX；每个阶段生成独立日志，最终 `findstr` 强制匹配 PASS 标记，缺失即返回 1。
- 不以 XSim 返回 0 代替功能 PASS；必须检查新日志时间、目标标记及 `Fatal`／`FAIL`。

本项目 OSD 实例（2026-11-02 已复测通过）：

```text
run_windows_xsim.cmd E:\competition\4_metrics\logs\2026-11-01_multitask_osd_run01\sim tb_task_coco_osd COCO_OSD_ALL_PASS <axi_lite_slave.v> <task_coco_osd.v> <tb_task_coco_osd.v>
run_windows_xsim.cmd E:\competition\4_metrics\logs\2026-11-01_multitask_osd_run01\sim tb_task_pose_osd POSE_OSD_ALL_PASS <axi_lite_slave.v> <task_pose_osd.v> <tb_task_pose_osd.v>
```

证据：`4_metrics/logs/2026-11-01_multitask_osd_run01/sim/tb_task_coco_osd_xsim.log` 与 `tb_task_pose_osd_xsim.log`。
