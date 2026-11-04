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
 *                         the r11 inert carrier (contact #2 "r11 裁",
 *                         SPEC §8 OPEN-1/2): rp_arm tied 1'b0, u_repack
 *                         carried under keep_hierarchy.  Without
 *                         M11_REPACK this file compiles byte-identical
 *                         to the r10 shadow.
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
    output wire [31:0] s2l_cnt       ,   // 2e: CHAIN_S2L_CNT (CSR 0xE4)
    output wire [31:0] skew_max      ,   // 2e: CHAIN_SKEW_MAX (CSR 0xE8)
    output wire [511:0] hb_dbg       ,   // r7 debug aperture (cursor 0xF8/0xFC)
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
    input  wire         tr_token_latch,  // G2: CSR frame_token doorbell pulse
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    output wire [7:0]  err           ,
    output wire [11:0] progress_blk  ,
    // ---- ROM read ports (plan faces, TB/board blob BRAM) ----
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
    output wire [4:0]  conv_idx      ,
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
    wire [4:0]  conv_idx_w;   // r10: issuer conv_idx is 5b (25 convs)
    wire        dut_busy, dut_done;
    wire [7:0]  dut_err;
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
    // effective producer per edge (adjacent fallback law), 4-bit
    function [3:0] eff_prod;
        input [7:0] node;
        input [7:0] pfield;
        begin
            eff_prod = (pfield != 8'd0) ? (pfield[3:0] - 4'd1)
                                        : (node[3:0] - 4'd1);
        end
    endfunction
    always @(*) begin
        cfg_bad = (cfg_nedge != 4'd0) && (cfg_nedge > 4'd8);
        for (mi = 0; mi < 8; mi = mi + 1) begin
            if ((cfg_nedge != 4'd0) && (mi < cfg_nedge)) begin
                if ((cfg_edge_node[mi*8 +: 8] == 8'd0) ||
                    (cfg_edge_node[mi*8 +: 8] >= {3'd0, cfg_nconv}))
                    cfg_bad = 1'b1;
                if ((cfg_edge_win[mi*16 +: 16] == 16'd0) ||
                    (cfg_edge_win[mi*16 +: 16] > 16'd32768))
                    cfg_bad = 1'b1;
                // 2d: explicit producer ordering + bounds
                if ((cfg_edge_prod[mi*8 +: 8] != 8'd0) &&
                    ((cfg_edge_prod[mi*8 +: 8] - 8'd1)
                        >= cfg_edge_node[mi*8 +: 8]))
                    cfg_bad = 1'b1;   // producer must precede consumer
                if ((cfg_edge_prod[mi*8 +: 8] != 8'd0) &&
                    ((cfg_edge_prod[mi*8 +: 8] - 8'd1)
                        >= {3'd0, cfg_nconv}))
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
    reg         mask_err_latch;   // sticky until next start (err 10)
    reg         cfg_err_latch;    // sticky until next start (err 12)
    reg         join_err_latch;   // 5b sticky until next start (err 13)
    reg         rej_done_l;       // synthesized done for a rejected frame
    reg  [4:0]  rej_done_c;
    wire        rej_now    = mask_err_now | cfg_err_now | join_bad_ad;
    wire        eng_start  = start & ~rej_now;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_err_latch <= 1'b0; cfg_err_latch <= 1'b0;
            join_err_latch <= 1'b0;
            rej_done_l <= 1'b0; rej_done_c <= 5'd0;
        end else if (start) begin
            mask_err_latch <= mask_err_now; cfg_err_latch <= cfg_err_now;
            join_err_latch <= join_bad_ad;
            rej_done_l <= 1'b0; rej_done_c <= 5'd0;
        end else if ((mask_err_latch | cfg_err_latch | join_err_latch)
                     && !rej_done_l) begin
            if (rej_done_c == 5'd16) rej_done_l <= 1'b1;
            else                     rej_done_c <= rej_done_c + 5'd1;
        end
    end

    // DDR line-queue outstanding counter (in-order merge guard: a
    // chained HBUF response is served only while u_xrd is drained).
    reg [4:0]  ddr_q;
    wire       x_lreq_ddr = x_rreq_line & ~chain_sel;
    wire       x_lreq_hbuf = x_rreq_line & chain_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ddr_q <= 5'd0;
        else if (start) ddr_q <= 5'd0;
        else case ({x_lreq_ddr, x_rvalid_ddr})
            2'b10: ddr_q <= ddr_q + 5'd1;
            2'b01: ddr_q <= ddr_q - 5'd1;
            default: ddr_q <= ddr_q;
        endcase
    end
    wire ddr_q_empty = (ddr_q == 5'd0);

    assign busy  = dut_busy;
    assign done  = dut_done | rej_done_l;
    wire        hb_join_cfg;      // 5b: E_CHAIN_JOIN=13 sticky
    assign err   = dut_err
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
    wire        x_ddr_gap, w_ddr_gap, y_fifo_full;
    wire        tr_store_active = m2_wvalid && m2_wready;

`ifdef M11_REPACK
    // ================ M11 repack merge (SPEC_m11_repack.md §7) =========
    // All of the following exists ONLY under M11_REPACK.  Without the
    // define the r10 datapath (yaddr/yreq/ywdata straight into u_ywr) is
    // bit-identical.
    //
    // contact #2 config face -- r11 inert carrier: the M11 config line
    // (CSR idle slots per the 0xE9/0xEA table-load canon, or issuer ROM
    // card extension; SPEC §8 OPEN-1/2 ruling) replaces these tie-offs.
    // rp_arm = 1'b0: u_repack can never arm -> rreq/wreq never fire ->
    // the write arbiter is a structural pass-through and the read FIFO
    // stays empty.  ABI/CAP0 untouched (identity law, cap0=4d390230).
    wire        rp_arm       = 1'b0;
    wire [31:0] rp_src_base  = 32'd0;
    wire [31:0] rp_dst_base  = 32'd0;
    wire [15:0] rp_c         = 16'd0;
    wire [15:0] rp_h         = 16'd0;
    wire [15:0] rp_w         = 16'd0;
    wire [15:0] rp_vc        = 16'd0;
    wire [31:0] rp_ypitch    = 32'd0;
    wire [15:0] rp_nb        = 16'd0;
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
`endif // M11_REPACK

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
        jn_ka[0]   <= jn_ya0 - jn_lo0 + cfg_ybase;
        jn_kb[0]   <= jn_yb0 - (jn_lo0 + jn_sp0) + cfg_ybase;
        jn_sphi[0] <= jn_lo0 + jn_sp0;
        jn_ka[1]   <= jn_ya1 - jn_lo1 + cfg_ybase;
        jn_kb[1]   <= jn_yb1 - (jn_lo1 + jn_sp1) + cfg_ybase;
        jn_sphi[1] <= jn_lo1 + jn_sp1;
        jn_ka[2]   <= jn_ya2 - jn_lo2 + cfg_ybase;
        jn_kb[2]   <= jn_yb2 - (jn_lo2 + jn_sp2) + cfg_ybase;
        jn_sphi[2] <= jn_lo2 + jn_sp2;
        jn_ka[3]   <= jn_ya3 - jn_lo3 + cfg_ybase;
        jn_kb[3]   <= jn_yb3 - (jn_lo3 + jn_sp3) + cfg_ybase;
        jn_sphi[3] <= jn_lo3 + jn_sp3;
        aff_off    <= cfg_ybase - cfg_xbase;
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
    wire [3:0]  iss_prod_conv;         // 2e-fix: drained producer conv
    m9_hbuf_ctrl u_hbuf (
        .clk(clk), .rst_n(rst_n),
        .start(start), .cfg_chain_mask(cfg_chain_mask),
        .cfg_nedge(cfg_nedge), .edge_node(cfg_edge_node),
        .edge_prod(cfg_edge_prod),
        .edge_win(cfg_edge_win), .cfg_nconv(cfg_nconv),
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
        .hb_dbg(hb_dbg)
    );

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
    wire        ywr_busy;
    wire        wr_flush = frm_started & ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                              frm_started <= 1'b0;
        else if (start)                          frm_started <= 1'b1;
        else if (frm_started & ~busy & ~ywr_busy) frm_started <= 1'b0;
    end

    m9_intra_top_v3 u_dut (
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
        .start(eng_start), .busy(dut_busy), .done(dut_done), .err(dut_err),
        .progress_blk(progress_blk),
        .pctl_addr(pctl_addr), .pctl_data(pctl_data),
        .strip_addr(strip_addr), .strip_data(strip_data),
        .lut_addr(lut_addr), .lut_data(lut_data),
        .cv_addr(cv_addr), .cv_iss(cv_iss), .cv_geo(cv_geo),
        .cv_wlay(cv_wlay), .conv_idx(conv_idx_w),
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
        .ppu_done_err(ppu_done_err), .ppu_desc_count(ppu_desc_count),
        .tr_token_latch(tr_token_latch)
`ifdef M11_REPACK
        ,.sc_done_out(sc_done_w)
`endif
    );

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
    // -------- M11 repack instances (contacts #1/#3/#4/#5/#6) -------------
    // keep_hierarchy carries u_repack into the routed netlist for the
    // r11 fingerprint gate while the config face is the inert carrier.
    (* keep_hierarchy = "yes" *) m9_scatter_chw_repack u_repack (
        .clk(clk), .rst_n(rst_n),
        .rp_arm(rp_arm), .rp_src_base(rp_src_base),
        .rp_dst_base(rp_dst_base),
        .rp_c(rp_c), .rp_h(rp_h), .rp_w(rp_w), .rp_vc(rp_vc),
        .rp_ypitch(rp_ypitch), .rp_nb(rp_nb),
        // contact #3: producer seal from u_ys's EXISTING outputs (the
        // sc_done sticky level via the intra-top export; the cumulative
        // y_blocks ledger was already a top-level output).  Zero change
        // to m9_y_scatter.
        .sc_done_lvl(sc_done_w), .sc_blocks(cnt_y_blocks),
        // contact #4: start pulse from the glue's top FF
        .rp_start(rp_start_w),
        .rp_busy(rp_busy_w), .rp_done(), .rp_err(), .rp_err_code(),
        // contact #5: read port <- glue return FIFO (fixed 1-cycle law)
        .raddr(rp_raddr), .rreq(rp_rreq), .rdata(rp_rdata),
        // contact #6: write port -> glue arbitration -> shared u_ywr
        .waddr(rp_waddr), .wreq(rp_wreq), .wdata(rp_wdata),
        .rp_bytes()
    );

    m9_repack_glue u_repack_glue (
        .clk(clk), .rst_n(rst_n),
        .rp_arm(rp_arm), .rp_src_base(rp_src_base),
        .rp_dst_base(rp_dst_base),
        .rp_c(rp_c), .rp_h(rp_h), .rp_w(rp_w), .rp_vc(rp_vc),
        .rp_ypitch(rp_ypitch), .rp_nb(rp_nb),
        .sc_done_lvl(sc_done_w), .sc_blocks(cnt_y_blocks),
        .rp_busy_i(rp_busy_w),
        .rp_start(rp_start_w),
        .rp_raddr(rp_raddr), .rp_rreq(rp_rreq), .rp_rdata(rp_rdata),
        .sc_yaddr(yaddr), .sc_yreq(yreq), .sc_ywdata(ywdata),
        .rp_waddr(rp_waddr), .rp_wreq(rp_wreq), .rp_wdata(rp_wdata),
        .mrg_yaddr(yaddr_m), .mrg_yreq(yreq_m), .mrg_ywdata(ywdata_m),
        // contact #5a glue AXI read master: r11 inert carrier -- outputs
        // dangle (never armed); the M11 line punches this face through
        // the shim/BD per the r9b s2_axi/m03_axi boundary precedent.
        .m_araddr(), .m_arlen(), .m_arvalid(),
        .m_arready(1'b0), .m_rdata(64'd0), .m_rresp(2'b00),
        .m_rvalid(1'b0), .m_rlast(1'b0), .m_rready(),
        .dbg_col(), .dbg_warm()
    );
`endif // M11_REPACK

    // contact #6: the shared m9_axi_wr takes the merged face under
    // M11_REPACK, the original scatter face otherwise (m9_axi_wr itself
    // is untouched in both modes).
    m9_axi_wr u_ywr (
        .clk(clk), .rst_n(rst_n),
`ifdef M11_REPACK
        .yaddr(yaddr_m), .yreq(yreq_m), .ywdata(ywdata_m),
`else
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
`endif
        .flush(wr_flush), .busy(ywr_busy),
        .m_awaddr(m2_awaddr), .m_awlen(m2_awlen),
        .m_awvalid(m2_awvalid), .m_awready(m2_awready),
        .m_wdata(m2_wdata), .m_wstrb(m2_wstrb),
        .m_wvalid(m2_wvalid), .m_wready(m2_wready),
        .m_bresp(m2_bresp), .m_bvalid(m2_bvalid), .m_bready(m2_bready),
        .fifo_full_wait(y_fifo_full)
    );

endmodule
