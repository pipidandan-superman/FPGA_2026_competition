/************************************************************************
 * File Name       : m9_intra_axi_top.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_intra_axi_top
 * Description     :
 *   M9.5b V2.5 wrapper: the proven m9_intra_top (byte faces, engine
 *   zero diff) with its three byte-memory faces served by AXI32 HP
 *   adapters (02_m9_issuer_spec.md section 1 V2.5 data movement):
 *
 *     x window byte reads  <- m9_axi_rd_v2 u_xrd  (HP0 read master)
 *     w feeder byte reads  <- m9_axi_rd_v2 u_wrd  (HP3 read master)
 *     y scatter byte writes-> m9_axi_wr u_ywr (HP0 write master)
 *
 *   Cores stay byte-face identical (sibling composition, not changes);
 *   the plan-blob BRAM reader + ABI v2 CSR slave land on this wrapper
 *   next (M9.5b cont.).
 *
 *   Frame-end flush: y write master drains its line when the intra
 *   top goes idle after start (partial tail line law in m9_axi_wr).
 *
 * Dependencies    : m9_intra_top.v, m9_axi_rd_v2.v, m9_axi_wr.v
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 *   - V1.1 (2026-10-10) : r6 ROM-widening: plan ROM addr ports pctl
 *     11b / strip 8b / lut 12b (NCONV_MAX=16, address-plane only).
 *   - V1.2 (2026-10-13) : M9.3 closure: u_xrd/u_wrd swapped to
 *     m9_axi_rd_v2 (multi-outstanding + 64-line cache + speculative
 *     top-up); client byte-serve contract unchanged.
 *   - V1.3 (2026-10-13) : cnt_beats port widened 19 -> 32 bits (m9_intra_top
 *     V1.6); pure width passthrough, zero logic change.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_intra_axi_top (
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
    input  wire [135:0] cv_wlay      ,
    output wire [4:0]  conv_idx      ,
    output wire [31:0] cnt_beats     ,
    output wire [31:0] cnt_stall     ,
    output wire [15:0] cnt_csr_w     ,
    output wire [19:0] cnt_y_bytes   ,
    output wire [9:0]  cnt_y_blocks  ,
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
    output wire        tr_last_compute
);

    // ---- byte faces between cores and adapters ----
    wire [31:0] xaddr, waddr, yaddr;
    wire        xreq, wreq, yreq;
    wire [7:0]  xdata, wdata, ywdata;
    wire        xvalid, wvalid;
    wire        x_ddr_gap, w_ddr_gap, y_fifo_full;
    wire        tr_store_active = m2_wvalid && m2_wready;

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

    m9_intra_top u_dut (
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
        .xaddr(xaddr), .xreq(xreq), .xdata(xdata), .xvalid(xvalid),
        .waddr(waddr), .wreq(wreq), .wdata(wdata), .wvalid(wvalid),
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
        .tr_last_compute(tr_last_compute)
    );

    m9_axi_rd_v2 u_xrd (
        .clk_i(clk), .rst_n_i(rst_n),
        .raddr_i(xaddr), .rreq_i(xreq), .rdata_o(xdata), .rvalid_o(xvalid),
        .m_araddr_o(m0_araddr), .m_arlen_o(m0_arlen),
        .m_arvalid_o(m0_arvalid), .m_arready_i(m0_arready),
        .m_rdata_i(m0_rdata), .m_rresp_i(m0_rresp),
        .m_rvalid_i(m0_rvalid), .m_rlast_i(m0_rlast), .m_rready_o(m0_rready),
        .ddr_gap_wait_o(x_ddr_gap)
    );

    m9_axi_rd_v2 u_wrd (
        .clk_i(clk), .rst_n_i(rst_n),
        .raddr_i(waddr), .rreq_i(wreq), .rdata_o(wdata), .rvalid_o(wvalid),
        .m_araddr_o(m1_araddr), .m_arlen_o(m1_arlen),
        .m_arvalid_o(m1_arvalid), .m_arready_i(m1_arready),
        .m_rdata_i(m1_rdata), .m_rresp_i(m1_rresp),
        .m_rvalid_i(m1_rvalid), .m_rlast_i(m1_rlast), .m_rready_o(m1_rready),
        .ddr_gap_wait_o(w_ddr_gap)
    );

    m9_axi_wr u_ywr (
        .clk(clk), .rst_n(rst_n),
        .yaddr(yaddr), .yreq(yreq), .ywdata(ywdata),
        .flush(wr_flush), .busy(ywr_busy),
        .m_awaddr(m2_awaddr), .m_awlen(m2_awlen),
        .m_awvalid(m2_awvalid), .m_awready(m2_awready),
        .m_wdata(m2_wdata), .m_wstrb(m2_wstrb),
        .m_wvalid(m2_wvalid), .m_wready(m2_wready),
        .m_bresp(m2_bresp), .m_bvalid(m2_bvalid), .m_bready(m2_bready),
        .fifo_full_wait(y_fifo_full)
    );

endmodule
