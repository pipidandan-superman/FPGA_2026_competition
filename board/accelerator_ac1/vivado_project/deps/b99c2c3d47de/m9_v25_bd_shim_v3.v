/************************************************************************
 * File Name       : m9_v25_bd_shim.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_v25_bd_shim
 * Description     :
 *   M9.5c V2.5 board-domain shim: re-exposes the gate-proven m9_v25_top
 *   (TB_M9_V25_PASS) under canonical BD-interface names so Vivado block
 *   design interface inference binds it (m9_v25_top uses short names
 *   s_awaddr/m0_araddr/... which inference does not recognize).
 *
 *   Faces:
 *     s_axi_*   AXI4-Lite slave  (PS GP0; low byte of the address goes
 *               to the CSR -- the BD assigns a 4K region, the PS driver
 *               addresses base+reg offset)
 *     m00_axi_* AXI4 read master (x window  -> PS7 HP0)
 *     m01_axi_* AXI4 read master (w feeder  -> PS7 HP3)
 *     m02_axi_* AXI4 write master (y scatter -> PS7 HP2; the spec's
 *               "HP0 write" comment maps to a dedicated HP port instead
 *               of a 2:1 interconnect on HP0 -- wiring choice at the BD,
 *               byte stream identical)
 *     pctl/strip/lut/cv_*  plan ROM faces as plain pins -- they exit
 *               the BD and meet the six BMG ROMs at the board top
 *               (m9_plan_roms), bitstream-baked from golden94 COE.
 *
 *   The masters are single-beat 64b (ARLEN/AWLEN=0) -- the AXI4 control
 *   fields this shim adds are constants (size=8B, burst=INCR).  This
 *   module is pure wiring: m9_v25_top stays byte-identical to its gate.
 *
 * Dependencies    : m9_v25_top
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5c.
 *   - V1.1 (2026-10-10) : r6 ROM-widening: plan ROM addr pins pctl
 *     11b / strip 8b / lut 12b (NCONV_MAX=16, address-plane only).
 *   - V1.2-M10.3 (2026-10-17): PPU island activation faces, ALL inside
 *     `ifdef PPU_ISLAND` (default OFF = port face and netlist structure
 *     byte-identical to g3r9 silicon, T7 identity law): s2_axi AXI4-Lite
 *     passthrough (island CSR, GP0 second segment) + m03_axi AXI4 master
 *     passthrough (island shell DMA, HP1) with tail-law control
 *     constants. The island instance itself is u_ppu inside
 *     m9_v25_top_v3 (same switch). See PPU_ACTIVATION_PLAN.md section 6.1.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_v25_bd_shim (
    // ---- clock / reset (FCLK + proc_sys_reset) ----
    input  wire        s_axi_aclk      ,
    input  wire        s_axi_aresetn   ,
    // ---- AXI4-Lite slave (PS GP0) ----
    input  wire [31:0] s_axi_awaddr    ,
    input  wire [2:0]  s_axi_awprot    ,
    input  wire        s_axi_awvalid   ,
    output wire        s_axi_awready   ,
    input  wire [31:0] s_axi_wdata     ,
    input  wire [3:0]  s_axi_wstrb     ,
    input  wire        s_axi_wvalid    ,
    output wire        s_axi_wready    ,
    output wire [1:0]  s_axi_bresp     ,
    output wire        s_axi_bvalid    ,
    input  wire        s_axi_bready    ,
    input  wire [31:0] s_axi_araddr    ,
    input  wire [2:0]  s_axi_arprot    ,
    input  wire        s_axi_arvalid   ,
    output wire        s_axi_arready   ,
    output wire [31:0] s_axi_rdata     ,
    output wire [1:0]  s_axi_rresp     ,
    output wire        s_axi_rvalid    ,
    input  wire        s_axi_rready    ,
    // ---- AXI4 read master m00: x window (HP0) ----
    output wire [31:0] m00_axi_araddr  ,
    output wire [7:0]  m00_axi_arlen   ,
    output wire [2:0]  m00_axi_arsize  ,
    output wire [1:0]  m00_axi_arburst ,
    output wire        m00_axi_arlock  ,
    output wire [3:0]  m00_axi_arcache ,
    output wire [2:0]  m00_axi_arprot  ,
    output wire [3:0]  m00_axi_arqos   ,
    output wire        m00_axi_arvalid ,
    input  wire        m00_axi_arready ,
    input  wire [63:0] m00_axi_rdata   ,
    input  wire [1:0]  m00_axi_rresp   ,
    input  wire        m00_axi_rlast   ,
    input  wire        m00_axi_rvalid  ,
    output wire        m00_axi_rready  ,
    // ---- AXI4 read master m01: w feeder (HP3) ----
    output wire [31:0] m01_axi_araddr  ,
    output wire [7:0]  m01_axi_arlen   ,
    output wire [2:0]  m01_axi_arsize  ,
    output wire [1:0]  m01_axi_arburst ,
    output wire        m01_axi_arlock  ,
    output wire [3:0]  m01_axi_arcache ,
    output wire [2:0]  m01_axi_arprot  ,
    output wire [3:0]  m01_axi_arqos   ,
    output wire        m01_axi_arvalid ,
    input  wire        m01_axi_arready ,
    input  wire [63:0] m01_axi_rdata   ,
    input  wire [1:0]  m01_axi_rresp   ,
    input  wire        m01_axi_rlast   ,
    input  wire        m01_axi_rvalid  ,
    output wire        m01_axi_rready  ,
    // ---- AXI4 write master m02: y scatter (HP2) ----
    output wire [31:0] m02_axi_awaddr  ,
    output wire [7:0]  m02_axi_awlen   ,
    output wire [2:0]  m02_axi_awsize  ,
    output wire [1:0]  m02_axi_awburst ,
    output wire        m02_axi_awlock  ,
    output wire [3:0]  m02_axi_awcache ,
    output wire [2:0]  m02_axi_awprot  ,
    output wire [3:0]  m02_axi_awqos   ,
    output wire        m02_axi_awvalid ,
    input  wire        m02_axi_awready ,
    output wire [63:0] m02_axi_wdata   ,
    output wire [7:0]  m02_axi_wstrb   ,
    output wire        m02_axi_wlast   ,
    output wire        m02_axi_wvalid  ,
    input  wire        m02_axi_wready  ,
    input  wire [1:0]  m02_axi_bresp   ,
    input  wire        m02_axi_bvalid  ,
    output wire        m02_axi_bready  ,
    // ---- plan ROM faces (plain pins -> m9_plan_roms at board top) ----
    // r10 widths (2026-10-18): pctl 12b / strip 9b / lut 13b, cv 5b
    // (25 live convs; was r6 11b/8b/12b/4b, NCONV_MAX=16)
    output wire [11:0] pctl_addr       ,
    input  wire [95:0] pctl_data       ,
    output wire [8:0]  strip_addr      ,
    input  wire [20:0] strip_data      ,
    output wire [12:0] lut_addr        ,
    input  wire [7:0]  lut_data        ,
    output wire [4:0]  cv_addr         ,
    input  wire [255:0] cv_iss         ,
    input  wire [105:0] cv_geo         ,
    // 2a: m9_bm_wlay widened 136->168 (ch_stride tail)
    input  wire [167:0] cv_wlay
`ifdef PPU_ISLAND
    // ---- M10.3 PPU island activation faces (PPU_ACTIVATION_PLAN section
    //      6.1 item 3). Switch-gated: with PPU_ISLAND undefined this port
    //      face is BYTE-IDENTICAL to the g3r9 silicon face (BD module-ref
    //      cache .xci law + T7 identity law). The island itself lives
    //      inside m9_v25_top_v3 (u_ppu); the shim only re-exposes its two
    //      AXI faces under canonical BD interface names. ----
    // s2: PPU island AXI4-Lite slave (PS GP0 second segment, 0x43C2_0000;
    //     full 32-bit address -- the island decodes its own windows)
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
    // m03: PPU island AXI4 master (shell DMA 64b INCR <=16 beats -> HP1)
    output wire [31:0] m03_axi_araddr  ,
    output wire [7:0]  m03_axi_arlen   ,
    output wire [2:0]  m03_axi_arsize  ,
    output wire [1:0]  m03_axi_arburst ,
    output wire        m03_axi_arlock  ,
    output wire [3:0]  m03_axi_arcache ,
    output wire [2:0]  m03_axi_arprot  ,
    output wire [3:0]  m03_axi_arqos   ,
    output wire        m03_axi_arvalid ,
    input  wire        m03_axi_arready ,
    input  wire [63:0] m03_axi_rdata   ,
    input  wire [1:0]  m03_axi_rresp   ,
    input  wire        m03_axi_rlast   ,
    input  wire        m03_axi_rvalid  ,
    output wire        m03_axi_rready  ,
    output wire [31:0] m03_axi_awaddr  ,
    output wire [7:0]  m03_axi_awlen   ,
    output wire [2:0]  m03_axi_awsize  ,
    output wire [1:0]  m03_axi_awburst ,
    output wire        m03_axi_awlock  ,
    output wire [3:0]  m03_axi_awcache ,
    output wire [2:0]  m03_axi_awprot  ,
    output wire [3:0]  m03_axi_awqos   ,
    output wire        m03_axi_awvalid ,
    input  wire        m03_axi_awready ,
    output wire [63:0] m03_axi_wdata   ,
    output wire [7:0]  m03_axi_wstrb   ,
    output wire        m03_axi_wlast   ,
    output wire        m03_axi_wvalid  ,
    input  wire        m03_axi_wready  ,
    input  wire [1:0]  m03_axi_bresp   ,
    input  wire        m03_axi_bvalid  ,
    output wire        m03_axi_bready
`endif
);

    // ---------------- core (gate-proven, byte-identical) ----------------
    m9_v25_top_v3 u_core (

        .clk        (s_axi_aclk),
        .rst_n      (s_axi_aresetn),
        // AXI-Lite face: low address byte carries the register offset
        .s_awaddr   (s_axi_awaddr[7:0]),
        .s_awprot   (s_axi_awprot),
        .s_awvalid  (s_axi_awvalid),
        .s_awready  (s_axi_awready),
        .s_wdata    (s_axi_wdata),
        .s_wstrb    (s_axi_wstrb),
        .s_wvalid   (s_axi_wvalid),
        .s_wready   (s_axi_wready),
        .s_bresp    (s_axi_bresp),
        .s_bvalid   (s_axi_bvalid),
        .s_bready   (s_axi_bready),
        .s_araddr   (s_axi_araddr[7:0]),
        .s_arprot   (s_axi_arprot),
        .s_arvalid  (s_axi_arvalid),
        .s_arready  (s_axi_arready),
        .s_rdata    (s_axi_rdata),
        .s_rresp    (s_axi_rresp),
        .s_rvalid   (s_axi_rvalid),
        .s_rready   (s_axi_rready),
        // x window read master
        .m0_araddr  (m00_axi_araddr),
        .m0_arlen   (m00_axi_arlen[3:0]),
        .m0_arvalid (m00_axi_arvalid),
        .m0_arready (m00_axi_arready),
        .m0_rdata   (m00_axi_rdata),
        .m0_rresp   (),
        .m0_rvalid  (m00_axi_rvalid),
        .m0_rlast   (m00_axi_rlast),
        .m0_rready  (m00_axi_rready),
        // w feeder read master
        .m1_araddr  (m01_axi_araddr),
        .m1_arlen   (m01_axi_arlen[3:0]),
        .m1_arvalid (m01_axi_arvalid),
        .m1_arready (m01_axi_arready),
        .m1_rdata   (m01_axi_rdata),
        .m1_rresp   (),
        .m1_rvalid  (m01_axi_rvalid),
        .m1_rlast   (m01_axi_rlast),
        .m1_rready  (m01_axi_rready),
        // y scatter write master
        .m2_awaddr  (m02_axi_awaddr),
        .m2_awlen   (m02_axi_awlen[3:0]),
        .m2_awvalid (m02_axi_awvalid),
        .m2_awready (m02_axi_awready),
        .m2_wdata   (m02_axi_wdata),
        .m2_wstrb   (m02_axi_wstrb),
        .m2_wvalid  (m02_axi_wvalid),
        .m2_wready  (m02_axi_wready),
        .m2_bresp   (),
        .m2_bvalid  (m02_axi_bvalid),
        .m2_bready  (m02_axi_bready),
        // plan ROM faces
        .pctl_addr  (pctl_addr),
        .pctl_data  (pctl_data),
        .strip_addr (strip_addr),
        .strip_data (strip_data),
        .lut_addr   (lut_addr),
        .lut_data   (lut_data),
        .cv_addr    (cv_addr),
        .cv_iss     (cv_iss),
        .cv_geo     (cv_geo),
        .cv_wlay    (cv_wlay),
        .tr_array_active (/* H2' tap: unconnected at shim */)
