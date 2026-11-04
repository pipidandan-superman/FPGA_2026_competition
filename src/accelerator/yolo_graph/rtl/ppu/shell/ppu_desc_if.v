/************************************************************************
 * File Name       : ppu_desc_if.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_desc_if
 * Description     : PPU-F3 单描述符 shell —— 描述符/缓冲/quant 表取包器。
 *                   按槽位顺序发起 1 拍同步表读（BRAM port B 模型），
 *                   把描述符 32 字 + 引用缓冲项 + 引用 quant 项锁存成
 *                   "bundle"，供 ppu_loader 纯寄存器域九步校验。
 *
 *   取包策略（与 loader 校验适用域严格一致，镜像 f3_prep.loader_mirror）：
 *     槽 0    = in0          （全部算子）
 *     槽 1    = in1          （仅 add 0x11）
 *     槽 2    = out          （非 heads；heads=0x3FF 空编码不取）
 *     槽 3..10= 段 0..7      （仅 concat/heads；present=段字非零；
 *                              数据事实：非 XFER 算子 n_seg=1 但段表空）
 *     quant 槽 0/1 = prof_in0/prof_in1（仅 add，含 prof=0：表内实项）
 *     quant 槽 2..9 = 段 profile    （仅 concat 且 prof!=0；heads 恒等豁免）
 *     id 超界（buf>=128 / quant>=256）不取（fetched=0 → loader 步 3/7 报）
 *
 *   表口合同：周期 k 呈现 addr（寄存器输出），周期 k+1 din_i 有效，
 *   采样沿在 k+2（BFM 侧 din<=rom[addr]）。
 * Dependencies    : 无（纯时序）。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : buf/quant id 超界取数门（sid<128 /
 *       qid<256 才取）——10b 表地址对 {id,低位} 截断回绕（实测
 *       qid=300 回绕取 176）误置 fetched，步 3/7 超界负例假通过
 *       （B1 L14 desc123 实测）。头注合同本就要求超界不取。
 *   - V1.2 (2026-09-24) by LSL : 表读数据本地捕获 + 按槽位分发（用户
 *       指示⑤，F7 时序整改 v3 / v19）。V1.1 的 buf/qt 回采把 BRAM Q
 *       （buf_din_i/qt_din_i）经变址切片直接写 704b+ 宽 sb/qm 寄存器
 *       ——每数据位扇出巨大，placer 拉散成 8-9ns 纯网线（v18 BD
 *       u_dif 443 失败路径中 250 条 = buf_tbl BRAM→sb_*_o/D，ll 0-1）。
 *       修法：bufd_r/qtd_r 本地捕获寄存（BRAM 只驱 32+32 FF，低扇出
 *       可贴 BRAM），捕获后一拍再按槽位/字序分发进 sb/qm（内部扇出
 *       获整拍预算）。S_BUF/S_QT 回采流水 2 拍→3 拍（发址→din 落
 *       bufd_r/qtd_r→sb/qm 写）：吞吐不变（每拍一址），done_o 至多
 *       晚 ≤21 拍；端口/取包规则/单脉冲/超界门语义零变化。
 ************************************************************************/

