/************************************************************************
 * File Name       : ppu_dma_master.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_dma_master
 * Description     : PPU-F3 shell DMA master（手册 §5.6 v1.1 合同）。
 *                   AXI4 64b 单 ID：读/写独立通道，最大 burst 16 拍、
 *                   地址递增不跨 4 KiB（burst 拆分）、读/写在途各 ≤4
 *                   （可配，默认 4/4；shell 级一次一个请求，burst 级流水）。
 *                   尾字节 WSTRB 由上游组装器供给；WLAST 由本模块按
 *                   burst 计划插入（请求级总拍数 = ceil(len/8) 已知）。
 *
 *   错误语义（§5.6）：任一 RRESP/BRESP 非 OKAY → 记首错 beat 号、
 *   停发新事务、在途受控排空、err 脉冲；引擎侧不产生 done。
 *   超时 = 有在途且 timeout_cfg×1024 周期无 AXI 握手进展 →
 *   E_BIT_TIMEOUT。halted = 错误定格后 64 拍静默（D-F3i：F3 shell 级
 *   停机定义；F6 CSR 集成期重议）。abort：立即停发（非错误）。
 *
 *   请求接口：rd_req/wr_req 各一次一个（ready=!active）；rd_beat 流
 *   带 1 拍 skid；wr_beat 流直通 W 通道。0 长度请求不受理（引擎侧
 *   跳过，shell 合同）。
 * Dependencies    : 无。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : 同拍 AR+RLAST 在途计数并算、arlen+1
 *                                位宽、w 计数多驱动三处修正。
 *   - V1.2 (2026-09-28) by LSL : P2.2 wash 恢复正典守卫——复位后迟至
 *                的散拍 r_last/b_acc（读侧 skid 停摆突发在 wash 复位
 *                释放 rready 后排空尾拍）不得令 ar_out_r/aw_out_r 下溢
 *                或 rq/wq 队列空出队。守卫条件 = 在途计数非零，正常序
 *                必满足（每个 r_last/b_acc 必有对应在途 AR/AW），对板
 *                证序列逐拍等价、零行为差；仅病理窗（复位吞掉在途账
 *                后的对端尾拍）生效。shell 实例（rst 直连）无此窗口，
 *                行为不变。
 *   - V1.3 (2026-09-29) by LSL : 软复位 footgun 消费端钳位（用户指令
 *                "1+2 合并改"案 1）——regfile V1.1 冻结全量擦洗语义下
 *                soft 后 dma_cfg=0 成合法可现态：outst=0 令发射门恒假
 *                （零事务）、timeout=0 关看门狗（tmo_ne0）→ 消费端静默
 *                死等（2026-09-29 板探针 2/3 实证：busy=1/ecode=0/零
 *                Y 写）。钳位：outst 0→最小合法 1；timeout 0→正典默认
 *                100（看门狗常开，tmo_ne0 语义废除——全工程零依赖面）。
 *                合法配置区间（1..4/正数）逐位透传零行为差。
 *                同批补错误保持期读排干（案 2 闭环）：err_r=1 期间 R 拍
 *                照收但丢弃（消费者已 abort），对端尾拍/在途 burst 收完、
 *                ar_out_r 归零 → halt 为静默态，shell wash（ppu_f7_top
 *                V1.7）落地时零在途；否则陈旧拍漏进复位后新流 → 流错位
 *                → 新引擎错 W_ERR 死锁（F7M M3S 首轮实测面）。
 *                同批补错误保持期写排干（案 2 收口，sfh 第 5 轮探针定案）：
 *                err/abort 期补发全零 strobe 拍（AXI 合法 no-op）走完已
 *                接受未写尽的 AW burst——AXI4 无 burst 中止，消费者死后
 *                无人续写则互连留幻影 AW（仅 rst_i 清，wash 不可达），
 *                恢复帧首 burst 被幻影吞走 + 末 AW 的 B 永不到 → aw_out
 *                卡 1 → 看门狗于末进展+timeout×1024 拍触发 → 新引擎错
 *                W_ERR 死锁。BFM V1.3 配套 cfg_zero_strb_ok 豁免窗。
 *   - V1.4 (2026-09-29) by LSL : 排干收口三件（授权轮 run02；单元见证件
 *                2026-09-29_dma_drain_unit_run01 三缺陷独立复现）：
 *                (1) wq 显式占用计数 wq_occ_r（0..4）——2 位 hd/tl 在占位
 *                4 回卷相等，V1.3 排干门 (wq_hd != wq_tl) 把满队误读为空
 *                → 补拍不触发 → 幻影 AW 存活（M3S 第 6 轮排干落定闸红
 *                根因，见证 FULL4）；排干条件改 wq_occ_r != 0，hd/tl 仅作
 *                数组索引。(2) WLAST 稳定性——原 wlast_o = w_fire && ...
 *                使 WVALID 挂起期间 WLAST 随 WREADY 组合翻转，违 AXI
 *                payload 冻结（见证 SINGLE）；改 wvalid_o && 位置匹配，
 *                w_bst_done 单一真源兼供 W 记账/占用归扣。(3) halted 账目
 *                前置——信号静默 64 拍不证互连排空（aw_out/wq_occ 未清
 *                零时静默恰为幻影窗，见证 DELAYED-B）；halted 置位前置
 *                ar_out/aw_out/wq_occ 全零，err_r 粘着与 quiet 语义不变，
 *                健康路径零生效。
 ************************************************************************/

