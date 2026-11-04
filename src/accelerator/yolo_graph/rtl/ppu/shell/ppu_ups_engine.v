/************************************************************************
 * File Name       : ppu_ups_engine.v
 * Developer       : LSL
 * Date            : 2026-09-22
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_ups_engine
 * Description     : PPU-F5 Upsample2 引擎（单描述符）——例化复用
 *                   yolo_ppu_upsample2.sv（P2b 版零修改）+
 *                   ppu_byte_reader + ppu_byte_store_assembler，
 *                   经 ppu_dma_master 完成 DDR 搬移。
 *
 *   机制（replan §PPU-F5-1"散写地址+assembler"的落法）：核输出为
 *   散 (addr,data) 字节流（行对内偶/奇行 1:1 交错，ph 序
 *   E0,E1,O0,O1,…），而行对两行在 out 缓冲内相邻——按行对重排后
 *   整个输出恰为 [out_base, out_base+4CHW) 的严格顺序流。故写通路
 *   复用 concat 同构：一次 wr_req 覆盖全区 + assembler 8B 聚合；
 *   AXI 侧无散写。
 *
 *   重排器（本模块核心）：
 *     推入侧（每拍无条件收核输出）流相位分类（V1.3 起；与 V1.0-V1.2
 *     的地址窗口分类逐字节等价，证明见 Revision V1.3）：核每收 1 输入
 *     字节按 E0,E1,O0,O1 四拍发射且地址序严格随相位（偶行对 ph0/1、
 *     奇行对 ph2/3），故分类 = 吸收拍计数 mod 4 的相位位[1]。WE 组合
 *     锥只含 absorb_w 与一个寄存器位，不含地址加法/比较——v20 routed
 *     残量 32 条 rowlen_r_reg 到 od_mem_reg_*（RAMx）WE 脚的路径
 *     （ll=14、dpd≈9.3 ns，锥=32b 加法+双比较器）的成因即旧分类器。
 *     发射侧（对 assembler 握手，仅 S_RUN 态）：偶行先（地址序），
 *       本对偶行发尽（e_emi==rowlen）才发奇行；奇行发尽即一对完成、
 *       计数归零。（进入 S_FLUSH 的条件 y_cnt==outlen 已含发射尽，
 *       无跨态尾拍——与 engine_mux V1.3 的教训条件不同、无此暴露。）
 *     流闸（核输入侧，F3 V1.1 纪律同源）：核输出无 ready 口（每拍必
 *       收），闸门设在 reader→核入口 —— 偶 FIFO 空位≥2 且奇 FIFO
 *       空位≥2 才呈现输入。**in_valid 与 out_ready 必须同闸共压**
 *       （run01 修复）：核无输入反压语义（ph0 见 in_valid 即收，
 *       in_ready_o 仅提示），只压 out_ready 会让核在闸关期"偷吃"
 *       reader 的保持字节（错字重复×4 + 发射数先于消费数到顶 + 后继
 *       任务读突发悬挂死锁——desc49 实测）。推入序 E,E,O,O（相位
 *       0..3 地址序）+ ph0 每 4 拍一格：闸检见的电平至多缺 1 个在途
 *       奇推入，≤6/≤8190 预留恰覆盖最坏 8/8192 满位，无溢出。输入
 *       恰 1 字节/4 拍，放行间隔≥4 拍 > 推入窗口；发射侧以 1 字节/拍
 *       排空，随 assembler/DMA 交付回落 → 无死锁。
 *
 *   DMA：先 wr_req(out_base, 4CHW)（concat 同序：写请求先行，拍随
 *   流到），再 rd_req(in0_base, CHW)；reader 供核输入。完成条件 =
 *   y_cnt==4CHW && 核 idle → 一次 asm_flush → asm_idle && 写妥
 *   （wr_done 语义，§4.2）。退化 C·H·W=0：无搬移直通 done（VIEW
 *   同构）。dma_err/abort：任一推进态弃权回 IDLE 无 done（shell 侧
 *   粘错/abort 落定，与 engine_mux 同构）。
 *
 *   容量界（壳层）：2·W ≤ 8192（奇 FIFO 深；正典 W≤320）、
 *   C·H·W ≤ 2^24（rd_len 口宽；buffer 表上限 409600B 远小）。
 *   超界描述符表现为流闸永关（仿真看门狗可见），非静默错数据。
 *   奇 FIFO 为一写一读简单双口结构：读仅非空、写仅非满，同址同拍
 *   读写被指针纪律结构性排除（用户 TDP BRAM 规则）。异步读 reg 阵
 *   列（仿真/综合可映 LUTRAM；F7 综合期可改同步读 BRAM，合同不变）。
 * Dependencies    : yolo_ppu_upsample2.sv / ppu_byte_reader.v /
 *                   ppu_byte_store_assembler.v。
 * Revision History:
 *   - V1.0 (2026-09-22) by LSL : F5 run01 初版（单描述符门）。
 *   - V1.1 (2026-09-22) by LSL : 核输入呈现门修复——in_valid 与
 *       out_ready 同闸共压（V1.0 只压 ready，核在闸关期偷吃 reader
 *       保持字节：desc49 wr 错字重复、rd 流截短 957 拍、desc58 读
 *       突发悬挂死锁，run01 实测三症同根）。
 *   - V1.2 (2026-09-24) by LSL : CHW 元数据直入（用户裁定条件性 A 指示③
 *       推广）：chw_i=desc w14/out_bytes（=输出字节数 4·CHW_in，不变量
 *       全语料 35/35 验证）启动拍直锁 chw_r(=w14>>2)/outlen_r(=w14) 与
 *       退化判据，删 c_i*h_i*w_i 两乘；核/行算术仍用 c/h/w 形状口，
 *       语义零变化。
 *   - V1.3 (2026-09-25) by LSL : P1.2 u_ups WE 锥结构整改（
 *       POST_V19_SYSTEM_PLAN §P1.2 候选"局部窗口分类"落法）：推入侧
 *       分类改流相位计数 bph_r（mod 4），删 pair_hi_r 与 ev/od/np 三
 *       分类比较锥（32b 加法+双比较器整体移出 od_mem/ev_mem WE 锥）。
 *       等价证明（全部 C,H,W≥1，无正典形状假设；L=rowlen=2W，
 *       x=组内输入序 0..W-1，p=行对序）：核第 g 组四拍地址
 *         ph0: 2p·L+2x      ph1: 2p·L+2x+1
 *         ph2: (2p+1)·L+2x   ph3: (2p+1)·L+2x+1
 *       旧窗口界 pair_hi=(2p+1)·L 下：ph0/1 → addr<pair_hi ⟺ 2x+{0,1}
 *       <2W（x≤W-1 恒真）→ 偶；ph2/3 → pair_hi≤addr<pair_hi+L ⟺ 2x+{0,1}
 *       <2W（恒真）→ 奇；x 回绕后首拍 addr=(2p+2)·L=pair_hi+L → np 入
 *       偶（旧逻辑同拍前进窗口，窗口界不再被读取）。故按相位位 bph[1]
 *       分类与按地址窗口分类逐拍同类。推入同拍同类 ⟹ FIFO 水位轨迹/
 *       流闸判决/发射序/DMA 拍序零变化；无新增寄存级 ⟹ lat 零漂移
 *       （F7B 台账应精确保持 v20 值）。
 ************************************************************************/

