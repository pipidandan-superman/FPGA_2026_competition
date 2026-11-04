/************************************************************************
 * File Name       : ppu_done_arbiter.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_done_arbiter
 * Description     : PPU-F3 完成事件仲裁（手册 §4.2 v1.1 冻结序：
 *                   abort ＞ stop ＞ ffe(doorbell sticky) ＞ last(w0[9])
 *                   ＞ circular(仅回卷，永不帧终) ＞ dependency
 *                   (顺序期 informational))。F3 单描述符 shell 范围：
 *                   circular 无环不判，dependency 不判（头注存档）。
 *
 *   done（引擎 wrapper 唯一产生 = 全部写 BRESP OKAY + 数据流排空，
 *   §4.2/§5.6）到达时按当拍粘着事件定案：
 *     abort  ：丢弃本帧——无 desc_done、无 ring 发布、stopped；
 *     stop   ：desc 照常完成（desc_done），ring 发布当且仅当 last；
 *     ffe    ：desc 完成，ring 立即发布（不等 last）；
 *     last   ：desc 完成，ring 发布；
 *     无事件 ：desc 完成，无发布。
 *   done_cause[2:0]：0=无/未完成 1=普通 2=last 3=ffe 4=stop 5=abort
 *                   （同拍多事件取最高优先级者；stop+last → cause=stop
 *                   且发布）。
 *   多任务重臂：shell 每派发一任务脉冲 arm_i——清上一判决；判决落定
 *   拍消费 stop/ffe/abort 粘着（已折算进结果），PS 需要再触发须重发。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : arm_i 重臂 + 事件消费（run A 连跑
 *                                104 任务每条独立判决）。
 ************************************************************************/

module ppu_done_arbiter (
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       arm_i,           // 新任务派发（清上一判决）
    // 引擎完成（wrapper 唯一来源：BRESP 全 OK + 排空）
    input  wire       done_i,
    // 描述符静态位
    input  wire       last_i,          // w0[9]
    // PS 事件（脉冲，内部粘着至判决消费）
    input  wire       stop_i,
    input  wire       abort_i,
    input  wire       ffe_i,           // doorbell sticky
    // 判决
    output reg        desc_done_o,     // 本描述符完成（walker 前进）
    output reg        ring_publish_o,  // 发布结果环
    output reg  [2:0] done_cause_o,    // 编码见头注（保持至下一判决）
    output wire       stopped_o        // stop/abort 定案 → shell 停
);

    localparam [2:0] CAUSE_NONE = 3'd0, CAUSE_NORM = 3'd1, CAUSE_LAST = 3'd2,
                     CAUSE_FFE  = 3'd3, CAUSE_STOP = 3'd4, CAUSE_ABORT = 3'd5;

    reg stop_q, abort_q, ffe_q, decided_q, stopped_q;

    assign stopped_o = stopped_q;

    // 当拍事件归并（done 到达时一次性定案）
    reg [2:0] cause_c;
    reg       pub_c;
    reg       stp_c;
    always @* begin
        cause_c = CAUSE_NORM;
        pub_c   = 1'b0;
        stp_c   = 1'b0;
        if (abort_i || abort_q) begin
            cause_c = CAUSE_ABORT;                    // 1. 丢弃本帧
            stp_c   = 1'b1;
        end else if (stop_i || stop_q) begin          // 2. 完成后停
            cause_c = CAUSE_STOP;
            pub_c   = last_i;                         //    last 到则照常发布
            stp_c   = 1'b1;
        end else if (ffe_i || ffe_q) begin            // 3. 强制 frame_end
            cause_c = CAUSE_FFE;
            pub_c   = 1'b1;
        end else if (last_i) begin                    // 4. last 位
            cause_c = CAUSE_LAST;
            pub_c   = 1'b1;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            stop_q <= 1'b0; abort_q <= 1'b0; ffe_q <= 1'b0;
            decided_q <= 1'b0; stopped_q <= 1'b0;
            desc_done_o <= 1'b0; ring_publish_o <= 1'b0;
            done_cause_o <= CAUSE_NONE;
        end else begin
            desc_done_o    <= 1'b0;
            ring_publish_o <= 1'b0;
            // 事件粘着（PS 脉冲 → 电平，至判决消费）
            stop_q  <= (stop_i  | stop_q)  && !decided_q;
            abort_q <= (abort_i | abort_q) && !decided_q;
            ffe_q   <= (ffe_i   | ffe_q)   && !decided_q;

            if (arm_i) begin
                decided_q <= 1'b0;                    // 新任务重臂
            end else if (done_i && !decided_q) begin
                decided_q      <= 1'b1;
                desc_done_o    <= (cause_c != CAUSE_ABORT);
                ring_publish_o <= pub_c;
                done_cause_o   <= cause_c;
                stopped_q      <= stp_c;
            end
        end
    end

endmodule
