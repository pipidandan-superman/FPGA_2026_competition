/************************************************************************
 * File Name       : m9_ld_mux.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_ld_mux
 * Description     :
 *   Three-beat interleave mux: re-creates the frozen load-port rhythm
 *   per k index (yolo_gemm_top.v V1.2 header, B3 contract section 3 --
 *   the rhythm the DMA bridge used to derive from its phase counter):
 *
 *     beat 0 W    : is_x=0 x_hi=0, first=(k==0)
 *     beat 1 X lo : is_x=1 x_hi=0
 *     beat 2 X hi : is_x=1 x_hi=1, last=(k==K-1)
 *
 *   Backpressure: stalls the feeder beat outlet (valid held until
 *   ready); the W and X feeders run in lockstep because the mux only
 *   accepts the next W beat after the current k's X hi has been taken
 *   (and vice versa) -- strictly round-robin, zero reordering.
 *
 * Dependencies    : m9_w_feeder.v, m9_x_window.v
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_ld_mux (
    input  wire        clk           ,
    input  wire        rst_n         ,
    input  wire        skip_w        ,
    input  wire        w_only        ,
    // ---- feeder inlets ----
    input  wire [63:0] w_beat_data   ,
    input  wire        w_beat_first  ,
    input  wire        w_beat_last   ,
    input  wire        w_beat_valid  ,
    output wire        w_beat_ready  ,
    input  wire [63:0] x_beat_data   ,
    input  wire        x_beat_hi     ,
    input  wire        x_beat_last   ,
    input  wire        x_beat_valid  ,
    output wire        x_beat_ready  ,
    // ---- engine load port outlet (s_axis_ld semantics) ----
    output reg  [63:0] ld_tdata      ,
    output reg         ld_first      ,   // W beat of k==0
    output reg         ld_last       ,   // X hi of k==K-1 (TLAST)
    output reg         ld_is_x       ,
    output reg         ld_x_hi       ,
    output reg         ld_tvalid     ,
    input  wire        ld_tready
);

    // Normal: 0=W, 1=X lo, 2=X hi. skip_w: 0=X lo, 2=X hi.
    reg [1:0] ph;
    reg       block_start;
    wire      xlo_phase = (ph == 2'd1) || (skip_w && (ph == 2'd0));

    assign w_beat_ready = !skip_w && (ph == 2'd0) && !ld_tvalid && ld_tready;
    assign x_beat_ready = (xlo_phase && !ld_tvalid && ld_tready
                                      && x_beat_valid && !x_beat_hi)
                       || ((ph == 2'd2) && !ld_tvalid && ld_tready
                                            && x_beat_valid &&  x_beat_hi);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= 2'd0; ld_tvalid <= 1'b0; block_start <= 1'b1;
            ld_tdata <= 64'd0; ld_first <= 1'b0; ld_last <= 1'b0;
            ld_is_x <= 1'b0; ld_x_hi <= 1'b0;
        end else begin
            if (!ld_tvalid) begin
                if (!skip_w && ph == 2'd0 && w_beat_valid) begin
                    ld_tdata <= w_beat_data; ld_first <= w_beat_first;
                    ld_last <= w_only && w_beat_last;
                    ld_is_x <= 1'b0; ld_x_hi <= 1'b0;
                    ld_tvalid <= 1'b1;
                end else if (xlo_phase && x_beat_valid && !x_beat_hi) begin
                    ld_tdata <= x_beat_data; ld_first <= skip_w && block_start;
                    ld_last <= 1'b0; ld_is_x <= 1'b1; ld_x_hi <= 1'b0;
                    ld_tvalid <= 1'b1;
                end else if (ph == 2'd2 && x_beat_valid && x_beat_hi) begin
                    ld_tdata <= x_beat_data; ld_first <= 1'b0;
                    ld_last <= x_beat_last; ld_is_x <= 1'b1; ld_x_hi <= 1'b1;
                    ld_tvalid <= 1'b1;
                end
            end else if (ld_tready) begin
                ld_tvalid <= 1'b0;
                if (ld_last) block_start <= 1'b1;
                else if (block_start && (ph != 2'd2)) block_start <= 1'b0;
                if (w_only) ph <= 2'd0;
                else if (skip_w) ph <= (ph == 2'd2) ? 2'd0 : 2'd2;
                else ph <= (ph == 2'd2) ? 2'd0 : ph + 2'd1;
            end
        end
    end

    // （拍序见证在 TB 侧逐拍比对——Verilog-2001 无 assert，RTL 不掺仿真语句）

endmodule
