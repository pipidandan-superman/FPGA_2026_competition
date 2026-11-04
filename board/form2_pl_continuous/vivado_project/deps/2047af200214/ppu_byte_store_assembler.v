/************************************************************************
 * File Name       : ppu_byte_store_assembler.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_byte_store_assembler
 * Description     : PPU-F3 —— 字节流 → DMA 64b 拍（lane0=低地址字节，
 *                   小端序；基址 8B 对齐合同 → 起始满拍对齐，仅尾部
 *                   可部分拍，strb=(1<<cnt)-1）。
 *                   上游为 xfer y 流（无反压、每拍必收）：满拍转移拍
 *                   （cnt==8→出级）同拍仍收字节（字节落新累加器
 *                   lane0），保证逐拍连续接收不丢；idle 间隙由引擎
 *                   流闸（ppu_engine_mux）保证缓冲不溢出。
 *                   flush 脉冲冲刷残留部分拍（段末/请求末，粘性重试
 *                   至出级空）；start 复位累计器。idle = 冲刷完成且
 *                   无积压。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : 转移拍同拍收字节（xfer y 无 ready
 *                                适配）；暴露 acc_cnt_o/out_full_o
 *                                供引擎流闸。
 *   - V1.2 (2026-09-21) by LSL : 部分拍死 lane 掩码清零——转移拍无
 *       同拍新字节时累加器残留上轮值，尾拍内容随时序不定（desc103
 *       段5 实测 lane4-7 带前拍旧值）；按 strb 掩码输出确定化。
 ************************************************************************/

module ppu_byte_store_assembler (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,
    input  wire        flush_i,
    input  wire        in_valid_i,
    output wire        in_ready_o,
    input  wire [7:0]  in_data_i,
    output reg         beat_valid_o,
    input  wire        beat_ready_i,
    output reg  [63:0] beat_data_o,
    output reg  [7:0]  beat_strb_o,
    output wire        idle_o,
    output wire [3:0]  acc_cnt_o,         // 累加器字节数（流闸用）
    output wire        out_full_o         // 出级占用（流闸用）
);

    reg [63:0] acc_r;
    reg [3:0]  cnt_r;                     // 0..8 累计字节
    reg        flushed_r;

    // 满拍转移（acc→out 级）与部分拍冲刷共用 out 级；
    // 冲刷为粘性（flushed_r）直至排空，防 out 级占用拍丢冲刷
    wire xfer_full = (cnt_r == 4'd8) && !beat_valid_o;
    wire flush_pend = flush_i || (flushed_r && cnt_r != 4'd0);
    wire xfer_part = flush_pend && (cnt_r != 4'd8) && (cnt_r != 4'd0)
                     && !beat_valid_o && !xfer_full;
    wire beat_fire = beat_valid_o && beat_ready_i;
    // V1.2：部分拍死 lane 掩码——转移拍若同拍无新字节，累加器 lane1-7
    // 保留上轮残留（实测 desc103 尾拍 lane4-7 带前拍旧值），拍内容随
    // 时序不定 → 逐位对拍失配。按 strb 掩码输出，死 lane 恒 0（与
    // golden 生成约定一致）。
    wire [7:0]  part_strb_w = (8'h01 << cnt_r) - 8'h01;
    wire [63:0] part_mask_w = {{8{part_strb_w[7]}}, {8{part_strb_w[6]}},
                               {8{part_strb_w[5]}}, {8{part_strb_w[4]}},
                               {8{part_strb_w[3]}}, {8{part_strb_w[2]}},
                               {8{part_strb_w[1]}}, {8{part_strb_w[0]}}};
    // 接收条件：累加器有位，或恰处满拍转移拍（字节落新轮 lane0）
    assign in_ready_o = (cnt_r != 4'd8) || xfer_full;
    wire in_fire = in_valid_i && in_ready_o;

    assign idle_o = flushed_r && (cnt_r == 4'd0) && !beat_valid_o;
    assign acc_cnt_o = cnt_r;
    assign out_full_o = beat_valid_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            acc_r <= 64'd0; cnt_r <= 4'd0; flushed_r <= 1'b0;
            beat_valid_o <= 1'b0; beat_data_o <= 64'd0; beat_strb_o <= 8'd0;
        end else begin
            if (start_i) begin
                cnt_r <= 4'd0;
                flushed_r <= 1'b0;
            end
            if (flush_i)
                flushed_r <= 1'b1;
            // 出级交付
            if (beat_fire)
                beat_valid_o <= 1'b0;
            // 满拍/部分拍入出级
            if (xfer_full) begin
                beat_data_o <= acc_r;
                beat_strb_o <= 8'hFF;
                beat_valid_o <= 1'b1;
                cnt_r <= 4'd0;
            end else if (xfer_part) begin
                beat_strb_o <= part_strb_w;
                beat_data_o <= acc_r & part_mask_w;
                beat_valid_o <= 1'b1;
                cnt_r <= 4'd0;
            end
            // 字节入累加器：转移拍同拍收 → 新轮 lane0，否则按 cnt 落位
            if (in_fire) begin
                if (xfer_full) begin
                    acc_r <= {56'd0, in_data_i};
                    cnt_r <= 4'd1;
                end else begin
                    acc_r[8*cnt_r +: 8] <= in_data_i;
                    cnt_r <= cnt_r + 4'd1;
                end
            end
        end
    end

endmodule
