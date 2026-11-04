/************************************************************************
 * File Name       : m9_w_feeder.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_w_feeder
 * Description     :
 *   Resident-W beat generator -- W-side of the frozen three-beat law
 *   (02_m9_issuer_spec.md section 3).  Layout law = M8 PIPE w_index
 *   (layout_plan.json, per-conv):
 *
 *     waddr(r,k) = W_BASE + base + rc_stride*rc + oc_stride*r
 *                        + seg_w_off + k
 *     wv[r][k]   = (8*rc + r >= oc) ? 8'h00 : W[8*rc + r][k]
 *                  (dead-row W zero: the engine computes the dead rows
 *                   harmlessly, gather truncates -- dead-row law)
 *
 *   Output: one 64b beat per k, data[8r+:8]=wv[r][k], first=(k==0).
 *   oc_stride == K (per-conv identity checked at blob compile; blob
 *   carries slab=base, rc_stride, seg_offsets explicitly).
 *
 *   M9.1 correctness-first byte-read port, dead rows skip the read.
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_w_feeder (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv W layout config ----
    input  wire [31:0] cfg_wbase     ,   // W region base (arena byte addr)
    input  wire [31:0] cfg_slab      ,   // w_index.base (layer slab start)
    input  wire [31:0] cfg_rc_stride ,
    input  wire [31:0] cfg_oc_stride ,   // == K
    input  wire [7:0]  cfg_oc        ,   // output channels
    // ---- per-block/per-segment runtime ----
    input  wire [4:0]  rt_rc         ,
    input  wire [10:0] rt_k          ,   // segment k count
    input  wire [31:0] rt_seg_off    ,   // seg w_off_in_slab (bytes)
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    // ---- W byte read port ----
    output reg  [31:0] waddr         ,
    output reg         wreq          ,
    input  wire [7:0]  wdata         ,
    input  wire        wvalid        ,
    // ---- W beat outlet ----
    output reg  [63:0] w_beat_data   ,
    output reg         w_beat_first  ,   // (k==0)
    output reg         w_beat_valid  ,
    input  wire        w_beat_ready
);

    localparam ST_IDLE = 3'd0, ST_ROW = 3'd1, ST_PRE = 3'd2, ST_DONE = 3'd3;
    reg [2:0] st;

    reg [2:0]  r_cur;      // 0..7 rows
    reg [10:0] k_cur;
    reg [10:0] k_r;
    reg [4:0]  rc_r;
    reg [31:0] seg_r;
    reg [7:0]  rows [0:7];

    wire [7:0]  row_abs = {rc_r, r_cur};        // 8*rc + r
    wire        dead    = (row_abs >= cfg_oc);
    wire [31:0] row_off = cfg_rc_stride * rc_r
                        + cfg_oc_stride * r_cur;

    assign busy = (st != ST_IDLE);
    assign done = (st == ST_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; wreq <= 1'b0; w_beat_valid <= 1'b0;
            r_cur <= 3'd0; k_cur <= 11'd0;
        end else begin
            w_beat_valid <= 1'b0;
            wreq <= 1'b0;
            case (st)
            ST_IDLE: if (start) begin
                rc_r <= rt_rc; k_r <= rt_k; seg_r <= rt_seg_off;
                r_cur <= 3'd0; k_cur <= 11'd0;
                st <= ST_ROW;
            end
            ST_ROW: begin
                if (dead) begin
                    rows[r_cur] <= 8'h00;
                    r_cur <= r_cur + 3'd1;
                    if (r_cur == 3'd7) st <= ST_PRE;
                end else if (!wreq) begin
                    waddr <= cfg_wbase + cfg_slab + row_off + seg_r + k_cur;
                    wreq  <= 1'b1;
                end else begin
                    wreq <= 1'b1;            // req 在途保持（顶默认 0 勿吞）
                    if (wvalid) begin
                        rows[r_cur] <= wdata;
                        wreq <= 1'b0;
                        r_cur <= r_cur + 3'd1;
                        if (r_cur == 3'd7) st <= ST_PRE;
                    end
                end
            end
            ST_PRE: begin
                w_beat_data  <= {rows[7],rows[6],rows[5],rows[4],
                                 rows[3],rows[2],rows[1],rows[0]};
                w_beat_first <= (k_cur == 11'd0);
                w_beat_valid <= 1'b1;
                if (w_beat_ready) begin
                    k_cur <= k_cur + 11'd1;
                    r_cur <= 3'd0;
                    if (k_cur == k_r - 1) st <= ST_DONE;
                    else                  st <= ST_ROW;
                end
            end
            ST_DONE: st <= ST_IDLE;
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
