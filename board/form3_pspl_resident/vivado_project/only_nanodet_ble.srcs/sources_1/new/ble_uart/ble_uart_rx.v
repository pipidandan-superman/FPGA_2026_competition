//====================================================================
// File name   : ble_uart_rx.v
// Author      : Claude Code
// Create date : 2026-10-01
// Description : Single-byte 8N1 UART receiver with run-time
//               programmable bit divisor. 2-flop input synchronizer,
//               start-bit validation at half bit, LSB-first sampling
//               at mid-bit, stop-bit check (low stop -> frm_err pulse).
//               rx_valid is a 1-cycle pulse with rx_data held.
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

module ble_uart_rx (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] clks_per_bit,
    input  wire        rxd,
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    output reg         frm_err
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3;

    // 2-flop synchronizer, reset value = idle level
    (* ASYNC_REG = "TRUE" *) reg [1:0] rxd_sync;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rxd_sync <= 2'b11;
        end else begin
            rxd_sync <= {rxd_sync[0], rxd};
        end
    end
    wire rxd_s = rxd_sync[1];

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_shift;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= S_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            rx_shift  <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            frm_err   <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            frm_err  <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (rxd_s == 1'b0) begin          // start edge
                        state <= S_START;
                    end
                end
                S_START: begin
                    if (clk_count == (clks_per_bit >> 1) - 16'd1) begin
                        clk_count <= 16'd0;
                        if (rxd_s == 1'b0) begin      // still low at mid start
                            state <= S_DATA;
                        end else begin
                            state <= S_IDLE;          // glitch, reject
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
                S_DATA: begin
                    if (clk_count == clks_per_bit - 16'd1) begin
                        clk_count <= 16'd0;
                        rx_shift  <= {rxd_s, rx_shift[7:1]};  // LSB first
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
                S_STOP: begin
                    if (clk_count == clks_per_bit - 16'd1) begin
                        clk_count <= 16'd0;
                        if (rxd_s == 1'b1) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end else begin
                            frm_err  <= 1'b1;         // missing stop bit
                        end
                        state <= S_IDLE;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
