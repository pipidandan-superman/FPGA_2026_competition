# 一芯多模：Zynq-7020 视觉推理与软硬件协同实验

本仓库对应 AMD 赛题 **3.3 自主选题赛道**，目标器件为 EES-331（xc7z020clg484-1），使用 OV5640、HDMI 和现有 PYNQ 镜像。复现工具固定为 **Vivado 2025.2**。

公开仓库：https://github.com/pipidandan-superman/FPGA_2026_competition

原始研发仓库：https://github.com/pipidandan-superman/FPGA2026_competition 。需要查阅完整研发过程、历史工程版本和原始实验证据时，可访问该仓库。当前仓库是专门面向 AMD §3.3.5 的整理提交版，与原始研发仓库分开维护，不能用历史版本替代本包的验证结论。

系统包含 PS ncnn 三网络/三任务演示、PL 网络计算，以及 PS 主干/颈部加 PL 检测头的驻留混合路径。PS 三模型切换已经展示；多网络由同一个 PL 加速器执行仍属在研目标。纯 PL 路径的 PS 仍承担归一化、量化、控制和解码/NMS。

**最新验收状态以 [build/validation_status.md](build/validation_status.md) 为准。** 历史板测、本次工程验证、完整 BIT 重建和当前部署板测分别记录，不能互相替代。

## 目录与赛题要求对照

| 目录 | 内容 |
|---|---|
| `src/` | 自研 RTL、软件、编译/量化工具与接口定义 |
| `sim/` | 测试台、OSD 正向/故障注入入口、历史加速器回归证据 |
| `build/` | 构建、部署、板测脚本及时序/资源/DRC 报告 |
| `board/` | 各形态源工程、BIT/HWH/XSA、模型、板端程序和实测输出 |
| `data/` | 固定输入与黄金参考数据 |
| `skill/` | 可复用技能、使用条件、失败边界和实测矩阵 |
| `report/` | 技术报告、大模型协作记录、配图和 ROSS 使用心得 |
| `licenses/` | 适用的第三方许可原文 |

各形态源工程位于 `board/<form>/vivado_project`。依赖收录在包内，构建脚本在外部新目录重建 IP 和工程，不修改源目录。模型按形态放在 `board/<form>/models`；`data/gold` 是部署树的共享输入。

## 形态与当前证据

| 形态 | 计算分工 | 历史 BIT SHA 前缀 | 当前可核验范围 |
|---|---|---|---|
| 一A预处理 | PL 输入预处理、PS ncnn 推理 | 0e9dd312 | 历史三网手势演示；本次 Vivado 工程验证通过，完整 BIT 重建未执行 |
| 一B三任务 | PS 三任务、PL 采集与 OSD | c910f8ce | 历史 HDMI 演示；本次完整 BIT/XSA 重建通过，OSD 四项回归通过 |
| 二纯 PL | PL 网络计算，PS 输入变换和结果处理 | c1015749 | 历史 83 帧、六类缺 Down；本次 Vivado 工程验证通过，部署树和固定输入入口已核验但未板测 |
| 三驻留混合 | PS 主干/颈部、PL 六段检测头 | 72b358ff | 历史最终 488 帧七类检出；本次完整 BIT/XSA 重建通过；严格序列以对应板测记录为准 |
| AC1 加速器 | GEMM 与图算子集成 | 2fa0f2e1 | 历史实现及 A/C 电池证据；本次 Vivado 工程验证通过，完整 BIT 重建未执行 |
| BLE J5 | 蓝牙桥开发候选 | b939ef67 | 本次 Vivado 工程验证通过；不是现役集成验收，完整 BIT 重建未执行 |

重建 BIT 与历史 BIT 是不同制品。任何新生成制品须使用其配对 HWH/XSA 并独立板测，不能按旧文件名或旧报告认定身份。C-leg 的历史 PASS 仅表示与旧基线等价，包含既存故障，不等于全图成功。

## 从源码构建

安装 Vivado 2025.2，主机需 Python 3.10+。所有输出目录必须在仓库之外且每次全新。以下示例使用 PowerShell；将 `<new_run>` 换成自己的证据目录。

```powershell
python build/prepare_build.py --form form3_pspl_resident --output C:/fpga_runs/<new_run> --stage bitstream
vivado -mode batch -source C:/fpga_runs/<new_run>/run.tcl -log C:/fpga_runs/<new_run>/vivado.log -journal C:/fpga_runs/<new_run>/vivado.jou
```

