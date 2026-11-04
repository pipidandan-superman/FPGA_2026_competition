//====================================================================
// File name   : ble_uart_tx.v
// Author      : Claude Code
// Create date : 2026-10-01
// Description : Single-byte 8N1 UART transmitter with run-time
//               programmable bit divisor (clks_per_bit), adapted from
//               the board-proven action_uart_tx byte machine.
//               Handshake: pulse start with data while not busy;
//               busy covers the whole byte; done is a 1-cycle pulse.
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

module ble_uart_tx (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] clks_per_bit,
    input  wire        start,
    input  wire [7:0]  data,
    output wire        busy,
    output reg         done,
    output reg         txd
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3,
                     S_DONE  = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  tx_shift;

    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state      <= S_IDLE;
            clk_count  <= 16'd0;
            bit_index  <= 3'd0;
            tx_shift   <= 8'd0;
            done       <= 1'b0;
            txd        <= 1'b1;      // UART idle level
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    txd <= 1'b1;
                    if (start) begin
                        tx_shift  <= data;    // LSB first on the wire
                        clk_count <= 16'd0;
                        bit_index <= 3'd0;
                        state     <= S_START;
                    end
                end
                S_START: begin
                    txd <= 1'b0;
                    if (clk_count == clks_per_bit - 16'd1) begin
                        clk_count <= 16'd0;
                        state     <= S_DATA;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
                S_DATA: begin
                    txd <= tx_shift[0];
                    if (clk_count == clks_per_bit - 16'd1) begin
                        clk_count <= 16'd0;
                        tx_shift  <= {1'b0, tx_shift[7:1]};
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
                    txd <= 1'b1;
                    if (clk_count == clks_per_bit - 16'd1) begin
                        clk_count <= 16'd0;
                        state     <= S_DONE;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
                S_DONE: begin
                    txd   <= 1'b1;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: begin
                    txd   <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
