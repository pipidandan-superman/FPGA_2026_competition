# PL 地址映射合同 — 3_yolo_zynq（G3 前置）

来源（只读借用，未改动主工程）：
- `2_fpga/0_diaplay_test/release/action_v1_uart_run02/display_test_axi_action_uart.hwh`
- `2_fpga/0_diaplay_test/pynq/current.hwh`（旧 overlay，无 action IP，对照用）

## 主工程已占用区间（必须避开）

| 实例 | IP | 区间 |
|---|---|---|
| processing_system7_0 | PS7 DDR | `0x1000_0000 – 0x1FFF_FFFF`（512MB，帧缓冲） |
| axi_vdma_0 | axi_vdma | `0x4300_0000 – 0x4300_FFFF`（64KB） |
| axi_action_0 | video_axi_action_uart_top | `0x43C0_0000 – 0x43C0_0FFF`（4KB） |

## 本工程（yolo 加速器）分配

| 用途 | 区间 | 说明 |
|---|---|---|
| yolo 寄存器组（AXI-Lite） | `0x43C1_0000 – 0x43C1_FFFF`（64KB） | 紧邻主工程 action IP 之后的 GP0 空闲段；描述符/门铃/中断状态 |
| yolo 权重/激活 DMA（AXI-HP） | DDR 内 carve-out，运行时由驱动分配 | 经 S_AXI_HP0 回 DDR，与帧缓冲同物理内存空间但由软件分区管理 |

依据：Zynq-7 M_AXI_GP0 映射窗口 `0x4000_0000–0x7FFF_FFFF`；上述选择
避开主工程全部已占用段；与主工程合并进同一 bitstream 时无冲突。
**RTL 顶层 C_BASEADDR 参数化，不硬编码。**

## yolo CSR 寄存器图（0x43C1_0000 段内；单一事实源 = 本表，RTL = rtl/yolo_csr.v，驱动/TB 同步）

| 偏移 | 访问 | 名称 | 内容 |
|---|---|---|---|
| 0x00 | R | ID | 0x594F4C31 |
| 0x04 | R | VER | 0x0001_0000（A1） |
| 0x08 | W | CTRL | [0] START 门铃；[1] CLR_STATS（清 ldone 计数/all_done 粘滞/IRQ raw） |
| 0x0C | R | STATUS | [0] busy [1] dsc_ready [2] all_done 粘滞 [3] dsc_pend（门铃未受理）[31:16] ldone 计数 |
| 0x10 | RW | DESC0 | [10:0] oc，[31:16] n |
| 0x14 | RW | DESC1 | [11:0] k，[16] last，[17] first，[18] act |
| 0x18 | RW | DESC2 | [15:0] ih，[31:16] iw |
| 0x1C | RW | DESC3 | [15:0] ow，[31:16] ic |
| 0x20 | RW | DESC4 | [7:0] kh [15:8] kw [23:16] sh [31:24] sw |
| 0x24 | RW | DESC5 | [7:0] ph，[15:8] pw |
| 0x28 | RW | WBASE | W 行 DDR 基址 |
| 0x2C | RW | XBASE | X 平面 DDR 基址 |
| 0x30 | RW | YBASE | Y 平面 DDR 基址（行起始 = ybase + oc_g·n_total + n_tile·N_EDGE） |
| 0x34 | RW | BBASE | bias_eff 字（LE 4B）基址 |
| 0x38 | RW | MBASE | M 字（LE 4B）基址 |
| 0x3C | RW | SBASE | shift 字节基址 |
| 0x40 | RW | IRQ_EN | [0] layer_done [1] all_done |
| 0x44 | RW | IRQ_STAT | W1C [0]/[1] |
| 0x400+4i | W | LUT[i] | wdata[7:0]，i=0..255（只写窗口，读回 0） |

未映射偏移：OKAY、写忽略、读 0。软件合同：STATUS.dsc_pend=1 期间不得重写
DESC*/BASE*（阵列仅在受理沿采样影子寄存器）。V1.0（2026-09-16，M12 A1）。

## PPU 段（0x43C2_0000 – 0x43C2_FFFF，V2.4 新增）

单一事实源 = `yolo_dma_csr\rtl\ps_axi_pl\yolo_csr_pkg.sv`（冻结共用包）+
`yolo_graph\rtl\ppu\f7\yolo_reg_file_f7.sv`（F7 位级语义）。V2.4（M5）在
V2.3 拓扑上新增 PPU 岛：ppu_f7_top（ID="YOL2"）挂 GP0 互连 M03；
**AXI-HP1（64b）为 PPU 专属口**——conv DMA 仍走 HP0（V2.3 原样），两路
互不影响。pkg 头注"from 0x43C1_0000"为设计稿期历史注释，实例基址以
本表 0x43C2_0000 为准。

### 寄存器图（段内偏移）

