//====================================================================
// File name   : ble_bt_power_fsm.v
// Author      : Claude Code
// Create date : 2026-10-01
// Description : MLT-BT05 power/reset sequencer, ported from the
//               board-proven ble_uart_debug_top (2026-09-12) bridge:
//               power enable active-high (U14), module reset active-low
//               (H15). Three-stage Moore FSM, reset state = STATE_IDLE.
//               restart_req=1 holds the module powered off; dropping it
//               re-runs the full sequence (soft power cycle of the
//               module, which returns the MLT firmware to AT mode).
// Target      : Xilinx Zynq-7020 FPGA (50 MHz FCLK domain)
// Revision    : V1.0
//====================================================================

module ble_bt_power_fsm #(
    parameter integer clock_freq_hz    = 50_000_000,
    parameter integer power_delay_ms   = 100,
    parameter integer startup_delay_ms = 1000
) (
    input  wire clk,
    input  wire resetn,
    input  wire restart_req,   // 1 = hold module off / restart sequence
    output reg  bt_power_en,   // U14, active high
    output reg  bt_reset_n,    // H15, active low
    output wire bt_ready
);

    localparam [1:0] STATE_IDLE    = 2'd0,
                     STATE_POWER   = 2'd1,
                     STATE_STARTUP = 2'd2,
                     STATE_READY   = 2'd3;

    localparam integer POWER_TICKS = (clock_freq_hz / 1000) * power_delay_ms;
    localparam integer BOOT_TICKS  = (clock_freq_hz / 1000) * startup_delay_ms;

    reg [1:0]  state, state_next;
    reg [31:0] delay_count;

    // ---------------------------------------------------------------
    // Stage 1: state register, async active-low reset to STATE_IDLE
    // ---------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: next-state logic
    // ---------------------------------------------------------------
    always @(*) begin
        state_next = state;
        case (state)
            STATE_IDLE: begin
                if (!restart_req)
                    state_next = STATE_POWER;
            end
            STATE_POWER: begin
                if (restart_req)
                    state_next = STATE_IDLE;
                else if (delay_count == POWER_TICKS - 1)
                    state_next = STATE_STARTUP;
            end
            STATE_STARTUP: begin
                if (restart_req)
                    state_next = STATE_IDLE;
                else if (delay_count == BOOT_TICKS - 1)
                    state_next = STATE_READY;
            end
            STATE_READY: begin
                if (restart_req)
                    state_next = STATE_IDLE;
            end
            default: state_next = STATE_IDLE;
        endcase
    end

    // ---------------------------------------------------------------
    // Stage 3: registered Moore outputs, fully specified per state
    // ---------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            bt_power_en <= 1'b0;
            bt_reset_n  <= 1'b0;
        end else begin
            case (state_next)
                STATE_IDLE: begin
                    bt_power_en <= 1'b0;
                    bt_reset_n  <= 1'b0;
                end
                STATE_POWER: begin
                    bt_power_en <= 1'b1;
                    bt_reset_n  <= 1'b0;   // power up while held in reset
                end
                STATE_STARTUP: begin
                    bt_power_en <= 1'b1;
                    bt_reset_n  <= 1'b1;   // release reset, let module boot
                end
                STATE_READY: begin
                    bt_power_en <= 1'b1;
                    bt_reset_n  <= 1'b1;
                end
                default: begin
                    bt_power_en <= 1'b0;
                    bt_reset_n  <= 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            delay_count <= 32'd0;
        end else if (state != state_next) begin
            delay_count <= 32'd0;
        end else begin
            delay_count <= delay_count + 32'd1;
        end
    end

    assign bt_ready = (state == STATE_READY);

endmodule
