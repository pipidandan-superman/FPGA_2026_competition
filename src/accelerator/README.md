# 12_yolo_accel — YOLO n80 加速线活正典工程（M4 工程拆分产物）

日期：2026-10-07 ｜ 依据：`1_docs/yolov8_object_hardware_accel_replan_2026-10-05.md` §6（M4）｜
授权：用户 2026-10-07 明确指令"启动 M4 工程拆分"，三项结构裁决均按推荐落定。

## 定位

- 本工程 = YOLO 目标识别硬件加速线（nc=80）的**活正典树**，自 M4 起一切加速线
  代码改动落位于此（M5 图算子后端替换等）。
- **冻结关系**：`2_fpga\`（手势线 PL 基线，只读，本工程 RTL 为其边界scoped 冻结
  拷贝+SHA 台账）；`3_host\yolo_p2\`、`3_host\yolo_ppu\`（手势线 host 母本，降级
  历史基线，不再更新）；n80 历史 run 拷出件（`4_metrics\logs\2026-10-0*`）为归位
  来源，归位后新树为准。
- **v1 等价基线**：位流 `display_test_wrapper.bit`（SHA256 `4f4c8487…`，V2.3，
  母工程 `2_fpga\3_yolo_zynq\proj\DMA_gemm`，正典副本在
  `4_metrics\logs\2026-09-20_yolo_p1_3_run04_v23_bitstream\`）与板驱动
  `pl_m3.py`（`2026-10-06_yolo_m3_board_run01`）均**字节复用不改写**；
  M4 验收=PC 侧 G1-G5 与 M3 基线逐字节等价，不上板。

## M5 状态（2026-10-07 收官：图算子逐类迁入 PPU）

- **M5_PASS**：五门全绿（M5_XSIM/BIT/REHEARSE_PASS + BOARD_M5_L0..L4_PASS +
  M5_BOARDCROSS_PASS），板梯一次点火零返工（板内 89m30s）。
- **收官口径（用户裁定）**：板级全图逐字节 == M3 golden + 25 引擎任务全 PPU
  （add6/mp5 3/ups2 2/concat13/heads1）+ 16 view 别名；X9 跨档字节同一性
  = l0 全软件…l4 全 PPU 每任务 SHA 全等（板证 backend 无关性）。
- **位流演进**：V2.3 → **V2.4 `yolo_v24_m5.bit`**（SHA256 `5694b28c…`，conv
  路径原样 + PPU 岛@0x43C2 + HP1；PPU ID 0x594F4C32"YOL2"）。conv 绝不走
  PPU gemm 引擎（`ppu_f7_top` V1.8 stub 化）；地址图 `abi\address_map.md`
  补 0x43C2。
- **驱动**：新写 `ps_host\pl_m5.py`（backend 逐算子类阶梯开关；
  `pl_m3.py` 字节冻结零改动）；备料/排演链 `ps_host\` 下
  `ppu_packer_n80/f3_prep_n80/f7prep_n80/rehearse_m5_driver.py`。
- **RTL 台账**：M5 变更记 `rtl_ledger_m5.json`（`rtl_ledger.json` M4 版历史
  快照不可变）；实改点 = `ppu_engine_mux.v` heads_off 6 常量 n80 化 +
  `ppu_f7_top.v` V1.8 stub 化。
- 证据：`4_metrics\logs\2026-10-07_yolo_m5_{xsim,v24_bitstream,rehearse,board}_run01`；
  日志 `7_logs\2026-10-07\05_yolo_m5_close.md`。
- 二期边界（未做，另立项）：层间流水/ping-pong/跨层 overlap/heads 直排；
  RT1 实时流；S3e 须另授权。

## 五边界（replan §6 原文）

| 边界 | 内容 | 本树落位 |
|---|---|---|
| `yolo_gemm` | Conv、bias、requant、SiLU、W8A8 数据流 | `yolo_gemm\`（conv 载荷打包正典 + `rtl\` GEMM 边界 RTL 冻结拷贝） |
| `yolo_graph` | view、Concat、Add、Upsample、MaxPool 和静态 descriptor | `yolo_graph\`（图算子内核正典 + backend_map + `rtl\` PPU RTL 冻结拷贝） |
| `yolo_head` | reg/cls 六段装配、head buffer 和结果发布 | `yolo_head\`（heads 装配 + DFL/sigmoid/NMS） |
| `yolo_dma_csr` | AXI DMA、CSR、done/error、owner/generation 检查 | `yolo_dma_csr\`（递交律/屏障 + `rtl\` ps_axi_pl 冻结拷贝） |
| PS 编译器/驱动 | manifest、CMA、cache、阶段 barrier、golden/hash 和 DFL/NMS | `ps_host\`（p2_compiler 链 + graph_exec + prep/rehearse/crosscheck 工具链） |

第一版允许 PS 继续做图算子和调度；PL/PS 共享同一 buffer/descriptor/quant ABI
（正典在 `abi\`）；PS 不在层间读取、重排、写回 tensor。

## ABI 正典索引（`abi\`）

| 文件 | 内容 | 来源 |
|---|---|---|
| `address_map.md` | GEMM 0x43C00000 / CSR 0x43C10000 / DMA 0x40400000 寄存器图 | `2_fpga\3_yolo_zynq\hw_contract\address_map.md` 冻结拷贝 |
| `ppu_desc_bundle.py` | descriptor record 正典（word0-31、opcode、HEADS_SEG_ORDER） | `3_host\yolo_ppu\ppu_desc_bundle.py` → n80 拷出件归位 |
| 手册指针 | ppu/gemm/b3_dma_gemm/axi_lite_csr 四手册 + 段序 §8 | `1_docs\doc\`（引用不拷贝） |
| `kbm 合同` | K 链段（K≤1024→[K] 一般化，2026-10-06 定稿） | k_block_manifest schema + B1 修订档 |
| `m3_meta schema` | 板梯级合同 conv_statics/stage_table/anchors/heads_blob_sha256/ref_sha256 | prep_m3_board.py 产物 schema |

## 命名消歧（防后续会话混淆）

1. 边界名 `yolo_gemm` **承袭**现网位流实例 `u_yolo_gemm`（hwh 三从机
   axi_dma_0/u_yolo_gemm/u_yolo_csr，GEMM ID 0x20260919）——有意连续性，非撞车。
2. 本工程 M4 = replan §6 工程拆分；≠ 旧 PE/GEMM 线里程碑编号里的 M4（xbuf 门，
   见 `1_docs\doc\yolo7020_gemm_pe_architecture_2026-09-15.md`）。
3. "实时视频流检测"（历史文档曾误记为 M4）= M6+perf 量测后另立项，暂名 RT1。
4. M3 板上位流名 `display_test_wrapper` 继承自显示基线容器，PL 实为 YOLO GEMM
   overlay；工程 `proj\DMA_gemm\runs\` 内现存 impl bit 与正典 SHA 不同，正典以
   run04 归档副本为准。

## 遗留债登记（不属本工程处置）

- `2_fpga\3_yolo_zynq\proj\PPU_DMA_axi\`（S3d 母工程）整目录 untracked 未入库
  ——S3d 线遗留，单独立项；本工程只冻结拷贝其已入库 RTL 源（`rtl\ppu\`）。

## 纪律

- 证据：`4_metrics\logs\YYYY-MM-DD_yolo_m4*_runNN\` 四件套（README/console_extract/
  原始 log/激励+sha256），当日 `7_logs\` 四件套链接；判据 token 唯一
  （M4_G1_EQUIV_PASS … M4_G5_LEDGER_PASS，总判据 M4_SPLIT_PASS）。
- git：日常推个人支 `codex/full/pipidandan-superman`；重大节点 refspec 推 main
  （政策 v2）。
- venv：量化/编译 = `4_metrics\logs\2026-09-21_model_env_rebuild_run03\venv`
  （CPU 锁定），经 `3_host\model_env\run_python.ps1`。
- 禁改 ABI 语义；一切改动以 G1/G2 字节等价为牢，等价破了=改动错，不是基线错。
