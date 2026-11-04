/************************************************************************
 * File Name       : m9_v25_top_v3.v
 * Developer       : M9.3 V3 issuer redesign line
 * Date            : 2026-10-13
 * Project Name    : YOLO object accel (M9.3 V3, 2026-10-13_yolo_m93_issuer_v3_run01)
 * Module Name     : m9_v25_top_v3
 * Description     :
 *   M9.3 V3 sibling of m9_v25_top (V1.2) -- pure composition swap:
 *   m9_abi_v2_csr stays BYTE-IDENTICAL (V3.0); the engine wrapper is
 *   m9_intra_axi_top_v3 (V3 feeders + m9_axi_rd_v3 line loaders + H2'
 *   array-active tap).  ABI face, PS frame law, done law, and plan
 *   faces are UNCHANGED -- every V2.5 ladder TB compiles against this
 *   sibling unchanged.  The only port addition is the observe-only
 *   tr_array_active output (spec 2.5 H2' tap).
 *
 *   V3.1 (M10.1, 2026-10-14): ABI v2.1 layer_chain wiring -- CSR
 *   CHAIN_MASK (0x58) -> engine, CHAIN_CNT (0x5C) <- engine; CAP0
 *   reads 0x4D39_0210.  Composition only; no new top-level ports (the
 *   board shim/BD face is untouched).
 *
 * Dependencies    : m9_abi_v2_csr.v (V1.2), m9_intra_axi_top_v3.v (V3.1)
 * Revision History:
 *   - V3.0 (2026-10-13) : sibling of m9_v25_top V1.2 (axi_top_v3 swap +
 *                         H2' tap passthrough).  Inherited history
 *                         V1.0-V1.2 applies to all else.
 *   - V3.1 (2026-10-14) : M10.1 layer_chain wiring (CHAIN_MASK/CHAIN_CNT
 *                         + CAP0 v2.1).
 *   - V3.2 (2026-10-14) : M10.1-v2 phase 2b edge-table plumbing
 *                         (CHAIN_NEDGE/EDGE_IDX/EDGE_NODE/EDGE_WIN 0xD0-
 *                         0xDC -> engine; CAP1 0xCC RO; composition only,
 *                         no new top-level ports).
 *   - V3.3-M10.3 (2026-10-17): PPU island activation switch (default OFF).
 *     Everything island-related is inside `ifdef PPU_ISLAND: new top
 *     ports (s2_axi AXI-Lite slave + m3_axi 64b master), the u_ppu
 *     island instance (src/rtl_ppu/ppu_f7_top.v V1.9-M10.3), and the
 *     u_eng four-input tie-off replaced by the real three-line face.
 *     OFF state: the tie-off text below is the ORIGINAL g3r9 text
 *     VERBATIM (byte-preserved inside the `else branch) -- compiled
 *     netlist and port face are structurally identical to silicon
 *     (T7 identity law, PPU_ACTIVATION_PLAN section 5-R3/C1).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_v25_top_v3 (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- ABI v2 AXI4-Lite slave (PS GP face) ----
    input  wire [7:0]  s_awaddr      ,
    input  wire [2:0]  s_awprot      ,
    input  wire        s_awvalid     ,
    output wire        s_awready     ,
    input  wire [31:0] s_wdata       ,
    input  wire [3:0]  s_wstrb       ,
    input  wire        s_wvalid      ,
    output wire        s_wready      ,
    output wire [1:0]  s_bresp       ,
    output wire        s_bvalid      ,
    input  wire        s_bready      ,
    input  wire [7:0]  s_araddr      ,
    input  wire [2:0]  s_arprot      ,
    input  wire        s_arvalid     ,
    output wire        s_arready     ,
    output wire [31:0] s_rdata       ,
    output wire [1:0]  s_rresp       ,
    output wire        s_rvalid      ,
    input  wire        s_rready      ,
    // ---- plan ROM faces (BD plan BRAM; registered read) ----
    // r10 widths (2026-10-18): pctl 12b / strip 9b / lut 13b, cv 5b
    // (25 live convs; was r6 11b/8b/12b/4b, NCONV_MAX=16)
    output wire [11:0] pctl_addr     ,
    input  wire [95:0] pctl_data     ,
    output wire [8:0]  strip_addr    ,
    input  wire [20:0] strip_data    ,
    output wire [12:0] lut_addr      ,
    input  wire [7:0]  lut_data      ,
    output wire [4:0]  cv_addr       ,
    input  wire [255:0] cv_iss       ,
    input  wire [105:0] cv_geo       ,
    // 2a: m9_bm_wlay widened 136->168 (ch_stride tail)
    input  wire [167:0] cv_wlay      ,
    // ---- HP0 read master: x window ----
    output wire [31:0] m0_araddr     ,
    output wire [3:0]  m0_arlen      ,
    output wire        m0_arvalid    ,
    input  wire        m0_arready    ,
    input  wire [63:0] m0_rdata      ,
    input  wire [1:0]  m0_rresp      ,
    input  wire        m0_rvalid     ,
    input  wire        m0_rlast      ,
    output wire        m0_rready     ,
    // ---- HP3 read master: w feeder ----
    output wire [31:0] m1_araddr     ,
    output wire [3:0]  m1_arlen      ,
    output wire        m1_arvalid    ,
    input  wire        m1_arready    ,
    input  wire [63:0] m1_rdata      ,
    input  wire [1:0]  m1_rresp      ,
    input  wire        m1_rvalid     ,
    input  wire        m1_rlast      ,
    output wire        m1_rready     ,
    // ---- HP0 write master: y scatter ----
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
    output wire        m2_bready     ,
    // ---- V3 spec 2.5: H2' array-active tap (observe-only) ----
    output wire        tr_array_active
`ifdef PPU_ISLAND
    // ---- M10.3 activation (switch-gated): PPU island CSR face ----
    // s2: island AXI4-Lite slave (BD GP0 second segment, 0x43C2_0000)
    ,input  wire [31:0] s2_axi_awaddr  ,
    input  wire [2:0]  s2_axi_awprot  ,
    input  wire        s2_axi_awvalid ,
    output wire        s2_axi_awready ,
    input  wire [31:0] s2_axi_wdata   ,
    input  wire [3:0]  s2_axi_wstrb   ,
    input  wire        s2_axi_wvalid  ,
    output wire        s2_axi_wready  ,
    output wire [1:0]  s2_axi_bresp   ,
    output wire        s2_axi_bvalid  ,
    input  wire        s2_axi_bready  ,
    input  wire [31:0] s2_axi_araddr  ,
    input  wire [2:0]  s2_axi_arprot  ,
    input  wire        s2_axi_arvalid ,
    output wire        s2_axi_arready ,
    output wire [31:0] s2_axi_rdata   ,
    output wire [1:0]  s2_axi_rresp   ,
    output wire        s2_axi_rvalid  ,
    input  wire        s2_axi_rready  ,
    // m3: island shell-DMA AXI4 master (BD -> PS7 HP1 via interconnect)
    output wire [31:0] m3_axi_araddr  ,
    output wire [3:0]  m3_axi_arlen   ,
    output wire [2:0]  m3_axi_arsize  ,
    output wire [1:0]  m3_axi_arburst ,
    output wire        m3_axi_arvalid ,
    input  wire        m3_axi_arready ,
    input  wire [63:0] m3_axi_rdata   ,
    input  wire [1:0]  m3_axi_rresp   ,
    input  wire        m3_axi_rlast   ,
    input  wire        m3_axi_rvalid  ,
    output wire        m3_axi_rready  ,
    output wire [31:0] m3_axi_awaddr  ,
    output wire [3:0]  m3_axi_awlen   ,
    output wire [2:0]  m3_axi_awsize  ,
    output wire [1:0]  m3_axi_awburst ,
    output wire        m3_axi_awvalid ,
    input  wire        m3_axi_awready ,
    output wire [63:0] m3_axi_wdata   ,
    output wire [7:0]  m3_axi_wstrb   ,
    output wire        m3_axi_wlast   ,
    output wire        m3_axi_wvalid  ,
    input  wire        m3_axi_wready  ,
    input  wire [1:0]  m3_axi_bresp   ,
    input  wire        m3_axi_bvalid  ,
    output wire        m3_axi_bready
`endif
);

    // ---- CSR config outputs -> intra top cfg inputs ----
    wire [31:0] plan_base, arena_base, w_base;
    wire [9:0]  cfg_nb;   wire [5:0]  cfg_rc;
    wire [3:0]  cfg_ns;   wire [1:0]  cfg_nseg;
    wire [4:0]  cfg_nconv;
    wire [15:0] cfg_ic, cfg_h, cfg_w;
    wire [3:0]  cfg_kh, cfg_kw, cfg_sh, cfg_sw, cfg_ph, cfg_pw;
    wire        cfg_first, cfg_law_fetch, cfg_overlap;
    wire [7:0]  cfg_oc;
    wire [10:0] cfg_s0_k; wire [7:0] cfg_s0_jc; wire [1:0] cfg_s0_g;
    wire [31:0] cfg_stride, cfg_obuf, cfg_slab, cfg_rc_stride,
                cfg_oc_stride;
    wire [15:0] cfg_chain_mask;          // M10.1 ABI v2.1 (CSR 0x58)
    wire [3:0]  cfg_nedge;               // 2b: CHAIN_NEDGE (CSR 0xD0)
    wire [63:0] cfg_edge_node;           // 2b: edge table nodes
    wire [63:0] cfg_edge_prod;           // 2d: edge table producer fields
    wire [127:0] cfg_edge_win;           // 2b: edge table windows
    wire [639:0] cfg_join_tab;           // 5b: join-region table (20 words)
    wire        db_start;
    // v2.3 (M10.2 m8): PPP segment table + generation + three-line face
    wire [255:0] cfg_ppp_tab;            // CSR 8x32b (0xE9/0xEA window)
    wire [29:0]  cfg_layout_id;          // CSR 10x3b (0xEB)
    wire [7:0]   frame_gen;              // doorbell wdata[7:0] latch
    wire         frame_token;            // pulse face for the PPU walker
    wire         ppu_start_w;            // issuer->walker (conv-only bits:
    wire [17:0]  ppu_start_payload_w;    //   unused; see u_eng tie-off)

    // ---- engine status (pre-done-gate) + counters ----
    wire        eng_busy, eng_done;
    wire [7:0]  err;
    wire [11:0] progress_blk;
    wire [31:0] cnt_beats;
    wire [31:0] cnt_stall;
    wire [15:0] cnt_csr_w;
    wire [19:0] cnt_y_bytes;
    wire [9:0]  cnt_y_blocks;
    wire [31:0] cnt_chain_bytes;         // M10.1: HBUF ledger (CSR 0x5C)
    wire         cfg_chain_rel;          // 2e: CHAIN_REL mode bit (CSR 0xE0)
    wire [15:0]  cfg_up2x;               // 5b: CHAIN_UP2X bitmap (CSR 0xDE)
    wire [31:0]  iss_s2l_cnt;            // 2e: issuer S2L counter (CSR 0xE4)
    wire [31:0]  hb_skew_max;            // 2e: hbuf skew max (CSR 0xE8)
    wire [511:0] hb_dbg;                 // r7 debug aperture (cursor 0xF8/0xFC)
    wire [4:0]  conv_idx_w;              // M10.1: connected (was dangling); r10 5b
    wire         tr_we;
    wire [11:0]  tr_waddr, tr_raddr;
    wire [31:0]  tr_wdata, tr_rdata;
    wire         tr_ring_ovr;
    wire         tr_last_compute;
    reg          issuer_done_seen, final_token_seen;
    wire         tr_steady_end = (tr_last_compute && (issuer_done_seen || eng_done))
                               || (eng_done && final_token_seen);

    // ---- done gating: PS must not see done before the arena is complete
    // ---- exact three-phase frame law: idle -> running -> draining -> done
    // running : eng_busy high (walk in flight)
    // draining: eng_done seen; y write master tail line + B in flight
    // done    : 16 quiet cycles on the m2 face after eng_done (level,
    //           cleared by the next doorbell -- sticky-done law M9.1)
    wire        ywr_act = m2_awvalid || m2_wvalid || m2_bvalid;
    reg         draining, done_l;
    reg [4:0]   drain_c;

    assign busy_v25 = eng_busy | draining;
    assign done_v25 = done_l;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            draining <= 1'b0; done_l <= 1'b0; drain_c <= 5'd0;
            issuer_done_seen <= 1'b0; final_token_seen <= 1'b0;
        end else if (db_start) begin
            draining <= 1'b0; done_l <= 1'b0; drain_c <= 5'd0;
            issuer_done_seen <= 1'b0; final_token_seen <= 1'b0;
        end else begin
            if (eng_done) issuer_done_seen <= 1'b1;
            if (tr_last_compute) final_token_seen <= 1'b1;
            if (ywr_act)                       drain_c <= 5'd0;
            else if (draining && drain_c != 5'd16)
                                               drain_c <= drain_c + 5'd1;
            if (!done_l && eng_done && !draining)      draining <= 1'b1;
            else if (draining && !ywr_act && drain_c == 5'd16) begin
                draining <= 1'b0;              done_l  <= 1'b1;
            end
        end
    end

    m9_abi_v2_csr u_csr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awprot(s_awprot),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arprot(s_arprot),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .busy(busy_v25), .done(done_v25), .err(err),
        .progress_blk(progress_blk),
        .cnt_beats(cnt_beats), .cnt_csr_w(cnt_csr_w),
        .cnt_y_bytes(cnt_y_bytes), .cnt_y_blocks(cnt_y_blocks),
        .cnt_stall(cnt_stall), .cnt_chain_bytes(cnt_chain_bytes),
        .s2l_cnt(iss_s2l_cnt), .skew_max(hb_skew_max), .hb_dbg(hb_dbg),
        // G3: OVF AW-capture tap (observe-only; the only DDR write master)
        .mon_awvalid(m2_awvalid), .mon_awready(m2_awready),
        .mon_awaddr(m2_awaddr),
        .plan_base(plan_base), .arena_base(arena_base), .w_base(w_base),
        .cfg_nb(cfg_nb), .cfg_rc(cfg_rc), .cfg_ns(cfg_ns),
        .cfg_nseg(cfg_nseg), .cfg_nconv(cfg_nconv),
        .cfg_ic(cfg_ic), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw),
        .cfg_sh(cfg_sh), .cfg_sw(cfg_sw),
        .cfg_ph(cfg_ph), .cfg_pw(cfg_pw),
        .cfg_first(cfg_first), .cfg_law_fetch(cfg_law_fetch),
        .cfg_overlap(cfg_overlap), .cfg_oc(cfg_oc),
        .cfg_s0_k(cfg_s0_k), .cfg_s0_jc(cfg_s0_jc), .cfg_s0_g(cfg_s0_g),
        .cfg_stride(cfg_stride), .cfg_obuf(cfg_obuf), .cfg_slab(cfg_slab),
        .cfg_rc_stride(cfg_rc_stride), .cfg_oc_stride(cfg_oc_stride),
        .cfg_chain_mask(cfg_chain_mask),   // M10.1 ABI v2.1
        .cfg_nedge(cfg_nedge),             // 2b edge table
        .cfg_edge_node(cfg_edge_node),
        .cfg_edge_prod(cfg_edge_prod),   // 2d producer field
        .cfg_edge_win(cfg_edge_win),
        .cfg_join_tab(cfg_join_tab),
        .cfg_chain_rel(cfg_chain_rel),   // 2e
        .cfg_up2x(cfg_up2x),             // 5b
        .cfg_ppp_tab(cfg_ppp_tab),       // v2.3 (M10.2 m8)
        .cfg_layout_id(cfg_layout_id),   // v2.3
        .frame_gen(frame_gen),           // v2.3: doorbell gen latch
        .frame_token(frame_token),       // v2.3: walker-side token face
        .start(db_start),
        .tr_we(tr_we), .tr_waddr(tr_waddr), .tr_wdata(tr_wdata),
        .tr_raddr(tr_raddr), .tr_rdata(tr_rdata)
    );

`ifdef PPU_ISLAND
    // M10.3 activation: island verdict/count nets (declared HERE, above
    // u_eng, so the port connections below reference declared wires --
    // port-connection implicit nets cannot be re-declared later).
    wire        ppu_done_w;              // walker arbiter verdict pulse
    wire        ppu_done_abort_w;        // 1 = token/engine failure
    wire [7:0]  ppu_done_err_w;          // abort err code (with pulse)
    wire [6:0]  ppu_desc_count_w;        // island loaded-DESC count
`endif

    m9_intra_axi_top_v3 u_eng (
        .clk(clk), .rst_n(rst_n),
        .cfg_nb(cfg_nb), .cfg_rc(cfg_rc), .cfg_ns(cfg_ns),
        .cfg_nseg(cfg_nseg), .cfg_s0_k(cfg_s0_k), .cfg_s0_jc(cfg_s0_jc),
        .cfg_s0_g(cfg_s0_g), .cfg_stride(cfg_stride), .cfg_obuf(cfg_obuf),
        .cfg_ybase(plan_base),    // M9.5c: CSR 0x04 = y-arena runtime base
        .cfg_overlap(cfg_overlap), .cfg_nconv(cfg_nconv),
        .cfg_ic(cfg_ic), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_kh(cfg_kh), .cfg_kw(cfg_kw), .cfg_sh(cfg_sh), .cfg_sw(cfg_sw),
        .cfg_ph(cfg_ph), .cfg_pw(cfg_pw),
        .cfg_first(cfg_first), .cfg_law_fetch(cfg_law_fetch),
        .cfg_xbase(arena_base),
        .cfg_wbase(w_base), .cfg_slab(cfg_slab),
        .cfg_rc_stride(cfg_rc_stride), .cfg_oc_stride(cfg_oc_stride),
        .cfg_oc(cfg_oc), .cfg_chain_mask(cfg_chain_mask),
        .cfg_nedge(cfg_nedge), .cfg_edge_node(cfg_edge_node),
        .cfg_edge_prod(cfg_edge_prod),
        .cfg_edge_win(cfg_edge_win),
        .cfg_join_tab(cfg_join_tab),
        .cfg_chain_rel(cfg_chain_rel),   // 2e
        .cfg_up2x(cfg_up2x),             // 5b
        // ---- v2.3 three-line face: PPU-side tie-off law (G3 identity) --
        // Conv-only bits have no PPU island: ppu_done* and ppu_desc_count
        // are tied off HERE (single integration point).  desc_count=0
        // makes any non-empty PPP table refuse with E_PPP_DESC (fail-fast
        // "PPU island absent"); the empty table keeps the v1 path
        // byte-identical (G3 T7 gate).  The two-island combined top
        // (M10.2 G4/G5 batch) replaces this tie-off with the real
        // ppu_start/ppu_done/frame_token PL lines.
`ifdef PPU_ISLAND
        // ---- M10.3 activation: real island verdict/count face (u_ppu).
        //      Issuer ppu_start/ppu_start_payload below now have the
        //      island as their consumer (ppu_start_w wires, L131 law). ----
        .ppu_done(ppu_done_w), .ppu_done_abort(ppu_done_abort_w),
        .ppu_done_err(ppu_done_err_w), .ppu_desc_count(ppu_desc_count_w),
`else
        .ppu_done(1'b0), .ppu_done_abort(1'b0), .ppu_done_err(8'd0),
        .ppu_desc_count(7'd0),
`endif
        // G2: doorbell token pulse still reaches the trace anchor composer
        // (observe-only; PPP FIFO gains one TOKEN_LATCH entry per frame).
        .tr_token_latch(frame_token),
        .cfg_ppp_tab(cfg_ppp_tab), .cfg_layout_id(cfg_layout_id),
        .frame_gen(frame_gen),
        .ppu_start(ppu_start_w), .ppu_start_payload(ppu_start_payload_w),
        .start(db_start), .busy(eng_busy), .done(eng_done), .err(err),
        .progress_blk(progress_blk),
        .pctl_addr(pctl_addr), .pctl_data(pctl_data),
        .strip_addr(strip_addr), .strip_data(strip_data),
        .lut_addr(lut_addr), .lut_data(lut_data),
        .cv_addr(cv_addr), .cv_iss(cv_iss), .cv_geo(cv_geo),
        .cv_wlay(cv_wlay), .conv_idx(conv_idx_w),
        .cnt_beats(cnt_beats), .cnt_stall(cnt_stall),
        .cnt_csr_w(cnt_csr_w), .cnt_y_bytes(cnt_y_bytes),
        .cnt_y_blocks(cnt_y_blocks), .cnt_chain_bytes(cnt_chain_bytes),
        .m0_araddr(m0_araddr), .m0_arlen(m0_arlen),
        .m0_arvalid(m0_arvalid), .m0_arready(m0_arready),
        .m0_rdata(m0_rdata), .m0_rresp(m0_rresp),
        .m0_rvalid(m0_rvalid), .m0_rlast(m0_rlast), .m0_rready(m0_rready),
        .m1_araddr(m1_araddr), .m1_arlen(m1_arlen),
        .m1_arvalid(m1_arvalid), .m1_arready(m1_arready),
        .m1_rdata(m1_rdata), .m1_rresp(m1_rresp),
        .m1_rvalid(m1_rvalid), .m1_rlast(m1_rlast), .m1_rready(m1_rready),
        .m2_awaddr(m2_awaddr), .m2_awlen(m2_awlen),
        .m2_awvalid(m2_awvalid), .m2_awready(m2_awready),
        .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb),
        .m2_wvalid(m2_wvalid), .m2_wready(m2_wready),
        .m2_bresp(m2_bresp), .m2_bvalid(m2_bvalid), .m2_bready(m2_bready),
        .tr_we(tr_we), .tr_waddr(tr_waddr), .tr_wdata(tr_wdata),
        .tr_raddr(tr_raddr), .tr_rdata(tr_rdata),
        .tr_ring_ovr(tr_ring_ovr), .tr_steady_end(tr_steady_end),
        .tr_last_compute(tr_last_compute),
        .tr_array_active(tr_array_active),
        .s2l_cnt(iss_s2l_cnt), .skew_max(hb_skew_max), .hb_dbg(hb_dbg)   // 2e + r7
    );

`ifdef PPU_ISLAND
    // ================= M10.3: PPU island (activation state only) ========
    // Island = src/rtl_ppu/ppu_f7_top.v (V1.9-M10.3: main-tree V1.8 byte
    // copy + PL face export). Three-line wiring (DESIGN_m8_v23 section 3.1):
    //   CSR frame_gen/frame_token (V3.0 outputs, unmodified) -> walker gen
    //   latch; issuer ppu_start/ppu_start_payload -> walker PL entry;
    //   walker verdict -> issuer. GEMM stub m1_axi = zero-flow face, tied
    //   (v23b BD precedent: only m_axi was wired; stub law section 1.3).
    // (verdict/count wires declared above u_eng -- see that site.)
    ppu_f7_top u_ppu (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        // AXI4-Lite slave: BD GP0 second segment (0x43C2_0000/64K)
        .s_axi_awaddr  (s2_axi_awaddr),  .s_axi_awprot(s2_axi_awprot),
        .s_axi_awvalid (s2_axi_awvalid), .s_axi_awready(s2_axi_awready),
        .s_axi_wdata   (s2_axi_wdata),   .s_axi_wstrb  (s2_axi_wstrb),
        .s_axi_wvalid  (s2_axi_wvalid),  .s_axi_wready (s2_axi_wready),
        .s_axi_bresp   (s2_axi_bresp),   .s_axi_bvalid (s2_axi_bvalid),
        .s_axi_bready  (s2_axi_bready),
        .s_axi_araddr  (s2_axi_araddr),  .s_axi_arprot(s2_axi_arprot),
        .s_axi_arvalid (s2_axi_arvalid), .s_axi_arready(s2_axi_arready),
        .s_axi_rdata   (s2_axi_rdata),   .s_axi_rresp  (s2_axi_rresp),
        .s_axi_rvalid  (s2_axi_rvalid),  .s_axi_rready (s2_axi_rready),
        // AXI4 master: shell DMA -> BD -> PS7 HP1
        .m_axi_araddr  (m3_axi_araddr),  .m_axi_arlen  (m3_axi_arlen),
        .m_axi_arsize  (m3_axi_arsize),  .m_axi_arburst(m3_axi_arburst),
        .m_axi_arvalid (m3_axi_arvalid), .m_axi_arready(m3_axi_arready),
        .m_axi_rdata   (m3_axi_rdata),   .m_axi_rresp  (m3_axi_rresp),
        .m_axi_rlast   (m3_axi_rlast),   .m_axi_rvalid (m3_axi_rvalid),
        .m_axi_rready  (m3_axi_rready),
        .m_axi_awaddr  (m3_axi_awaddr),  .m_axi_awlen  (m3_axi_awlen),
        .m_axi_awsize  (m3_axi_awsize),  .m_axi_awburst(m3_axi_awburst),
        .m_axi_awvalid (m3_axi_awvalid), .m_axi_awready(m3_axi_awready),
        .m_axi_wdata   (m3_axi_wdata),   .m_axi_wstrb  (m3_axi_wstrb),
        .m_axi_wlast   (m3_axi_wlast),   .m_axi_wvalid (m3_axi_wvalid),
        .m_axi_wready  (m3_axi_wready),
        .m_axi_bresp   (m3_axi_bresp),   .m_axi_bvalid (m3_axi_bvalid),
        .m_axi_bready  (m3_axi_bready),
        // GEMM stub second DMA master: zero-flow (u_gemm stubbed V1.8,
        // u_gdma user face tied all-zero inside the island) -- response
        // side tied here, request side left open (v23b BD same law).
        .m1_axi_arready(1'b0), .m1_axi_rdata(64'd0), .m1_axi_rresp(2'b00),
        .m1_axi_rlast  (1'b0), .m1_axi_rvalid(1'b0),
        .m1_axi_awready(1'b0), .m1_axi_wready(1'b0),
        .m1_axi_bresp  (2'b00), .m1_axi_bvalid(1'b0),
        .irq_o         (),
        // ---- v2.3 three-line PL face (walker f6, M10.2 blood) ----
        .ppu_start_pl_i     (ppu_start_w),
        .ppp_payload_pl_i   (ppu_start_payload_w),
        .frame_token_pl_i   (frame_gen),
        .token_valid_pl_i   (frame_token),
        .ppu_done_pl_o      (ppu_done_w),
        .ppp_done_abort_pl_o(ppu_done_abort_w),
        .ppp_done_err_pl_o  (ppu_done_err_w),
        .ppu_desc_count_pl_o(ppu_desc_count_w)
    );
`endif

endmodule
