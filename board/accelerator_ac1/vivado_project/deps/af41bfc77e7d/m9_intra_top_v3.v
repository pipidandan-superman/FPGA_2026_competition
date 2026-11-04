/************************************************************************
 * File Name       : m9_intra_top_v3.v
 * Developer       : M9.3 V3 issuer redesign line
 * Date            : 2026-10-13
 * Project Name    : YOLO object accel (M9.3 V3, 2026-10-13_yolo_m93_issuer_v3_run01)
 * Module Name     : m9_intra_top_v3
 * Description     :
 *   M9.3 V3 sibling of m9_intra_top (V1.6) -- SIBLING COMPOSITION, not
 *   a change: every core (m9_cmd_issuer, m9_ld_mux, yolo_gemm_top,
 *   m9_y_scatter, m9_trace_v2b, token-context pipeline, D4 ledgers) is
 *   instantiated BYTE-IDENTICAL from the frozen sources.  The only
 *   deltas are the two feeders swapped to their V3 line-oriented
 *   siblings (M9.3 spec 2.1/2.2):
 *
 *     m9_w_feeder    -> m9_w_feeder_v3   (byte read port -> W preload
 *                                          line port paddr/preq/pdata/
 *                                          pvalid; BRAM-resident slab)
 *     m9_x_window    -> m9_x_window_v3   (byte read port -> pipelined
 *                                          line port raddr/rreq/rdata/
 *                                          rvalid; <=5 lines/tap)
 *
 *   Top-level X/W BYTE read ports are replaced by LINE read ports of
 *   the v3 protocol (pulse request, in-order response; the downstream
 *   m9_axi_rd_v3 guarantees residency -- spec 2.1 assertion gate).
 *   The ld_mux three-beat law, beat content contract, and ledger
 *   semantics are UNCHANGED (golden94 zero-diff is the Phase B gate).
 *
 *   V3.0 addition vs V1.6: tr_array_active output (spec 2.5 H2' tap)
 *   = ld beat accepted && W beat (k-slice entering the array).
 *   Observe-only; zero data-plane effect.
 *
 * Dependencies    : m9_cmd_issuer.v, m9_x_window_v3.v, m9_w_feeder_v3.v,
 *                   m9_ld_mux.v, m9_y_scatter.v, yolo_gemm_top.v
 * Revision History:
 *   - V3.0 (2026-10-13) : sibling of m9_intra_top V1.6 (feeder swaps +
 *                         line faces + H2' tap).  Inherited history of
 *                         the frozen sibling V1.0-V1.6 applies verbatim
 *                         to all non-feeder logic.
 *   - V3.1 (2026-10-14) : M10.1-v2 2a -- cv_wlay face widened 136->168
 *                         (pass-through) + geo_ch_stride shadow wired
 *                         issuer -> u_xw cfg_ch_stride (SPEC v2 §6).
 *                         Chain-off behavior byte-exact (fallback = h*w).
 *   - V3.2-M11 (2026-10-18): r11 repack merge (SPEC_m11_repack.md §7):
 *                         define-gated export of the u_ys sc_done sticky
 *                         level (contact #3 seal tap for u_repack).  Zero
 *                         effect without M11_REPACK -- every frozen core
 *                         stays byte-identical, u_ys untouched.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_intra_top_v3 (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv config: issuer ----
    input  wire [9:0]  cfg_nb        ,
    input  wire [5:0]  cfg_rc        ,
    input  wire [3:0]  cfg_ns        ,
    input  wire [1:0]  cfg_nseg      ,
    input  wire [10:0] cfg_s0_k      ,
    input  wire [7:0]  cfg_s0_jc     ,
    input  wire [1:0]  cfg_s0_g      ,
    input  wire [31:0] cfg_stride    ,
    input  wire [31:0] cfg_obuf      ,
    input  wire [31:0] cfg_ybase     ,   // M9.5c: y-arena base (CSR 0x04)
    input  wire        cfg_overlap   ,   // M9.3: issuer overlap mode
    input  wire [4:0]  cfg_nconv     ,   // M9.4: conv count (>1 = walk)
    // ---- per-conv config: x window ----
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
    input  wire [31:0] cfg_xbase      ,
    // ---- per-conv config: w feeder ----
    input  wire [31:0] cfg_wbase     ,
    input  wire [31:0] cfg_slab      ,
    input  wire [31:0] cfg_rc_stride ,
    input  wire [31:0] cfg_oc_stride ,
    input  wire [7:0]  cfg_oc        ,
    // ---- frame control / status ----
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    output wire [7:0]  err           ,
    output wire [11:0] progress_blk  ,
    // ---- ROM read ports (data = addr visible + 1 cycle) ----
    // r10 widths (2026-10-18): pctl 12b / strip 9b / lut 13b flat bases,
    // cv 5b (25 live convs; was r6 11b/8b/12b/4b, NCONV_MAX=16)
    output wire [11:0] pctl_addr     ,
    input  wire [95:0] pctl_data     ,
    output wire [8:0]  strip_addr    ,
    input  wire [20:0] strip_data    ,
    output wire [12:0] lut_addr      ,
    input  wire [7:0]  lut_data      ,
    // ---- M9.4 conv-table ROM face ----
    output wire [4:0]  cv_addr       ,
    input  wire [255:0] cv_iss       ,
    input  wire [105:0] cv_geo       ,
    input  wire [167:0] cv_wlay      ,
    output wire [4:0]  conv_idx      ,   // active conv (TB ledger)
    // ---- X plane LINE read port (V3: pulsed req, in-order rsp) ----
    output wire [31:0] x_raddr_line  ,
    output wire        x_rreq_line   ,
    input  wire [63:0] x_rdata_line  ,
    input  wire        x_rvalid_line ,
    // ---- W preload LINE read port (V3: pulsed req, in-order rsp) ----
    output wire [31:0] w_paddr_line  ,
    output wire        w_preq_line   ,
    input  wire [63:0] w_pdata_line  ,
    input  wire        w_pvalid_line ,
    // ---- arena byte write port (y scatter) ----
    output wire [31:0] yaddr         ,
    output wire        yreq          ,
    output wire [7:0]  ywdata        ,
    // ---- D4 ledger ----
    output reg  [31:0] cnt_beats     ,   // s_axis_ld accepted beats
    output reg  [31:0] cnt_stall     ,   // tvalid && !tready cycles
    output reg  [15:0] cnt_csr_w     ,   // engine register writes
    output wire [19:0] cnt_y_bytes   ,
    output wire [9:0]  cnt_y_blocks  ,
    // ---- M9.2 trace readout face (separate from data path) ----
    input  wire [11:0] tr_raddr      ,
    output wire [31:0] tr_rdata      ,
    output wire        tr_ring_ovr   ,
    input  wire        tr_clr        ,
    input  wire        tr_we         ,
    input  wire [11:0] tr_waddr      ,
    input  wire [31:0] tr_wdata      ,
    input  wire        tr_ddr_gap    ,
    input  wire        tr_fifo_full  ,
    input  wire [15:0] tr_fifo_level ,
    input  wire [7:0]  tr_fifo_id    ,
    input  wire        tr_steady_end,
    input  wire        tr_store_active,
    output wire        tr_last_compute,
    // ---- V3 spec 2.5: H2' array-active tap (observe-only) ----
    output wire        tr_array_active,
    // ---- 2e credit-gated release (SPEC §7) ----
    input  wire        chain_rel     ,   // CSR 0xE0[0] (sampled by u_iss)
    input  wire        chain_go      ,   // hbuf consumer-credit export
    input  wire [15:0] cfg_up2x      ,   // 5b: CHAIN_UP2X producer bitmap
    output wire [31:0] s2l_cnt      ,   // CSR 0xE4 telemetry
    output wire [3:0]  prod_conv     ,   // 2e-fix: drained producer conv
    // ---- v2.3 (M10.2 m8): PPP table + three-line handshake ----
    input  wire [255:0] cfg_ppp_tab  ,   // CSR 8x32b PPP segment table
    input  wire [29:0]  cfg_layout_id,   // CSR 10 conv x 3b layout vector
    input  wire [7:0]   frame_gen    ,   // CSR doorbell-latched generation
    output wire         ppu_start    ,   // -> PPU walker PL entry (pulse)
    output wire [17:0]  ppu_start_payload, // {gen, seg_idx, desc_idx}
    input  wire         ppu_done     ,   // walker arbiter verdict pulse
    input  wire         ppu_done_abort,  // 1 = token/engine failure
    input  wire [7:0]   ppu_done_err ,   // abort err code (with pulse)
    input  wire [6:0]   ppu_desc_count,  // PPU island loaded-DESC count
    // ---- G2 (M10.2): PPP anchor event composer tap (observe-only) ----
    input  wire         tr_token_latch   // CSR frame_token doorbell pulse
`ifdef M11_REPACK
    // ---- M11 repack seal export (SPEC_m11_repack.md §7 contact #3):
    //      u_ys sc_done sticky level, tapped UNMODIFIED for the r11 top
    //      glue's producer seal.  Define-gated: without M11_REPACK the
    //      port list is identical to the r10 shadow.
    ,output wire        sc_done_out
`endif
);

    // ---------------- internal nets (declared before use) -----------
    wire        ld_start;
    wire [9:0]  rt_oy;   wire [3:0]  rt_s;   wire [4:0]  rt_rc;
    wire [4:0]  rt_vc;   wire [10:0] rt_k;   wire [31:0] rt_segoff;
    wire [15:0] rt_koff_ic; wire [3:0] rt_koff_kh, rt_koff_kw;
    wire        sc_arm, sc_done, sc_err, sc_up2x;
    wire [31:0] sc_base;
    wire [4:0]  sc_vc;
    // feeder cfg face = issuer geo/wlay shadow (single source)
    wire [15:0] geo_ic, geo_h, geo_w;
    wire [3:0]  geo_kh, geo_kw, geo_sh, geo_sw, geo_ph, geo_pw;
    wire        geo_first, geo_law_fetch;
    wire [31:0] geo_xbase;
    wire [31:0] geo_ch_stride;   // 2a: 0 = legacy h*w fallback
    wire [31:0] wl_wbase, wl_slab, wl_rc_stride, wl_oc_stride;
    wire [7:0]  wl_oc;
    // engine-facing AXI-Lite
    wire [7:0]  m_awaddr;  wire m_awvalid, m_awready;
    wire [31:0] m_wdata;   wire m_wvalid,  m_wready;
    wire [1:0]  m_bresp;   wire m_bvalid,  m_bready;
    wire [7:0]  m_araddr;  wire m_arvalid, m_arready;
    wire [31:0] m_rdata;   wire [1:0]  m_rresp;
    wire        m_rvalid,  m_rready;
    // feeders / mux
    wire        w_busy, w_done, x_busy, x_done;
    wire [63:0] w_beat_data, x_beat_data;
    wire        w_beat_first, w_beat_valid, w_beat_ready;
    wire        x_beat_hi, x_beat_last, x_beat_valid, x_beat_ready;
    wire [63:0] ld_tdata;
    wire        ld_first, ld_last, ld_is_x, ld_x_hi, ld_tvalid, ld_tready;
    // y stream
    wire [63:0] y_tdata;
    wire        y_tvalid, y_tready, y_tlast;
    // M9.2 engine debug taps
    wire        dbg_core_busy, dbg_core_y_valid, dbg_y_ovf;
    wire        dbg_y_padding, dbg_y_full_wait;
    wire [5:0]  dbg_yfifo_level;
    // M9.2 trace readout
    wire [31:0] tr_rdata_w;
    wire        tr_ring_ovr_w;
    wire        last_compute_useful;
    wire [9:0]  trace_arm_oy;
    wire [3:0]  trace_arm_s;
    wire [5:0]  trace_arm_rc;
    wire [1:0]  trace_arm_groups;
    wire [1:0]  trace_arm_nseg;
    wire [15:0] trace_arm_k_ic;
    wire [3:0]  trace_arm_kh, trace_arm_kw;
    wire [10:0] trace_arm_k_len;
    wire [3:0]  trace_arm_conv;
    wire [3:0]  trace_arm_geom_kh, trace_arm_geom_kw;
    // Issuer metadata is captured at scatter-arm, then queued until the
    // delayed Y output's first accepted beat. This prevents overlap/load-ahead
    // commands from relabelling a preceding tile.
    wire [15:0] trace_arm_tile_x = {8'd0, trace_arm_s, 4'd0};
    wire [15:0] trace_arm_tile_y = {6'd0, trace_arm_oy};
    wire [15:0] trace_arm_oc0 = {7'd0, trace_arm_rc, 3'd0};
    wire [16:0] trace_arm_oc_end_w = {1'd0, trace_arm_oc0} + 17'd7;
    wire [15:0] trace_arm_oc1 = (trace_arm_oc_end_w < {9'd0, cfg_oc}) ?
                                 trace_arm_oc_end_w[15:0] :
                                 {8'd0, cfg_oc} - 16'd1;
    // M9.3 debug-bit round 6 (2026-10-12): the flat-K coordinate must not
    // run combinationally from issuer registers into the token-context
    // capture flops (11-level CARRY4 path, WNS -1.515 across five build
    // rounds; keep/DONT_TOUCH provably cannot shorten a comb path).  The
    // arm bundle is sampled at the sc_arm edge, the arithmetic walks three
    // pipeline stages, and sc_arm is delayed three cycles to match.  The
    // captured token is bit-identical, three cycles later.  Observe-only:
    // these wires feed u_trace_context alone; sc_arm's scatter consumer
    // keeps the undelayed strobe.
    wire        tp_arm_err  = sc_err | dbg_y_ovf | (trace_arm_nseg != 2'd1);
    wire        tp_arm_tail = (sc_vc < 5'd16) ||
                              (trace_arm_oc1 == ({8'd0, cfg_oc} - 16'd1));

    reg        tp_vld;
    reg [15:0] tp_tx, tp_ty, tp_oc0, tp_oc1;
    reg [3:0]  tp_buf;
    reg        tp_tail, tp_err;
    reg [15:0] tp_ic;
    reg [2:0]  tp_kh, tp_kw;
    reg [3:0]  tp_gh, tp_gw;
    reg [10:0] tp_klen;

    reg        t1_vld;
    reg [15:0] t1_tx, t1_ty, t1_oc0, t1_oc1;
    reg [3:0]  t1_buf;
    reg        t1_tail, t1_err;
    reg [19:0] t1_mul;               // k_ic*geo_kh + k_h
    reg [3:0]  t1_gw;
    reg [2:0]  t1_kw;
    reg [10:0] t1_klen;

    reg        t2_vld;
    reg [15:0] t2_tx, t2_ty, t2_oc0, t2_oc1;
    reg [3:0]  t2_buf;
    reg        t2_tail, t2_err;
    reg [23:0] t2_flat;              // (..)*geo_kw + k_w  (k0 flat, low 24b)
    reg [10:0] t2_klen;

    reg        t3_vld;
    reg [15:0] t3_tx, t3_ty, t3_oc0, t3_oc1, t3_k0, t3_k1;
    reg [3:0]  t3_buf;
    reg        t3_tail, t3_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tp_vld  <= 1'b0;
            tp_tx   <= 16'd0;  tp_ty  <= 16'd0;
            tp_oc0  <= 16'd0;  tp_oc1 <= 16'd0;
            tp_buf  <= 4'd0;   tp_tail <= 1'b0;  tp_err <= 1'b0;
            tp_ic   <= 16'd0;
            tp_kh   <= 3'd0;   tp_kw  <= 3'd0;
            tp_gh   <= 4'd0;   tp_gw  <= 4'd0;
            tp_klen <= 11'd0;
        end else begin
            tp_vld  <= sc_arm;
            tp_tx   <= trace_arm_tile_x;
            tp_ty   <= trace_arm_tile_y;
            tp_oc0  <= trace_arm_oc0;
            tp_oc1  <= trace_arm_oc1;
            tp_buf  <= {2'd0, trace_arm_groups};
            tp_tail <= tp_arm_tail;
            tp_err  <= tp_arm_err;
            tp_ic   <= trace_arm_k_ic;
            tp_kh   <= trace_arm_kh[2:0];
            tp_kw   <= trace_arm_kw[2:0];
            tp_gh   <= trace_arm_geom_kh;
            tp_gw   <= trace_arm_geom_kw;
            tp_klen <= trace_arm_k_len;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t1_vld  <= 1'b0;
            t1_tx   <= 16'd0;  t1_ty  <= 16'd0;
            t1_oc0  <= 16'd0;  t1_oc1 <= 16'd0;
            t1_buf  <= 4'd0;   t1_tail <= 1'b0;  t1_err <= 1'b0;
            t1_mul  <= 20'd0;
            t1_gw   <= 4'd0;   t1_kw  <= 3'd0;
            t1_klen <= 11'd0;
        end else begin
            t1_vld  <= tp_vld;
            t1_tx   <= tp_tx;   t1_ty  <= tp_ty;
            t1_oc0  <= tp_oc0;  t1_oc1 <= tp_oc1;
            t1_buf  <= tp_buf;  t1_tail <= tp_tail;  t1_err <= tp_err;
            t1_mul  <= ({4'd0, tp_ic} * {16'd0, tp_gh}) + {17'd0, tp_kh};
            t1_gw   <= tp_gw;   t1_kw  <= tp_kw;
            t1_klen <= tp_klen;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t2_vld  <= 1'b0;
            t2_tx   <= 16'd0;  t2_ty  <= 16'd0;
            t2_oc0  <= 16'd0;  t2_oc1 <= 16'd0;
            t2_buf  <= 4'd0;   t2_tail <= 1'b0;  t2_err <= 1'b0;
            t2_flat <= 24'd0;
            t2_klen <= 11'd0;
        end else begin
            t2_vld  <= t1_vld;
            t2_tx   <= t1_tx;   t2_ty  <= t1_ty;
            t2_oc0  <= t1_oc0;  t2_oc1 <= t1_oc1;
            t2_buf  <= t1_buf;  t2_tail <= t1_tail;  t2_err <= t1_err;
            t2_flat <= (t1_mul * {20'd0, t1_gw}) + {21'd0, t1_kw};
            t2_klen <= t1_klen;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t3_vld  <= 1'b0;
            t3_tx   <= 16'd0;  t3_ty  <= 16'd0;
            t3_oc0  <= 16'd0;  t3_oc1 <= 16'd0;
            t3_k0   <= 16'd0;  t3_k1  <= 16'd0;
            t3_buf  <= 4'd0;   t3_tail <= 1'b0;  t3_err <= 1'b0;
        end else begin
            t3_vld  <= t2_vld;
            t3_tx   <= t2_tx;   t3_ty  <= t2_ty;
            t3_oc0  <= t2_oc0;  t3_oc1 <= t2_oc1;
            t3_k0   <= t2_flat[15:0];
            t3_k1   <= t2_flat[15:0] + {5'd0, t2_klen} - 16'd1;
            t3_buf  <= t2_buf;  t3_tail <= t2_tail;  t3_err <= t2_err;
        end
    end
    wire [15:0] token_tile_x, token_tile_y, token_oc0, token_oc1;
    wire [15:0] token_k0, token_k1;
    wire [3:0]  token_buffer_id;
    wire [7:0]  token_generation;
    wire token_valid, token_ready, token_first, token_last;
    wire token_tail, token_error;

    // ---------------- issuer ----------------
    m9_cmd_issuer u_iss (
        .clk(clk), .rst_n(rst_n),
        .cfg_nb(cfg_nb), .cfg_rc(cfg_rc), .cfg_ns(cfg_ns),
        .cfg_nseg(cfg_nseg), .cfg_s0_k(cfg_s0_k), .cfg_s0_jc(cfg_s0_jc),
        .cfg_s0_g(cfg_s0_g), .cfg_stride(cfg_stride), .cfg_obuf(cfg_obuf),
        .cfg_ybase(cfg_ybase),
        .cfg_overlap(cfg_overlap), .cfg_nconv(cfg_nconv),
        .cfg_ic(cfg_ic), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw), .cfg_sh(cfg_sh), .cfg_sw(cfg_sw),
        .cfg_ph(cfg_ph), .cfg_pw(cfg_pw),
        .cfg_first(cfg_first), .cfg_law_fetch(cfg_law_fetch),
        .cfg_xbase(cfg_xbase),
        .cfg_wbase(cfg_wbase), .cfg_slab(cfg_slab),
        .cfg_rc_stride(cfg_rc_stride), .cfg_oc_stride(cfg_oc_stride),
        .cfg_oc(cfg_oc),
        .start(start), .busy(busy), .done(done), .err(err),
        .progress_blk(progress_blk),
        .pctl_addr(pctl_addr), .pctl_data(pctl_data),
        .strip_addr(strip_addr), .strip_data(strip_data),
        .lut_addr(lut_addr), .lut_data(lut_data),
        .cv_addr(cv_addr), .cv_iss(cv_iss), .cv_geo(cv_geo),
        .cv_wlay(cv_wlay), .conv_idx(conv_idx),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .ld_start(ld_start),
        .rt_oy(rt_oy), .rt_s(rt_s), .rt_rc(rt_rc), .rt_vc(rt_vc),
        .rt_k(rt_k), .rt_segoff(rt_segoff),
        .rt_koff_ic(rt_koff_ic), .rt_koff_kh(rt_koff_kh),
        .rt_koff_kw(rt_koff_kw),
        .ld_w_busy(w_busy), .ld_x_busy(x_busy),
        .geo_ic(geo_ic), .geo_h(geo_h), .geo_w(geo_w),
        .geo_kh(geo_kh), .geo_kw(geo_kw), .geo_sh(geo_sh), .geo_sw(geo_sw),
        .geo_ph(geo_ph), .geo_pw(geo_pw),
        .geo_first(geo_first), .geo_law_fetch(geo_law_fetch),
        .geo_xbase(geo_xbase), .geo_ch_stride(geo_ch_stride),
        .wl_wbase(wl_wbase), .wl_slab(wl_slab),
        .wl_rc_stride(wl_rc_stride), .wl_oc_stride(wl_oc_stride),
        .wl_oc(wl_oc),
        .sc_arm(sc_arm), .sc_base(sc_base), .sc_vc(sc_vc),
        .sc_up2x(sc_up2x), .cfg_up2x(cfg_up2x),
        .sc_done(sc_done), .sc_err(sc_err),
        .chain_rel(chain_rel), .chain_go(chain_go),
        .s2l_cnt(s2l_cnt), .prod_conv(prod_conv),
        .trace_arm_oy(trace_arm_oy), .trace_arm_s(trace_arm_s),
        .trace_arm_rc(trace_arm_rc), .trace_arm_groups(trace_arm_groups),
        .trace_arm_nseg(trace_arm_nseg), .trace_arm_k_ic(trace_arm_k_ic),
        .trace_arm_kh(trace_arm_kh), .trace_arm_kw(trace_arm_kw),
        .trace_arm_k_len(trace_arm_k_len), .trace_arm_conv(trace_arm_conv),
        .trace_arm_geom_kh(trace_arm_geom_kh),
        .trace_arm_geom_kw(trace_arm_geom_kw),
        // v2.3: PPP gate face
        .cfg_ppp_tab(cfg_ppp_tab), .cfg_layout_id(cfg_layout_id),
        .frame_gen(frame_gen),
        .ppu_start(ppu_start), .ppu_start_payload(ppu_start_payload),
        .ppu_done(ppu_done), .ppu_done_abort(ppu_done_abort),
        .ppu_done_err(ppu_done_err), .ppu_desc_count(ppu_desc_count)
    );

    // ---------------- feeders + three-beat mux (V3 line faces) ---------
    m9_w_feeder_v3 u_wf (
        .clk(clk), .rst_n(rst_n),
        .cfg_wbase(wl_wbase), .cfg_slab(wl_slab),
        .cfg_rc_stride(wl_rc_stride), .cfg_oc_stride(wl_oc_stride),
        .cfg_oc(wl_oc),
        .rt_rc(rt_rc), .rt_k(rt_k), .rt_seg_off(rt_segoff),
        .start(ld_start), .busy(w_busy), .done(w_done),
        .paddr_line(w_paddr_line), .preq_line(w_preq_line),
        .pdata_line(w_pdata_line), .pvalid_line(w_pvalid_line),
        .w_beat_data(w_beat_data), .w_beat_first(w_beat_first),
        .w_beat_valid(w_beat_valid), .w_beat_ready(w_beat_ready)
    );

    m9_x_window_v3 u_xw (
        .clk(clk), .rst_n(rst_n),
        .cfg_ic(geo_ic), .cfg_h(geo_h), .cfg_w(geo_w),
        .cfg_kh(geo_kh), .cfg_kw(geo_kw), .cfg_sh(geo_sh), .cfg_sw(geo_sw),
        .cfg_ph(geo_ph), .cfg_pw(geo_pw),
        .cfg_first(geo_first), .cfg_law_fetch(geo_law_fetch),
        .cfg_xbase(geo_xbase), .cfg_ch_stride(geo_ch_stride),
        .cfg_layout_id(cfg_layout_id),   // v2.3: layout vector
        .conv_idx(conv_idx),             // v2.3: active conv (issuer face)
        .rt_oy(rt_oy), .rt_s(rt_s), .rt_k(rt_k), .rt_vc(rt_vc),
        .rt_koff_ic(rt_koff_ic), .rt_koff_kh(rt_koff_kh),
        .rt_koff_kw(rt_koff_kw),
        .start(ld_start), .busy(x_busy), .done(x_done),
        .raddr_line(x_raddr_line), .rreq_line(x_rreq_line),
        .rdata_line(x_rdata_line), .rvalid_line(x_rvalid_line),
        .x_beat_data(x_beat_data), .x_beat_hi(x_beat_hi),
        .x_beat_last(x_beat_last), .x_beat_valid(x_beat_valid),
        .x_beat_ready(x_beat_ready)
    );

    m9_ld_mux u_mux (
        .clk(clk), .rst_n(rst_n),
        .w_beat_data(w_beat_data), .w_beat_first(w_beat_first),
        .w_beat_valid(w_beat_valid), .w_beat_ready(w_beat_ready),
        .x_beat_data(x_beat_data), .x_beat_hi(x_beat_hi),
        .x_beat_last(x_beat_last), .x_beat_valid(x_beat_valid),
        .x_beat_ready(x_beat_ready),
        .ld_tdata(ld_tdata), .ld_first(ld_first), .ld_last(ld_last),
        .ld_is_x(ld_is_x), .ld_x_hi(ld_x_hi),
        .ld_tvalid(ld_tvalid), .ld_tready(ld_tready)
    );

    // ---------------- engine (u_yolo_gemm, zero diff) ----------------
    // s_axis_ld: the bridge rebuilds is_x/x_hi from its own phase
    // counter -- only tdata/tvalid/tlast cross the boundary (B3 C3).
    yolo_gemm_top u_eng (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr({24'd0, m_awaddr}), .s_axi_awprot(3'd0),
        .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata), .s_axi_wstrb(4'hF),
        .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bresp(m_bresp), .s_axi_bvalid(m_bvalid),
        .s_axi_bready(m_bready),
        .s_axi_araddr({24'd0, m_araddr}), .s_axi_arprot(3'd0),
        .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp),
        .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready),
        .s_axis_ld_tdata(ld_tdata),
        .s_axis_ld_tvalid(ld_tvalid),
        .s_axis_ld_tready(ld_tready),
        .s_axis_ld_tlast(ld_last),                 // TLAST on X hi of k=K-1
        .m_axis_y_tdata(y_tdata),
        .m_axis_y_tvalid(y_tvalid),
        .m_axis_y_tready(y_tready),
        .m_axis_y_tlast(y_tlast),
        // M9.2 observe-only taps (V1.3)
        .dbg_core_busy_o   (dbg_core_busy),
        .dbg_core_y_valid_o(dbg_core_y_valid),
        .dbg_yfifo_level_o (dbg_yfifo_level),
        .dbg_y_ovf_o       (dbg_y_ovf),
        .dbg_y_padding_o   (dbg_y_padding),
        .dbg_y_full_wait_o (dbg_y_full_wait)
    );

    // ---------------- y scatter ----------------
    m9_y_scatter u_ys (
        .clk(clk), .rst_n(rst_n),
        .sc_arm(sc_arm), .sc_base(sc_base), .sc_vc(sc_vc),
        .sc_up2x(sc_up2x),
        .sc_done(sc_done), .sc_err(sc_err),
        .y_tdata(y_tdata), .y_tvalid(y_tvalid), .y_tready(y_tready),
        .y_tlast(y_tlast),
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
        .y_bytes(cnt_y_bytes), .y_blocks(cnt_y_blocks)
    );
`ifdef M11_REPACK
    // M11 repack seal tap (contact #3): the sticky slot-closed level,
    // straight off the existing u_ys net -- u_ys itself is untouched.
    assign sc_done_out = sc_done;
`endif

`ifdef M9_TRACE_OFF
    // r8 capacity knife (2026-10-17): trace observer islands removed for
    // PPU_ON builds.  ON netlist measured 51,420/53,200 LUT (96.5%) with
    // zero packing room (Place 30-487 twice: with AND without the E3'
    // pblock).  Pure-observation subtree proven: s2l_cnt lives in the
    // issuer (CSR 0xE4), skew_max in hbuf (0xE8), beats/csr/yb/chain in
    // the D4 ledger -- no identity-ladder field crosses this cone; the
    // token context FIFO only snoops y_tready (driven by scatter) and its
    // token_* outputs feed u_trace alone.  M11b coverage evidence re-bases
    // at the M12-P engine swap budget.
    assign tr_rdata    = 32'd0;
    assign tr_ring_ovr = 1'b0;
`else
    m9_trace_token_context_fifo u_trace_context (
        .clk             (clk),
        .rst_n           (rst_n),
        .arm             (t3_vld),
        .arm_tile_x      (t3_tx),
        .arm_tile_y      (t3_ty),
        .arm_oc0         (t3_oc0),
        .arm_oc1         (t3_oc1),
        .arm_k0          (t3_k0),
        .arm_k1          (t3_k1),
        .arm_buffer_id   (t3_buf),
        .arm_tail        (t3_tail),
        .arm_error       (t3_err),
        .y_valid         (y_tvalid),
        .y_ready         (y_tready),
        .y_last          (y_tlast),
        .token_tile_x    (token_tile_x),
        .token_tile_y    (token_tile_y),
        .token_oc0       (token_oc0),
        .token_oc1       (token_oc1),
        .token_k0        (token_k0),
        .token_k1        (token_k1),
        .token_buffer_id (token_buffer_id),
        .token_generation(token_generation),
        .token_valid     (token_valid),
        .token_ready     (token_ready),
        .token_first     (token_first),
        .token_last      (token_last),
        .token_tail      (token_tail),
        .token_error     (token_error)
    );

    // ---------------- M9.2 v2b trace block ---------------------------
    // Every phase input is acceptance-qualified. Busy/request activity is
    // intentionally excluded from the metric definitions.
    // G2: PPP anchor composer — packs the three-line handshake into the
    // trace block's generic event port.  Pure observation (no datapath
    // cone); type priority TOK(6) > DONE(5) > START(4), mutual exclusion
    // guaranteed by the handshake protocol (doorbell owns the gen latch,
    // walker fires done once per segment, start/done never same cycle).
    wire        ppp_ev_valid = ppu_start | ppu_done | tr_token_latch;
    wire [3:0]  ppp_ev_type  = tr_token_latch ? 4'd6 :
                               ppu_done       ? 4'd5 : 4'd4;
    wire [11:0] ppp_ev_data  = tr_token_latch ? {4'd0, frame_gen} :
                               ppu_done       ? {2'd0, ppu_done_abort,
                                                 ppu_done_err} :
                                                {2'd0,
                                                 ppu_start_payload[9:0]};
    m9_trace_v2b u_trace (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_start      (start),
        .frame_done       (done),
        .steady_end       (tr_steady_end),
        .load_active      (ld_tvalid && ld_tready),
        .compute_useful   (tr_array_active),   // schema v3 (V3 bit): C 计数改 H2' 口径
                                              // = ld accept 的 W beat 拍 (k-slice 入阵)
        .store_active     (tr_store_active),
        .ddr_gap          (tr_ddr_gap),
        .fifo_full        (tr_fifo_full | dbg_y_full_wait),
        .fifo_level       ({10'd0, dbg_yfifo_level}),
        .fifo_id          (tr_fifo_id),
        .token_tile_x     (token_tile_x),
        .token_tile_y     (token_tile_y),
        .token_oc0        (token_oc0),
        .token_oc1        (token_oc1),
        .token_k0         (token_k0),
        .token_k1         (token_k1),
        .token_buffer_id  (token_buffer_id),
        .token_generation (token_generation),
        .token_valid      (token_valid),
        .token_ready      (token_ready),
        .token_first      (token_first),
        .token_last       (token_last),
        .token_tail       (token_tail),
        .token_error      (token_error),
        .event_valid      (ppp_ev_valid),
        .event_type       (ppp_ev_type),
        .event_data       (ppp_ev_data),
        .event_fifo_level (16'd0),
        .csr_we           (tr_we),
        .csr_waddr        (tr_waddr),
        .csr_wdata        (tr_wdata),
        .csr_raddr        (tr_raddr),
        .csr_rdata        (tr_rdata_w),
        .ring_ovr         (tr_ring_ovr_w)
    );
    assign tr_rdata    = tr_rdata_w;
    assign tr_ring_ovr = tr_ring_ovr_w;
`endif // M9_TRACE_OFF
    // y_tlast is the final output token; qualify it with the actual
    // accepted handshake and padding mask so drain cycles are excluded.
    assign last_compute_useful = y_tvalid && y_tready && y_tlast && !dbg_y_padding;
    assign tr_last_compute = last_compute_useful;
    // H2' tap (spec 2.5): W beat accepted into the array = k-slice compute
    // cycle.  ld_is_x==0 on an accepted beat is the W beat by the mux law.
    assign tr_array_active = ld_tvalid && ld_tready && !ld_is_x;

    // ---------------- D4 ledger ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_beats <= 32'd0; cnt_stall <= 32'd0; cnt_csr_w <= 16'd0;
        end else begin
            if (ld_tvalid && ld_tready) cnt_beats <= cnt_beats + 32'd1;
            if (ld_tvalid && !ld_tready) cnt_stall <= cnt_stall + 32'd1;
            if (m_bvalid && m_bready) cnt_csr_w <= cnt_csr_w + 16'd1;
        end
    end

endmodule
