/************************************************************************
 * File Name       : ppu_shell_top.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_shell_top
 * Description     : PPU-F3 单描述符 shell 顶层：取包（ppu_desc_if）→
 *                   九步校验（ppu_loader）→ 引擎（ppu_engine_mux，
 *                   VIEW/CONCAT/HEADS/UPSAMPLE2/MAXPOOL5/ADD；其余算子
 *                   ldr_only 校验即完）→ DMA（ppu_dma_master）→
 *                   完成仲裁（ppu_done_arbiter，§4.2 事件优先序）。
 *
 *   流程：req_i+desc_idx → desc_if bundle → loader 判决（多周期：
 *     V2.0 定长 41/42/70 拍，S_VERDICT 等待态消费脉冲）→
 *     错误：粘着上报（§4.3 停发不续跑），halt 至复位；
 *     通过且 XFER/VIEW/UPSAMPLE2/MAXPOOL5：引擎启动（VIEW 零搬移
 *       直通 done；UPSAMPLE2 走 ppu_ups_engine，MAXPOOL5 走
 *       ppu_mp5_engine，F5）；
 *     通过且其余算子（conv/add）：validate-only——无搬移，
 *       以等价 done（无写事务，§4.2 排空条件自然满足）进仲裁。
 *   事件：stop（优雅，当前描述符含 BRESP 排空完成后停）/ abort
 *     （丢弃：引擎取消、DMA 停发、仲裁记 cause=abort 无发布）/
 *     ffe（doorbell 强发环）——全部经仲裁器按 §4.2 序定案。
 *     abort 无在跑任务时不得发出（TB 合同；否则粘着殃及后续任务）。
 *   heads 输出基址为外部配置口（F6 CSR 期归寄存器，F3 由 TB 供
 *   0x1F800000）。
 * Dependencies    : ppu_desc_if / ppu_loader / ppu_engine_mux /
 *                   ppu_dma_master / ppu_done_arbiter。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-22) by LSL : F5 —— UPSAMPLE2（0x14）入引擎派发
 *       门；engine_mux 增 in0 基址/C/H/W 接线。其余路径零变化。
 *   - V1.2 (2026-09-22) by LSL : F5-M —— MAXPOOL5（0x13）入引擎
 *       派发门（engine_mux V1.7 三路派发）。其余路径零变化。
 *   - V1.3 (2026-09-22) by LSL : F5-A —— ADD（0x11）入引擎派发门
 *       （engine_mux V1.8 四路派发）；增槽 1 基址接线 in1_base（此前
 *       TFMPC 未连接警告的 b 侧字段随本类落位；首跑勘误：槽低字在
 *       64b/槽 布局 = [95:64]，误接 [63:32]（槽 0 高字=0）致 B 路读
 *       0 址）。其余路径零变化。
 *   - V1.4-M10.6 (2026-10-18) by M10.6 Rung C : seg_done 位图馈源三
 *       口透传（engine_mux V2.1 新输出直挂 shell 口，纯连线零逻辑）。
 *   - V1.5 (2026-10-23) by hwglobal G-02 : sb_base 通路 64→32b——
 *       dif 输出 11×32b + hi_nz 粘错位，loader 直挂（bank 二锁已删，
 *       见 loader V3.0 头注）；引擎侧 seg0to7_base_i 维持 8×64b 口宽，
 *       高字零扩展（编译器侧高 32b 恒零合同，证据 desc_if V2.0 头注），
 *       engine_mux/xfer 零接触；in0/in1/out_base 本就该是低字切片
 *       （槽 s 低字 = 32s+31:32s）。
 ************************************************************************/

