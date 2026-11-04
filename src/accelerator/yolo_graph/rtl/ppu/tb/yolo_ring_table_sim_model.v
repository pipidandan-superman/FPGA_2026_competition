/************************************************************************
 * File Name       : yolo_ring_table_sim_model.v
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ring_table
 * Description     : PPU-F6 仿真替身（仅 ModelSim 编译用）：result ring
 *                   的 BMG IP 存储原语行为模型。端口面与真件
 *                   rtl/ps_axi_pl/yolo_ring_table.sv 逐位对齐：
 *                   512x32 双口（A 只读 / B 字节写），输出寄存器关闭
 *                   → 1 拍同步读，与 CSR 线 TABLE_RD_LATENCY 合同同值。
 *                   环 FSM（yolo_result_ring.sv）本体为真件，不在替身
 *                   域。真件只在 Vivado/xsim 流（CSR 线正典）编译，
 *                   两者同名不同编译集，永不共存。
 *                   纯 Verilog-2001（RTL 铁律 .v；TB 侧行为件同律）。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : PPU-F6 初版（32 项 x 16 word）。
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_ring_table (
    input  wire        clk_i     ,
    // port A: PS read window (read only)
    input  wire [8:0]  a_raddr_i ,
    output wire [31:0] a_rdata_o ,   // 1-cycle latency
    // port B: publisher write port
    input  wire        b_we_i    ,
    input  wire [3:0]  b_wstrb_i ,
    input  wire [8:0]  b_waddr_i ,
    input  wire [31:0] b_wdata_i
);

    reg [31:0] mem [0:511];

    // port B: byte-write enabled
    integer k;
    always @(posedge clk_i) begin
        if (b_we_i) begin
            for (k = 0; k < 4; k = k + 1)
                if (b_wstrb_i[k])
                    mem[b_waddr_i][8*k +: 8] <= b_wdata_i[8*k +: 8];
        end
    end

    // port A: 1-cycle synchronous read
    reg [31:0] a_rd_q;
    always @(posedge clk_i) begin
        a_rd_q <= mem[a_raddr_i];
    end
    assign a_rdata_o = a_rd_q;

endmodule
