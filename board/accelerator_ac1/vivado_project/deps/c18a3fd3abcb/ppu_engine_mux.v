/************************************************************************
 * File Name       : ppu_engine_mux.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_engine_mux
 * Description     : PPU-F3/F5 引擎驱动（VIEW + XFER=CONCAT/HEADS +
 *                   UPSAMPLE2 + MAXPOOL5）。例化复用 yolo_ppu_xfer.sv
 *                   （P2e 版零修改）+ ppu_byte_reader + ppu_byte_
 *                   store_assembler + ppu_ups_engine + ppu_mp5_engine
 *                   （F5，内例 P2b/P2c 核零修改），经 ppu_dma_master
 *                   完成 DDR 搬移。
 *
 *   数据通路：DMA rd 拍 → reader（字节流）→ xfer（段 profile 逐段
 *   可选 requant；恒等段走硬件捷径）→ assembler（8B 拍 + 尾 strb）
 *   → DMA wr。
 *   CONCAT：一次 wr_req 覆盖 [out_base, out_base+out_bytes)（段间无
 *   隙，末尾一次 flush）；DMA rd 按段逐请求。
 *   HEADS：恒等 6 段，目标 = head_base + §8 固定偏移，逐段
 *   rd/wr/flush（尾段 700B → 尾拍 strb=0x0F）。
 *   VIEW：零搬移，立即 done（手册 §4.2）。
 *   0 字节段：不进 xfer 段表（核按字节计数推进，0 长会卡死——
 *   D-F3j），不发起 DMA；Σ段长不变。
 *
 *   y 侧流闸（关键，V1.1）：xfer 的 y_valid_o 无 ready 口（每拍必
 *   收），而组装器在 cnt==8 且出级拍未交付（W 通道反压）时拒收
 *   —— 未准入字节将永久丢失（run01 实测丢 783B → W 流短拍 →
 *   wr_done 悬死）。闸门在 reader→xfer 入口按"承诺量"放行：
 *   组装器积压(acc+出级) + xfer 在途(push−y脉冲) ≤ 8。放行拍承
 *   诺上界 9 < 16，拒收态不可达 → 零丢失；承诺量随出级交付/在
 *   途排空自行回落 → 无死锁（纯积压阈值闸在 DMA 读断流时会永卡
 *   acc=6/7，故必须计入在途）。
 * Dependencies    : yolo_ppu_xfer.sv / ppu_byte_reader.v /
 *                   ppu_byte_store_assembler.v。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : 流闸改承诺量准入（修复 y 丢字节）。
 *   - V1.2 (2026-09-21) by LSL : 流闸补 xfer in_valid 侧限定 —— 闸门
 *       原先只接 reader.out_ready，xfer 仍在闸关拍照收（同一字节重复
 *       入流，实测 reader 17B/200k 拍 vs xfer 吞 199k 字节）。闸现在
 *       同时限定 in_valid 与 out_ready，两侧同一拍同一条件原子转移。
 *   - V1.3 (2026-09-21) by LSL : y_cnt 改全程计数 —— xfer 3 级流水在
 *       段界/收尾后仍排水 ~3 拍，仅 S_STREAM 内计数漏尾致 S_FINAL
 *       永等 y_cnt==out_bytes（实测 307197/307200 悬死）。
 *   - V1.4 (2026-09-21) by LSL : heads S_FLUSHW 去 !xf_busy —— xfer
 *       段间连续运行永 busy，曾致段 0 冲刷后悬死（desc103 实测）。
 *   - V1.5 (2026-09-21) by LSL : heads 段末写妥移 S_FLUSHW —— S_STREAM
 *       原等 seg_wr_done 对尾段（len%8≠0，末拍=冲刷产物）环死锁
 *       （desc103 段5 700B 实测：W 87/88 悬死→DMA 超时弃权）。现
 *       S_STREAM 只等 y 流尽+读尽即冲刷，S_FLUSHW 等 asm_idle&&写妥。
 *   - V1.6 (2026-09-22) by LSL : F5 —— 增 UPSAMPLE2（0x14）派发与
 *       ppu_ups_engine 例化；DMA 请求/拍输出口改 wire 由 ups_act_r
 *       选择（xfer 通路寄存器改内部 xf_* 网，行为不变；一次任务仅
 *       一引擎在跑）。VIEW/CONCAT/HEADS 路径零语义变化。
 *   - V1.7 (2026-09-22) by LSL : F5-M —— 增 MAXPOOL5（0x13）派发与
 *       ppu_mp5_engine 例化；DMA 口选择扩为 ups/mp5/xfer 三路
 *       （mp5_act_r，一次任务仅一引擎在跑）。既有路径零语义变化；
 *       up_c/h/w_i 形状口复用于 maxpool5（同一槽 0 dims 接线）。
 *   - V1.8 (2026-09-22) by LSL : F5-A —— 增 ADD（0x11）派发与
 *       ppu_add_engine 例化；新端口 in1_base_i（槽 1 低字）+
 *       quant 槽 0/1 切片（m0/s0=prof_in0、m1/s1=prof_in1，随描述符
 *       锁存于引擎内）；DMA 口选择扩为 ups/mp5/add/xfer 四路
 *       （add_act_r）。既有路径零语义变化；up_c/h/w_i 形状口复用于
 *       add（三槽同形，槽 0 dims 权威）。
 *   - V1.9 (2026-09-24) by LSL : CHW 元数据路径（用户裁定条件性 A 指示③）
 *       —— 三引擎（ups/mp5/add）chw_i 统一接 out_bytes_i（desc_if 已寄存
 *       的 w14）：add 直入并撤形状口；mp5/ups 保留形状口供窗口/核算术、
 *       仅换 chw_r 锁存源。各引擎启动拍几何乘（c_i*h_i*w_i）全删。
 *       不变量全语料验证（2026-09-24）：add/mp5 w14==槽0 c·h·w
 *       （118/118、51/51），ups w14==4×槽0 c·h·w（35/35，w14=输出
 *       字节）；rd/wr 拍数与全部对外语义零变化。
 *   - V2.0 (2026-10-07) by LSL/M5 : heads_off nc=7→n80（cls8/cls16 段基
 *       145600/148400 → 262400/294400，§8 累计律其余四值不变，表尾
 *       302400）。仅 heads 目标地址常数变化，CONCAT/VIEW/ADD/UPS/MP5
 *       路径零语义变化。权威溯源与交叉锁见 heads_off 处 M5.1 注。
 *   - V2.1-M10.6 (2026-10-18) by M10.6 Rung C : seg_done 位图馈源三脉冲
 *       输出口（seg_done_pl_o/seg_done_idx_o/heads_start_pl_o）——
 *       S_FLUSHW 出口（本段写妥+排空=§4.2 段粒度 done 语义）发段完成
 *       脉冲，S_IDLE 受理 heads 任务发 heads_start 脉冲。纯观察面增量
 *       （零数据通路扰动）；PPU_NO_UPS 刀下恒可编译（本增量在 xfer
 *       heads 径，与 UPS 桩无关）。消费方=ppu_seg_done tracker。
 ************************************************************************/

