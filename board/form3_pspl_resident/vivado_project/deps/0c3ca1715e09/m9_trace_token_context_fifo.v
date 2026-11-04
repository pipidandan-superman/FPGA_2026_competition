//====================================================================
// File name   : m9_trace_token_context_fifo.sv
// Author      : M9 verification
// Create date : 2026-10-11
// Description : Queue issuer identity until delayed Y output handshakes
// Target      : FPGA/ASIC
// Revision    : V1.0
//====================================================================
`timescale 1ns / 1ps

module m9_trace_token_context_fifo #(
    parameter integer DEPTH = 8
) (
    input  wire         clk             ,
    input  wire         rst_n           ,
    input  wire         arm             ,
    input  wire [15:0]  arm_tile_x     ,
    input  wire [15:0]  arm_tile_y     ,
    input  wire [15:0]  arm_oc0        ,
    input  wire [15:0]  arm_oc1        ,
    input  wire [15:0]  arm_k0         ,
    input  wire [15:0]  arm_k1         ,
    input  wire [3:0]   arm_buffer_id  ,
    input  wire         arm_tail       ,
    input  wire         arm_error      ,
    input  wire         y_valid        ,
    input  wire         y_ready        ,
    input  wire         y_last         ,
    output wire [15:0]  token_tile_x   ,
    output wire [15:0]  token_tile_y   ,
    output wire [15:0]  token_oc0      ,
    output wire [15:0]  token_oc1      ,
    output wire [15:0]  token_k0       ,
    output wire [15:0]  token_k1       ,
    output wire [3:0]   token_buffer_id,
    output wire [7:0]   token_generation,
    output wire         token_valid   ,
    output wire         token_ready   ,
    output wire         token_first   ,
    output wire         token_last    ,
    output wire         token_tail    ,
    output wire         token_error
);
    localparam integer PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    reg [15:0] q_tile_x [0:DEPTH-1];
    reg [15:0] q_tile_y [0:DEPTH-1];
    reg [15:0] q_oc0 [0:DEPTH-1];
    reg [15:0] q_oc1 [0:DEPTH-1];
    reg [15:0] q_k0 [0:DEPTH-1];
    reg [15:0] q_k1 [0:DEPTH-1];
    reg [3:0]  q_buffer [0:DEPTH-1];
    reg [7:0]  q_generation [0:DEPTH-1];
    reg        q_tail [0:DEPTH-1];
    reg        q_error [0:DEPTH-1];
    reg [PTR_W-1:0] q_head;
    reg [PTR_W-1:0] q_tail_ptr;
    reg [PTR_W-1:0] display_idx;
    reg [3:0]  q_count;
    reg [7:0]  generation [0:15];
    reg        active_q;
    reg [15:0] c_tile_x, c_tile_y, c_oc0, c_oc1, c_k0, c_k1;
    reg [3:0]  c_buffer;
    reg [7:0]  c_generation;
    reg        c_tail, c_error;
    reg        first_q;
    reg        sticky_error;
    wire y_fire = y_valid && y_ready;
    wire take_queued = y_fire && !active_q && (q_count != 0);
    wire [PTR_W-1:0] head_idx = q_head;
    integer i;

    wire show_queued = take_queued || first_q;
    assign token_tile_x = show_queued ? q_tile_x[display_idx] : c_tile_x;
    assign token_tile_y = show_queued ? q_tile_y[display_idx] : c_tile_y;
    assign token_oc0 = show_queued ? q_oc0[display_idx] : c_oc0;
    assign token_oc1 = show_queued ? q_oc1[display_idx] : c_oc1;
    assign token_k0 = show_queued ? q_k0[display_idx] : c_k0;
    assign token_k1 = show_queued ? q_k1[display_idx] : c_k1;
    assign token_buffer_id = show_queued ? q_buffer[display_idx] : c_buffer;
    assign token_generation = show_queued ? q_generation[display_idx] : c_generation;
    assign token_valid = y_valid;
    assign token_ready = y_ready;
    assign token_first = first_q;
    assign token_last = y_last;
    assign token_tail = show_queued ? q_tail[display_idx] : c_tail;
    assign token_error = sticky_error |
                         (show_queued ? q_error[display_idx] : c_error);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_head <= 4'd0;
            q_tail_ptr <= 4'd0;
            display_idx <= 4'd0;
            q_count <= 4'd0;
            active_q <= 1'b0;
            c_tile_x <= 16'd0; c_tile_y <= 16'd0;
            c_oc0 <= 16'd0; c_oc1 <= 16'd0;
            c_k0 <= 16'd0; c_k1 <= 16'd0;
            c_buffer <= 4'd0; c_generation <= 8'd0;
            c_tail <= 1'b0; c_error <= 1'b0;
            first_q <= 1'b0;
            sticky_error <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                q_tile_x[i] <= 16'd0; q_tile_y[i] <= 16'd0;
                q_oc0[i] <= 16'd0; q_oc1[i] <= 16'd0;
                q_k0[i] <= 16'd0; q_k1[i] <= 16'd0;
                q_buffer[i] <= 4'd0; q_generation[i] <= 8'd0;
                q_tail[i] <= 1'b0; q_error[i] <= 1'b0;
            end
            for (i = 0; i < 16; i = i + 1)
                generation[i] <= 8'd0;
        end else begin
            if (arm) begin
                if (q_count == DEPTH) begin
                    sticky_error <= 1'b1;
                end else begin
                    q_tile_x[q_tail_ptr] <= arm_tile_x;
                    q_tile_y[q_tail_ptr] <= arm_tile_y;
                    q_oc0[q_tail_ptr] <= arm_oc0;
                    q_oc1[q_tail_ptr] <= arm_oc1;
                    q_k0[q_tail_ptr] <= arm_k0;
                    q_k1[q_tail_ptr] <= arm_k1;
                    q_buffer[q_tail_ptr] <= arm_buffer_id;
                    q_generation[q_tail_ptr] <= generation[arm_buffer_id];
                    q_tail[q_tail_ptr] <= arm_tail;
                    q_error[q_tail_ptr] <= arm_error;
                    q_tail_ptr <= (q_tail_ptr == DEPTH-1) ?
                                  {PTR_W{1'b0}} : q_tail_ptr + 1'b1;
                    q_count <= q_count + 4'd1;
                    if (generation[arm_buffer_id] != 8'hff)
                        generation[arm_buffer_id] <= generation[arm_buffer_id] + 8'd1;
                end
            end
            if (take_queued) begin
                display_idx <= head_idx;
                c_tile_x <= q_tile_x[head_idx];
                c_tile_y <= q_tile_y[head_idx];
                c_oc0 <= q_oc0[head_idx];
                c_oc1 <= q_oc1[head_idx];
                c_k0 <= q_k0[head_idx];
                c_k1 <= q_k1[head_idx];
                c_buffer <= q_buffer[head_idx];
                c_generation <= q_generation[head_idx];
                c_tail <= q_tail[head_idx];
                c_error <= q_error[head_idx];
                q_head <= (q_head == DEPTH-1) ?
                          {PTR_W{1'b0}} : q_head + 1'b1;
                q_count <= q_count - 4'd1;
                active_q <= !y_last;
                first_q <= 1'b1;
            end else if (y_fire && active_q && y_last) begin
                active_q <= 1'b0;
                c_error <= 1'b0;
                first_q <= 1'b0;
            end else if (y_fire) begin
                first_q <= 1'b0;
            end else if (y_fire && !active_q && (q_count == 0)) begin
                sticky_error <= 1'b1;
            end
        end
    end
endmodule
