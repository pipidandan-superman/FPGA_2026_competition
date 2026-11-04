//====================================================================
// File name   : ble_csr.v
// Author      : Claude Code
// Create date : 2026-10-01
// Description : Register bank + TX frame engine + RX ring buffer for
//               the BLE UART control block. Register protocol mirrors
//               the proven axi_action_reg_bank handshake (response
//               registered on the accept beat). PL moves raw bytes
//               only; AT / ASCII arm-frame grammar lives in PS.
//
//   0x000 ID        RO  0x424C4531 "BLE1"
//   0x004 VERSION   RO  0x00010000
//   0x008 CAPS      RO  bit0 TX, bit1 RX, bit2 SOFT_RST
//   0x00C BT_CTRL   RW  bit0 restart_req (1 = module held off)
//   0x010 STATUS    RO  bit0 bt_ready, bit1 tx_busy, bit2 rx_avail
//   0x014 UART_DIV  RW  bit divisor, reset 5208 = 9600 @ 50 MHz
//   0x018 TX_LEN    RW  frame length 0..256 (0 = not armed)
//   0x01C TX_GO     WO  write 1 = send TX buffer now
//   0x020 TX_COUNT  RO  bytes completed of current/last frame
//   0x024 RX_PROD   RO  RX ring producer counter
//   0x028 RX_CONS   RW  RX ring consumer counter (PS advances)
//   0x02C RX_DROPPED RO ring-full dropped byte count
//   0x030 RX_FRM_ERR RO stop-bit error count
//   0x400+4*i TX frame buffer (one byte per aligned word, wr_data[7:0])
//   0x800+4*j RX ring read    (one byte per aligned word, rd_data[7:0])
//   V1.1: buffer pages moved to word-aligned addressing (0x400/0x800);
//   V1.0 byte-indexed pages 0x100/0x200 were unreachable from PS MMIO,
//   which can only issue 4-byte-aligned accesses (caught on hardware).
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.1
//====================================================================