第二行须从已经配置 Vivado 2025.2 环境的命令行执行。支持 `--form`：`form1a_ble_bridge_j5`、`form1a_pl_preprocess`、`accelerator_ac1`、`form1b_multitask_osd`、`form2_pl_continuous`、`form3_pspl_resident`。只做工程打开、模块引用和 BD 校验时使用 `--stage validate`；它不等于 BIT 重建通过。

完整构建检查综合/实现进度、黑盒、已定义约束时序、DRC 与导出结果，同时人工检查未约束路径和时钟告警。详见 [build/README.md](build/README.md)。

在 Git Bash 启动 Windows Vivado 时，如遇到启动器静默退出，可在调用前设置 `PROCESSOR_ARCHITECTURE=AMD64`；远程 Linux 路径参数应避免被 Git Bash 自动转换，可设置 `MSYS_NO_PATHCONV=1`。

Windows 克隆若提示 `Filename too long`，先执行 `git config --global core.longpaths true` 再重新克隆；Vivado 输出目录也应使用较短路径，例如 `C:/fpga_runs`。仓库通过 `.gitattributes` 禁止文本行尾转换，提交、克隆和本地清单必须保持相同字节，不能用编辑器批量转换 CRLF/LF。

## 仿真

```powershell
python build/verify_osd.py --vivado-home F:/vivado2025/2025.2/Vivado --output C:/fpga_runs/<new_sim>
```

该入口先验证 XSim 实际运行，再执行 COCO、姿态 OSD 正向测试及历史错误版本负控。负控必须出现预定错误；进程退出码零不能代替仿真结论。当前结果为 `OSD_REGRESSION_PASS`，四项全部通过。

## 部署与板测

主机需 OpenSSH。首次连接前核对板卡身份并加入 `known_hosts`。凭据从当前进程环境 `BOARD_PW` 提供，不写入文件或命令行。PYNQ 环境、ncnn 依赖和 IP 合同须在目标板确认。

```powershell
python build/stage_submission.py --form form2_pl_continuous --output C:/fpga_runs/<new_stage> --remote-root /home/xilinx/amd_submission/<new_version>
```

`--form` 支持一B、二、三。默认只生成部署树；加 `--upload` 才上传并逐文件校验，上传不启动硬件。三种部署树均已离线生成成功。

形态二固定输入 21/21 黄金平面比对：

```powershell
python build/board_transport.py --script build/verify_form2.py --script-arg /home/xilinx/amd_submission/<new_version> --output C:/fpga_runs/<new_test> --sudo --timeout 420
python build/fetch_board_evidence.py --output C:/fpga_runs/<new_test>
```

形态三将脚本换成 `verify_form3.py`；七手势测试增加 `--script-arg=--gestures` 并提高运输超时。板测会暂停摄像头服务，必须事先取得现场授权，使用全新板端目录，并核对所有权、VDMA 停止和原服务恢复。形态二新增固定输入入口尚未实际板测；一B/二当前硬件启动也需各自验证配置，不能由部署树成功推断功能通过。

历史 `launch_*.sh` 中标记 `RETIRED_ENTRY` 的脚本只作来源留档，不要执行。历史文档里的 `E:/competition`、`13_final`、`4_metrics` 和 `7_logs` 是来源或证据路径，不是新机器的复现依赖。

## 文档、许可与发布

- 当前技术报告：[technical_report_v8.docx](report/technical_report_v8.docx) 及 [PDF](report/technical_report_v8.pdf)，39 页、18 图、16 表，含 OPU 体系、五类工程、锁布局消融和复现入口；[V4 历史报告](report/technical_report_v4.docx) 保留用于追溯。
- 大模型协作记录：[ai_collaboration_records_summary.md](report/ai_collaboration_records_summary.md) 及同名 DOCX。
- 技能验证矩阵：[validation_matrix.md](skill/validation_matrix.md)。
- 原创代码和原创文档采用 [MIT](license.txt)。
- 第三方组件、模型、转换制品和数据保留原许可，详见 [third_party_notices.md](third_party_notices.md) 与 `licenses/`。特别注意 Ultralytics 模型及派生制品的 AGPL-3.0 条款，不得误标为 MIT。

完整文件清单见根目录 `sha256_manifest.txt`，二进制专项清单见 `binary_sha256.txt`。发布前必须确认 `build/validation_status.md` 中的结论与实际执行范围一致，并重新生成和校验全量清单。演示视频等外部交付材料按既定方案单独提交，不混入源码仓库。
