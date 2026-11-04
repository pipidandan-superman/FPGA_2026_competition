/************************************************************************
 * File Name       : yolo_ppu_maxpool5_b.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_maxpool5_b
 * Description     : maxpool5 核 B 变体（Stage3-v2 结构整改候选）——
 *                   保留 A 的 269 深延迟线 + 运行时动态下标，把单拍
 *                   "25 抽头选择 + 25 级串行比较"拆为两拍：
 *                     第 1 拍：25 个抽头各自选择 + 掩码折入 -> tap_q 寄存
 *                     第 2 拍：25->13->7->4->2->1 平衡 max 树 -> out 寄存
 *                   诊断价值（规格 §二 B 案）：与 A/C 三方 OOC 对比可
 *                   分离"抽头选择 mux"与"串行比较链"各自的时序占比。
 *
 *   语义合同与 A 逐位相同：掩码种子 0x80=pad、读移位后语义
 *   (idx==0 -> in_data_i，否则 dl_r[idx-1]，idx=(4-r)*(W+2)+(4-t))、
 *   CHW 线性同形流、每输入步 1 字节、pad 步自走、发射 (pr>=2,pc>=2)、
 *   每通道恰 H*W 字节。控制面/游标推进与 A 逐字相同。
 *
 *   时延：发射步 T -> out_valid 于 T+2（P=2，与 C 同）；busy_o 覆盖
 *   流水 = (state!=IDLE)||v1_r||out_valid_o，末发射拍后 1 拍落（比 A
 *   的 busy 语义更健全，引擎完成三联不受影响）。
 *
 *   资源：dl_r 全保留（269x8 FF + 25x 269:1 动态索引 mux）+ tap_q 25x8
 *   + 树 24 个 max 节点——仅减串行链扇出压力，FF 不减（对 C 的
 *   -1880 FF 对照）。
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V2.0-B (2026-09-23) by LSL : 两拍拆分（Stage3-v2 规格 §二 B 案）。
 *   - 基于 A 变体 V1.1 (2026-09-19) 语义合同。
 ************************************************************************/

