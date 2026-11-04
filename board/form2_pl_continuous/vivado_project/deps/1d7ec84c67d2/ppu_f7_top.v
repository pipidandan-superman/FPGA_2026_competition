/************************************************************************
 * File Name       : ppu_f7_top.v
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_f7_top
 * Description     : PPU-F7 控制子系统顶层（replan §PPU-F7）：F6 walker/
 *                   CSR 汇合合同的可综合集成封装，Block Design
 *                   module-ref 顶层。自 yolo_control_subsystem V2.1
 *                   演化（CSR 线冻结物本体不动），集成面：
 *
 *   AXI4-Lite 从（0x43C1_0000，64 KB）= 原 V2.1 区域译码/写保护/
 *     窗口算术/读应答流水逐位沿用；调度器换 yolo_desc_walker_f6
 *     V3.0（引擎派发 + port-B 让渡），计算引擎 = ppu_shell_top V1.3
 *     （XFER/VIEW/UPSAMPLE2/MAXPOOL5/ADD；conv 验证即完），GEMM 后端
 *     = ppu_gemm_stub_f7（V1.8/M5-V2.4：真引擎 154/220=70.0% DSP 正压
 *     资源门；conv 走 BD 原路径 u_yolo_gemm 绝不经此引擎，M5 图算子
 *     域无 GEMM 描述符 → err 路径不可达；F7b 真引擎回插按
 *     rtl_ledger_m5.json 台账逆替换。V1.6 曾换装 ppu_gemm_engine V1.3
 *     （内部 yolo_gemm_top V1.2 + 自带第二 ppu_dma_master 出 m1_axi，
 *     G03 推荐径），u_gdma/m1_axi 连线与 wash 复位树全保留零流量待命）。
 *
 *   描述符表 port-B 单读者让渡 mux（F6 合同，tb_ppu_f6.sv 蓝图）：
 *     三路版（P2.2）：b_addr = !port_grant ? walker.desc_rd_addr_o
 *       : (gemm_sel_q ? gemm_engine.desc_rd_addr_o : shell.desc_addr_o)。
 *     gemm_sel_q 在 wk_greq_w 派发脉冲拍锁存（引擎 desc 地址 T+1 起
 *     有效，时序吻合）、!port_grant 拍清零；W_ENG 期 walker 停查，
 *     shell 取包（PPU 任务）或引擎抓 ABI v2 字（GEMM 任务）。
 *     buf/quant 表 port-B 只读口由 F7 变体表引出，仅 shell 读。
 *
 *   GEMM 数据通路（P2.2，G03 推荐径）：引擎自带第二 ppu_dma_master
 *     （u_gdma）出独立 m1_axi（BD：axi_mem_intercon NUM_SI=2 与 shell
 *     共享 S_AXI_HP0 同段）——金样镜像/参数/装载读与 y 写全走 m1_axi，
 *     shell m_axi 台账（F7B rd/wr 拍数）不受 GEMM 任务扰动。恢复正典：
 *     引擎 rcvr_o（E_ABORT/E_ERR 族）→ u_gdma.abort_i（在途受控排空）；
 *     rcvr_o 后沿 → gwash_cnt=16 拍 wash 复位（ppu_dma_master err/abort
 *     锁存仅 rst 可清——shell DMA 同局限记录在案，GEMM 侧结构修复）。
 *
 *   事件三线：CTRL stop/abort 脉冲同源 fan-out 到 walker 与 shell
 *     （F6 TB 同一线 stop_wk/abort_wk）；ffe = A_DESC_DOORBELL bit1
 *     （置 frame_end_pending 粘着供 walker 消费 + ffe_pulse 供 shell，
 *     reg_file_f7 双落点）。
 *
 *   head_base：LO → shell.head_base_i（32 位 DMA 地址；HI 必须为 0，
 *     DDR <4GB，板上合同）；{HI,LO} → ring.pub_head_base_i。
 *   DMA_CFG（0x200，F7 定版）：[23:0] 超时拍数、[26:24] 读 outstanding
 *     上限、[29:27] 写 outstanding 上限。
 *   ERROR_STATUS bit10 = 引擎错误（walker err_evt_eng_o：PPU ldr/dma
 *     错、GEMM 引擎 err；pkg 冻结于 0-9，本地 E_BIT_ENGINE 扩位）。
 *     DEBUG 区 0x7000 = GEMM 现场字（busy/rcvr/sel/wash/DMA err/engine
 *     err_code 纯组合快照，上板排障面；P2.2 增补）。
 *
 *   复位（V1.5 双极性 BUFG 树，Stage3-v2 Phase D 第一阶段）：BD
 *     aresetn（proc_sys_reset 同步释放）→ 两片 BUFG——低有效全局
 *     rst_n_glue_w 喂 u_slave/u_regf/u_wk/u_ring + top 本地
 *     rd_ack_pipe；高有效全局 rst_hi_w（LUT1 反相仅在 BUFG 之前、
 *     扇出 1）喂 u_shell/u_gemm（引擎+u_gdma 经引擎 rst 面，wash
 *     见 GEMM 数据通路节；u_shell 另受 V1.7 软复位 swash 门控，
 *     见 shell wash 节）。极性/同步异步端点语义不变
 *     （V1.4 及以前 aresetn 直连——recovery -20.224 / sync-rst
 *     setup -20.4、路由占 70%+ 的结构级分发整改，规格 §四）。
 *
 *   TDP 同址冲突结构性规避（用户铁律）：PS 写表仅限 walker 空闲窗
 *     （tbl_locked=walker_running）；port-B 引擎读仅发生在运行期
 *     ——写/读不同时存在；PS 读与引擎读为读-读组合，无冲突语义。
 *
 *   NOTE: 本文件纯 Verilog-2001（RTL 铁律 .v；BD "Add Module" 只收
 *   Verilog 顶层）。yolo_csr_pkg 常量由 SV 子模块自行 import，本层
 *   内联镜像的常量标注 keep in sync。
 * Dependencies    : yolo_axi_lite_slave.sv, yolo_reg_file_f7.sv,
 *                   yolo_desc_walker_f6.v, ppu_shell_top.v（含 shell
 *                   五件套）, ppu_gemm_stub_f7.v（V1.8 起例化；
 *                   ppu_gemm_engine.v 及 GEMM 面件套保留在源集供 F7b
 *                   回插，不再被本顶层例化）, ppu_dma_master.v（u_gdma 第二实例）,
 *                   yolo_result_ring.sv, yolo_desc_table.sv,
 *                   yolo_buf_table_f7.sv, yolo_quant_table_f7.sv,
 *                   yolo_lut_table.sv
 *                   （表内真 BMG v8.4 XCI，输出寄存器 DISABLED）
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版——V2.1 骨架 + F6 集成面
 *                （13 缺口逐项消解：port-B mux / buf-qt port-B 引出 /
 *                复位极性 / DMA_CFG 布局 / ffe 脉冲源 / err bit10 /
 *                head_base 拆分 / GEMM 桩）。
 *   - V1.5 (2026-09-24) by LSL : 复位双极性 BUFG 树（Stage3-v2
 *                Phase D 第一阶段，规格 §四）——2×BUFG：rst_n_glue_w
 *                （u_slave/u_regf/u_wk/u_ring/rd_ack_pipe）+
 *                rst_hi_w（u_shell/u_gemm_stub）；BUFG 后无高扇出
 *                反相网。证据：f7tmg_run01 ev1/ev2（复位两网原始
 *                扇出 ~4533 FD、recovery -20.224、sync-rst setup
 *                -20.4、route 主导 70%+）。若 O 后仍有违例升级
 *                第二阶段分区本地 reset synchronizer。
 *   - V1.6 (2026-09-28) by LSL : P2.2 GEMM 换装——u_gemm_stub →
 *                ppu_gemm_engine V1.3 + 第二 ppu_dma_master（u_gdma）
 *                出 m1_axi；desc port-B 三路 mux（gemm_sel_q 派发拍
 *                锁存）；rcvr_o 后沿 16 拍 wash 复位清 u_gdma err/
 *                abort 锁存；DEBUG 0x7000 GEMM 现场字。语义约束：
 *                F7A-D 全部门零改（GEMM 任务无真载荷时 m1_axi 零流
 *                量；B5 桩 err 负例改由坏 K desc 经真引擎 E_GEOM2
 *                错误回路产生，TB 侧同步改）。
 *   - V1.7 (2026-09-29) by LSL : 软复位恢复语义加固（用户指令"1+2
 *                合并改"）——ctrl_sreset 臂 16 拍 shell wash 复位
 *                （u_shell.rst_i = rst_hi_w || swash，清 shell/DMA 错
 *                粘着；V1.6 头注"shell DMA 同局限记录在案"闭合）。
 *                传输错后软复位恢复自此正典（M3S 判别腿）；dma_cfg=0
 *                footgun 由 ppu_dma_master V1.3 消费端钳位闭合（F7S-4
 *                判别腿）。walker/ring/regfile 软复位扇出不变。
 *   - V1.8 (2026-10-07) by LSL/M5 : u_gemm 换回 ppu_gemm_stub_f7
 *                （GEMM_DELAY=8/GEMM_ERR_ALWAYS=1，不伪装成功）+ 原
 *                u_gemm 独占输出 tie-off（ecode=0xE0/busy=0/rcvr=0/
 *                desc_addr=0/DMA 用户面全 0）。动机：V2.4 位流资源门
 *                （真引擎 154/220=70.0% DSP 正压 + LUT 双红；stub 78/220
 *                ≈35%）。M5 域无 GEMM 描述符 → err 路径不可达；u_gdma、
 *                m1_axi 连线、gwash/swash 复位树全保留（零流量待命）。
 *                台账 rtl_ledger_m5.json；F7A-D 门回归见 M5.1 xsim run。
 *   - V1.9-M10.3 (2026-10-17) by PPU activation (m10p3_ppu_act_run01):
 *                v25-island copy of the main-tree V1.8 file (byte-copy
 *                provenance sha256 in run provenance_rtl_ppu_sha256.txt;
 *                main tree 12_yolo_accel/.../ppu/f7/ppu_f7_top.v is NOT
 *                touched). Delta = PPU_ACTIVATION_PLAN.md section 1.3
 *                three structural gaps closed, port/wiring face only,
 *                zero new registers (multi-drive two-gate law):
 *                (1) eight PL dispatch ports exported at the island top
 *                    (walker f6 PL face, M10.2 blood);
 *                (2) u_wk PL face connected + .ppu_ldr_code_i wired to
 *                    the in-island sh_ldr_code_w (existed, was dangling);
 *                (3) desc_count_w[6:0] exported as ppu_desc_count_pl_o
 *                    (conv-issuer E_PPP_DESC evidence, DESIGN_m8_v23
 *                    section 3.3-1).
 *   - V1.10-M10.6-RungC (2026-10-18) by M10.6 Rung C : seg_done 完成
 *                位图 + commit 门集成（SPEC §2 提案 (a) 案 + L29 律）：
 *                (1) 新 ppu_seg_done tracker 例化（u_segd）——shell
 *                    三脉冲馈源（engine_mux V2.1）、帧边界=CTRL
 *                    start_frame（挂 doorbell 镜像）；
 *                (2) u_wk.commit_gate_i 接线（0x114 队列路径 W_PUB
 *                    位图全满门；PL 三面线/非 heads 帧零语义变化）；
 *                (3) A_SEG_DONE(0x074) RO CSR 读拦截（rd mux REGF 支，
 *                    CSR 线 .sv 冻结文件零触碰）。零顶层端口新增——
 *                    v25_top（m9_v25_top_v3）集成与 PPU_ISLAND 刀面
 *                    不受影响；PPU_NO_UPS 刀下恒可编译。
 *   - V1.11-G5 (2026-10-28) by Stage B PPU lane : candidate-only accepted
 *                heads-start fanout, raw-pending/gated-done epoch, and shim
 *                fence/fault integration.  A_STATUS[2] is host-gated done.
 ************************************************************************/
