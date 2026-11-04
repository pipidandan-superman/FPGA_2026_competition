/************************************************************************
 * yolo_gemm_dma_top.v — BD packaging wrapper for the B3 GEMM subsystem
 * ---------------------------------------------------------------------
 * Purpose  : Expose the verified GEMM core to the block design with
 *            explicit AXIS interfaces. proj/axi_gemm_test's module_ref
 *            snapshot was frozen at the V1.0 port list (stream pins
 *            never appeared; update_module_reference failed silently),
 *            so per user directive of 2026-09-20 the top is repackaged
 *            in a fresh project (proj/DMA_gemm) with interface
 *            attributes carried in the RTL itself.
 * Content  : PURE PASS-THROUGH. Every port is wired 1:1 into
 *            yolo_gemm_top (V1.2, untouched — run26 S1-S7 and run27 G4
 *            evidence attach to that file; see
 *            4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/).
 * Ports    : identical name/direction/width to yolo_gemm_top V1.2
 *            (port equivalence machine-checked, run28b portcheck).
 * Notes    : AXI4-Lite s_axi_* group needs no attribute (prefix
 *            inference is the proven path); the two AXIS groups carry
 *            X_INTERFACE_INFO so BD interface inference cannot be
 *            skipped. Verilog-2001 only.
 * Rev      : V1.0  2026-09-20  wrapper born (core = yolo_gemm_top V1.2)
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_gemm_dma_top (
    input  wire        s_axi_aclk    ,
    input  wire        s_axi_aresetn ,
    // AXI4-Lite slave interface (names fixed by AXI/BD convention)
    input  wire [31:0] s_axi_awaddr  ,
    input  wire [2:0]  s_axi_awprot  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire [3:0]  s_axi_wstrb   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [31:0] s_axi_araddr  ,
    input  wire [2:0]  s_axi_arprot  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready  ,
    // AXI4-Stream slave: DMA load port (MM2S -> bridge, B3 C3)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    input  wire [63:0] s_axis_ld_tdata ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    input  wire        s_axis_ld_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    output wire        s_axis_ld_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    input  wire        s_axis_ld_tlast ,
    // AXI4-Stream master: y recovery port (bridge -> S2MM, B3 D2)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    output wire [63:0] m_axis_y_tdata ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    output wire        m_axis_y_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    input  wire        m_axis_y_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0" *)
    output wire        m_axis_y_tlast
);

    yolo_gemm_top u_gemm_core (
        .s_axi_aclk    (s_axi_aclk    ),
        .s_axi_aresetn (s_axi_aresetn ),
        .s_axi_awaddr  (s_axi_awaddr  ),
        .s_axi_awprot  (s_axi_awprot  ),
        .s_axi_awvalid (s_axi_awvalid ),
        .s_axi_awready (s_axi_awready ),
        .s_axi_wdata   (s_axi_wdata   ),
        .s_axi_wstrb   (s_axi_wstrb   ),
        .s_axi_wvalid  (s_axi_wvalid  ),
        .s_axi_wready  (s_axi_wready  ),
        .s_axi_bresp   (s_axi_bresp   ),
        .s_axi_bvalid  (s_axi_bvalid  ),
        .s_axi_bready  (s_axi_bready  ),
        .s_axi_araddr  (s_axi_araddr  ),
        .s_axi_arprot  (s_axi_arprot  ),
        .s_axi_arvalid (s_axi_arvalid ),
        .s_axi_arready (s_axi_arready ),
        .s_axi_rdata   (s_axi_rdata   ),
        .s_axi_rresp   (s_axi_rresp   ),
        .s_axi_rvalid  (s_axi_rvalid  ),
        .s_axi_rready  (s_axi_rready  ),
        .s_axis_ld_tdata (s_axis_ld_tdata ),
        .s_axis_ld_tvalid(s_axis_ld_tvalid),
        .s_axis_ld_tready(s_axis_ld_tready),
        .s_axis_ld_tlast (s_axis_ld_tlast ),
        .m_axis_y_tdata (m_axis_y_tdata ),
        .m_axis_y_tvalid(m_axis_y_tvalid),
        .m_axis_y_tready(m_axis_y_tready),
        .m_axis_y_tlast (m_axis_y_tlast )
    );

endmodule
