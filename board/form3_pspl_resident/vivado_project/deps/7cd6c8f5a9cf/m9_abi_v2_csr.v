/************************************************************************
 * File Name       : m9_abi_v2_csr.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_abi_v2_csr
 * Description     :
 *   M9.5b ABI v2 CSR slave (02_m9_issuer_spec.md section 7 m9_intra_top
 *   bullet: CAP0/PLAN_BASE/ARENA_BASE/W_BASE/DOORBELL/progress RO).
 *   AXI4-Lite 32b from-face; the V2.5 wrapper instantiates it and it
 *   owns every PS-visible register.  Frame law (M9.5 gate):
 *
 *     setup : PS writes CFG and base registers + loads the plan BRAM
 *     frame : PS writes DOORBELL once -> start pulse -> zero PS
 *             until done (帧中零 PS 证明)
 *
 *   Register map (word offsets):
 *     0x00 CAP0      RO  32'h4D39_0240 ("M9" v2.4 BCD, M11a page sched)
 *     0x04 PLAN_BASE RW  plan blob DDR base (台账 reference; the blob
 *                          body streams through the plan BRAM faces)
 *     0x08 ARENA_BASE RW -> cfg_xbase (x window HP0 read base)
 *     0x0C W_BASE    RW  -> cfg_wbase (w feeder HP3 read base)
 *     0x10 CFG0  RW  nb[9:0] rc[5:0]@10 ns[3:0]@16 nseg[1:0]@20 nconv[3:0]@24
 *     0x14 CFG1  RW  ic[15:0] h[15:0]@16
 *     0x18 CFG2  RW  w[15:0] kh[3:0]@16 kw[3:0]@20 sh[3:0]@24 sw[3:0]@28
 *     0x1C CFG3  RW  ph[3:0] pw[3:0]@4 first@8 law_fetch@9 overlap@10
 *                    oc[7:0]@16
 *     0x20 CFG4  RW  s0_k[10:0] s0_jc[7:0]@11 s0_g[1:0]@19
 *     0x24 CFG5  RW  stride
 *     0x28 CFG6  RW  obuf
 *     0x2C CFG7  RW  slab
 *     0x30 CFG8  RW  rc_stride
 *     0x34 CFG9  RW  oc_stride
 *     0x38 DOORBELL  WO  any write -> 1-cycle start pulse (reads 0)
 *     0x3C STATUS    RO  busy@0 done@1 err[7:0]@8
 *     0x40 PROGRESS  RO  progress_blk[11:0]
 *     0x44 CNT0      RO  cnt_beats[31:0] (widened from 19b, V1.1 below)
 *     0x48 CNT1      RO  cnt_csr_w[15:0] cnt_y_blocks[9:0]@16
 *     0x4C CNT2      RO  cnt_y_bytes[19:0]
 *     0x50 CNT3      RO  cnt_stall[31:0]
 *     0x54 TICK      RO  tick_cnt[31:0] (P2 clock probe)
 *     0x58 CHAIN_MASK RW cfg_chain_mask[15:0] (ABI v2.1 layer_chain;
 *                          bit i=1 -> conv i X from HBUF; sampled at the
 *                          doorbell-start edge by m9_hbuf_ctrl; bit0 /
 *                          multi-bit / non-walk rejected -> E_CHAIN_MASK=10)
 *     0x5C CHAIN_CNT  RO cnt_chain_bytes[31:0] (HBUF delivered bytes;
 *                          cleared at doorbell start, M10.1 ledger)
 *     0xCC CAP1      RO  32'h4D39_1000 | NSLOT (ABI v2.2 phase 2b edge/
 *                          slot-table capability; NSLOT=8 -> 0x4D39_1008)
 *     0xD0 CHAIN_NEDGE RW cfg_nedge[3:0] (edge count; 0 = v1 CHAIN_MASK
 *                          mode; sampled at doorbell start)
 *     0xD4 CHAIN_EDGE_IDX RW edge table cursor [3:0] (0..NEDGE-1)
 *     0xD8 CHAIN_EDGE_NODE RW {edge_prod,edge_node}[edge_idx] <=
 *                          wdata[15:0]  (v2.4: byte-lane write into the
 *                          shared EDGE table RAM word edge_idx, low half;
 *                          windowed face sees it at page-0 base-0 window =
 *                          legacy flat position.  2d semantics unchanged:
 *                          wdata[7:0]=consumer conv idx;
 *                          wdata[15:8]=producer field, 0 = adjacent-walk
 *                          fallback prod=node-1 (v1/2b superset face),
 *                          else prod = field-1 explicit (spec §5.1 branch:
 *                          one producer serving multiple consumers from a
 *                          shared read-only slot).  CAP1 UNCHANGED
 *                          0x4D39_1008 -- old drivers write [15:8]=0 ->
 *                          byte-identical 2b behaviour.)
 *     0xDC CHAIN_EDGE_WIN  RW edge_win[edge_idx] <= wdata[15:0]
 *                          (v2.4: byte-lane write into the shared EDGE
 *                          table RAM word edge_idx, high half.
 *                          window_size bytes; compiler boxes all chained
 *                          producer slots into one 32KB page, spec §3.2;
 *                          2d law: edges sharing a producer MUST carry the
 *                          identical window -- one slot, one capture)
 *     ---- ABI v2.3 (M10.2 m8, DESIGN_m8_v23.md §1) ----
 *     0xE9 TBL_CURSOR RW  {21'd0, tbl_sel[1:0]@10, tbl_cur[9:0]} direct
 *                          set: table-select latch + per-table cursor
 *                          (v2.3 PPP cursor generalized, superset face:
 *                          v2.3 drivers write sel=0 cursor[2:0] -> PPP
 *                          table, byte-compatible at words 0..7)
 *     0xEA TBL_DATA   RW  table[tbl_sel][cur] <= wdata, cursor auto-inc
 *                          (PPP/EDGE mod 256, JOIN mod 640, PAGE mod 8)
 *     0xEB LAYOUT_ID  RW  layout[31:0] (48b page-local vector low half;
 *                          [31:30] = conv10 field[1:2] = 0 in legacy 10c)
 *     0xED CAP3       RO  32'h4D39_0810 ([7:0]=8 PPP seg capacity,
 *                          [15:8]=0x10 layout conv/page, [23:16]=NPAGE=8)
 *     ---- G3 (M10.2 OVF 补盲, RUNBOOK_5d §11) ----
 *     0xE2 OVF_STAT  RO {15'd0, ovf_trig, ovf_tot[15:0]} / WO = re-arm
 *     0xE6 OVF_CUR   RW  ring read cursor [3:0] (direct set, PPP law)
 *     0xEF OVF_DATA  RO  ovf_ring[ovf_cur] (v2.4: relocated from 0xEE --
 *                          0xEE now carries PAGE_CTRL; 0xEF v2.4-expansion
 *                          reserve consumed, documented deviation)
 *     ---- ABI v2.4 (M11a page scheduling, SPEC_m11a §4) ----
 *     0xEE PAGE_CTRL RW  {12'd0, auto_adv@19, npages[2:0]@16,
 *                          layout_hi[15:0]}  -- 0xEB+0xEE 拼布 forming the
 *                          48b page-local layout vector; npages=1 =
 *                          degenerate legacy (page 0 window == flat)
 *     0x38 DOORBELL    WO  v2.3: wdata[7:0] = frame generation, latched
 *                          at the start pulse edge (frame_gen level +
 *                          frame_token pulse to the walker island)
 *
 *   All config writes land only in registers -- the engine samples them
 *   at the doorbell start edge (issuer start law), so mid-frame PS
 *   writes cannot disturb a running frame.
 *
 *   Handshake law (xsim native canon): B/R hold until accepted, no
 *   default clear; ready faces combinational on the outstanding state,
 *   so a slow PS master can never lose a beat.
 *
 *   Proven-core discipline: sibling module; changes no proven core.
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 *   - V1.1 (2026-10-13) : CNT0 (0x44) readback widened to the full 32-bit
 *     cnt_beats (m9_intra_top V1.6); small-count consumers unaffected
 *     (value identical, zero-extension was implicit).
 *   - V1.2 (2026-10-14) : ABI v2.1 layer_chain (M10.1): CHAIN_MASK 0x58
 *     RW + CHAIN_CNT 0x5C RO; CAP0 0x4D39_0200 -> 0x4D39_0210 (v2.1 BCD)
 *     -> 0x4D39_0220 (M10.1-v2 phase 2a, 2026-10-14: ch_stride decoupling
 *     silicon, new-silicon-new-criterion law).
 *     0x04-0x54 semantics byte-identical.
 *   - V1.3 (2026-10-14) : ABI v2.2 phase 2b edge table: CAP1 0xCC RO,
 *     CHAIN_NEDGE 0xD0 RW, CHAIN_EDGE_IDX 0xD4 RW (table cursor),
 *     CHAIN_EDGE_NODE 0xD8 / CHAIN_EDGE_WIN 0xDC index-indirect RW with
 *     readback.  tr_we aperture excludes 0xCC-0xDC; read mux gets
 *     explicit cases so the new window is not routed into the trace
 *     aperture by the >=0x60 default.  0x00-0x5C semantics identical.
 *   - V2.3 (2026-10-16) : M10.2 m8 ABI upgrade (DESIGN_m8_v23.md, five
 *     rulings CLOSED b8302bd1).  PPP segment table 8x1W (0xE9/0xEA
 *     cursor+data pair), LAYOUT_ID 10x3b (0xEB), CAP3 0xED RO
 *     0x4D39_0A08, CAP0 -> 0x4D39_0230.  DOORBELL wdata[7:0] = frame
 *     generation (frame_gen latch + frame_token pulse).  tr_we aperture:
 *     the whole (0xE8,0xF0) band is carved out (indirect word tables
 *     need clean write AND read sides; 0xE9-0xEF writes no longer fan
 *     the trace ring -- trace anchors go explicit events, G2 law).
 *     New state lives ONLY in the ppp/layout always block below
 *     (multi-driver single-block law, cfg_chain_rel/dbg_cur precedent).
 *     v1 path structurally identical with an empty table (first word
 *     opcode=0x00 EMPTY at reset).
 *   - V2.3+G3 (2026-10-16) : OVF AW-capture window 0xE2/0xE6/0xEE (16-deep
 *     rolling m2-AW-address ring, E_CHAIN_OVF rising-edge trigger latch,
 *     ring keeps rolling post-trigger; see RUNBOOK_5d §11).  Explicit
 *     read cases close the >=0x60 trace-default leak that used to expose
 *     ring-payload garbage at these orphan addresses.  Zero datapath
 *     fanout (observation-only law).
 *   - V2.4 (2026-10-18) : M11a graph-level page scheduling (SPEC_m11a
 *     v1.0 §4, CAPACITY_LEDGER_PLAN §4.6/§6.1).  CAP0 -> 0x4D39_0240,
 *     CAP3 -> 0x4D39_0810 (8 PPP / 0x10 layout conv-page / NPAGE=8).
 *     0xE9/0xEA generalized from the PPP couple to a four-table load
 *     port (tbl_sel 0=PPP 1=EDGE 2=JOIN 3=PAGE; per-table cursors).
 *     The PPP / EDGE / JOIN / PAGE storage moves into the new
 *     m9_page_tables module (instantiated here; windowed read face keyed
 *     by the issuer page register pg_raddr -- frozen-wrapper floats are
 *     z-guarded to page 0, whose base-0 window reconstructs the legacy
 *     flat tables bit-exactly at reset and for legacy loads, T7 basis).
 *     cfg_edge_node/prod/win + cfg_join_tab + cfg_ppp_tab keep their
 *     widths (zero-drift through the frozen wrappers); cfg_layout_id
 *     widens 30b -> 48b (16 page-local convs x 3b; truncates to legacy
 *     at the frozen wrapper, r10 width-propagation precedent).
 *     0xEB = layout[31:0]; 0xEE = PAGE_CTRL 拼布 {12'd0, auto_adv,
 *     npages[2:0], layout_hi[15:0]}; OVF_DATA relocates 0xEE -> 0xEF
 *     (0xEF v2.4-expansion reserve consumed -- documented deviation).
 *     Legacy 0xD8/0xDC/0xF0/0xF4 keep working as byte-lane/full writes
 *     into the SAME RAMs (CAP0 already rejects pre-v2.4 drivers; the
 *     superset routing is belt-and-suspenders).  tr_we aperture
 *     unchanged (0xEF stays outside the trace-carved band on writes;
 *     its new read case is explicit like 0xE0-0xE8).
 *   - V2.5 (2026-10-21) : C3 r12 A-plan (A1_bram_plan.md v2.1, page_tables
 *     BRAM IP 化配套 CSR 三改，落地条件 2/5 + 读回握手）:
 *     (1) DOORBELL start 门控 win_rdy——窗未就绪时挂起 pending 锁存 +
 *         就绪重发 1 拍 start（禁与门蒸发律；双门铃后者覆盖 pend_gen）;
 *         frame_gen/frame_token 随迁重发拍。armed 粘位置位于门铃、
 *         done 上升沿清除（帧间装载合法）。
 *     (2) 表读回 0xF4/0xEA 改 req/gnt 握手（page_tables gnt+data 同拍、
 *         req 保持至 gnt 契约）：AR 受理进 wait 态锁存 sel/addr、hold
 *         RVALID 至 gnt 拍捕获；s_arready 增 ~tbl_rd_wait 门。读延迟
 *         +2~3 拍，PS 无感知（AXI 自流）。
 *     (3) sim 守卫：armed 期任何表写 = load/run 分离违约 $fatal
 *         （与 page_tables 侧守卫互补不重叠）。
 *     pg_pref 真线（r12 B 裁定）：input 口接 issuer 输出，预取提前一拍
 *         发起读（page_tables v2.3 pg_pref_d 捕获窗）；无 tie、无门。
 *   - V2.6 (2026-10-25) : 装载 FSM 呈批件 V2 实施（用户已批准，
 *     submission 2026-10-25_loadfsm_design_prep_run01，sha f533e279…）：
 *     (1) s_awaddr/s_araddr 端口 8→16bit（shim 切片 [7:0]→[15:0]；
 *         高位为零时 0x00-0xFF 既有译码逐位不变，G3）；
 *     (2) 新字对齐装载口 0x100-0x118 七寄存器（LD_DATA/LD_SEL/
 *         LD_ADDR/LD_LEN/LD_STAT/LD_ERR/LD_CNT），WSTRB=1111 显式
 *         门控（G1；窄写=OKAY+粘滞 err_code=1；LD_ERR 写清除豁免——
 *         唯一豁免面 C4③）；
 *     (3) 新增 m9_ldload_fsm 例化（五态：IDLE/LATCH/COMMIT/WAIT/ERR；
 *         S_WAIT 等 page_tables rmw_idle 新输出端口反压，C1 tap-off）；
 *         写表经 OR 合流复用既有 tbl_* 四口（§2.4 合流律）；
 *     (4) tr_we 与读 default 增 aw_addr_q/s_araddr[15:8]==0 高位零门
 *         = §1.5 C2 影子命令集拆除的实现面（0x138 门铃别名消失、
 *         0x160-0x1CB trace 环别名消失——有意行为变更，已声明）；
 *     (5) armed 期 LD_DATA 提交硬件硬门 err_code=3（§2.5 RUNTIME_
 *         WRITE = 本文件 sim $fatal L581-586 的硬件化）；
 *     (6) LD_ERR 独立暴露（C3 选项 b）：装载 err 只进 0x114 粘滞
 *         寄存器，零触 0x3C STATUS err[7:0]。
 *     0x00-0xFF 全部既有 case 臂零扰动（含不可达 E9/EA/EB/EE——保留
 *     sim/后向兼容；扩位后经 16bit 端口以字节地址 0xE9/0xEA 可达，
 *     为 16bit 切片下的固有可达性，PS 字对齐写行为不变）。
 *   - V2.7 (2026-10-28) by Stage-B control lane : Atomic doorbell request/
 *     accept split, normal/rejected/recovery classification, full 0xDE
 *     binding fields, and exact 16-bit progress readback.
 *   - V2.8-Closure (2026-10-28) by V25/PPU closure lane : Separate recovery
 *     from normal/rejected class, preserve recovery-rejected acceptance, and
 *     report LEGACY/AUTO/MANUAL mode independently of transaction class.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_abi_v2_csr (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- AXI4-Lite slave (PS GP face) ----
    // V2.6: 8→16bit（装载 FSM 呈批件 §2.4②；shim 送核切片同步拓宽）
    input  wire [15:0] s_awaddr      ,
    input  wire [2:0]  s_awprot      ,
    input  wire        s_awvalid     ,
    output wire        s_awready     ,
    input  wire [31:0] s_wdata       ,
    input  wire [3:0]  s_wstrb       ,
    input  wire        s_wvalid      ,
    output wire        s_wready      ,
    output reg  [1:0]  s_bresp       ,
    output reg         s_bvalid      ,
    input  wire        s_bready      ,
    input  wire [15:0] s_araddr      ,
    input  wire [2:0]  s_arprot      ,
    input  wire        s_arvalid     ,
    output wire        s_arready     ,
    output reg  [31:0] s_rdata       ,
    output reg  [1:0]  s_rresp       ,
    output reg         s_rvalid      ,
    input  wire        s_rready      ,
    // ---- engine status/counters (RO face) ----
    input  wire        busy          ,
    input  wire        done          ,
    input  wire [7:0]  err           ,
    input  wire [15:0] progress_blk  ,
    input  wire [31:0] cnt_beats     ,
    input  wire [15:0] cnt_csr_w     ,
    input  wire [19:0] cnt_y_bytes   ,
    input  wire [9:0]  cnt_y_blocks  ,
    input  wire [31:0] cnt_stall     ,
    input  wire [31:0] cnt_chain_bytes,  // M10.1: HBUF delivered bytes
    // ---- 2e credit-gated release telemetry (SPEC §7.4) ----
    input  wire [31:0] s2l_cnt        ,  // CHAIN_S2L_CNT (issuer)
    input  wire [31:0] skew_max       ,  // CHAIN_SKEW_MAX (hbuf)
    // ---- r7 debug aperture: hbuf slot-FSM/capture/serve telemetry ----
    input  wire [511:0] hb_dbg        ,  // 8 words, cursor-selected
    output reg  [3:0]  dbg_cur        ,  // CSR 0xF8 (write=select/read=rb)
    // ---- G3 (M10.2): OVF AW-capture tap (m2 write master; observe-only,
    // zero fanout into any engine logic -- RUNBOOK_5d §11 补盲 CSR) ----
    input  wire        mon_awvalid   ,
    input  wire        mon_awready   ,
    input  wire [31:0] mon_awaddr    ,
    // ---- config outputs to the wrapper (sampled at start) ----
    output reg  [31:0] plan_base     ,
    output reg  [31:0] arena_base    ,
    output reg  [31:0] w_base        ,
    output reg  [9:0]  cfg_nb        ,
    output reg  [5:0]  cfg_rc        ,
    output reg  [3:0]  cfg_ns        ,
    output reg  [1:0]  cfg_nseg      ,
    output reg  [4:0]  cfg_nconv     ,
    output reg  [15:0] cfg_ic        ,
    output reg  [15:0] cfg_h         ,
    output reg  [15:0] cfg_w         ,
    output reg  [3:0]  cfg_kh        ,
    output reg  [3:0]  cfg_kw        ,
    output reg  [3:0]  cfg_sh        ,
    output reg  [3:0]  cfg_sw        ,
    output reg  [3:0]  cfg_ph        ,
    output reg  [3:0]  cfg_pw        ,
    output reg         cfg_first     ,
    output reg         cfg_law_fetch ,
    output reg         cfg_overlap   ,
    output reg  [7:0]  cfg_oc        ,
    output reg  [10:0] cfg_s0_k      ,
    output reg  [7:0]  cfg_s0_jc     ,
    output reg  [1:0]  cfg_s0_g      ,
    output reg  [31:0] cfg_stride    ,
    output reg  [31:0] cfg_obuf      ,
    output reg  [31:0] cfg_slab      ,
    output reg  [31:0] cfg_rc_stride ,
    output reg  [31:0] cfg_oc_stride ,
    output reg  [15:0] cfg_chain_mask,  // M10.1 ABI v2.1 (CSR 0x58)
    // ---- M10.1-v2 phase 2b edge table (ABI v2.2 0xD0-0xDC) ----
    output reg  [3:0]  cfg_nedge     ,  // CHAIN_NEDGE (0 = v1 mask mode)
    output wire [63:0] cfg_edge_node ,  // 8 x consumer_idx[7:0] (v2.4:
                                        //   windowed face from m9_page_tables)
    output wire [63:0] cfg_edge_prod ,  // 2d: 8 x producer field[7:0]
    output wire [127:0] cfg_edge_win ,  // 8 x window_size[15:0]
    output wire [639:0] cfg_join_tab ,   // 5b: 20-word join-region table
                                        //   (v2.4 windowed face)
    // ---- M11a page scheduling (ABI v2.4, SPEC_m11a §4) ----
    input  wire [2:0]  pg_raddr      ,  // issuer page register (window
                                        //   select); frozen wrappers float
                                        //   it -> z-guard to page 0 below
    output wire [2:0]  cfg_npages    ,  // PAGE_CTRL npages (1..8; 0/1 =
                                        //   degenerate legacy, zero drift)
    output wire        cfg_pgauto    ,  // PAGE_CTRL auto_adv (paged frame
                                        //   doorbell->page advance legal)
    output wire [31:0] pg_desc_o     ,  // active-page descriptor (§6.1)
    output wire        pg_win_rdy    ,  // settled window for deferred bind
    // ---- v2.5 (C3 r12 B 裁定): issuer S_ADV prefetch pulse 真线（B 前
    //      tie 0 于 u_page_tables；B 后透传贯通，tie 拆除） ----
    input  wire        pg_pref       ,
    // ---- M10.1-v2 phase 2e (ABI 0xE0, SPEC §7.5) ----
    output reg         cfg_chain_rel ,  // CHAIN_REL: 1 = credit-gated
    output reg  [15:0] cfg_up2x      ,  // 5b: CHAIN_UP2X producer bitmap
                                        //   release (sampled at start)
    output reg  [2:0]  cfg_schedule_page,
    output reg  [5:0]  cfg_gconv_base,
    output reg         cfg_hbuf_restart,
    output reg  [5:0]  cfg_de_reserved,
    // ---- ABI v2.3 (M10.2 m8, DESIGN_m8_v23.md §1/§2) ----
    output wire [255:0] cfg_ppp_tab  ,  // 8 x 32b PPP trigger table (v2.4:
                                        //   windowed face from m9_page_tables,
                                        //   same width -> zero drift through
                                        //   the frozen wrappers)
    output wire [47:0]  cfg_layout_id,  // 16 page-local conv x 3b layout
                                        //   select (v2.4 widened from 30b;
                                        //   truncates at the frozen wrapper,
                                        //   r10 width-propagation precedent)
    output reg  [7:0]   frame_gen    ,  // doorbell-latched frame generation
    output reg          frame_token  ,  // 1-cycle pulse with start (walker
                                        //   island latches its current_gen)
    // ---- doorbell start pulse and Stage-B request/accept contract ----
    output reg         start,
    output reg         accept_start,
    output reg         accept_normal,
    output reg         accept_rejected_frame,
    output reg         recovery_accept,
    output reg  [1:0]  start_mode,
    output wire [1:0]  candidate_start_mode,
    output wire        raw_db_req,
    output wire        db_req_pending,
    output reg         request_reject,
    output reg  [7:0]  request_status,
    input  wire        accept_static_ok_i,
    input  wire        accept_quiescent_ok_i,
    input  wire        local_reject_static_ok_i,
    input  wire        recovery_static_ok_i,
    input  wire        rejected_frame_quiescent_i,
    input  wire        recoverable_reject_i,
    input  wire        legacy_local_reject_now_i,
    input  wire        rejected_frame_active_i,
    input  wire        rejected_done_seen_i,
    input  wire [2:0]  local_reject_flags_i,
    output wire        tr_we,
    output wire [11:0] tr_waddr,
    output wire [31:0] tr_wdata,
    output wire [11:0] tr_raddr,
    input  wire [31:0] tr_rdata
);

    // ---------------- write path ----------------
    // Independent AW / W capture (board-proven canon: V2.4
    // yolo_axi_lite_slave.sv).  AXI4-Lite lets the master present AW and
    // W in DIFFERENT cycles; V1.0 gated both readies on aw_seen||w_seen,
    // demanding a same-cycle pair.  The PS GP0 auto protocol converter
    // staggers AW/W, so the first board write deadlocked the GP
    // interconnect and took down the whole PS (read channel unaffected,
    // CAP0/RO reads returned fine -- board_run01 stepB evidence).  The
    // xsim BFM happened to pair AW+W in one cycle, which is why every
    // gate stayed green.  New AW/W are blocked only while B is pending;
    // commit ordering (one register write per AW+W pair) is unchanged.
    reg        aw_seen, w_seen;
    reg [15:0] aw_addr_q;
    reg [31:0] w_data_q;
    reg [3:0]  w_strb_q;   // V2.6：WSTRB 同 W 数据拍锁存（s_wstrb 不保持
                           // 律——装载口 G1 显式门控在 wr_go 拍判此寄存）
    wire       wr_go   = aw_seen && w_seen;

    // Observe-only trace CSR aperture. Existing configuration decode is intact.
    // 2b: the edge-table window 0xCC-0xDC stays inside the CSR slave (the
    // trace block owns 0x60-0xC4 + ring payload and ignores these anyway;
    // exclusion kept for aperture cleanliness).
    // 5b (M10.5): carve 0xF0 (JOIN_CURSOR) / 0xF4 (JOIN_DATA) out of the
    // trace payload aperture (>0xE8) for the piecewise join-region table.
    // v2.3 (M10.2 m8): the WHOLE (0xE8,0xF0) band is carved out (DESIGN
    // §1.3-4) -- the six free slots 0xE9-0xEF now carry the PPP/LAYOUT
    // indirect word tables, which need clean write AND read sides.  New
    // aperture = [0x60,0xCB] U [0xDD,0xDF] U [0xF5,0xFF].  0xEE/0xEF
    // reserved-address write observation is lost with the band; trace
    // anchors go explicit events (G2 law).
    // V2.6（C2 影子集拆除实现面）：tr_we 增 aw_addr_q[15:8]==0 高位
    // 零门——扩径后 0x100-0x1FF 写不再被扫进 trace 环（0x160-0x1CB
    // 环别名消失 = §1.5 拆除清单②，有意行为变更，呈批件已声明）。
    assign tr_we = wr_go && (aw_addr_q[15:8] == 8'h00) &&
                   (aw_addr_q >= 8'h60) &&
                   ((aw_addr_q < 8'hCC) ||
                    ((aw_addr_q > 8'hDC) && (aw_addr_q < 8'hE0)) ||
                    (aw_addr_q > 8'hF4));
    assign tr_waddr = {4'd0, aw_addr_q[7:0]};
    assign tr_wdata = w_data_q;
    assign tr_raddr = {4'd0, s_araddr[7:0]};

    // ---------------- 2b edge table state ----------------------------
    // 2e fix (10-15 board ladder): cfg_chain_rel lives ENTIRELY in this
    // block.  It was ALSO reset in the main config block below -> two
    // always blocks driving one flop = Synth 8-6859 multi-driven; Vivado
    // dropped the 0xE0 write path (xsim scheduled the edge block last so
    // the TB passed -- classic sim/synth divergence).  Single driver now.
    reg [3:0]  edge_idx;
    // 5b join-region table: 4 regions x 5 words = 20 words, flat cursor.
    // Word layout per region i (words 5i..5i+4):
    //   5i+0 xj_lo  (X-plan byte offset of region start, after cfg_xbase)
    //   5i+1 xj_hi  (end exclusive; hi<=lo disables the region)
    //   5i+2 split  (A-side byte count; off<split -> A, else B)
    //   5i+3 yA_base (Y-space base of producer A's slot)
    //   5i+4 yB_base (Y-space base of producer B's slot)
    // v2.4 (M11a): the EDGE/JOIN STORAGE lives in m9_page_tables (shared
    // with the page windows; one writer process there, multi-drive law).
    // 0xD8/0xDC/0xF4 keep their legacy decode shape but route as byte-
    // lane/full writes into the SAME RAMs via the lds_* load face (table
    // load decode below).  cfg_edge_*/cfg_join_tab are windowed output
    // WIRES driven by the table module.  Only the cursors live here.
    reg [4:0]  join_cur;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_idx      <= 4'd0;
            cfg_nedge     <= 4'd0;
            cfg_chain_rel <= 1'b0;
            cfg_up2x      <= 16'd0;
            cfg_schedule_page <= 3'd0;
            cfg_gconv_base <= 6'd0;
            cfg_hbuf_restart <= 1'b0;
            cfg_de_reserved <= 6'd0;
            join_cur      <= 5'd0;
            dbg_cur       <= 4'd0;   // r8 single-drive law: owned ONLY by
                                     // this block (0xF8 write below); the
                                     // main-block reset copy made it
                                     // multi-driven -> Vivado dropped the
                                     // 0xF8 path on silicon (r7 probe-dead
                                     // root cause, 10-16)
        end else if (wr_go) begin
            case (aw_addr_q)
            8'hD0: cfg_nedge <= w_data_q[3:0];
            8'hD4: edge_idx  <= w_data_q[3:0];
            8'hF0: join_cur  <= w_data_q[4:0];
            // 8'hF4 data write: routed to the shared JOIN RAM via lds_*
            // (comb decode below); ONLY the legacy cursor auto-inc lives
            // here (mod 20 law unchanged)
            8'hF4: join_cur <= (join_cur == 5'd19) ? 5'd0
                                                   : join_cur + 5'd1;
            // 2e (SPEC §7.5): CHAIN_REL mode bit; [31:1] reserved
            8'hE0: cfg_chain_rel <= w_data_q[0];
            // 5b (M10.5): CHAIN_UP2X per-conv producer bitmap: conv c's
            // scatter materializes the nearest-2x image into its slot
            // (4x bytes, block pitch = 4*stride).  0xDE sits in the
            // trace-carved 0xDD-0xDF gap (no PS decode collision).
            // Stage B: [31:26] reserved, [25] restart, [24:22] page,
            // [21:16] global-conv base, [15:0] legacy producer bitmap.
            8'hDE: begin
                cfg_up2x <= w_data_q[15:0];
                cfg_gconv_base <= w_data_q[21:16];
                cfg_schedule_page <= w_data_q[24:22];
                cfg_hbuf_restart <= w_data_q[25];
                cfg_de_reserved <= w_data_q[31:26];
            end
            // D0 board-proven transport repair: 0xDE is not 4-aligned and
            // PYNQ rejects full-word accesses there.  0xEC previously had
            // no write side effect; use it only as the aligned high-half
            // loader.  Its CAP2 readback remains unchanged.  After an EC
            // high-half write and DE low-half write, DE reads the full word.
            8'hEC: begin
                cfg_gconv_base <= w_data_q[5:0];
                cfg_schedule_page <= w_data_q[8:6];
                cfg_hbuf_restart <= w_data_q[9];
                cfg_de_reserved <= w_data_q[15:10];
            end
            // r7 debug aperture cursor (select word 0..7; readback at 0xF8)
            8'hF8: dbg_cur <= w_data_q[3:0];
            default: ;
            endcase
        end
    end

    reg        r_awready, r_wready;
    assign s_awready = r_awready;
    assign s_wready  = r_wready;

    // ---------------- v2.4 table / PPP / LAYOUT / PAGE_CTRL state --------
    // SPEC_m11a §2.3/§4: the PPP/EDGE/JOIN/PAGE storage lives in
    // m9_page_tables (windowed read face, page_r = issuer page register).
    // This block owns ONLY: the four per-table load cursors + the table-
    // select latch (0xE9), the 48b page-local layout vector (0xEB low +
    // 0xEE[15:0] high, 拼布 ruling), and the PAGE_CTRL register
    // (npages/auto_adv, 0xEE[19:16]/[19]).  Driven ONLY here
    // (multi-driver single-block law; cfg_chain_rel / dbg_cur precedent).
    // Reset = all-zero tables/windows = every PPP opcode 0x00 EMPTY and
    // edge node 0x00 = legacy flat zero state (T7 zero-leak basis);
    // layout all-default = v1 semantics; npages=0 -> issuer z/0-guard
    // treats the frame as degenerate legacy (npages<=1), zero drift.
    //   W0 PPP word layout (DESIGN §2.2, unchanged):
    //     [3:0]   opcode   0x00 EMPTY sentinel (scan stops), 0x11 add,
    //                     0x12 xfer(cat), 0x13 maxpool5 (engine_mux codes)
    //     [8:4]   conv_node[4:0]  trigger point (issuer chain walk)
    //     [15:9]  desc_idx[6:0]   PPU DESC slot (walker direct dispatch)
    //     [16]    req_requant     trailing non-identity requant pass
    //     [17]    ppp_last        last segment of this conv_node (consumer
    //                     release anchor, SPPF 3-level ordering)
    //     [31:18] rsvd (write-ignored, read-zero; v2.4 capacity fields)
    reg  [9:0] tbl_cur [0:3];    // PPP/EDGE(8b used) / JOIN(10b) / PAGE(3b)
    reg  [1:0] tbl_sel_r;
    reg [47:0] layout_id;
    reg  [2:0] npages_r;
    reg        auto_adv_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tbl_sel_r   <= 2'd0;
            layout_id   <= 48'd0;
            npages_r    <= 3'd0;
            auto_adv_r  <= 1'b0;
            tbl_cur[0]  <= 10'd0;
            tbl_cur[1]  <= 10'd0;
            tbl_cur[2]  <= 10'd0;
            tbl_cur[3]  <= 10'd0;
        end else if (wr_go) begin
            case (aw_addr_q)
            // 0xE9: {21'd0, tbl_sel[1:0]@10, tbl_cur[9:0]} direct set.
            // v2.3-compatible superset: a v2.3 driver writing cursor[2:0]
            // lands on sel=0 (PPP) -- its words 0..7 are the legacy table.
            8'hE9: begin
                tbl_sel_r           <= w_data_q[11:10];
                tbl_cur[w_data_q[11:10]] <= w_data_q[9:0];
            end
            // 0xEA: table[tbl_sel][cur] <= wdata, cursor auto-inc
            // (mod 256 / 640 / 8 per table; full-word write, no inc on
            // read -- the read path goes through the tbl_rd face below)
            8'hEA: begin
                if (tbl_sel_r == 2'b00 || tbl_sel_r == 2'b01)
                    tbl_cur[tbl_sel_r] <=
                        (tbl_cur[tbl_sel_r] == 10'd255) ? 10'd0
                                                : tbl_cur[tbl_sel_r] + 10'd1;
                else if (tbl_sel_r == 2'b10)
                    tbl_cur[tbl_sel_r] <=
                        (tbl_cur[tbl_sel_r] == 10'd639) ? 10'd0
                                                : tbl_cur[tbl_sel_r] + 10'd1;
                else
                    tbl_cur[tbl_sel_r] <=
                        (tbl_cur[tbl_sel_r] == 10'd7) ? 10'd0
                                                : tbl_cur[tbl_sel_r] + 10'd1;
            end
            // 0xEB: layout vector low half
            8'hEB: layout_id[31:0] <= w_data_q;
            // 0xEE PAGE_CTRL 拼布: {12'd0, auto_adv, npages[2:0],
            //                       layout_hi[15:0]}
            8'hEE: begin
                layout_id[47:32] <= w_data_q[15:0];
                npages_r         <= w_data_q[18:16];
                auto_adv_r       <= w_data_q[19];
            end
            default: ;
            endcase
        end
    end

    assign cfg_npages = npages_r;
    assign cfg_pgauto = auto_adv_r;

    // ---------------- m9_page_tables (storage + windowed faces) --------
    // Table load port (0xE9/0xEA) and the legacy partial-word write port
    // (0xD8/0xDC/0xF4) are mutually exclusive by the one-PS-write-per-
    // cycle law; the table module $fatal's on a collision (sim guard).
    // The readback port is comb-muxed by the AR address below.
    reg  [9:0] ea_addr;
    always @(*) ea_addr = tbl_cur[tbl_sel_r];   // procedural memory read
                                                // (xsim law: never on a
                                                // continuous assign)
    wire        tbl_we_w    = wr_go && (aw_addr_q == 8'hEA);
    wire [1:0]  tbl_sel_w   = tbl_sel_r;
    wire [9:0]  tbl_addr_w  = ea_addr;
    wire [31:0] tbl_wdata_w = w_data_q;

    wire        lds_we_w    = wr_go &&
                              ((aw_addr_q == 8'hD8) || (aw_addr_q == 8'hDC) ||
                               (aw_addr_q == 8'hF4));
    wire [1:0]  lds_sel_w   = (aw_addr_q == 8'hF4) ? 2'b10 : 2'b01;
    wire [9:0]  lds_addr_w  = (aw_addr_q == 8'hF4) ? {5'd0, join_cur}
                                                   : {6'd0, edge_idx};
    wire [31:0] lds_wdata_w = (aw_addr_q == 8'hD8) ? {16'd0, w_data_q[15:0]} :
                              (aw_addr_q == 8'hDC) ? {w_data_q[15:0], 16'd0} :
                                                     w_data_q;
    wire [3:0]  lds_lane_w  = (aw_addr_q == 8'hD8) ? 4'b0011 :
                              (aw_addr_q == 8'hDC) ? 4'b1100 : 4'b1111;

    // frozen-wrapper float guard: pg_raddr unconnected -> page 0, whose
    // base-0 window reconstructs the legacy flat tables (zero drift)
    wire [2:0] pg_raddr_g = (pg_raddr === 3'bzzz) ? 3'd0 : pg_raddr;

    wire [31:0] tbl_rd_data_w;
    wire        tbl_rd_gnt_w;
    wire        win_rdy_w;
    // V2.5 req/gnt 读回握手：AR 受理 F4/EA 时锁存地址（s_araddr 不保持
    // 律——wait 期主端可提前翻 AR 地址），req 保持至 gnt（page_tables
    // 契约），RVALID hold 到 gnt 拍捕获（gnt+data 同拍）。
    reg  [1:0]  tbl_rd_sel_r;
    reg  [9:0]  tbl_rd_addr_r;
    reg  [1:0]  tbl_rd_sel_q;
    reg  [9:0]  tbl_rd_addr_q;
    reg         tbl_rd_wait;
    reg         tbl_rd_req_r;
    always @(*) begin
        tbl_rd_sel_r  = tbl_sel_r;
        tbl_rd_addr_r = ea_addr;
        if ((s_araddr == 8'hD8) || (s_araddr == 8'hDC)) begin
            tbl_rd_sel_r  = 2'b01;              // EDGE table at edge_idx
            tbl_rd_addr_r = {6'd0, edge_idx};
        end else if (s_araddr == 8'hF4) begin
            tbl_rd_sel_r  = 2'b10;              // JOIN table at join_cur
            tbl_rd_addr_r = {5'd0, join_cur};
        end
    end

    // ---------------- V2.6 装载 FSM 写面合流（呈批件 §2.4 合流律）--------
    // ld/tbl 两源由 AXI-Lite 单未完成写律保证永不同时有效（tbl_we_w
    // 只在 wr_go 拍、ld_tbl_we 只在 S_COMMIT 拍，相位天然错开）；sim
    // 碰撞 $fatal 守卫补在文件尾（沿用 L460-461 形态）。
    reg         armed;    // 门铃置位/done 升沿清除（V2.5 语义不变；
                          // 声明前移：V2.6 FSM 例化在其使用之后——Verilog
                          // 先引用后声明会隐式建 net 撞 reg 声明）
    wire        ld_tbl_we;
    wire [1:0]  ld_tbl_sel;
    wire [9:0]  ld_tbl_addr;
    wire [31:0] ld_tbl_wdata;
    wire        rmw_idle_w;               // page_tables C1 tap-off 输出
    wire        ld_busy_w, ld_done_w;
    wire [3:0]  ld_err_w;
    wire [9:0]  ld_cnt_w, ld_addr_ld_w, ld_len_ld_w;
    wire [1:0]  ld_sel_ld_w;

    // 新装载口写译码（wr_go 拍 1 拍脉冲；0x100-0x118 全部 ≡0 mod 4，
    // PS 字写天然可达——呈批件 §2.1 G1 构造过 PS-reachability 审计）
    wire ld_data_hit = wr_go && (aw_addr_q == 16'h0100);
    wire ld_sel_hit  = wr_go && (aw_addr_q == 16'h0104);
    wire ld_addr_hit = wr_go && (aw_addr_q == 16'h0108);
    wire ld_len_hit  = wr_go && (aw_addr_q == 16'h010C);
    wire ld_err_hit  = wr_go && (aw_addr_q == 16'h0114);

    m9_ldload_fsm u_ldload_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .ld_data_hit  (ld_data_hit),
        .ld_sel_hit   (ld_sel_hit),
        .ld_addr_hit  (ld_addr_hit),
        .ld_len_hit   (ld_len_hit),
        .ld_err_hit   (ld_err_hit),
        .wdata        (w_data_q),
        .wstrb        (w_strb_q),
        .armed        (armed),
        .rmw_idle     (rmw_idle_w),
        .ld_tbl_we    (ld_tbl_we),
        .ld_tbl_sel   (ld_tbl_sel),
        .ld_tbl_addr  (ld_tbl_addr),
        .ld_tbl_wdata (ld_tbl_wdata),
        .ld_busy      (ld_busy_w),
        .ld_done      (ld_done_w),
        .ld_err_code  (ld_err_w),
        .ld_cnt       (ld_cnt_w),
        .ld_sel_o     (ld_sel_ld_w),
        .ld_addr_o    (ld_addr_ld_w),
        .ld_len_o     (ld_len_ld_w)
    );

    wire        tbl_we_m    = tbl_we_w | ld_tbl_we;
    wire [1:0]  tbl_sel_m   = ld_tbl_we ? ld_tbl_sel   : tbl_sel_w;
    wire [9:0]  tbl_addr_m  = ld_tbl_we ? ld_tbl_addr  : tbl_addr_w;
    wire [31:0] tbl_wdata_m = ld_tbl_we ? ld_tbl_wdata : tbl_wdata_w;

    m9_page_tables u_page_tables (
        .clk        (clk),
        .rst_n      (rst_n),
        .tbl_we     (tbl_we_m),
        .tbl_sel    (tbl_sel_m),
        .tbl_addr   (tbl_addr_m),
        .tbl_wdata  (tbl_wdata_m),
        .lds_we     (lds_we_w),
        .lds_sel    (lds_sel_w),
        .lds_addr   (lds_addr_w),
        .lds_wdata  (lds_wdata_w),
        .lds_lane   (lds_lane_w),
        .tbl_rd_req (tbl_rd_req_r),
        .tbl_rd_sel (tbl_rd_sel_q),
        .tbl_rd_addr(tbl_rd_addr_q),
        .tbl_rd_gnt (tbl_rd_gnt_w),
        .tbl_rd_data(tbl_rd_data_w),
        .page_r     (pg_raddr_g),
        .pg_pref    (pg_pref),   // v2.5 B 裁定真线（透传 issuer S_ADV 预取拍；
                                  // 旧 tie 0 已拆——z 守卫 npages=1 下条件链恒假
                                  // 本恒 0，多页帧生效）
        .win_rdy    (win_rdy_w),
        .pg_desc_o  (pg_desc_o),
        .ppp_win_o  (cfg_ppp_tab),
        .edge_node_o(cfg_edge_node),
        .edge_prod_o(cfg_edge_prod),
        .edge_win_o (cfg_edge_win),
        .join_win_o (cfg_join_tab),
        .rmw_idle   (rmw_idle_w)   // V2.6 C1：FSM S_WAIT 反压唯一判据
    );

    assign cfg_layout_id = layout_id;

    // ---------------- Stage-B single-deep request / atomic accept ---------
    // raw_db_req is the AXI write-commit event, never AW/W early reception.
    // A request may wait only when its current static/quiescent checks pass
    // but the checked page-table window is temporarily unavailable.  Every
    // release is requalified; no stale prequalification bit is carried.
    reg        start_pend;
    reg  [7:0] pend_gen;
    reg [15:0] pending_age;
    reg        done_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) done_d <= 1'b0; else done_d <= done;
    wire done_rise = done && !done_d;

    assign raw_db_req = wr_go && (aw_addr_q == 16'h0038);
    assign db_req_pending = start_pend;

    wire accept_resource_ok = win_rdy_w && rmw_idle_w;
    assign pg_win_rdy = win_rdy_w;
    localparam [1:0] SPPF_NONE   = 2'd0;
    localparam [1:0] SPPF_AUTO   = 2'd1;
    localparam [1:0] SPPF_MANUAL = 2'd2;
    wire [3:0] candidate_npages = (npages_r == 3'd0) ? 4'd1 :
                                  {1'b0, npages_r} + 4'd1;
    wire candidate_paged = (cfg_nconv > 5'd1) &&
                           ((candidate_npages > 4'd1) ||
                            (cfg_schedule_page != 3'd0) ||
                            (cfg_gconv_base != 6'd0));
    assign candidate_start_mode = !candidate_paged ? SPPF_NONE :
                                  auto_adv_r ? SPPF_AUTO : SPPF_MANUAL;
    wire request_is_recovery = recoverable_reject_i;
    wire request_is_rejected = legacy_local_reject_now_i;
    wire request_static_ok = request_is_recovery ? recovery_static_ok_i :
                             request_is_rejected ? local_reject_static_ok_i :
                                                   accept_static_ok_i;
    wire request_quiescent_ok = request_is_recovery ?
                                rejected_frame_quiescent_i :
                                accept_quiescent_ok_i;
    wire pending_release = start_pend && !raw_db_req && accept_resource_ok;
    wire accept_now = ((raw_db_req && !start_pend) || pending_release) &&
                      request_static_ok && request_quiescent_ok &&
                      accept_resource_ok;
    wire pend_set = raw_db_req && !start_pend && request_static_ok &&
                    request_quiescent_ok && !accept_resource_ok;
    wire raw_db_overlap = raw_db_req && start_pend;
    wire new_request_reject = raw_db_req && !start_pend && !accept_now &&
                              !pend_set;
    wire pending_release_reject = pending_release && !accept_now;
    wire pending_timeout = start_pend && !raw_db_req && !accept_now &&
                           (pending_age == 16'hFFFF);
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (armed && (tbl_we_w || lds_we_w))
            $fatal(1, "M9CSR_FAIL runtime table write while armed (load/run separation)");
        // V2.6 §2.4：ld/tbl 合流碰撞守卫（两源同拍有效 = 单未完成写律
        // 违约）。注意 ld_tbl_we 不含于上条 armed 守卫：FSM 在受理拍
        // 已硬门 armed（err_code=3），在飞提交拍后于 arming 完成是
        // 受理先于门铃的合法时序（与 legacy EA 写同 Exposure）。
        if (tbl_we_w && ld_tbl_we)
            $fatal(1, "M9CSR_FAIL ld/tbl write collision (one-write-per-cycle law)");
    end
`endif

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen <= 1'b0; w_seen <= 1'b0;
            r_awready <= 1'b1; r_wready <= 1'b1;
            aw_addr_q <= 16'd0; w_data_q <= 32'd0; w_strb_q <= 4'd0;
            s_bvalid <= 1'b0; s_bresp <= 2'd0;
            start <= 1'b0;
            accept_start <= 1'b0;
            accept_normal <= 1'b0;
            accept_rejected_frame <= 1'b0;
            recovery_accept <= 1'b0;
            start_mode <= 2'd0;
            request_reject <= 1'b0;
            request_status <= 8'd0;
            frame_gen <= 8'd0;      // v2.3: doorbell generation latch
            frame_token <= 1'b0;    // v2.3: 1-cycle pulse with start
            start_pend <= 1'b0;
            pend_gen <= 8'd0;
            pending_age <= 16'd0;
            armed <= 1'b0;
            plan_base <= 32'd0; arena_base <= 32'd0; w_base <= 32'd0;
            cfg_nb <= 10'd0; cfg_rc <= 6'd0; cfg_ns <= 4'd0;
            cfg_nseg <= 2'd0; cfg_nconv <= 5'd0;
            cfg_ic <= 16'd0; cfg_h <= 16'd0; cfg_w <= 16'd0;
            cfg_kh <= 4'd0; cfg_kw <= 4'd0; cfg_sh <= 4'd0;
            cfg_sw <= 4'd0; cfg_ph <= 4'd0; cfg_pw <= 4'd0;
            cfg_first <= 1'b0; cfg_law_fetch <= 1'b0; cfg_overlap <= 1'b0;
            cfg_oc <= 8'd0; cfg_s0_k <= 11'd0; cfg_s0_jc <= 8'd0;
            cfg_s0_g <= 2'd0; cfg_stride <= 32'd0; cfg_obuf <= 32'd0;
            cfg_slab <= 32'd0; cfg_rc_stride <= 32'd0; cfg_oc_stride <= 32'd0;
            cfg_chain_mask <= 16'd0;
            // cfg_chain_rel NOT here -- owned by the edge-table block
            // (single-driver law, see the 2e fix note above).
        end else begin
            start <= 1'b0;                       // doorbell = 1-cycle pulse
            accept_start <= 1'b0;
            accept_normal <= 1'b0;
            accept_rejected_frame <= 1'b0;
            recovery_accept <= 1'b0;
            frame_token <= 1'b0;                 // v2.3: same pulse law
            if (accept_now) begin
                start_pend <= 1'b0;
                pending_age <= 16'd0;
                start <= 1'b1;
                accept_start <= 1'b1;
                request_reject <= 1'b0;
                request_status <= 8'd0;
                armed <= 1'b1;
                start_mode <= candidate_start_mode;
                recovery_accept <= request_is_recovery;
                if (request_is_rejected) begin
                    accept_rejected_frame <= 1'b1;
                end else begin
                    accept_normal <= 1'b1;
                    frame_gen <= raw_db_req ? w_data_q[7:0] : pend_gen;
                    frame_token <= 1'b1;
                end
            end else begin
                if (raw_db_req && !start_pend) begin
                    request_reject <= 1'b0;
                    request_status <= 8'd0;
                end
                if (pend_set) begin
                    start_pend <= 1'b1;
                    pend_gen <= w_data_q[7:0];
                    pending_age <= 16'd0;
                end else if (start_pend && (pending_age != 16'hFFFF)) begin
                    pending_age <= pending_age + 16'd1;
                end
                if (new_request_reject || pending_release_reject) begin
                    start_pend <= 1'b0;
                    request_reject <= 1'b1;
                    request_status <= 8'd1;
                end
                if (raw_db_overlap) begin
                    request_reject <= 1'b1;
                    request_status <= 8'd2;
                end
                if (pending_timeout) begin
                    start_pend <= 1'b0;
                    request_reject <= 1'b1;
                    request_status <= 8'd3;
                end
            end
            if (done_rise) armed <= 1'b0;
            if (s_bvalid && s_bready) begin
                s_bvalid <= 1'b0;
                r_awready <= 1'b1; r_wready <= 1'b1;   // B done: reopen faces
            end
            if (s_awvalid && r_awready) begin
                aw_seen  <= 1'b1;
                aw_addr_q <= s_awaddr;
                r_awready <= 1'b0;
            end
            if (s_wvalid  && r_wready) begin
                w_seen   <= 1'b1;
                w_data_q <= s_wdata;
                w_strb_q <= s_wstrb;   // V2.6 G1：同拍锁存
                r_wready <= 1'b0;
            end
            if (wr_go) begin
                aw_seen <= 1'b0; w_seen <= 1'b0;
                s_bresp <= 2'd0;                 // OKAY everywhere
                s_bvalid <= 1'b1;
                case (aw_addr_q)
                8'h04: plan_base    <= w_data_q;
                8'h08: arena_base   <= w_data_q;
                8'h0C: w_base       <= w_data_q;
                8'h10: begin
                    cfg_nb   <= w_data_q[9:0];
                    cfg_rc   <= w_data_q[15:10];
                    cfg_ns   <= w_data_q[19:16];
                    cfg_nseg <= w_data_q[21:20];
                    cfg_nconv<= w_data_q[28:24];
                end
                8'h14: begin
                    cfg_ic <= w_data_q[15:0];
                    cfg_h  <= w_data_q[31:16];
                end
                8'h18: begin
                    cfg_w  <= w_data_q[15:0];
                    cfg_kh <= w_data_q[19:16];
                    cfg_kw <= w_data_q[23:20];
                    cfg_sh <= w_data_q[27:24];
                    cfg_sw <= w_data_q[31:28];
                end
                8'h1C: begin
                    cfg_ph        <= w_data_q[3:0];
                    cfg_pw        <= w_data_q[7:4];
                    cfg_first     <= w_data_q[8];
                    cfg_law_fetch <= w_data_q[9];
                    cfg_overlap   <= w_data_q[10];
                    cfg_oc        <= w_data_q[23:16];
                end
                8'h20: begin
                    cfg_s0_k  <= w_data_q[10:0];
                    cfg_s0_jc <= w_data_q[18:11];
                    cfg_s0_g  <= w_data_q[20:19];
                end
                8'h24: cfg_stride    <= w_data_q;
                8'h28: cfg_obuf      <= w_data_q;
                8'h2C: cfg_slab      <= w_data_q;
                8'h30: cfg_rc_stride <= w_data_q;
                8'h34: cfg_oc_stride <= w_data_q;
                8'h58: cfg_chain_mask <= w_data_q[15:0];  // M10.1 v2.1
                // Doorbell handling is centralized above at raw_db_req.
                // The AXI write itself never directly starts execution.
                8'h38: ;
                default: ;                       // RO/undefined: OKAY, no effect
                endcase
            end
        end
    end

    // ---------------- P2 clock probe (r5 tick patch) ----------------
    // 0x54 CNT4/TICK RO tick_cnt[31:0] -- free-running counter on the PL
    // aclk (= clk here).  Not part of any control or gate criterion; NOT
    // cleared by rst_n (soft reset law) -- only power-on/bitstream
    // download clears it (FF INIT=0).  0x00-0x50 semantics untouched.
    // ---------------- G3 OVF AW-capture (RUNBOOK_5d §11 补盲) ----------
    // Suspended-item deal: the 960B silicon-only OVF-sidecar writes have
    // only a post-hoc footprint (poison overwrite + fp_md5 9f064c35...);
    // the blind spot is the write-master ADDRESS STREAM.  This ring taps
    // the m2 AW channel (the only DDR write master, y_scatter path) and
    // latches the write pointer at the E_CHAIN_OVF (err=0x11) rising
    // edge.  The ring KEEPS ROLLING after the trigger (ovf_trig is only a
    // sticky marker), so software can reconstruct both the around-event
    // window (entries relative to the latched pointer) and, by polling
    // 0xEF at software pace, the whole post-OVF stream.  Addresses sit in
    // the CSR-owned slots 0xE2/0xE6/0xEF (v2.4: 0xEF; trace-aperture
    // orphans before G3: reads there accidentally returned ring-payload
    // garbage via the >=0x60 default -- these explicit cases close that
    // leak too).
    //   0xE2 OVF_STAT  RO {15'd0, ovf_trig, ovf_tot[15:0]}  WO=re-arm
    //   0xE6 OVF_CUR   RW  ring read cursor [3:0] (direct set, PPP law)
    //   0xEF OVF_DATA  RO  ovf_ring[ovf_cur_q] (no auto-inc; v2.4
    //                      relocation from 0xEE, PAGE_CTRL owns 0xEE)
    // Single always block owns every ovf_* reg (multi-drive law).
    reg        ovf_trig;
    reg [15:0] ovf_tot;
    reg [3:0]  ovf_wp, ovf_cur_q;
    reg [31:0] ovf_ring [0:15];
    reg [7:0]  err_d;
    wire       ovf_evt = (err == 8'h11) && (err_d != 8'h11);
    wire       ovf_push = mon_awvalid && mon_awready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ovf_trig  <= 1'b0;
            ovf_tot   <= 16'd0;
            ovf_wp    <= 4'd0;
            ovf_cur_q <= 4'd0;
            err_d     <= 8'd0;
        end else begin
            err_d <= err;
            if (ovf_evt)
                ovf_trig <= 1'b1;
            if (wr_go && (aw_addr_q == 8'hE2)) begin
                // re-arm: clear trigger + volume counter (ring/cursor
                // intentionally left intact for post-mortem reads)
                ovf_trig <= 1'b0;
                ovf_tot  <= 16'd0;
            end else if (ovf_push) begin
                ovf_ring[ovf_wp] <= mon_awaddr;
                ovf_wp           <= ovf_wp + 4'd1;
                if (ovf_tot != 16'hFFFF)
                    ovf_tot <= ovf_tot + 16'd1;
            end
            if (wr_go && (aw_addr_q == 8'hE6))
                ovf_cur_q <= w_data_q[3:0];
        end
    end

    reg [31:0] tick_cnt = 32'd0;
    always @(posedge clk) tick_cnt <= tick_cnt + 32'd1;

    // ---------------- read path ----------------
    // AR accepted only while no R pending and no table-readback wait;
    // R holds until accepted.
    assign s_arready = ~s_rvalid & ~tbl_rd_wait;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rvalid <= 1'b0; s_rdata <= 32'd0; s_rresp <= 2'd0;
            tbl_rd_wait <= 1'b0; tbl_rd_req_r <= 1'b0;
            tbl_rd_sel_q <= 2'b00; tbl_rd_addr_q <= 10'd0;
        end else begin
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
            if (tbl_rd_gnt_w) begin
                // gnt+data 同拍（page_tables 契约）：捕获即有效
                tbl_rd_wait  <= 1'b0;
                tbl_rd_req_r <= 1'b0;
                s_rresp      <= 2'd0;
                s_rdata      <= tbl_rd_data_w;
                s_rvalid     <= 1'b1;
            end else if (tbl_rd_wait) begin
                tbl_rd_req_r <= 1'b1;      // req 保持至 gnt（契约）
            end else if (s_arvalid && s_arready) begin
                if ((s_araddr == 8'hF4) || (s_araddr == 8'hEA)) begin
                    tbl_rd_wait  <= 1'b1;
                    tbl_rd_req_r <= 1'b1;
                    tbl_rd_sel_q <= tbl_rd_sel_r;
                    tbl_rd_addr_q<= tbl_rd_addr_r;
                end else begin
                s_rresp   <= 2'd0;
                case (s_araddr)
                8'h00: s_rdata <= 32'h4D39_0240;  // v2.4 (M11a page sched)
                8'h04: s_rdata <= plan_base;
                8'h08: s_rdata <= arena_base;
                8'h0C: s_rdata <= w_base;
                8'h10: s_rdata <= {3'd0, cfg_nconv, 2'd0, cfg_nseg, cfg_ns,
                                   cfg_rc, cfg_nb};
                8'h14: s_rdata <= {cfg_h, cfg_ic};
                8'h18: s_rdata <= {cfg_sw, cfg_sh, cfg_kw, cfg_kh, cfg_w};
                8'h1C: s_rdata <= {3'd0, cfg_oc, 5'd0, cfg_overlap,
                                    cfg_law_fetch, cfg_first, cfg_pw, cfg_ph};
                8'h20: s_rdata <= {11'd0, cfg_s0_g, cfg_s0_jc, cfg_s0_k};
                8'h24: s_rdata <= cfg_stride;
                8'h28: s_rdata <= cfg_obuf;
                8'h2C: s_rdata <= cfg_slab;
                8'h30: s_rdata <= cfg_rc_stride;
                8'h34: s_rdata <= cfg_oc_stride;
                8'h38: s_rdata <= 32'd0;        // doorbell reads 0
                // STATUS pack: err MUST sit at [15:8] per ABI (busy@0
                // done@1 err[7:0]@8).  {20'd0, err, done, busy} is a
                // 30-bit expression -> err landed at [9:2] and every
                // (val>>8)&0xFF reader (TB + driver) saw only err[7:6]
                // = always 0 for codes 1..63 (latent since V1.0, found
                // by the M10.1 T4 probe 2026-10-14).  勘误.
                8'h3C: s_rdata <= {16'd0, err, 6'd0, done, busy};
                8'h40: s_rdata <= {16'd0, progress_blk};
                8'h44: s_rdata <= cnt_beats;
                8'h48: s_rdata <= {6'd0, cnt_y_blocks, cnt_csr_w};
                8'h4C: s_rdata <= {12'd0, cnt_y_bytes};
                8'h50: s_rdata <= cnt_stall;
                8'h54: s_rdata <= tick_cnt;    // P2 clock probe (r5)
                8'h58: s_rdata <= {16'd0, cfg_chain_mask}; // M10.1 RW face
                8'h5C: s_rdata <= cnt_chain_bytes;         // M10.1 RO ledger
                // ---- 2b edge table window (explicit: keep out of the
                // >=0x60 trace-aperture default below) ----
                8'hCC: s_rdata <= 32'h4D39_1008; // CAP1 | NSLOT=8 (unchanged)
                // 5b join-extension capability at 0xEC (explicit case
                // overrides the trace-ring default read, same law as
                // 0xE0-0xE8 above): 0x4D39_5J00, J = max join regions = 4
                // D0 aligned high-half write/readback alias.  CAP2 read
                // is replaced by the live high-half value so host never
                // relies on the unsupported unaligned full-DE access.
                8'hEC: s_rdata <= {16'd0, cfg_de_reserved,
                                   cfg_hbuf_restart, cfg_schedule_page,
                                   cfg_gconv_base};
                // 5b join table readback (driver sets cursor via 0xF0
                // first; reads do NOT auto-increment).  V2.5: storage
                // lives in m9_page_tables behind the req/gnt handshake --
                // AR accept enters tbl_rd_wait and RVALID is raised on
                // the gnt beat (read-path FSM above).
                8'hD0: s_rdata <= {28'd0, cfg_nedge};
                8'hD4: s_rdata <= {28'd0, edge_idx};
                8'hD8: s_rdata <= {16'd0,
                                   cfg_edge_prod[edge_idx*8 +: 8],
                                   cfg_edge_node[edge_idx*8 +: 8]};
                8'hDC: s_rdata <= {16'd0,
                                   cfg_edge_win[edge_idx*16 +: 16]};
                // ---- 2e credit-gated release (SPEC §7; 盘态实读:
                // 0xE0-0xE8 在 trace ring 读窗口 0xA4-0x4A4 内，必须
                // CSR 显式 case 优先，否则 PS 读会拿到 ring 数据) ----
                8'hE0: s_rdata <= {31'd0, cfg_chain_rel};
                8'hDE: s_rdata <= {cfg_de_reserved, cfg_hbuf_restart,
                                   cfg_schedule_page, cfg_gconv_base,
                                   cfg_up2x};
                8'hE4: s_rdata <= s2l_cnt;
                8'hE8: s_rdata <= skew_max;
                // ---- v2.4 table/PPP/LAYOUT window (explicit case
                // beats the trace-ring default read, 0xE0-0xE8 law) ----
                8'hE9: s_rdata <= {20'd0, tbl_sel_r, ea_addr};
                8'hEA: ;        // V2.5: req/gnt wait-state path (above)
                8'hEB: s_rdata <= layout_id[31:0];      // 48b vector lo
                // PAGE_CTRL 拼布 readback: {12'd0, auto_adv, npages,
                //                           layout_hi[15:0]}
                8'hEE: s_rdata <= {12'd0, auto_adv_r, npages_r,
                                   layout_id[47:32]};
                8'hED: s_rdata <= 32'h4D39_0810;   // CAP3 (§2.3: 8 PPP /
                                                   // 0x10 layout conv-page /
                                                   // NPAGE=8)
                // ---- G3 OVF AW-capture window (RUNBOOK_5d §11; explicit
                // case beats the trace-ring default read, 0xE0-0xE8 law).
                // v2.4: OVF_DATA relocated 0xEE -> 0xEF (0xEE carries
                // PAGE_CTRL; 0xEF reserve consumed, documented) ----
                8'hE2: s_rdata <= {15'd0, ovf_trig, ovf_tot};
                8'hE6: s_rdata <= {28'd0, ovf_cur_q};
                8'hEF: s_rdata <= ovf_ring[ovf_cur_q];
                // ---- r7 debug aperture (explicit case beats the trace
                // ring default read, same law as 0xE0-0xE8 above) ----
                8'hF8: s_rdata <= {28'd0, dbg_cur};
                8'hFC: s_rdata <= hb_dbg[{dbg_cur, 5'b00000} +: 32];
                // ---- V2.6 新装载口读面（0x100-0x118，字对齐 RW/RO；
                //      显式 case 优先于 trace-ring default，0xE0-0xE8
                //      同律；LD_DATA 0x100 为 WO 面——读落 default=0）
                16'h0104: s_rdata <= {30'd0, ld_sel_ld_w};
                16'h0108: s_rdata <= {22'd0, ld_addr_ld_w};
                16'h010C: s_rdata <= {22'd0, ld_len_ld_w};
                16'h0110: s_rdata <= {30'd0, ld_done_w, ld_busy_w};
                16'h0114: s_rdata <= {28'd0, ld_err_w};
                16'h0118: s_rdata <= {22'd0, ld_cnt_w};
                // V2.6（C2 拆除实现面）：读 default 增高位零门——
                // 0x100+ 读不再落入 trace 环返回环数据（0x160-0x1CB
                // 读别名消失 = §1.5 拆除清单②）
                default: s_rdata <= ((s_araddr[15:8] == 8'h00) &&
                                     (s_araddr >= 8'h60)) ? tr_rdata
                                                          : 32'd0;
                endcase
                s_rvalid <= 1'b1;
                end            // V2.5: non-table-readback AR branch
            end
        end
    end

endmodule
