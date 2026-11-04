/************************************************************************
 * File Name       : yolo_quant_table_f7.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_quant_table_f7
 * Description     : PPU-F7 变体量化表：256 profiles x 4 words =
 *                   1024 x 32 BRAM，BMG IP（yolo_quant_bram，真双口、
 *                   字节写使能、输出寄存器 DISABLED -> 读延迟 1 拍）。
 *                   V1.1 原件 port B 空置，本变体引出 port B 只读口供
 *                   ppu_shell_top 取包（W_ENG 让渡期读量化字段）。
 *                   TDP 同址冲突结构性规避同 yolo_buf_table_f7（写读
 *                   不同时存在；读-读任意组合安全）。
 * Dependencies    : ip/yolo_quant_bram (BMG v8.4 XCI)，与 ps_axi_pl 线
 *                   共用同一 XCI，未另建 IP。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版——自 yolo_quant_table V1.1
 *                                复制扩展 port B 只读（原件冻结不动）。
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_quant_table_f7 (
    input  wire        clk_i     ,
    // port A: AXI aperture, write & read time-shared
    input  wire        a_we_i    ,
    input  wire [3:0]  a_wstrb_i ,
    input  wire [9:0]  a_waddr_i ,
    input  wire [31:0] a_wdata_i ,
    input  wire [9:0]  a_raddr_i ,
    output wire [31:0] a_rdata_o ,  // 1-cycle latency
    // port B: PPU shell read only (W_ENG grant window)
    input  wire [9:0]  b_raddr_i ,
    output wire [31:0] b_rdata_o    // 1-cycle latency
);

    yolo_quant_bram u_bram (
        .clka (clk_i),
        .ena  (1'b1),
        .wea  (a_we_i ? a_wstrb_i : 4'h0),
        .addra(a_we_i ? a_waddr_i : a_raddr_i),
        .dina (a_wdata_i),
        .douta(a_rdata_o),
        .clkb (clk_i),
        .enb  (1'b1),
        .web  (4'h0),
        .addrb(b_raddr_i),
        .dinb (32'h0),
        .doutb(b_rdata_o)
    );

endmodule