`timescale 1ns / 1ps

module ppu_f7_top (
    input  wire        s_axi_aclk    ,
    input  wire        s_axi_aresetn ,
    // AXI4-Lite slave interface (names fixed by AXI/BD convention)
    input  wire [31:0] s_axi_awaddr  ,
    input  wire [2:0]  s_axi_awprot  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire [3:0]  s_axi_wstrb   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [31:0] s_axi_araddr  ,
    input  wire [2:0]  s_axi_arprot  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready  ,
    // AXI4 master, 64-bit data (PPU DMA: INCR, <=16 beats)
    output wire [31:0] m_axi_araddr  ,
    output wire [3:0]  m_axi_arlen   ,
    output wire [2:0]  m_axi_arsize  ,
    output wire [1:0]  m_axi_arburst ,
    output wire        m_axi_arvalid ,
    input  wire        m_axi_arready ,
    input  wire [63:0] m_axi_rdata   ,
    input  wire [1:0]  m_axi_rresp   ,
    input  wire        m_axi_rlast   ,
    input  wire        m_axi_rvalid  ,
    output wire        m_axi_rready  ,
    output wire [31:0] m_axi_awaddr  ,
    output wire [3:0]  m_axi_awlen   ,
    output wire [2:0]  m_axi_awsize  ,
    output wire [1:0]  m_axi_awburst ,
    output wire        m_axi_awvalid ,
    input  wire        m_axi_awready ,
    output wire [63:0] m_axi_wdata   ,
    output wire [7:0]  m_axi_wstrb   ,
    output wire        m_axi_wlast   ,
    output wire        m_axi_wvalid  ,
    input  wire        m_axi_wready  ,
    input  wire [1:0]  m_axi_bresp   ,
    input  wire        m_axi_bvalid  ,
    output wire        m_axi_bready  ,
    // AXI4 master #2, 64-bit data (GEMM DMA: mirror/param/load reads + y
    // writes; BD: second SI of axi_mem_intercon sharing S_AXI_HP0)
    output wire [31:0] m1_axi_araddr  ,
    output wire [3:0]  m1_axi_arlen   ,
    output wire [2:0]  m1_axi_arsize  ,
    output wire [1:0]  m1_axi_arburst ,
    output wire        m1_axi_arvalid ,
    input  wire        m1_axi_arready ,
    input  wire [63:0] m1_axi_rdata   ,
    input  wire [1:0]  m1_axi_rresp   ,
    input  wire        m1_axi_rlast   ,
    input  wire        m1_axi_rvalid  ,
    output wire        m1_axi_rready  ,
    output wire [31:0] m1_axi_awaddr  ,
    output wire [3:0]  m1_axi_awlen   ,
    output wire [2:0]  m1_axi_awsize  ,
    output wire [1:0]  m1_axi_awburst ,
    output wire        m1_axi_awvalid ,
    input  wire        m1_axi_awready ,
    output wire [63:0] m1_axi_wdata   ,
    output wire [7:0]  m1_axi_wstrb   ,
    output wire        m1_axi_wlast   ,
    output wire        m1_axi_wvalid  ,
    input  wire        m1_axi_wready  ,
    input  wire [1:0]  m1_axi_bresp   ,
    input  wire        m1_axi_bvalid  ,
    output wire        m1_axi_bready  ,
    // interrupt (level: armed and (frame done or error))
    output wire        irq_o,
    // ---- v2.3 PL dispatch face (M10.2 m8 three-line contract, DESIGN
    //      section 3.1; M10.3 activation V1.9 export). Run-label law:
    //      ppp_mode (this face) and des_mode (0x114 queue) must not be
    //      mixed within one run. ----
    input  wire        ppu_start_pl_i     ,  // conv issuer trigger pulse
    input  wire [17:0] ppp_payload_pl_i   ,  // {gen[7:0], seg_idx[2:0], desc_idx[6:0]}
    input  wire [7:0]  frame_token_pl_i   ,  // conv CSR doorbell generation
    input  wire        token_valid_pl_i   ,  // pulse: latch cur_gen
    output wire        ppu_done_pl_o      ,  // verdict pulse -> conv issuer
    output wire        ppp_done_abort_pl_o,  // 1 = token/engine failure
    output wire [7:0]  ppp_done_err_pl_o  ,  // abort err code (with pulse)
    output wire [6:0]  ppu_desc_count_pl_o,  // loaded-DESC count (issuer sanity)
    // ---- G5 heads profile/fence interface (WR_OUTST_EFFECTIVE_1 only) ----
    input  wire        hw_m03_heads_commit_fence_i,
    input  wire        heads_transaction_fault_i,
    input  wire        m03_idle_quiescent_i,
    input  wire        epoch_invalid_i,
    output wire        heads_start_accepted_o,
    output wire        heads_gated_done_event_o,
    output wire        heads_frame_done_allowed_o,
    output wire        heads_epoch_active_o,
    output wire        heads_epoch_profile_accepted_o,
    output wire        heads_epoch_cfg0_o,
    output wire        heads_live_dma_cfg0_o,
    output wire        heads_profile_fault_o,
    output wire        ppu_error_any_o
);

    // ------------------------------------------------------------ --
    // constants mirrored from yolo_csr_pkg.sv -- keep in sync
    // ------------------------------------------------------------ --
    localparam integer TABLE_RD_LATENCY   = 1;

    localparam [7:0]   E_CODE_DESC_INVALID = 8'h01;
    localparam [7:0]   E_CODE_ENG_ERR      = 8'h02;  // F7 本地扩码
    localparam [7:0]   E_CODE_RING_OVF     = 8'h10;
    localparam [7:0]   E_CODE_RING_RO      = 8'h11;
    localparam [7:0]   E_CODE_TABLE_RUN    = 8'h12;
    localparam [7:0]   E_CODE_ADDR_ALIGN   = 8'h13;
    localparam [7:0]   E_CODE_ADDR_REGION  = 8'h14;
    localparam [7:0]   E_CODE_ACK_EMPTY    = 8'h15;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // M10.6 Rung C：A_SEG_DONE 6b 完成位图 RO CSR 地址。REGF 区空闲槽
    //（0x070 RESULT_CONF_Q 之后、0x100 DESC_CFG 之前）；yolo_csr_pkg
    // 冻结不动，本常量与驱动/TB 的本地镜像保持同步（TB 镜像律，同
    // tb_ppu_heads6.sv 头部 A_* 本地镜像先例）。
    localparam [15:0] A_SEG_DONE = 16'h074;
    localparam [15:0] A_DMA_CFG  = 16'h200;

    // region codes
    localparam [3:0] RGN_REGF  = 4'd0,
                     RGN_DESC  = 4'd1,
                     RGN_BUF   = 4'd2,
                     RGN_QUANT = 4'd3,
                     RGN_LUT   = 4'd4,
                     RGN_RING  = 4'd5,
                     RGN_DEBUG = 4'd6,
                     RGN_BAD   = 4'd7;

    // ------------------------------------------------------------ --
    // reset polarity glue: BD aresetn (proc_sys_reset sync release) ->
    // dual-polarity BUFG tree (Stage3-v2 Phase D Stage 1, spec section 4).
    // V1.4 evidence: two reset nets raw-fanout ~4533 FDs -- aresetn ->
    // u_wk/u_ring FDCE/CLR async (recovery -20.224) + rst_hi_w (LUT1)
    // -> u_shell subtree FDRE/R sync (setup, top12 -20.4). Route-dominated
    // (70%+), replicators already tried by synth (_rep__) -- a structural
    // distribution fix, not phys-opt. Both polarities driven on global
    // clock networks; the ONLY fabric inverter sits ahead of BUFG#2 with
    // fanout 1 (no post-BUFG high-fanout inversion regenerated). Sync/
    // async endpoint semantics unchanged (audit: recovery/removal on
    // FDCE/CLR, setup on FDRE/R).
    // ------------------------------------------------------------ --
    wire rst_hi_pre_w = ~s_axi_aresetn;   // LUT1, fanout 1 (BUFG in only)
    wire rst_n_bf_w;                       // low-active global
    wire rst_hi_bf_w;                      // high-active global
    BUFG u_rst_n_bfg  (.I (s_axi_aresetn), .O (rst_n_bf_w));
    BUFG u_rst_hi_bfg (.I (rst_hi_pre_w),  .O (rst_hi_bf_w));
    // polarity alias keeps instance maps readable below
    wire rst_n_glue_w  = rst_n_bf_w;
    wire rst_hi_w      = rst_hi_bf_w;

    // ------------------------------------------------------------ --
    // address region decode
    // ------------------------------------------------------------ --
    function [3:0] f_region(input [15:0] a);
        begin
            if      (a < 16'h0300)                    f_region = RGN_REGF;
            else if (a >= 16'h1000 && a < 16'h3000)   f_region = RGN_DESC;
            else if (a >= 16'h3000 && a < 16'h4000)   f_region = RGN_BUF;
            else if (a >= 16'h4000 && a < 16'h5000)   f_region = RGN_QUANT;
            else if (a >= 16'h5000 && a < 16'h6000)   f_region = RGN_LUT;
            else if (a >= 16'h6000 && a < 16'h6800)   f_region = RGN_RING;
            else if (a >= 16'h7000 && a < 16'h8000)   f_region = RGN_DEBUG;
            else                                      f_region = RGN_BAD;
        end
    endfunction

    // ------------------------------------------------------------ --
    // forward declarations
    // ------------------------------------------------------------ --
    // slave internal buses
    wire        wr_valid_w;
    wire        rd_valid_w;
    wire [15:0] wr_addr_w;
    wire [15:0] rd_addr_w;
    wire [31:0] wr_data_w;
    wire [3:0]  wr_strb_w;
    wire [1:0]  wr_rsp_w;
    wire [1:0]  rd_rsp_w;
    wire        rd_ack_w;
    wire [31:0] rd_data_w;
    wire        err_align_evt;
    // regfile <-> others
    wire        ctrl_enable;
    wire        ctrl_start;
    wire        ctrl_stop;
    wire        ctrl_abort;
    wire        ctrl_clr;
    wire        ctrl_flush;
    wire        ctrl_sreset;
    wire        ctrl_arm_irq;
    wire        dbell_commit;
    wire        ffe_pulse_w;
    wire        frame_end_clear;
    wire        frame_end_pending_w;
    wire [15:0] desc_tail_w;
    wire [15:0] desc_count_w;
    wire [15:0] walker_head_w;
    wire [15:0] walker_cur_w;
    wire [15:0] walker_done_w;
    wire [15:0] walker_err_id_w;
    wire [7:0]  desc_depth_w;
    wire [7:0]  walker_opcode_w;
    wire        desc_circular_w;
    wire [11:0] desc_win_base_w;
    wire [7:0]  ring_head_ptr_w;
    wire [7:0]  ring_tail_ptr_w;
    wire        ring_not_empty_w;
    wire        ring_ack_consume_w;
    wire        ring_ack_drop_w;
    wire        ring_ack_retry_w;
    wire [31:0] ring_seq_w;
    wire [31:0] ring_frame_id_w;
    wire [31:0] ring_head_bytes_w;
    wire        ring_publish_evt_w;
    wire        ring_overflow_evt_w;
    wire        ring_ack_err_evt;
    wire [31:0] regf_rd_data_w;
    wire [10:0] err_events_w;
    reg  [7:0]  err_code_w;
    reg  [7:0]  err_op_w;
    reg  [7:0]  err_desc_id_w;
    reg  [7:0]  err_port_w;
    wire [31:0] frame_id_w;
    wire [31:0] dma_cfg_w;
    wire [31:0] head_base_lo_w;
    wire [31:0] head_base_hi_w;
    wire [31:0] head_fmt_w;
    wire [10:0] error_status_w;
    wire        heads_prelaunch_profile_valid_w;
    wire        heads_profile_fault_sticky_w;
    wire        heads_start_reject_sticky_w;
    wire        heads_profile_fault_event_w;
    wire        heads_host_done_w;
    reg         heads_epoch_active_q;
    reg         heads_epoch_profile_accepted_q;
    reg         heads_epoch_cfg0_q;
    reg         heads_raw_done_pending_q;
    reg         heads_raw_consumed_q;
    // walker <-> shell engine dispatch
    wire        wk_ppureq_w;
    wire [6:0]  wk_ppuidx_w;
    wire        sh_busy_w;
    wire        sh_desc_done_w;
    wire        sh_stopped_w;
    wire        sh_ldr_ev_w;
    wire        sh_dma_halt_w;
    // walker <-> gemm engine (P2.2)
    wire        wk_greq_w;
    wire [6:0]  wk_gidx_w;
    wire [7:0]  wk_gop_w;
    wire        gemm_done_w;
    wire        gemm_err_w;
    wire [7:0]  gemm_ecode_w;
    wire        gemm_busy_w;
    wire        g_rcvr_w;               // 引擎恢复段 → u_gdma.abort_i
    // gemm desc port-B 让渡三路 mux 选择锁存
    reg         gemm_sel_q;
    wire [11:0] gemm_desc_addr_w;
    // gemm DMA 用户面（u_gdma <-> u_gemm）
    wire        gd_req_valid_w, gd_req_ready_w;
    wire [31:0] gd_req_addr_w;
    wire [23:0] gd_req_len_w;
    wire        gd_beat_valid_w, gd_beat_ready_w;
    wire [63:0] gd_beat_data_w;
    wire        gd_rd_done_w;
    wire        gdw_req_valid_w, gdw_req_ready_w;
    wire [31:0] gdw_req_addr_w;
    wire [23:0] gdw_req_len_w;
    wire        gdw_beat_valid_w, gdw_beat_ready_w;
    wire [63:0] gdw_beat_data_w;
    wire [7:0]  gdw_beat_strb_w;
    wire        gd_wr_done_w;
    wire        gdma_err_pulse_w;
    wire [3:0]  gdma_err_bit_w;
    wire [7:0]  gdma_err_code_w;
    wire        gdma_halt_w;
    // gemm DMA wash 复位发生器
    reg  [4:0]  gwash_cnt;
    reg         g_rcvr_q;
    // shell 软复位 wash 复位发生器（V1.7 案 2）
    reg  [4:0]  swash_cnt;
    wire        shell_rst_w;
    // shell error detail (info latch 仅取有效位，整组留观察口)
    wire [3:0]  sh_ldr_step_w, sh_ldr_bit_w;
    wire [7:0]  sh_ldr_code_w;
    wire        sh_dma_ev_w;
    wire [3:0]  sh_dma_bit_w;
    wire        sh_eng_busy_w;
    wire [2:0]  sh_cause_w;
    // M10.6 Rung C：seg_done 位图链（shell/engine_mux 馈源 → tracker）
    wire        sh_seg_done_pl_w;
    wire [2:0]  sh_seg_done_idx_w;
    wire        sh_heads_start_pl_w;
    wire [5:0]  segd_bitmap_w;
    wire        segd_commit_ok_w;
    // walker
    wire        walker_idle_w;
    wire        walker_busy;
    wire        walker_frame_done_w;
    wire        walker_err_evt;
    wire        walker_eng_evt;
    wire [7:0]  walker_err_op_w;
    wire [7:0]  walker_err_desc_w;
    wire        pub_valid_w;
    wire        pub_ready_w;
    wire [31:0] pub_bytes_w;
    // desc table port-B arbitration
    wire [11:0] walker_desc_addr_w;
    wire [31:0] muxed_desc_data_w;
    wire        port_grant_w;
    wire [11:0] shell_desc_addr_w;
    wire [9:0]  shell_buf_addr_w;
    wire [9:0]  shell_qt_addr_w;
    wire [31:0] shell_buf_din_w;
    wire [31:0] shell_qt_din_w;
    // tables
    wire        wr_desc;
    wire        wr_buf;
    wire        wr_quant;
    wire        wr_lut;
    wire [31:0] desc_rd_data_w;
    wire [31:0] buf_rd_data_w;
    wire [31:0] quant_rd_data_w;
    wire [31:0] lut_rd_data_w;
    wire [31:0] ring_rd_data_w;

    // ------------------------------------------------------------ --
    // AXI4-Lite slave instance
    // ------------------------------------------------------------ --
    yolo_axi_lite_slave u_slave (
        .clk_i           (s_axi_aclk),
        .rst_n           (rst_n_glue_w),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .wr_valid_o      (wr_valid_w),
        .wr_addr_o       (wr_addr_w),
        .wr_data_o       (wr_data_w),
        .wr_strb_o       (wr_strb_w),
        .wr_rsp_i        (wr_rsp_w),
        .rd_valid_o      (rd_valid_w),
        .rd_addr_o       (rd_addr_w),
        .rd_ack_i        (rd_ack_w),
        .rd_data_i       (rd_data_w),
        .rd_rsp_i        (rd_rsp_w),
        .err_axi_event_o (err_align_evt)
    );

    // ------------------------------------------------------------ --
    // write decode (sources are registered in the slave)
    // ------------------------------------------------------------ --
    wire [3:0]  wr_region  = f_region(wr_addr_w);
    wire [3:0]  rd_region  = f_region(rd_addr_w);
    wire        wr_aligned = (wr_addr_w[1:0] == 2'b00);
    wire        rd_aligned = (rd_addr_w[1:0] == 2'b00);

    // table lock: tables are writable only while the walker is idle
    wire tbl_locked  = walker_busy;
    wire wr_is_table = (wr_region == RGN_DESC) || (wr_region == RGN_BUF) ||
                       (wr_region == RGN_QUANT) || (wr_region == RGN_LUT);

    wire wr_illegal = !wr_aligned ||
                      (wr_region == RGN_BAD) ||
                      (wr_region == RGN_RING) ||        // ring is read-only
                      (wr_is_table && tbl_locked);      // reload in idle only
    assign wr_rsp_w = wr_illegal ? RESP_SLVERR : RESP_OKAY;

    // per-target write strobes (single beat, sources registered)
    wire wr_fire = wr_valid_w;                           // wr_ready is 1
    wire wr_regf = wr_fire && wr_aligned && (wr_region == RGN_REGF);
    assign wr_desc  = wr_fire && wr_aligned && (wr_region == RGN_DESC)  && !tbl_locked;
    assign wr_buf   = wr_fire && wr_aligned && (wr_region == RGN_BUF)   && !tbl_locked;
    assign wr_quant = wr_fire && wr_aligned && (wr_region == RGN_QUANT) && !tbl_locked;
    assign wr_lut   = wr_fire && wr_aligned && (wr_region == RGN_LUT)   && !tbl_locked;

    // write-path error events
    wire evt_region_bad  = wr_fire && (wr_region == RGN_BAD);
    wire evt_ring_ro     = wr_fire && wr_aligned && (wr_region == RGN_RING);
    wire evt_desc_guard  = wr_fire && wr_aligned && (wr_region == RGN_DESC)  && tbl_locked;
    wire evt_buf_guard   = wr_fire && wr_aligned && (wr_region == RGN_BUF)   && tbl_locked;
    wire evt_quant_guard = wr_fire && wr_aligned && (wr_region == RGN_QUANT) && tbl_locked;
    wire evt_lut_guard   = wr_fire && wr_aligned && (wr_region == RGN_LUT)   && tbl_locked;

    // ------------------------------------------------------------ --
    // read address mapping
    //
    // NOTE on window arithmetic: the descriptor aperture is 8 KB at
    // 0x1000 and its base has bit 12 set, so the window-relative word
    // offset must be formed by an explicit subtraction -- slicing the
    // raw address with [12:2] would leak the aperture base into the
    // offset (0x1000 -> offset 1024 instead of 0).  The 4 KB windows
    // below have all-zero low 12 base bits, so [11:2]/[10:2] are
    // already window-relative.
    // ------------------------------------------------------------ --
    wire [13:0] desc_wr_off = wr_addr_w[13:0] - 14'h1000;
    wire [13:0] desc_rd_off = rd_addr_w[13:0] - 14'h1000;
    wire [11:0] desc_wr_word = desc_win_base_w + {1'b0, desc_wr_off[12:2]};
    wire [11:0] desc_rd_word = desc_win_base_w + {1'b0, desc_rd_off[12:2]};
    wire [9:0]  buf_word     = rd_addr_w[11:2];
    wire [9:0]  quant_word   = rd_addr_w[11:2];
    wire [9:0]  lut_word     = rd_addr_w[11:2];
    wire [8:0]  ring_word    = rd_addr_w[10:2];

    wire rd_illegal = (rd_region == RGN_BAD);
    assign rd_rsp_w = (!rd_aligned || rd_illegal) ? RESP_SLVERR : RESP_OKAY;

    // ------------------------------------------------------------ --
    // DMA_CFG field slice (F7 layout, see header)
    // ------------------------------------------------------------ --
    wire [23:0] dma_timeout_w = dma_cfg_w[23:0];
    wire [2:0]  rd_outst_w    = dma_cfg_w[26:24];
    wire [2:0]  wr_outst_w    = dma_cfg_w[29:27];

    // G5: only cfg[29:27]==0 is reviewed.  Other DMA_CFG bits do not
    // participate in profile acceptance.  Case equality makes X/Z fail
    // closed in simulation; hardware implements the same three-bit compare.
    assign heads_live_dma_cfg0_o = (dma_cfg_w[29:27] === 3'd0);
    assign ppu_error_any_o = (|error_status_w) || (|err_events_w);
    assign heads_profile_fault_o = heads_profile_fault_sticky_w;
    assign heads_epoch_active_o = heads_epoch_active_q;
    assign heads_epoch_profile_accepted_o = heads_epoch_profile_accepted_q;
    assign heads_epoch_cfg0_o = heads_epoch_cfg0_q;

    wire heads_idle_quiescent_w = walker_idle_w && !walker_busy &&
        !sh_busy_w && !sh_eng_busy_w && !heads_epoch_active_q &&
        !heads_raw_done_pending_q && m03_idle_quiescent_i;
    wire heads_current_fault_event_w = heads_profile_fault_event_w ||
        heads_transaction_fault_i || ppu_error_any_o || epoch_invalid_i ||
        (heads_epoch_active_q && !heads_live_dma_cfg0_o);

    assign heads_start_accepted_o = ctrl_start &&
        heads_prelaunch_profile_valid_w && heads_live_dma_cfg0_o &&
        heads_idle_quiescent_w && !heads_profile_fault_sticky_w &&
        !heads_start_reject_sticky_w && !heads_transaction_fault_i &&
        !ppu_error_any_o && !epoch_invalid_i &&
        !heads_profile_fault_event_w;

    wire heads_raw_pending_available_w = heads_raw_done_pending_q ||
        (walker_frame_done_w && heads_epoch_active_q &&
         !heads_raw_consumed_q);
    assign heads_gated_done_event_o = heads_epoch_active_q &&
        !heads_raw_consumed_q && heads_raw_pending_available_w &&
        hw_m03_heads_commit_fence_i && !heads_profile_fault_sticky_w &&
        !heads_transaction_fault_i && !ppu_error_any_o &&
        !epoch_invalid_i && !heads_current_fault_event_w;
    assign heads_frame_done_allowed_o = heads_host_done_w &&
        !heads_profile_fault_sticky_w && !heads_transaction_fault_i &&
        !ppu_error_any_o && !epoch_invalid_i;

    // Raw done is only a pending request.  A single gated event consumes it;
    // faults have final priority over same-cycle start/done updates.
    always @(posedge s_axi_aclk) begin
        if (!rst_n_glue_w || ctrl_sreset) begin
            heads_epoch_active_q <= 1'b0;
            heads_epoch_profile_accepted_q <= 1'b0;
            heads_epoch_cfg0_q <= 1'b0;
            heads_raw_done_pending_q <= 1'b0;
            heads_raw_consumed_q <= 1'b0;
        end else begin
            if (heads_start_accepted_o) begin
                heads_epoch_active_q <= 1'b1;
                heads_epoch_profile_accepted_q <= 1'b1;
                heads_epoch_cfg0_q <= 1'b1;
                heads_raw_done_pending_q <= 1'b0;
                heads_raw_consumed_q <= 1'b0;
            end
            if (walker_frame_done_w && heads_epoch_active_q &&
                !heads_raw_consumed_q) begin
                heads_raw_done_pending_q <= 1'b1;
            end
            if (heads_gated_done_event_o) begin
                heads_epoch_active_q <= 1'b0;
                heads_epoch_profile_accepted_q <= 1'b0;
                heads_epoch_cfg0_q <= 1'b0;
                heads_raw_done_pending_q <= 1'b0;
                heads_raw_consumed_q <= 1'b1;
            end
            if (heads_current_fault_event_w) begin
                heads_epoch_active_q <= 1'b0;
                heads_epoch_profile_accepted_q <= 1'b0;
                heads_epoch_cfg0_q <= 1'b0;
                heads_raw_done_pending_q <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ --
    // register file (F7 variant)
    // ------------------------------------------------------------ --
    yolo_reg_file_f7 u_regf (
        .clk_i               (s_axi_aclk),
        .rst_n               (rst_n_glue_w),
        .soft_reset_i        (ctrl_sreset),
        .csr_wr_valid_i      (wr_regf),
        .csr_wr_addr_i       (wr_addr_w),
        .csr_wr_data_i       (wr_data_w),
        .csr_rd_addr_i       (rd_addr_w),
        .csr_rd_valid_i      (rd_valid_w),
        .csr_rd_ack_i        (rd_ack_w),
        .csr_rd_rsp_i        (rd_rsp_w),
        .csr_rd_data_i       (rd_data_w),
        .csr_rd_data_o       (regf_rd_data_w),
        .heads_epoch_active_i(heads_epoch_active_q),
        .csr_heads_start_accepted_i(heads_start_accepted_o),
        .heads_gated_done_event_i(heads_gated_done_event_o),
        .heads_transaction_fault_i(heads_transaction_fault_i),
        .ppu_error_any_i     (ppu_error_any_o),
        .epoch_invalid_i     (epoch_invalid_i),
        .heads_prelaunch_profile_valid_o(heads_prelaunch_profile_valid_w),
        .heads_profile_fault_sticky_o(heads_profile_fault_sticky_w),
        .heads_start_reject_sticky_o(heads_start_reject_sticky_w),
        .heads_profile_fault_event_o(heads_profile_fault_event_w),
        .heads_host_done_o   (heads_host_done_w),
        .walker_idle_i       (walker_idle_w),
        .walker_running_i    (walker_busy),
        .walker_frame_done_i (walker_frame_done_w),
        .walker_cur_opcode_i (walker_opcode_w),
        .walker_head_i       (walker_head_w),
        .walker_current_i    (walker_cur_w),
        .walker_done_i       (walker_done_w),
        .walker_error_id_i   (walker_err_id_w),
        .ctrl_enable_o       (ctrl_enable),
        .ctrl_start_frame_o  (ctrl_start),
        .ctrl_stop_o         (ctrl_stop),
        .ctrl_abort_o        (ctrl_abort),
        .ctrl_clr_status_o   (ctrl_clr),
        .ctrl_flush_cache_o  (ctrl_flush),
        .ctrl_soft_reset_o   (ctrl_sreset),
        .ctrl_arm_irq_o      (ctrl_arm_irq),
        .desc_count_o        (desc_count_w),
        .desc_tail_o         (desc_tail_w),
        .doorbell_commit_o   (dbell_commit),
        .frame_end_pending_o (frame_end_pending_w),
        .frame_end_clear_i   (frame_end_clear),
        .ffe_pulse_o         (ffe_pulse_w),
        .desc_depth_o        (desc_depth_w),
        .desc_circular_o     (desc_circular_w),
        .desc_win_base_o     (desc_win_base_w),
        .sched_cfg_o         (),
        .ring_head_ptr_i     (ring_head_ptr_w),
        .ring_not_empty_i    (ring_not_empty_w),
        .ring_seq_i          (ring_seq_w),
        .ring_frame_id_i     (ring_frame_id_w),
        .ring_head_bytes_i   (ring_head_bytes_w),
        .ring_publish_evt_i  (ring_publish_evt_w),
        .ring_overflow_evt_i (ring_overflow_evt_w),
        .ring_tail_ptr_o     (ring_tail_ptr_w),
        .ring_ack_consume_o  (ring_ack_consume_w),
        .ring_ack_drop_o     (ring_ack_drop_w),
        .ring_ack_retry_o    (ring_ack_retry_w),
        .frame_id_reg_o      (frame_id_w),
        .frame_cfg_o         (),
        .input_base_lo_o     (),
        .input_base_hi_o     (),
        .input_stride_o      (),
        .head_base_lo_o      (head_base_lo_w),
        .head_base_hi_o      (head_base_hi_w),
        .head_stride_o       (),
        .head_format_o       (head_fmt_w),
        .result_max_det_o    (),
        .result_conf_q_o     (),
        .model_id_o          (),
        .graph_crc_o         (),
        .err_events_i        (err_events_w),
        .err_code_i          (err_code_w),
        .err_op_i            (err_op_w),
        .err_desc_id_i       (err_desc_id_w),
        .err_port_i          (err_port_w),
        .error_status_o      (error_status_w),
        .dma_cfg_o           (dma_cfg_w),
        .perf_cycles_o       (),
        .irq_o               (irq_o)
    );

    // ------------------------------------------------------------ --
    // tables (real Block Memory Generator IP instances)
    //   desc port-B: single-reader yield mux, three-way (F6 contract +
    //   P2.2 GEMM engine). gemm_sel_q latches on the wk_greq_w dispatch
    //   pulse (engine desc addr valid from T+1; sel effective T+1 -- the
    //   pulse cycle still passes walker addr, which is idle then) and
    //   clears on the first !port_grant cycle (dispatch window close).
    // ------------------------------------------------------------ --
    always @(posedge s_axi_aclk) begin
        if (rst_hi_w)            gemm_sel_q <= 1'b0;
        else if (wk_greq_w)      gemm_sel_q <= 1'b1;
        else if (!port_grant_w)  gemm_sel_q <= 1'b0;
    end

    wire [11:0] desc_b_addr_w = !port_grant_w ? walker_desc_addr_w :
                                (gemm_sel_q   ? gemm_desc_addr_w
                                              : shell_desc_addr_w);

    yolo_desc_table u_desc_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_desc),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (desc_wr_word),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (desc_rd_word),
        .a_rdata_o (desc_rd_data_w),
        .b_raddr_i (desc_b_addr_w),
        .b_rdata_o (muxed_desc_data_w)
    );

    yolo_buf_table_f7 u_buf_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_buf),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (buf_word),
        .a_rdata_o (buf_rd_data_w),
        .b_raddr_i (shell_buf_addr_w),
        .b_rdata_o (shell_buf_din_w)
    );

    yolo_quant_table_f7 u_quant_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_quant),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (quant_word),
        .a_rdata_o (quant_rd_data_w),
        .b_raddr_i (shell_qt_addr_w),
        .b_rdata_o (shell_qt_din_w)
    );

    yolo_lut_table u_lut_tbl (
        .clk_i     (s_axi_aclk),
        .a_we_i    (wr_lut),
        .a_wstrb_i (wr_strb_w),
        .a_waddr_i (wr_addr_w[11:2]),
        .a_wdata_i (wr_data_w),
        .a_raddr_i (lut_word),
        .a_rdata_o (lut_rd_data_w),
        .b_raddr_i (10'h0),
        .b_rdata_o ()
    );

    // ------------------------------------------------------------ --
    // descriptor walker (F6 V3.0)
    // ------------------------------------------------------------ --
    yolo_desc_walker_f6 u_wk (
        .clk_i               (s_axi_aclk),
        .rst_n               (rst_n_glue_w),
        .soft_reset_i        (ctrl_sreset),
        .enable_i            (ctrl_enable),
        .start_frame_i       (heads_start_accepted_o),
        .stop_i              (ctrl_stop),
        .abort_i             (ctrl_abort),
        .doorbell_commit_i   (dbell_commit),
        .frame_end_pending_i (frame_end_pending_w),
        .frame_end_clear_o   (frame_end_clear),
        .desc_tail_i         (desc_tail_w),
        .desc_count_i        (desc_count_w),
        .desc_depth_i        (desc_depth_w),
        .desc_circular_i     (desc_circular_w),
        .walker_head_o       (walker_head_w),
        .walker_current_o    (walker_cur_w),
        .walker_done_o       (walker_done_w),
        .walker_error_id_o   (walker_err_id_w),
        .cur_opcode_o        (walker_opcode_w),
        .walker_idle_o       (walker_idle_w),
        .walker_running_o    (walker_busy),
        .walker_frame_done_o (walker_frame_done_w),
        .desc_rd_addr_o      (walker_desc_addr_w),
        .desc_rd_data_i      (muxed_desc_data_w),
        .port_grant_o        (port_grant_w),
        .ppu_req_valid_o     (wk_ppureq_w),
        .ppu_desc_idx_o      (wk_ppuidx_w),
        .ppu_busy_i          (sh_busy_w),
        .ppu_desc_done_i     (sh_desc_done_w),
        .ppu_stopped_i       (sh_stopped_w),
        .ppu_ldr_err_i       (sh_ldr_ev_w),
        .ppu_dma_halted_i    (sh_dma_halt_w),
        .gemm_req_valid_o    (wk_greq_w),
        .gemm_desc_idx_o     (wk_gidx_w),
        .gemm_opcode_o       (wk_gop_w),
        .gemm_done_i         (gemm_done_w),
        .gemm_err_i          (gemm_err_w),
        .pub_valid_o         (pub_valid_w),
        .pub_ready_i         (pub_ready_w),
        .pub_bytes_o         (pub_bytes_w),
        .err_evt_desc_o      (walker_err_evt),
        .err_op_o            (walker_err_op_w),
        .err_desc_id_o       (walker_err_desc_w),
        .err_evt_eng_o       (walker_eng_evt),
        // ---- v2.3 PL dispatch face (M10.3 V1.9): PL entry/verdict wiring.
        //      ppu_ldr_code_i consumes the in-island u_shell loader code
        //      (sh_ldr_code_w existed since V1.0, was left unconnected) --
        //      abort-face passthrough per DESIGN section 5 err 0x26 law. ----
        .ppu_start_pl_i      (ppu_start_pl_i),
        .ppp_payload_pl_i    (ppp_payload_pl_i),
        .frame_token_pl_i    (frame_token_pl_i),
        .token_valid_pl_i    (token_valid_pl_i),
        .ppu_ldr_code_i      (sh_ldr_code_w),
        .ppu_done_pl_o       (ppu_done_pl_o),
        .ppp_done_abort_pl_o (ppp_done_abort_pl_o),
        .ppp_done_err_pl_o   (ppp_done_err_pl_o),
        // ---- M10.6 Rung C：commit 门（L29 位图全满律；挂 doorbell
        //      镜像——仅 0x114 队列路径 W_PUB 评测）----
        .commit_gate_i       (segd_commit_ok_w)
    );

    // ---- v2.3 loaded-DESC count export (M10.3 V1.9): slice of the CSR
    //      A_DESC_COUNT register value (u_regf desc_count_o, 128-entry
    //      table fits 7b) -- conv-issuer PPP sanity compares ppp_ds*
    //      against it (E_PPP_DESC 0x22, DESIGN section 3.3-1). ----
    assign ppu_desc_count_pl_o = desc_count_w[6:0];

    // ------------------------------------------------------------ --
    // PPU compute shell (V1.3): DMA master straight out to BD
    // ------------------------------------------------------------ --
    ppu_shell_top u_shell (
        .clk_i           (s_axi_aclk),
        .rst_i           (shell_rst_w),
        .req_i           (wk_ppureq_w),
        .desc_idx_i      (wk_ppuidx_w),
        .head_base_i     (head_base_lo_w),
        .stop_i          (ctrl_stop),
        .abort_i         (ctrl_abort),
        .ffe_i           (ffe_pulse_w),
        .timeout_cfg_i   (dma_timeout_w),
        .rd_outst_cfg_i  (rd_outst_w),
        .wr_outst_cfg_i  (wr_outst_w),
        .desc_addr_o     (shell_desc_addr_w),
        .desc_din_i      (muxed_desc_data_w),
        .buf_addr_o      (shell_buf_addr_w),
        .buf_din_i       (shell_buf_din_w),
        .qt_addr_o       (shell_qt_addr_w),
        .qt_din_i        (shell_qt_din_w),
        .araddr_o        (m_axi_araddr),
        .arlen_o         (m_axi_arlen),
        .arsize_o        (m_axi_arsize),
        .arburst_o       (m_axi_arburst),
        .arvalid_o       (m_axi_arvalid),
        .arready_i       (m_axi_arready),
        .rdata_i         (m_axi_rdata),
        .rresp_i         (m_axi_rresp),
        .rlast_i         (m_axi_rlast),
        .rvalid_i        (m_axi_rvalid),
        .rready_o        (m_axi_rready),
        .awaddr_o        (m_axi_awaddr),
        .awlen_o         (m_axi_awlen),
        .awsize_o        (m_axi_awsize),
        .awburst_o       (m_axi_awburst),
        .awvalid_o       (m_axi_awvalid),
        .awready_i       (m_axi_awready),
        .wdata_o         (m_axi_wdata),
        .wstrb_o         (m_axi_wstrb),
        .wlast_o         (m_axi_wlast),
        .wvalid_o        (m_axi_wvalid),
        .wready_i        (m_axi_wready),
        .bresp_i         (m_axi_bresp),
        .bvalid_i        (m_axi_bvalid),
        .bready_o        (m_axi_bready),
        .busy_o          (sh_busy_w),
        .desc_done_o     (sh_desc_done_w),
        .ring_publish_o  (),   // walker is the sole publisher (F6 proof)
        .done_cause_o    (sh_cause_w),
        .stopped_o       (sh_stopped_w),
        .ldr_err_valid_o (sh_ldr_ev_w),
        .ldr_err_step_o  (sh_ldr_step_w),
        .ldr_err_bit_o   (sh_ldr_bit_w),
        .ldr_err_code_o  (sh_ldr_code_w),
        .dma_err_valid_o (sh_dma_ev_w),
        .dma_err_bit_o   (sh_dma_bit_w),
        .dma_halted_o    (sh_dma_halt_w),
        .eng_busy_o      (sh_eng_busy_w),
        // M10.6 Rung C：seg_done 位图馈源（纯观察脉冲透传）
        .seg_done_pl_o   (sh_seg_done_pl_w),
        .seg_done_idx_o  (sh_seg_done_idx_w),
        .heads_start_pl_o(sh_heads_start_pl_w)
    );

    // ------------------------------------------------------------ --
    // M10.6 Rung C：seg_done 完成位图 tracker（SPEC §2 提案 (a) 案岛侧
    // 6b 机构 + L29 律）。帧边界=CTRL start_frame（0x114 doorbell 路径，
    // 与 walker 队列指针复位同事件源）；复位面同 walker/regfile（glue
    // 低有效）。commit_ok 挂 walker 门（挂 doorbell 镜像）；bitmap 经
    // 下方 rd mux 的 A_SEG_DONE(0x074) 拦截面呈 PS（RO：regfile 写
    // 解码 default 忽略，天然写保护）。
    // ------------------------------------------------------------ --
    ppu_seg_done u_segd (
        .clk_i            (s_axi_aclk),
        .rst_n_i          (rst_n_glue_w),
        .soft_reset_i     (ctrl_sreset),
        .frame_start_i    (heads_start_accepted_o),
        .heads_start_pl_i (sh_heads_start_pl_w),
        .seg_done_pl_i    (sh_seg_done_pl_w),
        .seg_done_idx_i   (sh_seg_done_idx_w),
        .bitmap_o         (segd_bitmap_w),
        .commit_ok_o      (segd_commit_ok_w)
    );

    // ------------------------------------------------------------ --
    // GEMM backend (P2.2): ppu_gemm_engine V1.3 + own second DMA master.
    //   恢复正典：engine rcvr_o（E_ABORT/E_ERR 族，excl. E_ABORTD 排空
    //   态）→ u_gdma.abort_i 在途受控排空；rcvr_o 后沿 → gwash_cnt 16 拍
    //   wash 复位（ppu_dma_master 的 err_r/abort_q 仅 rst_i 可清——P2.1
    //   单元门不涉；wash 后引擎 req-valid 保持纪律天然兼容：E_PRMREQ/
    //   E_LUTREQ/E_SEGREQ 持 valid 等 ready，冲刷窗内 ready=0 仅延迟）。
    // ------------------------------------------------------------ --
    always @(posedge s_axi_aclk) begin
        if (rst_hi_w) begin
            gwash_cnt <= 5'd0; g_rcvr_q <= 1'b0;
        end else begin
            g_rcvr_q <= g_rcvr_w;
            if (g_rcvr_q && !g_rcvr_w)   gwash_cnt <= 5'd16; // 后沿臂
            else if (gwash_cnt != 5'd0)  gwash_cnt <= gwash_cnt - 5'd1;
        end
    end
    wire gwash_rst_w = rst_hi_w || (gwash_cnt != 5'd0);

    // ---- shell 软复位 wash（V1.7，用户指令 2026-09-29 "1+2 合并改"案 2）----
    // ctrl_sreset 脉冲臂 16 拍 u_shell 复位：清除 ppu_dma_master err_r/
    // halted 与 shell arbiter err_q/abort_q 粘着（"halt 至复位"头注局限
    // ——M3 实证软复位后重启帧=派发进错误保持 shell → 新引擎错 → W_ERR
    // 死锁，此前仅硬复位可清；V1.6 头注"shell DMA 同局限记录在案"就此
    // 闭合）。与 gwash 同构的末位恢复手段语义：正典错误后软复位流 shell
    // 必为 idle 或 halted（错误路径已受控排干）→ wash 零在途冲突。walker/
    // ring/regfile 脉冲扇出不变（环续行律/B5b 面零扰动）；软复位后 >16 拍
    // 重启帧为既有约束（TB:1283 板驱恢复纪律：cfg_csr_default ≫16 拍）。
    always @(posedge s_axi_aclk) begin
        if (rst_hi_w)              swash_cnt <= 5'd0;
        else if (ctrl_sreset)      swash_cnt <= 5'd16;    // 软复位臂
        else if (swash_cnt != 5'd0) swash_cnt <= swash_cnt - 5'd1;
    end
    assign shell_rst_w = rst_hi_w || (swash_cnt != 5'd0);

    // wash 窗内屏蔽 u_gdma 请求就绪：复位期 ready 组合读复位值为 1，
    // 引擎持 valid 等 ready（E_PRMREQ/E_LUTREQ/E_SEGREQ 纪律）会被假
    // 握手吞请求（DMA 复位支不采样受理）。拍面输出口复位期恒 0 无此险。
    wire gd_req_rdy_g_w  = gd_req_ready_w  && (gwash_cnt == 5'd0);
    wire gdw_req_rdy_g_w = gdw_req_ready_w && (gwash_cnt == 5'd0);

    ppu_dma_master u_gdma (
        .clk_i           (s_axi_aclk),
        .rst_i           (gwash_rst_w),
        .abort_i         (g_rcvr_w),
        .timeout_cfg_i   (dma_timeout_w),
        .rd_outst_cfg_i  (rd_outst_w),
        .wr_outst_cfg_i  (wr_outst_w),
        // 用户面：引擎（P2.1 单元门口径逐名直连）
        .rd_req_valid_i  (gd_req_valid_w),
        .rd_req_ready_o  (gd_req_ready_w),
        .rd_addr_i       (gd_req_addr_w),
        .rd_len_i        (gd_req_len_w),
        .rd_beat_valid_o (gd_beat_valid_w),
        .rd_beat_ready_i (gd_beat_ready_w),
        .rd_beat_data_o  (gd_beat_data_w),
        .rd_done_o       (gd_rd_done_w),
        .wr_req_valid_i  (gdw_req_valid_w),
        .wr_req_ready_o  (gdw_req_ready_w),
        .wr_addr_i       (gdw_req_addr_w),
        .wr_len_i        (gdw_req_len_w),
        .wr_beat_valid_i (gdw_beat_valid_w),
        .wr_beat_ready_o (gdw_beat_ready_w),
        .wr_beat_data_i  (gdw_beat_data_w),
        .wr_beat_strb_i  (gdw_beat_strb_w),
        .wr_done_o       (gd_wr_done_w),
        .err_pulse_o     (gdma_err_pulse_w),
        .err_bit_o       (gdma_err_bit_w),
        .err_code_o      (gdma_err_code_w),
        .err_beat_o      (),
        .halted_o        (gdma_halt_w),
        // AXI4 64b → m1_axi（BD：互连第二 SI，共享 S_AXI_HP0 同段）
        .araddr_o        (m1_axi_araddr),
        .arlen_o         (m1_axi_arlen),
        .arsize_o        (m1_axi_arsize),
        .arburst_o       (m1_axi_arburst),
        .arvalid_o       (m1_axi_arvalid),
        .arready_i       (m1_axi_arready),
        .rdata_i         (m1_axi_rdata),
        .rresp_i         (m1_axi_rresp),
        .rlast_i         (m1_axi_rlast),
        .rvalid_i        (m1_axi_rvalid),
        .rready_o        (m1_axi_rready),
        .awaddr_o        (m1_axi_awaddr),
        .awlen_o         (m1_axi_awlen),
        .awsize_o        (m1_axi_awsize),
        .awburst_o       (m1_axi_awburst),
        .awvalid_o       (m1_axi_awvalid),
        .awready_i       (m1_axi_awready),
        .wdata_o         (m1_axi_wdata),
        .wstrb_o         (m1_axi_wstrb),
        .wlast_o         (m1_axi_wlast),
        .wvalid_o        (m1_axi_wvalid),
        .wready_i        (m1_axi_wready),
        .bresp_i         (m1_axi_bresp),
        .bvalid_i        (m1_axi_bvalid),
        .bready_o        (m1_axi_bready)
    );

    // ------------------------------------------------------------ --
    // GEMM 后端（V1.8/M5-V2.4：stub 化）
    //
    // u_gemm 换 ppu_gemm_stub_f7——req 单拍脉冲启动，GEMM_DELAY 拍后回
    // err（GEMM_ERR_ALWAYS=1，不伪装成功）。M5 图算子域无 GEMM 描述符
    // （conv 走 BD 原路径 u_yolo_gemm），err 路径不可达；err_code 恒
    // 0xE0（stub 错误域），busy/rcvr/desc_addr/DMA 用户面 tie-off 全 0
    // → u_gdma 零流量、m1_axi 空闲、三路让渡 mux 引擎侧恒指向字 0。
    // 真引擎 F7b 回插：删 stub 例化与下方 tie-off 块，按 V1.6 版本库
    // 恢复 ppu_gemm_engine 全端口例化（台账 rtl_ledger_m5.json）。
    // ------------------------------------------------------------ --
    ppu_gemm_stub_f7 #(
        .GEMM_DELAY     (8),
        .GEMM_ERR_ALWAYS(1)
    ) u_gemm (
        .clk_i           (s_axi_aclk),
        .rst_i           (rst_hi_w),
        .req_valid_i     (wk_greq_w),
        .desc_idx_i      (wk_gidx_w),
        .opcode_i        (wk_gop_w),
        .done_o          (gemm_done_w),
        .err_o           (gemm_err_w),
        .abort_i         (ctrl_abort)
    );

    // 原 u_gemm 独占输出 tie-off（V1.8；宽度对齐声明区 gd_* [31:0]/[23:0]/
    // [63:0]/[7:0]、gemm_ecode_w [7:0]、gemm_desc_addr_w [11:0]）
    assign gemm_ecode_w     = 8'hE0;    // 引擎错码（err 路径不可达，观察口）
    assign gemm_busy_w      = 1'b0;
    assign g_rcvr_w         = 1'b0;     // gwash 发生器恒不触发（树保留）
    assign gemm_desc_addr_w = 12'h0;    // desc 口 B 三路 mux 引擎侧
    assign gd_req_valid_w   = 1'b0;     // u_gdma 读用户面（零流量）
    assign gd_req_addr_w    = 32'h0;
    assign gd_req_len_w     = 24'h0;
    assign gd_beat_ready_w  = 1'b0;
    assign gdw_req_valid_w  = 1'b0;     // u_gdma 写用户面（零流量）
    assign gdw_req_addr_w   = 32'h0;
    assign gdw_req_len_w    = 24'h0;
    assign gdw_beat_valid_w = 1'b0;
    assign gdw_beat_data_w  = 64'h0;
    assign gdw_beat_strb_w  = 8'h0;

    // ------------------------------------------------------------ --
    // result ring (V2.0, sole publisher = walker)
    // ------------------------------------------------------------ --
    yolo_result_ring u_ring (
        .clk_i               (s_axi_aclk),
        .rst_n               (rst_n_glue_w),
        .soft_reset_i        (ctrl_sreset),
        .pub_valid_i         (pub_valid_w),
        .pub_ready_o         (pub_ready_w),
        .pub_frame_id_i      (frame_id_w),
        .pub_head_base_i     ({head_base_hi_w, head_base_lo_w}),
        .pub_head_bytes_i    (pub_bytes_w),
        .pub_quant_profile_i (head_fmt_w[15:8]),
        .pub_stride_mask_i   (head_fmt_w[23:16]),
        .pub_done_evt_o      (ring_publish_evt_w),
        .pub_overflow_evt_o  (ring_overflow_evt_w),
        .tail_ptr_i          (ring_tail_ptr_w),
        .ack_consume_i       (ring_ack_consume_w),
        .ack_drop_i          (ring_ack_drop_w),
        .ack_err_evt_o       (ring_ack_err_evt),
        .head_ptr_o          (ring_head_ptr_w),
        .not_empty_o         (ring_not_empty_w),
        .seq_o               (ring_seq_w),
        .last_frame_id_o     (ring_frame_id_w),
        .last_head_bytes_o   (ring_head_bytes_w),
        .win_addr_i          (ring_word),
        .win_data_o          (ring_rd_data_w)
    );

    // ------------------------------------------------------------ --
    // error event aggregation (sticky bits + info priority mux)
    //   bit10 (F7) = engine error: PPU ldr/dma via walker, GEMM stub err
    // ------------------------------------------------------------ --
    assign err_events_w[0]  = err_align_evt || evt_region_bad;
    assign err_events_w[1]  = 1'b0;
    assign err_events_w[2]  = 1'b0;
    assign err_events_w[3]  = walker_err_evt || evt_desc_guard;
    assign err_events_w[4]  = evt_buf_guard;
    assign err_events_w[5]  = evt_quant_guard;
    assign err_events_w[6]  = evt_lut_guard;
    assign err_events_w[7]  = 1'b0;
    assign err_events_w[8]  = ring_overflow_evt_w;
    assign err_events_w[9]  = evt_ring_ro || ring_ack_err_evt;
    assign err_events_w[10] = walker_eng_evt;

    always @(*) begin
        if (walker_eng_evt) begin
            err_code_w    = E_CODE_ENG_ERR;
            err_op_w      = walker_err_op_w;
            err_desc_id_w = walker_err_desc_w;
            err_port_w    = 4'd5;               // engine port
        end else if (walker_err_evt) begin
            err_code_w    = E_CODE_DESC_INVALID;
            err_op_w      = walker_err_op_w;
            err_desc_id_w = walker_err_desc_w;
            err_port_w    = 4'd1;
        end else if (evt_lut_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd4;
        end else if (evt_quant_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd3;
        end else if (evt_buf_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd2;
        end else if (evt_desc_guard) begin
            err_code_w    = E_CODE_TABLE_RUN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd1;
        end else if (ring_overflow_evt_w) begin
            err_code_w    = E_CODE_RING_OVF;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (evt_ring_ro) begin
            err_code_w    = E_CODE_RING_RO;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (ring_ack_err_evt) begin
            err_code_w    = E_CODE_ACK_EMPTY;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd6;
        end else if (evt_region_bad) begin
            err_code_w    = E_CODE_ADDR_REGION;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd15;
        end else if (err_align_evt) begin
            err_code_w    = E_CODE_ADDR_ALIGN;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 4'd15;
        end else begin
            err_code_w    = 8'h0;
            err_op_w      = 8'h0;
            err_desc_id_w = 8'h0;
            err_port_w    = 8'h0;
        end
    end

    // ------------------------------------------------------------ --
    // read data mux + read ack alignment (TABLE_RD_LATENCY cycles)
    //   DEBUG 区 0x7000 = GEMM 现场字（纯组合快照，无状态）：
    //     [7:0]  引擎 err_code_o（保持到下个 req——即"最近一次错误"）
    //     [8]    u_gdma halted   [9]  u_gdma err_bit 非零
    //     [10]   wash 复位进行中  [11] gemm_sel_q（desc 口 B 引擎持锁）
    //     [12]   引擎 rcvr_o      [13] 引擎 busy_o
    //     [23:16] gwash_cnt       0x7004+ 保留 0
    // ------------------------------------------------------------ --
    wire [31:0] dbg_gemm_word0_w =
        {17'd0, gwash_cnt, gemm_busy_w, g_rcvr_w, gemm_sel_q,
         (gwash_cnt != 5'd0), (|gdma_err_bit_w), gdma_halt_w, gemm_ecode_w};

    reg [31:0] rd_mux_q;
    always @(*) begin
        case (rd_region)
            // M10.6 Rung C：A_SEG_DONE(0x074) 在 regfile 读 mux 拦截——
            // CSR 线 .sv 冻结文件零触碰（regfile 对本址读返回 0、写
            // 解码 default 忽略，天然 RW 保护与 RO 语义）；rd_addr_w
            // 在 ack 拍保持有效为既有全区域合同（desc/buf 窗同款）。
            RGN_REGF  : rd_mux_q = (rd_addr_w == A_SEG_DONE)
                                    ? {26'h0, segd_bitmap_w}
                                    : regf_rd_data_w;
            RGN_DESC  : rd_mux_q = desc_rd_data_w;
            RGN_BUF   : rd_mux_q = buf_rd_data_w;
            RGN_QUANT : rd_mux_q = quant_rd_data_w;
            RGN_LUT   : rd_mux_q = lut_rd_data_w;
            RGN_RING  : rd_mux_q = ring_rd_data_w;
            RGN_DEBUG : rd_mux_q = (rd_addr_w[11:2] == 10'd0)
                                    ? dbg_gemm_word0_w : 32'h0;
            default   : rd_mux_q = 32'h0;   // unmapped
        endcase
    end
    assign rd_data_w = rd_mux_q;

    reg [TABLE_RD_LATENCY:1] rd_ack_pipe;
    integer j;
    always @(posedge s_axi_aclk) begin
        if (!rst_n_glue_w) begin
            rd_ack_pipe <= {TABLE_RD_LATENCY{1'b0}};
        end else begin
            rd_ack_pipe[1] <= rd_valid_w;
            for (j = 2; j <= TABLE_RD_LATENCY; j = j + 1)
                rd_ack_pipe[j] <= rd_ack_pipe[j-1];
        end
    end
    assign rd_ack_w = rd_ack_pipe[TABLE_RD_LATENCY];

endmodule
