//====================================================================
// File name   : axi_ble_uart_top.v
// Author      : Claude Code
// Create date : 2026-10-01
// Description : AXI-Lite BLE UART control block (module_ref cell in
//               the display_test BD, base 0x43C10000). Wires the
//               proven axi_lite_slave to the BLE CSR, byte UART
//               TX/RX and the MLT-BT05 power/reset sequencer.
//               Pinout (board-proven 09-12 bridge):
//                 bt_uart_rxd  <- Y13  (MLT BT_TX)
//                 bt_uart_txd  -> AA13 (MLT BT_RX)
//                 bt_power_en  -> U14  (active high)
//                 bt_reset_n   -> H15  (active low)
// Target      : Xilinx Zynq-7020 FPGA, 50 MHz FCLK domain
// Revision    : V1.0
//====================================================================

module axi_ble_uart_top #(
    parameter integer clock_freq_hz    = 50000000,
    parameter integer power_delay_ms   = 100,
    parameter integer startup_delay_ms = 1000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET resetn, FREQ_HZ 50000000" *)
    input  wire         clk           ,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire         resetn        ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 50000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, HAS_QOS 0, HAS_PROT 1, HAS_WSTRB 1, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [11:0]  s_axi_awaddr  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]   s_axi_awprot  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire         s_axi_awvalid ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire         s_axi_awready ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]  s_axi_wdata   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]   s_axi_wstrb   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire         s_axi_wvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire         s_axi_wready  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]   s_axi_bresp   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire         s_axi_bvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire         s_axi_bready  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0]  s_axi_araddr  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]   s_axi_arprot  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire         s_axi_arvalid ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire         s_axi_arready ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]  s_axi_rdata   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]   s_axi_rresp   ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire         s_axi_rvalid  ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire         s_axi_rready  ,
    input  wire         bt_uart_rxd   ,
    output wire         bt_uart_txd   ,
    output wire         bt_power_en   ,
    output wire         bt_reset_n
);

    wire        wr_valid;
    wire        wr_ready;
    wire [11:0] wr_addr;
    wire [31:0] wr_data;
    wire [3:0]  wr_strb;
    wire        wr_rsp_valid;
    wire        wr_rsp_ready;
    wire [1:0]  wr_rsp;
    wire        rd_valid;
    wire        rd_ready;
    wire [11:0] rd_addr;
    wire        rd_rsp_valid;
    wire        rd_rsp_ready;
    wire [31:0] rd_data;
    wire [1:0]  rd_rsp;

    wire        tx_start;
    wire [7:0]  tx_wdata;
    wire        tx_busy, tx_done;
    wire [7:0]  rx_data;
    wire        rx_valid, rx_frm_err;
    wire        bt_ready;
    wire        restart_req;
    wire [15:0] uart_div;

    axi_lite_slave u_slave (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .s_axi_awaddr   (s_axi_awaddr  ),
        .s_axi_awvalid  (s_axi_awvalid ),
        .s_axi_awready  (s_axi_awready ),
        .s_axi_wdata    (s_axi_wdata   ),
        .s_axi_wstrb    (s_axi_wstrb   ),
        .s_axi_wvalid   (s_axi_wvalid  ),
        .s_axi_wready   (s_axi_wready  ),
        .s_axi_bresp    (s_axi_bresp   ),
        .s_axi_bvalid   (s_axi_bvalid  ),
        .s_axi_bready   (s_axi_bready  ),
        .s_axi_araddr   (s_axi_araddr  ),
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  ),
        .wr_valid       (wr_valid      ),
        .wr_ready       (wr_ready      ),
        .wr_addr        (wr_addr       ),
        .wr_data        (wr_data       ),
        .wr_strb        (wr_strb       ),
        .wr_rsp_valid   (wr_rsp_valid  ),
        .wr_rsp_ready   (wr_rsp_ready  ),
        .wr_rsp         (wr_rsp        ),
        .rd_valid       (rd_valid      ),
        .rd_ready       (rd_ready      ),
        .rd_addr        (rd_addr       ),
        .rd_rsp_valid   (rd_rsp_valid  ),
        .rd_rsp_ready   (rd_rsp_ready  ),
        .rd_data        (rd_data       ),
        .rd_rsp         (rd_rsp        )
    );

    ble_csr #(
        .clock_freq_hz (clock_freq_hz)
    ) u_csr (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .wr_valid       (wr_valid      ),
        .wr_ready       (wr_ready      ),
        .wr_addr        (wr_addr       ),
        .wr_data        (wr_data       ),
        .wr_strb        (wr_strb       ),
        .wr_rsp_valid   (wr_rsp_valid  ),
        .wr_rsp_ready   (wr_rsp_ready  ),
        .wr_rsp         (wr_rsp        ),
        .rd_valid       (rd_valid      ),
        .rd_ready       (rd_ready      ),
        .rd_addr        (rd_addr       ),
        .rd_rsp_valid   (rd_rsp_valid  ),
        .rd_rsp_ready   (rd_rsp_ready  ),
        .rd_data        (rd_data       ),
        .rd_rsp         (rd_rsp        ),
        .bt_ready       (bt_ready      ),
        .tx_start       (tx_start      ),
        .tx_wdata       (tx_wdata      ),
        .tx_busy        (tx_busy       ),
        .tx_done        (tx_done       ),
        .rx_data        (rx_data       ),
        .rx_valid       (rx_valid      ),
        .rx_frm_err     (rx_frm_err    ),
        .uart_div       (uart_div      ),
        .restart_req    (restart_req   )
    );

    ble_uart_tx u_tx (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .clks_per_bit   (uart_div      ),
        .start          (tx_start      ),
        .data           (tx_wdata      ),
        .busy           (tx_busy       ),
        .done           (tx_done       ),
        .txd            (bt_uart_txd   )
    );

    ble_uart_rx u_rx (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .clks_per_bit   (uart_div      ),
        .rxd            (bt_uart_rxd   ),
        .rx_data        (rx_data       ),
        .rx_valid       (rx_valid      ),
        .frm_err        (rx_frm_err    )
    );

    ble_bt_power_fsm #(
        .clock_freq_hz    (clock_freq_hz   ),
        .power_delay_ms   (power_delay_ms  ),
        .startup_delay_ms (startup_delay_ms)
    ) u_power (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .restart_req    (restart_req   ),
        .bt_power_en    (bt_power_en   ),
        .bt_reset_n     (bt_reset_n    ),
        .bt_ready       (bt_ready      )
    );

endmodule
