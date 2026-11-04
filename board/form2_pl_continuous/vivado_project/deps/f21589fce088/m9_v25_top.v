/************************************************************************
 * File Name       : m9_v25_top.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_v25_top
 * Description     :
 *   M9.5c V2.5 board top: m9_abi_v2_csr (ABI v2 PS face) driving the
 *   proven m9_intra_axi_top (engine + AXI adapters).  Pure composition
 *   -- both children are gate-proven siblings and stay byte-identical.
 *
 *   PS frame law (M9.5 board gate):
 *     setup : PS writes CFG and base regs via S_AXI + fills the plan
 *             BRAM (attached at the BD level to the ROM faces below)
 *     frame : PS writes DOORBELL once -> start -> ZERO PS traffic until
 *             STATUS.done (帧中零 PS 证明: doorbell 单发 + 台账)
 *
 *   done law: the intra walk finishes before the y write master has
 *   necessarily drained its tail line, so this level gates done:
 *   done_v25 = intra done HELD until the y master is idle.  busy_v25
 *   = intra busy | y-write busy so PS polling sees the true frame
 *   extent.  (The engine itself is untouched -- this is wrapper law.)
 *
 *   Plan faces pass straight through to the BD plan BRAM (registered
 *   read, one row per address -- the proven m9 face).
 *
 * Dependencies    : m9_abi_v2_csr.v, m9_intra_axi_top.v
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5c.
 *   - V1.1 (2026-10-10) : r6 ROM-widening: plan ROM addr ports pctl
 *     11b / strip 8b / lut 12b (NCONV_MAX=16, address-plane only).
 *   - V1.2 (2026-10-13) : cnt_beats wire widened 19 -> 32 bits (m9_intra_top
 *     V1.6); pure width passthrough, zero logic change.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_v25_top (
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
    input  wire [135:0] cv_wlay      ,
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
    output wire        m2_bready
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
    wire        db_start;

    // ---- engine status (pre-done-gate) + counters ----
    wire        eng_busy, eng_done;
    wire [7:0]  err;
    wire [11:0] progress_blk;
    wire [31:0] cnt_beats;
    wire [31:0] cnt_stall;
    wire [15:0] cnt_csr_w;
    wire [19:0] cnt_y_bytes;
    wire [9:0]  cnt_y_blocks;
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
        .cnt_stall(cnt_stall),
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
        .start(db_start),
        .tr_we(tr_we), .tr_waddr(tr_waddr), .tr_wdata(tr_wdata),
        .tr_raddr(tr_raddr), .tr_rdata(tr_rdata)
    );

    m9_intra_axi_top u_eng (
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
        .cfg_oc(cfg_oc),
        .start(db_start), .busy(eng_busy), .done(eng_done), .err(err),
        .progress_blk(progress_blk),
        .pctl_addr(pctl_addr), .pctl_data(pctl_data),
        .strip_addr(strip_addr), .strip_data(strip_data),
        .lut_addr(lut_addr), .lut_data(lut_data),
        .cv_addr(cv_addr), .cv_iss(cv_iss), .cv_geo(cv_geo),
        .cv_wlay(cv_wlay), .conv_idx(),
        .cnt_beats(cnt_beats), .cnt_stall(cnt_stall),
        .cnt_csr_w(cnt_csr_w), .cnt_y_bytes(cnt_y_bytes),
        .cnt_y_blocks(cnt_y_blocks),
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
        .tr_last_compute(tr_last_compute)
    );

endmodule
