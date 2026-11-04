/************************************************************************
 * File Name       : tb_ppu_f7.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_ppu_f7
 * Description     : PPU-F7 控制子系统顶层仿真（xsim 主证，三段流）：
 *                   DUT = ppu_f7_top 单实例，F6 的分件直驱全部撤除——
 *                   激励 100% 经 AXI4-Lite CSR（axi_lite_master_bfm）
 *                   打入：CTRL 脉冲 / DOORBELL 双落点 / DESC 队列 /
 *                   DMA_CFG / head_base / frame_id / 环 ack。五真表
 *                   （desc/buf/quant/lut/ring 的 BMG v8.4）载荷经
 *                   0x1000/0x3000/0x4000 窗口写入（含 win_base 两遍
 *                   算术证明），AXI4 数据面接 ppu_axi_bfm V1.2 金样。
 *
 *   程序形态（F7a 合同）：板上 GEMM 桩恒 err（无真引擎），故正程序
 *   = desc_table_A 的 25 个引擎任务（eng_q 原索引 {7,8,16,19,20,28,
 *   31,32,40,41,44,45,46,47,49,50,56,58,59,65,68,74,77,83,103}）紧凑
 *   化到槽 0..24（原索引均大于槽号，前向原地拷贝安全）；金样文件仍
 *   按原索引取（rd/wr_golden_f{fr}_{orig}.txt，复用 F6 prep 产物）。
 *   GEMM 描述符单独走负例（首错即停 → ERROR_STATUS bit10）。
 *
 *   四门：
 *     F7A 身份 + 全表窗口装载/回读 + 25 任务逐字节 + 队列空 DOORBELL
 *        ffe 发环 + CSR 可见结果面（seq/frame_id/bytes/ring_head/
 *        STATUS 位）+ ack 清环；
 *     F7B 事件语义（stop 温和/stop+last/abort 丢弃/ffe 中途强发环）
 *        + GEMM 桩 err→bit10 粘着→soft_reset 恢复 + D1/D2/D3 三种
 *        描述符错拼接（槽位化）；
 *     F7C 5 帧 × 25 任务连发不复位（帧参数化金样，每帧 CSR 换
 *        frame_id + BFM 换 preload，帧 1 后 1 次 ack）；
 *     F7D 表锁守卫（运行期四窗口写 → SLVERR + bits3-6 + 表内容不
 *        变）+ 环 RO/坏区/非对齐（SLVERR + bit0/bit9）+ 环容量边界
 *        （31 入环 + 第 32 溢出 + 排空 + 空环 ack 错）。
 *
 *   复用律：滑动金样窗/等待原语/看门狗/X-Z 守卫/标记协议逐字沿
 *   tb_ppu_f6.sv（正典），内部信号经层次引用（dut.*）观测。
 * Dependencies    : ppu_f7_top.v 及其全树、axi_lite_master_bfm.sv、
 *                   ppu_axi_bfm.sv、真 BMG 仿真网表（run-local）。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版。
 *   - V1.1 (2026-09-28) by LSL : P2.2 F7 换装——DUT 挂 ppu_gemm_engine
 *                 V1.3 + 第二 DMA（m1_axi）。TB 增第二 ppu_axi_bfm 实例
 *                 gbfm（独立 cfg 寄存器组）；B5 负例改真引擎非法 K
 *                 desc（K=999 → E_GEOM 拒绝，m1_axi 零拍，shell 台账
 *                 不变）；新增 F7G 门（K576 全卷金像对拍 + 写相位 abort
 *                 → E_ABORTD 冲刷/wash → 整卷重跑）。冲刷拍 strb=00 为
 *                 P2.2 正典（零字节写），BFM 严格 strb 检查在冲刷窗内
 *                 以 g_cfg_check_en 屏蔽——拍级冲刷精确性由单元门
 *                 tb_ppu_gemm_engine V1.2 证明，本门证系统级收口。
 *   - V1.2/V1.3 (2026-09-28) by LSL : 调试面——GFACE 引擎内面打印与
 *                 WDBG 事件触发面（§5.3 CLOBBER 定位轮引入，行内注记）。
 *   - V1.4 (2026-09-28) by LSL : P2.3 红灯取证场景 F7S（不改既有门）：
 *                 GEMM desc 槽>=1 取数跨距（walker 32 vs 引擎 16）双腿
 *                 实证——A 腿槽1 无影子→引擎 16 跨址抓全 0→bit10+
 *                 err_info{port=5,code=02}+m1 台账停单卷（desc_id 字段
 *                 walker 引擎错路径未锁存恒 0——钉当前，修复批次补接线
 *                 后改期 1）；B 腿仅追加
 *                 影子 5 字于 16 跨址（表字 19/20/24/26/27=槽0 保留区）
 *                 →双卷干净+末写 y=金像（机制对照闭环）。判据钉住
 *                 当前缺陷行为——P2.3 修复后本场景随修复同批改绿
 *                 （A 腿改期双卷干净、影子撤除）。
 *   - V1.5 (2026-09-28) by LSL : 子图梯一级混合程序场景 F7M——conv@槽0
 *                 （引擎，F7G 正典 K576 字，无 last）+ 25 PPU 任务紧凑到
 *                 槽 1..25（producer 重映射 orig→槽+1 域，last 在槽 25
 *                 原生位）。证明面：walker 按 op 混合派发 + 引擎成功卷
 *                 完成前零 PPU 派发（顺序屏障钉）+ 双引擎台账隔离
 *                 （gbfm=单卷正典 553088/3200，bfm=25 任务逐字节金样）
 *                 + 混合 w14 环账（conv 25600+ΣPPU）+ CSR 结果面。不证
 *                 面：同帧跨引擎数据流（conv y→PPU 入）——TB 双 BFM 独
 *                 立 memory 模型不可见（建模局限非 RTL 缺陷，板真值同
 *                 DDR）；层间数据流待 P2.3 修复后子图二级（种子法，
 *                 P23_MERGE_DESIGN §4/§6）。
 *   - V1.6 (2026-09-28) by LSL : P2.3 修复验证批（引擎 V2.0 跨距 32 +
 *                 walker V3.1 引擎错上下文锁存）——F7S 整体改写 V2 三
 *                 腿：F7S-1 双卷独立区不同负载（槽0 arena A + 槽1
 *                 arena B 块轮转镜像，金像=块轮转金像；旧 16 跨址落点
 *                 表字 19/20/24/26/27 预置毒值 K=4095——旧码必红、新
 *                 码零消费驻留）、F7S-2 C 负例 GEMM 面（槽1 合法
 *                 opcode+非法 K=999 → ERROR_INFO port5/desc_id=1/
 *                 op=01/code=02——旧码 desc_id 恒陈旧 0）、F7S-3 恢复
 *                 双卷复证；新增 f7s_check_dual 双区 y 对拍（contain-
 *                 ment+strb FF+无重复写+两区各 320B 块金像）。F7M 扩
 *                 三段：M2 = 25 PPU 先行 + conv@槽25（非零槽 GEMM 派发
 *                 +desc 口 B 让渡收口+屏障钉 done=25）、M3 = 槽2 PPU
 *                 读流 SLVERR 注入（cfg_fault_r_beat 活值 arm）→
 *                 ERROR_INFO 上下文（PPU 面 desc_id=2/op=槽2 w0）→
 *                 soft_reset 恢复整帧重跑（conv@25 复证）。V1.4 的
 *                 F7S 红灯取证判据（A 腿期错/B 腿影子喂对）随修复退役，
 *                 由本 V2 判据接替。
 *   - V1.6.1 (2026-09-29) by LSL : V1.6 首轮 F7S 红（errors=5）两律修正
 *                 ——判据错非 RTL 错（数据面/上下文/台账全绿）：
 *                 (1) 环续行律：环 seq/head/tail/entries 穿 csr_soft 持续，
 *                 仅 ack 消费条目；do_reset 才全清（新起 seq=1）。F7S-3
 *                 期 seq=2/条目@1/head=2/ack@2；M2 期 seq=2/ack@2；M3R 第
 *                 三次发环期 seq=3/条目@2/head=3/ack@3（M1 do_reset 新起
 *                 维持 seq=1 不变）。
 *                 (2) 错误驻留态：引擎错后 walker 停在错误保持态（非
 *                 W_IDLE，soft_reset 方出）——check_no_resume 的 idle 条
 *                 件在该态恒假。新增 check_frozen 任务（done 冻结 + PPU/
 *                 GEMM 日志零增长），F7S-2/F7M3 两处换用。
 *   - V1.6.2 (2026-09-29) by LSL : f7p23c/f7p23d 轮 F7M 两类判据修正
 *                 （M2 数据面首轮已全对——环账/台账/y 精确，全为 TB 错）：
 *                 (1) 逐帧日志律：csr_start_frame 开头清 gemm_log_q/
 *                 ppu_log_q（TB:488，B5 门 TB:1241 同律先例）——M2/M3/M3R
 *                 七处派发面判据误按跨帧累计写（期 50/53/78/2/3），改本
 *                 帧语义（期 25/3/25/1/1，索引去 N_PROG 偏移）。
 *                 (2) 传输级错恢复律：SLVERR 后 shell/DMA 错粘着至硬复位
 *                 （ppu_dma_master err_r/halted 仅 rst_i 清，shell 头注
 *                 "halt 至复位"；soft_reset 只达 regf/walker/ring，
 *                 u_shell.rst_i=rst_hi_w）——软复位后重启帧=派发进错误
 *                 保持的 shell → 新引擎错 → W_ERR 死锁（f7p23d 实测
 *                 errsts 复 0x400、errinfo 05/00/11/02、done 恒 0）。
 *                 M3R 恢复改硬复位新纪元（环 do_reset 全清 seq=1/条目@0/
 *                 head=1/ack@1，区别于软复位续行律）；F7S-3（EC_GEOM
 *                 引擎前错、shell 未涉）软复位恢复仍为正典。
 *   - V1.6.3 (2026-09-29) by LSL : f7p23e 轮 M3R 发环超时取证与环孔径
 *                 停泊律。(1) 停泊律：环孔口 A 常读 rd_addr_w[10:2]
 *                 （ppu_f7_top:473，BRAM ena 恒 1）——任何 CSR 读都会把
 *                 孔径停泊在其地址字；M3R 复位检查读 ERROR_STATUS=0x018
 *                 停泊字 6 恰入 entry@0 写域，新纪元发布 w6 同址读写冲突
 *                 （t=169.270695 全 run 唯一环冲突；F7S 绿轮 A=0/B=0 冲突
 *                 佐证环冲突不阻发布——两轮各 4 起表预载冲突为既有良性
 *                 模式）。发布前补读 DESC_DONE_COUNT(0x11C→字 71) 停泊
 *                 孔径于写域外（TB 不制造冲突访问铁律）。(2) 取证探针：
 *                 RING_PUB_DONE evt 逐拍打印 + wait_ring_pub 超时面倾倒
 *                 （环 FSM 态/头尾/seq/walker 态）。
 *   - V1.6.4 (2026-09-29) by LSL : f7p23f 探针闭合 M3R 红根因——新纪元
 *                 计数律。RING_PUB_DONE/RINGWAIT_DUMP 实测：第三发环已在
 *                 t=169.270805 完成发布（head=1/seq=1/ring R_IDLE/walker
 *                 W_IDLE/done=26，全合 V1.6.2 新纪元设计值；停泊律修复同
 *                 轮零冲突生效）——DUT 无错，红在 TB 累计判据：cfg_default
 *                 （TB:562）随新纪元清零纪元计数器，第三发环 cnt 自 0→1
 *                 而非 2→3、恢复帧 eng_evt_cnt=0 而非 1。判据改新纪元语
 *                 义：wait_ring_pub 期 1、eng_evt_cnt 期 0。
 *   - V1.7 (2026-09-29) by LSL : 软复位恢复语义加固判别批（用户指令
 *                 "1+2 合并改，走全链回归"；RTL=ppu_dma_master V1.3
 *                 钳位 + ppu_f7_top V1.7 shell wash）：
 *                 F7S-4（案 1 判别）——soft 后不重写 A_DMA_CFG（保持擦洗
 *                 0，回读钉 0）→ 双卷重跑期绿+环续行 seq=3/条目@2/head=3。
 *                 旧码：outst=0 零事务（ppu_dma_master:140 门恒假）+
 *                 timeout=0 看门狗关（:167）→ E_PRMREQ 静默死等
 *                 wait_walk_done 超时红——板探针 2/3 楔死面首次仿真复现
 *                 （原 TB 每处 soft 后必 cfg_csr_default 掩盖此径）。
 *                 M3S（案 2 判别，M3R 后增）——再注 SLVERR 得同 M3 错误面
 *                 → 软复位恢复（撤注入+soft+cfg_csr_default，无 do_reset）
 *                 → 整帧 26 任务重跑绿 + 环续行 seq=2/条目@1/head=2。
 *                 旧码：派发进错误保持 shell → 新引擎错 → W_ERR 死锁红
 *                 （V1.6.2 实测面，M3R 硬复位律仅回归保留）。M3R 全部
 *                 判据零改。
 *                 B8 末检查语义翻转——旧钉"soft_reset 不得释放 shell halt
 *                 （复位分层）"随案 2 废除（该语义即死锁根因），新钉：
 *                 soft 须以 shell wash 释放 halt；checks 总数不变（414）。
 *   - V1.8 (2026-09-29) by LSL : 排干收口判别批（授权轮 run02；RTL=
 *                 ppu_dma_master V1.4 三件——wq_occ_r 占用计数排干门 /
 *                 WLAST 稳定 / halted 账目前置；单元见证件
 *                 2026-09-29_dma_drain_unit_run01 三缺陷独立复现）：
 *                 (1) M3S 排干落定闸扩全量——wash 前置条件由 AR/AW 在
 *                 途扩至 +wq_occ_r/wvalid_o + BFM 账目（aw_addr_q/
 *                 w_expect/b_resp_q/bvalid/ar_addr_q/r_run/rvalid 全零
 *                 =互连侧无幻影的直接证明）；闸红时倾倒 16 项遥测后
 *                 $finish（不 wash、不带病续跑——授权纪律"超时必 FAIL
 *                 不得续 wash"）。(2) F7M 专属 AXI W payload 稳定性
 *                 监控（wvalid 挂起期 wdata/wstrb/wlast 逐拍冻结，违例
 *                 记 error；不进 checks——F7A-D/G 钉数零扰）。(3) M2
 *                 窗 cfg_w_stall=3（系统级背压面，内容不变仅时序）。
 *                 (4) 撤 V1.7-PROBE 三处（m3s_probe_q/probe always 块/
 *                 arm——诊断已定案 wq 占位 4 歧义，sfhr F7M 绿
 *                 chk=1926 后正典跑前撤；probe 仅 display 不入 checks）。
 *   - V1.9 (2026-09-30) by LSL : 子图梯二级 F7L2（P23_MERGE_DESIGN §6.2
 *                 种子法；prep=2026-09-30_yolo_p2_l2sub_run01）——conv0@槽0
 *                 （model.9.cv1 真网 K256 1×1）→ mp5@槽1（desc44 正典字
 *                 verbatim，producer 重映射 43→0/44→1 于 prep 产）→
 *                 conv1@槽2（synthetic K1152 oc24 借 model.8.m.0.cv1 前
 *                 24 行，valid+last）。证明面：引擎→shell→引擎 反向衔接
 *                 双向顺序屏障（mp5 完成前 conv1 零派发=首证）+ 同帧跨
 *                 引擎数据流种子法建模（gbfm 预载 mirror×2+param×2、
 *                 bfm 预载 buf44 span=oracle y43；V1.5 建模局限的正面
 *                 收口）+ mp5 rd/wr 金像逐拍（F6 正典复用）+ y0/y1 gather
 *                 紧凑金像（f7l2_check_y 参数化双窗）+ 混合环账 28000 +
 *                 台账钉值 grd=226852/gwr=1900/rd=1600/wr=1600。
 *   - V1.10 (2026-09-30) by LSL : B3-S3 S3a-W walker 多 desc 协议专证门
 *                 F7W（AUDIT 2026-09-30_b3s3_claude_audit_run01 裁定二/
 *                 可执行修订：单帧多 desc 与真实级联门 S3a-R 分立正名，
 *                 标签 WALKER_MULTI_DESC_PASS，不称 L2_CHAIN_PASS）。
 *                 数据面复用 F7L2 prep 零新增；W2 仅槽2 w0 清 last。
 *                 W1 三 desc 末 last 闭帧协议面：done 逐 desc 累计 1→2→3、
 *                 HEAD=3/CURRENT=2、last 完成前零发环、单环条目
 *                 bytes=Σw14、闭帧后表窗解锁正面（bresp OKAY——F7D 只证
 *                 锁住负面）。W2 三 desc 无 last + ffe 闭帧（S3b 起宿主桥
 *                 帧板级同构；L2 板仅单 desc 帧踩过）：停泊 W_CHK 非
 *                 idle/RUNNING=1/DESC_EMPTY=1、停泊期 W_BUF 写 SLVERR+
 *                 错位 bits3-6、环孔停泊正典（0x11C 预读）、ffe 发环
 *                 bytes=Σw14/fid 跟帧/环续行 seq、IDLE、解锁+表内容不变、
 *                 W1C 清错面、双帧台账×2（rd=3200/wr=3200/grd=453704/
 *                 gwr=3800）。既有门零改动。
 *   - V1.11 (2026-10-01) by LSL : B3-S3 S3b-W 首段窗门 F7SB（设计书
 *                 S3B_DESIGN.md v1 §PASS-2；用户 2026-10-01 授权执行，
 *                 板门 S3b-R 未授权）。7 硬件段各一独立 ffe 帧（每帧
 *                 1 desc@槽0 无 last）：f0/f1=model.0 winA/winB（K27 双窗
 *                 Wo160 分段）、f2=model.1、f3=2.cv1、f4/f5=m.0.cv1/cv2、
 *                 f6=2.cv2。每帧：desc 槽0 装载回读+设计表钉字、镜像
 *                 并集区逐段重打包预载（板同构 M=0x10000000 单区）、
 *                 帧始 DONE_COUNT 清零直接证据、停泊 W_CHK/表锁 SLVERR/
 *                 0x11C 孔停泊读、ffe 发环 bytes=w14/seq 续行/fid 跟帧、
 *                 解锁正面+W1C、y 写日志重建对金像+外排 f7sb_y_got_k.hex
 *                 （PC 面 verify_s3bw_bridge.py 硅字节重算真实 PS 桥，
 *                 SV 零律复制）、逐帧台账 EGRD/EGWR/shell 0-0、环 ack。
 *                 逐帧 clear_logs（winA/winB 同 y 基址，跨帧日志必混）；
 *                 累计账 S3BW_LEDGER 行钉 ΣEGRD=2026064/ΣEGWR=153600。
 *                 标签 S3B_WINDOW_SIM_PASS。既有门零改动。
 ************************************************************************/
