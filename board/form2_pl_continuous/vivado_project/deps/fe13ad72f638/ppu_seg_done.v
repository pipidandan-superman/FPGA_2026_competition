/************************************************************************
 * File Name       : ppu_seg_done.v
 * Developer       : M10.6 Rung C line
 * Date            : 2026-10-18
 * Project Name    : YOLO object accel (5b build tree, M10.6 Rung C)
 * Module Name     : ppu_seg_done
 * Description     :
 *   HEADS 六段 seg_done 完成位图 tracker（SPEC M10.6 §2 完成位图提案
 *   (a) 案岛侧 6b RO CSR 机构 + L29 完成位图/部分隔离律的 RTL 落地）。
 *
 *   帧生命周期（门=0x114 doorbell 路径帧边界，与 walker W_CHK 指针
 *   复位同事件源=CTRL start_frame 脉冲）：
 *     frame_start_i / soft_reset_i / !rst_n → 位图清零 + heads_seen
 *       清零（新帧重新记账）。
 *     heads_start_pl_i（engine_mux S_IDLE 受理 HEADS 任务脉冲）→
 *       heads_seen 帧内粘着置 1：本帧出现过 heads 任务。
 *     seg_done_pl_i（engine_mux S_FLUSHW 出口脉冲=本段写妥 BRESP 全收
 *       +数据排空，§4.2 段粒度 done 语义）→ bitmap[seg_done_idx_i] 置 1。
 *       错误优先律：DMA 错路径引擎弃权不发该脉冲 → 位图冻结于部分
 *       完成态（PS 可经 A_SEG_DONE RO CSR 观察，部分呈现=探针违例
 *       由驱动/TB 判，RTL 只保证冻结不丢、不假满）。
 *
 *   commit 门（挂 doorbell 镜像）：commit_ok_o = 本帧无 heads 任务
 *     （非 heads 帧零行为变化，T7 恒等律）|| 位图全满（6'b11_1111）。
 *     消费方=yolo_desc_walker_f6 W_ENG 出口：last/ffe 到达且门不开
 *     → W_ERR 粘着 + err_evt_eng（ERROR_STATUS bit10/ERROR_INFO
 *     现场），无环发布/无 RESULT_SEQ 推进——错误优先于部分完成的
 *     正向封闭。时序核算：尾段 seg_done 脉冲（S_FLUSHW 出口寄存一
 *     拍）先于 done_o 至少 2 拍 [S_FLUSHW 出口→S_VDONE→done_o 两级
 *     寄存]，walker 经 shell 仲裁再多 1-2 拍见 ppu_desc_done_i，位图
 *     必已满——门为纯守卫不挡正例。
 *
 *   结构纪律：单位拍块单驱动（8-6859 多驱动双门法）；纯 Verilog-2001
 *   （RTL 铁律 .v）；观察面零数据通路扰动；PPU_NO_UPS 刀下恒可编译
 *   （本机构在 xfer heads 径，与 UPS 桩零耦合）。
 * Dependencies    : 无（f7_top 集成，馈源 ppu_engine_mux V2.1 脉冲口）。
 * Revision History:
 *   - V1.0 (2026-10-18) : first release（M10.6 Rung C PPP 合并链）。
 ************************************************************************/
`timescale 1ns / 1ps

module ppu_seg_done (
    input  wire       clk_i,
    input  wire       rst_n_i,          // 岛 glue 低有效全局复位
    input  wire       soft_reset_i,     // CTRL soft reset 脉冲（同 walker/
                                        // regfile 软复位面，rst_n_glue 域）
    input  wire       frame_start_i,    // CTRL start_frame 脉冲（0x114 帧
                                        // 边界；PL 三面线帧不Publish、此
                                        // 脉冲只随 doorbell 路径，恰好=
                                        // "commit 挂 doorbell 镜像"的帧域）
    input  wire       heads_start_pl_i, // HEADS 任务受理脉冲（帧内粘着）
    input  wire       seg_done_pl_i,    // 段完成脉冲（S_FLUSHW 出口）
    input  wire [2:0] seg_done_idx_i,   // 完成段序（0..5）
    output reg  [5:0] bitmap_o,         // 6b 完成位图（RO CSR 观察面）
    output wire       commit_ok_o       // commit 门（见头注）
);

    reg heads_seen_q;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bitmap_o     <= 6'b00_0000;
            heads_seen_q <= 1'b0;
        end else if (soft_reset_i || frame_start_i) begin
            // 帧边界/软复位：清账重来（与 walker 队列指针复位同事件）
            bitmap_o     <= 6'b00_0000;
            heads_seen_q <= 1'b0;
        end else begin
            if (heads_start_pl_i)
                heads_seen_q <= 1'b1;
            // 段完成置位；idx>=6 防御丢弃（heads 恒 6 段，3b idx 越界
            // 不会发生——保留守卫为低成本结构保险，置位宽语义不依赖它）
            if (seg_done_pl_i && (seg_done_idx_i < 3'd6))
                bitmap_o[seg_done_idx_i] <= 1'b1;
        end
    end

    // L29：六段全 1 才许 metadata commit；非 heads 帧（heads_seen=0）
    // 门恒开——m94 正典 CONCAT/其他帧发布行为与 v2.3 逐位一致
    // （T7 恒等律，位图逻辑对旧帧型零语义变化）。
    assign commit_ok_o = (!heads_seen_q) || (bitmap_o == 6'b11_1111);

endmodule