module yolo_ppu_maxpool5_b #(
    parameter integer MAXW = 64          //延迟线容量上界（W 域）
) (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- task start（ST_IDLE 时采样）----
    input  wire        start_i,    //启动脉冲
    input  wire [15:0] c_i,        //通道数 C
    input  wire [15:0] h_i,        //输入/输出高 H
    input  wire [15:0] w_i,        //输入/输出宽 W
    // ---- input byte stream（CHW 线性序）----
    output wire        in_ready_o, //本拍可收输入字节（输入步）
    input  wire        in_valid_i,
    input  wire [7:0]  in_data_i,
    // ---- output byte stream（CHW 线性序，同形）----
    output reg         out_valid_o,
    output reg  [7:0]  out_data_o,
    output reg         out_last_o, //末字节同拍脉冲
    output wire        busy_o
);

    localparam [1:0]  ST_IDLE = 2'd0;
    localparam [1:0]  ST_RUN  = 2'd1;
    localparam integer DLN = 4 * (MAXW + 2) + 5;

    reg [1:0]  state_r;
    reg [15:0] cw_r, ch_r;           //锁存 W/H
    reg [15:0] ctot_r;               //锁存 C
    reg [15:0] pr_r, pc_r;           //处理网格游标（行 [0,H+2)，列 [0,W+2)）
    reg [15:0] c_r;                  //通道计数
    reg [7:0]  dl_r [0:DLN-1];       //延迟线：dl_r[i] = i 步前进入的字节
    reg        v1_r, l1_r;           //第 1 拍 valid/last 流水

    // ---- 步进条件：输入步需握手，pad 步自走（与 A 逐字同）----
    wire input_step_w = (pr_r < ch_r) && (pc_r < cw_r);
    wire step_w       = input_step_w ? in_valid_i : 1'b1;
    wire emit_w       = step_w && (pr_r >= 16'd2) && (pc_r >= 16'd2);
    wire last_step_w  = (c_r == ctot_r - 16'd1)
                      && (pr_r == ch_r + 16'd1)
                      && (pc_r == cw_r + 16'd1);

    assign in_ready_o = (state_r == ST_RUN) && input_step_w;
    assign busy_o     = (state_r != ST_IDLE) || v1_r || out_valid_o;

    // ---- 第 1 拍：25 抽头选择 + 掩码折入（读移位后语义）----
    // tap_w[k]，k = r*5+t：idx=(4-r)*(cw_r+2)+(4-t)；
    // d = (idx==0) ? in_data_i : dl_r[idx-1]（边沿前 dl_r = 移位前数组）；
    // 掩码 = 窗行 pr-4+r 与窗列 pc-4+t 各自有效，否则 0x80。
    wire [7:0] tap_w [0:24];
    genvar gk;
    generate
        for (gk = 0; gk < 25; gk = gk + 1) begin : g_tap
            wire [15:0] idx_w = (4 - gk/5) * (cw_r + 16'd2) + (4 - gk%5);
            wire [7:0]  d_w   = (idx_w == 16'd0) ? in_data_i
                                                      : dl_r[idx_w - 16'd1];
            wire msk_w = (pr_r + gk/5 >= 4) && (pr_r + gk/5 < ch_r + 4)
                      && (pc_r + gk%5 >= 4) && (pc_r + gk%5 < cw_r + 4);
            assign tap_w[gk] = msk_w ? d_w : 8'h80;
        end
    endgenerate
    reg [7:0] tap_q [0:24];           //第 1 拍寄存

    // ---- 第 2 拍：平衡 max 树 25->13->7->4->2->1 ----
    function [7:0] smax(input [7:0] a, input [7:0] b);
        smax = ($signed(a) > $signed(b)) ? a : b;
    endfunction
    wire [7:0] t1_w [0:12];
    wire [7:0] t2_w [0:6];
    wire [7:0] t3_w [0:3];
    wire [7:0] t4_w [0:1];
    genvar gt;
    generate
        for (gt = 0; gt < 12; gt = gt + 1) begin : g_t1
            assign t1_w[gt] = smax(tap_q[2*gt], tap_q[2*gt+1]);
        end
    endgenerate
    assign t1_w[12] = tap_q[24];
    generate
        for (gt = 0; gt < 6; gt = gt + 1) begin : g_t2
            assign t2_w[gt] = smax(t1_w[2*gt], t1_w[2*gt+1]);
        end
    endgenerate
    assign t2_w[6] = t1_w[12];
    assign t3_w[0] = smax(t2_w[0], t2_w[1]);
    assign t3_w[1] = smax(t2_w[2], t2_w[3]);
    assign t3_w[2] = smax(t2_w[4], t2_w[5]);
    assign t3_w[3] = t2_w[6];
    assign t4_w[0] = smax(t3_w[0], t3_w[1]);
    assign t4_w[1] = smax(t3_w[2], t3_w[3]);
    wire [7:0] fin_w = smax(t4_w[0], t4_w[1]);

    integer i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r     <= ST_IDLE;
            out_valid_o <= 1'b0;
            out_last_o  <= 1'b0;
            v1_r        <= 1'b0;
        end else begin
            //默认单拍脉冲
            v1_r        <= 1'b0;
            out_valid_o <= 1'b0;
            out_last_o  <= 1'b0;

            case (state_r)
                ST_IDLE: begin
                    if (start_i) begin
                        cw_r   <= w_i;
                        ch_r   <= h_i;
                        ctot_r <= c_i;
                        pr_r   <= 16'd0;
                        pc_r   <= 16'd0;
                        c_r    <= 16'd0;
                        state_r <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (step_w) begin
                        //延迟线整体前移（pad 步也移：同列跨行恒隔 L 步）
                        for (i = DLN - 1; i > 0; i = i - 1)
                            dl_r[i] <= dl_r[i-1];
                        dl_r[0] <= in_data_i;   //pad 步为无效数据（掩码排除）

                        //第 1 拍：抽头 + 掩码 -> tap_q（发射步才需要，
                        //但自由寄存无害且省门控）
                        for (i = 0; i < 25; i = i + 1)
                            tap_q[i] <= tap_w[i];
                        v1_r <= emit_w;
                        l1_r <= last_step_w;

                        //游标推进：与 A 逐字相同
                        if (pc_r == cw_r + 16'd1) begin
                            pc_r <= 16'd0;
                            if (pr_r == ch_r + 16'd1) begin
                                pr_r <= 16'd0;
                                c_r  <= c_r + 16'd1;
                                if (last_step_w)
                                    state_r <= ST_IDLE;
                            end else begin
                                pr_r <= pr_r + 16'd1;
                            end
                        end else begin
                            pc_r <= pc_r + 16'd1;
                        end
                    end
                end

                default: state_r <= ST_IDLE;
            endcase

            // ---- 第 2 拍：树 -> out 寄存 ----
            out_data_o  <= fin_w;
            out_valid_o <= v1_r;
            out_last_o  <= v1_r && l1_r;
        end
    end

endmodule
