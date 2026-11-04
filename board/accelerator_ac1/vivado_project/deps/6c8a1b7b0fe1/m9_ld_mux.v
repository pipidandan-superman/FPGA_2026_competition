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
    // ---- feeder inlets ----
    input  wire [63:0] w_beat_data   ,
    input  wire        w_beat_first  ,
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

    // phase: 0=W, 1=X lo, 2=X hi of the current k
    reg [1:0] ph;

    // ready 语义=「本拍 mux 将该源数据锁进 ld_tdata」（present 沿原子双动：
    // mux 锁存与源推进同拍发生，源数据绝不在被锁存前被覆盖）。
    // 假 ready（只看 ph+tready 不看 !tvalid/标志）会让发卡器提前一拍
    // 换数据——首跑 BEAT_DIFF 的根因。
    assign w_beat_ready = (ph == 2'd0) && !ld_tvalid && ld_tready;
    assign x_beat_ready = ((ph == 2'd1) && !ld_tvalid && ld_tready
                                            && x_beat_valid && !x_beat_hi)
                       || ((ph == 2'd2) && !ld_tvalid && ld_tready
                                            && x_beat_valid &&  x_beat_hi);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= 2'd0; ld_tvalid <= 1'b0;
            ld_tdata <= 64'd0; ld_first <= 1'b0; ld_last <= 1'b0;
            ld_is_x <= 1'b0; ld_x_hi <= 1'b0;
        end else begin
            if (!ld_tvalid) begin
                // present the phase's beat when its source offers one
                if (ph == 2'd0 && w_beat_valid) begin
                    ld_tdata <= w_beat_data; ld_first <= w_beat_first;
                    ld_last <= 1'b0; ld_is_x <= 1'b0; ld_x_hi <= 1'b0;
                    ld_tvalid <= 1'b1;
                end else if (ph == 2'd1 && x_beat_valid && !x_beat_hi) begin
                    ld_tdata <= x_beat_data; ld_first <= 1'b0;
                    ld_last <= 1'b0; ld_is_x <= 1'b1; ld_x_hi <= 1'b0;
                    ld_tvalid <= 1'b1;
                end else if (ph == 2'd2 && x_beat_valid && x_beat_hi) begin
                    ld_tdata <= x_beat_data; ld_first <= 1'b0;
                    ld_last <= x_beat_last; ld_is_x <= 1'b1; ld_x_hi <= 1'b1;
                    ld_tvalid <= 1'b1;
                end
            end else if (ld_tready) begin
                ld_tvalid <= 1'b0;
                ph <= (ph == 2'd2) ? 2'd0 : ph + 2'd1;
            end
        end
    end

    // （拍序见证在 TB 侧逐拍比对——Verilog-2001 无 assert，RTL 不掺仿真语句）

endmodule