`ifdef PPU_ISLAND
        // ---- M10.3 island faces (pure passthrough; same switch as the
        //      port list above) ----
        ,.s2_axi_awaddr  (s2_axi_awaddr),  .s2_axi_awprot(s2_axi_awprot),
        .s2_axi_awvalid  (s2_axi_awvalid), .s2_axi_awready(s2_axi_awready),
        .s2_axi_wdata    (s2_axi_wdata),   .s2_axi_wstrb  (s2_axi_wstrb),
        .s2_axi_wvalid   (s2_axi_wvalid),  .s2_axi_wready (s2_axi_wready),
        .s2_axi_bresp    (s2_axi_bresp),   .s2_axi_bvalid (s2_axi_bvalid),
        .s2_axi_bready   (s2_axi_bready),
        .s2_axi_araddr   (s2_axi_araddr),  .s2_axi_arprot(s2_axi_arprot),
        .s2_axi_arvalid  (s2_axi_arvalid), .s2_axi_arready(s2_axi_arready),
        .s2_axi_rdata    (s2_axi_rdata),   .s2_axi_rresp  (s2_axi_rresp),
        .s2_axi_rvalid   (s2_axi_rvalid),  .s2_axi_rready (s2_axi_rready),
        .m3_axi_araddr   (m03_axi_araddr),
        .m3_axi_arlen    (m03_axi_arlen[3:0]),
        .m3_axi_arsize   (m03_axi_arsize),
        .m3_axi_arburst  (m03_axi_arburst),
        .m3_axi_arvalid  (m03_axi_arvalid),
        .m3_axi_arready  (m03_axi_arready),
        .m3_axi_rdata    (m03_axi_rdata), .m3_axi_rresp(m03_axi_rresp),
        .m3_axi_rlast    (m03_axi_rlast), .m3_axi_rvalid(m03_axi_rvalid),
        .m3_axi_rready   (m03_axi_rready),
        .m3_axi_awaddr   (m03_axi_awaddr),
        .m3_axi_awlen    (m03_axi_awlen[3:0]),
        .m3_axi_awsize   (m03_axi_awsize),
        .m3_axi_awburst  (m03_axi_awburst),
        .m3_axi_awvalid  (m03_axi_awvalid),
        .m3_axi_awready  (m03_axi_awready),
        .m3_axi_wdata    (m03_axi_wdata), .m3_axi_wstrb  (m03_axi_wstrb),
        .m3_axi_wlast    (m03_axi_wlast), .m3_axi_wvalid (m03_axi_wvalid),
        .m3_axi_wready   (m03_axi_wready),
        .m3_axi_bresp    (),               .m3_axi_bvalid (m03_axi_bvalid),
        .m3_axi_bready   (m03_axi_bready)
`endif
    );

    // ---------------- AXI4 control constants (burst-capable 64b) --------
    // arlen/awlen [3:0] are DRIVEN BY u_core (V3 axi_rd_v3 burst length);
    // the shim only zero-extends the unused upper nibble -- the legacy
    // full-width 8'd0 ties here were a double-drive (Synth 8-6859,
    // constant preserved / core driver silently dropped) that would
    // have forced single-beat on silicon.  Caught by build log review
    // 2026-10-13, first V3 bit attempt.
    assign m00_axi_arlen[7:4] = 4'd0;
    assign m00_axi_arsize  = 3'd3;      // 8 bytes
    assign m00_axi_arburst = 2'd1;      // INCR
    assign m00_axi_arlock  = 1'b0;
    assign m00_axi_arcache = 4'd0;
    assign m00_axi_arprot  = 3'd0;
    assign m00_axi_arqos   = 4'd0;

    assign m01_axi_arlen[7:4] = 4'd0;
    assign m01_axi_arsize  = 3'd3;
    assign m01_axi_arburst = 2'd1;
    assign m01_axi_arlock  = 1'b0;
    assign m01_axi_arcache = 4'd0;
    assign m01_axi_arprot  = 3'd0;
    assign m01_axi_arqos   = 4'd0;

    assign m02_axi_awlen[7:4] = 4'd0;
    assign m02_axi_awsize  = 3'd3;
    assign m02_axi_awburst = 2'd1;
    assign m02_axi_awlock  = 1'b0;
    assign m02_axi_awcache = 4'd0;
    assign m02_axi_awprot  = 3'd0;
    assign m02_axi_awqos   = 4'd0;
    assign m02_axi_wlast   = 1'b1;      // single-beat writes

`ifdef PPU_ISLAND
    // ---------------- M10.3 island AXI4 control constants -----------------
    // Same 8-6859 law as the tail block above: the core (island shell DMA)
    // drives arlen/awlen[3:0] and arsize/arburst (ppu_f7_top m_axi face);
    // the shim constant-ties ONLY the fields the core does not drive (the
    // upper len nibble + lock/cache/prot/qos BD-width completion).
    assign m03_axi_arlen[7:4] = 4'd0;
    assign m03_axi_arlock  = 1'b0;
    assign m03_axi_arcache = 4'd0;
    assign m03_axi_arprot  = 3'd0;
    assign m03_axi_arqos   = 4'd0;
    assign m03_axi_awlen[7:4] = 4'd0;
    assign m03_axi_awlock  = 1'b0;
    assign m03_axi_awcache = 4'd0;
    assign m03_axi_awprot  = 3'd0;
    assign m03_axi_awqos   = 4'd0;
`endif

endmodule
