//====================================================================
// File name   : m9_trace_token_context.sv
// Author      : M9 verification
// Create date : 2026-10-11
// Description : Output-slot identity held across issuer load-ahead
// Target      : FPGA/ASIC
// Revision    : V1.3
//====================================================================
// V1.3 (2026-10-12 m93 bit round 5): module-level DONT_TOUCH.  V1.1
// (keep) and V1.2 (port-level DONT_TOUCH) both left the synthesized
// netlist byte-identical (u_trace_cells=23178 in every round; worst
// path still u_trace_context/q_k1_reg[3][15]/D at WNS=-1.515, and the
// arm-capture write mux was absorbed into the u_iss hierarchy) -- port
// declarations do not hold the implementing register against merge.
// The module-level attribute pins the whole boundary, which is the
// documented barrier against cross-hierarchy register absorption.
// Logic is unchanged (attributes only), observe-only, no ABI or
// datapath change; xsim gates re-run anyway.
`timescale 1ns / 1ps
(* DONT_TOUCH = "true" *) module m9_trace_token_context (
    input  wire         clk             ,
    input  wire         rst_n           ,
    input  wire         arm             ,
    input  wire [9:0]   arm_oy          ,
    input  wire [3:0]   arm_strip       ,
    input  wire [5:0]   arm_rc          ,
    input  wire [7:0]   total_oc        ,
    input  wire [31:0]  total_k         ,
    input  wire [1:0]   read_groups     ,
    input  wire [1:0]   segment_count   ,
    input  wire [3:0]   conv_index      ,
    input  wire         y_valid         ,
    input  wire         y_ready         ,
    input  wire         y_last          ,
    input  wire [4:0]   arm_valid_cols  ,
    (* DONT_TOUCH = "true" *) output reg [15:0] tile_x      ,
    (* DONT_TOUCH = "true" *) output reg [15:0] tile_y      ,
    (* DONT_TOUCH = "true" *) output reg [15:0] oc0         ,
    (* DONT_TOUCH = "true" *) output reg [15:0] oc1         ,
    (* DONT_TOUCH = "true" *) output reg [15:0] k0          ,
    (* DONT_TOUCH = "true" *) output reg [15:0] k1          ,
    (* DONT_TOUCH = "true" *) output reg [3:0]  buffer_id   ,
    (* DONT_TOUCH = "true" *) output reg [7:0]  generation  ,
    (* DONT_TOUCH = "true" *) output reg [3:0]  output_conv ,
    output wire         first           ,
    output wire         tail            ,
    output wire         error
);
    reg [7:0] reuse_count [0:3];
    reg       first_q;
    reg       tail_q;
    reg       error_q;
    reg       active_q;
    wire [15:0] arm_oc0 = {7'd0, arm_rc, 3'd0};
    wire [15:0] arm_oc_end = arm_oc0 + 16'd7;
    integer i;

    assign first = first_q;
    assign tail = tail_q;
    assign error = error_q | (y_valid && !active_q);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_x <= 16'd0;
            tile_y <= 16'd0;
            oc0 <= 16'd0;
            oc1 <= 16'd0;
            k0 <= 16'd0;
            k1 <= 16'd0;
            buffer_id <= 4'd0;
            generation <= 8'd0;
            output_conv <= 4'd0;
            first_q <= 1'b0;
            tail_q <= 1'b0;
            error_q <= 1'b0;
            active_q <= 1'b0;
            for (i = 0; i < 4; i = i + 1)
                reuse_count[i] <= 8'd0;
        end else begin
            if (arm) begin
                // Strip origin is an output-space coordinate, 16*s.
                tile_x <= {8'd0, arm_strip, 4'd0};
                tile_y <= {6'd0, arm_oy};
                oc0 <= arm_oc0;
                oc1 <= (arm_oc_end < {8'd0, total_oc}) ? arm_oc_end :
                       {8'd0, total_oc} - 16'd1;
                // A Y token represents the whole accumulated dot product,
                // not the currently loading K segment. W oc_stride == K.
                k0 <= 16'd0;
                k1 <= total_k[15:0] - 16'd1;
                buffer_id <= {2'd0, read_groups};
                generation <= reuse_count[read_groups];
                output_conv <= conv_index;
                first_q <= 1'b1;
                tail_q <= (arm_valid_cols < 5'd16) ||
                          (arm_oc_end >= {8'd0, total_oc});
                active_q <= 1'b1;
                // Multi-segment output may use several read groups. Its
                // single bank field is deliberately rejected until bank
                // lifecycle events, rather than one guessed bank, exist.
                error_q <= error_q | active_q | (segment_count != 2'd1) |
                           (total_k == 0) | (total_k > 32'd65536) |
                           (arm_oc0 >= {8'd0, total_oc}) |
                           (reuse_count[read_groups] == 8'hff);
                if (reuse_count[read_groups] != 8'hff)
                    reuse_count[read_groups] <= reuse_count[read_groups] + 8'd1;
            end else if (y_valid && y_ready) begin
                first_q <= 1'b0;
                if (y_last)
                    active_q <= 1'b0;
            end
        end
    end
endmodule
