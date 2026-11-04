/************************************************************************
 * File Name       : ppu_mp5_engine.v
 * Developer       : LSL
 * Date            : 2026-09-22
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_mp5_engine
 * Description     : PPU-F5 MaxPool5 引擎（单描述符）——例化复用
 *                   yolo_ppu_maxpool5.sv（P2c 版零修改）+
 *                   ppu_byte_reader + ppu_byte_store_assembler，
 *                   经 ppu_dma_master 完成 DDR 搬移。
 *
 *   语义（probe 实测 desc44/45/46，SPPF 三连池）：0x13 线性
 *   in==out 同形——desc c/h/w = 槽 dims = (C,H,W)，w14 = C·H·W =
 *   out.size（与 upsample 的"desc=输出 dims"不同，此处无歧义，
 *   引擎形状仍取槽 0 dims 权威接线，shell V1.1 同口复用）。
 *
 *   机制：核为 (H+2)×(W+2) 步进网格/通道，输出 CHW 线性序同形流；
 *   写通路与 concat/upsample 同构——一次 wr_req 覆盖
 *   [out_base, out_base+CHW) + assembler 8B 聚合，AXI 侧线性。
 *
 *   流控（本模块核心，P2c 核接口两事实）：
 *     ① 输入侧真反压：in_ready_o 仅输入步（pr<H 且 pc<W）为高，
 *        in_valid 低即整网格冻结（pad 步也不走）——reader 保持
 *        字节等待即可，无偷吃风险（与 upsample 核不同）。
 *     ② 输出侧无 ready：out_valid_o 注册一拍必收。pad 步自走
 *        （每拍 1 步），两次输入握手间最坏自主推进 = 2 个尾 pad 列
 *        + 2 个底 pad 行（各 W+2 步）= 2W+6 步，发射 ≤ 2W+2 字节
 *        ——此突发不受输入闸控制，必须由输出 FIFO 吸收。
 *   故设输出 FIFO（FD=256）+ 输入准入闸：仅当 FIFO 空位 ≥ 2W+8
 *   （最坏突发 + 余量）且 W ≤ 64（核延迟线 MAXW 域）才呈现输入。
 *   **in_valid 与 out_ready 同闸共压**（F5a 纪律沿用）：闸关期
 *   reader 不交付、核不见 in_valid，网格冻结于输入步；FIFO 随
 *   assembler/DMA 交付排空 → 闸 reopen，无死锁。超界 W>64 表现
 *   为流闸永关（仿真看门狗可见，非静默错数据——upsample 同款
 *   域界语义）。
 *
 *   完成条件（关键，engine_mux V1.3 尾拍教训同类）：核 busy_o 在
 *   末输出拍呈现前一拍即掉（ST_RUN 末步同拍回 IDLE、out_valid
 *   注册晚一拍），故完成判据以字节计为准：(y_cnt==CHW 即出 FIFO
 *   发射尽) && (FIFO 空) && !core_busy（带保险）→ 一次 asm_flush
 *   → asm_idle && 写妥（wr_done 语义，§4.2）。
 *
 *   DMA：先 wr_req(out_base, CHW)（concat 同序：写先行），再
 *   rd_req(in0_base, CHW)；reader 供核输入。退化 C·H·W=0：无搬移
 *   直通 done（VIEW 同构）。dma_err/abort：任一推进态弃权回 IDLE
 *   无 done（shell 侧粘错/abort 落定，与 engine_mux 同构）。
 *
 *   容量界（壳层）：W ≤ 64（核 MAXW；闸永关可见）、
 *   2W+8 ≤ FD=256（同左）、C·H·W ≤ 2^24（rd_len 口宽；正典
 *   12800 远小）。FIFO 一写一读简单双口结构：读仅非空、写仅
 *   非满，同址同拍读写被指针纪律结构性排除（用户 TDP BRAM
 *   规则）；异步读 reg 阵列映 LUTRAM（F7 综合期可改同步读
 *   BRAM，合同不变）。
 *
 *   FIFO 零溢出公式（Stage3-v2 §三，2026-09-24 推导；C 变体
 *   V2.2 核 P=3 发射流水口径）：
 *     记 P = 核发射步至 out_valid_o 的寄存级数（现 P=3；A 为 1），
 *     B = 闸关后核自主推进段的最坏发射字节 = 2W+2（两次输入握手
 *     间 2W+6 步中的发射步上界；H=1 时 B=W，边界更松）；
 *     闸开判据 f_lvl+thr ≤ FD ⟹ 关闸采样点 f_lvl ≤ FD−thr；
 *     其后再入 FIFO 的保守上界 = 在途 P + 突发 B，故
 *       L_max = (FD−thr) + P + B ≤ FD  ⟺  thr ≥ B+P。
 *     W=64：B=130、P=3 → 需 thr ≥ 133，实际 thr=2W+8=136，
 *     余量 3 字节（P ≤ 6 全域覆盖）——**thr/FD 零改动**，本公式
 *     仅重证明既有参数在 P=3 下仍零溢出（mp5eng 门 T8 临界容量
 *     实测 f_lvl 峰值 ≤ L_max=253，证据见 f7tmg_run01/gate_mp5eng）。
 *     busy 语义：核 busy_o 末发射拍后 1 拍落，完成三联
 *     (y_cnt==CHW && f_lvl==0 && !busy) 恰一次触发——无滞留字节、
 *     无新 FIFO 事件，P 加深不改变该结论（busy 含全部流水级）。
 * Dependencies    : yolo_ppu_maxpool5.sv / ppu_byte_reader.v /
 *                   ppu_byte_store_assembler.v。
 * Revision History:
 *   - V1.0 (2026-09-22) by LSL : F5-MaxPool5 初版（单描述符门）。
 *   - V1.1 (2026-09-24) by LSL : CHW 元数据直入（用户裁定条件性 A 指示③
 *       推广）：chw_i（=desc w14/out_bytes）启动拍直锁 chw_r 与退化判据，
 *       删 c_i*h_i*w_i 启动乘（不变量 w14==槽0 c·h·w 全语料 51/51 验证）；
 *       窗口算术（thr/游标）仍用 c/h/w 形状口，语义零变化。
 ************************************************************************/