module ppu_dma_master (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        abort_i,            // 立即停发（非错误）
    input  wire [23:0] timeout_cfg_i,      // ×1024 周期
    input  wire [2:0]  rd_outst_cfg_i,     // 1..4
    input  wire [2:0]  wr_outst_cfg_i,
    // ---- 读请求 / 数据流 ----
    input  wire        rd_req_valid_i,
    output wire        rd_req_ready_o,
    input  wire [31:0] rd_addr_i,
    input  wire [23:0] rd_len_i,
    output reg         rd_beat_valid_o,
    input  wire        rd_beat_ready_i,
    output reg  [63:0] rd_beat_data_o,
    output reg         rd_done_o,
    // ---- 写请求 / 数据流 ----
    input  wire        wr_req_valid_i,
    output wire        wr_req_ready_o,
    input  wire [31:0] wr_addr_i,
    input  wire [23:0] wr_len_i,
    input  wire        wr_beat_valid_i,
    output wire        wr_beat_ready_o,
    input  wire [63:0] wr_beat_data_i,
    input  wire [7:0]  wr_beat_strb_i,
    output reg         wr_done_o,
    // ---- 错误 ----
    output reg         err_pulse_o,
    output reg  [3:0]  err_bit_o,
    output reg  [7:0]  err_code_o,
    output reg  [23:0] err_beat_o,
    output reg         halted_o,
    // ---- AXI4 64b ----
    output reg  [31:0] araddr_o,
    output reg  [3:0]  arlen_o,
    output wire [2:0]  arsize_o,
    output wire [1:0]  arburst_o,
    output reg         arvalid_o,
    input  wire        arready_i,
    input  wire [63:0] rdata_i,
    input  wire [1:0]  rresp_i,
    input  wire        rlast_i,
    input  wire        rvalid_i,
    output wire        rready_o,
    output reg  [31:0] awaddr_o,
    output reg  [3:0]  awlen_o,
    output wire [2:0]  awsize_o,
    output wire [1:0]  awburst_o,
    output reg         awvalid_o,
    input  wire        awready_i,
    output wire [63:0] wdata_o,
    output wire [7:0]  wstrb_o,
    output wire        wlast_o,
    output wire        wvalid_o,
    input  wire        wready_i,
    input  wire [1:0]  bresp_i,
    input  wire        bvalid_i,
    output wire        bready_o
);

    localparam [3:0] E_BIT_DMA_RD = 4'd1, E_BIT_DMA_WR = 4'd2,
                     E_BIT_TIMEOUT = 4'd7;

    // ---- 配置钳位（V1.3）：0 值 = CSR 软复位全量擦洗后的合法可现态 ----
    // （regfile V1.1 冻结语义 soft 清 dma_cfg_o，F7 不得改）。outst=0 令
    // 发射门恒假（零事务）、timeout=0 关看门狗 → 消费端静默死等
    // （2026-09-29 板探针 2/3 实证）。消费侧钳位：outst 0→最小合法 1；
    // timeout 0→板/TB 正典默认 100（看门狗常开）。合法区间逐位透传。
    wire [2:0]  rd_outst_eff_w = (rd_outst_cfg_i == 3'd0)  ? 3'd1
                                                             : rd_outst_cfg_i;
    wire [2:0]  wr_outst_eff_w = (wr_outst_cfg_i == 3'd0)  ? 3'd1
                                                             : wr_outst_cfg_i;
    wire [23:0] timeout_eff_w  = (timeout_cfg_i == 24'd0)  ? 24'd100
                                                             : timeout_cfg_i;

    assign arsize_o  = 3'd3;               // 8B
    assign arburst_o = 2'b01;              // INCR
    assign awsize_o  = 3'd3;
    assign awburst_o = 2'b01;
    assign bready_o  = 1'b1;
    assign wr_beat_ready_o = wready_i;

    // ---- 请求级状态 ----
    reg        rd_act_r, wr_act_r;
    reg [31:0] raddr_r, waddr_r;
    reg [23:0] rlen_r, wlen_r;
    reg [23:0] rbeats_r, wbeats_r;         // 总拍数 = ceil(len/8)

    // ---- 读侧 burst 引擎 ----
    reg [31:0] rar_addr_r;                // 下一 burst 首址
    reg [23:0] rar_left_r;                // 未发拍数
    reg [3:0]  ar_out_r;                  // 在途 burst 数（0..4）
    reg [4:0]  rq_q [0:3];                // 在途 burst 拍数队列（16 需 5 位）
    reg [1:0]  rq_hd, rq_tl;
    reg [23:0] r_beat_tot_r;              // 已收拍数
    reg [23:0] r_deliv_r;                 // 已交付拍数
    reg        r_skid_v;
    reg [63:0] r_skid_d;

    // ---- 错误 / 停机（burst 发射闸用到，须先声明）----
    reg        err_r, abort_q;
    reg [23:0] tmo_cnt_r;
    reg [5:0]  quiet_r;

    // 4KiB 边界剩余拍数：4096-addr[11:0] 最大 4096 → 需 13 位
    wire [12:0] r_to4k_c = 13'd4096 - {1'b0, rar_addr_r[11:0]};
    wire [23:0] r_to4k   = {11'd0, r_to4k_c >> 3};
    wire [23:0] r_burst = (rar_left_r < 24'd16) ? rar_left_r :
                          (r_to4k < 24'd16)     ? r_to4k   : 24'd16;
    wire [4:0]  r_bst5 = r_burst[4:0];
    wire ar_can = rd_act_r && (rar_left_r != 24'd0) &&
                  (ar_out_r < {1'b0, rd_outst_eff_w}) && !err_r && !abort_q;

    // ---- 写侧 burst 引擎 ----
    reg [31:0] war_addr_r;
    reg [23:0] war_left_r;
    reg [3:0]  aw_out_r;
    reg [4:0]  wq_q [0:3];
    reg [1:0]  wq_hd, wq_tl;
    reg [2:0]  wq_occ_r;                 // 占用 0..4（V1.4 显式计数——2 位
                                         // hd/tl 占位 4 回卷相等，hd==tl 不
                                         // 可再作空判据，仅作数组索引）
    reg [23:0] w_sent_r;                  // 已发 W 拍数
    reg [4:0]  w_in_bst_r;                // 头 burst 内拍计数
    reg [23:0] aw_cnt_r, b_cnt_r;         // 已发/已收 burst 数
    wire [12:0] w_to4k_c = 13'd4096 - {1'b0, war_addr_r[11:0]};
    wire [23:0] w_to4k   = {11'd0, w_to4k_c >> 3};
    wire [23:0] w_burst = (war_left_r < 24'd16) ? war_left_r :
                          (w_to4k < 24'd16)     ? w_to4k   : 24'd16;
    wire [4:0]  w_bst5 = w_burst[4:0];
    wire aw_can = wr_act_r && (war_left_r != 24'd0) &&
                  (aw_out_r < {1'b0, wr_outst_eff_w}) && !err_r && !abort_q;

    // ---- W 源选择（V1.3 错误保持期写排干）----
    // err/abort 保持期消费者已死：已接受 AW 的 burst 若无人续写，其 W 拍
    // 永缺 → 互连 AW/B 账目悬空（AXI4 无 burst 中止）→ wash 只复位本模块
    // 而互连侧幻影 AW 存活（仅 rst_i 清）→ 恢复帧首 burst 被幻影吞走
    // （数据错位落他人地址）+ 末 AW 的 B 永不到 → aw_out 卡 1 → 看门狗
    // 于末进展+timeout×1024 拍触发 → 新引擎错 → W_ERR 死锁（sfh 第 5 轮
    // 探针逐拍实证）。补发全零 strobe 拍（AXI 合法 no-op，互连/内存零
    // 副作用）把 wq 在途 burst 走完 → B 收讫、账目归零，wash 落地为
    // 静默态。健康路径 err_r=abort_q=0 零生效；生产者拍优先（err 竞态
    // 窗内残余真数据照常流动）。
    wire w_drain_now = (err_r || abort_q) && !wr_beat_valid_i &&
                       (wq_occ_r != 3'd0);
    assign wvalid_o = wr_beat_valid_i || w_drain_now;
    assign wdata_o  = w_drain_now ? 64'd0 : wr_beat_data_i;
    assign wstrb_o  = w_drain_now ? 8'h00 : wr_beat_strb_i;

    wire w_fire = wvalid_o && wready_i;

    // ---- 事件（供同拍并算）----
    wire ar_acc = arvalid_o && arready_i;
    wire aw_acc = awvalid_o && awready_i;
    wire r_fire = rvalid_i && rready_o;
    wire r_last = r_fire && rlast_i;
    wire b_acc  = bvalid_i && bready_o;
    wire out_fire = rd_beat_valid_o && rd_beat_ready_i;
    wire any_pend = (ar_out_r != 4'd0) || (aw_out_r != 4'd0);
    wire axi_prog = ar_acc || aw_acc || r_fire || b_acc || w_fire;

    assign rd_req_ready_o = !rd_act_r && !err_r;
    assign wr_req_ready_o = !wr_act_r && !err_r;
    assign rready_o = !r_skid_v;

    // WLAST（V1.4 稳定性收口）：只标示"当前在驱动的拍是否为该 burst 末
    // 拍"，不得依赖 WREADY——WVALID 挂起而 WREADY 未至时 wdata/wstrb/
    // wlast 须整体冻结（AXI VALID/READY payload 稳定性；见证 SINGLE：
    // 旧式 w_fire && ... 在挂起拍 WLAST 组合落 0）。wq_occ 守卫防读空槽
    // （旧式同位置误配陈旧槽可产伪 WLAST）。w_bst_done 为单一真源，兼供
    // W 记账与 wq_occ_r 归扣——两处判据不可能分叉。
    wire w_bst_end  = (wq_occ_r != 3'd0) &&
                      (w_in_bst_r + 5'd1 == wq_q[wq_hd]);
    wire w_bst_done = w_fire && w_bst_end;
    assign wlast_o  = wvalid_o && w_bst_end;

    // 请求拍数计算函数
    function [23:0] ceil8;
        input [23:0] l;
        begin
            ceil8 = (l == 24'd0) ? 24'd0 :
                    (l[23:3] + (|l[2:0] ? 24'd1 : 24'd0));
        end
    endfunction

    integer k;

    always @(posedge clk_i) begin
        if (rst_i) begin
            rd_act_r <= 1'b0; wr_act_r <= 1'b0;
            raddr_r <= 32'd0; waddr_r <= 32'd0;
            rlen_r <= 24'd0;  wlen_r <= 24'd0;
            rbeats_r <= 24'd0; wbeats_r <= 24'd0;
            rar_addr_r <= 32'd0; rar_left_r <= 24'd0;
            war_addr_r <= 32'd0; war_left_r <= 24'd0;
            ar_out_r <= 4'd0; aw_out_r <= 4'd0;
            rq_hd <= 2'd0; rq_tl <= 2'd0; wq_hd <= 2'd0; wq_tl <= 2'd0;
            wq_occ_r <= 3'd0;
            for (k = 0; k < 4; k = k + 1) begin
                rq_q[k] <= 4'd0; wq_q[k] <= 4'd0;
            end
            r_beat_tot_r <= 24'd0; r_deliv_r <= 24'd0;
            rd_beat_valid_o <= 1'b0; rd_beat_data_o <= 64'd0;
            r_skid_v <= 1'b0; r_skid_d <= 64'd0;
            w_sent_r <= 24'd0; w_in_bst_r <= 4'd0;
            aw_cnt_r <= 24'd0; b_cnt_r <= 24'd0;
            arvalid_o <= 1'b0; araddr_o <= 32'd0; arlen_o <= 4'd0;
            awvalid_o <= 1'b0; awaddr_o <= 32'd0; awlen_o <= 4'd0;
            rd_done_o <= 1'b0; wr_done_o <= 1'b0;
            err_r <= 1'b0; abort_q <= 1'b0;
            err_pulse_o <= 1'b0; err_bit_o <= 4'd0; err_code_o <= 8'd0;
            err_beat_o <= 24'd0;
            halted_o <= 1'b0; quiet_r <= 6'd0;
            tmo_cnt_r <= 24'd0;
        end else begin
            rd_done_o  <= 1'b0;
            wr_done_o  <= 1'b0;
            err_pulse_o <= 1'b0;
            abort_q <= abort_i | abort_q;

            // ---- 读请求接收 ----
            if (rd_req_valid_i && rd_req_ready_o) begin
                rd_act_r  <= 1'b1;
                raddr_r   <= rd_addr_i;
                rlen_r    <= rd_len_i;
                rbeats_r  <= ceil8(rd_len_i);
                rar_addr_r<= rd_addr_i;
                rar_left_r<= ceil8(rd_len_i);
                r_beat_tot_r <= 24'd0;
                r_deliv_r <= 24'd0;
            end

            // ---- AR 发射 ----
            if (ar_acc) begin
                arvalid_o <= 1'b0;
                rq_q[rq_tl] <= r_bst5;
                rq_tl <= rq_tl + 2'd1;
                rar_addr_r <= rar_addr_r + ({27'd0, r_bst5} << 3);
                rar_left_r <= rar_left_r - {19'd0, r_bst5};
            end else if (ar_can && !arvalid_o) begin
                arvalid_o <= 1'b1;
                araddr_o  <= rar_addr_r;
                arlen_o   <= r_bst5[3:0] - 4'd1;
            end

            // ---- 在途计数（同拍并算；V1.2 守卫：复位后散拍 r_last 不下溢/空出队）----
            ar_out_r <= ar_out_r + (ar_acc ? 4'd1 : 4'd0)
                                - ((r_last && ar_out_r != 4'd0) ? 4'd1
                                                               : 4'd0);
            if (r_last && ar_out_r != 4'd0)
                rq_hd <= rq_hd + 2'd1;

            // ---- R 收拍 → 消费者（skid）----
            // V1.3 错误保持期读排干 v2：消费者已死（loader abort），腾空
            // skid 保 rready 流动——v1 仅丢新到拍，skid 满时 rready=0，
            // 尾拍冻在对端永不可达（M3S 第 3 轮实测同面同时刻复现）。
            // err_r=0 期零生效（唯一置位径在下方 r_fire 的 !err_r 分支，
            // 互斥）；引擎级错（如 B8 量化号）不设 err_r，基线门不受扰。
            if (err_r && r_skid_v) r_skid_v <= 1'b0;
            if (out_fire) begin
                r_deliv_r <= r_deliv_r + 24'd1;
                if (r_skid_v) begin
                    rd_beat_data_o <= r_skid_d;
                    r_skid_v <= 1'b0;
                end else begin
                    rd_beat_valid_o <= 1'b0;
                end
                if (r_deliv_r + 24'd1 == rbeats_r)
                    rd_done_o <= 1'b1;
            end
            if (r_fire) begin
                if (err_r) begin
                    // V1.3 错误保持期读排干：消费者已 abort，数据丢弃不进
                    // skid/beat 流水；保持 rready 流动令对端尾拍/在途 burst
                    // 收完（r_last 维持 ar_out_r 归零）→ halt 落地为静默态，
                    // wash/软复位清 err_r 时零在途（M3S 面闭环：否则陈旧拍
                    // 漏进复位后新流 → 流错位 → 新引擎错 W_ERR 死锁）。
                end else if (!out_fire && rd_beat_valid_o) begin
                    r_skid_d <= rdata_i;
                    r_skid_v <= 1'b1;
                end else begin
                    rd_beat_data_o <= rdata_i;
                    rd_beat_valid_o <= 1'b1;
                end
                r_beat_tot_r <= r_beat_tot_r + 24'd1;
                if (rresp_i != 2'b00 && !err_r) begin
                    err_r <= 1'b1;
                    err_pulse_o <= 1'b1;
                    err_bit_o <= E_BIT_DMA_RD;
                    err_code_o <= 8'd0;
                    err_beat_o <= r_beat_tot_r;
                end
            end
            if (rd_done_o)
                rd_act_r <= 1'b0;

            // ---- 写请求接收 ----
            if (wr_req_valid_i && wr_req_ready_o) begin
                wr_act_r  <= 1'b1;
                waddr_r   <= wr_addr_i;
                wlen_r    <= wr_len_i;
                wbeats_r  <= ceil8(wr_len_i);
                war_addr_r<= wr_addr_i;
                war_left_r<= ceil8(wr_len_i);
                w_sent_r  <= 24'd0;
                w_in_bst_r<= 4'd0;
                aw_cnt_r  <= 24'd0;
                b_cnt_r   <= 24'd0;
            end

            // ---- AW 发射 ----
            if (aw_acc) begin
                awvalid_o <= 1'b0;
                aw_cnt_r  <= aw_cnt_r + 24'd1;
                wq_q[wq_tl] <= w_bst5;
                wq_tl <= wq_tl + 2'd1;
                war_addr_r <= war_addr_r + ({27'd0, w_bst5} << 3);
                war_left_r <= war_left_r - {19'd0, w_bst5};
            end else if (aw_can && !awvalid_o) begin
                awvalid_o <= 1'b1;
                awaddr_o  <= war_addr_r;
                awlen_o   <= w_bst5[3:0] - 4'd1;
            end

            // ---- W 转发计数（WLAST 组合插入；w_bst_done 单一真源）----
            if (w_fire) begin
                w_sent_r <= w_sent_r + 24'd1;
                if (w_bst_done) begin
                    w_in_bst_r <= 4'd0;
                    wq_hd <= wq_hd + 2'd1;
                end else begin
                    w_in_bst_r <= w_in_bst_r + 4'd1;
                end
            end

            // ---- 写队列占用（V1.4）----
            // 单表达式并算同拍 AW 收讫(+1)/WLAST 完成(-1)——同拍互抵，
            // 不得拆两分支（非阻塞互覆）。边界：aw_acc 需发射时
            // aw_out≤3 → 占用≤4 不上溢；w_bst_done 蕴含占用≠0
            // （w_bst_end 守卫）→ 不下溢。
            wq_occ_r <= wq_occ_r + (aw_acc ? 3'd1 : 3'd0)
                                 - (w_bst_done ? 3'd1 : 3'd0);

            // ---- B 收妥（V1.2 守卫：复位后散拍 b_acc 不下溢）----
            aw_out_r <= aw_out_r + (aw_acc ? 4'd1 : 4'd0)
                                - ((b_acc && aw_out_r != 4'd0) ? 4'd1
                                                               : 4'd0);
            if (b_acc) begin
                b_cnt_r  <= b_cnt_r + 24'd1;
                if (bresp_i != 2'b00 && !err_r) begin
                    err_r <= 1'b1;
                    err_pulse_o <= 1'b1;
                    err_bit_o <= E_BIT_DMA_WR;
                    err_code_o <= 8'd0;
                    err_beat_o <= b_cnt_r;
                end
                if (b_cnt_r + 24'd1 == aw_cnt_r && war_left_r == 24'd0)
                    wr_done_o <= 1'b1;
            end
            if (wr_done_o)
                wr_act_r <= 1'b0;

            // ---- 超时看门狗（有在途且无进展）----
            if (any_pend) begin
                if (axi_prog)
                    tmo_cnt_r <= 24'd0;
                else
                    tmo_cnt_r <= tmo_cnt_r + 24'd1;
                // V1.3：看门狗常开（timeout 钳位默认 100，tmo_ne0 废除）
                if (!err_r &&
                    (tmo_cnt_r >= (timeout_eff_w << 10))) begin
                    err_r <= 1'b1;
                    err_pulse_o <= 1'b1;
                    err_bit_o <= E_BIT_TIMEOUT;
                    err_code_o <= 8'd0;
                    err_beat_o <= tmo_cnt_r;
                end
            end else begin
                tmo_cnt_r <= 24'd0;
            end

            // ---- 错误定格 → 停机（64 拍静默；V1.4 账目清零前置）----
            // 仅信号静默不足为证：AR/AW 在途、wq 占位未清零时静默恰为
            // 幻影窗口（halted=1 不得作为"互连已排空"证据，见证
            // DELAYED-B：W 侧走完而 B 悬置时旧码照样置位）；账目全零后
            // 64 拍静默方置位。err_r 粘着/quiet 计数语义不变，健康路径
            // err_r 恒 0 零生效。
            if (err_r && !halted_o) begin
                if (arvalid_o || awvalid_o || rvalid_i || bvalid_i ||
                    wvalid_o || (ar_out_r != 4'd0) ||
                    (aw_out_r != 4'd0) || (wq_occ_r != 3'd0))
                    quiet_r <= 6'd0;
                else if (quiet_r == 6'd63)
                    halted_o <= 1'b1;
                else
                    quiet_r <= quiet_r + 6'd1;
            end
        end
    end

endmodule
