# src/ — 设计源码（RTL / 加速器 / PS 侧软件）

本目录按赛题 §3.3.5.4 的 `src/` 要求收纳**设计源码**：PL 侧 RTL、加速器生成脚本、PS 侧软件。位流制品与部署脚本在 `board/`，综合实现报告在 `build/`，仿真在 `sim/`。

## 目录结构

```
src/
├── accelerator/              # YOLO CNN 加速器源码树（自带 README.md）
│   ├── yolo_gemm/            #   GEMM 计算核：RTL + 存储生成脚本（BRAM/LUTRAM IP 化）
│   ├── yolo_graph/           #   图调度器 RTL（任务描述字驱动的整网调度）
│   ├── yolo_dma_csr/         #   DMA/CSR 与 PS-PL AXI 互联 RTL（含 BRAM IP DCP）
│   ├── yolo_head/            #   head 段拆分/量化脚本
│   ├── ps_host/              #   加速器 PS 侧驱动（Python）
│   ├── abi/                  #   软硬件接口合同（ABI 文档）
│   ├── isa_tables/           #   4 份指令集/控制字字段表（xlsx：ppu_isa、view_alias、ppp_control_word、doorbell_control_word）
│   ├── tools/                #   生成与校验工具
│   ├── accel_bootstrap.py / accel_paths.py   # 入口引导与路径解析
│   └── rtl_ledger*.json      # RTL 台账（源文件清单与版本）
├── form1a_pl_preprocess/     # 形态一A：PL letterbox 预处理工程的 PS 侧源码
├── form1b_multitask_osd/     # 形态一B：三任务 OSD 工程 RTL
├── form2_pl_continuous/      # 形态二：任务描述字表 descriptor_table.json
└── host/                     # PS 主机侧软件全集（自带 README.md）
    ├── gesture_chain/        #   七手势主链（Python + C++ + spec）
    ├── model_arm_chain/      #   模型-机械臂联动链（含标定与变体）
    ├── ble_console/          #   蓝牙控制台（含中文使用说明 usage_notes_zh.md）
    ├── myarm2_ble/           #   MyArm-32 蓝牙直控（py/tcl）
    ├── udp_video/            #   UDP 视频回传
    ├── model_env/            #   模型运行环境（安装脚本与锁定清单）
    ├── pynq/                 #   pl_reloader（PL 在线重装载 GUI）+ sd_boot_builder（SD 镜像构建，v1/v02）
    ├── yolo_p2/、yolo_ppu/   #   推理脚本与 PPU 工具链
    └── README.md
```

## 使用说明

- 加速器源码入口：先读 `accelerator/README.md`，用 `accel_bootstrap.py` 初始化路径，再按 `rtl_ledger.json` 核对源文件清单。
- 指令集字段表位于 `accelerator/isa_tables/*.xlsx`（与 RTL 同步演进的四份表：PPU 指令、视图别名、PPP 控制字、门铃控制字）。
- 各形态源码与其上位流一一对应：源仓 `2_fpga/`（冻结基线）、`3_host/`、`12_yolo_accel/`；本包为提交用的整理副本，演进历史与证据在源仓。
- 模型部署副本按形态放在 `board/<form>/models/`，保证部署脚本相对路径可用；本目录不重复存放权重。

## 现役复现入口与历史研究工具

主形态复现统一从根目录 `build/prepare_build.py`、`build/stage_submission.py`、`build/verify_osd.py` 和相应 `verify_form*.py` 进入。六个 XPR 所需的 RTL、BD、XCI、COE、约束和模块引用已收录在各自 `board/<form>/vivado_project/`，不依赖 `accel_paths.py` 指向的历史证据目录。

`host/`、`accelerator/ps_host/`、`yolo_p2/`、`yolo_ppu/` 中还保留了设计和优化过程中的研究工具。其中部分脚本读取 `4_metrics/logs/<历史run>`、专用虚拟环境或作者工作区的输入，属于来源与实验记录，不是陌生机器上的一键入口。复用这些工具前必须单独准备其输入清单并改写路径；不得把它们的不完整外部依赖误判为主形态缺件，也不得在未准备输入时宣称整条历史实验链可复现。

## 边界

- `src/accelerator/yolo_dma_csr/rtl/ps_axi_pl/ip/**/*.dcp` 为 BRAM IP 检查点（SHA 见根 `binary_sha256.txt`），按 XPR 的实际引用处理；可由源配置再生成者不作为唯一重建依赖。
- 形态四（多 BIT 在线重装载）源码未入包，统一标注为在研，不计入当前验收。
- 本目录中的历史 README、命令示例和路径用于解释设计沿革；若与根目录现役构建说明冲突，以根目录和 `build/validation_status.md` 为准。