module ppu_mp5_engine (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,           // loader pass 后启动（脉冲）
    input  wire [31:0] in0_base_i,        // 输入缓冲基址（槽 0 低字）
    input  wire [31:0] out_base_i,        // 输出缓冲基址（槽 2 低字）
    input  wire [15:0] c_i, h_i, w_i,     // 输入形状（in0 槽 dims——表权威；
    input  wire [31:0] chw_i,             // CHW 元数据（=desc w14/out_bytes；
                                          //   不变量 w14==槽0 c·h·w 已全语料
                                          //   验证 2026-09-24：51/51。窗口
                                          //   算术仍用 c/h/w，仅删启动乘）
                                          // maxpool5 in==out 同形）
    // DMA 接口
    output reg         rd_req_valid_o,
    input  wire        rd_req_ready_i,
    output reg  [31:0] rd_addr_o,
    output reg  [23:0] rd_len_o,
    input  wire        rd_beat_valid_i,
    output wire        rd_beat_ready_o,
    input  wire [63:0] rd_beat_data_i,
    input  wire        rd_done_i,
    output reg         wr_req_valid_o,
    input  wire        wr_req_ready_i,
    output reg  [31:0] wr_addr_o,
    output reg  [23:0] wr_len_o,
    output wire        wr_beat_valid_o,
    input  wire        wr_beat_ready_i,
    output wire [63:0] wr_beat_data_o,
    output wire [7:0]  wr_beat_strb_o,
    input  wire        wr_done_i,
    input  wire        dma_err_i,         // DMA 错误/abort（取消推进）
    output reg         done_o,            // 引擎完成（写妥语义，§4.2）
    output wire        busy_o
);

    localparam [3:0] S_IDLE=4'd0, S_WREQ=4'd1, S_RREQ=4'd2,
                     S_RUN=4'd3, S_FLUSH=4'd4, S_VDONE=4'd5;
    localparam integer FD = 256;                  // 输出 FIFO 深（≥2W+8,
                                                  //  W≤64 域内 136 即够）
    localparam [15:0] MAXW_DOMAIN = 16'd64;       // 核延迟线 MAXW 域

    reg [3:0]  state_r;
    reg [31:0] in0_base_r, out_base_r;
    reg [15:0] c_r, h_r, w_r;
    reg [31:0] chw_r;                             // C·H·W（in==out 同长）
    reg [31:0] thr_r;                             // 准入阈值 2W+8
    reg [31:0] y_cnt_r;                           // 已入 assembler 字节
    reg        wr_done_all_r;

    // ---- 输出 FIFO：核无 ready 输出必收，pad 突发全靠它吸收 ----
    reg [7:0]  f_mem [0:FD-1];
    reg [7:0]  f_wp_r, f_rp_r;
    reg [8:0]  f_lvl_r;                           // 0..256

    // ---- 例化连线（reader / 核 / assembler）----
    reg         rdr_start_r, core_start_r, asm_start_r, asm_flush_r;
    wire        rdr_out_v_w;
    wire [7:0]  rdr_out_d_w;
    wire        core_in_rdy_w, core_busy_w;
    wire        core_out_v_w;
    wire [7:0]  core_out_d_w;
    wire        asm_rdy_w, asm_idle_w;

    // 输入准入闸（见文件头）：空位 ≥ 2W+8 且 W 在核域内才放行；
    // in_valid 与 out_ready 同闸共压（F5a 纪律——核虽真反压，同闸
    // 保证闸关期 reader 零交付，网格冻结点唯一）
    wire       gate_w = (w_r <= MAXW_DOMAIN) &&
                        (({16'd0, f_lvl_r} + thr_r) <= FD);
    wire       core_in_v_w = rdr_out_v_w && gate_w;

    // ---- FIFO 推入（核输出每拍必收；仅 S_RUN 有拍）----
    wire       push_w = core_out_v_w && (state_r == S_RUN);
    // ---- FIFO 弹出发射（仅 S_RUN；assembler 握手）----
    wire       emit_v_w   = (state_r == S_RUN) && (f_lvl_r != 9'd0);
    wire [7:0] emit_d_w   = f_mem[f_rp_r];
    wire       emit_fire_w = emit_v_w && asm_rdy_w;

    ppu_byte_reader u_reader (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(rdr_start_r), .len_i(chw_r[23:0]),
        .beat_valid_i(rd_beat_valid_i), .beat_ready_o(rd_beat_ready_o),
        .beat_data_i(rd_beat_data_i),
        .out_valid_o(rdr_out_v_w),
        .out_ready_i(core_in_rdy_w && gate_w),
        .out_data_o(rdr_out_d_w),
        .done_o()
    );

    yolo_ppu_maxpool5 #(.MAXW(64)) u_core (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(core_start_r),
        .c_i(c_r), .h_i(h_r), .w_i(w_r),
        .in_ready_o(core_in_rdy_w),
        .in_valid_i(core_in_v_w),
        .in_data_i(rdr_out_d_w),
        .out_valid_o(core_out_v_w), .out_data_o(core_out_d_w),
        .out_last_o(),
        .busy_o(core_busy_w)
    );

    ppu_byte_store_assembler u_asm (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(asm_start_r), .flush_i(asm_flush_r),
        .in_valid_i(emit_v_w), .in_data_i(emit_d_w),
        .in_ready_o(asm_rdy_w),
        .beat_valid_o(wr_beat_valid_o), .beat_ready_i(wr_beat_ready_i),
        .beat_data_o(wr_beat_data_o), .beat_strb_o(wr_beat_strb_o),
        .idle_o(asm_idle_w),
        .acc_cnt_o(), .out_full_o()
    );

    assign busy_o = (state_r != S_IDLE);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r <= S_IDLE;
            in0_base_r <= 32'd0; out_base_r <= 32'd0;
            c_r <= 16'd0; h_r <= 16'd0; w_r <= 16'd0;
            chw_r <= 32'd0; thr_r <= 32'd0;
            y_cnt_r <= 32'd0;
            wr_done_all_r <= 1'b0;
            f_wp_r <= 8'd0; f_rp_r <= 8'd0; f_lvl_r <= 9'd0;
            rdr_start_r <= 1'b0; core_start_r <= 1'b0;
            asm_start_r <= 1'b0; asm_flush_r <= 1'b0;
            rd_req_valid_o <= 1'b0; wr_req_valid_o <= 1'b0;
            rd_addr_o <= 32'd0; rd_len_o <= 24'd0;
            wr_addr_o <= 32'd0; wr_len_o <= 24'd0;
            done_o <= 1'b0;
        end else begin
            // 脉冲缺省
            rdr_start_r  <= 1'b0;
            core_start_r <= 1'b0;
            asm_start_r  <= 1'b0;
            asm_flush_r  <= 1'b0;
            done_o       <= 1'b0;

            // 写妥脉冲全局锁存（S_FLUSH 等待期不丢拍）
            if (wr_done_i)
                wr_done_all_r <= 1'b1;

            // ---- FIFO 推入/弹出（指针纪律见文件头；推入由闸不变
            //      量保证不满，弹出由非空保证）----
            if (push_w) begin
                f_mem[f_wp_r] <= core_out_d_w;
                f_wp_r <= f_wp_r + 8'd1;
            end
            if (emit_fire_w)
                f_rp_r <= f_rp_r + 8'd1;
            f_lvl_r <= f_lvl_r + (push_w ? 9'd1 : 9'd0)
                               - (emit_fire_w ? 9'd1 : 9'd0);

            // ---- 发射计数（完成判据，见文件头）----
            if (emit_fire_w)
                y_cnt_r <= y_cnt_r + 32'd1;

            // DMA 错误/abort：任一推进态弃权回 IDLE（无 done；
            // shell 粘错上报/abort 落定，与 engine_mux 同构）
            if (dma_err_i && state_r != S_IDLE && state_r != S_VDONE) begin
                state_r <= S_IDLE;
                rd_req_valid_o <= 1'b0;
                wr_req_valid_o <= 1'b0;
            end else begin
            case (state_r)
            // ---- 启动锁存 ----
            S_IDLE: begin
                if (start_i) begin
                    in0_base_r <= in0_base_i;
                    out_base_r <= out_base_i;
                    c_r <= c_i; h_r <= h_i; w_r <= w_i;
                    chw_r <= chw_i;                   // w14 直入（V1.1：删
                                                      // c_i*h_i*w_i 启动乘）
                    thr_r <= ({16'd0, w_i} << 1) + 32'd8;
                    y_cnt_r <= 32'd0;
                    f_wp_r <= 8'd0; f_rp_r <= 8'd0; f_lvl_r <= 9'd0;
                    wr_done_all_r <= 1'b0;
                    if (chw_i == 32'd0)
                        state_r <= S_VDONE;         // 退化：无搬移
                    else
                        state_r <= S_WREQ;
                end
            end
            // ---- 总写请求（concat 同构：写先行，拍随流到）----
            S_WREQ: begin
                if (!wr_req_valid_o) begin
                    wr_req_valid_o <= 1'b1;
                    wr_addr_o <= out_base_r;
                    wr_len_o  <= chw_r[23:0];
                end else if (wr_req_ready_i) begin
                    wr_req_valid_o <= 1'b0;
                    state_r <= S_RREQ;
                end
            end
            // ---- 读请求 → 三件同拍启动 ----
            S_RREQ: begin
                if (!rd_req_valid_o) begin
                    rd_req_valid_o <= 1'b1;
                    rd_addr_o <= in0_base_r;
                    rd_len_o  <= chw_r[23:0];
                end else if (rd_req_ready_i) begin
                    rd_req_valid_o <= 1'b0;
                    rdr_start_r  <= 1'b1;
                    asm_start_r  <= 1'b1;
                    core_start_r <= 1'b1;
                    state_r <= S_RUN;
                end
            end
            // ---- 流推进：发射尽 + FIFO 空 + 核 idle → 一次冲刷 ----
            S_RUN: begin
                if ((y_cnt_r == chw_r) && (f_lvl_r == 9'd0)
                    && !core_busy_w) begin
                    asm_flush_r <= 1'b1;
                    state_r <= S_FLUSH;
                end
            end
            // ---- 冲刷等待：assembler 排空 + 写妥 ----
            S_FLUSH: begin
                if (asm_idle_w && wr_done_all_r)
                    state_r <= S_VDONE;
            end
            // ---- 完成脉冲 ----
            S_VDONE: begin
                done_o  <= 1'b1;
                state_r <= S_IDLE;
            end
            default: state_r <= S_IDLE;
            endcase
            end
        end
    end

endmodule
