/************************************************************************
 * File Name       : yolo_buf_table_f7.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_buf_table_f7
 * Description     : PPU-F7 变体缓冲表：1024 x 32 BRAM，BMG IP
 *                   （yolo_buf_bram，真双口、字节写使能、输出寄存器
 *                   DISABLED -> 读延迟 1 拍）。V1.1 原件 port B 空置，
 *                   本变体引出 port B 只读口供 ppu_shell_top 取包
 *                   （W_ENG 让渡期读 in0/in1 槽基址等字段）。
 *                   TDP 同址冲突结构性规避（用户铁律）：
 *                     - port A PS 写仅在 walker 空闲窗开放（顶层
 *                       tbl_locked 守卫），port B 只在 walker 运行期
 *                       （W_ENG 让渡）读——写读不同时存在；
 *                     - port A PS 读与 port B 引擎读同拍任意地址组合
 *                       均为读-读，BMG 无冲突语义。
 * Dependencies    : ip/yolo_buf_bram (BMG v8.4 XCI)，与 ps_axi_pl 线
 *                   共用同一 XCI，未另建 IP。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版——自 yolo_buf_table V1.1 复制
 *                                扩展 port B 只读（原件冻结不动）。
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_buf_table_f7 (
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

    yolo_buf_bram u_bram (
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