module ppu_ups_engine (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,           // loader pass 后启动（脉冲）
    input  wire [31:0] in0_base_i,        // 输入缓冲基址（槽 0 低字）
    input  wire [31:0] out_base_i,        // 输出缓冲基址（槽 2 低字）
    input  wire [15:0] c_i, h_i, w_i,     // 输入形状（in0 槽 dims——表权威；
                                          // 正典 desc c/h/w 为输出形状 2H/2W）
    input  wire [31:0] chw_i,             // w14 元数据（=输出字节数 4·CHW_in；
                                          //   不变量已全语料验证 2026-09-24：
                                          //   35/35 w14==4×槽0 c·h·w。核/行
                                          //   算术仍用 c/h/w，仅删启动乘）
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
    localparam integer EV_DEPTH  = 8;             // 偶行暂存
    localparam integer ODD_DEPTH = 8192;          // 奇行缓冲（=2W 容量界）

    reg [3:0]  state_r;
    reg [31:0] in0_base_r, out_base_r;
    reg [15:0] c_r, h_r, w_r;
    reg [31:0] chw_r, outlen_r;                   // C·H·W / 4CHW
    reg [31:0] rowlen_r;                          // 2W（发射侧比较用）
    reg [1:0]  bph_r;                             // 推入侧流相位 0..3（V1.3）
    reg [31:0] y_cnt_r;                           // 已入 assembler 字节
    reg        wr_done_all_r;

    // ---- 重排器存储/指针 ----
    reg [7:0]  ev_mem [0:EV_DEPTH-1];
    reg [2:0]  ev_wp_r, ev_rp_r;
    reg [3:0]  ev_lvl_r;                          // 0..8
    reg [7:0]  od_mem [0:ODD_DEPTH-1];
    reg [12:0] od_wp_r, od_rp_r;
    reg [13:0] od_lvl_r;                          // 0..8192
    reg [15:0] e_emi_r, o_emi_r;                  // 本对已发射偶/奇字节数

    // ---- 例化连线（reader / 核 / assembler）----
    reg         rdr_start_r, core_start_r, asm_start_r, asm_flush_r;
    wire        rdr_out_v_w;
    wire [7:0]  rdr_out_d_w;
    wire        core_in_rdy_w, core_busy_w;
    wire        core_out_v_w;
    wire [7:0]  core_out_d_w;
    wire [31:0] core_out_a_w;   //（V1.3 后无功能负载：分类已改流相位。
                                //  保留连线作等价性出处/调试可见，综合自剪）
    wire        asm_rdy_w, asm_idle_w;

    // 流闸：偶/奇 FIFO 各预留空位才呈现输入（见文件头；in_valid 同闸）
    localparam [13:0] ODD_GATE_MAX = 14'd8190;
    wire       gate_w = (ev_lvl_r <= 4'd6) && (od_lvl_r <= ODD_GATE_MAX);
    wire       core_in_v_w = rdr_out_v_w && gate_w;   // 核 ph0 采样前闸

    // ---- 重排器：推入侧（流相位分类，V1.3）----
    //  吸收拍 = 核输出有效（仅 S_RUN；S_FLUSH 进入条件已含 !core_busy）
    //  分类 = 吸收拍计数 mod 4 的相位位[1]（与旧地址窗口分类逐拍同类，
    //  等价证明见文件头 Revision V1.3）——WE 锥不含地址加法/比较。
    wire absorb_w = core_out_v_w && (state_r == S_RUN);
    wire push_ev_w = absorb_w && (!bph_r[1]);   // E0/E1 → 偶行（含跨对首拍）
    wire push_od_w = absorb_w && bph_r[1];       // O0/O1 → 奇行

    // ---- 重排器：发射侧（偶先行、奇后发，按对推进；仅 S_RUN）----
    wire       emit_en_w  = (state_r == S_RUN);
    wire       ev_avail_w = (ev_lvl_r != 4'd0);
    wire       od_avail_w = (od_lvl_r != 14'd0);
    wire       emit_ev_w  = emit_en_w &&
                            (e_emi_r != rowlen_r[15:0]) && ev_avail_w;
    wire       emit_od_w  = emit_en_w &&
                            (e_emi_r == rowlen_r[15:0]) && od_avail_w;
    wire       emit_v_w   = emit_ev_w || emit_od_w;
    wire [7:0] emit_d_w   = emit_ev_w ? ev_mem[ev_rp_r] : od_mem[od_rp_r];
    wire       emit_fire_w = emit_v_w && asm_rdy_w;
    wire       pop_ev_w   = emit_fire_w && emit_ev_w;
    wire       pop_od_w   = emit_fire_w && emit_od_w;

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

    yolo_ppu_upsample2 u_core (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(core_start_r),
        .c_i(c_r), .h_i(h_r), .w_i(w_r),
        .in_ready_o(core_in_rdy_w),
        .in_valid_i(core_in_v_w),
        .in_data_i(rdr_out_d_w),
        .out_valid_o(core_out_v_w), .out_data_o(core_out_d_w),
        .out_addr_o(core_out_a_w), .out_last_o(),
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
            chw_r <= 32'd0; outlen_r <= 32'd0; rowlen_r <= 32'd0;
            bph_r <= 2'd0;
            y_cnt_r <= 32'd0;
            wr_done_all_r <= 1'b0;
            ev_wp_r <= 3'd0; ev_rp_r <= 3'd0; ev_lvl_r <= 4'd0;
            od_wp_r <= 13'd0; od_rp_r <= 13'd0; od_lvl_r <= 14'd0;
            e_emi_r <= 16'd0; o_emi_r <= 16'd0;
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

            // ---- 重排器推入（仅 S_RUN 吸收；指针纪律见文件头）----
            if (push_ev_w) begin
                ev_mem[ev_wp_r] <= core_out_d_w;
                ev_wp_r <= ev_wp_r + 3'd1;
            end
            if (push_od_w) begin
                od_mem[od_wp_r] <= core_out_d_w;
                od_wp_r <= od_wp_r + 13'd1;
            end
            if (absorb_w)
                bph_r <= bph_r + 2'd1;                // 流相位推进（mod 4）
            ev_lvl_r <= ev_lvl_r + (push_ev_w ? 4'd1 : 4'd0)
                                 - (pop_ev_w ? 4'd1 : 4'd0);
            od_lvl_r <= od_lvl_r + (push_od_w ? 14'd1 : 14'd0)
                                 - (pop_od_w ? 14'd1 : 14'd0);

            // ---- 发射（仅 S_RUN；进入 S_FLUSH 条件已含发射尽）----
            if (emit_fire_w) begin
                y_cnt_r <= y_cnt_r + 32'd1;
                if (emit_ev_w) begin
                    e_emi_r <= e_emi_r + 16'd1;
                end else begin
                    if (o_emi_r + 16'd1 == rowlen_r[15:0]) begin
                        e_emi_r <= 16'd0;             // 一对完成
                        o_emi_r <= 16'd0;
                    end else begin
                        o_emi_r <= o_emi_r + 16'd1;
                    end
                end
            end
            if (pop_ev_w)
                ev_rp_r <= ev_rp_r + 3'd1;
            if (pop_od_w)
                od_rp_r <= od_rp_r + 13'd1;

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
                    chw_r    <= chw_i >> 2;           // w14=4·CHW_in（V1.2：
                                                      // 删两乘；输入长=w14>>2）
                    outlen_r <= chw_i;                // 输出长 = w14 直入
                    rowlen_r <= {16'd0, w_i} << 1;
                    bph_r    <= 2'd0;                 // 流相位自 E0 起
                    y_cnt_r  <= 32'd0;
                    e_emi_r  <= 16'd0;
                    o_emi_r  <= 16'd0;
                    ev_wp_r  <= 3'd0; ev_rp_r  <= 3'd0; ev_lvl_r <= 4'd0;
                    od_wp_r  <= 13'd0; od_rp_r <= 13'd0; od_lvl_r <= 14'd0;
                    wr_done_all_r <= 1'b0;
                    if (chw_i == 32'd0)
                        state_r <= S_VDONE;           // 退化：无搬移
                    else
                        state_r <= S_WREQ;
                end
            end
            // ---- 总写请求（concat 同构：写先行，拍随流到）----
            S_WREQ: begin
                if (!wr_req_valid_o) begin
                    wr_req_valid_o <= 1'b1;
                    wr_addr_o <= out_base_r;
                    wr_len_o  <= outlen_r[23:0];
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
            // ---- 流推进：发射尽 + 核 idle → 一次冲刷 ----
            S_RUN: begin
                if ((y_cnt_r == outlen_r) && !core_busy_w) begin
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