`timescale 1ns / 1ps

module tb_ppu_f7;

    // ================= 时钟/复位 =================
    reg clk_r = 1'b0;
    reg rstn_r = 1'b0;               // BD aresetn 语义（异步低）
    wire rst_hi_w = ~rstn_r;         // shell/桩/BFM 极性
    always #5 clk_r = ~clk_r;        // 100 MHz

    // ================= 双流标记门控 =================
    reg    vivado_flow = 1'b0;
    string flow_s;
    string prep_dir, run_s;
    integer xz_err = 0;
    integer fj;

    // ================= CSR 地址镜像（yolo_csr_pkg，keep in sync）=================
    localparam [15:0] A_ID              = 16'h000;
    localparam [15:0] A_VERSION         = 16'h004;
    localparam [15:0] A_CTRL            = 16'h010;
    localparam [15:0] A_STATUS          = 16'h014;
    localparam [15:0] A_ERROR_STATUS    = 16'h018;   // W1C
    localparam [15:0] A_ERROR_INFO      = 16'h01C;
    localparam [15:0] A_FRAME_ID        = 16'h028;
    localparam [15:0] A_HEAD_BASE_LO    = 16'h040;
    localparam [15:0] A_HEAD_BASE_HI    = 16'h044;
    localparam [15:0] A_HEAD_BYTES      = 16'h04C;
    localparam [15:0] A_HEAD_FORMAT     = 16'h050;
    localparam [15:0] A_RESULT_SEQ      = 16'h054;
    localparam [15:0] A_RESULT_FRAME_ID = 16'h058;
    localparam [15:0] A_RESULT_ACK      = 16'h060;   // bit0/1/2 = consume/drop/retry
    localparam [15:0] A_RESULT_RING_HEAD= 16'h064;
    localparam [15:0] A_RESULT_RING_TAIL= 16'h068;
    localparam [15:0] A_DESC_CFG        = 16'h100;   // depth[7:0], circular[16]
    localparam [15:0] A_DESC_BASE       = 16'h104;   // win_base[11:0]
    localparam [15:0] A_DESC_COUNT      = 16'h108;
    localparam [15:0] A_DESC_HEAD       = 16'h10C;
    localparam [15:0] A_DESC_TAIL       = 16'h110;
    localparam [15:0] A_DESC_DOORBELL   = 16'h114;   // bit0 commit, bit1 ffe
    localparam [15:0] A_DESC_CURRENT    = 16'h118;
    localparam [15:0] A_DESC_DONE_COUNT = 16'h11C;
    localparam [15:0] A_DESC_ERROR_ID   = 16'h120;
    localparam [15:0] A_DMA_CFG         = 16'h200;

    localparam [31:0] YOLO_ID_VALUE  = 32'h594F4C32; // "YOL2"
    localparam [31:0] YOLO_VERSION   = 32'h0000_0300;

    // ================= 程序表（F7a：25 引擎任务紧凑化）=================
    localparam int N_PROG = 25;
    int PROG [0:N_PROG-1];

    // ================= AXI-Lite 主 BFM 互连 =================
    wire [31:0] lite_awaddr, lite_wdata, lite_araddr, lite_rdata;
    wire        lite_awvalid, lite_awready, lite_wvalid, lite_wready;
    wire        lite_bvalid, lite_bready, lite_arvalid, lite_arready;
    wire        lite_rvalid, lite_rready;
    wire [1:0]  lite_bresp, lite_rresp;

    axi_lite_master_bfm mcsr (
        .aclk        (clk_r),
        .aresetn     (rstn_r),
        .awaddr      (lite_awaddr),
        .awvalid     (lite_awvalid),
        .awready     (lite_awready),
        .wdata       (lite_wdata),
        .wstrb       (),
        .wvalid      (lite_wvalid),
        .wready      (lite_wready),
        .bresp       (lite_bresp),
        .bvalid      (lite_bvalid),
        .bready      (lite_bready),
        .araddr      (lite_araddr),
        .arvalid     (lite_arvalid),
        .arready     (lite_arready),
        .rdata       (lite_rdata),
        .rresp       (lite_rresp),
        .rvalid      (lite_rvalid),
        .rready      (lite_rready),
        .last_bresp_o(),
        .last_rdata_o(),
        .last_rresp_o()
    );

    // ================= AXI4 数据面 BFM（ppu_axi_bfm V1.2）=================
    wire [31:0] araddr_w, awaddr_w;
    wire [3:0]  arlen_w, awlen_w;
    wire [2:0]  arsize_w, awsize_w;
    wire [1:0]  arburst_w, awburst_w;
    wire        arvalid_w, arready_w, rvalid_w, rready_w, rlast_w;
    wire [63:0] rdata_w;
    wire [1:0]  rresp_w;
    wire        awvalid_w, awready_w, wvalid_w, wready_w, wlast_w;
    wire [63:0] wdata_w;
    wire [7:0]  wstrb_w;
    wire [1:0]  bresp_w;
    wire        bvalid_w, bready_w;

    wire [63:0] bfm_rd_cnt, bfm_wr_cnt;
    integer bfm_proto_err, bfm_unloaded;
    integer cfg_r_lat, cfg_fault_r_beat, cfg_stall_after;
    reg [1:0] cfg_fault_r_resp;
    integer cfg_fault_b_req, cfg_b_delay, cfg_w_stall;
    reg cfg_check_en;
    // V1.3（sfh 第 5 轮）：master 写排干零 strobe 拍豁免窗（仅 M3S
    // 错误保持期置 1，撤注入即清 0——排干拍落此窗内）
    reg bfm_zero_strb_ok_r = 1'b0;

    ppu_axi_bfm bfm (
        .clk_i(clk_r), .rst_i(rst_hi_w),
        .arvalid_i(arvalid_w), .arready_o(arready_w),
        .araddr_i(araddr_w), .arlen_i(arlen_w),
        .rvalid_o(rvalid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w), .rready_i(rready_w),
        .awvalid_i(awvalid_w), .awready_o(awready_w),
        .awaddr_i(awaddr_w), .awlen_i(awlen_w),
        .wvalid_i(wvalid_w), .wready_o(wready_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w), .wlast_i(wlast_w),
        .bvalid_o(bvalid_w), .bresp_o(bresp_w), .bready_i(bready_w),
        .cfg_r_lat(cfg_r_lat), .cfg_fault_r_beat(cfg_fault_r_beat),
        .cfg_fault_r_resp(cfg_fault_r_resp),
        .cfg_stall_after(cfg_stall_after),
        .cfg_fault_b_req(cfg_fault_b_req), .cfg_b_delay(cfg_b_delay),
        .cfg_w_stall(cfg_w_stall), .cfg_check_en(cfg_check_en),
        .cfg_zero_strb_ok(bfm_zero_strb_ok_r),
        .rd_cnt(bfm_rd_cnt), .wr_cnt(bfm_wr_cnt),
        .proto_err(bfm_proto_err), .unloaded_cnt(bfm_unloaded)
    );

    // ================= GEMM 数据面 BFM（P2.2：m1_axi 第二实例）=================
    wire [31:0] g_araddr_w, g_awaddr_w;
    wire [3:0]  g_arlen_w, g_awlen_w;
    wire [2:0]  g_arsize_w, g_awsize_w;
    wire [1:0]  g_arburst_w, g_awburst_w;
    wire        g_arvalid_w, g_arready_w, g_rvalid_w, g_rready_w, g_rlast_w;
    wire [63:0] g_rdata_w;
    wire [1:0]  g_rresp_w;
    wire        g_awvalid_w, g_awready_w, g_wvalid_w, g_wready_w, g_wlast_w;
    wire [63:0] g_wdata_w;
    wire [7:0]  g_wstrb_w;
    wire [1:0]  g_bresp_w;
    wire        g_bvalid_w, g_bready_w;

    wire [63:0] gbfm_rd_cnt, gbfm_wr_cnt;
    integer gbfm_proto_err, gbfm_unloaded;
    integer g_cfg_r_lat, g_cfg_fault_r_beat, g_cfg_stall_after;
    reg [1:0] g_cfg_fault_r_resp;
    integer g_cfg_fault_b_req, g_cfg_b_delay, g_cfg_w_stall;
    reg g_cfg_check_en;

    ppu_axi_bfm gbfm (
        .clk_i(clk_r), .rst_i(rst_hi_w),
        .arvalid_i(g_arvalid_w), .arready_o(g_arready_w),
        .araddr_i(g_araddr_w), .arlen_i(g_arlen_w),
        .rvalid_o(g_rvalid_w), .rdata_o(g_rdata_w),
        .rresp_o(g_rresp_w), .rlast_o(g_rlast_w), .rready_i(g_rready_w),
        .awvalid_i(g_awvalid_w), .awready_o(g_awready_w),
        .awaddr_i(g_awaddr_w), .awlen_i(g_awlen_w),
        .wvalid_i(g_wvalid_w), .wready_o(g_wready_w),
        .wdata_i(g_wdata_w), .wstrb_i(g_wstrb_w), .wlast_i(g_wlast_w),
        .bvalid_o(g_bvalid_w), .bresp_o(g_bresp_w), .bready_i(g_bready_w),
        .cfg_r_lat(g_cfg_r_lat), .cfg_fault_r_beat(g_cfg_fault_r_beat),
        .cfg_fault_r_resp(g_cfg_fault_r_resp),
        .cfg_stall_after(g_cfg_stall_after),
        .cfg_fault_b_req(g_cfg_fault_b_req), .cfg_b_delay(g_cfg_b_delay),
        .cfg_w_stall(g_cfg_w_stall), .cfg_check_en(g_cfg_check_en),
        .cfg_zero_strb_ok(1'b0),   // gdma 无错误注入面，全严
        .rd_cnt(gbfm_rd_cnt), .wr_cnt(gbfm_wr_cnt),
        .proto_err(gbfm_proto_err), .unloaded_cnt(gbfm_unloaded)
    );

    // ---- P2.2 F7G 写径诊断（事件触发面，run=F7G 才开）---------------------
    // M5.1（2026-10-07）：u_gemm 层级探针在 stub 化（ppu_gemm_stub_f7）下
    // 不存在，xsim 静态展开仍解析层级名 → elaboration 失败。F7G/F7M 面
    // 与 M5 无关（真引擎回插时编不带 PPU_F7_GEMM_STUB 定义即恢复全探针）。
`ifndef PPU_F7_GEMM_STUB
    // E_YARM=15 / E_CHKY1=31（引擎 FSM 局部参数值）：
    //   CHKY1 采样拍 = wr_done_seen 零等待判决拍，全写径状态一屏；
    //   WRD 脉冲迹 = u_gdma.wr_done_o 实际落拍（CHKY1 之后才来=纯竞态，
    //   永不来=结构楔死）；YARM 迹 = 每块写请求受理拍。
    always @(posedge clk_r) if (run_s == "F7G" && !rst_hi_w) begin
        if (dut.u_gemm.state == 6'd15 && dut.u_gemm.wr_req_valid_o
            && dut.gdw_req_ready_w)
            $display("[%0t] WDBG YARM blk=%0d addr=%08X len=%0d",
                     $time, dut.u_gemm.blk, dut.u_gemm.wr_addr_o,
                     dut.u_gemm.wr_len_o);
        if (dut.u_gemm.state == 6'd31)
            $display("[%0t] WDBG CHKY1 blk=%0d ycnt=%0d btt=%0d wds=%b | eng: yarm=%b wv=%b wrdy=%b ysent=%0d yfifo=%0d | gdma: wact=%b warl=%0d awout=%0d awc=%0d bc=%0d wsent=%0d wib=%0d awv=%b bv=%b wrdy0=%b err=%b | gbfm: wrn=%0d wexp=%0d awq=%0d bq=%0d bv=%b wrdy=%b perr=%0d",
                     $time, dut.u_gemm.blk,
                     dut.u_gemm.u_gemm.y_last_r, dut.u_gemm.btt_w,
                     dut.u_gemm.wr_done_seen,
                     dut.u_gemm.y_armed, dut.gdw_beat_valid_w,
                     dut.gdw_beat_ready_w, dut.u_gemm.y_sent_q,
                     dut.u_gemm.u_gemm.yfifo_cnt,
                     dut.u_gdma.wr_act_r, dut.u_gdma.war_left_r,
                     dut.u_gdma.aw_out_r, dut.u_gdma.aw_cnt_r,
                     dut.u_gdma.b_cnt_r, dut.u_gdma.w_sent_r,
                     dut.u_gdma.w_in_bst_r, g_awvalid_w, g_bvalid_w,
                     dut.gdw_req_ready_w, dut.u_gdma.err_r,
                     gbfm.wr_n, gbfm.w_expect, gbfm.aw_addr_q.size(),
                     gbfm.b_resp_q.size(), gbfm.bvalid_o, gbfm.wready_o,
                     gbfm_proto_err);
        if (dut.gd_wr_done_w)
            $display("[%0t] WDBG WRD blk=%0d wds=%b gbfm_wrn=%0d",
                     $time, dut.u_gemm.blk, dut.u_gemm.wr_done_seen,
                     gbfm.wr_n);
    end
`endif  // PPU_F7_GEMM_STUB

    // ================= DUT =================
    ppu_f7_top dut (
        .s_axi_aclk   (clk_r),
        .s_axi_aresetn(rstn_r),
        .s_axi_awaddr (lite_awaddr),
        .s_axi_awprot (3'h0),
        .s_axi_awvalid(lite_awvalid),
        .s_axi_awready(lite_awready),
        .s_axi_wdata  (lite_wdata),
        .s_axi_wstrb  (4'hF),
        .s_axi_wvalid (lite_wvalid),
        .s_axi_wready (lite_wready),
        .s_axi_bresp  (lite_bresp),
        .s_axi_bvalid (lite_bvalid),
        .s_axi_bready (lite_bready),
        .s_axi_araddr (lite_araddr),
        .s_axi_arprot (3'h0),
        .s_axi_arvalid(lite_arvalid),
        .s_axi_arready(lite_arready),
        .s_axi_rdata  (lite_rdata),
        .s_axi_rresp  (lite_rresp),
        .s_axi_rvalid (lite_rvalid),
        .s_axi_rready (lite_rready),
        .m_axi_araddr (araddr_w), .m_axi_arlen(arlen_w),
        .m_axi_arsize (arsize_w), .m_axi_arburst(arburst_w),
        .m_axi_arvalid(arvalid_w), .m_axi_arready(arready_w),
        .m_axi_rdata  (rdata_w), .m_axi_rresp(rresp_w),
        .m_axi_rlast  (rlast_w), .m_axi_rvalid(rvalid_w),
        .m_axi_rready (rready_w),
        .m_axi_awaddr (awaddr_w), .m_axi_awlen(awlen_w),
        .m_axi_awsize (awsize_w), .m_axi_awburst(awburst_w),
        .m_axi_awvalid(awvalid_w), .m_axi_awready(awready_w),
        .m_axi_wdata  (wdata_w), .m_axi_wstrb(wstrb_w),
        .m_axi_wlast  (wlast_w), .m_axi_wvalid(wvalid_w),
        .m_axi_wready (wready_w),
        .m_axi_bresp  (bresp_w), .m_axi_bvalid(bvalid_w),
        .m_axi_bready (bready_w),
        .m1_axi_araddr  (g_araddr_w), .m1_axi_arlen(g_arlen_w),
        .m1_axi_arsize  (g_arsize_w), .m1_axi_arburst(g_arburst_w),
        .m1_axi_arvalid (g_arvalid_w), .m1_axi_arready(g_arready_w),
        .m1_axi_rdata   (g_rdata_w), .m1_axi_rresp(g_rresp_w),
        .m1_axi_rlast   (g_rlast_w), .m1_axi_rvalid(g_rvalid_w),
        .m1_axi_rready  (g_rready_w),
        .m1_axi_awaddr  (g_awaddr_w), .m1_axi_awlen(g_awlen_w),
        .m1_axi_awsize  (g_awsize_w), .m1_axi_awburst(g_awburst_w),
        .m1_axi_awvalid (g_awvalid_w), .m1_axi_awready(g_awready_w),
        .m1_axi_wdata   (g_wdata_w), .m1_axi_wstrb(g_wstrb_w),
        .m1_axi_wlast   (g_wlast_w), .m1_axi_wvalid(g_wvalid_w),
        .m1_axi_wready  (g_wready_w),
        .m1_axi_bresp   (g_bresp_w), .m1_axi_bvalid(g_bvalid_w),
        .m1_axi_bready  (g_bready_w),
        .irq_o        ()
    );

    // ================= 内部观测（层次引用，检查不改激励面）=================
    wire wk_idle_w   = dut.walker_idle_w;
    wire wk_run_w    = dut.walker_busy;
    wire [15:0] wk_head_w = dut.walker_head_w;
    wire [15:0] wk_done_w = dut.walker_done_w;
    wire [15:0] wk_errid_w = dut.walker_err_id_w;
    wire busy_w      = dut.sh_busy_w;
    wire stopped_w   = dut.sh_stopped_w;
    wire eng_busy_w  = dut.sh_eng_busy_w;
    wire ring_ne_w   = dut.ring_not_empty_w;
    wire [7:0] ring_head_w = dut.ring_head_ptr_w;
    wire [31:0] ring_seq_w = dut.ring_seq_w;
    wire [31:0] ring_fid_w = dut.ring_frame_id_w;
    wire [31:0] ring_bytes_w = dut.ring_head_bytes_w;
    wire ring_ready_w = dut.pub_ready_w;
    wire ffe_pend_w  = dut.frame_end_pending_w;

    // ================= 表 ROM（TB 侧源阵列，经窗口写灌入真表）=================
    reg [31:0] desc_rom [0:4095];
    reg [31:0] buf_rom  [0:1023];
    reg [31:0] qt_rom   [0:1023];
    reg [31:0] gemm_desc0 [0:31];     // 原始 desc0（conv）留档：GEMM 桩负例用

    // ================= 事件计数 =================
    integer ring_pub_cnt, ring_ovf_cnt, ring_ack_cnt;
    integer shell_pub_cnt, desc_evt_cnt, eng_evt_cnt;
    integer errors, checks;
    reg [7:0] desc_evt_op, desc_evt_id;
    reg [3:0] ldr_step_l, ldr_bit_l;          // DBG：loader 判决明细锁存
    reg [7:0] ldr_code_l;
    int gemm_log_q [$];
    int ppu_log_q [$];

    always @(posedge clk_r) begin
        if (!rst_hi_w) begin
            if (dut.ring_publish_evt_w) begin
                ring_pub_cnt = ring_pub_cnt + 1;
                // V1.6.3 evt 探针：每次发环完成拍落一行（f7p23e M3R 超时取证）
                $display("[%0t] RING_PUB_DONE cnt->%0d head=%0d seq=%0d",
                         $time, ring_pub_cnt, dut.u_ring.head_ptr_o,
                         dut.ring_seq_w);
            end
            if (dut.ring_overflow_evt_w) ring_ovf_cnt = ring_ovf_cnt + 1;
            if (dut.ring_ack_err_evt)    ring_ack_cnt = ring_ack_cnt + 1;
            if (dut.u_shell.ring_publish_o) shell_pub_cnt = shell_pub_cnt + 1;
            if (dut.walker_err_evt) begin
                desc_evt_cnt = desc_evt_cnt + 1;
                desc_evt_op  = dut.walker_err_op_w;
                desc_evt_id  = dut.walker_err_desc_w;
            end
            if (dut.walker_eng_evt) eng_evt_cnt = eng_evt_cnt + 1;
            if (dut.sh_ldr_ev_w) begin
                ldr_step_l = dut.sh_ldr_step_w;
                ldr_bit_l  = dut.sh_ldr_bit_w;
                ldr_code_l = dut.sh_ldr_code_w;
            end
            if (dut.wk_greq_w) gemm_log_q.push_back(dut.wk_gidx_w);
        end
    end

    // ---- DBG（临时）: 从机写脉冲 + regfile 写提交全记录 -----------------
    // 定位“复位后第一笔 CTRL 写丢失”：三层各打一枪，跑一遍即可分层。
    always @(posedge clk_r) begin
        if (rstn_r && dut.u_slave.wr_valid_o)
            $display("[%0t] DBG slv_wr: a=%03X regf_gate=%b",
                     $time, dut.u_slave.wr_addr_o, dut.wr_regf);
    end
    always @(posedge clk_r) begin
        if (rstn_r && dut.u_regf.csr_wr_valid_i)
            $display("[%0t] DBG regf_wr: a=%03X d=%08X",
                     $time, dut.u_regf.csr_wr_addr_i, dut.u_regf.csr_wr_data_i);
    end

    // ---- 派发序断言：严格按槽号递增 + 类别一致 + 无重叠派发 ----
    int last_disp_idx;

    always @(posedge clk_r) begin
        if (!rst_hi_w) begin
            if (dut.wk_ppureq_w && dut.wk_greq_w)
                fail("同拍双后端派发（walker 解复须互斥）");
            else if (dut.wk_ppureq_w || dut.wk_greq_w) begin
                int got_idx, exp_idx;
                got_idx = dut.wk_ppureq_w ? dut.wk_ppuidx_w : dut.wk_gidx_w;
                exp_idx = last_disp_idx + 1;
                if (got_idx != exp_idx)
                    fail($sformatf("派发序断裂：得 desc%0d 期 %0d",
                                     got_idx, exp_idx));
                if (dut.wk_ppureq_w && busy_w)
                    fail($sformatf("desc%0d 派发时 shell 仍 busy（重叠派发）",
                                     got_idx));
                if (dut.wk_ppureq_w) ppu_log_q.push_back(got_idx);
                last_disp_idx = got_idx;
            end
        end
    end

    task automatic fail(string s);
        begin
            errors = errors + 1;
            $display("[%0t] FAIL: %s", $time, s);
        end
    endtask

    // V1.8：M3S 排干遥测（授权纪律第 7 条清单——闸红/超时先取证再议）
    task automatic m3s_dump_dma_state;
        begin
            $display("[%0t] M3S-TELEMETRY occ=%0d hd=%0d tl=%0d awout=%0d awcnt=%0d bcnt=%0d wib=%0d wq=%0d/%0d/%0d/%0d awv=%b wv=%b wl=%b wrdy=%b bv=%b brs=%b err=%b halt=%b | bfm awq=%0d wexp=%0d bq=%0d bv=%b aq=%0d rrun=%b rv=%b",
                $time, dut.u_shell.u_dma.wq_occ_r, dut.u_shell.u_dma.wq_hd,
                dut.u_shell.u_dma.wq_tl, dut.u_shell.u_dma.aw_out_r,
                dut.u_shell.u_dma.aw_cnt_r, dut.u_shell.u_dma.b_cnt_r,
                dut.u_shell.u_dma.w_in_bst_r,
                dut.u_shell.u_dma.wq_q[0], dut.u_shell.u_dma.wq_q[1],
                dut.u_shell.u_dma.wq_q[2], dut.u_shell.u_dma.wq_q[3],
                dut.u_shell.u_dma.awvalid_o, dut.u_shell.u_dma.wvalid_o,
                dut.u_shell.u_dma.wlast_o, dut.u_shell.u_dma.wready_i,
                dut.u_shell.u_dma.bvalid_i, dut.u_shell.u_dma.bresp_i,
                dut.u_shell.u_dma.err_r, dut.u_shell.u_dma.halted_o,
                bfm.aw_addr_q.size(), bfm.w_expect, bfm.b_resp_q.size(),
                bfm.bvalid_o, bfm.ar_addr_q.size(), bfm.r_run, bfm.rvalid_o);
        end
    endtask

    // V1.8：AXI W payload 稳定性监控（F7M 专属；F7A-D/G 钉数零扰）。
    // wvalid 挂起（wready 未至）期间 wdata/wstrb/wlast 逐拍冻结——
    // 不只在握手拍查 WLAST（授权 B-5），违例记 error + 遥测。
    reg        wst_held_q;
    reg [63:0] wst_dat_q;
    reg [7:0]  wst_str_q;
    reg        wst_lst_q;
    always @(posedge clk_r) begin
        if (run_s == "F7M" && !rst_hi_w) begin
            if (dut.u_shell.u_dma.wvalid_o === 1'b1 &&
                dut.u_shell.u_dma.wready_i !== 1'b1) begin
                if (wst_held_q &&
                    (dut.u_shell.u_dma.wdata_o !== wst_dat_q ||
                     dut.u_shell.u_dma.wstrb_o !== wst_str_q ||
                     dut.u_shell.u_dma.wlast_o !== wst_lst_q)) begin
                    errors = errors + 1;
                    $display("[%0t] F7M AXI-W STABILITY VIOLATION", $time);
                end
            end
        end
        wst_held_q <= (run_s == "F7M" && !rst_hi_w &&
                       dut.u_shell.u_dma.wvalid_o === 1'b1 &&
                       dut.u_shell.u_dma.wready_i !== 1'b1);
        wst_dat_q <= dut.u_shell.u_dma.wdata_o;
        wst_str_q <= dut.u_shell.u_dma.wstrb_o;
        wst_lst_q <= dut.u_shell.u_dma.wlast_o;
    end

    task automatic do_reset(int n);
        begin
            rstn_r <= 1'b0;
            repeat (n) @(posedge clk_r);
            rstn_r <= 1'b1;
            repeat (4) @(posedge clk_r);
        end
    endtask

    // ================= CSR 原语（全部激励经此）=================
    task automatic csr_wr(input [15:0] a, input [31:0] d);
        begin mcsr.wr32({16'h0, a}, d); end
    endtask

    task automatic csr_rd(input [15:0] a, output [31:0] d);
        begin mcsr.rd32({16'h0, a}, d); end
    endtask

    // 期待 SLVERR 的写（守卫负例）：写后查留档 bresp
    task automatic csr_wr_slv(input [15:0] a, input [31:0] d, input string tag);
        begin
            mcsr.wr32({16'h0, a}, d);
            if (mcsr.last_bresp_o !== 2'b10)
                fail($sformatf("%s: bresp 得 %b 期 SLVERR", tag, mcsr.last_bresp_o));
            else checks = checks + 1;
        end
    endtask

    // CTRL 写（bit0=enable 恒置，脉冲位按需；拼接序 = enable 在最低位）
    task automatic csr_ctrl(input [7:0] bits);
        begin csr_wr(A_CTRL, {24'h0, bits[7:1], 1'b1}); end
    endtask

    task automatic csr_start_frame;
        begin
            gemm_log_q.delete();
            ppu_log_q.delete();
            last_disp_idx = -1;
            csr_ctrl(8'h04);            // start_frame 脉冲
        end
    endtask

    task automatic csr_stop;     begin csr_ctrl(8'h08); end endtask
    task automatic csr_abort;    begin csr_ctrl(8'h10); end endtask
    task automatic csr_soft;     begin csr_ctrl(8'h02); end endtask

    task automatic csr_ffe;      begin csr_wr(A_DESC_DOORBELL, 32'h2); end endtask

    // ack 脉冲先于尾指针前进（regfile 时序：脉冲拍用旧尾判空；
    // 与 F6 TB ack_consume 同律）。尾指针写落地后再等 2 拍防同拍竞争。
    task automatic ack_consume_at(input [7:0] new_tail);
        begin
            csr_wr(A_RESULT_ACK, 32'h1);
            csr_wr(A_RESULT_RING_TAIL, {24'h0, new_tail});
            repeat (2) @(posedge clk_r);
        end
    endtask

    task automatic ack_drop_at(input [7:0] new_tail);
        begin
            csr_wr(A_RESULT_ACK, 32'h2);
            csr_wr(A_RESULT_RING_TAIL, {24'h0, new_tail});
            repeat (2) @(posedge clk_r);
        end
    endtask

    // ================= 缺省配置（CSR 面 + BFM 面）=================
    task automatic cfg_default;
        begin
            cfg_r_lat        = 2;
            cfg_fault_r_beat = 0;
            cfg_fault_r_resp = 2'b10;
            cfg_stall_after  = 0;
            cfg_fault_b_req  = 0;
            cfg_b_delay      = 2;
            cfg_w_stall      = 0;
            cfg_check_en     = 1'b1;
            ring_pub_cnt = 0; ring_ovf_cnt = 0; ring_ack_cnt = 0;
            shell_pub_cnt = 0; desc_evt_cnt = 0; eng_evt_cnt = 0;
        end
    endtask

    // gbfm 独立配置（P2.2）：缺省镜像 shell 侧；F7G-2 冲刷窗内
    // check_en 屏蔽 + w_stall 拉写（见 run_f7g）
    task automatic g_cfg_default;
        begin
            g_cfg_r_lat        = 2;
            g_cfg_fault_r_beat = 0;
            g_cfg_fault_r_resp = 2'b10;
            g_cfg_stall_after  = 0;
            g_cfg_fault_b_req  = 0;
            g_cfg_b_delay      = 2;
            g_cfg_w_stall      = 0;
            g_cfg_check_en     = 1'b1;
        end
    endtask

    // DUT CSR 缺省：enable + DMA_CFG{wr_os=4, rd_os=4, tmo=100}
    //   + head_base=1F80_0000 + HI=0 + FORMAT=0 + frame_id=0
    task automatic cfg_csr_default;
        begin
            csr_ctrl(8'h00);                              // enable=1
            csr_wr(A_DMA_CFG, (32'd4 << 27) | (32'd4 << 24) | 32'd100);
            csr_wr(A_HEAD_BASE_LO, 32'h1F80_0000);
            csr_wr(A_HEAD_BASE_HI, 32'h0);
            csr_wr(A_HEAD_FORMAT, 32'h0);
            csr_wr(A_FRAME_ID, 32'h0);
            csr_wr(A_DESC_CFG, 32'h0);                    // depth=0 非环形
            $display("[%0t] DBG cfg_csr done: en=%b bresp=%b",
                     $time, dut.ctrl_enable, mcsr.last_bresp_o);
        end
    endtask

    // ================= 程序构建 + 表装载 =================
    function automatic int slot_of(input int orig);
        int s;
        begin
            slot_of = -1;
            for (s = 0; s < N_PROG; s = s + 1)
                if (PROG[s] == orig) slot_of = s;
        end
    endfunction

    // 原地紧凑：原索引均大于槽号（PROG[s] >= 7 > s），前向拷贝安全
    task automatic build_prog;
        int s, w;
        begin
            for (w = 0; w < 32; w = w + 1)
                gemm_desc0[w] = desc_rom[w];              // 原始 desc0 留档
            for (s = 0; s < N_PROG; s = s + 1)
                for (w = 0; w < 32; w = w + 1)
                    desc_rom[32 * s + w] = desc_rom[32 * PROG[s] + w];
        end
    endtask

    // producer 重映射（槽号==desc_id 契约的配套律）：
    //   ppu_desc_if 的 b_desc_id=请求槽号（描述符字不含 id 字段），
    //   loader 步 5 用 buf 表 word6[7:0] 的 producer 与之比序。纯 PPU
    //   程序紧凑化后，producer 须同域重编：25 任务内 orig→slot（PROG
    //   升序保序，拓扑序不破）；任务外生产者（conv/view/canvas，数据
    //   由 BFM preload 提供）→ 0xFF 外部标记（步 5 明确豁免）。
    task automatic remap_producers;
        int b, s;
        reg [7:0] pr;
        begin
            for (b = 0; b < 128; b = b + 1) begin
                pr = buf_rom[8*b + 6][7:0];
                if (pr != 8'hFF) begin
                    s = slot_of(pr);
                    if (s >= 0) buf_rom[8*b + 6][7:0] = s[7:0];
                    else        buf_rom[8*b + 6][7:0] = 8'hFF;
                end
            end
        end
    endtask

    // 描述符窗口装载（win_base=0 单遍，800 字 < 2048 窗）+ 全量回读
    task automatic load_desc_win(input string tag);
        int w;
        reg [31:0] rb;
        begin
            csr_wr(A_DESC_BASE, 32'h0);                   // win_base = 0
            for (w = 0; w < 32 * N_PROG; w = w + 1)
                csr_wr(16'h1000 + 4 * w, desc_rom[w]);
            // win_base 两遍算术证明：基 2048 时窗口 0 落在 BRAM 字 2048
            csr_wr(A_DESC_BASE, 32'd2048);
            csr_wr(16'h1000, 32'hF00D_0000);
            csr_rd(16'h1000, rb);
            if (rb !== 32'hF00D_0000)
                fail($sformatf("%s: win_base=2048 窗口回读得 %08X", tag, rb));
            else checks = checks + 1;
            csr_wr(A_DESC_BASE, 32'h0);                   // 复位回 0
            for (w = 0; w < 32 * N_PROG; w = w + 1) begin
                csr_rd(16'h1000 + 4 * w, rb);
                if (rb !== desc_rom[w])
                    fail($sformatf("%s: desc 窗口回读 w%0d 得 %08X 期 %08X",
                                   tag, w, rb, desc_rom[w]));
            end
            if (errors == 0) checks = checks + 1;         // 全量回读过（本趟）
        end
    endtask

    task automatic load_buf_win(input string tag);
        int w;
        reg [31:0] rb;
        begin
            for (w = 0; w < 1024; w = w + 1)
                csr_wr(16'h3000 + 4 * w, buf_rom[w]);
            for (w = 0; w < 1024; w = w + 1) begin
                csr_rd(16'h3000 + 4 * w, rb);
                if (rb !== buf_rom[w])
                    fail($sformatf("%s: buf 窗口回读 w%0d 得 %08X 期 %08X",
                                   tag, w, rb, buf_rom[w]));
            end
            if (errors == 0) checks = checks + 1;
        end
    endtask

    task automatic load_qt_win(input string tag);
        int w;
        reg [31:0] rb;
        begin
            for (w = 0; w < 1024; w = w + 1)
                csr_wr(16'h4000 + 4 * w, qt_rom[w]);
            for (w = 0; w < 1024; w = w + 1) begin
                csr_rd(16'h4000 + 4 * w, rb);
                if (rb !== qt_rom[w])
                    fail($sformatf("%s: quant 窗口回读 w%0d 得 %08X 期 %08X",
                                   tag, w, rb, qt_rom[w]));
            end
            if (errors == 0) checks = checks + 1;
        end
    endtask

    // 队列寄存器：count=tail（F6 TB 同律）
    task automatic csr_tail(input [15:0] t);
        begin
            csr_wr(A_DESC_COUNT, {16'h0, t});
            csr_wr(A_DESC_TAIL,  {16'h0, t});
        end
    endtask

    // 读 hex 三表 + 紧凑 + 三窗口装载 + preload
    task automatic load_full(input string desc_hex, input int fr, input string tag);
        begin
            $readmemh({prep_dir, "/", desc_hex}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            build_prog;
            remap_producers;
            load_desc_win(tag);
            load_buf_win(tag);
            load_qt_win(tag);
            bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", fr)});
        end
    endtask

    // ================= 等待原语（F6 正典）=================
    task automatic final_fail(input string s);
        begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT FAIL %s", s);
            else
                $display("EES_VIVADO_RESULT FAIL %s", s);
            $finish;
        end
    endtask

    task automatic wait_walk_done(input int n, input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (wk_done_w == n) break;
                t = t + 1;
                if ((t % 200000) == 0)
                    $display("[%0t] DBG %s: done=%0d rd=%0d wr=%0d wkst=%0d grant=%b busy=%b eb=%b halted=%b unl=%0d shst=%0d errsts=%03X errinfo=%08X lst=%0d lbit=%0d lcode=%02X | dif: op=%02X dbid=%0d in0=%0d in1=%0d out=%0d prod=%06X fet=%03X val=%03X",
                             $time, tag, wk_done_w, bfm.rd_n, bfm.wr_n,
                             dut.u_wk.state, dut.port_grant_w, busy_w,
                             eng_busy_w, dut.sh_dma_halt_w, bfm_unloaded,
                             dut.u_shell.state_r,
                             dut.u_regf.error_status_q, dut.u_regf.error_info_q,
                             ldr_step_l, ldr_bit_l, ldr_code_l,
                             dut.u_shell.b_opcode_w, dut.u_shell.b_desc_id_w,
                             dut.u_shell.b_in0_w, dut.u_shell.b_in1_w,
                             dut.u_shell.b_out_w,
                             dut.u_shell.sb_prod_w, dut.u_shell.sb_fetched_w,
                             dut.u_shell.sb_valid_w);
`ifndef PPU_F7_GEMM_STUB
                if ((t % 200000) == 0 && run_s == "F7G")
                    $display("[%0t] DBG %s GFACE: gst=%0d ecode=%02X gsel=%b gbusy=%b grcvr=%b gwash=%0d halt=%b gerrp=%b | dw: oc_ho=%08X wo=%08X arena=%08X param=%08X k_act=%08X | gdma: rdy=%b rac=%b err=%b",
                             $time, tag,
                             dut.u_gemm.state, dut.gemm_ecode_w,
                             dut.gemm_sel_q, dut.gemm_busy_w, dut.g_rcvr_w,
                             dut.gwash_cnt, dut.gdma_halt_w,
                             dut.u_gdma.err_pulse_o,
                             dut.u_gemm.dw_oc_ho, dut.u_gemm.dw_wo,
                             dut.u_gemm.dw_arena, dut.u_gemm.dw_param,
                             dut.u_gemm.dw_k_act,
                             dut.u_gdma.rd_req_ready_o, dut.u_gdma.rd_act_r,
                             dut.u_gdma.err_r);
`endif  // PPU_F7_GEMM_STUB
                if (t > tmo) begin
                    fail($sformatf("%s: walker_done==%0d 超时 %0d 拍", tag, n, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_idle(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (wk_idle_w) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: walker idle 超时 %0d 拍", tag, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            // 2 拍落定：监视器（计数/锁存）与唤醒同沿竞争（F6 实测律）
            repeat (2) @(posedge clk_r);
            checks = checks + 1;
        end
    endtask

    task automatic wait_eng_busy(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (eng_busy_w) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: eng_busy 超时 %0d 拍", tag, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_ring_pub(input int n, input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (ring_pub_cnt == n) break;
                t = t + 1;
                if (t > tmo) begin
                    // V1.6.3 超时面：环 FSM/指针/seq + walker 态一次性倾倒
                    $display("[%0t] RINGWAIT_DUMP %s: cnt=%0d rst_hi=%b ring.state=%0d head=%0d tail=%0d seq=%0d wkst=%0d done=%0d pubv=%b pubr=%b",
                             $time, tag, ring_pub_cnt, rst_hi_w, dut.u_ring.state,
                             dut.u_ring.head_ptr_o, dut.ring_tail_ptr_w,
                             dut.ring_seq_w, dut.u_wk.state, wk_done_w,
                             dut.pub_valid_w, dut.pub_ready_w);
                    fail($sformatf("%s: 环发布计数==%0d 超时", tag, n));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_ring_ovf(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (ring_ovf_cnt >= 1) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: 环溢出事件超时", tag));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_evt_cnt(input int n, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (eng_evt_cnt >= n) break;
                t = t + 1;
                if (t > 300000) begin
                    fail($sformatf("%s: 引擎错误事件超时", tag));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic check_no_resume(input int cyc, input int dn, input string tag);
        int t;
        reg ok;
        begin
            t = 0; ok = 1'b1;
            while (t < cyc && ok) begin
                @(posedge clk_r);
                if (!wk_idle_w || wk_done_w != dn) begin
                    fail($sformatf("%s: 停后 %0d 拍内自行续走（done=%0d 期停于 %0d）",
                                   tag, t, wk_done_w, dn));
                    ok = 1'b0;
                end
                t = t + 1;
            end
            if (ok) checks = checks + 1;
        end
    endtask

    // 错误驻留态专用（V1.6.1）：引擎错后 walker 停在错误保持态（非 W_IDLE，
    // soft_reset 方出），check_no_resume 的 idle 条件在此恒假。判据收敛为
    // done 冻结 + 零新派发（PPU/GEMM 日志长度不变）；环/上下文另有钉。
    task automatic check_frozen(input int cyc, input int dn, input string tag);
        int t, p0, g0;
        reg ok;
        begin
            t = 0; ok = 1'b1;
            p0 = ppu_log_q.size(); g0 = gemm_log_q.size();
            while (t < cyc && ok) begin
                @(posedge clk_r);
                if (wk_done_w != dn || ppu_log_q.size() != p0
                    || gemm_log_q.size() != g0) begin
                    fail($sformatf("%s: 停后 %0d 拍续走（done=%0d 期停 %0d 派发+%0d/+0）",
                                   tag, t, wk_done_w, dn,
                                   ppu_log_q.size() - p0));
                    ok = 1'b0;
                end
                t = t + 1;
            end
            if (ok) checks = checks + 1;
        end
    endtask

    // Σw14：槽区间 [lo,hi]（含，紧凑后 desc_rom 即槽布局）
    function automatic longint unsigned sum_range(int lo, int hi);
        int i;
        begin
            sum_range = 0;
            for (i = lo; i <= hi; i = i + 1)
                sum_range = sum_range + desc_rom[32 * i + 14];
        end
    endfunction

    // ================= 金样窗口比对（F6 正典，文件按原索引取）=================
    task automatic cmp_golden(string kind, int di,
                              longint unsigned mark, string tag,
                              int fr = -1);
        int fd, n, code;
        string f, why;
        bit [31:0] ea; bit [63:0] ed; bit [7:0] es;
        longint unsigned got, sz;
        begin
            f = (fr < 0) ? $sformatf("%s/%s_golden_%0d.txt", prep_dir, kind, di)
                         : $sformatf("%s/%s_golden_f%0d_%0d.txt",
                                     prep_dir, kind, fr, di);
            fd = $fopen(f, "r");
            if (fd == 0) begin
                fail($sformatf("%s: 打不开 %s", tag, f));
                return;
            end
            sz  = (kind == "rd") ? bfm.rd_n : bfm.wr_n;
            n   = 0;
            why = "";
            code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            while (code == 3 && why == "") begin
                if (mark + n >= sz)
                    why = $sformatf("拍数不足：log=%0d 期望≥%0d", sz - mark, n + 1);
                else if (kind == "rd") begin
                    if (bfm.rd_addr_lg[mark+n] != ea || bfm.rd_data_lg[mark+n] != ed)
                        why = $sformatf("rd 拍%0d: 得 %08X/%016X 期 %08X/%016X",
                            n, bfm.rd_addr_lg[mark+n], bfm.rd_data_lg[mark+n], ea, ed);
                end else begin
                    if (bfm.wr_addr_lg[mark+n] != ea || bfm.wr_data_lg[mark+n] != ed
                        || bfm.wr_strb_lg[mark+n] != es)
                        why = $sformatf("wr 拍%0d: 得 %08X/%016X/%02X 期 %08X/%016X/%02X",
                            n, bfm.wr_addr_lg[mark+n], bfm.wr_data_lg[mark+n],
                            bfm.wr_strb_lg[mark+n], ea, ed, es);
                end
                n = n + 1;
                code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            end
            $fclose(fd);
            got = sz - mark;
            if (why != "")
                fail($sformatf("%s: desc%0d(原) %s %s", tag, di, kind, why));
            else if (got != n)
                fail($sformatf("%s: desc%0d(原) %s 拍数 得%0d 期%0d",
                               tag, di, kind, got, n));
            else begin
                checks = checks + 2;
                $display("[%0t] %s 原desc%0d %s BITEXACT %0d 拍",
                         $time, tag, di, kind, n);
            end
        end
    endtask

    // ---- 走到 walker_done==n：逐槽滑动金样窗（全槽皆引擎任务）----
    longint unsigned g_rm, g_wm;

    task automatic walk_mark(input int n, input int fr, input string tag);
        longint unsigned rm, wm;
        int i;
        begin
            rm = bfm.rd_n;
            wm = bfm.wr_n;
            for (i = 0; i < n; i = i + 1) begin
                wait_walk_done(i + 1, 3_000_000, $sformatf("%s s%0d", tag, i));
                cmp_golden("rd", PROG[i], rm, tag, fr);
                cmp_golden("wr", PROG[i], wm, tag, fr);
                rm = bfm.rd_n;
                wm = bfm.wr_n;
            end
            g_rm = rm;
            g_wm = wm;
        end
    endtask

    // CSR 结果面核对（F7 专有：PS 可见性）
    task automatic check_csr_result(input [31:0] exp_seq, input [31:0] exp_fid,
                                    input [31:0] exp_bytes, input [7:0] exp_rhead,
                                    input string tag);
        reg [31:0] v;
        begin
            csr_rd(A_RESULT_SEQ, v);
            if (v !== exp_seq)
                fail($sformatf("%s: RESULT_SEQ 得 %0d 期 %0d", tag, v, exp_seq));
            csr_rd(A_RESULT_FRAME_ID, v);
            if (v !== exp_fid)
                fail($sformatf("%s: RESULT_FRAME_ID 得 %0d 期 %0d", tag, v, exp_fid));
            csr_rd(A_HEAD_BYTES, v);
            if (v !== exp_bytes)
                fail($sformatf("%s: HEAD_BYTES 得 %0d 期 %0d", tag, v, exp_bytes));
            csr_rd(A_RESULT_RING_HEAD, v);
            if (v[7:0] !== exp_rhead)
                fail($sformatf("%s: RING_HEAD 得 %0d 期 %0d", tag, v[7:0], exp_rhead));
            csr_rd(A_STATUS, v);
            if (v[7] !== (ring_ne_w ? 1'b1 : 1'b0))
                fail($sformatf("%s: STATUS.PS_ACK_WAIT(%b) 与环非空(%b) 不一致",
                               tag, v[7], ring_ne_w));
            checks = checks + 5;
        end
    endtask

    task automatic check_desc_csr(input [15:0] exp_head, input [15:0] exp_done,
                                  input string tag);
        reg [31:0] v;
        begin
            csr_rd(A_DESC_HEAD, v);
            if (v[15:0] !== exp_head)
                fail($sformatf("%s: DESC_HEAD 得 %0d 期 %0d", tag, v[15:0], exp_head));
            csr_rd(A_DESC_DONE_COUNT, v);
            if (v[15:0] !== exp_done)
                fail($sformatf("%s: DESC_DONE 得 %0d 期 %0d", tag, v[15:0], exp_done));
            checks = checks + 2;
        end
    endtask

    // ================= RUN F7A =================
    // 身份 + 全表窗口装载/回读 + 25 任务逐字节 + 队列空 ffe 发环
    // + CSR 结果面 + ack 清环。
    task automatic run_f7a;
        reg [31:0] v, exp_bytes;
        begin
            $display("[RUN F7A] 身份/表装载/25 任务/ffe 发环/CSR 结果面");
            do_reset(5);
            cfg_default;
            cfg_csr_default;

            // ---- 身份门 ----
            csr_rd(A_ID, v);
            if (v !== YOLO_ID_VALUE)
                fail($sformatf("F7A: ID 得 %08X 期 %08X", v, YOLO_ID_VALUE));
            csr_rd(A_VERSION, v);
            if (v !== YOLO_VERSION)
                fail($sformatf("F7A: VERSION 得 %08X 期 %08X", v, YOLO_VERSION));
            checks = checks + 2;

            // ---- 全表装载（含窗口算术证明与全量回读）----
            load_full("desc_table_A.hex", 0, "F7A");

            // 槽 24 清 last 位（w0[9]，窗口直写 word 768）——本门专测
            // "队列空 ffe 发环"；帧终路径分工：F7C 原生 last 帧末自动发
            // 环 / B2 stop+last / B4、G3 中途 ffe。清位后 walker 在队列
            // 空 + 无 last 时真停 W_CHK 轮询，ffe 是唯一发环源。
            begin : f7a_splice
                reg [31:0] w0v;
                w0v = desc_rom[32*24] & ~32'h200;
                desc_rom[32*24] = w0v;
                csr_wr(16'h1000 + 4*32*24, w0v);   // win_base=0 → word 768
            end

            // ---- 25 任务逐字节 ----
            csr_tail(16'd25);
            begin : dbg_cfg
                reg [31:0] dv;
                csr_rd(A_DESC_TAIL, dv);
                $display("[%0t] DBG cfg: rd_tail=%0d xmr_tail=%0d xmr_cnt=%0d en=%b dma=%08X hb=%08X wkst=%0d idle=%b",
                         $time, dv, dut.desc_tail_w, dut.desc_count_w,
                         dut.ctrl_enable, dut.dma_cfg_w, dut.head_base_lo_w,
                         dut.u_wk.state, wk_idle_w);
            end
            csr_start_frame;
            walk_mark(25, 0, "F7A");

            // 队列空：walker 停在 W_CHK 轮询（未 idle、未发环）
            if (wk_idle_w) fail("[E-EARLY-IDLE] F7A: 队列空后 walker 提前 idle（应 W_CHK 轮询）");
            if (wk_head_w != 16'd25 || wk_done_w != 16'd25)
                fail($sformatf("F7A: head/done 得 %0d/%0d 期 25/25", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0) fail("[E-FFE-EARLY] F7A: ffe 前出现发环");
            checks = checks + 3;
            check_desc_csr(16'd25, 16'd25, "F7A");

            // ---- DOORBELL bit1：ffe 双落点（walker 粘着 + shell 脉冲）----
            csr_ffe;
            wait_ring_pub(1, 100000, "F7A");
            exp_bytes = sum_range(0, 24);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("[E-BYTES] F7A: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1)   fail("[E-SEQ] F7A: seq != 1");
            if (ring_fid_w != 32'd0)   fail("[E-FID] F7A: frame_id != 0");
            // 空闲 ffe：shell 仲裁器无从判定（无 done 可决），发环必来自
            // walker W_CHK→W_PUB 清粘着路径——须 0（B4 中途 ffe 才是 1）
            if (shell_pub_cnt != 0)
                fail("[E-SHELLPUB] F7A: shell 侧 ring_publish 须 0（walker 独占发布证明）");
            if (ffe_pend_w !== 1'b0)   fail("[E-FFESTICK] F7A: ffe 粘着未被消费");
            checks = checks + 5;
            check_csr_result(32'd1, 32'd0, exp_bytes, 8'd1, "F7A");

            wait_idle(1000, "F7A");
            check_no_resume(200, 25, "F7A");
            if (ppu_log_q.size() != 25)
                fail($sformatf("F7A: PPU 派发数 得%0d 期25", ppu_log_q.size()));
            if (gemm_log_q.size() != 0)
                fail($sformatf("F7A: 程序期不得派发 GEMM（得%0d）", gemm_log_q.size()));
            checks = checks + 2;

            // ---- ack 清环（CSR 双写：脉冲先、尾后）----
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7A: ack 后环仍非空");
            else checks = checks + 1;
            csr_rd(A_STATUS, v);
            if (v[7] !== 1'b0) fail("F7A: ack 后 STATUS.PS_ACK_WAIT 仍置位");
            else checks = checks + 1;

            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F7A] 完：25 任务 / 发环 1 / rd %0d wr %0d",
                     bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= RUN F7B =================
    // 事件语义四连 + GEMM 桩 err→bit10 + D1/D2/D3 拼接负例。
    task automatic run_f7b;
        reg [31:0] v, exp_bytes;
        int s50, s7;
        begin
            s50 = slot_of(50);
            s7  = slot_of(7);

            // ---- B1：stop 温和停 @槽12（当条完成后停）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7B1");
            $display("[RUN F7B/B1] stop 温和停 @槽12（原desc%0d）", PROG[12]);
            csr_tail(16'd25);
            csr_start_frame;
            walk_mark(12, 0, "F7B1");
            wait_eng_busy(100000, "F7B1");
            csr_stop;
            wait_walk_done(13, 3_000_000, "F7B1 stop后当条完成");
            cmp_golden("rd", PROG[12], g_rm, "F7B1", 0);
            cmp_golden("wr", PROG[12], g_wm, "F7B1", 0);
            wait_idle(1000, "F7B1");
            if (!stopped_w)        fail("B1: shell stopped 未置位");
            if (wk_head_w != 16'd13 || wk_done_w != 16'd13)
                fail($sformatf("B1: head/done 得 %0d/%0d 期 13/13", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0) fail("B1: 温和停（非 last）不得发环");
            checks = checks + 3;
            check_no_resume(500, 13, "B1");

            // ---- B2：stop+last @槽24（当条完成且发环）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7B2");
            $display("[RUN F7B/B2] stop+last @槽24（整程序走完）");
            csr_tail(16'd25);
            csr_start_frame;
            walk_mark(24, 0, "F7B2");
            wait_eng_busy(500000, "F7B2");
            csr_stop;
            wait_walk_done(25, 3_000_000, "F7B2 stop后当条完成");
            cmp_golden("rd", PROG[24], g_rm, "F7B2", 0);
            cmp_golden("wr", PROG[24], g_wm, "F7B2", 0);
            wait_ring_pub(1, 100000, "F7B2");
            exp_bytes = sum_range(0, 24);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("B2: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1) fail("B2: seq != 1");
            if (!stopped_w)          fail("B2: shell stopped 未置位");
            if (wk_head_w != 16'd25) fail("B2: head != 25");
            checks = checks + 4;
            check_csr_result(32'd1, 32'd0, exp_bytes, 8'd1, "F7B2");
            wait_idle(1000, "F7B2");
            ack_consume_at(8'd1);

            // ---- B3：abort @槽7 中途（丢弃帧）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7B3");
            $display("[RUN F7B/B3] abort 中途丢弃 @槽7");
            csr_tail(16'd25);
            csr_start_frame;
            walk_mark(7, 0, "F7B3");                    // 槽 0..6 金样
            wait_eng_busy(100000, "F7B3");
            repeat (200) @(posedge clk_r);              // 走进引擎中段再 abort
            csr_abort;
            wait_idle(300000, "F7B3 abort落定");
            if (!stopped_w) fail("B3: shell stopped 未置位");
            if (wk_head_w != 16'd7 || wk_done_w != 16'd7)
                fail($sformatf("B3: abort 不得前进（head/done 得 %0d/%0d 期 7/7）",
                               wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0)   fail("B3: abort 帧不得发环");
            if (desc_evt_cnt != 0 || eng_evt_cnt != 0)
                fail("B3: abort 不是错误事件（desc/eng evt 须为 0）");
            checks = checks + 4;
            check_no_resume(500, 7, "B3");

            // ---- B4：ffe @槽16 中途（当条完成后立即发环）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7B4");
            $display("[RUN F7B/B4] ffe 中途强发环 @槽16");
            csr_tail(16'd25);
            csr_start_frame;
            walk_mark(16, 0, "F7B4");
            wait_eng_busy(100000, "F7B4");
            csr_ffe;
            wait_walk_done(17, 3_000_000, "F7B4 当条完成");
            cmp_golden("rd", PROG[16], g_rm, "F7B4", 0);
            cmp_golden("wr", PROG[16], g_wm, "F7B4", 0);
            wait_ring_pub(1, 100000, "F7B4");
            exp_bytes = sum_range(0, 16);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("B4: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1) fail("B4: seq != 1");
            if (stopped_w)           fail("B4: ffe 非终态事件，stopped 须为 0");
            if (wk_head_w != 16'd17) fail("B4: head != 17");
            if (shell_pub_cnt != 1)  fail("B4: shell 侧 ring_publish 须恰好 1");
            checks = checks + 5;
            wait_idle(1000, "F7B4");
            check_no_resume(500, 17, "B4");
            ack_consume_at(8'd1);

            // ---- B5：真 GEMM 引擎非法 K desc（P2.2）→ bit10 粘着 ----
            // 原桩恒 err 已撤；负例改写原始 conv desc0 为 K=999 → 引擎
            // E_GEOM 链律拒绝（P2.1 S3 板证：err 0x02、任何 DMA 拍前）
            // → m1_axi 零拍、shell 台账不变（F7B 基线逐数保持的关键）
            do_reset(5); cfg_default; cfg_csr_default; g_cfg_default;
            load_full("desc_table_A.hex", 0, "F7B5");
            // 槽 0 换回原始 conv 描述符（gemm_desc0 在 build_prog 留档）
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32; v = v + 1)
                csr_wr(16'h1000 + 4 * v, gemm_desc0[v]);
            // 覆写 w0（valid+opcode 0x01，无 last）/ w11（K=999）成非法 desc
            csr_wr(16'h1000,             32'h0000_0101);
            csr_wr(16'h1000 + 4 * 11,    32'h0000_03E7);
            $display("[RUN F7B/B5] GEMM 引擎非法 K=999 @desc0 → bit10/soft_reset");
            csr_tail(16'd1);
            csr_start_frame;
            wait_evt_cnt(1, "B5 引擎错误事件");
            repeat (300) @(posedge clk_r);              // W_ERR 须粘着
            if (wk_idle_w)     fail("B5: W_ERR 不得自行回 idle");
            if (!wk_run_w)     fail("B5: W_ERR 期 running 须为 1");
            if (wk_head_w != 16'd0 || wk_done_w != 16'd0)
                fail("B5: head/done 须停于 0/0");
            if (ring_pub_cnt != 0) fail("B5: 引擎错不得发环");
            if (gemm_log_q.size() != 1)
                fail($sformatf("B5: GEMM 派发数 得%0d 期1", gemm_log_q.size()));
            checks = checks + 5;
            // ---- B5a：forensics 先读后复位（板驱纪律）+ W1C 证明 ----
            csr_rd(A_ERROR_STATUS, v);
            if (v[10] !== 1'b1)
                fail($sformatf("[E-B5-STICK] bit10 得 %b 期 1（全字 %03X）",
                               v[10], v[10:0]));
            else checks = checks + 1;
            csr_rd(A_ERROR_INFO, v);
            if (v === 32'h0)
                fail("[E-B5-INFO] ERROR_INFO 未锁存（全 0）");
            else checks = checks + 1;
            csr_wr(A_ERROR_STATUS, 32'h400);            // W1C bit10
            csr_rd(A_ERROR_STATUS, v);
            if (v[10] !== 1'b0) fail("[E-B5-W1C] W1C 未清 bit10");
            else checks = checks + 1;
            // ---- B5b：soft_reset = V1.1 冻结全量擦洗（含 ERROR_STATUS；
            //      regfile 头注"其余语义逐位沿用 V1.1"，CSR 线板证语义，
            //      F7 不得改）。重跑 desc0 再触发桩错证明擦洗路径。----
            csr_soft;                                   // 释放 walker（W_ERR 唯一出口）
            wait_idle(1000, "B5 soft_reset 释放");
            cfg_csr_default;    // V1.1 全量擦洗→CSR 归零（板驱恢复纪律：
                                // 软复位后须重配；BRAM 表不擦无需重装）
            csr_tail(16'd1); csr_start_frame;           // 重跑 desc0 → 桩再错
            wait_evt_cnt(2, "B5 二次引擎错误事件");
            // csr_start_frame 开头清 gemm_log_q（逐帧日志语义，TB:340）
            // → 期望 = 本趟新增 1 次派发、对象 desc0；累计引擎错由
            // eng_evt_cnt==2 见证（wait_evt_cnt 已证）
            if (gemm_log_q.size() != 1 || gemm_log_q[0] != 0)
                fail($sformatf("[E-B5-DSP2] 重跑派发 得%0d 条/首idx=%0d 期1/idx0",
                               gemm_log_q.size(), gemm_log_q[0]));
            else checks = checks + 1;
            csr_soft;                                   // 再软复位 → 全量擦洗
            wait_idle(1000, "B5 二次 soft_reset");
            csr_rd(A_ERROR_STATUS, v);
            if (v[10] !== 1'b0)
                fail("[E-B5-SCRUB] soft_reset 后 bit10 须 0（V1.1 全量擦洗）");
            else checks = checks + 1;
            check_no_resume(300, 0, "B5");              // soft_reset 清零 done

            // ---- B6：D1 拼接（原desc50 valid=0 → 槽%0d 描述符错）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_D1.hex", 0, "F7B6");
            $display("[RUN F7B/B6] D1：原desc50 valid=0 → 槽%0d", s50);
            csr_tail(16'd25);
            csr_start_frame;
            wait_idle(5_000_000, "B6 错误落定");
            if (desc_evt_cnt != 1)     fail($sformatf("B6: 描述符错事件 得%0d 期1", desc_evt_cnt));
            if (wk_errid_w != s50[15:0])
                fail($sformatf("B6: walker_error_id 得 %0d 期 %0d", wk_errid_w, s50));
            if (wk_head_w != s50[15:0] || wk_done_w != s50[15:0])
                fail($sformatf("B6: head/done 得 %0d/%0d 期 %0d/%0d",
                               wk_head_w, wk_done_w, s50, s50));
            if (ring_pub_cnt != 0 || eng_evt_cnt != 0)
                fail("B6: 不得发环/引擎错");
            checks = checks + 4;
            csr_rd(A_DESC_ERROR_ID, v);
            if (v[15:0] != s50[15:0])
                fail($sformatf("B6: CSR DESC_ERROR_ID 得 %0d 期 %0d", v[15:0], s50));
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, v);
            if (v[3] !== 1'b1) fail("B6: ERROR_STATUS.bit3 未置位");
            else checks = checks + 1;
            check_no_resume(300, s50, "B6");
            csr_wr(A_ERROR_STATUS, 32'h008);            // W1C bit3

            // ---- B7：D2 拼接（原desc50 opcode=0x20 非法码）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_D2.hex", 0, "F7B7");
            $display("[RUN F7B/B7] D2：原desc50 opcode=0x20 → 槽%0d", s50);
            csr_tail(16'd25);
            csr_start_frame;
            wait_idle(5_000_000, "B7 错误落定");
            if (desc_evt_cnt != 1)    fail($sformatf("B7: 描述符错事件 得%0d 期1", desc_evt_cnt));
            if (desc_evt_op != 8'h20) fail($sformatf("B7: err_op 得 %02X 期 20", desc_evt_op));
            if (wk_errid_w != s50[15:0]) fail("B7: walker_error_id 槽号错");
            if (ring_pub_cnt != 0)    fail("B7: 不得发环");
            checks = checks + 4;
            check_no_resume(300, s50, "B7");

            // ---- B8：D3 拼接（原desc7 quant id 越界 → 槽0 loader 错 → W_ERR）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_D3.hex", 0, "F7B8");
            $display("[RUN F7B/B8] D3：原desc7 quant id 越界 → 槽0 loader 错");
            csr_tail(16'd25);
            csr_start_frame;
            wait_evt_cnt(1, "B8 引擎错误事件");
            repeat (300) @(posedge clk_r);
            if (wk_idle_w)         fail("B8: W_ERR 不得自行回 idle");
            if (!wk_run_w)         fail("B8: W_ERR 期 running 须为 1");
            if (wk_head_w != 16'd0 || wk_done_w != 16'd0)
                fail("B8: head/done 须停于 0/0");
            if (!busy_w)           fail("B8: shell 未粘着（S_HALT 期 busy 须为 1）");
            if (ring_pub_cnt != 0) fail("B8: 引擎错不得发环");
            checks = checks + 5;
            csr_soft;
            wait_idle(1000, "B8 soft_reset 释放");
            // V1.7（2026-09-29 案 2）：ctrl_sreset 臂 16 拍 u_shell wash →
            // halt 随 wash 释放。旧钉"soft_reset 不得释放 shell halt（复位
            // 分层）"已废——该语义正是 M3 软复位恢复死锁（派发进错误保持
            // shell → W_ERR）的根因，用户指令 1+2 合并改案 2 裁定翻转。
            if (busy_w) fail("B8: soft_reset 须以 shell wash 释放 halt（V1.7 语义）");
            else checks = checks + 1;

            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 1;
            if (bfm_proto_err != 0)
                $display("[RUN F7B] 注：abort 中断在途致 AXI 协议计数 %0d（F6B 同例，报告不判死）",
                         bfm_proto_err);
            $display("[RUN F7B] 完：B1-B8 八连毕 / rd %0d wr %0d", bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= RUN F7C =================
    // 5 帧 × 25 任务连发不复位：每帧 CSR 换 frame_id + BFM 换 preload；
    // 槽 24=last → 帧末自动发环；帧 1 后 1 次 ack。
    task automatic run_f7c;
        int k;
        reg [31:0] v, exp_bytes;
        begin
            $display("[RUN F7C] 5 帧 × 25 任务连发（不复位）");
            do_reset(5);
            cfg_default;
            cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7C");    // 表只装一次
            for (k = 0; k < 5; k = k + 1) begin
                bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", k)});
                csr_wr(A_FRAME_ID, k);
                csr_tail(16'd25);   // 逐帧重挂 tail（板驱逐帧序列
                                    // FRAME_ID+TAIL+START；walker 帧启动
                                    // 自清 head/done，tail 非软复位不清）
                $display("[RUN F7C] 帧%0d：25 任务连发", k);
                csr_start_frame;
                walk_mark(25, k, $sformatf("F7C f%0d", k));
                wait_ring_pub(k + 1, 200000, $sformatf("F7C f%0d", k));
                exp_bytes = sum_range(0, 24);
                if (ring_bytes_w != exp_bytes)
                    fail($sformatf("帧%0d 环字节 得 %0d 期 %0d", k, ring_bytes_w, exp_bytes));
                if (ring_seq_w != k + 1)
                    fail($sformatf("帧%0d seq 得 %0d 期 %0d", k, ring_seq_w, k + 1));
                if (ring_fid_w != k)
                    fail($sformatf("帧%0d frame_id 得 %0d", k, ring_fid_w));
                checks = checks + 3;
                check_csr_result(k + 1, k, exp_bytes, (k + 1),
                                 $sformatf("F7C f%0d", k));
                wait_idle(1000, $sformatf("F7C f%0d", k));
                if (k == 1) ack_consume_at(8'd2);        // 帧 1 后插 1 次消费
                $display("[RUN F7C] 帧%0d 完：发环 %0d / rd %0d wr %0d",
                         k, ring_pub_cnt, bfm.rd_n, bfm.wr_n);
            end
            if (ring_pub_cnt != 5)
                fail($sformatf("全回放发环数=%0d 期 5", ring_pub_cnt));
            else checks = checks + 1;
            if (ppu_log_q.size() != 25)
                fail($sformatf("终帧 PPU 派发 得%0d 期25", ppu_log_q.size()));
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 3;
        end
    endtask

    // ================= RUN F7D =================
    // 表锁守卫（运行期四窗口写 → SLVERR + bits + 表内容不变）
    // + 环 RO / 坏区 / 非对齐读 + 环容量边界（31 入环 + 溢出 + 排空
    // + 空环 ack 错）。
    task automatic run_f7d;
        int i;
        reg [31:0] v, exp_bytes, save_w0, save_bw, save_qw;
        begin
            // ---- G1：运行期表写守卫 ----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7D1");
            save_w0 = desc_rom[0]; save_bw = buf_rom[0]; save_qw = qt_rom[0];
            $display("[RUN F7D/G1] 运行期四窗口写 → SLVERR + bits3-6");
            csr_tail(16'd25);
            csr_start_frame;
            wait_eng_busy(100000, "G1");
            csr_wr_slv(16'h1000, 32'hDEAD_0001, "G1 desc 窗");
            csr_wr_slv(16'h3000, 32'hDEAD_0002, "G1 buf 窗");
            csr_wr_slv(16'h4000, 32'hDEAD_0003, "G1 quant 窗");
            csr_wr_slv(16'h5000, 32'hDEAD_0004, "G1 lut 窗");
            // 守卫写不打断运行；帧走完后 walker 停在队列空轮询，abort 收口
            wait_walk_done(25, 5_000_000, "G1 程序走完");
            csr_abort;
            wait_idle(300000, "G1 abort 落定");
            if (ring_pub_cnt != 0)
                $display("[RUN F7D/G1] 注：abort 收口未发环（预期）");
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, v);
            if (v[3] !== 1'b1) fail("G1: bit3(desc 守卫) 未置位");
            if (v[4] !== 1'b1) fail("G1: bit4(buf 守卫) 未置位");
            if (v[5] !== 1'b1) fail("G1: bit5(quant 守卫) 未置位");
            if (v[6] !== 1'b1) fail("G1: bit6(lut 守卫) 未置位");
            checks = checks + 4;
            // 表内容不变（守卫写被拒）
            csr_rd(16'h1000, v);
            if (v !== save_w0)
                fail($sformatf("G1: desc 表被污染 得 %08X 期 %08X", v, save_w0));
            csr_rd(16'h3000, v);
            if (v !== save_bw) fail("G1: buf 表被污染");
            csr_rd(16'h4000, v);
            if (v !== save_qw) fail("G1: quant 表被污染");
            checks = checks + 3;
            csr_wr(A_ERROR_STATUS, 32'h078);            // W1C bits3-6

            // ---- G2：环窗只读 + 坏区 + 非对齐 ----
            $display("[RUN F7D/G2] 环 RO / 坏区 / 非对齐");
            csr_wr_slv(16'h6000, 32'hBEEF_0001, "G2 环 RO 写");
            csr_rd(A_ERROR_STATUS, v);
            if (v[9] !== 1'b1) fail("G2: bit9(环 RO) 未置位");
            else checks = checks + 1;
            csr_wr(A_ERROR_STATUS, 32'h200);
            csr_wr_slv(16'h6C00, 32'hBEEF_0002, "G2 坏区写");
            csr_rd(A_ERROR_STATUS, v);
            if (v[0] !== 1'b1) fail("G2: bit0(坏区) 未置位");
            else checks = checks + 1;
            csr_wr(A_ERROR_STATUS, 32'h001);
            csr_wr_slv(16'h1002, 32'hBEEF_0003, "G2 非对齐写");
            csr_rd(A_ERROR_STATUS, v);
            if (v[0] !== 1'b1) fail("G2: bit0(非对齐) 未置位");
            else checks = checks + 1;
            csr_wr(A_ERROR_STATUS, 32'h001);
            mcsr.rd32(32'h0000_1002, v);                 // 非对齐读 → SLVERR
            if (mcsr.last_rresp_o !== 2'b10)
                fail($sformatf("G2: 非对齐读 rresp 得 %b 期 SLVERR", mcsr.last_rresp_o));
            else checks = checks + 1;

            // ---- G3：环容量边界（31 入环 + 第 32 溢出 + 排空 + 空 ack 错）----
            do_reset(5); cfg_default; cfg_csr_default;
            load_full("desc_table_A.hex", 0, "F7D3");
            $display("[RUN F7D/G3] 环容量边界：tail=1（槽0）× 32 帧连发");
            for (i = 0; i < 32; i = i + 1) begin
                csr_wr(A_FRAME_ID, i);
                csr_tail(16'd1);
                csr_start_frame;
                wait_eng_busy(100000, $sformatf("G3 f%0d", i));
                csr_ffe;                                 // 引擎中段 ffe（B4 同律）
                // 预算对齐 walk_mark 的 300 万拍：等待内容 = 槽 0 引擎
                // 剩余时间 + 发环，槽 0 是最大张量搬运，10 万拍不够
                if (i < 31) wait_ring_pub(i + 1, 3_000_000, $sformatf("G3 pub%0d", i));
                else        wait_ring_ovf(3_000_000, "G3 第32次满环丢弃");
                wait_idle(1000, $sformatf("G3 f%0d", i));
            end
            if (ring_pub_cnt != 31)
                fail($sformatf("G3: 入环计数 得%0d 期31", ring_pub_cnt));
            if (ring_ovf_cnt != 1)
                fail($sformatf("G3: 溢出计数 得%0d 期1", ring_ovf_cnt));
            if (ring_seq_w != 32'd32)
                fail($sformatf("G3: seq 得 %0d 期 32（溢出间隙可见）", ring_seq_w));
            if (ring_head_w != 8'd31)
                fail($sformatf("G3: head_ptr 得 %0d 期 31", ring_head_w));
            checks = checks + 4;
            csr_rd(A_ERROR_STATUS, v);
            if (v[8] !== 1'b1) fail("G3: bit8(环溢出) 未置位");
            else checks = checks + 1;
            for (i = 0; i < 31; i = i + 1) ack_drop_at(i[7:0] + 8'd1);
            repeat (2) @(posedge clk_r);
            if (ring_ne_w) fail("G3: 排空后环仍非空");
            else checks = checks + 1;
            ack_consume_at(8'd31);                       // 空环 ack → 协议错
            repeat (2) @(posedge clk_r);
            if (ring_ack_cnt != 1)
                fail($sformatf("G3: 空环 ack 错事件 得%0d 期1", ring_ack_cnt));
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, v);
            if (v[9] !== 1'b1) fail("G3: bit9(空环 ack) 未置位");
            else checks = checks + 1;

            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 1;
            $display("[RUN F7D] 完：G1-G3 毕 / rd %0d wr %0d", bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= RUN F7G（P2.2：真 GEMM 后端系统门）=================
    // K576 全卷（320 块）经 walker 派发 → ppu_gemm_engine V1.3 + 第二 DMA
    // （m1_axi → gbfm）：y 槽 gather 对拍（反散张量 sha 由 python 闭环）+
    // 双侧台账（GEMM 侧 553,088 读拍/3,200 写拍、shell 侧零拍）+ CSR
    // 结果面；F7G-2 写相位中段 abort → E_ABORTD 零字节冲刷 → wash 16 拍
    // → 无错无环 → 整卷重跑再对拍（恢复闭环，不复位）。
    localparam [31:0] F7G_YBASE = 32'h1043_8100;   // mirror_base + Y_OFF
    localparam integer F7G_EXP_RD = 553088;        // 96 param + 32 LUT + 552,960 载入
    localparam integer F7G_EXP_WR = 3200;          // 320 块 × vc(s) 拍
    reg [7:0] f7g_golden [0:25599];
    int f7g_widx [bit [31:0]];                     // 写日志 字地址→下标

    // gather 对拍 + 外排（f7g_y_got_runN.hex 供 python 反散 sha 闭环）
    // V1.8 修复同步：期望落点从 128*b 槽位律改紧凑累计律（引擎 V1.8
    // y_dst_off_q 游标；原律=板 H4 放置缺陷，sim 盲区根因）
    task automatic f7g_check_y(input integer run_id, output integer bad);
        integer b, s, j, g_off, eo, fd;
        reg [31:0] wa;
        reg [7:0] gv;
        begin
            bad = 0; g_off = 0; eo = 0;
            f7g_widx.delete();
            for (b = 0; b < gbfm.wr_n; b = b + 1)
                f7g_widx[gbfm.wr_addr_lg[b]] = b;
            if (f7g_widx.size() != gbfm.wr_n)
                fail("F7G: 写日志字地址重复（单帧不得复写）");
            fd = $fopen($sformatf("%s/f7g_y_got_run%0d.hex", prep_dir, run_id), "w");
            if (fd == 0) fail("F7G: y_got 外排打开失败");
            for (b = 0; b < 320; b = b + 1) begin
                s = (b / 8) % 2;
                for (j = 0; j < ((s == 0) ? 128 : 32); j = j + 1) begin
                    wa = F7G_YBASE + eo + j;
                    if (!f7g_widx.exists(wa & 32'hFFFF_FFF8)) begin
                        bad = bad + 1;
                        if (bad <= 8)
                            $display("[%0t] FAIL: F7G y 槽缺写拍 b=%0d j=%0d a=%08x",
                                     $time, b, j, wa);
                        $fwrite(fd, "00\n");
                    end else begin
                        if (gbfm.wr_strb_lg[f7g_widx[wa & 32'hFFFF_FFF8]] != 8'hFF)
                            fail($sformatf("F7G: 整卷写拍 strb 非 FF b=%0d", b));
                        gv = gbfm.wr_data_lg[f7g_widx[wa & 32'hFFFF_FFF8]]
                             [8*(wa[2:0]) +: 8];
                        $fwrite(fd, "%02x\n", gv);
                        // g_off 已逐字节自增——索引即 g_off 本身；先前
                        // g_off+j 双计=j+j 隔字比对（bad=21937 非 RTL 缺陷）
                        if (gv !== f7g_golden[g_off]) begin
                            bad = bad + 1;
                            if (bad <= 8)
                                $display("[%0t] FAIL: F7G y b=%0d j=%0d got=%02x want=%02x",
                                         $time, b, j, gv, f7g_golden[g_off]);
                        end
                    end
                    g_off = g_off + 1;
                end
                eo = eo + ((s == 0) ? 128 : 32);
            end
            $fclose(fd);
        end
    endtask

    task automatic run_f7g;
        integer v, i, bad;
        reg [31:0] dv;
        reg f7g2_wash_seen;
        begin
            $display("[RUN F7G] 真 GEMM 后端 K576 全卷 → 对拍 → abort/冲刷/wash/重跑");
            do_reset(5);
            cfg_default;
            g_cfg_default;
            cfg_csr_default;
            gbfm.load_preload({prep_dir, "/f7g_m1_preload.txt"});
            $readmemh({prep_dir, "/f7g_golden_gather.hex"}, f7g_golden);

            // desc 槽 0 = K576 正典（ABI v2，P2.1 台账冻结）
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32; v = v + 1) csr_wr(16'h1000 + 4*v, 32'h0);
            csr_wr(16'h1000 + 4*0,  32'h0000_0301); // valid+last+GEMM conv
            csr_wr(16'h1000 + 4*3,  32'h0014_0040); // {Ho=20, oc=64}
            csr_wr(16'h1000 + 4*4,  32'h0000_0014); // Wo=20
            csr_wr(16'h1000 + 4*8,  32'h1000_0000); // mirror 基址
            csr_wr(16'h1000 + 4*10, 32'h2000_0000); // param 基址
            csr_wr(16'h1000 + 4*11, 32'h0000_1240); // has_act=1, K=576
            csr_wr(16'h1000 + 4*14, 32'h0000_6400); // 环账字节数 25600

            // ---- F7G-1：全卷 ----
            csr_tail(16'd1);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7G-1 全卷");
            // 引擎事件 = walker W_ENG&&eng_err 脉冲（f6:267）——仅引擎错误才有
            // 事件，干净卷/干净 abort 均为 0（V1.4 轮实测 0 与语义一致，原期1 为笔误）
            if (eng_evt_cnt != 0)
                fail($sformatf("F7G-1: 引擎事件 得%0d 期0", eng_evt_cnt));
            else checks = checks + 1;
            wait_ring_pub(1, 200000, "F7G-1 发环");
            if (ring_bytes_w != 32'd25600)
                fail($sformatf("F7G-1: 环字节 得%0d 期25600", ring_bytes_w));
            if (ring_seq_w != 32'd1)   fail("F7G-1: seq != 1");
            if (ring_fid_w != 32'd0)   fail("F7G-1: frame_id != 0");
            if (shell_pub_cnt != 0)    fail("F7G-1: 不得 shell 侧发环");
            checks = checks + 4;
            check_csr_result(32'd1, 32'd0, 32'd25600, 8'd1, "F7G-1");
            if (gemm_log_q.size() != 1 || gemm_log_q[0] != 0)
                fail($sformatf("F7G-1: GEMM 派发 得%0d 条 期1/idx0",
                               gemm_log_q.size()));
            if (ppu_log_q.size() != 0) fail("F7G-1: 不得 PPU 派发");
            checks = checks + 2;
            // 台账：GEMM 侧正典拍数 + shell 侧零拍（端口隔离证明）
            if (gbfm.rd_n != F7G_EXP_RD)
                fail($sformatf("F7G-1: gbfm rd 得%0d 期%0d",
                               gbfm.rd_n, F7G_EXP_RD));
            if (gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7G-1: gbfm wr 得%0d 期%0d",
                               gbfm.wr_n, F7G_EXP_WR));
            if (bfm.rd_n != 0 || bfm.wr_n != 0)
                fail($sformatf("F7G-1: shell 侧流量 得rd%0d wr%0d 期0/0",
                               bfm.rd_n, bfm.wr_n));
            checks = checks + 3;
            f7g_check_y(1, bad);
            if (bad != 0) fail($sformatf("F7G-1: y 对拍 bad=%0d", bad));
            else checks = checks + 320;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7G-1: gbfm 协议违例 %0d", gbfm_proto_err));
            if (gbfm_unloaded != 0)
                fail($sformatf("F7G-1: gbfm 未装载拍 %0d", gbfm_unloaded));
            checks = checks + 2;

            // ---- F7G-2：写相位中段 abort → 冲刷/wash → 静默收口 ----
            gbfm.clear_logs;
            g_cfg_w_stall = 30;         // 拉写：abort 必落首块写相位
            csr_wr(A_FRAME_ID, 32'd1);
            csr_tail(16'd1);
            csr_start_frame;
            i = 0;
            while (gbfm.wr_n == 0 && i < 400_000) begin
                @(posedge clk_r); i = i + 1;
            end
            if (gbfm.wr_n == 0) fail("F7G-2: 未等到首写拍（写相位窗口失守）");
            else checks = checks + 1;
            repeat (3) @(posedge clk_r);
            g_cfg_check_en = 1'b0;      // 冲刷拍 strb=00 合法窗（头注 V1.1）
            csr_abort;
            wait_idle(200_000, "F7G-2 abort walker 释放");
            // 引擎收口：busy 落（E_ABORTD 冲刷完 → wr_done）→ wash 完 → 无 halt
            i = 0;
            while (dut.gemm_busy_w && i < 200_000) begin
                @(posedge clk_r); i = i + 1;
            end
            if (dut.gemm_busy_w) fail("F7G-2: 引擎 busy 未落（冲刷未收口）");
            else checks = checks + 1;
            repeat (4) @(posedge clk_r);    // wash 布防沿观测窗
            f7g2_wash_seen = 1'b0;
            i = 0;
            while (dut.gwash_cnt != 5'd0 && i < 1000) begin
                f7g2_wash_seen = 1'b1;
                @(posedge clk_r); i = i + 1;
            end
            if (!f7g2_wash_seen) fail("F7G-2: wash 未观测到（rcvr 边沿未触发）");
            if (dut.gwash_cnt != 5'd0) fail("F7G-2: wash 16 拍未收口");
            if (dut.gdma_halt_w) fail("F7G-2: gdma 不得 halt（abort 非错误）");
            checks = checks + 3;
            // 静默性：无环/无引擎事件/无描述符错/无错误位
            if (ring_pub_cnt != 1)   fail("F7G-2: abort 不得发环");
            if (eng_evt_cnt != 0)    fail("F7G-2: abort 不得记引擎事件");
            if (desc_evt_cnt != 0)   fail("F7G-2: abort 不得记描述符错");
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7G-2: ERROR_STATUS 非零 %03x", dv[10:0]));
            checks = checks + 4;
            // 写通道账目闭合：BFM aw 队列排空 + burst 内计数归零
            // （= orphan-AW 已被零字节冲刷闭环，shared-HP0 楔死隐患根除）
            if (gbfm.w_expect != 0)            fail("F7G-2: BFM aw/w 配对未闭合");
            if (gbfm.aw_addr_q.size() != 0)    fail("F7G-2: BFM aw 队列残留");
            if (gbfm_unloaded != 0)
                fail($sformatf("F7G-2: 未装载拍 %0d", gbfm_unloaded));
            checks = checks + 3;

            // ---- F7G-2R：整卷重跑（恢复闭环，不复位）----
            g_cfg_check_en = 1'b1;
            g_cfg_w_stall = 0;
            gbfm.clear_logs;
            csr_wr(A_FRAME_ID, 32'd2);
            csr_tail(16'd1);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7G-2R 重跑");
            wait_ring_pub(2, 200_000, "F7G-2R 发环");
            if (ring_bytes_w != 32'd25600) fail("F7G-2R: 环字节");
            else checks = checks + 1;
            check_csr_result(32'd2, 32'd2, 32'd25600, 8'd2, "F7G-2R");
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7G-2R: 台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            if (bfm.rd_n != 0 || bfm.wr_n != 0) fail("F7G-2R: shell 侧流量");
            checks = checks + 2;
            f7g_check_y(2, bad);
            if (bad != 0) fail($sformatf("F7G-2R: y 对拍 bad=%0d", bad));
            else checks = checks + 320;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7G-2R: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            wait_idle(1000, "F7G-2R");
            check_no_resume(200, 1, "F7G");
            $display("[RUN F7G] 完：全卷对拍 + abort/冲刷/wash/重跑毕 / g rd %0d wr %0d / shell rd %0d wr %0d",
                     gbfm.rd_n, gbfm.wr_n, bfm.rd_n, bfm.wr_n);
        end
    endtask

    localparam [31:0] F7S_YBASE2 = 32'h1143_8100;   // arena B(0x1100_0000)+Y_OFF(0x438100)
    reg [7:0] f7s2_golden [0:25599];                // 块轮转金像（区 B 期像）

    // F7S V2 双卷双区 y 对拍：全量写拍 containment（两 y 区之外零写拍）
    // + strb 全 FF + 无重复写 + 区 A 对 f7g_golden / 区 B 对 f7s2_golden
    // （两区独立 → 无复写掩盖；逐块 128/32 紧凑累计律同 f7g_check_y，
    //   末写优先不适用——双卷独立区本就无复写，重复即违规）。
    task automatic f7s_check_dual(input string tag, input integer run_id);
        integer b, s, j, g_off, eo, badc, bada, badb, fd;
        reg [31:0] wa;
        reg [7:0] gv;
        begin
            badc = 0; bada = 0; badb = 0;
            if (gbfm.wr_n != 2*F7G_EXP_WR)
                fail($sformatf("%s: 双卷写拍 得%0d 期%0d",
                               tag, gbfm.wr_n, 2*F7G_EXP_WR));
            else checks = checks + 1;
            f7g_widx.delete();
            for (b = 0; b < gbfm.wr_n; b = b + 1) begin
                wa = gbfm.wr_addr_lg[b];
                if (!((wa >= F7G_YBASE && wa < F7G_YBASE + 32'd25600) ||
                      (wa >= F7S_YBASE2 && wa < F7S_YBASE2 + 32'd25600))) begin
                    badc = badc + 1;
                    if (badc <= 8)
                        $display("[%0t] FAIL: %s 写拍越区 a=%08x", $time, tag, wa);
                end else begin
                    if (gbfm.wr_strb_lg[b] != 8'hFF) begin
                        badc = badc + 1;
                        if (badc <= 8)
                            $display("[%0t] FAIL: %s 写拍 strb=%02x a=%08x",
                                     $time, tag, gbfm.wr_strb_lg[b], wa);
                    end
                    if (f7g_widx.exists(wa)) begin
                        badc = badc + 1;
                        if (badc <= 8)
                            $display("[%0t] FAIL: %s 重复写 a=%08x", $time, tag, wa);
                    end
                    f7g_widx[wa] = b;
                end
            end
            if (badc != 0) fail($sformatf("%s: 写拍 containment bad=%0d", tag, badc));
            else checks = checks + 1;
            // 区 A（f7g_golden）
            fd = $fopen($sformatf("%s/f7s_y_got_run%0d_a.hex", prep_dir, run_id), "w");
            if (fd == 0) fail($sformatf("%s: 区A y_got 外排打开失败", tag));
            g_off = 0; eo = 0;
            for (b = 0; b < 320; b = b + 1) begin
                s = (b / 8) % 2;
                for (j = 0; j < ((s == 0) ? 128 : 32); j = j + 1) begin
                    wa = F7G_YBASE + eo + j;
                    gv = 8'h00;
                    if (!f7g_widx.exists(wa & 32'hFFFF_FFF8)) begin
                        bada = bada + 1;
                        if (bada <= 8)
                            $display("[%0t] FAIL: %s 区A缺写 b=%0d j=%0d a=%08x",
                                     $time, tag, b, j, wa);
                    end else begin
                        gv = gbfm.wr_data_lg[f7g_widx[wa & 32'hFFFF_FFF8]]
                             [8*wa[2:0] +: 8];
                        if (gv !== f7g_golden[g_off]) begin
                            bada = bada + 1;
                            if (bada <= 8)
                                $display("[%0t] FAIL: %s 区A y b=%0d got=%02x want=%02x",
                                         $time, tag, b, gv, f7g_golden[g_off]);
                        end
                    end
                    $fwrite(fd, "%02x\n", gv);
                    g_off = g_off + 1;
                end
                eo = eo + ((s == 0) ? 128 : 32);
            end
            $fclose(fd);
            if (bada != 0) fail($sformatf("%s: 区A y 对拍 bad=%0d", tag, bada));
            else checks = checks + 320;
            // 区 B（f7s2_golden，块轮转金像）
            fd = $fopen($sformatf("%s/f7s_y_got_run%0d_b.hex", prep_dir, run_id), "w");
            if (fd == 0) fail($sformatf("%s: 区B y_got 外排打开失败", tag));
            g_off = 0; eo = 0;
            for (b = 0; b < 320; b = b + 1) begin
                s = (b / 8) % 2;
                for (j = 0; j < ((s == 0) ? 128 : 32); j = j + 1) begin
                    wa = F7S_YBASE2 + eo + j;
                    gv = 8'h00;
                    if (!f7g_widx.exists(wa & 32'hFFFF_FFF8)) begin
                        badb = badb + 1;
                        if (badb <= 8)
                            $display("[%0t] FAIL: %s 区B缺写 b=%0d j=%0d a=%08x",
                                     $time, tag, b, j, wa);
                    end else begin
                        gv = gbfm.wr_data_lg[f7g_widx[wa & 32'hFFFF_FFF8]]
                             [8*wa[2:0] +: 8];
                        if (gv !== f7s2_golden[g_off]) begin
                            badb = badb + 1;
                            if (badb <= 8)
                                $display("[%0t] FAIL: %s 区B y b=%0d got=%02x want=%02x",
                                         $time, tag, b, gv, f7s2_golden[g_off]);
                        end
                    end
                    $fwrite(fd, "%02x\n", gv);
                    g_off = g_off + 1;
                end
                eo = eo + ((s == 0) ? 128 : 32);
            end
            $fclose(fd);
            if (badb != 0) fail($sformatf("%s: 区B y 对拍 bad=%0d", tag, badb));
            else checks = checks + 320;
        end
    endtask

    // ---- F7S（P2.3 修复验证 V2）：槽>=1 跨距 32（引擎 V2.0）+ 引擎错
    //      上下文锁存（walker V3.1 / C 项）----
    // V1.4 红灯取证已闭环（A 腿槽1 无影子 → 引擎 16 跨址抓全 0 → EC_GEOM；
    // B 腿补影子 5 字 → 双卷金像 = 机制对照）。引擎 V2.0 五址改
    // {idx[6:0],5'w}（跨距 32）+ walker V3.1 引擎错路径同拍锁
    // err_op_o/err_desc_id_o 后，本门改修复后正典三腿：
    //   F7S-1 双卷独立区不同负载：槽0 正典卷（arena A）+ 槽1 valid+last
    //     （arena B=块轮转镜像——逐块 GEMM 独立性(K=576 全归约/逐块参数
    //     复取)使金像恰为块轮转金像，字节级可算）。两卷 y 区独立
    //     （0x1043_8100 / 0x1143_8100）→ 无复写掩盖；旧码 16 跨址消费的
    //     表字 19/20/24/26/27 预置毒值（w11 取 K=4095 → 旧码在此必
    //     EC_GEOM；新码读 35/36/40/42/43 不触、毒值驻留）——红灯/绿灯
    //     判别自足，且不复用 V1.4 的"补影子喂对"方向。
    //   F7S-2 C 负例（GEMM 面）：槽0 合法卷跑完后槽1 合法 opcode+非法
    //     K=999 → EC_GEOM（DMA 前）：ERROR_INFO port=5/desc_id=1/op=0x01/
    //     code=02（旧码引擎错路径不锁存 → desc_id 恒陈旧 0，B5 槽0
    //     掩盖、V1.4 run1 首次暴露）+ bit10 粘着 + 单卷台账停 + 无新
    //     发环/无新完成帧。
    //   F7S-3 恢复：soft_reset → 槽1 复法 → 双卷重跑全对拍（非零槽合法
    //     复证 + 上下文/恢复闭环）。
    task automatic run_f7s;
        integer v, bad;
        reg [31:0] dv;
        begin
            $display("[RUN F7S] P2.3 修复验证：槽>=1 跨距 32（引擎 V2.0）+ 引擎错上下文锁存（walker V3.1）");
            do_reset(5); cfg_default; g_cfg_default; cfg_csr_default;
            gbfm.load_preload({prep_dir, "/f7g_m1_preload.txt"});
            gbfm.load_preload({prep_dir, "/f7s2_m1_preload.txt"});
            $readmemh({prep_dir, "/f7g_golden_gather.hex"}, f7g_golden);
            $readmemh({prep_dir, "/f7s2_golden_rot.hex"}, f7s2_golden);

            // ---- 表装载：槽0 正典（无 last，arena A）+ 槽1（valid+last，
            //      arena B 0x1100_0000）+ 毒值影字（旧 16 跨址落点）----
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 64; v = v + 1) csr_wr(16'h1000 + 4*v, 32'h0);
            csr_wr(16'h1000 + 4*0,  32'h0000_0101); // 槽0 valid（无 last → 帧续走槽1）
            csr_wr(16'h1000 + 4*3,  32'h0014_0040); // {Ho=20, oc=64}
            csr_wr(16'h1000 + 4*4,  32'h0000_0014); // Wo=20
            csr_wr(16'h1000 + 4*8,  32'h1000_0000); // arena A mirror 基址
            csr_wr(16'h1000 + 4*10, 32'h2000_0000); // param 基址
            csr_wr(16'h1000 + 4*11, 32'h0000_1240); // has_act=1, K=576
            csr_wr(16'h1000 + 4*14, 32'h0000_6400); // 环账 25600
            csr_wr(16'h1000 + 4*32 + 4*0,  32'h0000_0301); // 槽1 valid+last
            csr_wr(16'h1000 + 4*32 + 4*3,  32'h0014_0040);
            csr_wr(16'h1000 + 4*32 + 4*4,  32'h0000_0014);
            csr_wr(16'h1000 + 4*32 + 4*8,  32'h1100_0000); // arena B 基址（块轮转载荷）
            csr_wr(16'h1000 + 4*32 + 4*10, 32'h2000_0000);
            csr_wr(16'h1000 + 4*32 + 4*11, 32'h0000_1240);
            csr_wr(16'h1000 + 4*32 + 4*14, 32'h0000_6400);
            // 毒值影字：旧码槽1 读址 {1,4'dw}=19/20/24/26/27（w11 毒值
            // K=4095 非法 → 旧码必 EC_GEOM 红灯）；新码读 35/36/40/42/43
            csr_wr(16'h1000 + 4*19, 32'hDEAD_BEEF);
            csr_wr(16'h1000 + 4*20, 32'hCAFE_F00D);
            csr_wr(16'h1000 + 4*24, 32'hBADC_0DE0);
            csr_wr(16'h1000 + 4*26, 32'hFEED_FACE);
            csr_wr(16'h1000 + 4*27, 32'h0000_0FFF);

            // ---- F7S-1：双卷独立区（不同负载，无影子喂对）----
            $display("[RUN F7S/1] 槽0 arena A + 槽1 arena B（块轮转）：期双卷干净+双区金像");
            csr_wr(A_FRAME_ID, 32'd1);
            csr_tail(16'd2);
            csr_start_frame;
            wait_walk_done(2, 6_000_000, "F7S-1 双卷");
            wait_ring_pub(1, 200000, "F7S-1 发环");
            if (eng_evt_cnt != 0)
                fail($sformatf("F7S-1: 引擎事件 得%0d 期0", eng_evt_cnt));
            else checks = checks + 1;
            if (gemm_log_q.size() != 2 || gemm_log_q[0] != 0
                || gemm_log_q[1] != 1)
                fail($sformatf("F7S-1: GEMM 派发 得%0d 条 期2/idx{0,1}",
                               gemm_log_q.size()));
            else checks = checks + 1;
            if (ppu_log_q.size() != 0) fail("F7S-1: 不得 PPU 派发");
            else checks = checks + 1;
            if (ring_bytes_w != 32'd51200)
                fail($sformatf("F7S-1: 环字节 得%0d 期51200（2x25600）",
                               ring_bytes_w));
            else checks = checks + 1;
            if (ring_seq_w != 32'd1 || ring_fid_w != 32'd1)
                fail($sformatf("F7S-1: seq/fid 得%0d/%0d 期1/1",
                               ring_seq_w, ring_fid_w));
            else checks = checks + 1;
            check_csr_result(32'd1, 32'd1, 32'd51200, 8'd1, "F7S-1");
            if (gbfm.rd_n != 2*F7G_EXP_RD || gbfm.wr_n != 2*F7G_EXP_WR)
                fail($sformatf("F7S-1: m1 台账 得rd%0d wr%0d 期%0d/%0d（2x）",
                               gbfm.rd_n, gbfm.wr_n,
                               2*F7G_EXP_RD, 2*F7G_EXP_WR));
            else checks = checks + 1;
            if (bfm.rd_n != 0 || bfm.wr_n != 0) fail("F7S-1: shell 侧流量");
            else checks = checks + 1;
            f7s_check_dual("F7S-1", 1);
            // 毒值影字驻留（新码零消费的直接钉：5 字原样可回读）
            bad = 0;
            csr_rd(16'h1000 + 4*19, dv); if (dv !== 32'hDEAD_BEEF) bad = bad + 1;
            csr_rd(16'h1000 + 4*20, dv); if (dv !== 32'hCAFE_F00D) bad = bad + 1;
            csr_rd(16'h1000 + 4*24, dv); if (dv !== 32'hBADC_0DE0) bad = bad + 1;
            csr_rd(16'h1000 + 4*26, dv); if (dv !== 32'hFEED_FACE) bad = bad + 1;
            csr_rd(16'h1000 + 4*27, dv); if (dv !== 32'h0000_0FFF) bad = bad + 1;
            if (bad != 0) fail($sformatf("F7S-1: 毒值影字被扰 bad=%0d", bad));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7S-1: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            wait_idle(1000, "F7S-1 收口");
            check_no_resume(200, 2, "F7S-1");
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7S-1: ack 后环仍非空");
            else checks = checks + 1;
            gbfm.clear_logs;                        // F7S-2 台账窗重起

            // ---- F7S-2：C 负例（槽1 合法 opcode + 非法 K=999）----
            csr_wr(16'h1000 + 4*32 + 4*11, 32'h0000_13E7); // has_act=1, K=999
            $display("[RUN F7S/2] 槽1 非法 K → 期 ERROR_INFO port5/desc1/op01/code02");
            csr_wr(A_FRAME_ID, 32'd2);
            csr_tail(16'd2);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7S-2 槽0 卷");
            wait_evt_cnt(1, "F7S-2 槽1 EC_GEOM 引擎错");
            repeat (300) @(posedge clk_r);          // W_ERR 粘着窗
            if (wk_idle_w) fail("F7S-2: W_ERR 不得自行回 idle");
            else checks = checks + 1;
            if (wk_done_w != 1)
                fail($sformatf("F7S-2: done 得%0d 期1（槽0 完成、槽1 不计）",
                               wk_done_w));
            else checks = checks + 1;
            if (ring_pub_cnt != 1) fail("F7S-2: 引擎错不得发环");
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b1)
                fail($sformatf("F7S-2: bit10 得%b 期1（全字 %03X）",
                               dv[10], dv[10:0]));
            else checks = checks + 1;
            csr_rd(A_ERROR_INFO, dv);
            $display("[RUN F7S/2] ERROR_INFO = %08X（port/desc_id/op/code）", dv);
            // C 修复判据（walker V3.1）：desc_id=1/op=0x01——旧码引擎错
            // 路径只发事件不锁存，desc_id 恒复位陈旧 0（B5 槽0 负例掩盖，
            // V1.4 F7S run1 idx=1 首次暴露）
            if (dv[31:24] !== 8'h05 || dv[23:16] !== 8'd1
                || dv[15:8] !== 8'h01 || dv[7:0] !== 8'h02)
                fail($sformatf("F7S-2: err_info 得 port%0d desc%0d op%02x code%02x 期5/1/01/02",
                               dv[31:24], dv[23:16], dv[15:8], dv[7:0]));
            else checks = checks + 4;
            // 台账：槽1 错在 DMA 前 → 停单卷；无成功帧（结果面停留 F7S-1）
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7S-2: m1 台账 得rd%0d wr%0d 期%0d/%0d（单卷）",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            else checks = checks + 1;
            csr_rd(A_RESULT_SEQ, dv);
            if (dv !== 32'd1) fail("F7S-2: 无新完成帧（RESULT_SEQ 须停留 1）");
            else checks = checks + 1;
            if (bfm.rd_n != 0 || bfm.wr_n != 0) fail("F7S-2: shell 侧流量");
            else checks = checks + 1;
            check_frozen(200, 1, "F7S-2");

            // ---- F7S-3：恢复后再跑合法非零槽（双卷复证）----
            csr_soft;
            wait_idle(1000, "F7S-2 soft_reset 释放");
            cfg_csr_default;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b0) fail("F7S-2: soft_reset 后 bit10 须 0");
            else checks = checks + 1;
            gbfm.clear_logs;
            // 表 BRAM 驻留（soft_reset 不清表，F7S-B 腿正典）——槽1 复法
            csr_wr(16'h1000 + 4*32 + 4*11, 32'h0000_1240); // K=576 复法
            $display("[RUN F7S/3] 恢复后双卷复跑：期上下文清+双区金像复现");
            csr_wr(A_FRAME_ID, 32'd3);
            csr_tail(16'd2);
            csr_start_frame;
            wait_walk_done(2, 6_000_000, "F7S-3 双卷复跑");
            wait_ring_pub(2, 200000, "F7S-3 发环");
            if (eng_evt_cnt != 1)
                fail($sformatf("F7S-3: 引擎事件 得%0d 期1（不新增）", eng_evt_cnt));
            else checks = checks + 1;
            if (ring_bytes_w != 32'd51200)
                fail($sformatf("F7S-3: 环字节 得%0d 期51200", ring_bytes_w));
            else checks = checks + 1;
            // V1.6.1：环状态（seq/head/tail/entries）穿 csr_soft 持续、仅 ack
            // 消费（do_reset 才全清）——F7S-3 为第 2 次发环：seq=2、条目@1、
            // head=2、ack@2。板侧 pl_p25 两帧 seq=1→2 同律互证。
            if (ring_seq_w != 32'd2 || ring_fid_w != 32'd3)
                fail($sformatf("F7S-3: seq/fid 得%0d/%0d 期2/3（环 seq 穿软复位单调续）",
                               ring_seq_w, ring_fid_w));
            else checks = checks + 1;
            check_csr_result(32'd2, 32'd3, 32'd51200, 8'd2, "F7S-3");
            if (gbfm.rd_n != 2*F7G_EXP_RD || gbfm.wr_n != 2*F7G_EXP_WR)
                fail($sformatf("F7S-3: m1 台账 得rd%0d wr%0d 期%0d/%0d（2x）",
                               gbfm.rd_n, gbfm.wr_n,
                               2*F7G_EXP_RD, 2*F7G_EXP_WR));
            else checks = checks + 1;
            f7s_check_dual("F7S-3", 3);
            wait_idle(1000, "F7S-3 收口");
            check_no_resume(200, 2, "F7S-3");
            ack_consume_at(8'd2);
            if (ring_ne_w) fail("F7S-3: ack 后环仍非空");
            else checks = checks + 1;

            // ---- F7S-4：软复位零重配 DMA_CFG（V1.7 案 1 判别）----
            // 板探针 2/3 楔死面首次仿真复现径：soft 全量擦洗后 dma_cfg=0
            // （outst=0 零事务 + timeout=0 看门狗关）→ 旧码 E_PRMREQ 静默
            // 死等。ppu_dma_master V1.3 钳位（outst 0→1、timeout 0→100）
            // 后此径须与正典配置逐面等价（金像/环/台账全同 F7S-3）。
            csr_soft;
            wait_idle(1000, "F7S-4 soft_reset 释放");
            // cfg_csr_default 减 A_DMA_CFG 一项（其余逐项同写——保证差异
            // 面仅 DMA_CFG 一项）
            csr_ctrl(8'h00);                              // enable=1
            csr_wr(A_HEAD_BASE_LO, 32'h1F80_0000);
            csr_wr(A_HEAD_BASE_HI, 32'h0);
            csr_wr(A_HEAD_FORMAT, 32'h0);
            csr_wr(A_DESC_CFG, 32'h0);
            csr_rd(A_DMA_CFG, dv);
            if (dv !== 32'h0)
                fail($sformatf("F7S-4: DMA_CFG 得%08X 期0（擦洗驻留=判别前提）", dv));
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b0) fail("F7S-4: soft 后 bit10 须 0");
            else checks = checks + 1;
            gbfm.clear_logs;
            $display("[RUN F7S/4] 软复位零重配双卷（dma_cfg=0 钳位径）：期全绿");
            csr_wr(A_FRAME_ID, 32'd4);
            csr_tail(16'd2);
            csr_start_frame;
            wait_walk_done(2, 12_000_000, "F7S-4 零重配双卷");
            wait_ring_pub(3, 200000, "F7S-4 发环");
            if (eng_evt_cnt != 1)
                fail($sformatf("F7S-4: 引擎事件 得%0d 期1（不新增）", eng_evt_cnt));
            else checks = checks + 1;
            if (ring_bytes_w != 32'd51200)
                fail($sformatf("F7S-4: 环字节 得%0d 期51200", ring_bytes_w));
            else checks = checks + 1;
            // 环续行律（V1.6.1）：第 3 次发环 seq=3、条目@2、head=3
            if (ring_seq_w != 32'd3 || ring_fid_w != 32'd4)
                fail($sformatf("F7S-4: seq/fid 得%0d/%0d 期3/4（环 seq 穿软复位单调续）",
                               ring_seq_w, ring_fid_w));
            else checks = checks + 1;
            check_csr_result(32'd3, 32'd4, 32'd51200, 8'd3, "F7S-4");
            if (gbfm.rd_n != 2*F7G_EXP_RD || gbfm.wr_n != 2*F7G_EXP_WR)
                fail($sformatf("F7S-4: m1 台账 得rd%0d wr%0d 期%0d/%0d（2x，钳位径流量不变）",
                               gbfm.rd_n, gbfm.wr_n,
                               2*F7G_EXP_RD, 2*F7G_EXP_WR));
            else checks = checks + 1;
            f7s_check_dual("F7S-4", 4);
            wait_idle(1000, "F7S-4 收口");
            check_no_resume(200, 2, "F7S-4");
            ack_consume_at(8'd3);
            if (ring_ne_w) fail("F7S-4: ack 后环仍非空");
            else checks = checks + 1;
            $display("[RUN F7S] 完：F7S-1 双卷双区金像（跨距 32+毒值零消费）+ F7S-2 引擎错上下文 desc_id=1/op=01 + F7S-3 恢复复证 + F7S-4 软复位零重配钳位径 / g rd %0d wr %0d",
                     gbfm.rd_n, gbfm.wr_n);
        end
    endtask

    // ---- F7M（子图梯一级）：conv@槽0 + 25 PPU 任务混合程序 ----
    // 当前 RTL 即支持的形态（conv 合法槽 0 + PPU 任务任意槽），POST_V19
    // §P2"单Conv→子图"梯的第一级力学门。B5 只证混排里的引擎错误路径，
    // 本门补"引擎成功卷居程序首 + 顺序屏障放行 + PPU 后续干净走完"。
    // ================= F7L2（子图梯二级：2conv+桥接，种子法）=================
    // conv0@槽0 → mp5@槽1 → conv1@槽2(valid+last)；prep 产最终域三表
    // （desc 96 字 / buf 全 1024 含 producer 补丁 / quant 拷贝）。
    localparam [31:0] F7L2_Y0    = 32'h100F_0100;   // M0+0x100+983040
    localparam [31:0] F7L2_Y1    = 32'h110C_A900;   // M1+0x100+829440
    localparam integer F7L2_EGRD = 226852;          // 192+32+122880 | 36+32+103680
    localparam integer F7L2_EGWR = 1900;            // y0 1600 + y1 300 拍
    localparam integer F7L2_ERD  = 1600;            // mp5 读 buf44
    localparam integer F7L2_EWR  = 1600;            // mp5 写 buf45
    reg [7:0] f7l2_g0 [0:12799];                    // y0 gather 紧凑金像
    reg [7:0] f7l2_g1 [0:2399];                     // y1 gather 紧凑金像
    int f7l2_widx [bit [31:0]];                     // 写日志 字地址→下标

    // 参数化 y 窗对拍（which=0→y0/1→y1）：整拍 strb=FF + 逐字节金像 + 缺写
    // 拍计数 + 取证外排（f7l2_y_got_{which}.hex）。
    task automatic f7l2_check_y(input [31:0] base, input integer nbytes,
                                input integer which, input string tag,
                                output integer bad);
        integer b, j, fd;
        reg [31:0] wa;
        reg [7:0] gv, gw;
        begin
            bad = 0;
            f7l2_widx.delete();
            for (b = 0; b < gbfm.wr_n; b = b + 1)
                f7l2_widx[gbfm.wr_addr_lg[b]] = b;
            if (f7l2_widx.size() != gbfm.wr_n)
                fail($sformatf("%s: 写日志字地址重复（单帧不得复写）", tag));
            fd = $fopen($sformatf("%s/f7l2_y_got_%0d.hex", prep_dir, which), "w");
            if (fd == 0) fail($sformatf("%s: y_got 外排打开失败", tag));
            for (j = 0; j < nbytes; j = j + 1) begin
                wa = base + j;
                if (!f7l2_widx.exists(wa & 32'hFFFF_FFF8)) begin
                    bad = bad + 1;
                    if (bad <= 8)
                        $display("[%0t] FAIL: %s y 缺写拍 j=%0d a=%08x",
                                 $time, tag, j, wa);
                    $fwrite(fd, "00\n");
                end else begin
                    if (gbfm.wr_strb_lg[f7l2_widx[wa & 32'hFFFF_FFF8]] != 8'hFF)
                        fail($sformatf("%s: y 写拍 strb 非 FF j=%0d", tag, j));
                    gv = gbfm.wr_data_lg[f7l2_widx[wa & 32'hFFFF_FFF8]]
                         [8*(wa[2:0]) +: 8];
                    gw = (which == 0) ? f7l2_g0[j] : f7l2_g1[j];
                    $fwrite(fd, "%02x\n", gv);
                    if (gv !== gw) begin
                        bad = bad + 1;
                        if (bad <= 8)
                            $display("[%0t] FAIL: %s y j=%0d got=%02x want=%02x",
                                     $time, tag, j, gv, gw);
                    end
                end
            end
            $fclose(fd);
        end
    endtask

    task automatic run_f7l2;
        integer v, bad, bad1;
        longint unsigned exp_bytes;
        reg [31:0] dv;
        begin
            $display("[RUN F7L2] 子图梯二级：conv0@0(K256) → mp5@1 → conv1@2(K1152,last) 种子法");
            do_reset(5); cfg_default; g_cfg_default; cfg_csr_default;
            gbfm.load_preload({prep_dir, "/f7l2_m1_preload.txt"});
            bfm.load_preload({prep_dir, "/f7l2_bfm_preload.txt"});
            $readmemh({prep_dir, "/f7l2_golden_y0.hex"}, f7l2_g0);
            $readmemh({prep_dir, "/f7l2_golden_y1.hex"}, f7l2_g1);
            // 三表直读（prep 已产最终域：无紧凑、无重映射）
            $readmemh({prep_dir, "/desc_table_l2.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_l2.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_l2.hex"}, qt_rom);
            // desc 窗装载（3 槽 96 字）+ 全量回读
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*3; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            for (v = 0; v < 32*3; v = v + 1) begin
                csr_rd(16'h1000 + 4*v, dv);
                if (dv !== desc_rom[v])
                    fail($sformatf("F7L2: desc 回读 w%0d 得%08X 期%08X",
                                   v, dv, desc_rom[v]));
            end
            if (errors == 0) checks = checks + 1;
            load_buf_win("F7L2");
            load_qt_win("F7L2");

            // ---- 混合帧三任务链 ----
            csr_tail(16'd3);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7L2 conv0 槽0");
            if (eng_evt_cnt != 0)
                fail($sformatf("F7L2: conv0 干净卷引擎事件 得%0d 期0", eng_evt_cnt));
            else checks = checks + 1;
            // 屏障 1（引擎→shell）：conv0 完成拍 PPU 派发必为 0
            if (ppu_log_q.size() != 0)
                fail($sformatf("F7L2: conv0 完成前 PPU 派发 得%0d 期0",
                               ppu_log_q.size()));
            else checks = checks + 1;
            wait_walk_done(2, 3_000_000, "F7L2 mp5 槽1");
            // mp5 逐字节（conv0 零 bfm 流量 → 滑动窗 mark 从 0 起）
            cmp_golden("rd", 44, 0, "F7L2", 0);
            cmp_golden("wr", 44, 0, "F7L2", 0);
            // 屏障 2（shell→引擎 反向衔接首证）：mp5 完成拍 GEMM 派发仅 1
            if (gemm_log_q.size() != 1)
                fail($sformatf("F7L2: mp5 完成前 GEMM 派发 得%0d 期1",
                               gemm_log_q.size()));
            else checks = checks + 1;
            wait_walk_done(3, 3_000_000, "F7L2 conv1 槽2");
            if (eng_evt_cnt != 0)
                fail($sformatf("F7L2: conv1 干净卷引擎事件 得%0d 期0", eng_evt_cnt));
            else checks = checks + 1;

            // ---- 发环（槽2 原生 last）+ 混合 w14 环账 ----
            wait_ring_pub(1, 200_000, "F7L2 发环");
            exp_bytes = sum_range(0, 2);           // 12800+12800+2400
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7L2: 环字节 得%0d 期%0d（12800+12800+2400）",
                               ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            if (ring_seq_w != 32'd1) fail("F7L2: seq != 1");
            else checks = checks + 1;
            if (ring_fid_w != 32'd0) fail("F7L2: fid != 0");
            else checks = checks + 1;
            check_csr_result(32'd1, 32'd0, exp_bytes, 8'd1, "F7L2");
            check_desc_csr(16'd3, 16'd3, "F7L2");

            // ---- 派发面 ----
            if (gemm_log_q.size() != 2 || gemm_log_q[0] != 0 || gemm_log_q[1] != 2)
                fail($sformatf("F7L2: GEMM 派发 得%0d 期2/idx{0,2}",
                               gemm_log_q.size()));
            else checks = checks + 1;
            if (ppu_log_q.size() != 1 || ppu_log_q[0] != 1)
                fail($sformatf("F7L2: PPU 派发 得%0d 期1/idx1", ppu_log_q.size()));
            else checks = checks + 1;

            // ---- 台账钉值（双引擎镜像账 + shell 账）----
            if (gbfm.rd_n != F7L2_EGRD || gbfm.wr_n != F7L2_EGWR)
                fail($sformatf("F7L2: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7L2_EGRD, F7L2_EGWR));
            else checks = checks + 2;
            if (bfm.rd_n != F7L2_ERD || bfm.wr_n != F7L2_EWR)
                fail($sformatf("F7L2: shell 侧台账 得rd%0d wr%0d 期%0d/%0d",
                               bfm.rd_n, bfm.wr_n, F7L2_ERD, F7L2_EWR));
            else checks = checks + 2;
            if (bfm_proto_err != 0)
                fail($sformatf("F7L2: bfm 协议违例 %0d", bfm_proto_err));
            else checks = checks + 1;
            if (bfm_unloaded != 0)
                fail($sformatf("F7L2: bfm 未装载拍 %0d", bfm_unloaded));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7L2: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            if (gbfm_unloaded != 0)
                fail($sformatf("F7L2: gbfm 未装载拍 %0d", gbfm_unloaded));
            else checks = checks + 1;

            // ---- y 双窗 gather 金像（写日志重建）----
            f7l2_check_y(F7L2_Y0, 12800, 0, "F7L2 y0", bad);
            f7l2_check_y(F7L2_Y1, 2400, 1, "F7L2 y1", bad1);
            if (bad != 0 || bad1 != 0)
                fail($sformatf("F7L2: y 对拍 bad0=%0d bad1=%0d", bad, bad1));
            else checks = checks + 2;

            // ---- 错误面干净 + idle/停走 + ack 清环 ----
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7L2: ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            wait_idle(1000, "F7L2");
            check_no_resume(200, 3, "F7L2");
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7L2: ack 后环仍非空");
            else checks = checks + 1;
            $display("[RUN F7L2] 完：三任务链（conv0→mp5→conv1）屏障双向 / 环 %0d B / g rd %0d wr %0d / shell rd %0d wr %0d",
                     exp_bytes, gbfm.rd_n, gbfm.wr_n, bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= F7W（B3-S3 S3a-W：walker 多 desc 协议专证门）=================
    // AUDIT 2026-09-30_b3s3_claude_audit_run01：单帧多 desc 只是 walker
    // 协议测试，与真实级联门（S3a-R 板门）分立正名；本门只证协议面
    // （计数/闭帧/表锁循环），数据面归 F7L2 正典，prep 零新增。
    task automatic run_f7w;
        integer v;
        longint unsigned exp_bytes;
        reg [31:0] dv, orig44, orig45, lock_bits;
        begin
            $display("[RUN F7W] S3a-W 协议门：W1 三 desc 末 last 闭帧 + W2 三 desc 无 last ffe 闭帧");
            do_reset(5); cfg_default; g_cfg_default; cfg_csr_default;
            gbfm.load_preload({prep_dir, "/f7l2_m1_preload.txt"});
            bfm.load_preload({prep_dir, "/f7l2_bfm_preload.txt"});
            $readmemh({prep_dir, "/desc_table_l2.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_l2.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_l2.hex"}, qt_rom);
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*3; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            for (v = 0; v < 32*3; v = v + 1) begin
                csr_rd(16'h1000 + 4*v, dv);
                if (dv !== desc_rom[v])
                    fail($sformatf("F7W: desc 回读 w%0d 得%08X 期%08X",
                                   v, dv, desc_rom[v]));
            end
            if (errors == 0) checks = checks + 1;
            load_buf_win("F7W");
            load_qt_win("F7W");
            // 留档 buf44/45 producer 字（解锁正面/表内容不变判据用）
            csr_rd(16'h3000 + 4*(8*44+6), orig44);
            csr_rd(16'h3000 + 4*(8*45+6), orig45);

            // ---- W1：三 desc 末 last 闭帧（计数/单环/解锁正面）----
            csr_tail(16'd3);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7W1 conv0 槽0");
            wait_walk_done(2, 3_000_000, "F7W1 mp5 槽1");
            if (ring_pub_cnt != 0)
                fail("F7W1: last 完成前出现发环");
            else checks = checks + 1;
            if (gemm_log_q.size() != 1 || ppu_log_q.size() != 1)
                fail($sformatf("F7W1: mp5 完成拍派发 GEMM=%0d PPU=%0d 期1/1",
                               gemm_log_q.size(), ppu_log_q.size()));
            else checks = checks + 1;
            wait_walk_done(3, 3_000_000, "F7W1 conv1 槽2");
            // （无提前发环已由 done==2 拍格证；done==3 与发环仅数拍距，
            //  此处不设竞态格）
            wait_ring_pub(1, 200_000, "F7W1 发环");
            exp_bytes = sum_range(0, 2);            // 12800+12800+2400
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7W1: 环字节 得%0d 期%0d（Σw14 单条目）",
                               ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            if (ring_seq_w != 32'd1) fail("F7W1: seq != 1");
            else checks = checks + 1;
            if (ring_fid_w != 32'd0) fail("F7W1: fid != 0");
            else checks = checks + 1;
            check_csr_result(32'd1, 32'd0, exp_bytes[31:0], 8'd1, "F7W1");
            check_desc_csr(16'd3, 16'd3, "F7W1");
            csr_rd(A_DESC_CURRENT, dv);
            if (dv[15:0] !== 16'd2)
                fail($sformatf("F7W1: DESC_CURRENT 得%0d 期2（末 desc 槽）",
                               dv[15:0]));
            else checks = checks + 1;
            if (gemm_log_q.size() != 2 || gemm_log_q[0] != 0
                || gemm_log_q[1] != 2 || ppu_log_q.size() != 1
                || ppu_log_q[0] != 1)
                fail($sformatf("F7W1: 派发序 GEMM=%0d PPU=%0d 期{0,2}/{1}",
                               gemm_log_q.size(), ppu_log_q.size()));
            else checks = checks + 1;
            wait_idle(1000, "F7W1");
            // 解锁正面：闭帧后表窗写回同值须 OKAY（F7D 只证锁住负面）
            csr_wr(16'h3000 + 4*(8*44+6), orig44);
            if (mcsr.last_bresp_o !== 2'b00)
                fail($sformatf("F7W1: 闭帧后表窗写 bresp=%b 期OKAY",
                               mcsr.last_bresp_o));
            else checks = checks + 1;
            csr_rd(16'h3000 + 4*(8*44+6), dv);
            if (dv !== orig44) fail("F7W1: 解锁写回后回读失配");
            else checks = checks + 1;
            check_no_resume(200, 3, "F7W1");
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7W1: ack 后环仍非空");
            else checks = checks + 1;

            // ---- W2：三 desc 无 last + ffe 闭帧（宿主桥帧板级同构）----
            csr_wr(16'h1000 + 4*32*2, 32'h0000_0101);   // 槽2 w0 清 last
            csr_rd(16'h1000 + 4*32*2, dv);
            if (dv !== 32'h0000_0101)
                fail($sformatf("F7W2: 槽2 清 last 回读 得%08X 期00000101", dv));
            else checks = checks + 1;
            csr_wr(A_FRAME_ID, 32'd1);
            csr_tail(16'd3);
            csr_start_frame;
            wait_walk_done(3, 3_000_000, "F7W2 三 desc 全成");
            check_desc_csr(16'd3, 16'd3, "F7W2");
            // 停泊面：W_CHK 自旋为设计语义——非 idle、RUNNING=1、EMPTY=1
            if (wk_idle_w) fail("F7W2: 队列空后提前 idle（应 W_CHK 停泊）");
            else checks = checks + 1;
            csr_rd(A_STATUS, dv);
            if (dv[0] !== 1'b0 || dv[1] !== 1'b1 || dv[4] !== 1'b1)
                fail($sformatf("F7W2: 停泊 STATUS IDLE=%b RUNNING=%b EMPTY=%b 期0/1/1",
                               dv[0], dv[1], dv[4]));
            else checks = checks + 1;
            if (ring_pub_cnt != 1)
                fail("F7W2: ffe 前新发环（无 last 停泊不得发环）");
            else checks = checks + 1;
            // 停泊期表窗写：SLVERR（F7D 锁律在本态复钉；读回不变移到
            // 闭帧后——停泊期窗口读行为不在本门证明面）
            csr_wr_slv(16'h3000 + 4*(8*45+6), orig45, "F7W2 停泊期 W_BUF 锁");
            csr_rd(A_ERROR_STATUS, lock_bits);
            if (lock_bits[6:3] == 4'h0 || lock_bits[10] !== 1'b0)
                fail($sformatf("F7W2: 锁写后错位 得%03X 期 bits3-6≠0 且 bit10=0",
                               lock_bits[10:0]));
            else checks = checks + 1;
            // 环孔停泊正典（V1.6.3）：ffe 前末读 0x11C（字 71，写域外）；
            // 兼证停泊期 DONE_COUNT CSR 面
            csr_rd(A_DESC_DONE_COUNT, dv);
            if (dv[15:0] !== 16'd3)
                fail($sformatf("F7W2: 停泊期 DONE_COUNT 得%0d 期3", dv[15:0]));
            else checks = checks + 1;
            csr_ffe;
            wait_ring_pub(2, 200_000, "F7W2 ffe 发环");
            exp_bytes = sum_range(0, 2);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7W2: 环字节 得%0d 期%0d（Σw14 单条目）",
                               ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            if (ring_seq_w != 32'd2)
                fail("F7W2: seq != 2（环续行律，无 do_reset）");
            else checks = checks + 1;
            if (ring_fid_w != 32'd1)
                fail("F7W2: fid != 1（帧 id 跟帧律）");
            else checks = checks + 1;
            check_csr_result(32'd2, 32'd1, exp_bytes[31:0], 8'd2, "F7W2");
            wait_idle(1000, "F7W2");
            // 解锁 + 表内容不变（停泊期 SLVERR 写未落地）
            csr_rd(16'h3000 + 4*(8*45+6), dv);
            if (dv !== orig45)
                fail("F7W2: 停泊期 SLVERR 写改变了表内容（或读回失配）");
            else checks = checks + 1;
            csr_wr(16'h3000 + 4*(8*45+6), orig45);
            if (mcsr.last_bresp_o !== 2'b00)
                fail($sformatf("F7W2: ffe 闭帧后表窗写 bresp=%b 期OKAY",
                               mcsr.last_bresp_o));
            else checks = checks + 1;
            // W1C 清锁错位（帧已终，错面须可清净）
            csr_wr(A_ERROR_STATUS, lock_bits);
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7W2: W1C 后错面 得%03X 期0", dv[10:0]));
            else checks = checks + 1;
            check_no_resume(200, 3, "F7W2");
            ack_consume_at(8'd2);
            if (ring_ne_w) fail("F7W2: ack 后环仍非空");
            else checks = checks + 1;

            // ---- 双帧台账（协议门下的真实流量面：单帧账×2）----
            if (gbfm.rd_n != 2*F7L2_EGRD || gbfm.wr_n != 2*F7L2_EGWR)
                fail($sformatf("F7W: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n,
                               2*F7L2_EGRD, 2*F7L2_EGWR));
            else checks = checks + 2;
            if (bfm.rd_n != 2*F7L2_ERD || bfm.wr_n != 2*F7L2_EWR)
                fail($sformatf("F7W: shell 侧台账 得rd%0d wr%0d 期%0d/%0d",
                               bfm.rd_n, bfm.wr_n, 2*F7L2_ERD, 2*F7L2_EWR));
            else checks = checks + 2;
            if (bfm_proto_err != 0 || gbfm_proto_err != 0
                || bfm_unloaded != 0 || gbfm_unloaded != 0)
                fail($sformatf("F7W: bfm 违例/未装载 %0d/%0d %0d/%0d",
                               bfm_proto_err, bfm_unloaded,
                               gbfm_proto_err, gbfm_unloaded));
            else checks = checks + 4;
            $display("[RUN F7W] 完：W1 last 闭帧 + W2 ffe 闭帧 / 环 seq 1→2 fid 0→1 / 表锁-解锁循环 / g rd %0d wr %0d / shell rd %0d wr %0d",
                     gbfm.rd_n, gbfm.wr_n, bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= F7SB（B3-S3 S3b-W：首段窗 7 帧 ffe 闭帧门）=================
    // 设计书 S3B_DESIGN.md v1 §PASS-2；prep=2026-10-01_yolo_p2_2_s3bw_run01。
    // 7 硬件段各一独立帧（每帧 1 desc@槽0，无 last，ffe 闭帧）：
    //   f0/f1 = model.0 winA/winB（K27 z_sum_w 律；Wo160 双窗分段 Wo_w=80）
    //   f2 = model.1（K144） f3 = 2.cv1（K32） f4/f5 = m.0.cv1/cv2（K144）
    //   f6 = 2.cv2（K48）。PS 桥在 PC 面：verify_s3bw_bridge.py 用
    //   f7sb_y_got_k.hex 硅字节重算 gather→stitch→pack→软算子（SV 零律复制）。
    // 逐帧 clear_logs：winA/winB（及 cv1/cv2 对）同 y 基址，跨帧写日志
    // 必混；累计账由 S3BW_LEDGER 行钉 ΣEGRD/ΣEGWR。
    localparam [31:0] S3B_MBASE = 32'h1000_0000;   // 镜像并集区（板同构单区）
    localparam [31:0] S3B_PBASE = 32'h2000_0000;   // param 区
    localparam int S3B_SPAN [0:6] = '{1036800, 1036800, 5529600,
                                      1228800, 2764800, 2764800, 1843200};
    localparam int S3B_YLEN [0:6] = '{204800, 204800, 204800,
                                      204800, 102400, 102400, 204800};
    localparam int S3B_EGRD [0:6] = '{129656, 129656, 691280,
                                      153680, 345656, 345656, 230480};
    localparam int S3B_EGWR [0:6] = '{25600, 25600, 25600,
                                      25600, 12800, 12800, 25600};
    localparam int S3B_POFF [0:6] = '{0, 0, 192, 576, 960, 1152, 1344};
    localparam [31:0] S3B_W3  [0:6] = '{32'h00A00010, 32'h00A00010,
                                        32'h00500020, 32'h00500020,
                                        32'h00500010, 32'h00500010,
                                        32'h00500020};
    localparam [31:0] S3B_W11 [0:6] = '{32'h0000_101B, 32'h0000_101B,
                                        32'h0000_1090, 32'h0000_1020,
                                        32'h0000_1090, 32'h0000_1090,
                                        32'h0000_1030};
    localparam string S3B_NODE [0:6] = '{"model.0.winA", "model.0.winB",
                                         "model.1", "model.2.cv1",
                                         "model.2.m.0.cv1", "model.2.m.0.cv2",
                                         "model.2.cv2"};
    localparam integer S3B_GRD_TOT = 2026064;      // Σ EGRD（7 帧引擎读拍）
    localparam integer S3B_GWR_TOT = 153600;        // Σ EGWR（7 帧引擎写拍）
    reg [7:0] s3b_gy [0:204799];                    // 本帧金像 y 流（逐帧重读）
    int s3b_widx [bit [31:0]];                      // 写日志 字地址→下标

    // y 写日志重建对拍（f7l2_check_y 血统；金像取 s3b_gy，外排含帧号）
    task automatic s3b_check_y(input integer k, input [31:0] base,
                               input integer nbytes, input string tag,
                               output integer bad);
        integer b, j, fd;
        reg [31:0] wa;
        reg [7:0] gv;
        begin
            bad = 0;
            s3b_widx.delete();
            for (b = 0; b < gbfm.wr_n; b = b + 1)
                s3b_widx[gbfm.wr_addr_lg[b]] = b;
            if (s3b_widx.size() != gbfm.wr_n)
                fail($sformatf("%s: 写日志字地址重复（单帧不得复写）", tag));
            fd = $fopen($sformatf("%s/f7sb_y_got_%0d.hex", prep_dir, k), "w");
            if (fd == 0) fail($sformatf("%s: y_got 外排打开失败", tag));
            for (j = 0; j < nbytes; j = j + 1) begin
                wa = base + j;
                if (!s3b_widx.exists(wa & 32'hFFFF_FFF8)) begin
                    bad = bad + 1;
                    if (bad <= 8)
                        $display("[%0t] FAIL: %s y 缺写拍 j=%0d a=%08x",
                                 $time, tag, j, wa);
                    $fwrite(fd, "00\n");
                end else begin
                    if (gbfm.wr_strb_lg[s3b_widx[wa & 32'hFFFF_FFF8]] != 8'hFF)
                        fail($sformatf("%s: y 写拍 strb 非 FF j=%0d", tag, j));
                    gv = gbfm.wr_data_lg[s3b_widx[wa & 32'hFFFF_FFF8]]
                         [8*(wa[2:0]) +: 8];
                    $fwrite(fd, "%02x\n", gv);
                    if (gv !== s3b_gy[j]) begin
                        bad = bad + 1;
                        if (bad <= 8)
                            $display("[%0t] FAIL: %s y j=%0d got=%02x want=%02x",
                                     $time, tag, j, gv, s3b_gy[j]);
                    end
                end
            end
            $fclose(fd);
        end
    endtask

    task automatic run_f7sb;
        integer k, v, bad;
        longint unsigned exp_bytes, grd_tot, gwr_tot;
        reg [31:0] dv, orig45, lock_bits, ybase, stag32;
        reg [7:0] rtail;
        string stag;
        begin
            $display("[RUN F7SB] S3b-W 首段窗门：7 帧×1 desc ffe 闭帧（model.0 双窗 K27 → model.2.cv2）");
            do_reset(5); cfg_default; g_cfg_default; cfg_csr_default;
            $readmemh({prep_dir, "/desc_s3bw.hex"}, desc_rom);   // 7×32 字
            $readmemh({prep_dir, "/buf_table_s3bw.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_s3bw.hex"}, qt_rom);
            load_buf_win("F7SB");
            load_qt_win("F7SB");
            csr_rd(16'h3000 + 4*(8*45+6), orig45);   // 锁探针字留档（W2 同字）
            grd_tot = 0; gwr_tot = 0;

            for (k = 0; k < 7; k = k + 1) begin
                stag = $sformatf("F7SB f%0d %s", k, S3B_NODE[k]);
                // ---- desc 槽0：设计表钉字（第三源：prep 律 ↔ 设计表 ↔ 硅回读）----
                if (desc_rom[32*k + 0]  !== 32'h0000_0101 ||
                    desc_rom[32*k + 3]  !== S3B_W3[k]       ||
                    desc_rom[32*k + 4]  !== 32'h0000_0050   ||
                    desc_rom[32*k + 8]  !== S3B_MBASE       ||
                    desc_rom[32*k + 10] !== S3B_PBASE + S3B_POFF[k] ||
                    desc_rom[32*k + 11] !== S3B_W11[k]      ||
                    desc_rom[32*k + 14] !== S3B_YLEN[k])
                    fail($sformatf("%s: desc 钉字失配 w0=%08X w3=%08X w4=%08X w8=%08X w10=%08X w11=%08X w14=%08X",
                        stag, desc_rom[32*k+0], desc_rom[32*k+3], desc_rom[32*k+4],
                        desc_rom[32*k+8], desc_rom[32*k+10], desc_rom[32*k+11],
                        desc_rom[32*k+14]));
                else checks = checks + 1;
                for (v = 0; v < 32; v = v + 1)
                    csr_wr(16'h1000 + 4*v, desc_rom[32*k + v]);
                for (v = 0; v < 32; v = v + 1) begin
                    csr_rd(16'h1000 + 4*v, dv);
                    if (dv !== desc_rom[32*k + v])
                        fail($sformatf("%s: desc 回读 w%0d 得%08X 期%08X",
                                       stag, v, dv, desc_rom[32*k + v]));
                end
                if (errors == 0) checks = checks + 1;
                // ---- 金像读入 + 镜像并集区逐段重打包预载（板同构）----
                $readmemh($sformatf("%s/golden_y_%0d.hex", prep_dir, k), s3b_gy);
                gbfm.load_preload($sformatf("%s/mirror_%0d.txt", prep_dir, k));
                gbfm.clear_logs;
                bfm.clear_logs;
                // ---- 帧启动：DONE_COUNT 帧清零律直接证据（S3a-R 两律之一）----
                csr_wr(A_FRAME_ID, k);
                csr_tail(16'd1);
                csr_start_frame;
                repeat (2) @(posedge clk_r);
                csr_rd(A_DESC_DONE_COUNT, dv);
                if (dv[15:0] !== 16'd0)
                    fail($sformatf("%s: 帧始 DONE_COUNT 得%0d 期0（帧清零律）",
                                   stag, dv[15:0]));
                else checks = checks + 1;
                // ---- 走单 desc（大段心跳 200K 拍/次）----
                wait_walk_done(1, 20_000_000, stag);
                if (eng_evt_cnt != 0)
                    fail($sformatf("%s: 引擎错误事件 得%0d 期0", stag,
                                   eng_evt_cnt));
                else checks = checks + 1;
                // 派发面：GEMM 单发槽0、零 PPU
                if (gemm_log_q.size() != 1 || gemm_log_q[0] != 0
                    || ppu_log_q.size() != 0)
                    fail($sformatf("%s: 派发 GEMM=%0d PPU=%0d 期{0}/{}",
                                   stag, gemm_log_q.size(), ppu_log_q.size()));
                else checks = checks + 1;
                // ---- 停泊 W_CHK（无 last 队列空）----
                if (wk_idle_w) fail($sformatf("%s: 提前 idle（应 W_CHK 停泊）", stag));
                else checks = checks + 1;
                csr_rd(A_STATUS, dv);
                if (dv[0] !== 1'b0 || dv[1] !== 1'b1 || dv[4] !== 1'b1)
                    fail($sformatf("%s: 停泊 STATUS IDLE=%b RUNNING=%b EMPTY=%b 期0/1/1",
                                   stag, dv[0], dv[1], dv[4]));
                else checks = checks + 1;
                if (ring_pub_cnt != k)
                    fail($sformatf("%s: ffe 前发环 得%0d 期%0d（停泊不得发环）",
                                   stag, ring_pub_cnt, k));
                else checks = checks + 1;
                // ---- 停泊期表锁（W2 正典：SLVERR + 错位 bits3-6、bit10=0）----
                csr_wr_slv(16'h3000 + 4*(8*45+6), orig45,
                           $sformatf("%s 停泊期 W_BUF 锁", stag));
                csr_rd(A_ERROR_STATUS, lock_bits);
                if (lock_bits[6:3] == 4'h0 || lock_bits[10] !== 1'b0)
                    fail($sformatf("%s: 锁写后错位 得%03X 期 bits3-6≠0 且 bit10=0",
                                   stag, lock_bits[10:0]));
                else checks = checks + 1;
                // 环孔停泊正典（V1.6.3）：ffe 前末读 0x11C（写域外）+ 停泊期
                // DONE_COUNT CSR 面
                csr_rd(A_DESC_DONE_COUNT, dv);
                if (dv[15:0] !== 16'd1)
                    fail($sformatf("%s: 停泊期 DONE_COUNT 得%0d 期1",
                                   stag, dv[15:0]));
                else checks = checks + 1;
                // ---- ffe 闭帧 → 环发布 ----
                csr_ffe;
                wait_ring_pub(k + 1, 200_000, $sformatf("%s ffe 发环", stag));
                exp_bytes = desc_rom[32*k + 14];
                if (ring_bytes_w != exp_bytes)
                    fail($sformatf("%s: 环字节 得%0d 期%0d（w14 单条目）",
                                   stag, ring_bytes_w, exp_bytes));
                else checks = checks + 1;
                if (ring_seq_w != k + 1)
                    fail($sformatf("%s: seq 得%0d 期%0d（环续行律）",
                                   stag, ring_seq_w, k + 1));
                else checks = checks + 1;
                if (ring_fid_w != k)
                    fail($sformatf("%s: fid 得%0d 期%0d（帧 id 跟帧律）",
                                   stag, ring_fid_w, k));
                else checks = checks + 1;
                check_csr_result(k + 1, k, exp_bytes[31:0], k + 1, stag);
                csr_rd(A_DESC_CURRENT, dv);
                if (dv[15:0] !== 16'd0)
                    fail($sformatf("%s: DESC_CURRENT 得%0d 期0（单 desc 槽0）",
                                   stag, dv[15:0]));
                else checks = checks + 1;
                check_desc_csr(16'd1, 16'd1, stag);
                // ---- 解锁正面 + W1C 清错面（帧已终，留干净态给下帧）----
                wait_idle(1000, stag);
                csr_rd(16'h3000 + 4*(8*45+6), dv);
                if (dv !== orig45)
                    fail($sformatf("%s: 停泊期 SLVERR 写改变了表内容", stag));
                else checks = checks + 1;
                csr_wr(16'h3000 + 4*(8*45+6), orig45);
                if (mcsr.last_bresp_o !== 2'b00)
                    fail($sformatf("%s: 闭帧后表窗写 bresp=%b 期OKAY",
                                   stag, mcsr.last_bresp_o));
                else checks = checks + 1;
                csr_wr(A_ERROR_STATUS, lock_bits);
                csr_rd(A_ERROR_STATUS, dv);
                if (dv[10:0] !== 11'd0)
                    fail($sformatf("%s: W1C 后错面 得%03X 期0", stag, dv[10:0]));
                else checks = checks + 1;
                // ---- y 对拍（写日志重建 + 外排硅字节）----
                ybase = S3B_MBASE + 32'h100 + S3B_SPAN[k];
                s3b_check_y(k, ybase, S3B_YLEN[k], stag, bad);
                if (bad != 0)
                    fail($sformatf("%s: y 对拍 bad=%0d", stag, bad));
                else checks = checks + 1;
                // ---- 逐帧台账（本帧 clear 窗口内的精确账 = 越界扫描）----
                if (gbfm.rd_n != S3B_EGRD[k] || gbfm.wr_n != S3B_EGWR[k])
                    fail($sformatf("%s: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                                   stag, gbfm.rd_n, gbfm.wr_n,
                                   S3B_EGRD[k], S3B_EGWR[k]));
                else checks = checks + 2;
                if (bfm.rd_n != 0 || bfm.wr_n != 0)
                    fail($sformatf("%s: shell 侧台账 得rd%0d wr%0d 期0/0（无 PPU 任务）",
                                   stag, bfm.rd_n, bfm.wr_n));
                else checks = checks + 2;
                if (bfm_proto_err != 0 || gbfm_proto_err != 0
                    || bfm_unloaded != 0 || gbfm_unloaded != 0)
                    fail($sformatf("%s: bfm 违例/未装载 %0d/%0d %0d/%0d",
                                   stag, bfm_proto_err, bfm_unloaded,
                                   gbfm_proto_err, gbfm_unloaded));
                else checks = checks + 4;
                grd_tot = grd_tot + gbfm.rd_n;
                gwr_tot = gwr_tot + gbfm.wr_n;
                // ---- 停走 + ack 清环 ----
                check_no_resume(200, 1, stag);
                rtail = k + 1;
                ack_consume_at(rtail);
                if (ring_ne_w) fail($sformatf("%s: ack 后环仍非空", stag));
                else checks = checks + 1;
                stag32 = ybase;
                $display("[S3BW] f%0d %s span=%0d ylen=%0d ybase=%08x rd=%0d wr=%0d grd=%0d gwr=%0d ybad=%0d seq=%0d",
                         k, S3B_NODE[k], S3B_SPAN[k], S3B_YLEN[k], stag32,
                         bfm.rd_n, bfm.wr_n, gbfm.rd_n, gbfm.wr_n, bad,
                         ring_seq_w);
            end

            // ---- 累计账 + 终态错面 ----
            if (grd_tot != S3B_GRD_TOT || gwr_tot != S3B_GWR_TOT)
                fail($sformatf("F7SB: 累计台账 得grd%0d gwr%0d 期%0d/%0d",
                               grd_tot, gwr_tot, S3B_GRD_TOT, S3B_GWR_TOT));
            else checks = checks + 2;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7SB: 终态 ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            $display("S3BW_LEDGER frames=7 grd_tot=%0d gwr_tot=%0d rd_tot=0 wr_tot=0",
                     grd_tot, gwr_tot);
            $display("[RUN F7SB] 完：7 帧 ffe 闭帧 / 环 seq 1→7 fid 0→6 / 表锁-解锁×7 / y 逐帧金像 / grd %0d gwr %0d",
                     grd_tot, gwr_tot);
        end
    endtask

    // 程序布局：槽0=conv（F7G 正典字、无 last），槽1..25=PROG 紧凑
    // （producer 重映射 orig→槽+1），槽25 原生 last 帧末自动发环。
    task automatic run_f7m;
        integer v, s, w, bad;
        longint unsigned rm, wm, exp_bytes;
        reg [31:0] dv;
        begin
            $display("[RUN F7M] 子图梯一级：conv@槽0（引擎）+ 25 PPU 任务混合程序");
            do_reset(5); cfg_default; g_cfg_default; cfg_csr_default;
            gbfm.load_preload({prep_dir, "/f7g_m1_preload.txt"});
            $readmemh({prep_dir, "/f7g_golden_gather.hex"}, f7g_golden);

            // ---- 三表读入 + 紧凑到槽 1..25（前向安全：PROG[s]>=7>s+1）----
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            for (s = 0; s < N_PROG; s = s + 1)
                for (w = 0; w < 32; w = w + 1)
                    desc_rom[32*(s+1) + w] = desc_rom[32*PROG[s] + w];
            // conv desc @槽0（F7G 正典 ABI v2 字；w0 无 last）
            for (w = 0; w < 32; w = w + 1) desc_rom[w] = 32'h0;
            desc_rom[32*0 + 0]  = 32'h0000_0101;   // valid+GEMM conv（无 last）
            desc_rom[32*0 + 3]  = 32'h0014_0040;   // {Ho=20, oc=64}
            desc_rom[32*0 + 4]  = 32'h0000_0014;   // Wo=20
            desc_rom[32*0 + 8]  = 32'h1000_0000;   // mirror 基址
            desc_rom[32*0 + 10] = 32'h2000_0000;   // param 基址
            desc_rom[32*0 + 11] = 32'h0000_1240;   // has_act=1, K=576
            desc_rom[32*0 + 14] = 32'h0000_6400;   // 环账 25600
            // producer 重映射：orig→槽+1 域（PPU 任务现居槽 1..25；
            // 外部生产者 conv/view/canvas → 0xFF 步 5 豁免，同 F7 律）
            for (v = 0; v < 128; v = v + 1) begin
                dv = buf_rom[8*v + 6];
                if (dv[7:0] != 8'hFF) begin
                    s = slot_of(dv[7:0]);
                    if (s >= 0) buf_rom[8*v + 6][7:0] = s + 1;
                    else        buf_rom[8*v + 6][7:0] = 8'hFF;
                end
            end

            // ---- 26 槽 desc 窗口装载 + 全量回读 + buf/qt + bfm 帧预载 ----
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*26; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            for (v = 0; v < 32*26; v = v + 1) begin
                csr_rd(16'h1000 + 4*v, dv);
                if (dv !== desc_rom[v])
                    fail($sformatf("F7M: desc 回读 w%0d 得%08X 期%08X",
                                   v, dv, desc_rom[v]));
            end
            if (errors == 0) checks = checks + 1;
            load_buf_win("F7M");
            load_qt_win("F7M");
            bfm.load_preload({prep_dir, "/preload_f0.txt"});

            // ---- 混合帧：conv 先行（引擎），顺序屏障后 25 PPU 任务 ----
            csr_tail(16'd26);
            csr_start_frame;
            wait_walk_done(1, 3_000_000, "F7M conv 槽0");
            if (eng_evt_cnt != 0)
                fail($sformatf("F7M: 干净卷引擎事件 得%0d 期0", eng_evt_cnt));
            else checks = checks + 1;
            // 顺序屏障钉：槽0 完成拍时 PPU 派发必为 0（屏障未放行）
            if (ppu_log_q.size() != 0)
                fail($sformatf("F7M: 引擎卷完成前 PPU 派发 得%0d 期0（顺序屏障破坏）",
                               ppu_log_q.size()));
            else checks = checks + 1;
            // 25 PPU 任务逐字节（conv 零 bfm 流量 → 滑动窗 mark 从 0 起）
            rm = 0; wm = 0;
            for (s = 0; s < N_PROG; s = s + 1) begin
                wait_walk_done(s + 2, 3_000_000, $sformatf("F7M s%0d", s));
                cmp_golden("rd", PROG[s], rm, "F7M", 0);
                cmp_golden("wr", PROG[s], wm, "F7M", 0);
                rm = bfm.rd_n; wm = bfm.wr_n;
            end

            // ---- 发环（槽25 原生 last）+ 混合 w14 环账 ----
            wait_ring_pub(1, 200_000, "F7M 发环");
            exp_bytes = sum_range(0, 25);           // conv 0x6400 + Σ PPU w14
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7M: 环字节 得%0d 期%0d（conv 25600+ΣPPU w14）",
                               ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            if (ring_seq_w != 32'd1) fail("F7M: seq != 1");
            else checks = checks + 1;
            if (ring_fid_w != 32'd0) fail("F7M: fid != 0");
            else checks = checks + 1;
            check_csr_result(32'd1, 32'd0, exp_bytes, 8'd1, "F7M");
            check_desc_csr(16'd26, 16'd26, "F7M");

            // ---- 派发面 + 双引擎台账隔离 ----
            if (gemm_log_q.size() != 1 || gemm_log_q[0] != 0)
                fail($sformatf("F7M: GEMM 派发 得%0d 条 期1/idx0", gemm_log_q.size()));
            else checks = checks + 1;
            if (ppu_log_q.size() != N_PROG)
                fail($sformatf("F7M: PPU 派发 得%0d 期25", ppu_log_q.size()));
            else checks = checks + 1;
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7M: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            else checks = checks + 2;
            // bfm 侧不 pin 绝对拍（v1.6 时序敏感教训）——逐任务金样已证；
            // 协议/装载面两 BFM 各自查：
            if (bfm_proto_err != 0)
                fail($sformatf("F7M: bfm 协议违例 %0d", bfm_proto_err));
            else checks = checks + 1;
            if (bfm_unloaded != 0)
                fail($sformatf("F7M: bfm 未装载拍 %0d", bfm_unloaded));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7M: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            if (gbfm_unloaded != 0)
                fail($sformatf("F7M: gbfm 未装载拍 %0d", gbfm_unloaded));
            else checks = checks + 1;

            // ---- 引擎 y 金像（单卷无复写 → f7g_check_y 直用）----
            f7g_check_y(3, bad);
            if (bad != 0) fail($sformatf("F7M: y 对拍 bad=%0d", bad));
            else checks = checks + 320;

            // ---- 错误面干净 + idle/停走 + ack 清环 ----
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7M: ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            wait_idle(1000, "F7M");
            check_no_resume(200, 26, "F7M");
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7M: ack 后环仍非空");
            else checks = checks + 1;
            $display("[RUN F7M] 完：混合 26 任务（conv+25 PPU）屏障放行 / 环 %0d B / g rd %0d wr %0d / shell rd %0d wr %0d",
                     exp_bytes, gbfm.rd_n, gbfm.wr_n, bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ---- F7M2（P2.3 修复验证）：25 PPU 先行 + conv@槽25（非零+last）----
    // M1 的镜像布局：PPU PROG 紧凑到槽 0..24（前向安全 PROG[s]>=7>s），
    // conv 居槽 25（valid+last）——GEMM 引擎首次在非零槽经 walker 派发，
    // desc 口 B 让渡序 = 25 次 PPU 让渡后首度 GEMM 让渡（共享口交接收
    // 口面）。producer 重映射 orig→槽 s（无 +1 偏移）；金样/环账/台账
    // 隔离判据同 M1；新增钉：GEMM 派发 idx=25、派发拍 done=25（顺序
    // 屏障）、本帧 PPU 派发 idx 面 0..24。
    task automatic run_f7m2;
        integer v, s, w, bad;
        longint unsigned rm, wm, exp_bytes;
        reg [31:0] dv;
        begin
            $display("[RUN F7M2] 25 PPU 先行 + conv@槽25（非零槽 GEMM 派发+口 B 让渡）");
            csr_soft;
            wait_idle(1000, "F7M2 soft_reset 释放");
            cfg_csr_default; bfm.clear_logs; gbfm.clear_logs;
            // V1.8：M2 窗 AXI W 背压面（授权门 4 系统级）——每 4 拍接受
            // 后 wready 拉 3 拍，内容不变仅时序；稳定性监控逐拍把关
            // （F7M 专属监控块）。
            cfg_w_stall = 3;
            // 三表重读（M1 已破坏性紧凑/重映射）+ 镜像紧凑：PPU→槽 0..24
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            for (s = 0; s < N_PROG; s = s + 1)
                for (w = 0; w < 32; w = w + 1)
                    desc_rom[32*s + w] = desc_rom[32*PROG[s] + w];
            // 紧凑后槽 24 承原帧末任务（orig-103）的 last 位（w0[9]）——
            // M2 帧末归 conv@25（w0=0x301），须摘除（F7A 1019 同律先例）：
            // 否则 25 PPU 后 walker W_ENG 出口见 w0_last → W_PUB → 槽 25
            // conv 永不派发（f7p23c 实测：done=25 停 W_IDLE、零错、口 B
            // 末事务 dbid=24）。M1（last 在槽 25 原生位）不受影响。
            desc_rom[32*24 + 0] = desc_rom[32*24 + 0] & ~32'h0000_0200;
            // conv desc @槽25（F7G 正典 ABI v2 字；w0 valid+last 帧末发环）
            for (w = 0; w < 32; w = w + 1) desc_rom[32*25 + w] = 32'h0;
            desc_rom[32*25 + 0]  = 32'h0000_0301;   // valid+last+GEMM conv
            desc_rom[32*25 + 3]  = 32'h0014_0040;   // {Ho=20, oc=64}
            desc_rom[32*25 + 4]  = 32'h0000_0014;   // Wo=20
            desc_rom[32*25 + 8]  = 32'h1000_0000;   // arena A mirror 基址
            desc_rom[32*25 + 10] = 32'h2000_0000;   // param 基址
            desc_rom[32*25 + 11] = 32'h0000_1240;   // has_act=1, K=576
            desc_rom[32*25 + 14] = 32'h0000_6400;   // 环账 25600
            // producer 重映射：orig→槽 s（PPU 任务现居槽 0..24，无偏移；
            // 外部生产者 conv/view/canvas → 0xFF 步 5 豁免，同 F7 律）
            for (v = 0; v < 128; v = v + 1) begin
                dv = buf_rom[8*v + 6];
                if (dv[7:0] != 8'hFF) begin
                    s = slot_of(dv[7:0]);
                    if (s >= 0) buf_rom[8*v + 6][7:0] = s;
                    else        buf_rom[8*v + 6][7:0] = 8'hFF;
                end
            end
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*26; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            for (v = 0; v < 32*26; v = v + 1) begin
                csr_rd(16'h1000 + 4*v, dv);
                if (dv !== desc_rom[v])
                    fail($sformatf("F7M2: desc 回读 w%0d 得%08X 期%08X",
                                   v, dv, desc_rom[v]));
            end
            if (errors == 0) checks = checks + 1;
            load_buf_win("F7M2");
            load_qt_win("F7M2");

            // ---- 混合帧（镜像序）：25 PPU 先行，屏障后 conv@25 收口 ----
            csr_tail(16'd26);
            csr_start_frame;
            rm = 0; wm = 0;
            for (s = 0; s < N_PROG; s = s + 1) begin
                wait_walk_done(s + 1, 3_000_000, $sformatf("F7M2 s%0d", s));
                cmp_golden("rd", PROG[s], rm, "F7M2", 0);
                cmp_golden("wr", PROG[s], wm, "F7M2", 0);
                rm = bfm.rd_n; wm = bfm.wr_n;
            end
            // 屏障钉：conv@槽25 GEMM 派发拍 PPU 已全成（done=25）
            // （逐帧日志律 V1.6.2：本帧 conv 即 gemm_log_q[0]）
            v = 0;
            while (gemm_log_q.size() < 1 && v < 200000) begin
                v = v + 1; @(posedge clk_r);
            end
            if (gemm_log_q.size() < 1)
                fail("F7M2: conv@槽25 GEMM 派发未见（200k 拍）");
            else if (gemm_log_q[0] != 25)
                fail($sformatf("F7M2: GEMM 派发 idx 得%0d 期25（非零槽）",
                               gemm_log_q[0]));
            else checks = checks + 2;
            if (wk_done_w != 25)
                fail($sformatf("F7M2: GEMM 派发时 done 得%0d 期25（顺序屏障）",
                               wk_done_w));
            else checks = checks + 1;
            wait_walk_done(26, 3_000_000, "F7M2 conv 槽25");
            wait_ring_pub(2, 200_000, "F7M2 发环");
            exp_bytes = sum_range(0, 25);           // conv 0x6400 + Σ PPU w14
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7M2: 环字节 得%0d 期%0d", ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            // V1.6.1：环 seq 穿 csr_soft 单调续（F7S-3 实测定律）——M2 为第
            // 2 次发环：seq=2、条目@1、head=2、ack@2。
            if (ring_seq_w != 32'd2) fail("F7M2: seq != 2（环 seq 穿软复位续）");
            else checks = checks + 1;
            if (ring_fid_w != 32'd0) fail("F7M2: fid != 0");
            else checks = checks + 1;
            check_csr_result(32'd2, 32'd0, exp_bytes, 8'd2, "F7M2");
            check_desc_csr(16'd26, 16'd26, "F7M2");
            // 派发面：本帧 PPU 25 条 idx 0..24（逐帧日志律 V1.6.2——
            // csr_start_frame 清日志，M1 的 25 条不累计；B5 门同律先例）
            if (ppu_log_q.size() != N_PROG)
                fail($sformatf("F7M2: PPU 派发 得%0d 期%0d",
                               ppu_log_q.size(), N_PROG));
            else checks = checks + 1;
            bad = 0;
            for (s = 0; s < N_PROG; s = s + 1)
                if (ppu_log_q[s] != s) bad = bad + 1;
            if (bad != 0)
                fail($sformatf("F7M2: 本帧 PPU 派发 idx 面 bad=%0d（期 0..24）", bad));
            else checks = checks + 1;
            // 双引擎台账隔离（clear_logs 后 = 本帧：conv 单卷 + 25 任务）
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7M2: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            else checks = checks + 2;
            if (eng_evt_cnt != 0)
                fail($sformatf("F7M2: 引擎事件 得%0d 期0（M1+M2 全程零）",
                               eng_evt_cnt));
            else checks = checks + 1;
            if (bfm_proto_err != 0)
                fail($sformatf("F7M2: bfm 协议违例 %0d", bfm_proto_err));
            else checks = checks + 1;
            if (bfm_unloaded != 0)
                fail($sformatf("F7M2: bfm 未装载拍 %0d", bfm_unloaded));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7M2: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            if (gbfm_unloaded != 0)
                fail($sformatf("F7M2: gbfm 未装载拍 %0d", gbfm_unloaded));
            else checks = checks + 1;
            // 引擎 y 金像（本帧单卷无复写 → f7g_check_y 直用）
            f7g_check_y(4, bad);
            if (bad != 0) fail($sformatf("F7M2: y 对拍 bad=%0d", bad));
            else checks = checks + 320;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7M2: ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            wait_idle(1000, "F7M2");
            check_no_resume(200, 26, "F7M2");
            ack_consume_at(8'd2);
            if (ring_ne_w) fail("F7M2: ack 后环仍非空");
            else checks = checks + 1;
            $display("[RUN F7M2] 完：conv@槽25 非零 GEMM 派发+口 B 让渡 / 环 %0d B / g rd %0d wr %0d / shell rd %0d wr %0d",
                     exp_bytes, gbfm.rd_n, gbfm.wr_n, bfm.rd_n, bfm.wr_n);
            cfg_w_stall = 0;                   // V1.8：背压窗关（M3 错误腿不掺时序变量）
        end
    endtask

    // ---- F7M3（P2.3 修复验证）：非零槽 PPU 引擎错（C 的 PPU 面）+ 恢复 ----
    // 布局同 M2（PPU 0..24 + conv@25）。槽 2 的 PPU 任务读流注入
    // RRESP=SLVERR（cfg_fault_r_beat 于 done=2 拍以 bfm.r_beat_tot+16
    // 活值装定——walker 顺序性保证此后读拍全属槽 2 任务；DMA 错语义
    // = 停发新事务+在途受控排干 ppu_dma_master §5.6）→ dma_halted →
    // walker eng_err：期 ERROR_INFO port=5/desc_id=2/op=槽2 w0[7:0]/
    // code=02（walker V3.1 上下文锁存的 PPU 面钉——与 F7S-2 的 GEMM
    // 面互补）+ bit10 粘着 + done 停 2 + 无发环 + conv（槽25）永不派发。
    // 恢复：撤注入 → 硬复位（SLVERR 后 shell/DMA 错粘着至 rst_i——V1.6.2
    // 律）→ 同程序整帧重跑全对拍（含 conv@25 非零槽 GEMM 复证）。
    task automatic run_f7m3;
        integer v, s, w, bad;
        longint unsigned rm, wm, exp_bytes;
        reg [31:0] dv, exp_op;
        begin
            $display("[RUN F7M3] 槽2 PPU 读流 SLVERR → 引擎错上下文（PPU 面）+ 恢复重跑");
            csr_soft;
            wait_idle(1000, "F7M3 soft_reset 释放");
            cfg_csr_default; bfm.clear_logs; gbfm.clear_logs;
            // 三表重读 + 布局同 M2
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            for (s = 0; s < N_PROG; s = s + 1)
                for (w = 0; w < 32; w = w + 1)
                    desc_rom[32*s + w] = desc_rom[32*PROG[s] + w];
            // 同 M2：摘槽 24 紧凑带入的原帧末 last 位（帧末归 conv@25；
            // M3R 恢复整帧重跑依赖 conv@25 派发+done=26）
            desc_rom[32*24 + 0] = desc_rom[32*24 + 0] & ~32'h0000_0200;
            for (w = 0; w < 32; w = w + 1) desc_rom[32*25 + w] = 32'h0;
            desc_rom[32*25 + 0]  = 32'h0000_0301;
            desc_rom[32*25 + 3]  = 32'h0014_0040;
            desc_rom[32*25 + 4]  = 32'h0000_0014;
            desc_rom[32*25 + 8]  = 32'h1000_0000;
            desc_rom[32*25 + 10] = 32'h2000_0000;
            desc_rom[32*25 + 11] = 32'h0000_1240;
            desc_rom[32*25 + 14] = 32'h0000_6400;
            for (v = 0; v < 128; v = v + 1) begin
                dv = buf_rom[8*v + 6];
                if (dv[7:0] != 8'hFF) begin
                    s = slot_of(dv[7:0]);
                    if (s >= 0) buf_rom[8*v + 6][7:0] = s;
                    else        buf_rom[8*v + 6][7:0] = 8'hFF;
                end
            end
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*26; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            load_buf_win("F7M3");
            load_qt_win("F7M3");
            exp_op = desc_rom[32*2 + 0];           // 槽2 w0（op=exp_op[7:0]）

            // ---- 错误帧：槽0/1 干净 → 槽2 读流注错 → 引擎错上下文 ----
            csr_tail(16'd26);
            csr_start_frame;
            wait_walk_done(2, 3_000_000, "F7M3 槽0/1");
            cfg_fault_r_beat = bfm.r_beat_tot + 16;   // 落槽2 读流内（容积≫16 拍）
            $display("[RUN F7M3] 注错 arm：fault_beat=%0d（r_beat_tot=%0d+16）",
                     cfg_fault_r_beat, bfm.r_beat_tot);
            wait_evt_cnt(1, "F7M3 槽2 PPU 引擎错");
            repeat (300) @(posedge clk_r);         // W_ERR 粘着窗 + 排干窗
            if (wk_idle_w) fail("F7M3: W_ERR 不得自行回 idle");
            else checks = checks + 1;
            if (wk_run_w !== 1'b1) fail("F7M3: W_ERR 期 running 须 1");
            else checks = checks + 1;
            if (wk_done_w != 2)
                fail($sformatf("F7M3: done 得%0d 期2（槽2 不计完成）", wk_done_w));
            else checks = checks + 1;
            if (ring_pub_cnt != 2) fail("F7M3: 引擎错不得发环");
            else checks = checks + 1;
            check_desc_csr(16'd2, 16'd2, "F7M3E"); // head 停 2（错槽不前进）
            if (bfm.rvalid_o !== 1'b0)
                fail("F7M3: 注错后 BFM R 通道未排干（受控排干语义破坏）");
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b1)
                fail($sformatf("F7M3: bit10 得%b 期1（全字 %03X）",
                               dv[10], dv[10:0]));
            else checks = checks + 1;
            csr_rd(A_ERROR_INFO, dv);
            $display("[RUN F7M3] ERROR_INFO = %08X（期 port5/desc2/op%02x/code02）",
                     dv, exp_op[7:0]);
            // C 修复判据（PPU 面）：desc_id=2/op=槽2 opcode/code=02
            if (dv[31:24] !== 8'h05 || dv[23:16] !== 8'd2
                || dv[15:8] !== exp_op[7:0] || dv[7:0] !== 8'h02)
                fail($sformatf("F7M3: err_info 得 port%0d desc%0d op%02x code%02x 期5/2/%02x/02",
                               dv[31:24], dv[23:16], dv[15:8], exp_op[7:0]));
            else checks = checks + 4;
            // 派发面：本帧 PPU {0,1,2} 三条、GEMM 零新派发（逐帧日志律
            // V1.6.2——不累计 M1/M2 各 25 条）
            if (ppu_log_q.size() != 3)
                fail($sformatf("F7M3: PPU 派发 得%0d 期3",
                               ppu_log_q.size()));
            else checks = checks + 1;
            bad = 0;
            for (s = 0; s < 3; s = s + 1)
                if (ppu_log_q[s] != s) bad = bad + 1;
            if (bad != 0)
                fail($sformatf("F7M3: 错误帧 PPU 派发 idx 面 bad=%0d（期 {0,1,2}）", bad));
            else checks = checks + 1;
            if (gemm_log_q.size() != 0)
                fail($sformatf("F7M3: GEMM 派发 得%0d 期0（conv@25 永不达）",
                               gemm_log_q.size()));
            else checks = checks + 1;
            check_frozen(200, 2, "F7M3");

            // ---- 恢复：撤注入 → 硬复位 → 重布表整帧重跑 ----
            // V1.6.2 传输级错恢复律（f7p23d 实测）：SLVERR 后 shell/DMA
            // 错粘着（ppu_dma_master err_r/halted 仅 rst_i 清；soft_reset
            // 只达 regf/walker/ring，u_shell.rst_i=rst_hi_w）——软复位后
            // 重启帧=派发进错误保持的 shell → 新引擎错 → W_ERR 死锁。
            // 按设计契约走硬复位新纪元；F7S-3（引擎前错、shell 未涉）
            // 软复位恢复仍为正典。
            cfg_fault_r_beat = 0;                  // 撤销读流注入
            do_reset(5);
            cfg_default; g_cfg_default; cfg_csr_default;
            // 三表重读 + M2 布局重布（BRAM 内容穿 do_reset，重写取确定性）
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            for (s = 0; s < N_PROG; s = s + 1)
                for (w = 0; w < 32; w = w + 1)
                    desc_rom[32*s + w] = desc_rom[32*PROG[s] + w];
            desc_rom[32*24 + 0] = desc_rom[32*24 + 0] & ~32'h0000_0200;
            for (w = 0; w < 32; w = w + 1) desc_rom[32*25 + w] = 32'h0;
            desc_rom[32*25 + 0]  = 32'h0000_0301;
            desc_rom[32*25 + 3]  = 32'h0014_0040;
            desc_rom[32*25 + 4]  = 32'h0000_0014;
            desc_rom[32*25 + 8]  = 32'h1000_0000;
            desc_rom[32*25 + 10] = 32'h2000_0000;
            desc_rom[32*25 + 11] = 32'h0000_1240;
            desc_rom[32*25 + 14] = 32'h0000_6400;
            for (v = 0; v < 128; v = v + 1) begin
                dv = buf_rom[8*v + 6];
                if (dv[7:0] != 8'hFF) begin
                    s = slot_of(dv[7:0]);
                    if (s >= 0) buf_rom[8*v + 6][7:0] = s;
                    else        buf_rom[8*v + 6][7:0] = 8'hFF;
                end
            end
            csr_wr(A_DESC_BASE, 32'h0);
            for (v = 0; v < 32*26; v = v + 1)
                csr_wr(16'h1000 + 4*v, desc_rom[v]);
            load_buf_win("F7M3R");
            load_qt_win("F7M3R");
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b0) fail("F7M3R: 硬复位后 bit10 须 0");
            else checks = checks + 1;
            // 环孔径停泊律（V1.6.3，TB 不制造冲突访问铁律）：环孔口 A 常读
            // rd_addr_w[10:2]（ppu_f7_top:473，BRAM ena 恒 1）——上面读
            // ERROR_STATUS=0x018 会把孔径停泊在字 6，恰入 entry@0 写域，
            // M3R 新纪元发布 w6 同址读写冲突（f7p23e 实测 t=169.270695，
            // 全 run 唯一环冲突）。发布前补读 DESC_DONE_COUNT(0x11C→字
            // 71，本次写域外)把孔径停泊到安全字。
            csr_rd(A_DESC_DONE_COUNT, dv);
            bfm.clear_logs; gbfm.clear_logs;
            csr_wr(A_FRAME_ID, 32'd2);
            csr_tail(16'd26);
            csr_start_frame;
            rm = 0; wm = 0;
            for (s = 0; s < N_PROG; s = s + 1) begin
                wait_walk_done(s + 1, 3_000_000, $sformatf("F7M3R s%0d", s));
                cmp_golden("rd", PROG[s], rm, "F7M3R", 0);
                cmp_golden("wr", PROG[s], wm, "F7M3R", 0);
                rm = bfm.rd_n; wm = bfm.wr_n;
            end
            v = 0;
            while (gemm_log_q.size() < 1 && v < 200000) begin
                v = v + 1; @(posedge clk_r);
            end
            if (gemm_log_q.size() < 1 || gemm_log_q[0] != 25)
                fail("F7M3R: conv@槽25 GEMM 复派发未见/idx≠25");
            else checks = checks + 1;
            wait_walk_done(26, 3_000_000, "F7M3R conv 槽25");
            wait_ring_pub(1, 200_000, "F7M3R 发环");
            exp_bytes = sum_range(0, 25);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7M3R: 环字节 得%0d 期%0d", ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            // V1.6.2：硬复位恢复=环新纪元（do_reset 全清）：seq=1、条目@0、
            // head=1、ack@1（V1.6.1 软复位续行律 seq=3 在此不适用）。
            // V1.6.4 纪元计数律（f7p23f 探针闭合）：cfg_default（TB:562）
            // 随 M3R 新纪元把纪元计数器一并清零——RING_PUB_DONE 实测第三
            // 发环 cnt 自 0→1（非 2→3）、恢复帧 eng_evt_cnt=0（非 1）→
            // wait_ring_pub 期 1、eng_evt_cnt 期 0（新纪元语义，非累计）。
            if (ring_seq_w != 32'd1) fail("F7M3R: seq != 1（硬复位环新纪元）");
            else checks = checks + 1;
            if (ring_fid_w != 32'd2) fail("F7M3R: fid != 2");
            else checks = checks + 1;
            check_csr_result(32'd1, 32'd2, exp_bytes, 8'd1, "F7M3R");
            check_desc_csr(16'd26, 16'd26, "F7M3R");
            if (eng_evt_cnt != 0)
                fail($sformatf("F7M3: 引擎事件 得%0d 期0（新纪元零引擎事件）",
                               eng_evt_cnt));
            else checks = checks + 1;
            if (ppu_log_q.size() != N_PROG)
                fail($sformatf("F7M3R: PPU 派发 得%0d 期%0d（逐帧）",
                               ppu_log_q.size(), N_PROG));
            else checks = checks + 1;
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7M3R: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            else checks = checks + 2;
            if (bfm_proto_err != 0)
                fail($sformatf("F7M3R: bfm 协议违例 %0d", bfm_proto_err));
            else checks = checks + 1;
            if (bfm_unloaded != 0)
                fail($sformatf("F7M3R: bfm 未装载拍 %0d", bfm_unloaded));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7M3R: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            if (gbfm_unloaded != 0)
                fail($sformatf("F7M3R: gbfm 未装载拍 %0d", gbfm_unloaded));
            else checks = checks + 1;
            f7g_check_y(5, bad);
            if (bad != 0) fail($sformatf("F7M3R: y 对拍 bad=%0d", bad));
            else checks = checks + 320;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7M3R: ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            wait_idle(1000, "F7M3R");
            check_no_resume(200, 26, "F7M3R");
            ack_consume_at(8'd1);
            if (ring_ne_w) fail("F7M3R: ack 后环仍非空");
            else checks = checks + 1;

            // ---- M3S：传输错后软复位恢复（V1.7 案 2 判别）----
            // 再注 SLVERR 得同 M3 错误面 → 软复位恢复（撤注入+soft+
            // cfg_csr_default，无 do_reset）→ 整帧 26 任务重跑绿。
            // 旧码（shell/DMA 错粘着）：软复位后重启帧=派发进错误保持
            // shell → 新引擎错 → W_ERR 死锁（V1.6.2 实测 errsts 复
            // 0x400、errinfo 05/00/11/02、done 恒 0）；ppu_f7_top V1.7
            // ctrl_sreset 臂 16 拍 u_shell wash 清 err_r/halted+arbiter
            // 粘着后此径须与硬复位新纪元逐面等价（环改续行律）。
            // 表 BRAM 驻留（M2 布局穿两次复位完好，soft 不清表正典）。
            exp_op = desc_rom[32*2 + 0];           // 复钉槽2 w0
            csr_wr(A_FRAME_ID, 32'd3);
            csr_tail(16'd26);
            csr_start_frame;
            wait_walk_done(2, 3_000_000, "F7M3S 槽0/1");
            cfg_fault_r_beat = bfm.r_beat_tot + 16;
            bfm_zero_strb_ok_r = 1'b1;    // V1.3：写排干零 strobe 拍豁免窗开
            $display("[RUN F7M3S] 注错 arm：fault_beat=%0d（r_beat_tot=%0d+16）",
                     cfg_fault_r_beat, bfm.r_beat_tot);
            wait_evt_cnt(1, "F7M3S 槽2 PPU 引擎错（二次）");
            repeat (300) @(posedge clk_r);         // W_ERR 粘着窗 + 排干窗
            if (wk_done_w != 2)
                fail($sformatf("F7M3S: done 得%0d 期2", wk_done_w));
            else checks = checks + 1;
            if (ring_pub_cnt != 1) fail("F7M3S: 引擎错不得发环");
            else checks = checks + 1;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b1) fail("F7M3S: bit10 期1");
            else checks = checks + 1;
            csr_rd(A_ERROR_INFO, dv);
            if (dv[31:24] !== 8'h05 || dv[23:16] !== 8'd2
                || dv[15:8] !== exp_op[7:0] || dv[7:0] !== 8'h02)
                fail($sformatf("F7M3S: err_info 得 port%0d desc%0d op%02x code%02x 期5/2/%02x/02",
                               dv[31:24], dv[23:16], dv[15:8], exp_op[7:0]));
            else checks = checks + 4;
            check_frozen(200, 2, "F7M3S");

            // ---- 软复位恢复（本案判别核心：无 do_reset）----
            cfg_fault_r_beat = 0;                  // 撤销读流注入
            // V1.8 排干落定闸（全量）：wash 前置条件 = 主侧在途/占用/
            // 挂 valid 全零 + BFM 账目全零（aw_addr_q/w_expect/b_resp_q/
            // bvalid/ar_addr_q/r_run/rvalid——互连侧无幻影 AW/AR、B 全
            // 返回的直接证明）。闸红 = 排干未竟：倾倒 16 项遥测后
            // $finish（授权纪律：超时必 FAIL，不得带病续 wash——幻影
            // 仅 rst_i 清，wash 救不回，续跑只会复现同面）。
            begin : m3s_drain_settle
                int dt;
                dt = 0;
                while ((dut.u_shell.u_dma.aw_out_r != 4'd0 ||
                        dut.u_shell.u_dma.awvalid_o ||
                        dut.u_shell.u_dma.ar_out_r != 4'd0 ||
                        dut.u_shell.u_dma.arvalid_o ||
                        dut.u_shell.u_dma.wq_occ_r != 3'd0 ||
                        dut.u_shell.u_dma.wvalid_o ||
                        bfm.aw_addr_q.size() != 0 ||
                        bfm.w_expect != 0 ||
                        bfm.b_resp_q.size() != 0 ||
                        bfm.bvalid_o !== 1'b0 ||
                        bfm.ar_addr_q.size() != 0 ||
                        bfm.r_run !== 1'b0 ||
                        bfm.rvalid_o !== 1'b0) && dt < 5000) begin
                    @(posedge clk_r); dt = dt + 1;
                end
                if (dut.u_shell.u_dma.aw_out_r != 4'd0 ||
                    dut.u_shell.u_dma.awvalid_o ||
                    dut.u_shell.u_dma.ar_out_r != 4'd0 ||
                    dut.u_shell.u_dma.arvalid_o ||
                    dut.u_shell.u_dma.wq_occ_r != 3'd0 ||
                    dut.u_shell.u_dma.wvalid_o ||
                    bfm.aw_addr_q.size() != 0 ||
                    bfm.w_expect != 0 ||
                    bfm.b_resp_q.size() != 0 ||
                    bfm.bvalid_o !== 1'b0 ||
                    bfm.ar_addr_q.size() != 0 ||
                    bfm.r_run !== 1'b0 ||
                    bfm.rvalid_o !== 1'b0) begin
                    fail("F7M3S: drain not settled pre-wash (in-flight/occupancy/BFM accounts must be zero)");
                    m3s_dump_dma_state;
                    $display("EES_SUMMARY run=F7M checks=%0d errors=%0d DRAIN_SETTLE_FAIL", checks, errors);
                    $finish;
                end else checks = checks + 1;
            end
            bfm_zero_strb_ok_r = 1'b0;    // 豁免窗关（排干拍已落定）
            csr_soft;
            wait_idle(1000, "F7M3S soft_reset 释放");
            cfg_csr_default;
            // 环孔径停泊律（V1.6.3）：发布前把孔径停泊到写域外
            csr_rd(A_DESC_DONE_COUNT, dv);
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10] !== 1'b0) fail("F7M3S: soft 后 bit10 须 0（wash 清粘着）");
            else checks = checks + 1;
            bfm.clear_logs; gbfm.clear_logs;
            csr_wr(A_FRAME_ID, 32'd4);
            csr_tail(16'd26);
            csr_start_frame;
            rm = 0; wm = 0;
            for (s = 0; s < N_PROG; s = s + 1) begin
                wait_walk_done(s + 1, 3_000_000, $sformatf("F7M3S s%0d", s));
                cmp_golden("rd", PROG[s], rm, "F7M3S", 0);
                cmp_golden("wr", PROG[s], wm, "F7M3S", 0);
                rm = bfm.rd_n; wm = bfm.wr_n;
            end
            v = 0;
            while (gemm_log_q.size() < 1 && v < 200000) begin
                v = v + 1; @(posedge clk_r);
            end
            if (gemm_log_q.size() < 1 || gemm_log_q[0] != 25)
                fail("F7M3S: conv@槽25 GEMM 复派发未见/idx≠25");
            else checks = checks + 1;
            wait_walk_done(26, 3_000_000, "F7M3S conv 槽25");
            wait_ring_pub(2, 200_000, "F7M3S 发环");
            exp_bytes = sum_range(0, 25);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F7M3S: 环字节 得%0d 期%0d", ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            // 软复位恢复=环续行律（V1.6.1，区别于 M3R 硬复位新纪元）：
            // 第 2 次发环（M3R 纪元）seq=2、条目@1、head=2、ack@2。
            if (ring_seq_w != 32'd2) fail("F7M3S: seq != 2（软复位环续行）");
            else checks = checks + 1;
            if (ring_fid_w != 32'd4) fail("F7M3S: fid != 4");
            else checks = checks + 1;
            check_csr_result(32'd2, 32'd4, exp_bytes, 8'd2, "F7M3S");
            check_desc_csr(16'd26, 16'd26, "F7M3S");
            if (eng_evt_cnt != 1)
                fail($sformatf("F7M3S: 引擎事件 得%0d 期1（恢复帧零新增）",
                               eng_evt_cnt));
            else checks = checks + 1;
            if (ppu_log_q.size() != N_PROG)
                fail($sformatf("F7M3S: PPU 派发 得%0d 期%0d（逐帧）",
                               ppu_log_q.size(), N_PROG));
            else checks = checks + 1;
            if (gbfm.rd_n != F7G_EXP_RD || gbfm.wr_n != F7G_EXP_WR)
                fail($sformatf("F7M3S: 引擎侧台账 得rd%0d wr%0d 期%0d/%0d",
                               gbfm.rd_n, gbfm.wr_n, F7G_EXP_RD, F7G_EXP_WR));
            else checks = checks + 2;
            if (bfm_proto_err != 0)
                fail($sformatf("F7M3S: bfm 协议违例 %0d", bfm_proto_err));
            else checks = checks + 1;
            if (gbfm_proto_err != 0)
                fail($sformatf("F7M3S: gbfm 协议违例 %0d", gbfm_proto_err));
            else checks = checks + 1;
            f7g_check_y(6, bad);
            if (bad != 0) fail($sformatf("F7M3S: y 对拍 bad=%0d", bad));
            else checks = checks + 320;
            csr_rd(A_ERROR_STATUS, dv);
            if (dv[10:0] !== 11'd0)
                fail($sformatf("F7M3S: ERROR_STATUS 非零 %03X", dv[10:0]));
            else checks = checks + 1;
            wait_idle(1000, "F7M3S");
            check_no_resume(200, 26, "F7M3S");
            ack_consume_at(8'd2);
            if (ring_ne_w) fail("F7M3S: ack 后环仍非空");
            else checks = checks + 1;
            $display("[RUN F7M3] 完：槽2 PPU 引擎错上下文 desc_id=2/op=%02x + 硬复位整帧重跑（M3R）+ 软复位恢复整帧重跑（M3S，conv@25 复证）/ 环 %0d B / g rd %0d wr %0d / shell rd %0d wr %0d",
                     exp_op[7:0], exp_bytes, gbfm.rd_n, gbfm.wr_n,
                     bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= 主控 =================
    initial begin
        PROG = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                 47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
        errors = 0; checks = 0;
        ring_pub_cnt = 0; ring_ovf_cnt = 0; ring_ack_cnt = 0;
        shell_pub_cnt = 0; desc_evt_cnt = 0; eng_evt_cnt = 0;
        last_disp_idx = -1;
        if (!$value$plusargs("PREP=%s", prep_dir))
            prep_dir = "E:/competition/4_metrics/logs/2026-09-23_yolo_ppu_f6_walker_run01/prep";
        if (!$value$plusargs("RUN=%s", run_s)) run_s = "F7A";
        if ($value$plusargs("FLOW=%s", flow_s)) vivado_flow = (flow_s == "vivado");
        cfg_default;
        rstn_r = 1'b0;

        case (run_s)
        "F7A": run_f7a;
        "F7B": run_f7b;
        "F7C": run_f7c;
        "F7D": run_f7d;
        "F7G": run_f7g;
        "F7S": run_f7s;
        // F7M = M1（conv@0 基线）+ M2（PPU 先行+conv@25 非零槽）+
        //       M3（槽2 PPU 引擎错+恢复重跑）三段连跑一窗出判
        "F7M": begin run_f7m; run_f7m2; run_f7m3; end
        // F7L2 = 子图梯二级：2conv+桥接单帧种子法（V1.9）
        "F7L2": run_f7l2;
        // F7W = B3-S3 S3a-W walker 多 desc 协议专证（V1.10，AUDIT 正名门）
        "F7W": run_f7w;
        // F7SB = B3-S3 S3b-W 首段窗 7 帧 ffe 闭帧门（V1.11，设计 §PASS-2）
        "F7SB": run_f7sb;
        default: begin
            $display("FATAL: 未知 RUN=%s", run_s);
            final_fail("bad-run");
        end
        endcase

        if (bfm_proto_err != 0 && run_s != "F7B" && run_s != "F7D")
            fail($sformatf("协议违例 %0d", bfm_proto_err));
        if (run_s == "F7G" && gbfm_proto_err != 0)
            fail($sformatf("gbfm 协议违例 %0d", gbfm_proto_err));
        if (xz_err != 0)
            fail($sformatf("控制面 X/Z 污染 %0d 拍", xz_err));
        $display("EES_SUMMARY run=%s checks=%0d errors=%0d rd=%0d wr=%0d grd=%0d gwr=%0d",
                 run_s, checks, errors, bfm.rd_n, bfm.wr_n,
                 gbfm.rd_n, gbfm.wr_n);
        if (vivado_flow) begin
            fj = $fopen("f7_result.json", "w");
            $fdisplay(fj, "{\"run\":\"%s\",\"checks\":%0d,\"errors\":%0d}",
                      run_s, checks, errors);
            $fclose(fj);
        end
        if (errors == 0) begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT PASS ppu_f7_top run=%s", run_s);
            else
                $display("EES_VIVADO_RESULT PASS ppu_f7_top run=%s", run_s);
        end else begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT FAIL ppu_f7_top run=%s errors=%0d",
                         run_s, errors);
            else
                $display("EES_VIVADO_RESULT FAIL ppu_f7_top run=%s errors=%0d",
                         run_s, errors);
        end
        $finish;
    end

    // ---- 控制面 X/Z 守卫 ----
    always @(posedge clk_r) if (!rst_hi_w)
        if ((dut.u_wk.state === 1'bx) || (busy_w === 1'bx) ||
            (ring_ready_w === 1'bx) || (dut.port_grant_w === 1'bx))
            xz_err = xz_err + 1;

    // ---- 全局看门狗 ----
    initial begin
        #500_000_000;
        $display("FATAL: F7 全局看门狗 500ms");
        final_fail("watchdog");
    end

endmodule
