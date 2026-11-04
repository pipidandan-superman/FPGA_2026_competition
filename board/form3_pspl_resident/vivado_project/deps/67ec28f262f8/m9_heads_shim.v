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
 *   - V1.3-R160 (2026-10-26) : candidate-only M11_REPACK-gated m04
 *         read-only AXI4 face; OFF builds expose and drive no m04 net.
 *   - V1.4-G5 (2026-10-28) : candidate-only m03 AW/WLAST/B mirror,
 *         checked accounts, response aggregation, and four response repairs.
 *   - V1.5-Closure (2026-10-28) : all-master response monitoring in both
 *         define faces, qualified heads-done export, and m03 idle routes.
 ***********************************************************************/
`timescale 1ns / 1ps

// Dedicated hybrid heads shim: no PPU island, repack DMA, or their ports.
module m9_heads_shim (
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
    // r12 widths (2026-10-21, M11a/D4 slot-doubling): pctl 14b / strip 11b
    // / lut 15b, cv 6b (69 slots x 128/16/256 = 8832/1104/17664; was r10
    // 12b/9b/13b/5b).  Legacy low-bit values unchanged (zero-ext).
    output wire [13:0] pctl_addr       ,
    input  wire [95:0] pctl_data       ,
    output wire [10:0] strip_addr      ,
    input  wire [20:0] strip_data      ,
    output wire [14:0] lut_addr        ,
    input  wire [7:0]  lut_data        ,
    output wire [6:0]  cv_addr         ,
    input  wire [255:0] cv_iss         ,
    input  wire [105:0] cv_geo         ,
    // 2a: m9_bm_wlay widened 136->168 (ch_stride tail)
    input  wire [167:0] cv_wlay        ,
    // r12 (M11a/D4): per-conv plan slot base from the new cv_slot ROM face
    // (64 x 7b; roms BD cell output -> shim -> top -> issuer)
    input  wire [6:0]  cv_slot,
    output wire        all_master_response_fault_sticky_o
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
    output wire        m03_axi_bready  ,
    // G5 observation/fault outputs; profile state enters through u_core.
    output wire        hw_m03_heads_commit_fence_o,
    output wire        heads_transaction_fault_sticky_o,
    output wire        m03_idle_quiescent_o,
    output wire        heads_frame_done_allowed_o,
    output wire        heads_gated_done_event_seen_o
`endif
`ifdef M11_REPACK
    ,output wire [31:0] m04_axi_araddr
    ,output wire [7:0]  m04_axi_arlen
    ,output wire [2:0]  m04_axi_arsize
    ,output wire [1:0]  m04_axi_arburst
    ,output wire        m04_axi_arlock
    ,output wire [3:0]  m04_axi_arcache
    ,output wire [2:0]  m04_axi_arprot
    ,output wire [3:0]  m04_axi_arqos
    ,output wire        m04_axi_arvalid
    ,input  wire        m04_axi_arready
    ,input  wire [63:0] m04_axi_rdata
    ,input  wire [1:0]  m04_axi_rresp
    ,input  wire        m04_axi_rlast
    ,input  wire        m04_axi_rvalid
    ,output wire        m04_axi_rready
`endif
);

    // G5 core-facing wires.  m9_v25_top_v3 owns the matching port face;
    // the shim never reaches into PPU internal DMA_CFG state.