module ppu_desc_if (
    input  wire        clk_i,
    input  wire        rst_i,
    // 取包请求
    input  wire        req_i,              // 上升启动
    input  wire [6:0]  desc_idx_i,
    output wire        busy_o,
    output reg         done_o,             // bundle 就绪脉冲（保持到被取）
    // 表口（1 拍同步读）
    output reg  [11:0] desc_addr_o,
    input  wire [31:0] desc_din_i,
    output reg  [9:0]  buf_addr_o,
    input  wire [31:0] buf_din_i,
    output reg  [9:0]  qt_addr_o,
    input  wire [31:0] qt_din_i,
    // ---- bundle：描述符域 ----
    output reg  [7:0]  b_opcode_o,
    output reg  [15:0] b_w0_o,             // w0[15:0]（step2 原位校验）
    output reg  [7:0]  b_desc_id_o,        // 请求槽位号（真 desc_id）
    output reg  [9:0]  b_in0_o, b_in1_o, b_out_o,
    output reg  [15:0] b_c_o, b_h_o, b_w_o,
    output reg  [15:0] b_prof0_o, b_prof1_o,
    output reg  [15:0] b_nseg_o,
    output reg  [31:0] b_out_bytes_o,
    output reg  [7:0]  b_seg_present_o,    // 段字非零标志
    // ---- bundle：段表（present 项有效）----
    output reg  [79:0]  b_seg_buf_o,       // 8×10b
    output reg  [79:0]  b_seg_prof_o,      // 8×10b
    output reg  [255:0] b_seg_len_o,       // 8×32b
    // ---- bundle：缓冲槽 0..10（base/size/stride/c/h/w/valid/prod）----
    output reg  [703:0] sb_base_o,         // 11×64b
    output reg  [351:0] sb_size_o,         // 11×32b
    output reg  [351:0] sb_stride_o,       // 11×32b
    output reg  [175:0] sb_c_o,            // 11×16b
    output reg  [175:0] sb_h_o,            // 11×16b
    output reg  [175:0] sb_w_o,            // 11×16b
    output reg  [10:0]  sb_valid_o,
    output reg  [87:0]  sb_prod_o,         // 11×8b
    output reg  [10:0]  sb_fetched_o,      // 实取标志（loader 步 3 配对）
    // ---- bundle：quant 槽 0..9（m/shift/实取）----
    output reg  [319:0] qm_o,              // 10×32b
    output reg  [59:0]  qs_o,              // 10×6b
    output reg  [9:0]   q_fetched_o
);

    localparam [2:0] S_IDLE = 3'd0, S_DESC = 3'd1, S_DEC = 3'd2,
                     S_BUF  = 3'd3, S_QT  = 3'd4, S_DONE = 3'd5;

    reg [2:0]  state_r;
    reg [6:0]  idx_r;
    reg        busy_r;

    // 描述符 32 字锁存
    reg [31:0] dw_r [0:31];

    // 取包计划（DEC 期算好）
    reg [10:0] app_r;                        // 缓冲槽适用位
    reg [9:0]  appq_r;                       // quant 槽适用位
    reg [9:0]  sid_r [0:10];                 // 槽→表 id
    reg [9:0]  qid_r [0:9];
    reg [7:0]  seg_present_r;

    // 流水计数：描述符阶段（capture_r 标 din 有效拍）
    //   wa_r 6 位：须容纳 32（5'd32 截断为 0 曾致地址死停 w0）
    reg [5:0]  wa_r;
    reg [4:0]  cw_r;
    // 缓冲/quant 阶段 3 拍流水：aw=发址计数 cwq=分发计数 vp=有效链
    //   （V1.2：发址 → din 落本地捕获寄存 → sb/qm 按槽位分发；
    //    vp[0]=din 将至 vp[1]=捕获拍 vp[2]=分发拍）
    reg [3:0]  slot_r, aw_r, cwq_r;
    reg [2:0]  vp_r;
    reg        capture_r;
    reg [31:0] base_lo_r, base_hi_r;
    reg [31:0] bufd_r, qtd_r;               // V1.2 表读数据本地捕获
    reg        is_add_r, is_cat_r, is_heads_r;
    reg [15:0] nseg_r;
    reg [9:0]  in0_r, in1_r, out_r;
    reg [7:0]  opcode_r;

    wire [31:0] desc_base = {idx_r, 5'd0};   // idx*32

    integer i;

    assign busy_o = busy_r;

    // 槽字段切片辅助（DEC 后计划用）
    wire [9:0] seg_buf_w [0:7];
    wire [9:0] seg_prof_w [0:7];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GC_SEG
            assign seg_buf_w[g]  = dw_r[16 + 2*g][9:0];
            assign seg_prof_w[g] = dw_r[16 + 2*g][25:16];
        end
    endgenerate
    wire [31:0] seg_len_w [0:7];
    generate
        for (g = 0; g < 8; g = g + 1) begin : GC_SEGL
            assign seg_len_w[g] = dw_r[17 + 2*g];
        end
    endgenerate

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r <= S_IDLE;
            busy_r  <= 1'b0;
            done_o  <= 1'b0;
            app_r   <= 11'd0;
            appq_r  <= 10'd0;
            sb_fetched_o <= 11'd0;
            q_fetched_o  <= 10'd0;
            seg_present_r <= 8'd0;
            b_seg_present_o <= 8'd0;
            desc_addr_o <= 12'd0;
            buf_addr_o  <= 10'd0;
            qt_addr_o   <= 10'd0;
            capture_r   <= 1'b0;
            bufd_r  <= 32'd0;               // V1.2
            qtd_r   <= 32'd0;
            wa_r <= 6'd0; cw_r <= 5'd0;
            slot_r <= 4'd0; aw_r <= 4'd0; cwq_r <= 4'd0; vp_r <= 3'b000;
        end else begin
            done_o <= 1'b0;
            case (state_r)
            S_IDLE: begin
                if (req_i) begin
                    idx_r   <= desc_idx_i;
                    busy_r  <= 1'b1;
                    cw_r    <= 5'd0;
                    capture_r <= 1'b0;
                    sb_fetched_o <= 11'd0;   // 跨描述符清零（防前条
                    q_fetched_o  <= 10'd0;   // 置位掩盖本条漏取）
                    desc_addr_o <= {desc_idx_i, 5'd0};   // 首址本拍发
                    wa_r <= 6'd1;
                    state_r <= S_DESC;
                end
            end
            S_DESC: begin
                // 呈现下一字地址；同时回采上一字
                if (capture_r)
                    dw_r[cw_r] <= desc_din_i;
                if (wa_r < 6'd32) begin
                    desc_addr_o <= desc_base + {6'd0, wa_r};
                    wa_r <= wa_r + 6'd1;
                end else if (capture_r && cw_r == 5'd31) begin
                    dw_r[31] <= desc_din_i;      // 末字回采
                    state_r <= S_DEC;
                end
                capture_r <= 1'b1;
                cw_r <= (capture_r && cw_r < 5'd31) ? cw_r + 5'd1 : cw_r;
            end
            S_DEC: begin
                // 32 字齐 → 解码 + 取包计划（1 拍组合 → 寄存）
                opcode_r  <= dw_r[0][7:0];
                is_add_r  <= (dw_r[0][7:0] == 8'h11);
                is_cat_r  <= (dw_r[0][7:0] == 8'h12);
                is_heads_r<= (dw_r[0][7:0] == 8'h15);
                in0_r  <= dw_r[2][9:0];
                in1_r  <= dw_r[2][19:10];
                out_r  <= dw_r[2][29:20];
                nseg_r <= dw_r[6][15:0];
                seg_present_r <= b_seg_present_calc(1'b0);
                b_seg_present_o <= b_seg_present_calc(1'b0);
                for (i = 0; i < 8; i = i + 1) begin
                    b_seg_buf_o  [10*i +: 10] <= seg_buf_w [i];
                    b_seg_prof_o [10*i +: 10] <= seg_prof_w[i];
                    b_seg_len_o  [32*i +: 32] <= seg_len_w [i];
                end
                b_opcode_o    <= dw_r[0][7:0];
                b_w0_o        <= dw_r[0][15:0];
                b_desc_id_o   <= idx_r;
                b_in0_o       <= dw_r[2][9:0];
                b_in1_o       <= dw_r[2][19:10];
                b_out_o       <= dw_r[2][29:20];
                b_c_o         <= dw_r[3][15:0];
                b_h_o         <= dw_r[3][31:16];
                b_w_o         <= dw_r[4][15:0];
                b_prof0_o     <= dw_r[5][15:0];
                b_prof1_o     <= dw_r[5][31:16];
                b_nseg_o      <= dw_r[6][15:0];
                b_out_bytes_o <= dw_r[14];
                // 槽适用位（present 需待 seg_present_r 下一拍 → 用组合值）
                app_r <= b_app_calc(1'b0);
                appq_r <= b_appq_calc(1'b0);
                for (i = 0; i < 11; i = i + 1)
                    sid_r[i] <= b_sid_calc(i);
                for (i = 0; i < 10; i = i + 1)
                    qid_r[i] <= b_qid_calc(i);
                slot_r <= 4'd0;
                aw_r <= 4'd0; cwq_r <= 4'd0; vp_r <= 3'b000;
                state_r  <= S_BUF;
            end
            S_BUF: begin
                // 3 拍表读流水（V1.2）：发址(aw) → 总线 1 拍 → din 落
                // bufd_r(vp[1]) → 一拍后按槽位/字序分发进 sb(vp[2])。
                // BRAM Q 只驱 bufd_r 32 FF（低扇出，可贴 BRAM）；sb 宽
                // 寄存器的写数据从 bufd_r 出发获整拍预算。
                // id 超界（buf>=128）不取（V1.1，与 quant 门同因：
                // {sid,3'b0} 截 10b 会回绕误取）；不置 fetched → 步 3 报。
                if (app_r[slot_r[3:0]] && (sid_r[slot_r[3:0]] < 10'd128)) begin
                    if (aw_r < 4'd8) begin
                        buf_addr_o <= {sid_r[slot_r[3:0]], 3'd0}
                                    + {6'd0, aw_r[2:0]};
                        aw_r <= aw_r + 4'd1;
                    end
                    vp_r <= {vp_r[1:0], (aw_r < 4'd8)};
                    if (vp_r[1]) begin
                        bufd_r <= buf_din_i;      // V1.2 本地捕获
                    end
                    if (vp_r[2]) begin
                        buf_capture();
                        cwq_r <= cwq_r + 4'd1;
                    end
                    if (vp_r[2] && cwq_r == 4'd7) begin
                        slot_r   <= slot_r + 4'd1;
                        aw_r     <= 4'd0;
                        cwq_r    <= 4'd0;
                        vp_r     <= 3'b000;
                    end
                end else if (slot_r < 4'd10) begin
                    slot_r <= slot_r + 4'd1;
                end else begin
                    slot_r <= 4'd0;
                    aw_r   <= 4'd0;
                    cwq_r  <= 4'd0;
                    vp_r   <= 3'b000;
                    state_r <= S_QT;
                end
            end
            S_QT: begin
                // 3 拍流水同 S_BUF（V1.2：qtd_r 本地捕获 → qm/qs 分发）。
                // id 超界（quant>=256）不取（V1.1）：qid_r 为 10b，
                // {qid,2'b00} 截 10b 地址会回绕（300→176）误取并置
                // fetched，步 7 负例（prof 超界）曾假通过（B1 L14）。
                if (appq_r[slot_r[3:0]] && (qid_r[slot_r[3:0]] < 10'd256)) begin
                    if (aw_r < 4'd4) begin
                        qt_addr_o <= {qid_r[slot_r[3:0]], 2'd0}
                                   + {8'd0, aw_r[1:0]};
                        aw_r <= aw_r + 4'd1;
                    end
                    vp_r <= {vp_r[1:0], (aw_r < 4'd4)};
                    if (vp_r[1]) begin
                        qtd_r <= qt_din_i;       // V1.2 本地捕获
                    end
                    if (vp_r[2]) begin
                        qt_capture();
                        cwq_r <= cwq_r + 4'd1;
                    end
                    if (vp_r[2] && cwq_r == 4'd3) begin
                        slot_r <= slot_r + 4'd1;
                        aw_r   <= 4'd0;
                        cwq_r  <= 4'd0;
                        vp_r   <= 3'b000;
                    end
                end else if (slot_r < 4'd9) begin
                    slot_r <= slot_r + 4'd1;
                end else begin
                    state_r <= S_DONE;
                end
            end
            S_DONE: begin
                done_o <= 1'b1;
                busy_r <= 1'b0;
                state_r <= S_IDLE;
            end
            default: state_r <= S_IDLE;
            endcase
        end
    end

    // ---- 段 present 标志（组合；d 为哑元：10.1c 函数须有输入）----
    function [7:0] b_seg_present_calc;
        input d;
        integer k;
        begin
            b_seg_present_calc = 8'd0;
            for (k = 0; k < 8; k = k + 1)
                if (dw_r[16 + 2*k] != 32'd0 || dw_r[17 + 2*k] != 32'd0)
                    b_seg_present_calc[k] = 1'b1;
        end
    endfunction

    wire [7:0] segp_w = b_seg_present_calc(1'b0);

    // ---- 槽适用位 / 槽 id（组合；供 DEC 寄存）----
    //   注：经局部暂存 + 直接函数调用求值（10.1c 对函数内读 segp_w
    //   wire + 变址写返回值的组合求值出错，曾致 concat 段槽恒漏）
    function [10:0] b_app_calc;
        input d;
        reg is_add_w, is_xf_w, is_heads_w;
        reg [7:0] segp_l;
        reg [10:0] tmp;
        integer k;
        begin
            is_add_w   = (dw_r[0][7:0] == 8'h11);
            is_xf_w    = (dw_r[0][7:0] == 8'h12) || (dw_r[0][7:0] == 8'h15);
            is_heads_w = (dw_r[0][7:0] == 8'h15);
            segp_l     = b_seg_present_calc(1'b0);
            tmp        = 11'd0;
            tmp[0]     = 1'b1;                              // in0
            tmp[1]     = is_add_w;                          // in1
            tmp[2]     = !is_heads_w;                       // out
            for (k = 0; k < 8; k = k + 1)
                tmp[3 + k] = is_xf_w && segp_l[k];          // 段
            b_app_calc = tmp;
        end
    endfunction

    function [9:0] b_sid_calc;
        input integer slot;
        reg is_add_w, is_heads_w;
        begin
            is_add_w   = (dw_r[0][7:0] == 8'h11);
            is_heads_w = (dw_r[0][7:0] == 8'h15);
            case (slot)
                0: b_sid_calc = dw_r[2][9:0];
                1: b_sid_calc = dw_r[2][19:10];
                2: b_sid_calc = is_heads_w ? 10'd0 : dw_r[2][29:20];
                default: b_sid_calc = dw_r[16 + 2*(slot-3)][9:0];
            endcase
        end
    endfunction

    function [9:0] b_appq_calc;
        input d;
        reg is_add_w, is_cat_w;
        reg [7:0] segp_l;
        reg [9:0] tmp;
        integer k;
        begin
            is_add_w = (dw_r[0][7:0] == 8'h11);
            is_cat_w = (dw_r[0][7:0] == 8'h12);
            segp_l   = b_seg_present_calc(1'b0);
            tmp      = 10'd0;
            tmp[0]   = is_add_w;
            tmp[1]   = is_add_w;
            for (k = 0; k < 8; k = k + 1)
                tmp[2 + k] = is_cat_w && segp_l[k]
                             && (dw_r[16 + 2*k][25:16] != 10'd0);
            b_appq_calc = tmp;
        end
    endfunction

    function [9:0] b_qid_calc;
        input integer slot;
        begin
            if (slot == 0)      b_qid_calc = dw_r[5][15:0] & 10'h3FF;
            else if (slot == 1) b_qid_calc = dw_r[5][31:16] & 10'h3FF;
            else                b_qid_calc = dw_r[16 + 2*(slot-2)][25:16];
        end
    endfunction

    // ---- 缓冲槽字分发（S_BUF；cwq_r 指向分发字序号；V1.2 从 bufd_r）----
    task buf_capture;
        integer s;
        begin
            s = slot_r;
            sb_fetched_o[s] <= 1'b1;
            case (cwq_r)
                4'd0: sb_base_o [64*s +: 32] <= bufd_r;
                4'd1: sb_base_o [64*s + 32 +: 32] <= bufd_r;
                4'd2: sb_size_o [32*s +: 32]   <= bufd_r;
                4'd3: sb_stride_o[32*s +: 32]  <= bufd_r;
                4'd4: begin
                    sb_c_o [16*s +: 16] <= bufd_r[15:0];
                    sb_h_o [16*s +: 16] <= bufd_r[31:16];
                end
                4'd5: begin
                    sb_w_o [16*s +: 16]     <= bufd_r[15:0];
                    sb_valid_o[s]           <= bufd_r[24];
                end
                4'd6: sb_prod_o [8*s +: 8]  <= bufd_r[7:0];
                default: ;
            endcase
        end
    endtask

    // ---- quant 槽字分发（S_QT；word 0=M、1=shift；V1.2 从 qtd_r）----
    task qt_capture;
        integer s;
        begin
            s = slot_r;
            q_fetched_o[s] <= 1'b1;
            if (cwq_r == 4'd0) qm_o [32*s +: 32] <= qtd_r;
            if (cwq_r == 4'd1) qs_o [6*s +: 6]   <= qtd_r[5:0];
        end
    endtask

endmodule
