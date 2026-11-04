/************************************************************************
 * File Name       : m9_intra_top.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_intra_top
 * Description     :
 *   M9.1 engine-level integration: the V2.4 board-green GEMM engine
 *   u_yolo_gemm (yolo_gemm_top.v, zero diff) with its PS/DMA data
 *   movement replaced in-stream (02_m9_issuer_spec.md section 1):
 *
 *     m9_cmd_issuer  --AXI-Lite master--> engine CSR face (replays the
 *                       pl_m3 per-block command sequence)
 *     m9_w_feeder \                                    |-- s_axis_ld
 *     m9_x_window +-- m9_ld_mux (three-beat law) ------|   (MM2S gone)
 *     engine m_axis_y --> m9_y_scatter --> arena out slots (S2MM gone)
 *
 *   Memory faces are byte-granularity request ports (M9.1 correctness
 *   first; the AXI HP read/write masters are M9.5).  The ROM ports
 *   (pctl/strip/lut) are the future plan-blob BRAM row-cache face.
 *   The ABI v2 CSR slave subset (CAP0/PLAN_BASE/ARENA_BASE/W_BASE/
 *   DOORBELL/progress) lands with the blob reader in M9.4/M9.5; M9.1
 *   drives the config face directly from the TB (credit.v likewise
 *   staged to M9.3 -- 01_m9_plan.md section 7).
 *
 *   D4 ledger counters: ld beats accepted, engine-external stall
 *   cycles, CSR writes issued.
 *
 * Dependencies    : m9_cmd_issuer.v, m9_x_window.v, m9_w_feeder.v,
 *                   m9_ld_mux.v, m9_y_scatter.v, yolo_gemm_top.v
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 *   - V1.1 (2026-10-09) : cfg_overlap passthrough for the M9.3 issuer
 *     overlap mode (load||compute ping-pong + store||compute).
 *   - V1.2 (2026-10-09) : M9.4 conv-table walk face: cfg_nconv + cv ROM
 *     ports (cv_iss/cv_geo/cv_wlay at cv_addr) + conv_idx snoop.  The
 *     feeder cfg inputs are RE-SOURCED to the issuer's geo/wl shadow
 *     outputs (single source: legacy = cfg port passthrough, walk =
 *     per-conv table decode); x window gains the rt_koff k-seed face.
 *     ROM faces widened to flat multi-conv indices; progress_blk 12b
 *     cumulative across convs.
 *   - V1.3 (2026-10-10) : r6 ROM-widening batch: ROM faces pctl 11b /
 *     strip 8b / lut 12b (NCONV_MAX=16; superseded V1.2 9b/6b/10b and
 *     the M9.5 10b/7b/11b law).  Address-plane only, data plane
 *     unchanged.
 *   - V1.4 (2026-10-11) : M9.2 trace bring-up. Instantiates m9_trace
 *     (13.4.3 counter bank + block-event ring) and wires the engine
 *     V1.3 observe-only debug taps. Trace readout face tr_raddr/
 *     tr_rdata/ring_ovr is separate from the data path (13.4.2);
 *     trace clear = tr_clr pulse. Zero data-plane change.
 *   - V1.5 (2026-10-12) : M9.3 run01 -- m9_trace_v2b V1.1 frame/node/case
 *     context (0xC4/0xC8) + ring_ovr output actually driven (was a
 *     floating wire).  Zero data-plane change.
 *   - V1.6 (2026-10-13) : M9.4 batch exposure -- cnt_beats widened 19 ->
 *     32 bits.  The m93 fixture never wrapped 2^19, but M9.4 batches do
 *     (B04 385920/f, B06 969888/f per-frame beats vs 524288 modulus;
 *     B06 exceeds the modulus within ONE frame, so no TB-side modulo
 *     accounting can recover the exact count).  0x44 readback zero-extends
 *     the same way, so small-count consumers are unaffected.  Ledger-only
 *     change; zero data-plane change.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_intra_top (
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
    input  wire [135:0] cv_wlay      ,
    output wire [4:0]  conv_idx      ,   // active conv (TB ledger)
    // ---- X plane byte read port ----
    output wire [31:0] xaddr         ,
    output wire        xreq          ,
    input  wire [7:0]  xdata         ,
    input  wire        xvalid        ,
    // ---- W resident byte read port ----
    output wire [31:0] waddr         ,
    output wire        wreq          ,
    input  wire [7:0]  wdata         ,
    input  wire        wvalid        ,
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
    output wire        tr_last_compute
);

    // ---------------- internal nets (declared before use) -----------
    wire        ld_start;
    wire [9:0]  rt_oy;   wire [3:0]  rt_s;   wire [4:0]  rt_rc;
    wire [4:0]  rt_vc;   wire [10:0] rt_k;   wire [31:0] rt_segoff;
    wire [15:0] rt_koff_ic; wire [3:0] rt_koff_kh, rt_koff_kw;
    wire        sc_arm, sc_done, sc_err;
    wire [31:0] sc_base;
    wire [4:0]  sc_vc;
    // feeder cfg face = issuer geo/wlay shadow (single source)
    wire [15:0] geo_ic, geo_h, geo_w;
    wire [3:0]  geo_kh, geo_kw, geo_sh, geo_sw, geo_ph, geo_pw;
    wire        geo_first, geo_law_fetch;
    wire [31:0] geo_xbase;
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
        .geo_xbase(geo_xbase),
        .wl_wbase(wl_wbase), .wl_slab(wl_slab),
        .wl_rc_stride(wl_rc_stride), .wl_oc_stride(wl_oc_stride),
        .wl_oc(wl_oc),
        .sc_arm(sc_arm), .sc_base(sc_base), .sc_vc(sc_vc),
        .sc_done(sc_done), .sc_err(sc_err),
        .trace_arm_oy(trace_arm_oy), .trace_arm_s(trace_arm_s),
        .trace_arm_rc(trace_arm_rc), .trace_arm_groups(trace_arm_groups),
        .trace_arm_nseg(trace_arm_nseg), .trace_arm_k_ic(trace_arm_k_ic),
        .trace_arm_kh(trace_arm_kh), .trace_arm_kw(trace_arm_kw),
        .trace_arm_k_len(trace_arm_k_len), .trace_arm_conv(trace_arm_conv),
        .trace_arm_geom_kh(trace_arm_geom_kh),
        .trace_arm_geom_kw(trace_arm_geom_kw)
    );

    // ---------------- feeders + three-beat mux ----------------
    m9_w_feeder u_wf (
        .clk(clk), .rst_n(rst_n),
        .cfg_wbase(wl_wbase), .cfg_slab(wl_slab),
        .cfg_rc_stride(wl_rc_stride), .cfg_oc_stride(wl_oc_stride),
        .cfg_oc(wl_oc),
        .rt_rc(rt_rc), .rt_k(rt_k), .rt_seg_off(rt_segoff),
        .start(ld_start), .busy(w_busy), .done(w_done),
        .waddr(waddr), .wreq(wreq), .wdata(wdata), .wvalid(wvalid),
        .w_beat_data(w_beat_data), .w_beat_first(w_beat_first),
        .w_beat_valid(w_beat_valid), .w_beat_ready(w_beat_ready)
    );

    m9_x_window u_xw (
        .clk(clk), .rst_n(rst_n),
        .cfg_ic(geo_ic), .cfg_h(geo_h), .cfg_w(geo_w),
        .cfg_kh(geo_kh), .cfg_kw(geo_kw), .cfg_sh(geo_sh), .cfg_sw(geo_sw),
        .cfg_ph(geo_ph), .cfg_pw(geo_pw),
        .cfg_first(geo_first), .cfg_law_fetch(geo_law_fetch),
        .cfg_xbase(geo_xbase),
        .rt_oy(rt_oy), .rt_s(rt_s), .rt_k(rt_k), .rt_vc(rt_vc),
        .rt_koff_ic(rt_koff_ic), .rt_koff_kh(rt_koff_kh),
        .rt_koff_kw(rt_koff_kw),
        .start(ld_start), .busy(x_busy), .done(x_done),
        .xaddr(xaddr), .xreq(xreq), .xdata(xdata), .xvalid(xvalid),
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
        .sc_chw(1'b0), .sc_ch_stride(32'd0),
        .sc_done(sc_done), .sc_err(sc_err),
        .y_tdata(y_tdata), .y_tvalid(y_tvalid), .y_tready(y_tready),
        .y_tlast(y_tlast),
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
        .y_bytes(cnt_y_bytes), .y_blocks(cnt_y_blocks)
    );

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
    m9_trace_v2b u_trace (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_start      (start),
        .frame_done       (done),
        .steady_end       (tr_steady_end),
        .load_active      (ld_tvalid && ld_tready),
        .compute_useful   (dbg_core_y_valid),
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
        .event_valid      (1'b0),
        .event_type       (4'd0),
        .event_data       (12'd0),
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
    // y_tlast is the final output token; qualify it with the actual
    // accepted handshake and padding mask so drain cycles are excluded.
    assign last_compute_useful = y_tvalid && y_tready && y_tlast && !dbg_y_padding;
    assign tr_last_compute = last_compute_useful;

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