module ble_csr #(
    parameter integer clock_freq_hz = 50_000_000
) (
    input  wire        clk,
    input  wire        resetn,
    // AXI-Lite internal channel (from axi_lite_slave)
    input  wire        wr_valid,
    output reg         wr_ready,
    input  wire [11:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_strb,
    output reg         wr_rsp_valid,
    input  wire        wr_rsp_ready,
    output reg  [1:0]  wr_rsp,
    input  wire        rd_valid,
    output reg         rd_ready,
    input  wire [11:0] rd_addr,
    output reg         rd_rsp_valid,
    input  wire        rd_rsp_ready,
    output reg  [31:0] rd_data,
    output reg  [1:0]  rd_rsp,
    // BLE UART TX engine interface
    input  wire        bt_ready,
    output reg         tx_start,
    output wire [7:0]  tx_wdata,
    input  wire        tx_busy,
    input  wire        tx_done,
    // BLE UART RX interface
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_frm_err,
    // shared UART bit divisor (runtime programmable)
    output wire [15:0] uart_div,
    // power sequencer control
    output reg         restart_req
);

    localparam [1:0] RESP_OKAY   = 2'd0,
                     RESP_SLVERR = 2'd2;

    localparam [1:0] TXS_IDLE = 2'd0,
                     TXS_SEND = 2'd1,
                     TXS_WAIT = 2'd2;

    localparam [15:0] DIV_RESET = 16'd5208;   // 9600 baud @ 50 MHz

    reg [15:0] uart_div_reg;
    assign uart_div = uart_div_reg;
    reg [8:0]  tx_len;
    reg [8:0]  tx_idx;
    reg [31:0] tx_count;
    reg        tx_busy_frame;
    reg [1:0]  tx_state;
    reg [31:0] rx_prod, rx_cons, rx_dropped, rx_frm_err_cnt;

    // ---------------------------------------------------------------
    // Buffers: sync write / async read (distributed RAM, 256 x 8 each)
    // Single writer and single reader per buffer; TX buffer writes are
    // rejected while a frame is in flight, so no read-during-write
    // ambiguity ever reaches the engine.
    // ---------------------------------------------------------------
    reg [7:0] tx_buf [0:255];
    reg [7:0] rx_buf [0:255];

    wire        tx_buf_sel  = (wr_addr[11:10] == 2'b01);  // 0x400-0x7FF
    wire        tx_rd_sel   = (rd_addr[11:10] == 2'b01);  // 0x400-0x7FF
    wire        rx_rd_sel   = (rd_addr[11:10] == 2'b10);  // 0x800-0xBFF
    reg  [7:0]  ram_rd_idx;
    reg         ram_rd_rx;      // 0 = TX buffer readback, 1 = RX ring

    wire [7:0] tx_engine_byte = tx_buf[tx_idx];
    wire [7:0] tx_ps_byte     = tx_buf[ram_rd_idx];
    wire [7:0] rx_ps_byte     = rx_buf[ram_rd_idx];

    assign tx_wdata = tx_engine_byte;

    wire tx_go_fire = wr_valid && wr_ready && (wr_addr == 12'h01c)
                      && (wr_strb == 4'hf) && (wr_data == 32'h1)
                      && !tx_busy_frame && bt_ready && (tx_len != 9'd0);

    // ---------------------------------------------------------------
    // Write path
    // ---------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ready      <= 1'b0;
            wr_rsp_valid  <= 1'b0;
            wr_rsp        <= RESP_OKAY;
            uart_div_reg  <= DIV_RESET;
            tx_len        <= 9'd0;
            restart_req   <= 1'b0;
        end else begin
            if (!wr_rsp_valid)
                wr_ready <= 1'b1;
            if (wr_rsp_valid && wr_rsp_ready) begin
                wr_rsp_valid <= 1'b0;
                wr_ready     <= 1'b1;
            end
            if (wr_valid && wr_ready) begin
                wr_ready     <= 1'b0;
                wr_rsp_valid <= 1'b1;
                wr_rsp       <= RESP_OKAY;
                if (wr_addr[11:8] == 4'h0) begin
                    case (wr_addr[7:0])
                            8'h0c: begin
                                if (wr_strb[0])
                                    restart_req <= wr_data[0];
                            end
                            8'h14: begin
                                // divisor: full word, idle only, non-zero
                                if ((wr_strb != 4'hf) || tx_busy_frame
                                    || (wr_data[15:0] == 16'd0)
                                    || (wr_data[31:16] != 16'd0)) begin
                                    wr_rsp <= RESP_SLVERR;
                                end else begin
                                    uart_div_reg <= wr_data[15:0];
                                end
                            end
                            8'h18: begin
                                // length: full word, idle only, 0..256
                                if ((wr_strb != 4'hf) || tx_busy_frame
                                    || (wr_data[31:9] != 23'd0)
                                    || (wr_data[8:0] > 9'h100)) begin
                                    wr_rsp <= RESP_SLVERR;
                                end else begin
                                    tx_len <= wr_data[8:0];
                                end
                            end
                            8'h28: begin
                                // RX consumer advance, full word, any time
                                if (wr_strb != 4'hf)
                                    wr_rsp <= RESP_SLVERR;
                                // rx_cons itself latched in the RX block
                            end
                            8'h1c: begin
                                if (!tx_go_fire)
                                    wr_rsp <= RESP_SLVERR;
                                // engine arming handled below
                            end
                            default: wr_rsp <= RESP_SLVERR;
                        endcase
                end else if (tx_buf_sel) begin
                    // TX frame buffer byte write (aligned word, lane 0)
                    if (tx_busy_frame) begin
                        wr_rsp <= RESP_SLVERR;
                    end else if (wr_strb[0]) begin
                        tx_buf[wr_addr[9:2]] <= wr_data[7:0];
                    end
                end else begin
                    wr_rsp <= RESP_SLVERR;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // TX frame engine: byte feeder for ble_uart_tx
    // ---------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tx_state     <= TXS_IDLE;
            tx_idx       <= 9'd0;
            tx_count     <= 32'd0;
            tx_busy_frame<= 1'b0;
            tx_start     <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (tx_state)
                TXS_IDLE: begin
                    if (tx_go_fire) begin
                        tx_idx       <= 9'd0;
                        tx_count     <= 32'd0;
                        tx_busy_frame<= 1'b1;
                        tx_state     <= TXS_SEND;
                    end
                end
                TXS_SEND: begin
                    tx_start <= 1'b1;          // 1-cycle pulse with byte
                    tx_state <= TXS_WAIT;
                end
                TXS_WAIT: begin
                    if (tx_done) begin
                        tx_count <= tx_count + 32'd1;
                        if (tx_idx == tx_len - 9'd1) begin
                            tx_busy_frame <= 1'b0;
                            tx_state      <= TXS_IDLE;
                        end else begin
                            tx_idx   <= tx_idx + 9'd1;
                            tx_state <= TXS_SEND;
                        end
                    end
                end
                default: begin
                    tx_busy_frame <= 1'b0;
                    tx_state      <= TXS_IDLE;
                end
            endcase
        end
    end

    // ---------------------------------------------------------------
    // RX ring: producer writes at prod & 0xFF, overflow counted
    // ---------------------------------------------------------------
    wire [31:0] rx_used = rx_prod - rx_cons;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rx_prod       <= 32'd0;
            rx_cons       <= 32'd0;
            rx_dropped    <= 32'd0;
            rx_frm_err_cnt<= 32'd0;
        end else begin
            if (rx_valid) begin
                if (rx_used < 32'd256) begin
                    rx_buf[rx_prod[7:0]] <= rx_data;
                    rx_prod <= rx_prod + 32'd1;
                end else begin
                    rx_dropped <= rx_dropped + 32'd1;
                end
            end
            if (rx_frm_err)
                rx_frm_err_cnt <= rx_frm_err_cnt + 32'd1;
            if (wr_valid && wr_ready && (wr_addr == 12'h028)
                && (wr_strb == 4'hf)) begin
                rx_cons <= wr_data;
            end
        end
    end

    // ---------------------------------------------------------------
    // Read path: registers answer on the beat after accept; buffer
    // reads take one extra beat (async RAM read is stable by then).
    // ---------------------------------------------------------------
    reg ram_rd_pending;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ready      <= 1'b0;
            rd_rsp_valid  <= 1'b0;
            rd_data       <= 32'd0;
            rd_rsp        <= RESP_OKAY;
            ram_rd_pending<= 1'b0;
            ram_rd_idx    <= 8'd0;
            ram_rd_rx     <= 1'b0;
        end else begin
            if (!rd_rsp_valid && !ram_rd_pending)
                rd_ready <= 1'b1;
            if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 1'b0;
                rd_ready     <= 1'b1;
            end
            if (ram_rd_pending) begin
                ram_rd_pending <= 1'b0;
                rd_rsp_valid   <= 1'b1;
                rd_rsp         <= RESP_OKAY;
                rd_data        <= {24'b0, ram_rd_rx ? rx_ps_byte : tx_ps_byte};
            end else if (rd_valid && rd_ready) begin
                rd_ready <= 1'b0;
                if (rd_addr[11:8] == 4'h0) begin
                    rd_rsp_valid <= 1'b1;
                    rd_rsp       <= RESP_OKAY;
                    case (rd_addr[7:0])
                        8'h00: rd_data <= 32'h424C4531;               // "BLE1"
                        8'h04: rd_data <= 32'h00010000;
                        8'h08: rd_data <= 32'h00000007;
                        8'h0c: rd_data <= {31'd0, restart_req};
                        8'h10: rd_data <= {29'd0, (rx_prod != rx_cons),
                                           tx_busy_frame, bt_ready};
                        8'h14: rd_data <= {16'd0, uart_div_reg};
                        8'h18: rd_data <= {23'd0, tx_len};
                        8'h1c: rd_data <= 32'd0;
                        8'h20: rd_data <= tx_count;
                        8'h24: rd_data <= rx_prod;
                        8'h28: rd_data <= rx_cons;
                        8'h2c: rd_data <= rx_dropped;
                        8'h30: rd_data <= rx_frm_err_cnt;
                        default: begin
                            rd_data <= 32'd0;
                            rd_rsp  <= RESP_SLVERR;
                        end
                    endcase
                end else if (tx_rd_sel || rx_rd_sel) begin
                    ram_rd_pending <= 1'b1;
                    ram_rd_idx     <= rd_addr[9:2];
                    ram_rd_rx      <= rx_rd_sel;
                end else begin
                    rd_rsp_valid <= 1'b1;
                    rd_rsp       <= RESP_SLVERR;
                    rd_data      <= 32'd0;
                end
            end
        end
    end

endmodule
