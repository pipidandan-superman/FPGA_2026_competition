/************************************************************************
 * File Name       : ppu_gemm_stub_f7.v
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_gemm_stub_f7
 * Description     : PPU-F7a GEMM 后端占位桩（B3 通路占位合同的可综合
 *                   版，时序行为对齐 tb_ppu_f6.sv 桩逻辑）：req 单拍
 *                   脉冲启动，GEMM_DELAY 拍后回 done/err；abort 取消
 *                   在跑请求（帧丢弃语义）。
 *                   F7a 板上无 GEMM 引擎——GEMM_ERR_ALWAYS=1 使任何
 *                   GEMM 描述符（opcode[7:4]==0x0）都走 err 回路，
 *                   walker 进 W_ERR 粘着至 soft_reset（首错停后续，
 *                   不挂死、不伪装成功）。F7b/F8 换真引擎时删本桩。
 *                   纯 Verilog-2001（RTL 铁律 .v；无可综合 SV 特性
 *                   需求）。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版（自 tb_ppu_f6.sv 桩逻辑
 *                                移植，录序队列等 TB 专属物剔除）。
 ************************************************************************/
`timescale 1ns / 1ps

module ppu_gemm_stub_f7 (
    input  wire        clk_i       ,
    input  wire        rst_i       ,  // sync active-high (与 shell 同极性)
    // dispatch (from yolo_desc_walker_f6)
    input  wire        req_valid_i ,  // 单拍脉冲
    input  wire [6:0]  desc_idx_i  ,
    input  wire [7:0]  opcode_i    ,  // 未用，保留合同位
    // completion (to walker)
    output reg         done_o      ,  // 单拍脉冲
    output reg         err_o       ,  // 单拍脉冲（GEMM_ERR_ALWAYS 时替代 done）
    // event (frame discard cancels an in-flight request)
    input  wire        abort_i
);

    parameter integer GEMM_DELAY     = 8;   // 拍数（对齐 F6 TB 桩默认）
    parameter         GEMM_ERR_ALWAYS= 1;   // F7a：无真引擎，恒 err

    reg        run_q;
    reg [6:0]  cur_q;
    reg [3:0]  cnt_q;

    // unused dispatch contract bits (reserved for the real F7b engine)
    wire unused_ok = (opcode_i == 8'h0) && (cur_q == 7'd0);

    always @(posedge clk_i) begin
        if (rst_i) begin
            run_q   <= 1'b0;
            cur_q   <= 7'd0;
            cnt_q   <= 4'd0;
            done_o  <= 1'b0;
            err_o   <= 1'b0;
        end else begin
            done_o <= 1'b0;
            err_o  <= 1'b0;
            if (req_valid_i) begin
                run_q <= 1'b1;
                cur_q <= desc_idx_i;
                cnt_q <= 4'd0;
            end else if (run_q) begin
                if (abort_i) begin
                    run_q <= 1'b0;          // abort 取消（帧丢弃）
                end else begin
                    cnt_q <= cnt_q + 4'd1;
                    if (cnt_q >= GEMM_DELAY) begin
                        run_q <= 1'b0;
                        if (GEMM_ERR_ALWAYS)
                            err_o  <= 1'b1;
                        else
                            done_o <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
