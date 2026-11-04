/************************************************************************
 * File Name       : m9_intra_axi_top_v3.v
 * Developer       : M9.3 V3 issuer redesign line
 * Date            : 2026-10-13
 * Project Name    : YOLO object accel (M9.3 V3, 2026-10-13_yolo_m93_issuer_v3_run01)
 * Module Name     : m9_intra_axi_top_v3
 * Description     :
 *   M9.3 V3 sibling of m9_intra_axi_top (V1.3) -- SIBLING COMPOSITION.
 *   The intra core is m9_intra_top_v3 (V3 feeders, line faces, H2' tap);
 *   the two read adapters swap m9_axi_rd_v2 -> m9_axi_rd_v3 (V3: 16-deep
 *   LSQ line client port + SPEC_N=8 demand-seeded speculation window +
 *   V2.1 five fixes + V2.3 distributed-RAM law):
 *
 *     x window line reads  <- m9_axi_rd_v3 u_xrd  (HP0 read master)
 *     w feeder line reads  <- m9_axi_rd_v3 u_wrd  (HP3 read master)
 *     y scatter byte writes-> m9_axi_wr u_ywr      (HP0 write, unchanged)
 *
 *   The legacy byte client face of each m9_axi_rd_v3 is tied off
 *   (rreq_i=0; no V3 client uses it) and kept for the legacy TB
 *   contract per the V3 header law.  lsq_ovf_o is sim-fatal inside the
 *   adapter; left open here (sticky synth flag unused at this level).
 *   tr_array_active (H2' tap) passes through to the top port.
 *   Port list otherwise IDENTICAL to V1.3 -- every ladder TB compiles
 *   against this sibling unchanged.
 *
 *   V3.1 (M10.1, 2026-10-14): layer_chain handoff add-on (SPEC v1.1 /
 *   ABI v2.1 ch.10).  Pure adapter-level addition; every frozen core
 *   stays BYTE-IDENTICAL:
 *     - m9_hbuf_ctrl u_hbuf: Y-scatter write tap -> HBUF (BMG TDP 32KB)
 *       -> chained-conv X line reads (credit = block-sequential
 *       watermark; TGPA tile-window isomorph);
 *     - request routing mux: chain_sel (CHAIN_MASK[conv_idx]) sends the
 *       x window line requests to the HBUF queue, else to u_xrd as
 *       before; responses merge in order (the serve gate requires the
 *       DDR queue empty, so the two sources can never interleave);
 *     - E_CHAIN_MASK=10 legality (bit0 / multi-bit / non-walk) rejects
 *       the frame AT THE ADAPTER: engine start suppressed, done
 *       synthesized (~16 cyc), err sticky -- frozen issuer untouched;
 *     - E_CHAIN_OVF=11 (chained read outside the producer slot window)
 *       is report-only sticky (frame already ran; arena dual-write
 *       keeps the TB/board compare ground truth).
 *
 * Dependencies    : m9_intra_top_v3.v, m9_axi_rd_v3.v, m9_axi_wr.v,
 *                   m9_hbuf_ctrl.v, m9_bm_hbuf (blk_mem_gen 8.4)
 * Revision History:
 *   - V3.0 (2026-10-13) : sibling of m9_intra_axi_top V1.3 (axi_rd_v3
 *                         line wiring + H2' passthrough).  Inherited
 *                         history V1.0-V1.3 applies to all else.
 *   - V3.1 (2026-10-14) : M10.1 layer_chain handoff (hbuf ctrl + read
 *                         mux + CHAIN_MASK legality + CHAIN_CNT face).
 *   - V3.2-M11 (2026-10-18): r11 repack merge (SPEC_m11_repack.md §7):
 *                         define-gated u_repack + u_repack_glue block
 *                         (contacts #1/#3/#4/#5/#6), y_scatter/repack
 *                         write arbitration into the SHARED u_ywr
 *                         (contact #6, m9_axi_wr untouched; the hbuf tap
 *                         keeps the scatter-only view).  Config face is
 *                         the r11 inert carrier (contact #2 "r11 裁"):
 *                         rp_arm tied 1'b0, u_repack carried under
 *                         keep_hierarchy.  Without M11_REPACK this file
 *                         compiles byte-identical to the r10 shadow.
 *   - V3.3-D1D2 (2026-10-26) : repack 配置面闭合 (D1) + issuer 判决锁存
 *                         (D2) 同修 (审计 R154 快裁 + R155 重裁; SPEC v3
 *                         新章《M11 repack 配置面闭合与判决锁存 (D1/D2
 *                         同修)》(2026-10-26 立项, 数字待 run04 回填)):
 *       * D1 arm 真源 = 门铃受理链 (设计件 §1): rp_arm_r 置位 = start
 *         受理拍且 paged (cfg_npages 非零, issuer S_IDLE start 同事件),
 *         1-cycle 帧级 re-arm 脉冲, 零 ABI 触碰 (不动 CSR/CAP0);
 *         glue 侧 rp_arm 保持 1'b0 (legacy 惰性载体不动, arm_accept 几何
 *         零守卫天然拒收).
 *       * D1 err 面 = R155 中案连接点重映射: u_repack rp_err/rp_err_code
 *         脱空挂 -> rp_err_mapped = rp_err ? code+8'h0D : 8'h00 (映射表
 *         见接线处头注), 新增内部口经 m9_intra_top_v3 透传 issuer;
 *         repack 模块内部一字不动.
 *       * D2 (issuer 侧, 见 m9_cmd_issuer.v V3.2-D1D2): 判决锁存
 *         ppp_vld/ppp_ab/ppp_err + 看门狗边沿刷新修正案.
 *       * 配置几何/src/dst 基址维持 r11 tie-off: dst 窗精确推导式按
 *         设计件 §1 是本案唯一待 run04 对 golden 布局验证的算术 (实测
 *         出处律, 先验证后落笔), 回填前 paged 帧 repack 在 arm 拍判
 *         GEOM_ZERO (映射 0x11) -> S_PPPW fail-fast, run03 cyc 144484
 *         型静默活锁消除、错误可见 (错误不静默律); 不落任何猜测算术.
 *       * 回退成对律 (设计件 §7, 仅注释留档不动结构): D1/D2 互为必要
 *         同修亦成对回退 -- D1 单退 = rp_arm_r 输出恒 0; D2 单退 =
 *         恢复 if(ppu_done) 电平判据 + 看门狗电平刷新同步回退.
 *   - V3.4-R160 (2026-10-26) : candidate-only unique issuer arm,
 *         latched producer geometry, local epoch, and independent
 *         read-only m04 glue path.  Repack/y_scatter remain untouched.
 *   - V3.5 (2026-10-28) : locked epoch_ybase distribution, reset-only
 *         hardware byte/AW/W/B accounts, commit fence and done gating.
 *   - V3.6-EngineClosure (2026-10-28) by LSL : Accepted rejected/recovery
 *         flow, checked bind/ARN/window/segment routes, 6-bit keys, 16-bit
 *         progress, 48-bit layouts, dense/epoch status, and RP commit fences.
 *   - V3.7-EngineDeepening (2026-10-28) by LSL : Phase-local SPPF emit/enqueue
 *         accounting, retained producer/repack commits, and RP event guards.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_intra_axi_top_v3 (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- passthrough: per-conv config + frame control (see intra top) --
    input  wire [9:0]  cfg_nb        ,
    input  wire [5:0]  cfg_rc        ,
    input  wire [3:0]  cfg_ns        ,
    input  wire [1:0]  cfg_nseg      ,
    input  wire [10:0] cfg_s0_k      ,
    input  wire [7:0]  cfg_s0_jc     ,
    input  wire [1:0]  cfg_s0_g      ,
    input  wire [31:0] cfg_stride    ,
    input  wire [31:0] cfg_obuf      ,
    input  wire [31:0] cfg_ybase     ,
    input  wire        cfg_overlap   ,
    input  wire [4:0]  cfg_nconv     ,
    input  wire [15:0] cfg_ic        ,
    input  wire [15:0] cfg_h         ,
    input  wire [15:0] cfg_w         ,
    input  wire [3:0]  cfg_kh        ,
    input  wire [3:0]  cfg_kw        ,
    input  wire [3:0]  cfg_sh        ,
    input  wire [3:0]  cfg_sw        ,
    input  wire [3:0]  cfg_ph        ,
    input  wire [3:0]  cfg_pw        ,
    input  wire        cfg_first      ,
    input  wire        cfg_law_fetch  ,
    input  wire [31:0] cfg_xbase     ,
    input  wire [31:0] cfg_wbase     ,
    input  wire [31:0] cfg_slab      ,
    input  wire [31:0] cfg_rc_stride ,
    input  wire [31:0] cfg_oc_stride ,
    input  wire [7:0]  cfg_oc        ,
    input  wire [15:0] cfg_chain_mask,   // M10.1 ABI v2.1 (CSR 0x58)
    input  wire [3:0]  cfg_nedge     ,   // 2b: CHAIN_NEDGE (0 = v1 mode)
    input  wire [63:0] cfg_edge_node ,   // 2b: 8 x consumer_idx
    input  wire [63:0] cfg_edge_prod ,   // 2d: 8 x producer field (0=adj)
    input  wire [127:0] cfg_edge_win ,   // 2b: 8 x window_size
    input  wire [639:0] cfg_join_tab ,   // 5b: 20-word join-region table
    input  wire        cfg_chain_rel ,   // 2e: CHAIN_REL mode bit (CSR 0xE0)
    input  wire [15:0] cfg_up2x      ,   // 5b: CHAIN_UP2X bitmap (CSR 0xDE)
    input  wire [2:0]  cfg_schedule_page,
    input  wire [5:0]  cfg_gconv_base,
    input  wire        cfg_hbuf_restart,
    output wire [31:0] s2l_cnt       ,   // 2e: CHAIN_S2L_CNT (CSR 0xE4)
    output wire [31:0] skew_max      ,   // 2e: CHAIN_SKEW_MAX (CSR 0xE8)
    output wire [511:0] hb_dbg       ,   // r7 debug aperture (cursor 0xF8/0xFC)
    // ---- v2.3 (M10.2 m8): PPP table + three-line handshake ----
    input  wire [255:0] cfg_ppp_tab  ,   // CSR 8x32b PPP segment table
    input  wire [47:0]  cfg_layout_id,   // CSR 16 conv x 3b layout vector
    input  wire [7:0]   frame_gen    ,   // CSR doorbell-latched generation
    output wire         ppu_start    ,   // -> PPU walker PL entry (pulse)
    output wire [17:0]  ppu_start_payload, // {gen, seg_idx, desc_idx}
    input  wire         ppu_done     ,   // walker arbiter verdict pulse
    input  wire         ppu_done_abort,  // 1 = token/engine failure
    input  wire [7:0]   ppu_done_err ,   // abort err code (with pulse)
    input  wire [6:0]   ppu_desc_count,  // PPU island loaded-DESC count
    input  wire         tr_token_latch,  // G2: CSR frame_token doorbell pulse
    input  wire        start         ,
    input  wire        accept_normal ,
    input  wire        accept_rejected_frame,
    input  wire        recovery_accept,
    input  wire [1:0]  accepted_start_mode,
    input  wire        start_paged   ,
    input  wire [31:0] tmo_max_w     ,
    output wire [31:0] m03_b_timeout_limit_o,
    input  wire        pg_win_rdy_i  ,
    input  wire        hbuf_start    ,
    input  wire [4:0]  hbuf_nconv    ,
    input  wire [3:0]  hbuf_nedge    ,
    input  wire        hbuf_segmented_mode,
    output wire        cfg_prequal_ok,
    output wire        nonlocal_cfg_prequal_ok,
    output wire        engine_quiescent,
    output wire        epoch_invalid_o,
    output wire        sppf_pending_empty,
    output wire        sppf_prequal_ok,
    output wire        ybase_prequal_ok,
    output wire        nonlocal_error_start_block,
    output wire        local_reject_now,
    output wire [2:0]  local_reject_flags,
    output wire        normal_done   ,
    output wire        rejected_done ,
    output wire        dense_addr_err_o,
    output wire        bind_done_o   ,
    output wire        bind_err_o    ,
    output wire        bind_ready_o  ,
    output wire        execution_enable_o,
    output wire        rearm_ovf_o   ,
    output wire        busy          ,
    output wire        done          ,
    output wire [7:0]  err           ,
    output wire [15:0] progress_blk  ,
    output reg  [31:0] epoch_ybase_q ,
    output reg         epoch_ybase_valid,
    output reg         epoch_ybase_fault,
    output reg  [31:0] epoch_native_enqueue_bytes,
    output reg  [31:0] merged_enqueue_bytes,
    output reg  [31:0] axi_w_accepted_bytes,
    output reg  [31:0] aw_accepted_txns,
    output reg  [31:0] w_accepted_txns,
    output reg  [31:0] b_returned_txns,
    output reg  [31:0] b_okay_txns,
    output reg  [31:0] b_bad_txns,
    output reg  [1:0]  axi_w_pending_txns,
    output reg  [1:0]  b_debt,
    output reg         axi_account_sticky,
    output wire        axi_epoch_invalid,
    output wire        axi_fifo_overflow_sticky,
    output wire        axi_b_timeout_sticky,
    output wire        axi_bresp_error_sticky,
    output wire        rp_skid_overflow_sticky,
    output wire        hw_axi_commit_fence,
    // ---- ROM read ports (plan faces, TB/board blob BRAM) ----
    // r12 widths (2026-10-21, build-line widening duty): pctl 14b / strip
    // 11b / lut 15b / cv 6b (R63 slot-doubling 8832/1104/17664/69) + the
    // NEW cv_slot[6:0] passthrough into the issuer (M11a froze this module
    // at r10 widths -- the leaf issuer is v2.4-widened already, every hop
    // between must carry the full width or the high bits truncate).
    output wire [13:0] pctl_addr     ,
    input  wire [95:0] pctl_data     ,
    output wire [10:0] strip_addr    ,
    input  wire [20:0] strip_data    ,
    output wire [14:0] lut_addr      ,
    input  wire [7:0]  lut_data      ,
    output wire [6:0]  cv_addr       ,
    input  wire [255:0] cv_iss       ,
    input  wire [105:0] cv_geo       ,
    // 2a: m9_bm_wlay widened 136->168 (ch_stride tail)
    input  wire [167:0] cv_wlay      ,
    input  wire [6:0]  cv_slot       ,   // r12: per-conv plan slot base (D4)
    output wire [5:0]  conv_idx      ,
    // ---- v2.5 (C3 r12 B 裁定): M11a page face pass-through.  仅 CSR<->
    //      issuer 环跨模块（5 口）；pg_adv rearm / rp_start+rp_done repack
    //      环 / pg_anchor trace 锚点均在 u_dut 内部或本层内部消化，
    //      不出端口（最小作用域律）。 --
    input  wire [2:0]  cfg_npages    ,
    input  wire        cfg_pgauto    ,
    input  wire [31:0] pg_desc       ,
    output wire [2:0]  page_r        ,
    output wire        pg_pref       ,
    output wire [31:0] cnt_beats     ,
    output wire [31:0] cnt_stall     ,
    output wire [15:0] cnt_csr_w     ,
    output wire [19:0] cnt_y_bytes   ,
    output wire [9:0]  cnt_y_blocks  ,
    output wire [31:0] cnt_chain_bytes,  // M10.1: HBUF delivered bytes (0x5C)
    // ---- AXI32 HP0 read master: x window ----
    output wire [31:0] m0_araddr     ,
    output wire [3:0]  m0_arlen      ,
    output wire        m0_arvalid    ,
    input  wire        m0_arready    ,
    input  wire [63:0] m0_rdata      ,
    input  wire [1:0]  m0_rresp      ,
    input  wire        m0_rvalid     ,
    input  wire        m0_rlast      ,
    output wire        m0_rready     ,
    // ---- AXI32 HP3 read master: w feeder ----
    output wire [31:0] m1_araddr     ,
    output wire [3:0]  m1_arlen      ,
    output wire        m1_arvalid    ,
    input  wire        m1_arready    ,
    input  wire [63:0] m1_rdata      ,
    input  wire [1:0]  m1_rresp      ,
    input  wire        m1_rvalid     ,
    input  wire        m1_rlast      ,
    output wire        m1_rready     ,
    // ---- AXI32 HP0 write master: y scatter ----
    output wire [31:0] m2_awaddr     ,
    output wire [3:0]  m2_awlen      ,
    output wire        m2_awvalid    ,
    input  wire        m2_awready    ,
    output wire [63:0] m2_wdata      ,
    output wire [7:0]  m2_wstrb      ,
    output wire        m2_wvalid     ,
    input  wire        m2_wready     ,
    input  wire [1:0]  m2_bresp      ,
    input  wire        m2_bvalid     ,
    output wire        m2_bready,
    input  wire        tr_we,
    input  wire [11:0] tr_waddr,
    input  wire [31:0] tr_wdata,
    input  wire [11:0] tr_raddr,
    output wire [31:0] tr_rdata,
    output wire        tr_ring_ovr,
    input  wire        tr_steady_end,
    output wire        tr_last_compute,
    // ---- V3 spec 2.5: H2' array-active tap (observe-only passthrough) --
    output wire        tr_array_active
`ifdef M11_REPACK
    ,output wire [31:0] m4_araddr
    ,output wire [3:0]  m4_arlen
    ,output wire        m4_arvalid
    ,input  wire        m4_arready
    ,input  wire [63:0] m4_rdata
    ,input  wire [1:0]  m4_rresp
    ,input  wire        m4_rvalid
    ,input  wire        m4_rlast
    ,output wire        m4_rready
`endif
);

    // ---- line faces between V3 cores and adapters ----
    wire [31:0] x_raddr_line, w_paddr_line;
    wire        x_rreq_line,  w_preq_line;
    wire [63:0] x_rdata_line, w_pdata_line;
    wire        x_rvalid_line, w_pvalid_line;
    // M10.1 V3.1: DDR-side line response wires (u_xrd) + merged face to
    // the x window (DDR has merge priority; the two sources can never
    // be active together by the serve-gate law, see m9_hbuf_ctrl).
    wire [63:0] x_rdata_ddr;
    wire        x_rvalid_ddr;

    // ---- M10.1: layer_chain handoff (SPEC v1.1 / ABI v2.1 ch.10) ----
    wire [5:0]  conv_idx_w;   // global 6-bit consumer key
    wire        dut_busy, dut_done;
    wire [7:0]  dut_err;
    wire        eng_epoch_invalid;
    wire        eng_bind_ready;
    wire        eng_execution_enable;
    wire        eng_sppf_pending_empty;
    wire        eng_sppf_prequal_ok;
    wire        eng_sppf_mode;
    wire        eng_paged_mode;
    wire        eng_conv_start;
    wire        eng_face_close;
    wire        eng_scatter_verified_close;
    wire        eng_producer_arm;
    wire [31:0] iss_tmo_max_w;
    wire        chain_any, chain_sel;
    wire [63:0] hb_data;
    wire        hb_valid;
    wire        hb_ovf;
    wire        hb_cfg;         // 2b hbuf-side E_CHAIN_CFG report

    // E_CHAIN_MASK=10 legality: bit0 / multi-bit (v1 single-chain) /
    // non-walk.  E_CHAIN_CFG=12 legality (2b): duplicate consumer_idx /
    // node==0 / node>=nconv / NEDGE>NSLOT(8) / window==0 / window>32KB.
    // 2d additions: explicit producer field (CSR 0xD8[15:8], 0=adjacent
    // fallback) must satisfy producer < consumer (walk-order law; catches
    // self-loops and forward refs) and producer < nconv; edges sharing an
    // effective producer must carry the IDENTICAL window (one shared slot
    // = one capture, spec §5.1).  Rejection happens HERE (adapter), not
    // in the frozen issuer: engine start is suppressed and done is
    // synthesized.
    wire [15:0] cm          = cfg_chain_mask;
    wire        cm_multibit = |(cm & (cm - 16'd1));
    wire        mask_err_now = cm[0] |
                    ((|cm) & ((cfg_nconv < 5'd2) | cm_multibit));
    // 2b/2d edge-table legality mirror: evaluated on the RAW CSR face at
    // the start edge (engine gating needs it combinationally at start;
    // m9_hbuf_ctrl re-checks the sampled regs and reports the same
    // sticky cfg_err -- the RTL-level probe face, OR'd into err below).
    integer mi, mj, mk;
    reg cfg_bad;
    // Full-field global-key mirror.  The HBUF checked builder remains the
    // authority; these functions prevent the adapter prequalifier from
    // truncating node/producer fields or adding the base twice.
    function [8:0] consumer9;
        input [7:0] node;
        begin
            consumer9 = {3'd0, cfg_gconv_base} + {1'b0, node};
        end
    endfunction
    function [8:0] producer9;
        input [7:0] node;
        input [7:0] pfield;
        begin
            producer9 = (pfield != 8'd0) ? ({1'b0, pfield} - 9'd1)
                                         : (consumer9(node) - 9'd1);
        end
    endfunction
    function [5:0] eff_prod;
        input [7:0] node;
        input [7:0] pfield;
        reg [8:0] producer9_full;
        begin
            producer9_full = producer9(node, pfield);
            eff_prod = producer9_full[5:0];
        end
    endfunction
    always @(*) begin
        cfg_bad = (cfg_nedge != 4'd0) && (cfg_nedge > 4'd8);
        for (mi = 0; mi < 8; mi = mi + 1) begin
            if ((cfg_nedge != 4'd0) && (mi < cfg_nedge)) begin
                if ((consumer9(cfg_edge_node[mi*8 +: 8]) >=
                     ({3'd0, cfg_gconv_base} + {4'd0, cfg_nconv})) ||
                    (consumer9(cfg_edge_node[mi*8 +: 8]) > 9'd62) ||
                    (producer9(cfg_edge_node[mi*8 +: 8],
                               cfg_edge_prod[mi*8 +: 8]) >=
                     consumer9(cfg_edge_node[mi*8 +: 8])) ||
                    (producer9(cfg_edge_node[mi*8 +: 8],
                               cfg_edge_prod[mi*8 +: 8]) > 9'd62))
                    cfg_bad = 1'b1;
                if ((cfg_edge_win[mi*16 +: 16] == 16'd0) ||
                    (cfg_edge_win[mi*16 +: 16] > 16'd32768))
                    cfg_bad = 1'b1;
                // 5b/5d (M10.5): multi-edge consumer (concat join) RUN
                // law -- SAME generalization as the hbuf legality
                // (delta #5): a consumer may occupy a RUN of >=1
                // consecutive edges (run >=2 = join group).  (a) the
                // same node reappearing after a DIFFERENT node's edge
                // (two runs) raises cfg_bad (and join_bad_ad below ->
                // E_CHAIN_JOIN=13); (b) within a run all effective
                // producers must be DISTINCT -- a same-producer pair
                // keeps the 2d malformed-dup semantics (E_CHAIN_CFG=12,
                // C02b cfg_dup baseline preserved; the old adjacent-pair
                // test is the N=2 case).
                for (mj = mi + 1; mj < 8; mj = mj + 1)
                    if ((mj < cfg_nedge) &&
                        (cfg_edge_node[mj*8 +: 8]
                         == cfg_edge_node[mi*8 +: 8])) begin
                        for (mk = mi + 1; mk < mj; mk = mk + 1)
                            if ((mk < cfg_nedge) &&
                                (cfg_edge_node[mk*8 +: 8]
                                 != cfg_edge_node[mi*8 +: 8]))
                                cfg_bad = 1'b1;
                        if (eff_prod(cfg_edge_node[mi*8 +: 8],
                                     cfg_edge_prod[mi*8 +: 8])
                            == eff_prod(cfg_edge_node[mj*8 +: 8],
                                        cfg_edge_prod[mj*8 +: 8]))
                            cfg_bad = 1'b1;
                    end
            end
        end
        // 2d: shared-producer single-window law
        for (mi = 0; mi < 8; mi = mi + 1)
            if ((cfg_nedge != 4'd0) && (mi < cfg_nedge))
                for (mj = mi + 1; mj < 8; mj = mj + 1)
                    if ((mj < cfg_nedge) &&
                        (eff_prod(cfg_edge_node[mi*8 +: 8],
                                  cfg_edge_prod[mi*8 +: 8])
                         == eff_prod(cfg_edge_node[mj*8 +: 8],
                                     cfg_edge_prod[mj*8 +: 8])) &&
                        (cfg_edge_win[mi*16 +: 16]
                         != cfg_edge_win[mj*16 +: 16]))
                        cfg_bad = 1'b1;
    end
    wire        cfg_err_now = cfg_bad;
    // 5b/5d: adapter-side malformed-join detect (same-node edge in two
    // runs = non-adjacent duplicate consumer).  Mirrors the hbuf
    // join_cfg_err semantics so the reject frame reports
    // E_CHAIN_JOIN=13 even though eng_start never fires.  5d: the
    // contiguity test generalizes to N-edge runs (the hbuf delta #5
    // mirror -- a same-node run member at any distance is legal iff
    // every position between them is the same node).
    reg         join_bad_ad;
    always @(*) begin
        join_bad_ad = 1'b0;
        for (mi = 0; mi < 8; mi = mi + 1)
            if ((cfg_nedge != 4'd0) && (mi < cfg_nedge))
                for (mj = mi + 1; mj < 8; mj = mj + 1)
                    if ((mj < cfg_nedge) &&
                        (cfg_edge_node[mj*8 +: 8]
                         == cfg_edge_node[mi*8 +: 8]))
                        for (mk = mi + 1; mk < mj; mk = mk + 1)
                            if ((mk < cfg_nedge) &&
                                (cfg_edge_node[mk*8 +: 8]
                                 != cfg_edge_node[mi*8 +: 8]))
                                join_bad_ad = 1'b1;
    end
    reg         mask_err_latch;
    reg         cfg_err_latch;
    reg         join_err_latch;
    reg         rej_done_l;
    reg  [4:0]  rej_done_c;
    reg         rejected_frame_active_q;
    reg         rejected_done_seen_q;
    reg         recoverable_reject_q;
    reg         rejected_mode_manual_q;
    wire        rej_now = mask_err_now | cfg_err_now | join_bad_ad;
    wire        sppf_manual_now = (accepted_start_mode == 2'd2);
    wire        legacy_local_reject_now = rej_now && !sppf_manual_now;
    wire        ybase_change_now = epoch_ybase_valid &&
                                   (cfg_ybase != epoch_ybase_q);
    wire        eng_start  = accept_normal & ~rej_now &
                             ~ybase_change_now & ~epoch_ybase_fault &
                             ~axi_account_sticky;
    wire [31:0] ybase_eff = epoch_ybase_valid ? epoch_ybase_q : cfg_ybase;
    reg         normal_done_pending;
    reg         normal_close_q;
    wire        hb_bind_done;
    wire        hb_bind_err;
    wire        hb_bind_ready;
    wire        hb_arn_ack;
    wire        hb_arn_sealed;
    wire        hb_rearm_ovf;
    wire        iss_arn_req;
    wire [2:0]  iss_arn_page;
    wire [5:0]  iss_arn_gconv;
    wire [4:0]  iss_pg_nconv_w;
    wire        rp_fault_any;
    wire        rp_outstanding_any;
    wire        iss_hbuf_start_w;
    wire [4:0]  iss_hbuf_nconv_w;
    wire [3:0]  iss_hbuf_nedge_w;
    wire        iss_hbuf_segmented_mode_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_ybase_q <= 32'd0;
            epoch_ybase_valid <= 1'b0;
            epoch_ybase_fault <= 1'b0;
        end else begin
            if (accept_normal && start_paged && !epoch_ybase_valid) begin
                epoch_ybase_q <= cfg_ybase;
                epoch_ybase_valid <= 1'b1;
            end
            if (ybase_change_now) begin
                epoch_ybase_fault <= 1'b1;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_err_latch <= 1'b0;
            cfg_err_latch <= 1'b0;
            join_err_latch <= 1'b0;
            rej_done_l <= 1'b0;
            rej_done_c <= 5'd0;
            rejected_frame_active_q <= 1'b0;
            rejected_done_seen_q <= 1'b0;
            recoverable_reject_q <= 1'b0;
            rejected_mode_manual_q <= 1'b0;
        end else if (accept_rejected_frame) begin
            mask_err_latch <= mask_err_now;
            cfg_err_latch <= cfg_err_now;
            join_err_latch <= join_bad_ad;
            rej_done_l <= 1'b0;
            rej_done_c <= 5'd0;
            rejected_frame_active_q <= 1'b1;
            rejected_done_seen_q <= 1'b0;
            recoverable_reject_q <= 1'b0;
            rejected_mode_manual_q <= sppf_manual_now;
        end else if (recovery_accept) begin
            mask_err_latch <= 1'b0;
            cfg_err_latch <= 1'b0;
            join_err_latch <= 1'b0;
            rej_done_l <= 1'b0;
            rej_done_c <= 5'd0;
            rejected_frame_active_q <= 1'b0;
            rejected_done_seen_q <= 1'b0;
            recoverable_reject_q <= 1'b0;
            rejected_mode_manual_q <= 1'b0;
        end else begin
            if (rejected_frame_active_q && !rej_done_l) begin
                if (rej_done_c == 5'd16) begin
                    rej_done_l <= 1'b1;
                end else begin
                    rej_done_c <= rej_done_c + 5'd1;
                end
            end
            if (rejected_frame_active_q && rej_done_l &&
                !rejected_done_seen_q) begin
                rejected_done_seen_q <= 1'b1;
                recoverable_reject_q <= !rejected_mode_manual_q;
            end
        end
    end

    // DDR line-queue outstanding counter (in-order merge guard: a
    // chained HBUF response is served only while u_xrd is drained).
    reg [4:0]  ddr_q;
    wire       x_lreq_ddr = x_rreq_line & ~chain_sel;
    wire       x_lreq_hbuf = x_rreq_line & chain_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ddr_q <= 5'd0;
        else if (accept_normal) ddr_q <= 5'd0;
        else case ({x_lreq_ddr, x_rvalid_ddr})
            2'b10: ddr_q <= ddr_q + 5'd1;
            2'b01: ddr_q <= ddr_q - 5'd1;
            default: ddr_q <= ddr_q;
        endcase
    end
    wire ddr_q_empty = (ddr_q == 5'd0);

    assign busy  = (dut_busy && !dut_done) |
                   (rejected_frame_active_q && !rej_done_l);
    assign done  = normal_close_q |
                   (rej_done_l && rejected_frame_active_q);
    wire        hb_join_cfg;      // 5b: E_CHAIN_JOIN=13 sticky
    wire        ywr_err;
    wire [7:0]  ywr_err_code;
    assign err   = dut_err
                 | (ywr_err       ? ywr_err_code : 8'd0)
                 | (mask_err_latch ? 8'd10 : 8'd0)   // E_CHAIN_MASK
                 | (hb_ovf         ? 8'd11 : 8'd0)   // E_CHAIN_OVF
                 | ((cfg_err_latch | hb_cfg)
                                   ? 8'd12 : 8'd0)   // E_CHAIN_CFG
                 | ((hb_join_cfg | join_err_latch)
                                   ? 8'd13 : 8'd0);  // E_CHAIN_JOIN (5b)
    // y scatter byte write face unchanged (m9_axi_wr sibling)
    wire [31:0] yaddr;
    wire        yreq;
    wire [7:0]  ywdata;
    wire [31:0] ywr_addr;
    wire        ywr_req;
    wire [7:0]  ywr_data;
    wire        rp_native_req;
    wire        glue_skid_empty;
    wire        rp_skid_overflow_sticky_int;
    wire        ywr_empty;
    wire        ywr_b_waiting;
    wire        x_ddr_gap, w_ddr_gap, y_fifo_full;
    wire        tr_store_active = m2_wvalid && m2_wready;

`ifdef M11_REPACK
    // ================ M11 repack merge (SPEC_m11_repack.md §7) =========
    // All of the following exists ONLY under M11_REPACK.  Without the
    // define the r10 datapath (yaddr/yreq/ywdata straight into u_ywr) is
    // bit-identical.
    //
    // contact #2 config face -- r11 inert carrier base (geometry/src/dst
    // tie-offs UNCHANGED): the dst-window derivation is the ONE deferred
    // arithmetic (设计件 §1, 实测出处律 -- validated against the golden
    // layout in run04, then back-annotated into SPEC v3 新章《M11 repack
    // 配置面闭合与判决锁存 (D1/D2 同修)》(2026-10-26 立项, 数字待 run04
    // 回填)).  D1 (V3.3-D1D2) arms u_repack from the doorbell chain
    // (rp_arm_r, declared outside this define with the always-present rp
    // nets); glue keeps rp_arm = 1'b0 (legacy 惰性载体).  With geometry
    // tied 0 a paged arm is judged RP_ERR_GEOM_ZERO -> mapped 0x11 ->
    // issuer S_PPPW fail-fast (visible error, no silent hang).  ABI/CAP0
    // untouched (identity law, cap0=4d390230).
    wire [31:0] rp_src_base;
    wire [31:0] rp_dst_base;
    wire [15:0] rp_c;
    wire [15:0] rp_h;
    wire [15:0] rp_w;
    wire [15:0] rp_vc;
    wire [31:0] rp_ypitch;
    wire [15:0] rp_nb;
    wire        rp_arm_w;
    wire        rp_pf_abort_w;
    wire        rp_sc_done_w;
    wire [9:0]  rp_sc_blocks_w;
    wire        rp_pf_fault_w;
    wire        rp_pf_hang_w;
    wire        rp_warm_w;
    wire [23:0] rp_bytes_w;
    wire        rp_commit_req_w;
    reg         producer_commit_q;
    reg         repack_done_seen_q;
    wire        repack_commit_w;
    reg         repack_commit_q;
    reg  [31:0] producer_native_emit_bytes_q;
    reg  [31:0] producer_native_enqueue_bytes_q;
    reg  [31:0] repack_native_emit_bytes_q;
    reg  [31:0] repack_native_enqueue_bytes_q;
    reg         producer_phase_active_q;
    reg         rp_epoch_active_q;
    reg         rp_start_seen_q;
    reg         native_rp_start_seen_q;
    reg         sppf_phase_error_q;
    // contact #3 seal nets: sc_done straight off u_dut's u_ys (exported
    // under the same define); y_blocks is the existing D4 ledger output.
    wire        sc_done_w;
    // repack <-> glue nets
    wire        rp_start_w, rp_busy_w;
    wire [31:0] rp_raddr, rp_waddr;
    wire        rp_rreq,  rp_wreq;
    wire [7:0]  rp_rdata, rp_wdata;
    // contact #6 merged byte write face into u_ywr (hbuf keeps the
    // scatter-only yaddr/yreq/ywdata tap above)
    wire [31:0] yaddr_m;
    wire        yreq_m;
    wire [7:0]  ywdata_m;
    assign ywr_addr = yaddr_m;
    assign ywr_req = yreq_m;
    assign ywr_data = ywdata_m;
    assign rp_native_req = rp_wreq;
`else
    assign ywr_addr = yaddr;
    assign ywr_req = yreq;
    assign ywr_data = ywdata;
    assign rp_native_req = 1'b0;
    assign glue_skid_empty = 1'b1;
    assign rp_skid_overflow_sticky_int = 1'b0;
    assign rp_fault_any = 1'b0;
    assign rp_outstanding_any = 1'b0;
`endif // M11_REPACK
    assign rp_skid_overflow_sticky = rp_skid_overflow_sticky_int;
    // v2.5 (r12 B 裁定): issuer page face internal nets.  DECLARED OUTSIDE
    // the M11_REPACK region on purpose: u_hbuf (L591) and u_iss (L670)
    // consume them UNCONDITIONALLY — inside the ifdef the elab without
    // M11_REPACK degrades them to implicit 1-bit scalars (VRFC 10-3091,
    // C1 rerun evidence probe_w5) and the hbuf rearm base silently
    // truncates to {5'b0,bit0}.  rp 环与 rearm 环均不出本模块（最小作用域
    // 律）；M11_REPACK 未定义时 iss_rp_done_w 浮空，issuer 侧 z 守卫
    // rp_done_g=1 良性（与截断期同语义）。
    wire        iss_rp_start_w;   // u_dut.rp_start_o（paged SPPF 锚）
    wire        iss_rp_done_w;    // u_repack.rp_done -> u_dut.rp_done_i
    // D1 err 面 (V3.3-D1D2): u_repack err 口脱空挂解除后的新内部网.
    // 声明在 ifdef 外, 与 iss_rp_done_w 同一律 (M11_REPACK 未定义时浮空,
    // issuer 侧 z 守卫 rp_err_lvl=0 良性退化).
    wire        iss_rp_err_w;     // u_repack.rp_err (粘着级) -> u_dut.rp_err_i
    wire [7:0]  iss_rp_err_code_w;// u_repack.rp_err_code (原生码)
    wire [7:0]  iss_rp_err_mapped;// 连接点重映射码 -> u_dut.rp_err_code_i
    wire        iss_pg_adv_w;     // u_dut.pg_adv -> u_hbuf rearm
    wire [5:0]  iss_pg_base_w;
    wire [2:0]  iss_pg_nedge_w;
    wire        rp_start_m;       // glue legacy FF 与 issuer 锚的合并启动
`ifdef M11_REPACK
    assign rp_fault_any = iss_rp_err_w || rp_pf_fault_w || rp_pf_hang_w ||
                          rp_skid_overflow_sticky_int || sppf_phase_error_q;
    assign rp_outstanding_any = rp_busy_w || iss_rp_start_w ||
                                rp_commit_req_w;
`endif

    // M10.1 V3.1: HBUF handoff controller (declarations above; the
    // y-address tap wires exist only from here)
    //
    // M10.1-v2 chain base-translation law (2026-10-14, C01b board OVF
    // root cause): the frozen issuer emits chained X reads in the X-arena
    // address space (cfg_xbase + plan offset), but the HBUF capture
    // window lives in the Y-arena space (slot_base = cfg_ybase + the
    // SAME plan offset, in-place chain law).  TB canon co-locates the
    // arenas (xbase==ybase==0, plan_base resets to 0) so the two spaces
    // coincide; the board driver uses split arenas (x@0x20000000,
    // y@0x22000000) -> every chained read fell outside the slot window
    // and E_CHAIN_OVF fired.  Translate chained reads into Y space BEFORE
    // the window check.  The base delta is 32KB-aligned (producer-slot
    // alignment law), so window bits [31:15] map 1:1 and the BMG index
    // bits [14:3] are bit-identical.  DDR-path reads are never
    // translated (the mux already guarantees lr_* carries chained
    // requests only).  plan-internal offset mismatches (T2/T3 classes)
    // are unaffected: the translation is a per-frame constant shift.
    // 5b (M10.5): join-region piecewise translation.  A concat consumer's
    // X input spans TWO producer slot windows (A/B); the legacy single
    // affine shift (in-place law) cannot map it.  cfg_join_tab carries 4
    // regions x 5 words {xj_lo, xj_hi, split, yA_base, yB_base} in X-plan
    // offset space (xoff = addr - cfg_xbase).  A chained read inside a
    // region maps off<split -> yA_base+off, else yB_base+(off-split).
    // Region match is priority-ordered (region 0 wins; the compiler must
    // not emit overlapping regions).  Reads outside every region keep the
    // v2 in-place affine law unchanged.  Chained requests only (the
    // lr_req path is already gated by chain_sel upstream).
    wire [31:0] xoff = x_raddr_line - cfg_xbase;
    wire [31:0] jn_lo0  = cfg_join_tab[ 0*32 +: 32];
    wire [31:0] jn_hi0  = cfg_join_tab[ 1*32 +: 32];
    wire [31:0] jn_sp0  = cfg_join_tab[ 2*32 +: 32];
    wire [31:0] jn_ya0  = cfg_join_tab[ 3*32 +: 32];
    wire [31:0] jn_yb0  = cfg_join_tab[ 4*32 +: 32];
    wire [31:0] jn_lo1  = cfg_join_tab[ 5*32 +: 32];
    wire [31:0] jn_hi1  = cfg_join_tab[ 6*32 +: 32];
    wire [31:0] jn_sp1  = cfg_join_tab[ 7*32 +: 32];
    wire [31:0] jn_ya1  = cfg_join_tab[ 8*32 +: 32];
    wire [31:0] jn_yb1  = cfg_join_tab[ 9*32 +: 32];
    wire [31:0] jn_lo2  = cfg_join_tab[10*32 +: 32];
    wire [31:0] jn_hi2  = cfg_join_tab[11*32 +: 32];
    wire [31:0] jn_sp2  = cfg_join_tab[12*32 +: 32];
    wire [31:0] jn_ya2  = cfg_join_tab[13*32 +: 32];
    wire [31:0] jn_yb2  = cfg_join_tab[14*32 +: 32];
    wire [31:0] jn_lo3  = cfg_join_tab[15*32 +: 32];
    wire [31:0] jn_hi3  = cfg_join_tab[16*32 +: 32];
    wire [31:0] jn_sp3  = cfg_join_tab[17*32 +: 32];
    wire [31:0] jn_ya3  = cfg_join_tab[18*32 +: 32];
    wire [31:0] jn_yb3  = cfg_join_tab[19*32 +: 32];
    // 5d timing fix round 2 (Track C, 2026-10-15): the per-read join
    // translation carried THREE serial 32-bit carry stages
    // (joff = xoff-lo; ya+joff | yb+(joff-sp)) on the raddr_line ->
    // q_addr critical path (33 logic levels, 19 CARRY4, wns -0.526).
    // Algebra: ya+joff == xoff+(ya-lo); yb+(joff-sp) == xoff+(yb-lo-sp)
    //   (5e lo-law fix 10-15: Track C's original comment dropped the lo
    //   term in the B leg -- yb+(joff-sp) with joff=xoff-lo equals
    //   xoff+(yb-lo-sp), NOT xoff+(yb-sp).  All pre-5e batches had
    //   lo==0 (J01/J04 canon: producer A at page offset 0), which masked
    //   it; NECK_B3 (lo=0x900) is the first lo!=0 frame.  xsim caught it:
    //   B-leg reads translated 0xD00 -> 0x1600, OVF past both windows.)
    // joff<sp <=> xoff<lo+sp.  The three constants per region are
    // CSR-stable within a frame, so register them (free-running sample
    // of the comb -- join_tab is written long before the frame doorbell,
    // so one-cycle settle is safe; BYTE-exact same arithmetic mod 2^32).
    // Per-read path drops to: xoff sub -> region match -> K mux ->
    // ONE add.  Same law applied to the affine leg (ybase-xbase).
    // 10-16 r9 fix (RUNBOOK_5d §9): the JOIN legs produced PLANE offsets
    // (ya-lo) while hbuf slot windows are ABSOLUTE Y addresses -- page
    // match failed 100% on the board (serve_miss=24576=chain/8, CHAIN
    // exact = every pop took the !e_in_win zero-response arm).  TB canon
    // co-located arena (xbase=ybase=0) masked it; third case of the
    // "zero-base canon hides missing-base" class.  Fold cfg_ybase into
    // the registered constants (same multi-cycle free-running sample,
    // read path still ONE add; mod-2^32).  ybase=0: bit-identical netlist
    // (all existing ladders zero-disturbance); ybase!=0: board fixed.
    reg [31:0] jn_ka [0:3];      // yA - lo + ybase (absolute)
    reg [31:0] jn_kb [0:3];      // yB - (lo + split) + ybase   (5e lo-law)
    reg [31:0] jn_sphi [0:3];    // lo + split (j_a threshold, xoff space)
    reg [31:0] aff_off;          // cfg_ybase - cfg_xbase
    always @(posedge clk) begin
        jn_ka[0]   <= jn_ya0 - jn_lo0 + ybase_eff;
        jn_kb[0]   <= jn_yb0 - (jn_lo0 + jn_sp0) + ybase_eff;
        jn_sphi[0] <= jn_lo0 + jn_sp0;
        jn_ka[1]   <= jn_ya1 - jn_lo1 + ybase_eff;
        jn_kb[1]   <= jn_yb1 - (jn_lo1 + jn_sp1) + ybase_eff;
        jn_sphi[1] <= jn_lo1 + jn_sp1;
        jn_ka[2]   <= jn_ya2 - jn_lo2 + ybase_eff;
        jn_kb[2]   <= jn_yb2 - (jn_lo2 + jn_sp2) + ybase_eff;
        jn_sphi[2] <= jn_lo2 + jn_sp2;
        jn_ka[3]   <= jn_ya3 - jn_lo3 + ybase_eff;
        jn_kb[3]   <= jn_yb3 - (jn_lo3 + jn_sp3) + ybase_eff;
        jn_sphi[3] <= jn_lo3 + jn_sp3;
        aff_off    <= ybase_eff - cfg_xbase;
    end
    wire m0 = (jn_hi0 > jn_lo0) && (xoff >= jn_lo0) && (xoff < jn_hi0);
    wire m1 = (jn_hi1 > jn_lo1) && (xoff >= jn_lo1) && (xoff < jn_hi1);
    wire m2 = (jn_hi2 > jn_lo2) && (xoff >= jn_lo2) && (xoff < jn_hi2);
    wire m3 = (jn_hi3 > jn_lo3) && (xoff >= jn_lo3) && (xoff < jn_hi3);
    wire [31:0] m_ka   = m0 ? jn_ka[0] : (m1 ? jn_ka[1] :
                         (m2 ? jn_ka[2] : jn_ka[3]));
    wire [31:0] m_kb   = m0 ? jn_kb[0] : (m1 ? jn_kb[1] :
                         (m2 ? jn_kb[2] : jn_kb[3]));
    wire [31:0] m_sphi = m0 ? jn_sphi[0] : (m1 ? jn_sphi[1] :
                         (m2 ? jn_sphi[2] : jn_sphi[3]));
    wire        in_join = m0 || m1 || m2 || m3;
    // Track C: joff<sp <=> xoff<lo+sp (registered sphi); one add total
    wire        j_a    = xoff < m_sphi;
    wire [31:0] join_addr = xoff + (j_a ? m_ka : m_kb);
    wire [31:0] hb_lr_addr = in_join ? join_addr
                                     : (x_raddr_line + aff_off);
`ifndef SYNTHESIS
    // 5e debug: chained-read translation tap (err=11 root-cause
    // instrumentation; guard = zero netlist impact).  Prints the first
    // few chained reads of the consumer conv plus EVERY chained read that
    // misses all join regions (the OVF class).
    integer dbg_n = 0;
    reg dbg_armed = 1'b0;
    always @(posedge clk) begin
        if (x_lreq_hbuf && chain_sel && conv_idx_w >= 5'd3) begin
            if (!dbg_armed && dbg_n < 40) begin
                dbg_n <= dbg_n + 1;
                $display("M9TR_DBG rd#%0d conv=%0d xline=%h xbase=%h ybase=%h xoff=%h inj=%b ja=%b hb=%h aff=%h r0={lo=%h hi=%h sp=%h ya=%h yb=%h}",
                         dbg_n, conv_idx_w, x_raddr_line, cfg_xbase,
                         cfg_ybase, xoff, in_join, j_a, hb_lr_addr, aff_off,
                         jn_lo0, jn_hi0, jn_sp0, jn_ya0, jn_yb0);
            end
            if (!in_join && !dbg_armed) begin
                dbg_armed <= 1'b1;
                $display("M9TR_DBG FIRST_NONJOIN t=%0t xline=%h xbase=%h xoff=%h aff=%h hb=%h",
                         $time, x_raddr_line, cfg_xbase, xoff, aff_off,
                         hb_lr_addr);
            end
        end
    end
`endif
    wire        hbuf_chain_go;
    wire [5:0]  iss_prod_conv;
    m9_hbuf_ctrl u_hbuf (
        .clk(clk), .rst_n(rst_n),
        .start(hbuf_start), .cfg_chain_mask(cfg_chain_mask),
        .cfg_nedge(hbuf_nedge), .edge_node(cfg_edge_node),
        .edge_prod(cfg_edge_prod),
        .edge_win(cfg_edge_win), .cfg_nconv(hbuf_nconv),
        .cfg_gconv_base(cfg_gconv_base),
        .hbuf_restart(cfg_hbuf_restart),
        .segmented_mode(hbuf_segmented_mode),
        .bind_done(hb_bind_done), .bind_err(hb_bind_err),
        .bind_ready(hb_bind_ready),
        .arn_req(iss_arn_req), .arn_gconv(iss_arn_gconv),
        .arn_ack(hb_arn_ack), .arn_sealed(hb_arn_sealed),
        .chain_any(chain_any), .chain_sel(chain_sel),
        .conv_idx(conv_idx_w), .prod_conv(iss_prod_conv),
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
        .lr_addr(hb_lr_addr), .lr_req(x_lreq_hbuf),
        .lr_data(hb_data), .lr_valid(hb_valid),
        .ddr_q_empty(ddr_q_empty),
        .cnt_chain_bytes(cnt_chain_bytes), .ovf_err(hb_ovf),
        .cfg_err(hb_cfg),
        .chain_go(hbuf_chain_go), .skew_max(skew_max),
        .join_cfg_err(hb_join_cfg),
        // v2.5 (r12 B 裁定): 页推进 rearm 真线（M11a SPEC §2.4 正典）
        .pg_adv(iss_pg_adv_w), .pg_base(iss_pg_base_w),
        .pg_nconv(iss_pg_nconv_w),
        .pg_nedge(iss_pg_nedge_w),
        .rearm_ovf(hb_rearm_ovf),
        .hb_dbg(hb_dbg_hbuf)
    );
    wire [511:0] hb_dbg_hbuf;
    wire [31:0] iss_dbg_dual_transition;
    wire [31:0] iss_dbg_last_face_close;
    assign hb_dbg = {iss_dbg_last_face_close, iss_dbg_dual_transition,
                     hb_dbg_hbuf[447:0]};

    // response merge: DDR responses pass through with priority; HBUF
    // responses fill the rest (mutually exclusive by the serve gate:
    // an HBUF entry is served only while the DDR queue is drained)
    assign x_rdata_line  = x_rvalid_ddr ? x_rdata_ddr : hb_data;
    assign x_rvalid_line = x_rvalid_ddr | hb_valid;
    assign conv_idx      = conv_idx_w;   // TB snoop face preserved

    // frame-end flush (level): hold from frame start until BOTH the
    // intra top is idle and the write master drained -- the write
    // master's busy covers its pending line (ln_cnt law), so the clear
    // below can only fire after the tail line landed.  A mid-frame
    // write-master busy dip never clears it (intra busy still high).
    reg         frm_started;
    reg         conv_flush_pending;
    wire        ywr_busy;
    wire        wr_flush = (frm_started & ~busy) | eng_face_close |
                           conv_flush_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frm_started       <= 1'b0;
            conv_flush_pending <= 1'b0;
        end else begin
            if (accept_normal)                  frm_started <= 1'b1;
            else if (frm_started & ~busy & ~ywr_busy) frm_started <= 1'b0;
            if (eng_face_close)                 conv_flush_pending <= 1'b1;
            else if (conv_flush_pending && ywr_empty) conv_flush_pending <= 1'b0;
        end
    end

    m9_intra_top_v3 u_dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_nb(cfg_nb), .cfg_rc(cfg_rc), .cfg_ns(cfg_ns),
        .cfg_nseg(cfg_nseg), .cfg_s0_k(cfg_s0_k), .cfg_s0_jc(cfg_s0_jc),
        .cfg_s0_g(cfg_s0_g), .cfg_stride(cfg_stride), .cfg_obuf(cfg_obuf),
        .cfg_ybase(ybase_eff),
        .cfg_overlap(cfg_overlap), .cfg_nconv(cfg_nconv),
        .cfg_ic(cfg_ic), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw), .cfg_sh(cfg_sh), .cfg_sw(cfg_sw),
        .cfg_ph(cfg_ph), .cfg_pw(cfg_pw),
        .cfg_first(cfg_first), .cfg_law_fetch(cfg_law_fetch),
        .cfg_xbase(cfg_xbase),
        .cfg_wbase(cfg_wbase), .cfg_slab(cfg_slab),
        .cfg_rc_stride(cfg_rc_stride), .cfg_oc_stride(cfg_oc_stride),
        .cfg_oc(cfg_oc),
        .start(eng_start), .busy(dut_busy), .done(dut_done), .err(dut_err),
        .progress_blk(progress_blk),
        .tmo_max_w(iss_tmo_max_w),
        .epoch_invalid(eng_epoch_invalid),
        .axi_epoch_invalid_i(axi_epoch_invalid),
        .epoch_ybase_valid_i(epoch_ybase_valid),
        .epoch_ybase_i(epoch_ybase_q),
        .epoch_ybase_fault_i(epoch_ybase_fault),
        .dense_addr_err_o(dense_addr_err_o),
        .pctl_addr(pctl_addr), .pctl_data(pctl_data),
        .strip_addr(strip_addr), .strip_data(strip_data),
        .lut_addr(lut_addr), .lut_data(lut_data),
        .cv_addr(cv_addr), .cv_iss(cv_iss), .cv_geo(cv_geo),
        .cv_wlay(cv_wlay), .cv_slot(cv_slot), .conv_idx(conv_idx_w),
        .x_raddr_line(x_raddr_line), .x_rreq_line(x_rreq_line),
        .x_rdata_line(x_rdata_line), .x_rvalid_line(x_rvalid_line),
        .w_paddr_line(w_paddr_line), .w_preq_line(w_preq_line),
        .w_pdata_line(w_pdata_line), .w_pvalid_line(w_pvalid_line),
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
        .cnt_beats(cnt_beats), .cnt_stall(cnt_stall),
        .cnt_csr_w(cnt_csr_w), .cnt_y_bytes(cnt_y_bytes),
        .cnt_y_blocks(cnt_y_blocks),
        .tr_raddr(tr_raddr), .tr_rdata(tr_rdata),
        .tr_ring_ovr(tr_ring_ovr), .tr_clr(1'b0),
        .tr_we(tr_we), .tr_waddr(tr_waddr), .tr_wdata(tr_wdata),
        .tr_ddr_gap(x_ddr_gap | w_ddr_gap), .tr_fifo_full(y_fifo_full),
        .tr_fifo_level({10'd0, 6'd0}), .tr_fifo_id(8'd2),
        .tr_steady_end(tr_steady_end),
        .tr_store_active(tr_store_active),
        .tr_last_compute(tr_last_compute),
        .tr_array_active(tr_array_active),
        .chain_rel(cfg_chain_rel), .chain_go(hbuf_chain_go),
        .cfg_up2x(cfg_up2x),
        .s2l_cnt(s2l_cnt), .prod_conv(iss_prod_conv),
        // v2.3: PPP gate face
        .cfg_ppp_tab(cfg_ppp_tab), .cfg_layout_id(cfg_layout_id),
        .frame_gen(frame_gen),
        .ppu_start(ppu_start), .ppu_start_payload(ppu_start_payload),
        .ppu_done(ppu_done), .ppu_done_abort(ppu_done_abort),
        .ppu_done_err(ppu_done_err), .ppu_write_fence_i(ywr_empty),
        .ppu_desc_count(ppu_desc_count),
        .tr_token_latch(tr_token_latch),
        // v2.5 (r12 B 裁定): 页面面透传 + 内部 rearm/rp 环接线
        .cfg_npages(cfg_npages), .cfg_pgauto(cfg_pgauto),
        .cfg_schedule_page(cfg_schedule_page),
        .cfg_gconv_base(cfg_gconv_base),
        .cfg_nedge(cfg_nedge),
        .cfg_hbuf_restart(cfg_hbuf_restart),
        .bind_done_i(hb_bind_done), .bind_err_i(hb_bind_err),
        .pg_win_rdy_i(pg_win_rdy_i),
        .bind_ready(eng_bind_ready),
        .execution_enable(eng_execution_enable),
        .hbuf_start(iss_hbuf_start_w), .hbuf_nconv(iss_hbuf_nconv_w),
        .hbuf_nedge(iss_hbuf_nedge_w),
        .hbuf_segmented_mode(iss_hbuf_segmented_mode_w),
        .sppf_pending_empty(eng_sppf_pending_empty),
        .sppf_prequal_ok(eng_sppf_prequal_ok),
        .sppf_mode(eng_sppf_mode),
        .paged_mode(eng_paged_mode),
        .conv_start(eng_conv_start),
        .face_close(eng_face_close),
        .scatter_verified_close(eng_scatter_verified_close),
        .dbg_dual_transition(iss_dbg_dual_transition),
        .dbg_last_face_close(iss_dbg_last_face_close),
        .arn_req(iss_arn_req), .arn_page(iss_arn_page),
        .arn_gconv(iss_arn_gconv),
        .arn_ack_i(hb_arn_ack), .arn_sealed_i(hb_arn_sealed),
        .arn_err_i(hb_rearm_ovf),
        .pg_desc(pg_desc), .rp_done_i(iss_rp_done_w),
        // D1 (V3.3-D1D2): err 面内部口 (R155 中案, 新增口不动 ABI/CAP0)
        .rp_err_i(iss_rp_err_w), .rp_err_code_i(iss_rp_err_mapped),
        .page_r(page_r), .pg_adv(iss_pg_adv_w), .pg_base(iss_pg_base_w),
        .pg_nconv(iss_pg_nconv_w), .pg_nedge(iss_pg_nedge_w),
        .pg_anchor(), .pg_anchor_page(),
        .rp_start_o(iss_rp_start_w), .pg_pref(pg_pref)
`ifdef M11_REPACK
        ,.sc_done_out(sc_done_w)
        ,.rp_busy_i(rp_busy_w), .rp_warm_i(rp_warm_w),
        .rp_pf_fault_i(rp_pf_fault_w || sppf_phase_error_q),
        .rp_pf_hang_i(rp_pf_hang_w),
        .rp_bytes_i(rp_bytes_w), .rp_arm_o(rp_arm_w),
        .rp_pf_abort_o(rp_pf_abort_w),
        .rp_sc_done_lvl(rp_sc_done_w), .rp_sc_blocks(rp_sc_blocks_w),
        .rp_src_base_o(rp_src_base), .rp_dst_base_o(rp_dst_base),
        .rp_c_o(rp_c), .rp_h_o(rp_h), .rp_w_o(rp_w),
        .rp_vc_o(rp_vc), .rp_ypitch_o(rp_ypitch), .rp_nb_o(rp_nb),
        .rp_commit_req(rp_commit_req_w),
        .producer_arm_o(eng_producer_arm),
        .repack_commit_i(repack_commit_w),
        .producer_commit_i(producer_commit_q)
`endif
    );

    assign m03_b_timeout_limit_o = iss_tmo_max_w;
    assign epoch_invalid_o = eng_epoch_invalid;
    assign bind_done_o = hb_bind_done;
    assign bind_err_o = hb_bind_err;
    assign bind_ready_o = eng_bind_ready && hb_bind_ready;
    assign execution_enable_o = eng_execution_enable;
    assign rearm_ovf_o = hb_rearm_ovf;
    assign sppf_pending_empty = eng_sppf_pending_empty;
    assign sppf_prequal_ok = eng_sppf_prequal_ok;
    assign local_reject_now = rej_now;
    assign local_reject_flags = {join_err_latch, cfg_err_latch,
                                 mask_err_latch};
    assign normal_done = normal_close_q;
    assign rejected_done = rej_done_l && rejected_frame_active_q;

    // V3 read adapters: line client port serves the V3 feeders; the
    // legacy byte face is tied off (rreq_i=0) per the V3 header law.
    m9_axi_rd_v3 u_xrd (
        .clk_i(clk), .rst_n_i(rst_n),
        .raddr_i(32'd0), .rreq_i(1'b0),
        .rdata_o(), .rvalid_o(),
        .laddr_line_i(x_raddr_line), .lreq_line_i(x_lreq_ddr),
        .rdata_line_o(x_rdata_ddr), .rvalid_line_o(x_rvalid_ddr),
        .lsq_ovf_o(),
        .m_araddr_o(m0_araddr), .m_arlen_o(m0_arlen),
        .m_arvalid_o(m0_arvalid), .m_arready_i(m0_arready),
        .m_rdata_i(m0_rdata), .m_rresp_i(m0_rresp),
        .m_rvalid_i(m0_rvalid), .m_rlast_i(m0_rlast),
        .m_rready_o(m0_rready),
        .ddr_gap_wait_o(x_ddr_gap)
    );

    m9_axi_rd_v3 u_wrd (
        .clk_i(clk), .rst_n_i(rst_n),
        .raddr_i(32'd0), .rreq_i(1'b0),
        .rdata_o(), .rvalid_o(),
        .laddr_line_i(w_paddr_line), .lreq_line_i(w_preq_line),
        .rdata_line_o(w_pdata_line), .rvalid_line_o(w_pvalid_line),
        .lsq_ovf_o(),
        .m_araddr_o(m1_araddr), .m_arlen_o(m1_arlen),
        .m_arvalid_o(m1_arvalid), .m_arready_i(m1_arready),
        .m_rdata_i(m1_rdata), .m_rresp_i(m1_rresp),
        .m_rvalid_i(m1_rvalid), .m_rlast_i(m1_rlast),
        .m_rready_o(m1_rready),
        .ddr_gap_wait_o(w_ddr_gap)
    );

`ifdef M11_REPACK
    // repack 启动合并律：glue 顶 FF（单页 legacy）| issuer 锚（paged）。
    assign rp_start_m = rp_start_w | iss_rp_start_w;
    // ---- D1 err 面连接点重映射 (R155 中案, 审计重裁实据; 弃案 = 原生
    //      直通 / 通道前缀位).  repack 模块内部一字不动, 映射挂在本
    //      接线点; err 粘着级下映射码被 issuer S_PPPW 消费一次
    //      (fail-fast), 粘着保持至下一 arm 清除.
    //        repack 原生 (m9_scatter_chw_repack L100-105)
    //                      |  +8'h0D  | issuer err 面 (本线)
    //        RP_ERR_NONE     00    (rp_err=0, 不上挂, 恒 00)
    //        RP_ERR_UNSEALED 01 -> 0E  (start while seal false)
    //        RP_ERR_NOT_ARMED 02 -> 0F (start with no valid arm)
    //        RP_ERR_GEOM_LANE 03 -> 10 (W > vc)
    //        RP_ERR_GEOM_ZERO 04 -> 11 (C/H/W/vc == 0)
    //        RP_ERR_BUSY     05 -> 12  (arm/start while active)
    //      0x0E-0x12 段在 issuer err 全表零占用 (err_code_table_check
    //      v2 机验: issuer 赋值点 + 本层 E_CHAIN OR 组合两面都查);
    //      0x0A-0x0D 被本层 E_CHAIN 组合面占用, 0x01-0x09/0x20-0x26
    //      issuer 既有面 -- 新段不与任何既有码碰撞.
    assign iss_rp_err_mapped = iss_rp_err_w ? (iss_rp_err_code_w + 8'h0D)
                                            : 8'h00;
    // -------- M11 repack instances (contacts #1/#3/#4/#5/#6) -------------
    // keep_hierarchy carries u_repack into the routed netlist for the
    // r11 fingerprint gate while the config face is the inert carrier.
    (* keep_hierarchy = "yes" *) m9_scatter_chw_repack u_repack (
        .clk(clk), .rst_n(rst_n),
        // D1 (V3.3-D1D2): arm 真线 = 门铃链 rp_arm_r (原 r11 tie-off 解除)
        .rp_arm(rp_arm_w), .rp_src_base(rp_src_base),
        .rp_dst_base(rp_dst_base),
        .rp_c(rp_c), .rp_h(rp_h), .rp_w(rp_w), .rp_vc(rp_vc),
        .rp_ypitch(rp_ypitch), .rp_nb(rp_nb),
        // contact #3: producer seal from u_ys's EXISTING outputs (the
        // sc_done sticky level via the intra-top export; the cumulative
        // y_blocks ledger was already a top-level output).  Zero change
        // to m9_y_scatter.
        .sc_done_lvl(rp_sc_done_w), .sc_blocks(rp_sc_blocks_w),
        // contact #4: start pulse = glue top FF（legacy npages<=1 路）与
        // issuer rp_start_o（paged SPPF 锚，M11a 正典）合并——单页帧
        // issuer 恒不脉冲（rp_start_o 仅 paged SPPF 锚点火），OR 无竞争。
        // rp_done 真线回 issuer rp_done_i（paged SPPW 等待，B 裁定）。
        .rp_start(rp_start_m),
        // D1 (V3.3-D1D2): rp_err/rp_err_code 脱空挂解除, 接 err 面
        // (映射见本 ifdef 顶部头注); rp_done 真线回 issuer rp_done_i
        //（paged SPPW 等待，B 裁定）.
        .rp_busy(rp_busy_w), .rp_done(iss_rp_done_w),
        .rp_err(iss_rp_err_w), .rp_err_code(iss_rp_err_code_w),
        // contact #5: read port <- glue return FIFO (fixed 1-cycle law)
        .raddr(rp_raddr), .rreq(rp_rreq), .rdata(rp_rdata),
        // contact #6: write port -> glue arbitration -> shared u_ywr
        .waddr(rp_waddr), .wreq(rp_wreq), .wdata(rp_wdata),
        .rp_bytes(rp_bytes_w)
    );

    m9_repack_glue u_repack_glue (
        .clk(clk), .rst_n(rst_n),
        // R160: one issuer arm feeds both the native repack and glue.
        .rp_arm(rp_arm_w), .rp_src_base(rp_src_base),
        .rp_dst_base(rp_dst_base),
        .rp_c(rp_c), .rp_h(rp_h), .rp_w(rp_w), .rp_vc(rp_vc),
        .rp_ypitch(rp_ypitch), .rp_nb(rp_nb),
        .sc_done_lvl(rp_sc_done_w), .sc_blocks(rp_sc_blocks_w),
        .rp_busy_i(rp_busy_w),
        .rp_start(rp_start_w),
        // v2.5 (r12 B 裁定): npages 真线进 glue——paged 帧 glue 顶 FF
        // 按 M11a 正典退化为不点火（npages>1 时 rp_start 由 issuer 锚独占）
        .cfg_npages(cfg_npages),
        .rp_raddr(rp_raddr), .rp_rreq(rp_rreq), .rp_rdata(rp_rdata),
        .sc_yaddr(yaddr), .sc_yreq(yreq), .sc_ywdata(ywdata),
        .rp_waddr(rp_waddr), .rp_wreq(rp_wreq), .rp_wdata(rp_wdata),
        .mrg_yaddr(yaddr_m), .mrg_yreq(yreq_m), .mrg_ywdata(ywdata_m),
        // contact #5a glue AXI read master: r11 inert carrier -- outputs
        // dangle (never armed); the M11 line punches this face through
        // the shim/BD per the r9b s2_axi/m03_axi boundary precedent.
        .m_araddr(m4_araddr), .m_arlen(m4_arlen), .m_arvalid(m4_arvalid),
        .m_arready(m4_arready), .m_rdata(m4_rdata), .m_rresp(m4_rresp),
        .m_rvalid(m4_rvalid), .m_rlast(m4_rlast), .m_rready(m4_rready),
        .pf_abort(rp_pf_abort_w), .pf_fault(rp_pf_fault_w),
        .pf_hang(rp_pf_hang_w),
        .dbg_col(), .dbg_warm(rp_warm_w),
        .rp_skid_overflow_sticky(rp_skid_overflow_sticky_int),
        .skid_empty(glue_skid_empty)
    );

    wire producer_native_event = 1'b0;  // direct CHW slot 28 has no native epoch
    wire repack_native_event = rp_native_req && eng_paged_mode;
    wire legal_sealed_pending = eng_paged_mode && rp_sc_done_w &&
                                (rp_sc_blocks_w == 10'd160);
    wire producer_commit_condition = legal_sealed_pending &&
        (producer_native_emit_bytes_q == 32'd12800) &&
        (producer_native_enqueue_bytes_q == 32'd12800) &&
        (repack_native_emit_bytes_q == 32'd0) &&
        (repack_native_enqueue_bytes_q == 32'd0) &&
        hw_axi_commit_fence && !rp_fault_any &&
        (dut_err == 8'd0) && !eng_epoch_invalid && !dense_addr_err_o;
    wire repack_commit_condition = rp_commit_req_w &&
        legal_sealed_pending && producer_commit_q && repack_done_seen_q &&
        rp_start_seen_q && native_rp_start_seen_q &&
        (rp_bytes_w == 24'd12800) &&
        (producer_native_emit_bytes_q == 32'd12800) &&
        (producer_native_enqueue_bytes_q == 32'd12800) &&
        (repack_native_emit_bytes_q == 32'd12800) &&
        (repack_native_enqueue_bytes_q == 32'd12800) &&
        hw_axi_commit_fence && !rp_fault_any &&
        (dut_err == 8'd0) && !eng_epoch_invalid && !dense_addr_err_o;
    assign repack_commit_w = repack_commit_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            producer_commit_q <= 1'b0;
            repack_commit_q <= 1'b0;
            repack_done_seen_q <= 1'b0;
            producer_native_emit_bytes_q <= 32'd0;
            producer_native_enqueue_bytes_q <= 32'd0;
            repack_native_emit_bytes_q <= 32'd0;
            repack_native_enqueue_bytes_q <= 32'd0;
            producer_phase_active_q <= 1'b0;
            rp_epoch_active_q <= 1'b0;
            rp_start_seen_q <= 1'b0;
            native_rp_start_seen_q <= 1'b0;
            sppf_phase_error_q <= 1'b0;
        end else begin
            if (eng_producer_arm) begin
                producer_commit_q <= 1'b0;
                repack_commit_q <= 1'b0;
                repack_done_seen_q <= 1'b0;
                producer_native_emit_bytes_q <= 32'd0;
                producer_native_enqueue_bytes_q <= 32'd0;
                repack_native_emit_bytes_q <= 32'd0;
                repack_native_enqueue_bytes_q <= 32'd0;
                producer_phase_active_q <= 1'b1;
                rp_epoch_active_q <= 1'b0;
                rp_start_seen_q <= 1'b0;
                native_rp_start_seen_q <= 1'b0;
            end

            if (eng_paged_mode && rp_arm_w) begin
                rp_epoch_active_q <= 1'b1;
                repack_done_seen_q <= 1'b0;
                rp_start_seen_q <= 1'b0;
                native_rp_start_seen_q <= 1'b0;
            end

            if (producer_native_event) begin
                if (!producer_phase_active_q || rp_epoch_active_q ||
                    producer_commit_q ||
                    (producer_native_emit_bytes_q >= 32'd12800) ||
                    (producer_native_enqueue_bytes_q >= 32'd12800)) begin
                    sppf_phase_error_q <= 1'b1;
                end else begin
                    producer_native_emit_bytes_q <=
                        producer_native_emit_bytes_q + 32'd1;
                    producer_native_enqueue_bytes_q <=
                        producer_native_enqueue_bytes_q + 32'd1;
                end
            end

            if (repack_native_event) begin
                if (!rp_epoch_active_q || !rp_start_seen_q ||
                    !native_rp_start_seen_q || repack_done_seen_q ||
                    (repack_native_emit_bytes_q >= 32'd12800) ||
                    (repack_native_enqueue_bytes_q >= 32'd12800)) begin
                    sppf_phase_error_q <= 1'b1;
                end else begin
                    repack_native_emit_bytes_q <=
                        repack_native_emit_bytes_q + 32'd1;
                    repack_native_enqueue_bytes_q <=
                        repack_native_enqueue_bytes_q + 32'd1;
                end
            end

            if (eng_paged_mode && iss_rp_start_w) begin
                if (rp_start_seen_q || !rp_epoch_active_q) begin
                    sppf_phase_error_q <= 1'b1;
                end else begin
                    rp_start_seen_q <= 1'b1;
                end
            end
            if (eng_paged_mode && rp_start_m) begin
                if (native_rp_start_seen_q || !rp_epoch_active_q) begin
                    sppf_phase_error_q <= 1'b1;
                end else begin
                    native_rp_start_seen_q <= 1'b1;
                end
            end
            if (eng_paged_mode && iss_rp_done_w) begin
                if (!rp_start_seen_q || !native_rp_start_seen_q ||
                    repack_done_seen_q ||
                    (repack_native_emit_bytes_q != 32'd12800) ||
                    (repack_native_enqueue_bytes_q != 32'd12800)) begin
                    sppf_phase_error_q <= 1'b1;
                end else begin
                    repack_done_seen_q <= 1'b1;
                end
            end

            if (legal_sealed_pending &&
                ((producer_native_emit_bytes_q != 32'd12800) ||
                 (producer_native_enqueue_bytes_q != 32'd12800))) begin
                sppf_phase_error_q <= 1'b1;
            end
            if (eng_paged_mode && ppu_done_abort) begin
                sppf_phase_error_q <= 1'b1;
            end

            if (producer_commit_condition && !producer_commit_q) begin
                producer_commit_q <= 1'b1;
            end
            if (repack_commit_condition && !repack_commit_q) begin
                repack_commit_q <= 1'b1;
            end
        end
    end
`endif // M11_REPACK
    // M11_REPACK, the original scatter face otherwise (m9_axi_wr itself
    // is untouched in both modes).
    m9_axi_wr u_ywr (
        .clk(clk), .rst_n(rst_n),
        .yaddr(ywr_addr), .yreq(ywr_req), .ywdata(ywr_data),
        .flush(wr_flush), .b_timeout_limit(iss_tmo_max_w),
        .busy(ywr_busy), .writer_empty(ywr_empty),
        .m_awaddr(m2_awaddr), .m_awlen(m2_awlen),
        .m_awvalid(m2_awvalid), .m_awready(m2_awready),
        .m_wdata(m2_wdata), .m_wstrb(m2_wstrb),
        .m_wvalid(m2_wvalid), .m_wready(m2_wready),
        .m_bresp(m2_bresp), .m_bvalid(m2_bvalid), .m_bready(m2_bready),
        .fifo_full_wait(y_fifo_full), .fifo_fill(),
        .axi_fifo_overflow_event(),
        .axi_fifo_overflow_sticky(axi_fifo_overflow_sticky),
        .axi_b_timeout_sticky(axi_b_timeout_sticky),
        .axi_bresp_error_sticky(axi_bresp_error_sticky),
        .b_waiting(ywr_b_waiting), .err(ywr_err), .err_code(ywr_err_code)
    );

    function [3:0] popcount8;
        input [7:0] value;
        integer pi;
        begin
            popcount8 = 4'd0;
            for (pi = 0; pi < 8; pi = pi + 1) begin
                popcount8 = popcount8 + {3'd0, value[pi]};
            end
        end
    endfunction

    wire aw_fire = m2_awvalid && m2_awready;
    wire w_fire = m2_wvalid && m2_wready;
    wire b_fire = m2_bvalid && m2_bready;
    wire [1:0] native_inc = {1'b0, yreq} + {1'b0, rp_native_req};
    wire [3:0] accepted_w_inc = popcount8(m2_wstrb);
    wire [32:0] native_sum = {1'b0, epoch_native_enqueue_bytes}
                           + {31'd0, native_inc};
    wire [32:0] merged_sum = {1'b0, merged_enqueue_bytes}
                           + {32'd0, ywr_req};
    wire [32:0] accepted_w_sum = {1'b0, axi_w_accepted_bytes}
                               + {29'd0, accepted_w_inc};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch_native_enqueue_bytes <= 32'd0;
            merged_enqueue_bytes <= 32'd0;
            axi_w_accepted_bytes <= 32'd0;
            aw_accepted_txns <= 32'd0;
            w_accepted_txns <= 32'd0;
            b_returned_txns <= 32'd0;
            b_okay_txns <= 32'd0;
            b_bad_txns <= 32'd0;
            axi_w_pending_txns <= 2'd0;
            b_debt <= 2'd0;
            axi_account_sticky <= 1'b0;
        end else begin
            if (native_inc != 2'd0) begin
                if (native_sum[32]) begin
                    axi_account_sticky <= 1'b1;
                end else begin
                    epoch_native_enqueue_bytes <= native_sum[31:0];
                end
            end
            if (ywr_req) begin
                if (merged_sum[32]) begin
                    axi_account_sticky <= 1'b1;
                end else begin
                    merged_enqueue_bytes <= merged_sum[31:0];
                end
            end
            if (w_fire) begin
                if (accepted_w_sum[32]) begin
                    axi_account_sticky <= 1'b1;
                end else begin
                    axi_w_accepted_bytes <= accepted_w_sum[31:0];
                end
            end

            case ({aw_fire, w_fire, b_fire})
                3'b000: begin
                end
                3'b100: begin
                    if ((axi_w_pending_txns != 2'd0) || (b_debt != 2'd0) ||
                        (m2_awlen != 4'd0) ||
                        (aw_accepted_txns == 32'hFFFF_FFFF)) begin
                        axi_account_sticky <= 1'b1;
                    end else begin
                        aw_accepted_txns <= aw_accepted_txns + 32'd1;
                        axi_w_pending_txns <= 2'd1;
                        b_debt <= 2'd1;
                    end
                end
                3'b010: begin
                    if ((axi_w_pending_txns == 2'd0) ||
                        (w_accepted_txns == 32'hFFFF_FFFF)) begin
                        axi_account_sticky <= 1'b1;
                    end else begin
                        w_accepted_txns <= w_accepted_txns + 32'd1;
                        axi_w_pending_txns <= axi_w_pending_txns - 2'd1;
                    end
                end
                3'b001: begin
                    if ((b_debt == 2'd0) || (axi_w_pending_txns != 2'd0) ||
                        (b_returned_txns == 32'hFFFF_FFFF) ||
                        ((m2_bresp == 2'b00) &&
                         (b_okay_txns == 32'hFFFF_FFFF)) ||
                        ((m2_bresp != 2'b00) &&
                         (b_bad_txns == 32'hFFFF_FFFF))) begin
                        axi_account_sticky <= 1'b1;
                    end else begin
                        b_returned_txns <= b_returned_txns + 32'd1;
                        b_debt <= b_debt - 2'd1;
                        if (m2_bresp == 2'b00) begin
                            b_okay_txns <= b_okay_txns + 32'd1;
                        end else begin
                            b_bad_txns <= b_bad_txns + 32'd1;
                        end
                    end
                end
                default: begin
                    axi_account_sticky <= 1'b1;
                end
            endcase
        end
    end

    wire byte_conservation =
        (epoch_native_enqueue_bytes == merged_enqueue_bytes) &&
        (merged_enqueue_bytes == axi_w_accepted_bytes);
    wire w_complete = (axi_w_pending_txns == 2'd0);
    wire b_complete = (b_debt == 2'd0) && (b_bad_txns == 32'd0) &&
                      (b_okay_txns == b_returned_txns);
    wire source_idle = !yreq && !rp_native_req && !ywr_req;
    wire hw_queue_empty = ywr_empty && glue_skid_empty && source_idle;
    assign axi_epoch_invalid = epoch_ybase_fault;
    assign hw_axi_commit_fence = byte_conservation && w_complete &&
                                 b_complete && !axi_b_timeout_sticky &&
                                 !axi_fifo_overflow_sticky &&
                                 !rp_skid_overflow_sticky &&
                                 hw_queue_empty && !ywr_b_waiting &&
                                 !axi_epoch_invalid && !axi_account_sticky &&
                                 !axi_bresp_error_sticky;

    wire local_reject_start_block = mask_err_latch || cfg_err_latch ||
                                    join_err_latch;
    wire nonlocal_error_any = (dut_err != 8'd0) || ywr_err || hb_ovf ||
                              hb_cfg || hb_join_cfg || hb_bind_err ||
                              hb_rearm_ovf || eng_epoch_invalid ||
                              dense_addr_err_o ||
                              epoch_ybase_fault || axi_account_sticky ||
                              axi_fifo_overflow_sticky ||
                              axi_b_timeout_sticky ||
                              axi_bresp_error_sticky || rp_fault_any;
    wire rejected_timer_busy = rejected_frame_active_q && !rej_done_l;
    wire sppf_manual_current = start_paged && !cfg_pgauto;
    assign nonlocal_cfg_prequal_ok = (cfg_nconv != 5'd0) &&
                                     (cfg_nedge <= 4'd8) &&
                                     (cfg_npages <= 3'd5) &&
                                     (!start_paged || (cfg_npages != 3'd0)) &&
                                     !(start_paged && cfg_overlap) &&
                                     (!sppf_manual_current ||
                                      (cfg_schedule_page <= 3'd4)) &&
                                     (!(start_paged && cfg_pgauto) ||
                                      ((cfg_schedule_page == 3'd0) &&
                                       (cfg_gconv_base == 6'd0)));
    assign cfg_prequal_ok = nonlocal_cfg_prequal_ok && !rej_now;
    assign ybase_prequal_ok = !epoch_ybase_fault &&
                              (!epoch_ybase_valid ||
                               (cfg_ybase == epoch_ybase_q));
    assign nonlocal_error_start_block = nonlocal_error_any;
    assign engine_quiescent = (!dut_busy || dut_done) &&
                              !rp_outstanding_any && !ywr_busy &&
                              ywr_empty && glue_skid_empty &&
                              !hb_bind_err && !hb_rearm_ovf &&
                              hw_queue_empty && hw_axi_commit_fence &&
                              !rejected_timer_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            normal_done_pending <= 1'b0;
            normal_close_q <= 1'b0;
        end else if (accept_normal || accept_rejected_frame) begin
            normal_done_pending <= 1'b0;
            normal_close_q <= 1'b0;
        end else begin
            if (dut_done) begin
                normal_done_pending <= 1'b1;
            end
            if ((normal_done_pending || dut_done) && hw_axi_commit_fence &&
                eng_bind_ready && hb_bind_ready && eng_execution_enable &&
                !rejected_frame_active_q && !nonlocal_error_any &&
                !ybase_change_now) begin
                normal_done_pending <= 1'b0;
                normal_close_q <= 1'b1;
            end
        end
    end

endmodule