`ifdef PPU_ISLAND
    wire [31:0] m03_b_timeout_limit_w;
    wire heads_start_accepted_w;
    wire heads_epoch_active_w;
    wire heads_epoch_profile_accepted_w;
    wire heads_epoch_cfg0_w;
    wire heads_live_dma_cfg0_w;
    wire heads_profile_fault_w;
    wire ppu_error_any_w;
    wire epoch_invalid_w;
    wire heads_gated_done_event_w;
    wire heads_frame_done_allowed_w;
`endif

    // Dedicated heads core; convolution-coupled post-processing stays in PL.
    m9_heads_top u_core (

        .clk        (s_axi_aclk),
        .rst_n      (s_axi_aresetn),
        // AXI-Lite face: 装载 FSM 呈批件 V2 §2.4①：送核地址切片 [7:0]→
        // [15:0] 纯切片拓宽（既有 64 字槽译码高位为零时逐位不变；段内
        // 0x100+ 归新装载口——BD 地址段 64K 已分配零改动）
        .s_awaddr   (s_axi_awaddr[15:0]),
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
        .s_araddr   (s_axi_araddr[15:0]),
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
        .m0_rresp   (m00_axi_rresp),
        .m0_rvalid  (m00_axi_rvalid),
        .m0_rlast   (m00_axi_rlast),
        .m0_rready  (m00_axi_rready),
        // w feeder read master
        .m1_araddr  (m01_axi_araddr),
        .m1_arlen   (m01_axi_arlen[3:0]),
        .m1_arvalid (m01_axi_arvalid),
        .m1_arready (m01_axi_arready),
        .m1_rdata   (m01_axi_rdata),
        .m1_rresp   (m01_axi_rresp),
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
        .m2_bresp   (m02_axi_bresp),
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
        .cv_slot    (cv_slot),
        .tr_array_active (/* H2' tap: unconnected at shim */),
        .all_master_response_fault_i(all_master_response_fault_sticky_o)
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
        .m3_axi_bresp    (m03_axi_bresp),   .m3_axi_bvalid (m03_axi_bvalid),
        .m3_axi_bready   (m03_axi_bready),
        // G5 owner-integration face (see integration_port_notes.txt).
        .m03_b_timeout_limit_o(m03_b_timeout_limit_w),
        .heads_start_accepted_o(heads_start_accepted_w),
        .heads_epoch_active_o(heads_epoch_active_w),
        .heads_epoch_profile_accepted_o(heads_epoch_profile_accepted_w),
        .heads_epoch_cfg0_o(heads_epoch_cfg0_w),
        .heads_live_dma_cfg0_o(heads_live_dma_cfg0_w),
        .heads_profile_fault_o(heads_profile_fault_w),
        .ppu_error_any_o(ppu_error_any_w),
        .epoch_invalid_o(epoch_invalid_w),
        .heads_gated_done_event_o(heads_gated_done_event_w),
        .heads_frame_done_allowed_o(heads_frame_done_allowed_w),
        .hw_m03_heads_commit_fence_i(hw_m03_heads_commit_fence_o),
        .heads_transaction_fault_i(heads_transaction_fault_sticky_o),
        .m03_idle_quiescent_i(m03_idle_quiescent_o)
`endif
`ifdef M11_REPACK
        ,.m4_axi_araddr(m04_axi_araddr),
        .m4_axi_arlen(m04_axi_arlen[3:0]),
        .m4_axi_arvalid(m04_axi_arvalid),
        .m4_axi_arready(m04_axi_arready),
        .m4_axi_rdata(m04_axi_rdata), .m4_axi_rresp(m04_axi_rresp),
        .m4_axi_rlast(m04_axi_rlast), .m4_axi_rvalid(m04_axi_rvalid),
        .m4_axi_rready(m04_axi_rready)
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

    // Passive response aggregation is present in every define face.  It is
    // independent of leaf response owners and feeds both CSR and PPU status.
    localparam [1:0] AXI_RESP_OKAY = 2'b00;
    wire m00_response_fault_event = m00_axi_rvalid && m00_axi_rready &&
                                    (m00_axi_rresp != AXI_RESP_OKAY);
    wire m01_response_fault_event = m01_axi_rvalid && m01_axi_rready &&
                                    (m01_axi_rresp != AXI_RESP_OKAY);
    wire m02_response_fault_event = m02_axi_bvalid && m02_axi_bready &&
                                    (m02_axi_bresp != AXI_RESP_OKAY);
    wire m03_r_response_fault_event;
    wire m03_b_response_fault_event;
    wire m04_response_fault_event;
`ifdef PPU_ISLAND
    assign m03_r_response_fault_event = m03_axi_rvalid && m03_axi_rready &&
                                        (m03_axi_rresp != AXI_RESP_OKAY);
    assign m03_b_response_fault_event = m03_axi_bvalid && m03_axi_bready &&
                                        (m03_axi_bresp != AXI_RESP_OKAY);
`else
    assign m03_r_response_fault_event = 1'b0;
    assign m03_b_response_fault_event = 1'b0;
`endif
`ifdef M11_REPACK
    assign m04_response_fault_event = m04_axi_rvalid && m04_axi_rready &&
                                      (m04_axi_rresp != AXI_RESP_OKAY);
`else
    assign m04_response_fault_event = 1'b0;
`endif
    wire all_master_response_fault_event = m00_response_fault_event ||
        m01_response_fault_event || m02_response_fault_event ||
        m03_r_response_fault_event || m03_b_response_fault_event ||
        m04_response_fault_event;
    reg all_master_response_fault_sticky_q;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            all_master_response_fault_sticky_q <= 1'b0;
        end else if (all_master_response_fault_event) begin
            all_master_response_fault_sticky_q <= 1'b1;
        end
    end
    assign all_master_response_fault_sticky_o =
        all_master_response_fault_sticky_q;

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

    // ---------------- G5 passive m03 transaction mirror -----------------
    // Only WR_OUTST_EFFECTIVE_1 is legal: a second AW before the prior B is
    // a fault.  W/WLAST never retires B debt.  All cumulative counters are
    // reset-only and all epoch counters are initialized by accepted start.
    localparam [1:0] M03_IDLE       = 2'd0;
    localparam [1:0] M03_WAIT_WLAST = 2'd1;
    localparam [1:0] M03_WAIT_B     = 2'd2;
    localparam [1:0] M03_ERROR      = 2'd3;

    reg [1:0] state;
    reg [1:0] next_state;
    wire [1:0] m03_w_state = state;
    reg [1:0] m03_b_debt_q;
    reg [31:0] m03_b_wait_cycles_q;
    reg [4:0] m03_aw_expected_beats_q;
    reg [4:0] m03_aw_accepted_beats_q;
    reg m03_aw_w_complete_q;

    reg [31:0] m03_aw_accepted_txns_q;
    reg [31:0] m03_w_accepted_beats_q;
    reg [31:0] m03_wlast_accepted_txns_q;
    reg [31:0] m03_b_returned_txns_q;
    reg [31:0] m03_b_okay_txns_q;
    reg [31:0] m03_b_bad_txns_q;
    reg [31:0] epoch_aw_accepted_q;
    reg [31:0] epoch_wlast_accepted_q;
    reg [31:0] epoch_b_returned_q;
    reg [31:0] epoch_b_okay_q;

    reg m03_b_timeout_sticky_q;
    reg m03_b_response_fault_sticky_q;
    reg m03_b_unmatched_sticky_q;
    reg m03_b_late_sticky_q;
    reg m03_axi_account_sticky_q;
    reg m03_w_protocol_sticky_q;
    reg heads_gated_done_event_seen_q;

    wire m03_aw_fire = m03_axi_awvalid && m03_axi_awready;
    wire m03_w_fire = m03_axi_wvalid && m03_axi_wready;
    wire m03_wlast_fire = m03_w_fire && m03_axi_wlast;
    wire m03_b_fire = m03_axi_bvalid && m03_axi_bready;

    wire [5:0] m03_next_beat_count = {1'b0, m03_aw_accepted_beats_q} + 6'd1;
    wire m03_wlast_early_event = m03_wlast_fire &&
        (m03_next_beat_count != {1'b0, m03_aw_expected_beats_q});
    wire m03_wlast_missing_event = m03_w_fire && !m03_axi_wlast &&
        (m03_next_beat_count >= {1'b0, m03_aw_expected_beats_q});
    wire m03_wlast_good_event = m03_wlast_fire &&
        (state == M03_WAIT_WLAST) &&
        (m03_next_beat_count == {1'b0, m03_aw_expected_beats_q});
    wire m03_aw_fault_event = m03_aw_fire &&
        ((state != M03_IDLE) || (m03_b_debt_q != 2'd0) ||
         (heads_epoch_active_w && (!heads_epoch_profile_accepted_w ||
                                   !heads_epoch_cfg0_w ||
                                   !heads_live_dma_cfg0_w)) ||
         (m03_axi_awlen[7:4] != 4'd0));
    wire m03_w_fault_event = m03_w_fire &&
        ((state != M03_WAIT_WLAST) || m03_wlast_early_event ||
         m03_wlast_missing_event);
    wire m03_b_early_event = m03_b_fire && (m03_b_debt_q != 2'd0) &&
                             (state != M03_WAIT_B);
    wire m03_b_unmatched_event = m03_b_fire && (m03_b_debt_q == 2'd0);
    wire m03_b_late_event = m03_b_fire && (m03_b_debt_q != 2'd0) &&
                            m03_b_timeout_sticky_q;
    wire m03_b_timeout_now = (state == M03_WAIT_B) &&
        ((m03_b_timeout_limit_w == 32'd0) ||
         (m03_b_wait_cycles_q >= (m03_b_timeout_limit_w - 32'd1)));
    wire m03_timeout_config_fault_event =
        ((heads_start_accepted_w || m03_wlast_good_event) &&
         (m03_b_timeout_limit_w == 32'd0));
    wire m03_duplicate_gated_event = heads_gated_done_event_w &&
                                     heads_gated_done_event_seen_q;

    wire m03_account_overflow_event =
        (m03_aw_fire && (m03_aw_accepted_txns_q == 32'hFFFF_FFFF)) ||
        (m03_aw_fire && (epoch_aw_accepted_q == 32'hFFFF_FFFF)) ||
        (m03_w_fire && (m03_w_accepted_beats_q == 32'hFFFF_FFFF)) ||
        (m03_wlast_good_event &&
         (m03_wlast_accepted_txns_q == 32'hFFFF_FFFF)) ||
        (m03_wlast_good_event &&
         (epoch_wlast_accepted_q == 32'hFFFF_FFFF)) ||
        (m03_b_fire && (m03_b_returned_txns_q == 32'hFFFF_FFFF)) ||
        (m03_b_fire && (epoch_b_returned_q == 32'hFFFF_FFFF)) ||
        (m03_b_fire && (m03_axi_bresp == AXI_RESP_OKAY) &&
         (m03_b_okay_txns_q == 32'hFFFF_FFFF)) ||
        (m03_b_fire && (m03_axi_bresp == AXI_RESP_OKAY) &&
         (epoch_b_okay_q == 32'hFFFF_FFFF)) ||
        (m03_b_response_fault_event &&
         (m03_b_bad_txns_q == 32'hFFFF_FFFF)) ||
        (m03_aw_fire && (m03_b_debt_q == 2'd3));

    wire m03_local_fault_event = m03_aw_fault_event || m03_w_fault_event ||
        m03_b_early_event || m03_b_unmatched_event ||
        m03_b_response_fault_event || m03_b_late_event ||
        m03_b_timeout_now || m03_timeout_config_fault_event ||
        m03_account_overflow_event;
    // Duplicate gated-done observation is registered/FSM-visible only.  It
    // must not enter the combinational fence cone because that fence is an
    // input to the top-level gated-event equation.
    wire m03_fsm_fault_event = m03_local_fault_event ||
                               m03_duplicate_gated_event;

    // FSM block 1: registered state.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            state <= M03_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // FSM block 2: next-state logic.  Fault always wins over channel progress.
    always @(*) begin
        next_state = state;
        if (m03_fsm_fault_event) begin
            next_state = M03_ERROR;
        end else begin
            case (state)
                M03_IDLE: begin
                    if (m03_aw_fire) begin
                        next_state = M03_WAIT_WLAST;
                    end
                end
                M03_WAIT_WLAST: begin
                    if (m03_wlast_good_event) begin
                        next_state = M03_WAIT_B;
                    end
                end
                M03_WAIT_B: begin
                    if (m03_b_fire) begin
                        next_state = M03_IDLE;
                    end
                end
                M03_ERROR: begin
                    next_state = M03_ERROR;
                end
                default: begin
                    next_state = M03_IDLE;
                end
            endcase
        end
    end

    wire [2:0] m03_b_debt_math = {1'b0, m03_b_debt_q} +
        (m03_aw_fire ? 3'd1 : 3'd0) -
        ((m03_b_fire && (m03_b_debt_q != 2'd0)) ? 3'd1 : 3'd0);

    // FSM block 3 and checked accounts: registered outputs/state metadata.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            m03_b_debt_q <= 2'd0;
            m03_b_wait_cycles_q <= 32'd0;
            m03_aw_expected_beats_q <= 5'd0;
            m03_aw_accepted_beats_q <= 5'd0;
            m03_aw_w_complete_q <= 1'b0;
            m03_aw_accepted_txns_q <= 32'd0;
            m03_w_accepted_beats_q <= 32'd0;
            m03_wlast_accepted_txns_q <= 32'd0;
            m03_b_returned_txns_q <= 32'd0;
            m03_b_okay_txns_q <= 32'd0;
            m03_b_bad_txns_q <= 32'd0;
            epoch_aw_accepted_q <= 32'd0;
            epoch_wlast_accepted_q <= 32'd0;
            epoch_b_returned_q <= 32'd0;
            epoch_b_okay_q <= 32'd0;
            m03_b_timeout_sticky_q <= 1'b0;
            m03_b_response_fault_sticky_q <= 1'b0;
            m03_b_unmatched_sticky_q <= 1'b0;
            m03_b_late_sticky_q <= 1'b0;
            m03_axi_account_sticky_q <= 1'b0;
            m03_w_protocol_sticky_q <= 1'b0;
            heads_gated_done_event_seen_q <= 1'b0;
        end else begin
            if (heads_start_accepted_w) begin
                m03_b_debt_q <= 2'd0;
                m03_b_wait_cycles_q <= 32'd0;
                m03_aw_expected_beats_q <= 5'd0;
                m03_aw_accepted_beats_q <= 5'd0;
                m03_aw_w_complete_q <= 1'b0;
                epoch_aw_accepted_q <= 32'd0;
                epoch_wlast_accepted_q <= 32'd0;
                epoch_b_returned_q <= 32'd0;
                epoch_b_okay_q <= 32'd0;
                heads_gated_done_event_seen_q <= 1'b0;
            end else begin
                m03_b_debt_q <= m03_b_debt_math[1:0];
            end

            if (m03_aw_fire) begin
                m03_aw_expected_beats_q <= {1'b0, m03_axi_awlen[3:0]} + 5'd1;
                m03_aw_accepted_beats_q <= 5'd0;
                m03_aw_w_complete_q <= 1'b0;
                m03_b_wait_cycles_q <= 32'd0;
                if (m03_aw_accepted_txns_q != 32'hFFFF_FFFF) begin
                    m03_aw_accepted_txns_q <= m03_aw_accepted_txns_q + 32'd1;
                end
                if (epoch_aw_accepted_q != 32'hFFFF_FFFF) begin
                    epoch_aw_accepted_q <= epoch_aw_accepted_q + 32'd1;
                end
            end
            if (m03_w_fire) begin
                if (m03_w_accepted_beats_q != 32'hFFFF_FFFF) begin
                    m03_w_accepted_beats_q <= m03_w_accepted_beats_q + 32'd1;
                end
                if (state == M03_WAIT_WLAST) begin
                    m03_aw_accepted_beats_q <= m03_next_beat_count[4:0];
                end
            end
            if (m03_wlast_good_event) begin
                m03_aw_w_complete_q <= 1'b1;
                m03_b_wait_cycles_q <= 32'd0;
                if (m03_wlast_accepted_txns_q != 32'hFFFF_FFFF) begin
                    m03_wlast_accepted_txns_q <=
                        m03_wlast_accepted_txns_q + 32'd1;
                end
                if (epoch_wlast_accepted_q != 32'hFFFF_FFFF) begin
                    epoch_wlast_accepted_q <= epoch_wlast_accepted_q + 32'd1;
                end
            end

            if (m03_b_timeout_now) begin
                m03_b_timeout_sticky_q <= 1'b1;
            end
            if ((state == M03_WAIT_B) && !m03_b_fire) begin
                if (!m03_b_timeout_now) begin
                    m03_b_wait_cycles_q <= m03_b_wait_cycles_q + 32'd1;
                end
            end
            if (m03_b_fire) begin
                if (m03_b_returned_txns_q != 32'hFFFF_FFFF) begin
                    m03_b_returned_txns_q <= m03_b_returned_txns_q + 32'd1;
                end
                if (epoch_b_returned_q != 32'hFFFF_FFFF) begin
                    epoch_b_returned_q <= epoch_b_returned_q + 32'd1;
                end
                if (m03_axi_bresp == AXI_RESP_OKAY) begin
                    if (m03_b_okay_txns_q != 32'hFFFF_FFFF) begin
                        m03_b_okay_txns_q <= m03_b_okay_txns_q + 32'd1;
                    end
                    if (epoch_b_okay_q != 32'hFFFF_FFFF) begin
                        epoch_b_okay_q <= epoch_b_okay_q + 32'd1;
                    end
                end else begin
                    m03_b_response_fault_sticky_q <= 1'b1;
                    if (m03_b_bad_txns_q != 32'hFFFF_FFFF) begin
                        m03_b_bad_txns_q <= m03_b_bad_txns_q + 32'd1;
                    end
                end
            end

            if (m03_aw_fault_event || m03_account_overflow_event ||
                m03_timeout_config_fault_event || m03_duplicate_gated_event) begin
                m03_axi_account_sticky_q <= 1'b1;
            end
            if (m03_w_fault_event || m03_b_early_event) begin
                m03_w_protocol_sticky_q <= 1'b1;
            end
            if (m03_b_unmatched_event) begin
                m03_b_unmatched_sticky_q <= 1'b1;
            end
            if (m03_b_late_event) begin
                m03_b_late_sticky_q <= 1'b1;
            end
            if (heads_gated_done_event_w) begin
                heads_gated_done_event_seen_q <= 1'b1;
            end
        end
    end

    assign heads_frame_done_allowed_o = heads_frame_done_allowed_w;
    assign heads_gated_done_event_seen_o = heads_gated_done_event_seen_q;
    assign heads_transaction_fault_sticky_o = m03_b_timeout_sticky_q ||
        m03_b_response_fault_sticky_q || m03_b_unmatched_sticky_q ||
        m03_b_late_sticky_q || m03_axi_account_sticky_q ||
        m03_w_protocol_sticky_q || all_master_response_fault_sticky_q;
    assign m03_idle_quiescent_o = (state == M03_IDLE) &&
        (m03_b_debt_q == 2'd0) && !m03_axi_awvalid &&
        !m03_axi_wvalid && !m03_axi_bvalid && !m03_axi_arvalid &&
        !m03_axi_rvalid;

    wire m03_epoch_wlast_closed = (epoch_aw_accepted_q > 32'd0) &&
        (epoch_wlast_accepted_q == epoch_aw_accepted_q) &&
        m03_aw_w_complete_q;
    wire m03_epoch_all_b_returned = (epoch_aw_accepted_q > 32'd0) &&
        (epoch_b_returned_q == epoch_aw_accepted_q) &&
        (m03_b_debt_q == 2'd0);
    wire m03_epoch_all_b_okay = (epoch_aw_accepted_q > 32'd0) &&
        (epoch_b_okay_q == epoch_aw_accepted_q) &&
        (epoch_b_returned_q == epoch_aw_accepted_q);
    wire m03_w_side_complete = m03_aw_w_complete_q &&
        (m03_aw_accepted_beats_q == m03_aw_expected_beats_q);
    wire m03_idle_epoch_fence = (state == M03_IDLE) &&
        m03_epoch_wlast_closed && m03_epoch_all_b_returned &&
        m03_epoch_all_b_okay && m03_w_side_complete;
    wire [32:0] m03_final_b_returned = {1'b0, epoch_b_returned_q} + 33'd1;
    wire [32:0] m03_final_b_okay = {1'b0, epoch_b_okay_q} + 33'd1;
    wire m03_same_cycle_final_b_fence = (state == M03_WAIT_B) &&
        m03_b_fire && (m03_axi_bresp == AXI_RESP_OKAY) &&
        (m03_b_debt_q == 2'd1) && (epoch_aw_accepted_q > 32'd0) &&
        (epoch_wlast_accepted_q == epoch_aw_accepted_q) &&
        (m03_final_b_returned == {1'b0, epoch_aw_accepted_q}) &&
        (m03_final_b_okay == {1'b0, epoch_aw_accepted_q}) &&
        m03_w_side_complete && !m03_b_timeout_now;
    wire m03_cumulative_b_consistent = (m03_b_bad_txns_q == 32'd0) &&
        (m03_b_okay_txns_q == m03_b_returned_txns_q);

    assign hw_m03_heads_commit_fence_o = heads_epoch_profile_accepted_w &&
        heads_epoch_cfg0_w && heads_live_dma_cfg0_w &&
        !heads_profile_fault_w && !heads_transaction_fault_sticky_o &&
        (m03_idle_epoch_fence || m03_same_cycle_final_b_fence) &&
        m03_cumulative_b_consistent && !m03_local_fault_event &&
        !all_master_response_fault_event && !ppu_error_any_w &&
        !epoch_invalid_w;
`endif

`ifdef M11_REPACK
    assign m04_axi_arlen[7:4] = 4'd0;
    assign m04_axi_arsize = 3'd3;
    assign m04_axi_arburst = 2'd1;
    assign m04_axi_arlock = 1'b0;
    assign m04_axi_arcache = 4'd0;
    assign m04_axi_arprot = 3'd0;
    assign m04_axi_arqos = 4'd0;
`endif

endmodule
