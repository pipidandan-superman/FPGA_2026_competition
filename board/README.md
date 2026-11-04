# board/ — 上板工程、运行脚本与实测输出

本目录按赛题 §3.3.5.4 的 `board/` 要求收纳**上板工程、位流/硬件制品、部署运行脚本与板端实测输出**。六个子目录各带自己的 `README.md`（复现步骤与边界）与 `manifest`（制品哈希），全包二进制 SHA-256 汇总见仓库根目录 `binary_sha256.txt`。

## 公共前提

- **板卡**：普通市售 Zynq-7020 教学板（XC7Z020，与 PYNQ-Z2 同款），OV5640 摄像头 + HDMI 输出 + 蓝牙模块（形态一A 蓝牙桥）。
- **板上环境**：PYNQ 镜像 + `pynq-venv`（见根 README 复现步骤）。
- **口令策略**：板卡 SSH 口令只从 `$BOARD_PW` 环境变量读取，任何脚本都不落盘、不硬编码。
- **Vivado 版本**：2025.2（仅在需要重建工程时使用；`vivado_project/` 只含 `.srcs` + `.xpr` 可复现子集，打开后由 Vivado 重建 `.cache/.runs` 等生成树）。

## 子目录一览

| 子目录 | 形态 | 关键制品 | 位流 SHA-256（前 8 位） | 状态 |
|---|---|---|---|---|
| `accelerator_ac1/` | CNN 加速器单元 AC1（M9 v25 集成版） | `hw/m9_v25_integration.bit` + `.xsa`、`sw/` 驱动 | `2fa0f2e1` | 冻结（板证） |
| `form1a_pl_preprocess/` | 形态一A：PL letterbox 预处理 + PS 推理 | `hw/t1_letterbox_m_final.bit`+`.hwh`、`models/` | `0e9dd312` | 冻结（板证） |
| `form1a_ble_bridge_j5/` | 形态一A 蓝牙桥（J5 扩展口）候选版 | `net3_ps_only_pl_ble_j5.xsa`、`sw/board_artifacts/t1_overlay_ble_j5.bit`+`.hwh`、调试工程 `ble_uart_debug_j5/` | `b939ef67` | **候选**（J5 接法待定，含调试位流 `c7d8bd84`） |
| `form1b_multitask_osd/` | 形态一B：三网络三任务 OSD（一块 BIT 拨码切换） | `sw/board_artifacts/multitask_osd.bit`+`.hwh`+`.xsa`、`models/`、`logs/` | `c910f8ce` | 冻结（板证） |
| `form2_pl_continuous/` | 形态二：完整 PL 连续推理 | `sw/board_artifacts/net3_pl_hp_rebalance.bit`+`.xsa`+`.hwh`、`prog/`、`logs/` | `c1015749` | 冻结（板证，实测 4.2671 s/帧 @80 MHz） |
| `form3_pspl_resident/` | 形态三：PS backbone + PL heads 混合驻留 | `sw/board_artifacts/hybrid_heads_ic64_fix.bit`+`.hwh`+`.xsa`、`prog/`、`models/`、`logs/` | `72b358ff` | 冻结（板证） |

## 目录约定

- `hw/`、`sw/board_artifacts/`：位流与硬件导出（`.bit/.xsa/.hwh`），SHA 与冻结包一致。
- `models/`：该形态部署所需的 ncnn/ONNX 模型副本（随形态放置，保证部署脚本相对路径可用；训练侧与 gold 数据见 `data/` 与源仓）。
- `vivado_project/`：仅 `.srcs` + `.xpr` 的可复现工程子集（不含生成树）。
- `sw/`：部署与运行脚本（含 PC 侧辅助）。
- `prog/`：板上服务化运行入口（形态二/三）。
- `logs/`：板端实测原始输出（UART/服务日志）。

## 诚实边界

- `form1a_ble_bridge_j5` 为候选版：蓝牙模块接 J5 扩展口 V13/W13 的方案尚未最终确认，另含独立调试位流 `ble_uart_debug_j5_top.bit`。
- 形态四（多 BIT 在线重装载）在研，未纳入本包。
- 位流重建须以本表 SHA 为验收基准；`vivado_project` 重新实现生成的位流未经板证，不得直接替换冻结制品。