module ppu_engine_mux (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,           // loader pass 后启动（脉冲）
    // 任务参数（bundle）
    input  wire [7:0]  opcode_i,
    input  wire [31:0] out_base_i,        // concat 目标基址（out 缓冲）
    input  wire [31:0] in0_base_i,        // upsample 输入基址（槽 0 低字）
    input  wire [31:0] in1_base_i,        // add B 路基址（槽 1 低字，V1.8）
    input  wire [15:0] up_c_i, up_h_i, up_w_i, // upsample/maxpool5 输入
                                          // 形状（槽 0 dims；V1.9 起 add
                                          // 改用 chw_i 元数据不用形状）
    input  wire [31:0] head_base_i,
    input  wire [15:0] nseg_i,
    input  wire [31:0] out_bytes_i,
    input  wire [79:0]  seg_buf_i,        // 8×10b
    input  wire [79:0]  seg_prof_i,       // 8×10b
    input  wire [255:0] seg_len_i,        // 8×32b
    input  wire [7:0]   seg_present_i,
    input  wire [511:0] seg0to7_base_i,   // 8×64b（缓冲槽 3..10 基址）
    input  wire [319:0] segq_m_i,         // 10×32b（quant 槽；2..9=段）
    input  wire [59:0]  segq_s_i,         // 10×6b
    // DMA 接口（V1.6：输出口改 wire —— xfer 通路与 upsample/maxpool
    // 引擎按 ups_act_r/mp5_act_r 选择，一次任务仅一引擎在跑）
    output wire        rd_req_valid_o,
    input  wire        rd_req_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [23:0] rd_len_o,
    input  wire        rd_beat_valid_i,
    output wire        rd_beat_ready_o,
    input  wire [63:0] rd_beat_data_i,
    input  wire        rd_done_i,
    output wire        wr_req_valid_o,
    input  wire        wr_req_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [23:0] wr_len_o,
    output wire        wr_beat_valid_o,
    input  wire        wr_beat_ready_i,
    output wire [63:0] wr_beat_data_o,
    output wire [7:0]  wr_beat_strb_o,
    input  wire        wr_done_i,
    input  wire        dma_err_i,         // DMA 错误（取消推进）
    // 完成
    output reg         done_o,            // 引擎完成（数据排空；done 门
                                          // = wr_done 语义，§4.2）
    output wire        busy_o,            // 引擎占用（abort 取消观察用）
    // ---- M10.6 Rung C seg_done 位图馈源（SPEC §2 完成位提案 (a) 案 /
    //      L29 律；纯观察脉冲，零数据通路扰动）----
    output reg         seg_done_pl_o,     // heads 段完成脉冲（本段写妥
                                          // BRESP 全收+数据排空，S_FLUSHW
                                          // 出口寄存一拍）
    output reg  [2:0]  seg_done_idx_o,    // 完成段序（0..5，描述符段序）
    output reg         heads_start_pl_o   // heads 任务受理脉冲（S_IDLE
                                          // start_i 拍；位图 tracker 帧内
                                          // 粘着"本帧有 heads 任务"判据）
);

    localparam [7:0] OP_VIEW  = 8'h10,
                     OP_UPS   = 8'h14,
                     OP_MP5   = 8'h13,
                     OP_ADD   = 8'h11,
                     OP_CAT   = 8'h12,
                     OP_HEADS = 8'h15;
    localparam [3:0] S_IDLE=4'd0, S_TBL=4'd1, S_WRI=4'd2, S_START=4'd3,
                     S_SEG=4'd4, S_STREAM=4'd5, S_FLUSHW=4'd6,
                     S_FINAL=4'd7, S_VDONE=4'd8, S_UPS=4'd9, S_MP5=4'd10,
                     S_ADD=4'd11;
    localparam [31:0] IDENT_M = 32'h40000000;   // 2^30（恒等捷径）
    localparam [5:0]  IDENT_S = 6'd30;

    reg [3:0] state_r;
    reg [7:0] opcode_r;
    reg       is_heads_r, is_cat_r;
    reg [31:0] out_base_r, head_base_r, out_bytes_r;
    reg [3:0]  nseg_r;                     // 描述符段数（≤8，loader 已保）
    reg [79:0]  seg_prof_r;
    reg [255:0] seg_len_r;
    reg [7:0]   seg_present_r;
    reg [511:0] seg_base_r;
    reg [319:0] segm_r;
    reg [59:0]  segs_r;

    // 段游标
    reg [2:0]  si_r;                       // 描述符段序
    reg [3:0]  nz_r;                       // 非零段数（= xfer 段表项数）
    reg [3:0]  nseg_xf_r;                  // xfer start 用
    reg        rd_iss_r, wr_iss_r;         // 本段 rd/wr 已受
    reg [31:0] y_cnt_r, y_exp_r;           // y 字节累计 / 本段期望
    reg        rdr_done_r, seg_wr_done_r, wr_done_all_r;
    reg        flush_issued_r;
    reg [4:0]  xfl_r;                     // xfer 在途字节（push−y 脉冲）

    // 段字段切片（变量基片选）
    wire [9:0]  cur_prof = seg_prof_r[10*si_r +: 10];
    wire [31:0] cur_len  = seg_len_r [32*si_r +: 32];
    wire [63:0] cur_base = seg_base_r[64*si_r +: 64];
    wire [31:0] cur_qm   = segm_r    [32*(3'd2 + {1'b0,si_r}) +: 32];
    wire [5:0]  cur_qs   = segs_r    [6*(3'd2 + {1'b0,si_r}) +: 6];
    wire        last_seg = (si_r == nseg_r - 4'd1);
    // 本段参与搬运（0 长段跳过：D-F3j）
    wire        seg_go   = seg_present_r[si_r] &&
                           ({1'b0, si_r} < nseg_r) && (cur_len != 32'd0);
    // 段 profile 是否实装（heads 恒等；concat 仅 prof!=0）
    wire        seg_q_on = is_cat_r && (cur_prof != 10'd0);

    // heads §8 偏移（描述符段序 0..5）
    // M5.1（2026-10-07）：nc 依赖常量改 n80——仅 cls8/cls16 两段基随
    // nc=7→80 变化（145600→262400、148400→294400），reg 三段与 cls32
    // 段基（default=段序 5 基，表尾 294400+8000=302400）依 §8 累计律；
    // 权威=ppu_desc_bundle.HEADS_LAYOUT（reg8 102400 + reg16 25600 +
    // reg32 6400 + cls8 128000 + cls16 32000 + cls32 8000）。M4 冻结件
    // 为手势 nc=7 值，变更台账见 rtl_ledger_m5.json；xsim heads 逐字节
    // 门与 f3_prep_n80 派生表互为交叉锁。
    function [31:0] heads_off;
        input [2:0] s;
        case (s)
            3'd0: heads_off = 32'd0;
            3'd1: heads_off = 32'd102400;
            3'd2: heads_off = 32'd128000;
            3'd3: heads_off = 32'd134400;
            3'd4: heads_off = 32'd262400;
            default: heads_off = 32'd294400;
        endcase
    endfunction

    // ---- 内部例化 ----
    reg         rdr_start_r;
    wire [23:0] rdr_len_w = cur_len[23:0];
    wire        reader_done_w;
    wire        xf_in_valid, xf_in_ready;
    wire [7:0]  xf_in_data;
    wire        xf_y_valid, xf_y_last, xf_busy;
    wire [7:0]  xf_y_data;
    wire        asm_idle_w, asm_out_full_w;
    wire [3:0]  asm_acc_cnt_w;
    wire        xf_rbr_w, xf_wbv;                  // xfer 通路拍口（V1.6 内网）
    wire [63:0] xf_wbd;
    wire [7:0]  xf_wbs;
    reg         asm_start_r, asm_flush_r;
    reg         xf_seg_we_r, xf_start_r;
    reg [31:0]  xf_seg_len_r;
    reg [31:0]  xf_seg_m_r;
    reg [5:0]   xf_seg_s_r;

    // y 侧流闸（V1.1 承诺量准入，见文件头）：承诺 = 组装器积压 +
    // xfer 在途；≤8 放行。放行拍承诺至多 9 <16 → 拒收态（pend=16）
    // 不可达；承诺随交付回落 → 无死锁。
    wire [4:0] asm_pend_w = {1'b0, asm_acc_cnt_w} +
                            (asm_out_full_w ? 5'd8 : 5'd0);
    wire [5:0] commit_w = {1'b0, asm_pend_w} + {1'b0, xfl_r};
    wire       y_gate   = (commit_w <= 6'd8);
    wire       push_fire_w = xf_in_valid && xf_in_ready && y_gate;

    ppu_byte_reader u_reader (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(rdr_start_r), .len_i(rdr_len_w),
        .beat_valid_i(rd_beat_valid_i), .beat_ready_o(xf_rbr_w),
        .beat_data_i(rd_beat_data_i),
        .out_valid_o(xf_in_valid), .out_ready_i(xf_in_ready && y_gate),
        .out_data_o(xf_in_data),
        .done_o(reader_done_w)
    );

    yolo_ppu_xfer #(.MAXSEG(8)) u_xfer (
        .clk_i(clk_i), .rst_i(rst_i),
        .seg_we_i(xf_seg_we_r), .seg_len_i(xf_seg_len_r),
        .seg_m_i(xf_seg_m_r), .seg_s_i(xf_seg_s_r),
        .start_i(xf_start_r), .nseg_i(nseg_xf_r),
        .in_ready_o(xf_in_ready), .in_valid_i(xf_in_valid && y_gate),
        .in_data_i(xf_in_data),
        .y_valid_o(xf_y_valid), .y_o(xf_y_data), .y_last_o(xf_y_last),
        .busy_o(xf_busy)
    );

    ppu_byte_store_assembler u_asm (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(asm_start_r), .flush_i(asm_flush_r),
        .in_valid_i(xf_y_valid), .in_data_i(xf_y_data),
        .in_ready_o(),                        // 恒收由流闸保证
        .beat_valid_o(xf_wbv), .beat_ready_i(wr_beat_ready_i),
        .beat_data_o(xf_wbd), .beat_strb_o(xf_wbs),
        .idle_o(asm_idle_w),
        .acc_cnt_o(asm_acc_cnt_w), .out_full_o(asm_out_full_w)
    );

    // ---- Upsample2 引擎（F5，V1.6）----
    //  自含 FSM（ppu_ups_engine）：一次 rd_req(CHW) + 一次
    //  wr_req(4CHW)，行对重排后走自家 assembler；DMA 口由
    //  ups_act_r 选择（一次任务仅一引擎在跑，xfer 侧无并发）。
    reg         ups_start_r;
    reg         ups_act_r;
    wire        ups_rd_req_v, ups_rd_brt;
    wire [31:0] ups_rd_addr;
    wire [23:0] ups_rd_len;
    wire        ups_wr_req_v;
    wire [31:0] ups_wr_addr;
    wire [23:0] ups_wr_len;
    wire        ups_wbv;
    wire [63:0] ups_wbd;
    wire [7:0]  ups_wbs;
    wire        ups_done_w, ups_busy_w;
    reg         xf_rd_req_v, xf_wr_req_v;
    reg [31:0]  xf_rd_addr, xf_wr_addr;
    reg [23:0]  xf_rd_len, xf_wr_len;

`ifdef PPU_NO_UPS
    // r8 capacity knife (2026-10-17): UPS engine stubbed for PPU_ON builds
    // (Place 30-487 capacity wall, 51,420/53,200 LUT).  UPS dual-route is
    // still pending M10.5 D3 adjudication and every current batch runs the
    // conv-side scatter route -- 0x14 dispatch in this build hangs to the
    // engine watchdog by design.  All u_ups output wires tied inactive;
    // ADD/CAT/MP5 dispatch paths untouched.
    assign ups_rd_req_v = 1'b0;
    assign ups_rd_addr  = 32'd0;
    assign ups_rd_len   = 24'd0;
    assign ups_rd_brt   = 1'b0;
    assign ups_wr_req_v = 1'b0;
    assign ups_wr_addr  = 32'd0;
    assign ups_wr_len   = 24'd0;
    assign ups_wbv      = 1'b0;
    assign ups_wbd      = 64'd0;
    assign ups_wbs      = 8'd0;
    assign ups_done_w   = 1'b0;
    assign ups_busy_w   = 1'b0;
`else
    ppu_ups_engine u_ups (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(ups_start_r),
        .in0_base_i(in0_base_i), .out_base_i(out_base_i),
        .c_i(up_c_i), .h_i(up_h_i), .w_i(up_w_i),
        .chw_i(out_bytes_i),                    // w14 元数据（V1.9）
        .rd_req_valid_o(ups_rd_req_v), .rd_req_ready_i(rd_req_ready_i),
        .rd_addr_o(ups_rd_addr), .rd_len_o(ups_rd_len),
        .rd_beat_valid_i(rd_beat_valid_i), .rd_beat_ready_o(ups_rd_brt),
        .rd_beat_data_i(rd_beat_data_i), .rd_done_i(rd_done_i),
        .wr_req_valid_o(ups_wr_req_v), .wr_req_ready_i(wr_req_ready_i),
        .wr_addr_o(ups_wr_addr), .wr_len_o(ups_wr_len),
        .wr_beat_valid_o(ups_wbv), .wr_beat_ready_i(wr_beat_ready_i),
        .wr_beat_data_o(ups_wbd), .wr_beat_strb_o(ups_wbs),
        .wr_done_i(wr_done_i),
        .dma_err_i(dma_err_i),
        .done_o(ups_done_w), .busy_o(ups_busy_w)
    );
`endif // PPU_NO_UPS

    // ---- MaxPool5 引擎（F5-M，V1.7）----
    //  自含 FSM（ppu_mp5_engine）：一次 rd_req(CHW) + 一次
    //  wr_req(CHW)（in==out 同形），输出 FIFO + 输入准入闸吸收
    //  pad 步突发；DMA 口由 mp5_act_r 选择（一次任务仅一引擎在跑）。
    //  形状/基址口与 upsample 同一槽 0/槽 2 接线复用。
    reg         mp5_start_r;
    reg         mp5_act_r;
    wire        mp5_rd_req_v, mp5_rd_brt;
    wire [31:0] mp5_rd_addr;
    wire [23:0] mp5_rd_len;
    wire        mp5_wr_req_v;
    wire [31:0] mp5_wr_addr;
    wire [23:0] mp5_wr_len;
    wire        mp5_wbv;
    wire [63:0] mp5_wbd;
    wire [7:0]  mp5_wbs;
    wire        mp5_done_w, mp5_busy_w;

    ppu_mp5_engine u_mp5 (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(mp5_start_r),
        .in0_base_i(in0_base_i), .out_base_i(out_base_i),
        .c_i(up_c_i), .h_i(up_h_i), .w_i(up_w_i),
        .chw_i(out_bytes_i),                    // w14 元数据（V1.9）
        .rd_req_valid_o(mp5_rd_req_v), .rd_req_ready_i(rd_req_ready_i),
        .rd_addr_o(mp5_rd_addr), .rd_len_o(mp5_rd_len),
        .rd_beat_valid_i(rd_beat_valid_i), .rd_beat_ready_o(mp5_rd_brt),
        .rd_beat_data_i(rd_beat_data_i), .rd_done_i(rd_done_i),
        .wr_req_valid_o(mp5_wr_req_v), .wr_req_ready_i(wr_req_ready_i),
        .wr_addr_o(mp5_wr_addr), .wr_len_o(mp5_wr_len),
        .wr_beat_valid_o(mp5_wbv), .wr_beat_ready_i(wr_beat_ready_i),
        .wr_beat_data_o(mp5_wbd), .wr_beat_strb_o(mp5_wbs),
        .wr_done_i(wr_done_i),
        .dma_err_i(dma_err_i),
        .done_o(mp5_done_w), .busy_o(mp5_busy_w)
    );

    // ---- Add 引擎（F5-A，V1.8）----
    //  自含 FSM（ppu_add_engine）：两路独立读 FIFO 64B 块交替读 +
    //  会合逐字节双 requant 求和；一次 wr_req(CHW)+assembler。
    //  quant 槽 0/1 = prof_in0/prof_in1（desc_if 映射），切片直供；
    //  DMA 口由 add_act_r 选择（一次任务仅一引擎在跑）。
    reg         add_start_r;
    reg         add_act_r;
    wire        add_rd_req_v, add_rd_brt;
    wire [31:0] add_rd_addr;
    wire [23:0] add_rd_len;
    wire        add_wr_req_v;
    wire [31:0] add_wr_addr;
    wire [23:0] add_wr_len;
    wire        add_wbv;
    wire [63:0] add_wbd;
    wire [7:0]  add_wbs;
    wire        add_done_w, add_busy_w;

    ppu_add_engine u_add (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(add_start_r),
        .in0_base_i(in0_base_i), .in1_base_i(in1_base_i),
        .out_base_i(out_base_i),
        .chw_i(out_bytes_i),                    // w14 元数据直入（V2.1：
                                                // ADD 撤 c/h/w 形状口）
        .m0_i(segq_m_i[31:0]),  .s0_i(segq_s_i[5:0]),    // 槽 0=prof_in0
        .m1_i(segq_m_i[63:32]), .s1_i(segq_s_i[11:6]),   // 槽 1=prof_in1
        .rd_req_valid_o(add_rd_req_v), .rd_req_ready_i(rd_req_ready_i),
        .rd_addr_o(add_rd_addr), .rd_len_o(add_rd_len),
        .rd_beat_valid_i(rd_beat_valid_i), .rd_beat_ready_o(add_rd_brt),
        .rd_beat_data_i(rd_beat_data_i), .rd_done_i(rd_done_i),
        .wr_req_valid_o(add_wr_req_v), .wr_req_ready_i(wr_req_ready_i),
        .wr_addr_o(add_wr_addr), .wr_len_o(add_wr_len),
        .wr_beat_valid_o(add_wbv), .wr_beat_ready_i(wr_beat_ready_i),
        .wr_beat_data_o(add_wbd), .wr_beat_strb_o(add_wbs),
        .wr_done_i(wr_done_i),
        .dma_err_i(dma_err_i),
        .done_o(add_done_w), .busy_o(add_busy_w)
    );

    // DMA 口选择：ups/mp5/add 任务期走自含引擎，其余走 xfer 通路
    assign rd_req_valid_o = ups_act_r ? ups_rd_req_v :
                            mp5_act_r ? mp5_rd_req_v :
                            add_act_r ? add_rd_req_v : xf_rd_req_v;
    assign rd_addr_o      = ups_act_r ? ups_rd_addr  :
                            mp5_act_r ? mp5_rd_addr  :
                            add_act_r ? add_rd_addr  : xf_rd_addr;
    assign rd_len_o       = ups_act_r ? ups_rd_len   :
                            mp5_act_r ? mp5_rd_len   :
                            add_act_r ? add_rd_len   : xf_rd_len;
    assign rd_beat_ready_o= ups_act_r ? ups_rd_brt   :
                            mp5_act_r ? mp5_rd_brt   :
                            add_act_r ? add_rd_brt   : xf_rbr_w;
    assign wr_req_valid_o = ups_act_r ? ups_wr_req_v :
                            mp5_act_r ? mp5_wr_req_v :
                            add_act_r ? add_wr_req_v : xf_wr_req_v;
    assign wr_addr_o      = ups_act_r ? ups_wr_addr  :
                            mp5_act_r ? mp5_wr_addr  :
                            add_act_r ? add_wr_addr  : xf_wr_addr;
    assign wr_len_o       = ups_act_r ? ups_wr_len   :
                            mp5_act_r ? mp5_wr_len   :
                            add_act_r ? add_wr_len   : xf_wr_len;
    assign wr_beat_valid_o= ups_act_r ? ups_wbv      :
                            mp5_act_r ? mp5_wbv      :
                            add_act_r ? add_wbv      : xf_wbv;
    assign wr_beat_data_o = ups_act_r ? ups_wbd      :
                            mp5_act_r ? mp5_wbd      :
                            add_act_r ? add_wbd      : xf_wbd;
    assign wr_beat_strb_o = ups_act_r ? ups_wbs      :
                            mp5_act_r ? mp5_wbs      :
                            add_act_r ? add_wbs      : xf_wbs;

    assign busy_o = (state_r != S_IDLE);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r <= S_IDLE;            opcode_r <= 8'd0; is_heads_r <= 1'b0; is_cat_r <= 1'b0;
            out_base_r <= 32'd0; head_base_r <= 32'd0; out_bytes_r <= 32'd0;
            nseg_r <= 4'd0;
            seg_prof_r <= 80'd0; seg_len_r <= 256'd0;
            seg_present_r <= 8'd0; seg_base_r <= 512'd0;
            segm_r <= 320'd0; segs_r <= 60'd0;
            si_r <= 3'd0; nz_r <= 4'd0; nseg_xf_r <= 4'd0;
            rd_iss_r <= 1'b0; wr_iss_r <= 1'b0;
            y_cnt_r <= 32'd0; y_exp_r <= 32'd0;
            rdr_done_r <= 1'b0; seg_wr_done_r <= 1'b0; wr_done_all_r <= 1'b0;
            flush_issued_r <= 1'b0;
            xfl_r <= 5'd0;
            rdr_start_r <= 1'b0; asm_start_r <= 1'b0; asm_flush_r <= 1'b0;
            xf_seg_we_r <= 1'b0; xf_start_r <= 1'b0;
            xf_seg_len_r <= 32'd0;
            xf_seg_m_r <= 32'd0; xf_seg_s_r <= 6'd0;
            xf_rd_req_v <= 1'b0; xf_wr_req_v <= 1'b0;
            xf_rd_addr <= 32'd0; xf_rd_len <= 24'd0;
            xf_wr_addr <= 32'd0; xf_wr_len <= 24'd0;
            ups_start_r <= 1'b0; ups_act_r <= 1'b0;
            mp5_start_r <= 1'b0; mp5_act_r <= 1'b0;
            add_start_r <= 1'b0; add_act_r <= 1'b0;
            done_o <= 1'b0;
            seg_done_pl_o <= 1'b0; seg_done_idx_o <= 3'd0;
            heads_start_pl_o <= 1'b0;
        end else begin
            // 脉冲缺省
            rdr_start_r  <= 1'b0;
            asm_start_r  <= 1'b0;
            asm_flush_r  <= 1'b0;
            xf_seg_we_r  <= 1'b0;
            xf_start_r   <= 1'b0;
            ups_start_r  <= 1'b0;
            mp5_start_r  <= 1'b0;
            add_start_r  <= 1'b0;
            done_o       <= 1'b0;
            seg_done_pl_o <= 1'b0;      // M10.6 Rung C：单拍缺省
            heads_start_pl_o <= 1'b0;

            // 写妥脉冲全局锁存（S_FINAL/S_FLUSHW 等待期不丢拍）。
            // V1.5：heads 段写妥改在 S_FLUSHW 等待——尾段（len%8≠0）的
            // 末拍由冲刷产生，写妥只能在冲刷后到来；原 S_STREAM 内等
            // seg_wr_done 对尾段构成环死锁（desc103 段5 实测 DMA 超时）。
            if (wr_done_i)
                wr_done_all_r <= 1'b1;
            if (wr_done_i && is_heads_r &&
                (state_r == S_SEG || state_r == S_STREAM || state_r == S_FLUSHW))
                seg_wr_done_r <= 1'b1;

            // xfer 在途计数（流闸 V1.1；跨状态推进，任务起点/弃权清零）
            case ({push_fire_w, xf_y_valid})
                2'b10:   xfl_r <= xfl_r + 5'd1;
                2'b01:   xfl_r <= xfl_r - 5'd1;
                default: ;
            endcase

            // y 脉冲计数（V1.3：跨状态计数）。concat 段界（S_STREAM→
            // S_SEG）与收尾（→S_FINAL）后 xfer 3 级流水仍在排水脉冲，
            // 仅在 S_STREAM 内计数会漏尾 ~3 拍 → y_cnt 永不及 out_bytes
            // → flush 不发 → S_FINAL 悬死（run01 实测 307197/307200）。
            // 置零仅发生在 S_START（任务）与 heads S_SEG（段），在 case
            // 内后写覆盖本计数。
            if (state_r != S_IDLE && xf_y_valid)
                y_cnt_r <= y_cnt_r + 32'd1;

            // DMA 错误：任一推进态弃权回 IDLE（无 done；shell 粘错上报）
            if (dma_err_i && state_r != S_IDLE && state_r != S_VDONE) begin
                state_r <= S_IDLE;
                xf_rd_req_v <= 1'b0;
                xf_wr_req_v <= 1'b0;
                ups_act_r <= 1'b0;       // u_ups 自含 err 弃权，此处只清选择
                mp5_act_r <= 1'b0;       // u_mp5 同构（自含 err 弃权）
                add_act_r <= 1'b0;       // u_add 同构（自含 err 弃权）
                xfl_r  <= 5'd0;
            end else begin
            case (state_r)
            // ---- 启动锁存 / VIEW 直通 ----
            S_IDLE: begin
                if (start_i) begin
                    opcode_r      <= opcode_i;
                    is_heads_r    <= (opcode_i == OP_HEADS);
                    is_cat_r      <= (opcode_i == OP_CAT);
                    // M10.6 Rung C：heads 任务受理脉冲（位图 tracker 的
                    // 帧内 heads_seen 置位源；单拍，零数据通路扰动）
                    if (opcode_i == OP_HEADS)
                        heads_start_pl_o <= 1'b1;
                    out_base_r    <= out_base_i;
                    head_base_r   <= head_base_i;
                    out_bytes_r   <= out_bytes_i;
                    nseg_r        <= nseg_i[3:0];
                    seg_prof_r    <= seg_prof_i;
                    seg_len_r     <= seg_len_i;
                    seg_present_r <= seg_present_i;
                    seg_base_r    <= seg0to7_base_i;
                    segm_r        <= segq_m_i;
                    segs_r        <= segq_s_i;
                    si_r <= 3'd0; nz_r <= 4'd0;
                    wr_done_all_r <= 1'b0;
                    xfl_r <= 5'd0;
                    if ((opcode_i == OP_CAT) || (opcode_i == OP_HEADS))
                        state_r <= S_TBL;
                    else if (opcode_i == OP_UPS) begin
                        ups_start_r <= 1'b1;     // F5：upsample 引擎
                        ups_act_r   <= 1'b1;
                        state_r     <= S_UPS;
                    end
                    else if (opcode_i == OP_MP5) begin
                        mp5_start_r <= 1'b1;     // F5-M：maxpool5 引擎
                        mp5_act_r   <= 1'b1;
                        state_r     <= S_MP5;
                    end
                    else if (opcode_i == OP_ADD) begin
                        add_start_r <= 1'b1;     // F5-A：add 引擎
                        add_act_r   <= 1'b1;
                        state_r     <= S_ADD;
                    end
                    else                        // VIEW / 其他：零搬移
                        state_r <= S_VDONE;
                end
            end
            // ---- xfer 段表（每拍一段，只写非零参与段；核内自动递增）----
            S_TBL: begin
                if (seg_go) begin
                    xf_seg_we_r  <= 1'b1;     // len/m/s 同拍锁存（写脉冲
                    xf_seg_len_r <= cur_len;  // 滞后一拍，组合直连会错段）
                    xf_seg_m_r   <= seg_q_on ? cur_qm : IDENT_M;
                    xf_seg_s_r  <= seg_q_on ? cur_qs : IDENT_S;
                end
                if (si_r == 3'd7) begin
                    nseg_xf_r <= nz_r + (seg_go ? 4'd1 : 4'd0);
                    if ((nz_r + (seg_go ? 4'd1 : 4'd0)) == 4'd0)
                        state_r <= S_VDONE;     // 全零段：Σ=0，无搬移
                    else
                        state_r <= is_cat_r ? S_WRI : S_START;
                end else begin
                    si_r <= si_r + 3'd1;
                    nz_r <= nz_r + (seg_go ? 4'd1 : 4'd0);
                end
            end
            // ---- concat 总写请求 ----
            S_WRI: begin
                if (!xf_wr_req_v) begin
                    xf_wr_req_v <= 1'b1;
                    xf_wr_addr <= out_base_r;
                    xf_wr_len <= out_bytes_r[23:0];
                end else if (wr_req_ready_i) begin
                    xf_wr_req_v <= 1'b0;
                    asm_start_r    <= 1'b1;     // 整条流一次复位累加器
                    state_r        <= S_START;
                end
            end
            // ---- xfer 启动 ----
            S_START: begin
                xf_start_r <= 1'b1;             // nseg_xf_r 已就绪
                si_r       <= 3'd0;
                y_cnt_r    <= 32'd0;
                rd_iss_r   <= 1'b0;
                wr_iss_r   <= 1'b0;
                rdr_done_r <= 1'b0;
                seg_wr_done_r <= 1'b0;
                flush_issued_r <= 1'b0;
                state_r    <= S_SEG;
            end
            // ---- 逐段发请求（heads：rd+wr；concat：仅 rd）----
            S_SEG: begin
                if (!seg_go) begin              // 0 长段：跳过
                    if (last_seg)
                        state_r <= is_cat_r ? S_FINAL : S_VDONE;
                    else begin
                        si_r <= si_r + 3'd1;
                        rd_iss_r <= 1'b0; wr_iss_r <= 1'b0;
                    end
                end else begin
                    if (!rd_iss_r) begin
                        if (!xf_rd_req_v) begin
                            xf_rd_req_v <= 1'b1;
                            xf_rd_addr <= cur_base[31:0];
                            xf_rd_len <= cur_len[23:0];
                        end else if (rd_req_ready_i) begin
                            xf_rd_req_v <= 1'b0;
                            rd_iss_r <= 1'b1;
                        end
                    end
                    if (is_heads_r && !wr_iss_r) begin
                        if (!xf_wr_req_v) begin
                            xf_wr_req_v <= 1'b1;
                            xf_wr_addr <= head_base_r + heads_off(si_r);
                            xf_wr_len <= cur_len[23:0];
                        end else if (wr_req_ready_i) begin
                            xf_wr_req_v <= 1'b0;
                            wr_iss_r <= 1'b1;
                        end
                    end
                    if (rd_iss_r && (!is_heads_r || wr_iss_r)) begin
                        rdr_start_r <= 1'b1;    // reader 按段重启
                        if (is_heads_r) begin
                            asm_start_r <= 1'b1; // heads 逐段复位累加器
                            y_exp_r <= cur_len;
                            y_cnt_r <= 32'd0;
                        end
                        rdr_done_r   <= 1'b0;
                        seg_wr_done_r<= 1'b0;
                        state_r <= S_STREAM;
                    end
                end
            end
            // ---- 流推进 ----
            S_STREAM: begin
                if (reader_done_w)
                    rdr_done_r <= 1'b1;
                if (is_heads_r) begin
                    // 段末：y 流尽（含 xfer 流水滞后）+ 读尽 → 冲刷。
                    // 写妥不在此等（V1.5）：尾段末拍=冲刷产物，此处等
                    // seg_wr_done 即环死锁；写妥移 S_FLUSHW。
                    if (rdr_done_r && (y_cnt_r == y_exp_r)) begin
                        asm_flush_r <= 1'b1;
                        state_r <= S_FLUSHW;
                    end
                end else begin
                    // concat：reader 尽即接下段（xfer 连续流，无段界）
                    if (rdr_done_r) begin
                        if (last_seg)
                            state_r <= S_FINAL;
                        else begin
                            si_r <= si_r + 3'd1;
                            rd_iss_r <= 1'b0; wr_iss_r <= 1'b0;
                            state_r <= S_SEG;
                        end
                    end
                end
            end
            // ---- heads 段末冲刷等待 ----
            // V1.4：段界出清不等 xf_busy —— xfer 在 heads 全程连续运行
            //（段间不停），!xf_busy 段间永假曾致 S_FLUSHW 悬死；本段
            // 排水已由 S_STREAM 的 y_cnt==y_exp 保证（脉冲数=出清数）。
            // V1.5：补等本段写妥（asm_idle && seg_wr_done）——尾段末拍
            // 由冲刷产生、写妥随后才来；不等则末段 done 早于 BRESP（违
            // §4.2 done=写妥语义），下段 wr_req 亦会压在前段未完写上。
            S_FLUSHW: begin
                if (asm_idle_w && seg_wr_done_r) begin
                    // M10.6 Rung C：本段写妥+排空（= §4.2 段粒度 done
                    // 语义）→ seg_done 脉冲馈位图 tracker。is_heads_r
                    // 守卫恒真（S_FLUSHW 仅 heads 径可达），保留为结构
                    // 保险。尾段脉冲先于 done_o 至少 2 拍，walker commit
                    // 门评测时位图必已满（时序核算见 ppu_seg_done 头注）。
                    if (is_heads_r) begin
                        seg_done_pl_o   <= 1'b1;
                        seg_done_idx_o  <= si_r;
                    end
                    if (last_seg)
                        state_r <= S_VDONE;
                    else begin
                        si_r <= si_r + 3'd1;
                        rd_iss_r <= 1'b0; wr_iss_r <= 1'b0;
                        state_r <= S_SEG;
                    end
                end
            end
            // ---- concat 收尾：y 流尽 → 一次 flush → 写妥 ----
            S_FINAL: begin
                if (!flush_issued_r) begin
                    if ((y_cnt_r == out_bytes_r) && !xf_busy) begin
                        asm_flush_r   <= 1'b1;
                        flush_issued_r<= 1'b1;
                    end
                end else if (asm_idle_w && wr_done_all_r)
                    state_r <= S_VDONE;
            end
            // ---- upsample 引擎运行（自含 FSM；完成即出）----
            S_UPS: begin
                if (ups_done_w) begin
                    ups_act_r <= 1'b0;
                    state_r   <= S_VDONE;
                end
            end
            // ---- maxpool5 引擎运行（自含 FSM；完成即出）----
            S_MP5: begin
                if (mp5_done_w) begin
                    mp5_act_r <= 1'b0;
                    state_r   <= S_VDONE;
                end
            end
            // ---- add 引擎运行（自含 FSM；完成即出）----
            S_ADD: begin
                if (add_done_w) begin
                    add_act_r <= 1'b0;
                    state_r   <= S_VDONE;
                end
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
