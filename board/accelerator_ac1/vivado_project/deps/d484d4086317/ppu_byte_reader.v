/************************************************************************
 * File Name       : ppu_byte_reader.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_byte_reader
 * Description     : PPU-F3 —— DMA 64b 拍 → 字节流（lane0=低地址字节，
 *                   小端序）。逐段加载（start+len），尾拍超界字节丢弃
 *                  （按段字节计数截尾）；len=0 立即 done。1 字节/拍。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 ************************************************************************/

module ppu_byte_reader (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,
    input  wire [23:0] len_i,
    input  wire        beat_valid_i,
    output wire        beat_ready_o,
    input  wire [63:0] beat_data_i,
    output wire        out_valid_o,
    input  wire        out_ready_i,
    output wire [7:0]  out_data_o,
    output reg         done_o
);

    reg [23:0] len_r;
    reg [23:0] cnt_r;                     // 已交付字节
    reg        buf_v;
    reg [63:0] buf_d;
    reg [2:0]  buf_cnt;                   // 缓冲内有效字节
    reg        busy_r;

    assign beat_ready_o = ~buf_v && busy_r;
    assign out_valid_o  = buf_v;
    assign out_data_o   = buf_d[7:0];

    wire [23:0] need_w = len_r - cnt_r;
    wire out_fire = out_valid_o && out_ready_i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            len_r <= 24'd0; cnt_r <= 24'd0;
            buf_v <= 1'b0; buf_d <= 64'd0; buf_cnt <= 3'd0;
            done_o <= 1'b0; busy_r <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (start_i) begin
                len_r  <= len_i;
                cnt_r  <= 24'd0;
                buf_v  <= 1'b0;
                buf_cnt<= 3'd0;
                busy_r <= (len_i != 24'd0);
                if (len_i == 24'd0)
                    done_o <= 1'b1;       // 0 长：立即完成
            end else if (beat_valid_i && beat_ready_o) begin
                buf_d   <= beat_data_i;
                buf_cnt <= (need_w[23:3] != 21'd0) ? 3'd7 :
                           need_w[2:0] - 3'd1;      // 尾拍有效字节-1
                buf_v   <= 1'b1;
            end else if (out_fire) begin
                buf_d <= {8'd0, buf_d[63:8]};
                cnt_r <= cnt_r + 24'd1;
                if (buf_cnt == 3'd0)
                    buf_v <= 1'b0;
                else
                    buf_cnt <= buf_cnt - 3'd1;
                if (cnt_r + 24'd1 == len_r) begin
                    done_o <= 1'b1;
                    busy_r <= 1'b0;
                end
            end
        end
    end

endmodule