| 偏移 | 访问 | 名称 | 内容 |
|---|---|---|---|
| 0x000 | R | ID | 0x594F4C32（"YOL2"） |
| 0x004 | R | VERSION | 0x0000_0300 |
| 0x008 | R | CAP0 | 能力位（GRAPH_OP/HEAD_DMA/IRQ） |
| 0x00C | R | CAP1 | 表几何（128 槽等） |
| 0x010 | W | CTRL | [0]ENABLE 锁存 [1]SOFT_RESET [2]START_FRAME [3]STOP [4]ABORT [5]CLR_STATUS [6]FLUSH_CACHE（脉冲）[7]ARM_IRQ（置位）；驱动律 0x5=ENABLE+START_FRAME |
| 0x014 | R | STATUS | walker 状态（idle/running/frame_done/opcode） |
| 0x018 | R/W1C | ERROR_STATUS | bit0..9=AXI_LITE/DMA_RD/DMA_WR/DESC/BUFFER/QUANT/LUT/TIMEOUT/OVERFLOW/PROTOCOL；bit10=引擎错（F7，walker err_evt_eng） |
| 0x01C | R | ERROR_INFO | 错误码/算子/描述符 id |
| 0x020/0x024 | RW | MODEL_ID / GRAPH_CRC | 模型标识 |
| 0x028 | RW | FRAME_ID | 帧号（帧循环驱动） |
| 0x02C–0x038 | RW | FRAME_CFG / INPUT_BASE_LO/HI / INPUT_STRIDE | 输入面配置 |
| 0x040/0x044/0x048 | RW | HEAD_BASE_LO/HI/STRIDE | heads 输出 DDR 基址（描述符 w2 out=0x3FF 时写此） |
| 0x04C | R | HEAD_BYTES | |
| 0x050 | RW | HEAD_FORMAT | 0 |
| 0x054 | R | RESULT_SEQ | ring 发布序号（帧完成轮询点） |
| 0x058 | R | RESULT_FRAME_ID | |
| 0x05C | R/W1C | RESULT_STATUS | valid/ovf/drop/owned |
| 0x060 | W | RESULT_ACK | [0]consume [1]drop [2]retry；尾针在 ACK 后一拍自增（板 l3r1 律：先 ACK 再写 RING_TAIL） |
| 0x064 / 0x068 | R / RW | RESULT_RING_HEAD / RING_TAIL | 32 项环指针 |
| 0x06C / 0x070 | RW | RESULT_MAX_DET / CONF_Q | |
| 0x100 | RW | DESC_CFG | |
| 0x104 | RW | DESC_BASE | 描述符窗基（字偏移 [11:0]）——8KB 物理窗滑入 16KB 表 |
| 0x108 / 0x10C / 0x110 | RW / R / RW | DESC_COUNT / HEAD / TAIL | |
| 0x114 | W | DESC_DOORBELL | [0]commit [1]frame_end（置粘着+发 ffe 脉冲） |
| 0x118 / 0x11C / 0x120 | R | DESC_CURRENT / DONE_COUNT / ERROR_ID | 帧内进度轮询点 |
| 0x124 / 0x128 | RW / R | SCHED_CFG / SCHED_STATUS | |
| 0x200 | RW | DMA_CFG | [23:0] AXI 超时拍 [26:24] 读 outstanding 上限 [29:27] 写 outstanding 上限（F7 定版；驱动默认 (4<<27)\|(4<<24)\|100） |
| 0x204–0x224 | R/W | DMA_STATUS…PERF_CLEAR | 计数/清零 |

### 窗口（段内偏移；**表写仅在 walker idle 期合法**，运行期写=SLVERR+E_CODE_TABLE_RUN；ring 只读，写=E_CODE_RING_RO）

| 窗 | 区间 | 容量 | 说明 |
|---|---|---|---|
| DESC | 0x1000–0x2FFF | 8KB = 64 槽 | 16KB 表（128 槽 × 128B）的滑窗，DESC_BASE 定窗基。**>64 任务须分页装载：n80 全图 104 任务 = 页 0（win_base=0，槽 0–63）+ 页 1（win_base=2048，槽 64–103）** |
| BUF | 0x3000–0x3FFF | 4KB = 128 槽 | 8 字/槽，全量直映（buf word0/1 的 64b 基址按 CMA delta 补丁） |
| QUANT | 0x4000–0x4FFF | 4KB = 256 profile | 4 字/profile（w0=M32 w1=shift；profile 0=恒等 2³⁰/30） |
| LUT | 0x5000–0x5FFF | 4KB | SiLU 16 bank × 256 × 8b |
| RING | 0x6000–0x67FF | 2KB = 32 项 | 16 字/项（w0=frame_id w4=head_bytes w10=flags…）；上半 0x6800 起未映射 |
| DEBUG | 0x7000–0x7FFF | — | 选配，读 0 |

HP 归属：HP0 = axi_mem_intercon（V2.3 conv DMA 原样）；HP1 = PPU 专属。
**环孔径停泊律（V1.6.3）**：任一 CSR 读都会占用 ring BRAM 读口——驱动
不得读正在被写的那一项；slot0 帧以 RESULT_SEQ 轮询代替逐项读。

## 借用的其它主工程参数（后续 RTL/驱动参考）

- PS7 DDR 基址 0x10000000（帧缓冲惯例沿用）
- VDMA 64KB 寄存器段布局（如需视频输出链路复用）
- action IP 的 AXI-Lite 从设备模式（4KB 段经验值 → 本工程放宽到 64KB）

## 变更纪律

本文件是 3_yolo_zynq 硬件地址合同的单一事实源；改地址 = 改本文件 +
RTL 参数 + 驱动三处同步，禁止只改一处。

版本：V1.0（2026-09-16，M12 A1，CSR 段）。V1.1（2026-10-07，M5.0）：
新增 PPU 段 0x43C2（YOL2）寄存器图+窗口合同（V2.4 位流），内容逐项取自
冻结包 yolo_csr_pkg.sv / yolo_reg_file_f7.sv / ppu_f7_top.v 与板证驱动
pl_v23b_v24bit.py，无新设计。