module ppu_shell_top (
    input  wire        clk_i,
    input  wire        rst_i,
    // ---- 任务派发 ----
    input  wire        req_i,
    input  wire [6:0]  desc_idx_i,
    input  wire [31:0] head_base_i,        // heads 输出基址（F6 前 TB 配）
    // ---- PS 事件 ----
    input  wire        stop_i,
    input  wire        abort_i,
    input  wire        ffe_i,
    // ---- DMA 配置 ----
    input  wire [23:0] timeout_cfg_i,
    input  wire [2:0]  rd_outst_cfg_i,
    input  wire [2:0]  wr_outst_cfg_i,
    // ---- 表口（1 拍同步读，BRAM port B 模型）----
    output wire [11:0] desc_addr_o,
    input  wire [31:0] desc_din_i,
    output wire [9:0]  buf_addr_o,
    input  wire [31:0] buf_din_i,
    output wire [9:0]  qt_addr_o,
    input  wire [31:0] qt_din_i,
    // ---- AXI4 64b master（DMA）----
    output wire [31:0] araddr_o,
    output wire [3:0]  arlen_o,
    output wire [2:0]  arsize_o,
    output wire [1:0]  arburst_o,
    output wire        arvalid_o,
    input  wire        arready_i,
    input  wire [63:0] rdata_i,
    input  wire [1:0]  rresp_i,
    input  wire        rlast_i,
    input  wire        rvalid_i,
    output wire        rready_o,
    output wire [31:0] awaddr_o,
    output wire [3:0]  awlen_o,
    output wire [2:0]  awsize_o,
    output wire [1:0]  awburst_o,
    output wire        awvalid_o,
    input  wire        awready_i,
    output wire [63:0] wdata_o,
    output wire [7:0]  wstrb_o,
    output wire        wlast_o,
    output wire        wvalid_o,
    input  wire        wready_i,
    input  wire [1:0]  bresp_i,
    input  wire        bvalid_i,
    output wire        bready_o,
    // ---- 完成判决 ----
    output wire        busy_o,
    output wire        desc_done_o,
    output wire        ring_publish_o,
    output wire [2:0]  done_cause_o,
    output wire        stopped_o,
    // ---- 错误上报（粘着至复位）----
    output reg         ldr_err_valid_o,
    output reg  [3:0]  ldr_err_step_o,
    output reg  [3:0]  ldr_err_bit_o,
    output reg  [7:0]  ldr_err_code_o,
    output reg         dma_err_valid_o,
    output reg  [3:0]  dma_err_bit_o,
    output wire        dma_halted_o,
    output wire        eng_busy_o,
    // ---- M10.6 Rung C：seg_done 位图馈源透传（engine_mux → f7_top
    //      tracker；纯观察面，shell 本体零逻辑增量）----
    output wire        seg_done_pl_o,
    output wire [2:0]  seg_done_idx_o,
    output wire        heads_start_pl_o
);

    localparam [2:0] S_IDLE=3'd0, S_FETCH=3'd1, S_VERDICT=3'd2,
                     S_RUN=3'd3, S_DECIDE=3'd4, S_HALT=3'd5;

    reg [2:0] state_r;
    reg       err_q;                        // 任一错误粘着（停发不续跑）
    reg       ldr_err_q, dma_err_q;
    reg       abort_q;                      // PS abort 粘着（至取消落定）
    reg       arm_r, eng_start_r, vld_done_r, abt_done_r;

    // ---- 帧内派发门（错误/停机后拒新任务）----
    wire dispatch_ok_w = !err_q && !stopped_o;
    wire dif_req_w = req_i && (state_r == S_IDLE) && dispatch_ok_w;

    // ================= 取包 =================
    wire        dif_busy_w, dif_done_w;
    wire [7:0]  b_opcode_w;
    wire [15:0] b_w0_w;
    wire [7:0]  b_desc_id_w;
    wire [9:0]  b_in0_w, b_in1_w, b_out_w;
    wire [15:0] b_c_w, b_h_w, b_w_w;
    wire [15:0] b_nseg_w;
    wire [31:0] b_out_bytes_w;
    wire [7:0]  b_seg_present_w;
    wire [79:0] b_seg_prof_w;
    wire [255:0] b_seg_len_w;
    wire [351:0] sb_base_w;
    wire [10:0]  sb_base_hi_nz_w;
    wire [351:0] sb_size_w, sb_stride_w;
    wire [175:0] sb_c_w, sb_h_w, sb_w_w;
    wire [10:0]  sb_valid_w, sb_fetched_w;
    wire [87:0]  sb_prod_w;
    wire [319:0] qm_w;
    wire [59:0]  qs_w;
    wire [9:0]   q_fetched_w;

    ppu_desc_if u_dif (
        .clk_i(clk_i), .rst_i(rst_i),
        .req_i(dif_req_w), .desc_idx_i(desc_idx_i),
        .busy_o(dif_busy_w), .done_o(dif_done_w),
        .desc_addr_o(desc_addr_o), .desc_din_i(desc_din_i),
        .buf_addr_o(buf_addr_o),   .buf_din_i(buf_din_i),
        .qt_addr_o(qt_addr_o),     .qt_din_i(qt_din_i),
        .b_opcode_o(b_opcode_w), .b_w0_o(b_w0_w),
        .b_desc_id_o(b_desc_id_w),
        .b_in0_o(b_in0_w), .b_in1_o(b_in1_w), .b_out_o(b_out_w),
        .b_c_o(b_c_w), .b_h_o(b_h_w), .b_w_o(b_w_w),
        .b_nseg_o(b_nseg_w), .b_out_bytes_o(b_out_bytes_w),
        .b_seg_present_o(b_seg_present_w),
        .b_seg_prof_o(b_seg_prof_w), .b_seg_len_o(b_seg_len_w),
        .sb_base_o(sb_base_w), .sb_base_hi_nz_o(sb_base_hi_nz_w),
        .sb_size_o(sb_size_w),
        .sb_stride_o(sb_stride_w),
        .sb_c_o(sb_c_w), .sb_h_o(sb_h_w), .sb_w_o(sb_w_w),
        .sb_valid_o(sb_valid_w), .sb_fetched_o(sb_fetched_w),
        .sb_prod_o(sb_prod_w),
        .qm_o(qm_w), .qs_o(qs_w), .q_fetched_o(q_fetched_w)
    );

    wire        ldr_pass_w, ldr_ev_w;
    wire [3:0]  ldr_step_w, ldr_bit_w;
    wire [7:0]  ldr_code_w;

    ppu_loader u_ldr (
        .clk_i(clk_i), .rst_i(rst_i),
        .valid_i(dif_done_w),
        .b_opcode_i(b_opcode_w),
        .b_w0_i(b_w0_w),
        .b_desc_id_i(b_desc_id_w),
        .b_in0_i(b_in0_w), .b_in1_i(b_in1_w), .b_out_i(b_out_w),
        .b_c_i(b_c_w), .b_h_i(b_h_w), .b_w_i(b_w_w),
        .b_nseg_i(b_nseg_w),
        .b_out_bytes_i(b_out_bytes_w),
        .b_seg_present_i(b_seg_present_w),
        .b_seg_prof_i(b_seg_prof_w),
        .b_seg_len_i(b_seg_len_w),
        .sb_base_i(sb_base_w), .sb_base_hi_nz_i(sb_base_hi_nz_w),
        .sb_size_i(sb_size_w),
        .sb_stride_i(sb_stride_w),
        .sb_c_i(sb_c_w), .sb_h_i(sb_h_w), .sb_w_i(sb_w_w),
        .sb_valid_i(sb_valid_w), .sb_fetched_i(sb_fetched_w),
        .sb_prod_i(sb_prod_w),
        .q_fetched_i(q_fetched_w),
        .pass_o(ldr_pass_w),
        .err_valid_o(ldr_ev_w), .err_step_o(ldr_step_w),
        .err_bit_o(ldr_bit_w), .err_code_o(ldr_code_w)
    );

    // ================= 引擎（XFER/VIEW）=================
    wire        eng_done_w, eng_busy_w;
    wire        rd_req_v_w, rd_req_r_w, rd_bv_w, rd_br_w, rd_dn_w;
    wire        wr_req_v_w, wr_req_r_w, wr_bv_w, wr_br_w, wr_dn_w;
    wire [31:0] rd_addr_w, wr_addr_w;
    wire [23:0] rd_len_w, wr_len_w;
    wire [63:0] rd_beat_d_w, wr_beat_d_w;
    wire [7:0]  wr_beat_s_w;

    wire is_xfer_w = (b_opcode_w == 8'h12) || (b_opcode_w == 8'h15) ||
                     (b_opcode_w == 8'h10) || (b_opcode_w == 8'h14) ||
                     (b_opcode_w == 8'h13) || (b_opcode_w == 8'h11);
    // V1.5(G-02)：base 32b 布局（槽 s 低字 = 32s+31:32s）
    wire [31:0] out_base_w  = sb_base_w[95:64];     // 槽 2（out）基址低字
    wire [31:0] in0_base_w  = sb_base_w[31:0];      // 槽 0（in0）基址低字（F5）
    wire [31:0] in1_base_w  = sb_base_w[63:32];     // 槽 1（in1）基址低字
                                                    // （F5-A add B 路）
    wire [15:0] in0_c_w     = sb_c_w[15:0];         // 槽 0（in0）dims ——
    wire [15:0] in0_h_w     = sb_h_w[15:0];         // upsample/maxpool5/add
    wire [15:0] in0_w_w     = sb_w_w[15:0];         // 输入形状权威（ups
                                                    // desc=输出形状；mp5/add
                                                    // 同形，三槽一致）
    // V1.5(G-02)：seg0to7_base_i 口宽维持 8×64b（engine_mux 零接触），
    // 高字零扩展——高 32b 恒零合同（desc_if V2.0 头注），契约内逐位同
    // 原 sb_base_w[703:192]；契约外（hi≠0）描述字在 loader 步 6 即拒，
    // 引擎不会启动。段 m = 槽 (3+m)，原映射 bit 64m+31:64m = 槽低字。
    wire [511:0] seg_base_w;
    genvar gs;
    generate
        for (gs = 0; gs < 8; gs = gs + 1) begin : GC_SEGBASE
            assign seg_base_w[64*gs +: 64] = {32'd0, sb_base_w[32*(3+gs) +: 32]};
        end
    endgenerate

    ppu_engine_mux u_eng (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(eng_start_r),
        .opcode_i(b_opcode_w),
        .out_base_i(out_base_w),
        .in0_base_i(in0_base_w),
        .in1_base_i(in1_base_w),
        .up_c_i(in0_c_w), .up_h_i(in0_h_w), .up_w_i(in0_w_w),
        .head_base_i(head_base_i),
        .nseg_i(b_nseg_w),
        .out_bytes_i(b_out_bytes_w),
        .seg_buf_i(80'd0),
        .seg_prof_i(b_seg_prof_w),
        .seg_len_i(b_seg_len_w),
        .seg_present_i(b_seg_present_w),
        .seg0to7_base_i(seg_base_w),
        .segq_m_i(qm_w), .segq_s_i(qs_w),
        .rd_req_valid_o(rd_req_v_w), .rd_req_ready_i(rd_req_r_w),
        .rd_addr_o(rd_addr_w), .rd_len_o(rd_len_w),
        .rd_beat_valid_i(rd_bv_w), .rd_beat_ready_o(rd_br_w),
        .rd_beat_data_i(rd_beat_d_w), .rd_done_i(rd_dn_w),
        .wr_req_valid_o(wr_req_v_w), .wr_req_ready_i(wr_req_r_w),
        .wr_addr_o(wr_addr_w), .wr_len_o(wr_len_w),
        .wr_beat_valid_o(wr_bv_w), .wr_beat_ready_i(wr_br_w),
        .wr_beat_data_o(wr_beat_d_w), .wr_beat_strb_o(wr_beat_s_w),
        .wr_done_i(wr_dn_w),
        .dma_err_i(err_q || abort_q),
        .done_o(eng_done_w), .busy_o(eng_busy_w),
        .seg_done_pl_o(seg_done_pl_o),
        .seg_done_idx_o(seg_done_idx_o),
        .heads_start_pl_o(heads_start_pl_o)
    );

    // ================= DMA =================
    wire        dma_ep_w, dma_halt_w;
    wire [3:0]  dma_ebit_w;
    wire [23:0] dma_ebeat_w;

    ppu_dma_master u_dma (
        .clk_i(clk_i), .rst_i(rst_i),
        .abort_i(abort_q),
        .timeout_cfg_i(timeout_cfg_i),
        .rd_outst_cfg_i(rd_outst_cfg_i), .wr_outst_cfg_i(wr_outst_cfg_i),
        .rd_req_valid_i(rd_req_v_w), .rd_req_ready_o(rd_req_r_w),
        .rd_addr_i(rd_addr_w), .rd_len_i(rd_len_w),
        .rd_beat_valid_o(rd_bv_w), .rd_beat_ready_i(rd_br_w),
        .rd_beat_data_o(rd_beat_d_w), .rd_done_o(rd_dn_w),
        .wr_req_valid_i(wr_req_v_w), .wr_req_ready_o(wr_req_r_w),
        .wr_addr_i(wr_addr_w), .wr_len_i(wr_len_w),
        .wr_beat_valid_i(wr_bv_w), .wr_beat_ready_o(wr_br_w),
        .wr_beat_data_i(wr_beat_d_w), .wr_beat_strb_i(wr_beat_s_w),
        .wr_done_o(wr_dn_w),
        .err_pulse_o(dma_ep_w), .err_bit_o(dma_ebit_w),
        .err_code_o(), .err_beat_o(dma_ebeat_w), .halted_o(dma_halt_w),
        .araddr_o(araddr_o), .arlen_o(arlen_o),
        .arsize_o(arsize_o), .arburst_o(arburst_o),
        .arvalid_o(arvalid_o), .arready_i(arready_i),
        .rdata_i(rdata_i), .rresp_i(rresp_i),
        .rlast_i(rlast_i), .rvalid_i(rvalid_i), .rready_o(rready_o),
        .awaddr_o(awaddr_o), .awlen_o(awlen_o),
        .awsize_o(awsize_o), .awburst_o(awburst_o),
        .awvalid_o(awvalid_o), .awready_i(awready_i),
        .wdata_o(wdata_o), .wstrb_o(wstrb_o),
        .wlast_o(wlast_o), .wvalid_o(wvalid_o), .wready_i(wready_i),
        .bresp_i(bresp_i), .bvalid_i(bvalid_i), .bready_o(bready_o)
    );

    // ================= 完成仲裁 =================
    wire arb_done_w = eng_done_w || vld_done_r || abt_done_r;

    ppu_done_arbiter u_arb (
        .clk_i(clk_i), .rst_i(rst_i),
        .arm_i(arm_r),
        .done_i(arb_done_w),
        .last_i(b_w0_w[9]),
        .stop_i(stop_i), .abort_i(abort_i), .ffe_i(ffe_i),
        .desc_done_o(desc_done_o), .ring_publish_o(ring_publish_o),
        .done_cause_o(done_cause_o), .stopped_o(stopped_o)
    );

    assign busy_o      = (state_r != S_IDLE) || dif_busy_w || eng_busy_w;
    assign dma_halted_o = dma_halt_w;
    assign eng_busy_o  = eng_busy_w;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r <= S_IDLE;
            err_q <= 1'b0; ldr_err_q <= 1'b0; dma_err_q <= 1'b0;
            abort_q <= 1'b0;
            arm_r <= 1'b0; eng_start_r <= 1'b0;
            vld_done_r <= 1'b0; abt_done_r <= 1'b0;
            ldr_err_valid_o <= 1'b0; ldr_err_step_o <= 4'd0;
            ldr_err_bit_o <= 4'd0; ldr_err_code_o <= 8'd0;
            dma_err_valid_o <= 1'b0; dma_err_bit_o <= 4'd0;
        end else begin
            // 脉冲缺省
            arm_r       <= 1'b0;
            eng_start_r <= 1'b0;
            vld_done_r  <= 1'b0;
            abt_done_r  <= 1'b0;

            // 事件/错误粘着
            abort_q  <= abort_i | abort_q;
            if (ldr_ev_w) begin
                ldr_err_q <= 1'b1;
                ldr_err_valid_o <= 1'b1;
                ldr_err_step_o <= ldr_step_w;
                ldr_err_bit_o  <= ldr_bit_w;
                ldr_err_code_o <= ldr_code_w;
            end
            if (dma_ep_w) begin
                dma_err_q <= 1'b1;
                dma_err_valid_o <= 1'b1;
                dma_err_bit_o  <= dma_ebit_w;
            end
            err_q <= err_q | ldr_err_q | dma_err_q;

            case (state_r)
            S_IDLE: begin
                if (dif_req_w) begin
                    arm_r  <= 1'b1;          // 仲裁重臂（新任务）
                    state_r <= S_FETCH;
                end
            end
            S_FETCH: begin
                if (dif_done_w)
                    state_r <= S_VERDICT;    // loader V2.0 定长扫描后脉冲
            end
            S_VERDICT: begin
                if (ldr_ev_w)
                    state_r <= S_HALT;       // 首错即停（§4.3）
                else if (ldr_pass_w) begin
                    if (is_xfer_w) begin
                        eng_start_r <= 1'b1;
                        state_r <= S_RUN;
                    end else begin
                        vld_done_r <= 1'b1;  // validate-only 等价 done
                        state_r <= S_DECIDE;
                    end
                end
            end
            S_RUN: begin
                // dma_ep 为脉冲：当拍引擎未必已弃权 → 用粘着 dma_err_q
                // 补看（否则引擎已 IDLE 无 done，本态永挂）
                if ((dma_ep_w || dma_err_q) && !eng_busy_w) begin
                    state_r <= S_HALT;
                end else if (eng_done_w) begin
                    state_r <= S_DECIDE;
                end else if (abort_q && !eng_busy_w) begin
                    abt_done_r <= 1'b1;      // abort 取消落定 → 仲裁
                    state_r <= S_DECIDE;
                end
            end
            S_DECIDE: begin
                // 仲裁判决已寄存（desc_done/done_cause 本拍可见）
                if (stopped_o || err_q)
                    state_r <= S_HALT;
                else
                    state_r <= S_IDLE;
            end
            S_HALT: state_r <= S_HALT;       // 粘着至复位
            default: state_r <= S_IDLE;
            endcase
        end
    end

endmodule
