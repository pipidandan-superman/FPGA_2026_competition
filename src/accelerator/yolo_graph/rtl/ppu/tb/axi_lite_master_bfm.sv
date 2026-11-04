/************************************************************************
 * File Name       : axi_lite_master_bfm.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : axi_lite_master_bfm
 * Description     : PPU-F7 仿真用 AXI4-Lite 主 BFM：tb_ppu_f7 的全部
 *                   激励经它打入 ppu_f7_top 的 CSR 从口（F7 门的核心
 *                   = 控制面走真 AXI-Lite 通路，不再 TB 直驱内部线）。
 *                   wr32/rd32 两任务；激励全部在 negedge 沿变化（无
 *                   竞争），握手检测用 posedge NBA 影子标志（下一
 *                   negedge 可见），逐通道独立撤 valid——对任意
 *                   ready 时序（含恒高 ready）都恰好一次握手，不重复
 *                   发请求。bresp/rdata/rresp 在握手拍采样留档
 *                   （last_bresp_o/last_rdata_o/last_rresp_o）供 TB
 *                   断言 SLVERR 等。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版（xsim -sv；对照
 *                                ppu_axi_bfm V1.2 的任务风格）。
 ************************************************************************/
`timescale 1ns / 1ps

module axi_lite_master_bfm (
    input  wire        aclk    ,
    input  wire        aresetn ,
    // AXI4-Lite master interface
    output reg  [31:0] awaddr  ,
    output reg         awvalid ,
    input  wire        awready ,
    output reg  [31:0] wdata   ,
    output reg  [3:0]  wstrb   ,
    output reg         wvalid  ,
    input  wire        wready  ,
    input  wire [1:0]  bresp   ,
    input  wire        bvalid  ,
    output reg         bready  ,
    output reg  [31:0] araddr  ,
    output reg         arvalid ,
    input  wire        arready ,
    input  wire [31:0] rdata   ,
    input  wire [1:0]  rresp   ,
    input  wire        rvalid  ,
    output reg         rready  ,
    // response archive (sampled at the handshake edge)
    output wire [1:0]  last_bresp_o,
    output wire [31:0] last_rdata_o,
    output wire [1:0]  last_rresp_o
);

    // ---- 握手影子标志（posedge NBA 置位，negedge 可见）----
    reg aw_hs_q, w_hs_q, b_hs_q, ar_hs_q, r_hs_q;
    always @(posedge aclk) begin
        aw_hs_q <= awvalid && awready;
        w_hs_q  <= wvalid  && wready;
        b_hs_q  <= bvalid  && bready;
        ar_hs_q <= arvalid && arready;
        r_hs_q  <= rvalid  && rready;
    end

    // ---- 应答采样（握手拍的前沿值，NBA 留档）----
    reg [1:0]  bresp_q, rresp_q;
    reg [31:0] rdata_q;
    always @(posedge aclk) begin
        if (bvalid && bready) bresp_q <= bresp;
        if (rvalid && rready) begin
            rresp_q <= rresp;
            rdata_q <= rdata;
        end
    end

    assign last_bresp_o = bresp_q;
    assign last_rdata_o = rdata_q;
    assign last_rresp_o = rresp_q;

    // ---- 32 位写：AW/W/B 三通道独立握手后撤 ----
    task automatic wr32(input logic [31:0] a, input logic [31:0] d);
        bit aw_done, w_done, b_done;
        begin
            @(negedge aclk);
            aw_hs_q = 1'b0;  w_hs_q = 1'b0;  b_hs_q = 1'b0;
            aw_done = 0;     w_done  = 0;     b_done  = 0;
            awaddr  = a;     awvalid = 1'b1;
            wdata   = d;     wstrb   = 4'hF;  wvalid = 1'b1;
            bready  = 1'b1;
            while (!(aw_done && w_done && b_done)) begin
                @(negedge aclk);
                if (!aw_done && aw_hs_q) begin awvalid = 1'b0; aw_done = 1; end
                if (!w_done  && w_hs_q)  begin wvalid  = 1'b0; w_done  = 1; end
                if (!b_done  && b_hs_q)  begin bready  = 1'b0; b_done  = 1; end
            end
        end
    endtask

    // ---- 32 位读：AR/R 两通道独立握手后撤 ----
    task automatic rd32(input logic [31:0] a, output logic [31:0] d);
        bit ar_done, r_done;
        begin
            @(negedge aclk);
            ar_hs_q = 1'b0;  r_hs_q = 1'b0;
            ar_done = 0;     r_done  = 0;
            araddr  = a;     arvalid = 1'b1;
            rready  = 1'b1;
            while (!(ar_done && r_done)) begin
                @(negedge aclk);
                if (!ar_done && ar_hs_q) begin arvalid = 1'b0; ar_done = 1; end
                if (!r_done  && r_hs_q)  begin rready  = 1'b0; r_done  = 1; end
            end
            d = rdata_q;
        end
    endtask

    // ---- 复位期驱动安全值（避免 valid 悬空触发假握手）----
    initial begin
        awaddr = 32'h0; awvalid = 1'b0;
        wdata  = 32'h0; wstrb   = 4'h0; wvalid = 1'b0;
        bready = 1'b0;
        araddr = 32'h0; arvalid = 1'b0;
        rready = 1'b0;
        aw_hs_q = 1'b0; w_hs_q = 1'b0; b_hs_q = 1'b0;
        ar_hs_q = 1'b0; r_hs_q = 1'b0;
    end

endmodule
