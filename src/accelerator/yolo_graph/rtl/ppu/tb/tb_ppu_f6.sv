/************************************************************************
 * File Name       : tb_ppu_f6.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_ppu_f6
 * Description     : PPU-F6 walker/CSR 汇合门仿真 TB（replan §PPU-F6）。
 *   被测拓扑：yolo_desc_walker_f6（调度器，唯一发布源）+ ppu_shell_top
 *   （真件，req 来自 walker 派发）+ yolo_result_ring（真件环 FSM +
 *   yolo_ring_table 仿真替身）+ ppu_axi_bfm。描述符 port B 单读者：
 *   W_ENG 让渡期 mux 选 shell 侧地址，walker 探测期选 walker 侧。
 *   GEMM 后端 = TB 桩（记录派发序、可配延迟/错误注入、abort 取消）。
 *
 *   RUN=F6A：基础汇合门。tail=8 走 desc0..7（conv 桩 + view + ADD
 *          desc7 真引擎金样 f0）；队列空后 ffe → walker 发环（shell
 *          ring_publish==0 证发布权独占）；ack_consume 收尾。
 *   RUN=F6B：事件语义四连（v1.1 §7 优先序）：
 *          B1 stop 温和停 @desc16（当条完成后停、不发环、不再续走）；
 *          B2 stop+last @desc103（当条完成且发环）；
 *          B3 abort @desc7 中途（丢弃帧：不前进、无 done、不发环）；
 *          B4 ffe @desc16 中途（当条完成后立即发环、不再续走，
 *          shell 侧 ring_publish 同拍交叉核对）。
 *   RUN=F6C：全帧整网回放门。5 帧 × 104 描述符（63 GEMM 桩 + 41
 *          PPU：16 view 零流量 + 25 引擎任务帧参数化金样）；帧间不
 *          复位；每帧末 last→发环（seq/bytes/frame_id 逐帧核对）；
 *          GEMM 派发序 == ROM 卷积类升序；帧 1 后插 1 次 ack。
 *   RUN=F6D：协议负例 + 边界六连：
 *          D1 desc50 valid=0 → walker 侧描述符错（W_IDLE、不前进）；
 *          D2 desc50 opcode=0x20 → 非法码同路径（err_op=0x20）；
 *          D3 desc7 w5 双半字 quant id=0x200 → loader 步 7 错 →
 *             shell S_HALT 粘着 + walker W_ERR 粘着 → soft_reset
 *             仅释放 walker（shell 仍 halt，复位分层证）；
 *          D4 GEMM 桩错误注入 @desc5 → W_ERR 粘着 → soft_reset 释放；
 *          D5 circular depth=16 回绕 40 步（head==8、ffe 发环累加
 *             字节=回绕求和）；
 *          D6 环容量边界：tail=1 × 32 帧连发——31 次入环后第 32 次
 *             溢出（seq 仍前进=PS 可见间隙）；ack_drop×31 排空后
 *             空环 ack → ack_err 事件。
 *   派发序全局断言：req 脉冲严格按索引递增（环形取模）、opcode
 *   [7:4] 解复用类别与 ROM 一致、ppu_req |-> !shell.busy（无重叠
 *   派发，顺序屏障）。
 *   数据/金样全部来自 prep 工件（+PREP 目录，SHA 链自 F5AD），TB
 *   不自造期望（Σw14 期望从 desc_rom 现算）。
 *   marker：EES_SUMMARY + EES_MODELSIM_RESULT（ModelSim 过渡流）/
 *   EES_VIVADO_RESULT（xsim 主证流，+FLOW=vivado 门控）。
 * Dependencies    : yolo_desc_walker_f6 + ppu_shell_top + ppu_axi_bfm +
 *                   yolo_result_ring + yolo_ring_table(仿真替身)。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : PPU-F6 初版（F6A-F6D 四门）。
 ************************************************************************/

`timescale 1ns/1ps

module tb_ppu_f6;

    // ---- 时钟/复位 ----
    reg clk_r, rst_r;
    wire rst_n_w = ~rst_r;
    reg soft_r;                       // walker + ring 软复位（PS SOFT_RESET 镜像）

    initial begin clk_r = 1'b0; forever #5 clk_r = ~clk_r; end

    // ---- walker 控制（regfile 镜像）----
    reg         enable_r;
    reg         start_frame_r;        // pulse
    reg         stop_wk, abort_wk;    // pulse：同时喂 walker 与 shell
    reg         ffe_pend_r;           // walker 侧粘着（frame_end_pending）
    reg         ffe_sh_r;             // shell 侧脉冲
    reg  [15:0] tail_r;
    reg  [7:0]  depth_r;
    reg         circ_r;
    reg  [31:0] frame_id_r;

    // ---- shell 配置 ----
    reg  [31:0] head_base_r;
    reg  [23:0] tmo_cfg_r;
    reg  [2:0]  rd_os_r, wr_os_r;

    // ---- walker 互连（先声明后使用，防隐式网）----
    wire        wk_ffeclear_w, wk_idle_w, wk_run_w, wk_fdone_w;
    wire [15:0] wk_head_w, wk_cur_w, wk_done_w, wk_errid_w;
    wire [7:0]  wk_curop_w, wk_errop_w, wk_errdesc_w;
    wire        wk_ppureq_w, wk_greq_w, wk_pubv_w, wk_descev_w, wk_engev_w;
    wire [6:0]  wk_ppuidx_w, wk_gidx_w;
    wire [7:0]  wk_gop_w;
    wire [31:0] wk_bytes_w;
    wire [11:0] wk_addr_w;
    wire        wk_grant_w;

    // ---- GEMM 后端桩 ----
    reg         gemm_done_w, gemm_err_w, gemm_run_q;
    reg  [6:0]  gemm_cur_q;
    integer     gemm_cnt_q;
    integer     gemm_delay_i;         // 每描述符拍数（默认 8）
    integer     gemm_err_at_i;        // 错误注入描述符号（-1 关）
    int         gemm_log_q [$];

    // ---- shell 互连 ----
    wire [11:0] sh_addr_w;
    wire [31:0] desc_din_w;
    wire [9:0]  buf_addr_w, qt_addr_w;
    wire [31:0] buf_din_w, qt_din_w;

    wire [31:0] araddr_w; wire [3:0] arlen_w; wire [2:0] arsize_w;
    wire [1:0]  arburst_w; wire arvalid_w; wire arready_w;
    wire [63:0] rdata_w; wire [1:0] rresp_w; wire rlast_w;
    wire rvalid_w, rready_w;
    wire [31:0] awaddr_w; wire [3:0] awlen_w; wire [2:0] awsize_w;
    wire [1:0]  awburst_w; wire awvalid_w; wire awready_w;
    wire [63:0] wdata_w; wire [7:0] wstrb_w;
    wire wlast_w, wvalid_w, wready_w;
    wire [1:0] bresp_w; wire bvalid_w, bready_w;

    wire        busy_w, desc_done_w, ring_pub_w, stopped_w;
    wire [2:0]  cause_w;
    wire        ldr_ev_w, dma_ev_w, dma_halt_w, eng_busy_w;
    wire [3:0]  ldr_step_w, ldr_bit_w, dma_bit_w;
    wire [7:0]  ldr_code_w;

    // ---- result ring 互连 ----
    wire        ring_ready_w, ring_ne_w;
    wire        ring_done_evt_w, ring_ovf_evt_w, ring_ack_err_w;
    wire [7:0]  ring_head_w;
    wire [31:0] ring_seq_w, ring_fid_w, ring_bytes_w, ring_wdata_w;
    reg  [7:0]  ring_tail_r;
    reg         ack_consume_r, ack_drop_r;

    // 双流标记门控：ModelSim 过渡证据 vs xsim 主证（+FLOW=vivado）
    reg         vivado_flow = 1'b0;
    string      flow_s;
    integer     xz_err = 0;
    integer     fj;

    // ---- 表 ROM（1 拍同步读：addr k → din k+1，desc_if 合同）----
    reg [31:0] desc_rom [0:4095];
    reg [31:0] buf_rom  [0:1023];
    reg [31:0] qt_rom   [0:1023];
    reg [31:0] desc_din_r, buf_din_r, qt_din_r;

    // port B 单读者 mux：让渡期（W_ENG）选 shell，其余选 walker
    wire [11:0] desc_b_addr_w = wk_grant_w ? sh_addr_w : wk_addr_w;

    always @(posedge clk_r) begin
        desc_din_r <= desc_rom[desc_b_addr_w];
        buf_din_r  <= buf_rom [buf_addr_w];
        qt_din_r   <= qt_rom  [qt_addr_w];
    end
    assign desc_din_w = desc_din_r;
    assign buf_din_w  = buf_din_r;
    assign qt_din_w   = qt_din_r;

    // ---- walker（被测调度器）----
    yolo_desc_walker_f6 u_wk (
        .clk_i(clk_r), .rst_n(rst_n_w), .soft_reset_i(soft_r),
        .enable_i(enable_r), .start_frame_i(start_frame_r),
        .stop_i(stop_wk), .abort_i(abort_wk),
        .doorbell_commit_i(1'b0), .frame_end_pending_i(ffe_pend_r),
        .frame_end_clear_o(wk_ffeclear_w),
        .desc_tail_i(tail_r), .desc_count_i(tail_r),
        .desc_depth_i(depth_r), .desc_circular_i(circ_r),
        .walker_head_o(wk_head_w), .walker_current_o(wk_cur_w),
        .walker_done_o(wk_done_w), .walker_error_id_o(wk_errid_w),
        .cur_opcode_o(wk_curop_w),
        .walker_idle_o(wk_idle_w), .walker_running_o(wk_run_w),
        .walker_frame_done_o(wk_fdone_w),
        .desc_rd_addr_o(wk_addr_w), .desc_rd_data_i(desc_din_w),
        .port_grant_o(wk_grant_w),
        .ppu_req_valid_o(wk_ppureq_w), .ppu_desc_idx_o(wk_ppuidx_w),
        .ppu_busy_i(busy_w), .ppu_desc_done_i(desc_done_w),
        .ppu_stopped_i(stopped_w), .ppu_ldr_err_i(ldr_ev_w),
        .ppu_dma_halted_i(dma_halt_w),
        .gemm_req_valid_o(wk_greq_w), .gemm_desc_idx_o(wk_gidx_w),
        .gemm_opcode_o(wk_gop_w),
        .gemm_done_i(gemm_done_w), .gemm_err_i(gemm_err_w),
        .pub_valid_o(wk_pubv_w), .pub_ready_i(ring_ready_w),
        .pub_bytes_o(wk_bytes_w),
        .err_evt_desc_o(wk_descev_w), .err_op_o(wk_errop_w),
        .err_desc_id_o(wk_errdesc_w), .err_evt_eng_o(wk_engev_w)
    );

    // ---- shell（真件；req 来自 walker 派发）----
    ppu_shell_top dut (
        .clk_i(clk_r), .rst_i(rst_r),
        .req_i(wk_ppureq_w), .desc_idx_i(wk_ppuidx_w),
        .head_base_i(head_base_r),
        .stop_i(stop_wk), .abort_i(abort_wk), .ffe_i(ffe_sh_r),
        .timeout_cfg_i(tmo_cfg_r),
        .rd_outst_cfg_i(rd_os_r), .wr_outst_cfg_i(wr_os_r),
        .desc_addr_o(sh_addr_w), .desc_din_i(desc_din_w),
        .buf_addr_o(buf_addr_w),   .buf_din_i(buf_din_w),
        .qt_addr_o(qt_addr_w),     .qt_din_i(qt_din_w),
        .araddr_o(araddr_w), .arlen_o(arlen_w),
        .arsize_o(arsize_w), .arburst_o(arburst_w),
        .arvalid_o(arvalid_w), .arready_i(arready_w),
        .rdata_i(rdata_w), .rresp_i(rresp_w),
        .rlast_i(rlast_w), .rvalid_i(rvalid_w), .rready_o(rready_w),
        .awaddr_o(awaddr_w), .awlen_o(awlen_w),
        .awsize_o(awsize_w), .awburst_o(awburst_w),
        .awvalid_o(awvalid_w), .awready_i(awready_w),
        .wdata_o(wdata_w), .wstrb_o(wstrb_w),
        .wlast_o(wlast_w), .wvalid_o(wvalid_w), .wready_i(wready_w),
        .bresp_i(bresp_w), .bvalid_i(bvalid_w), .bready_o(bready_w),
        .busy_o(busy_w),
        .desc_done_o(desc_done_w), .ring_publish_o(ring_pub_w),
        .done_cause_o(cause_w), .stopped_o(stopped_w),
        .ldr_err_valid_o(ldr_ev_w), .ldr_err_step_o(ldr_step_w),
        .ldr_err_bit_o(ldr_bit_w), .ldr_err_code_o(ldr_code_w),
        .dma_err_valid_o(dma_ev_w), .dma_err_bit_o(dma_bit_w),
        .dma_halted_o(dma_halt_w), .eng_busy_o(eng_busy_w)
    );

    // ---- GEMM 桩逻辑（B3 通路占位合同：录序/延迟/错误注入/abort 取消）----
    always @(posedge clk_r or posedge rst_r) begin
        if (rst_r) begin
            gemm_done_w <= 1'b0; gemm_err_w <= 1'b0; gemm_run_q <= 1'b0;
            gemm_cnt_q  <= 0;     gemm_cur_q  <= 7'd0;
        end else begin
            gemm_done_w <= 1'b0;
            gemm_err_w  <= 1'b0;
            if (wk_greq_w) begin
                gemm_run_q <= 1'b1;
                gemm_cur_q <= wk_gidx_w;
                gemm_cnt_q <= 0;
                gemm_log_q.push_back(wk_gidx_w);
            end else if (gemm_run_q) begin
                if (abort_wk) begin
                    gemm_run_q <= 1'b0;          // abort 取消（帧丢弃）
                end else begin
                    gemm_cnt_q <= gemm_cnt_q + 1;
                    if (gemm_cnt_q >= gemm_delay_i) begin
                        gemm_run_q <= 1'b0;
                        if (gemm_err_at_i >= 0 && gemm_cur_q == gemm_err_at_i[6:0])
                            gemm_err_w <= 1'b1;
                        else
                            gemm_done_w <= 1'b1;
                    end
                end
            end
        end
    end

    // ---- AXI BFM ----
    wire [63:0] bfm_rd_cnt, bfm_wr_cnt;    // BFM 口为 longint：4 态网可接
    integer bfm_proto_err, bfm_unloaded;

    integer cfg_r_lat, cfg_fault_r_beat, cfg_stall_after;
    reg [1:0] cfg_fault_r_resp;
    integer cfg_fault_b_req, cfg_b_delay, cfg_w_stall;
    reg cfg_check_en;

    ppu_axi_bfm bfm (
        .clk_i(clk_r), .rst_i(rst_r),
        .arvalid_i(arvalid_w), .arready_o(arready_w),
        .araddr_i(araddr_w), .arlen_i(arlen_w),
        .rvalid_o(rvalid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w), .rready_i(rready_w),
        .awvalid_i(awvalid_w), .awready_o(awready_w),
        .awaddr_i(awaddr_w), .awlen_i(awlen_w),
        .wvalid_i(wvalid_w), .wready_o(wready_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w), .wlast_i(wlast_w),
        .bvalid_o(bvalid_w), .bresp_o(bresp_w), .bready_i(bready_w),
        .cfg_r_lat(cfg_r_lat), .cfg_fault_r_beat(cfg_fault_r_beat),
        .cfg_fault_r_resp(cfg_fault_r_resp),
        .cfg_stall_after(cfg_stall_after),
        .cfg_fault_b_req(cfg_fault_b_req), .cfg_b_delay(cfg_b_delay),
        .cfg_w_stall(cfg_w_stall), .cfg_check_en(cfg_check_en),
        .rd_cnt(bfm_rd_cnt), .wr_cnt(bfm_wr_cnt),
        .proto_err(bfm_proto_err), .unloaded_cnt(bfm_unloaded)
    );

    // ---- result ring（真件 FSM + 仿真替身表）----
    yolo_result_ring u_ring (
        .clk_i(clk_r), .rst_n(rst_n_w), .soft_reset_i(soft_r),
        .pub_valid_i(wk_pubv_w), .pub_ready_o(ring_ready_w),
        .pub_frame_id_i(frame_id_r),
        .pub_head_base_i({32'h0, head_base_r}),
        .pub_head_bytes_i(wk_bytes_w),
        .pub_quant_profile_i(8'h0), .pub_stride_mask_i(8'h0),
        .pub_done_evt_o(ring_done_evt_w),
        .pub_overflow_evt_o(ring_ovf_evt_w),
        .tail_ptr_i(ring_tail_r),
        .ack_consume_i(ack_consume_r), .ack_drop_i(ack_drop_r),
        .ack_err_evt_o(ring_ack_err_w),
        .head_ptr_o(ring_head_w), .not_empty_o(ring_ne_w),
        .seq_o(ring_seq_w),
        .last_frame_id_o(ring_fid_w), .last_head_bytes_o(ring_bytes_w),
        .win_addr_i(9'd0), .win_data_o(ring_wdata_w)
    );

    // ---- ffe 粘着消费镜像（regfile 行为：clear 脉冲清粘着）----
    always @(posedge clk_r) begin
        if (wk_ffeclear_w) ffe_pend_r <= 1'b0;
    end

    // ---- 事件计数 ----
    integer ring_pub_cnt, ring_ovf_cnt, ring_ack_cnt;
    integer shell_pub_cnt, desc_evt_cnt, eng_evt_cnt;
    integer errors, checks;
    reg [7:0] desc_evt_op, desc_evt_id;

    always @(posedge clk_r) begin
        if (!rst_r) begin
            if (ring_done_evt_w) ring_pub_cnt = ring_pub_cnt + 1;
            if (ring_ovf_evt_w)  ring_ovf_cnt = ring_ovf_cnt + 1;
            if (ring_ack_err_w)  ring_ack_cnt = ring_ack_cnt + 1;
            if (ring_pub_w)      shell_pub_cnt = shell_pub_cnt + 1;
            if (wk_descev_w) begin
                desc_evt_cnt = desc_evt_cnt + 1;
                desc_evt_op  = wk_errop_w;
                desc_evt_id  = wk_errdesc_w;
            end
            if (wk_engev_w) eng_evt_cnt = eng_evt_cnt + 1;
        end
    end

    // ---- 派发序全局断言：严格按索引递增（环形取模）+ 类别一致 +
    //      无重叠派发（顺序屏障：ppu_req |-> !shell.busy）----
    int last_disp_idx;
    int ppu_log_q [$];
    int chk_got_idx, chk_exp_idx;
    reg [31:0] chk_w0;
    reg [7:0] chk_rom_op;
    reg chk_got_ppu;

    always @(posedge clk_r) begin
        if (!rst_r) begin
            if (wk_ppureq_w && wk_greq_w)
                fail("同拍双后端派发（walker 解复须互斥）");
            else if (wk_ppureq_w || wk_greq_w) begin
                chk_got_ppu = wk_ppureq_w;
                chk_got_idx = chk_got_ppu ? wk_ppuidx_w : wk_gidx_w;
                chk_exp_idx = circ_r
                    ? ((last_disp_idx + 1) % ((depth_r == 0) ? 128 : depth_r))
                    : (last_disp_idx + 1);
                chk_w0      = desc_rom[32 * chk_got_idx];
                chk_rom_op  = chk_w0[7:0];
                if (chk_got_idx != chk_exp_idx)
                    fail($sformatf("派发序断裂：得 desc%0d 期 %0d",
                                   chk_got_idx, chk_exp_idx));
                if (chk_got_ppu != (chk_rom_op[7:4] == 4'h1))
                    fail($sformatf("desc%0d 解复用类别错：op=%02X %s",
                                   chk_got_idx, chk_rom_op,
                                   chk_got_ppu ? "走PPU" : "走GEMM"));
                if (chk_got_ppu && busy_w)
                    fail($sformatf("desc%0d 派发时 shell 仍 busy（重叠派发）",
                                   chk_got_idx));
                if (chk_got_ppu)
                    ppu_log_q.push_back(chk_got_idx);
                last_disp_idx = chk_got_idx;
            end
        end
    end

    string prep_dir, run_s;

    task automatic fail(string s);
        begin
            errors = errors + 1;
            $display("[%0t] FAIL: %s", $time, s);
        end
    endtask

    task automatic do_reset(int n);
        begin
            rst_r <= 1'b1;
            repeat (n) @(posedge clk_r);
            rst_r <= 1'b0;
            repeat (2) @(posedge clk_r);
        end
    endtask

    // ---- walker 控制（regfile 镜像脉冲）----
    task automatic start_frame;
        begin
            gemm_log_q.delete();
            ppu_log_q.delete();
            last_disp_idx = -1;
            @(negedge clk_r);
            start_frame_r <= 1'b1;
            @(negedge clk_r);
            start_frame_r <= 1'b0;
        end
    endtask

    task automatic pulse_stop;
        begin
            @(negedge clk_r); stop_wk <= 1'b1;
            @(negedge clk_r); stop_wk <= 1'b0;
        end
    endtask

    task automatic pulse_abort;
        begin
            @(negedge clk_r); abort_wk <= 1'b1;
            @(negedge clk_r); abort_wk <= 1'b0;
        end
    endtask

    task automatic pulse_ffe;
        begin
            @(negedge clk_r); ffe_sh_r <= 1'b1; ffe_pend_r <= 1'b1;
            @(negedge clk_r); ffe_sh_r <= 1'b0;
        end
    endtask

    task automatic pulse_soft;
        begin
            @(negedge clk_r); soft_r <= 1'b1;
            @(negedge clk_r); soft_r <= 1'b0;
        end
    endtask

    // ack 脉冲先于尾指针前进（regfile 时序：脉冲拍用旧尾判空）。
    // 尾指针 NBA 落地后任务才返回：防调用方同拍阻塞写（cfg_default）
    // 先写 0 再被 NBA 踩回 1，造成 D6 起始 tail=1 假满环。
    task automatic ack_consume;
        begin
            @(negedge clk_r); ack_consume_r <= 1'b1;
            @(negedge clk_r); ack_consume_r <= 1'b0;
            ring_tail_r <= ring_tail_r + 8'd1;
            @(negedge clk_r);   // NBA 落地拍
        end
    endtask

    task automatic ack_drop;
        begin
            @(negedge clk_r); ack_drop_r <= 1'b1;
            @(negedge clk_r); ack_drop_r <= 1'b0;
            ring_tail_r <= ring_tail_r + 8'd1;
            @(negedge clk_r);   // NBA 落地拍
        end
    endtask

    // 终局失败收口：按流打印对应终标记后停仿真（超时/看门狗共用）
    task automatic final_fail(input string s);
        begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT FAIL %s", s);
            else
                $display("EES_VIVADO_RESULT FAIL %s", s);
            $finish;
        end
    endtask

    // ---- 等待原语 ----
    task automatic wait_walk_done(input int n, input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (wk_done_w == n) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: walker_done==%0d 超时 %0d 拍", tag, n, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_idle(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (wk_idle_w) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: walker idle 超时 %0d 拍", tag, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            // 2 拍落定：idle 与 err_evt 同拍置起时，监视器（计数/锁存）
            // 与本任务的唤醒同沿竞争——xsim 下主进程先跑会读到旧计数
            // （D1/D2 事件计数 0 假失败实测）；让监视器先落再返回。
            repeat (2) @(posedge clk_r);
            checks = checks + 1;
        end
    endtask

    task automatic wait_eng_busy(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (eng_busy_w) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: eng_busy 超时 %0d 拍", tag, tmo));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_ring_pub(input int n, input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (ring_pub_cnt == n) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: 环发布计数==%0d 超时", tag, n));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_ring_ovf(input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (ring_ovf_cnt >= 1) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: 环溢出事件超时", tag));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic wait_evt_cnt(input int n, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (eng_evt_cnt >= n) break;
                t = t + 1;
                if (t > 300000) begin
                    fail($sformatf("%s: 引擎错误事件超时", tag));
                    final_fail($sformatf("%s timeout", tag));
                end
            end
            checks = checks + 1;
        end
    endtask

    task automatic check_no_resume(input int cyc, input int dn, input string tag);
        int t;
        reg ok;
        begin
            t = 0; ok = 1'b1;
            while (t < cyc && ok) begin
                @(posedge clk_r);
                if (!wk_idle_w || wk_done_w != dn) begin
                    fail($sformatf("%s: 停后 %0d 拍内自行续走（done=%0d 期停于 %0d）",
                                   tag, t, wk_done_w, dn));
                    ok = 1'b0;
                end
                t = t + 1;
            end
            if (ok) checks = checks + 1;
        end
    endtask

    function automatic bit in_list(int v, int q [$]);
        begin
            in_list = 1'b0;
            foreach (q[k])
                if (q[k] == v) in_list = 1'b1;
        end
    endfunction

    // Σw14：索引区间 [lo,hi]（含）
    function automatic longint unsigned sum_range(int lo, int hi);
        int i;
        begin
            sum_range = 0;
            for (i = lo; i <= hi; i = i + 1)
                sum_range = sum_range + desc_rom[32 * i + 14];
        end
    endfunction

    // Σw14：环形走 n 步（第 i 步描述符号 = i % depth）
    function automatic longint unsigned sum_wrap(int n, int depth);
        int i;
        begin
            sum_wrap = 0;
            for (i = 0; i < n; i = i + 1)
                sum_wrap = sum_wrap + desc_rom[32 * (i % depth) + 14];
        end
    endfunction

    // ---- 金样窗口比对（addr/data/strb 逐拍；fr>=0 → 帧参数化文件名）----
    task automatic cmp_golden(string kind, int di,
                              longint unsigned mark, string tag,
                              int fr = -1);
        int fd, n, code;
        string f, why;
        bit [31:0] ea; bit [63:0] ed; bit [7:0] es;
        longint unsigned got, sz;
        begin
            f = (fr < 0) ? $sformatf("%s/%s_golden_%0d.txt", prep_dir, kind, di)
                         : $sformatf("%s/%s_golden_f%0d_%0d.txt",
                                     prep_dir, kind, fr, di);
            fd = $fopen(f, "r");
            if (fd == 0) begin
                fail($sformatf("%s: 打不开 %s", tag, f));
                return;
            end
            sz  = (kind == "rd") ? bfm.rd_n
                                 : bfm.wr_n;
            n   = 0;
            why = "";
            code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            while (code == 3 && why == "") begin
                if (mark + n >= sz)
                    why = $sformatf("拍数不足：log=%0d 期望≥%0d",
                                    sz - mark, n + 1);
                else if (kind == "rd") begin
                    if (bfm.rd_addr_lg[mark+n] != ea ||
                        bfm.rd_data_lg[mark+n] != ed)
                        why = $sformatf("rd 拍%0d: 得 %08X/%016X 期 %08X/%016X",
                            n, bfm.rd_addr_lg[mark+n], bfm.rd_data_lg[mark+n],
                            ea, ed);
                end else begin
                    if (bfm.wr_addr_lg[mark+n] != ea ||
                        bfm.wr_data_lg[mark+n] != ed ||
                        bfm.wr_strb_lg[mark+n] != es)
                        why = $sformatf("wr 拍%0d: 得 %08X/%016X/%02X 期 %08X/%016X/%02X",
                            n, bfm.wr_addr_lg[mark+n], bfm.wr_data_lg[mark+n],
                            bfm.wr_strb_lg[mark+n], ea, ed, es);
                end
                n = n + 1;
                code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            end
            $fclose(fd);
            got = sz - mark;
            if (why != "")
                fail($sformatf("%s: desc%0d %s %s", tag, di, kind, why));
            else if (got != n)
                fail($sformatf("%s: desc%0d %s 拍数 得%0d 期%0d",
                               tag, di, kind, got, n));
            else begin
                checks = checks + 2;
                $display("[%0t] %s desc%0d %s BITEXACT %0d 拍",
                         $time, tag, di, kind, n);
            end
        end
    endtask

    // ---- 走到 walker_done==n：逐描述符滑动金样窗 ----
    // 引擎任务（eng_q 成员且非 skip_cmp）比对 rd/wr 金样；conv 桩与
    // view 均须零 AXI 流量。返回末窗标 g_rm/g_wm（供当条任务比对）。
    longint unsigned g_rm, g_wm;
    int eng_q [$];

    task automatic walk_mark(input int n, input int fr, input string tag,
                             input int skip_cmp);
        longint unsigned rm, wm;
        int i;
        begin
            rm = bfm.rd_n;
            wm = bfm.wr_n;
            for (i = 0; i < n; i = i + 1) begin
                wait_walk_done(i + 1, 3_000_000, $sformatf("%s d%0d", tag, i));
                if (in_list(i, eng_q) && i != skip_cmp) begin
                    cmp_golden("rd", i, rm, tag, fr);
                    cmp_golden("wr", i, wm, tag, fr);
                end else begin
                    if (bfm.rd_n != rm || bfm.wr_n != wm)
                        fail($sformatf("%s: desc%0d 非金样任务出现 AXI 流量（rd %0d→%0d wr %0d→%0d）",
                            tag, i, rm, bfm.rd_n,
                            wm, bfm.wr_n));
                    else checks = checks + 1;
                end
                rm = bfm.rd_n;
                wm = bfm.wr_n;
            end
            g_rm = rm;
            g_wm = wm;
        end
    endtask

    // ---- GEMM 派发序核对：== ROM 卷积类（[7:4]==0）升序（前 lim 条内）----
    task automatic check_gemm_log(input int lim, input string tag);
        int i;
        int exp_q [$];
        begin
            for (i = 0; i < lim; i = i + 1)
                if (desc_rom[32 * i][7:4] == 4'h0)
                    exp_q.push_back(i);
            if (gemm_log_q.size() != exp_q.size())
                fail($sformatf("%s: GEMM 派发数 得%0d 期%0d",
                               tag, gemm_log_q.size(), exp_q.size()));
            else begin
                for (i = 0; i < exp_q.size(); i = i + 1)
                    if (gemm_log_q[i] != exp_q[i])
                        fail($sformatf("%s: GEMM 派发序[%0d] 得%0d 期%0d",
                                       tag, i, gemm_log_q[i], exp_q[i]));
                checks = checks + 1;
            end
        end
    endtask

    // ---- 缺省配置 ----
    task automatic cfg_default;
        begin
            cfg_r_lat        = 2;
            cfg_fault_r_beat = 0;
            cfg_fault_r_resp = 2'b10;
            cfg_stall_after  = 0;
            cfg_fault_b_req  = 0;
            cfg_b_delay      = 2;
            cfg_w_stall      = 0;
            cfg_check_en     = 1'b1;
            tmo_cfg_r        = 24'd100;
            rd_os_r          = 3'd4;
            wr_os_r          = 3'd4;
            stop_wk          = 1'b0;
            abort_wk         = 1'b0;
            ffe_sh_r         = 1'b0;
            ffe_pend_r       = 1'b0;
            soft_r           = 1'b0;
            start_frame_r    = 1'b0;
            head_base_r      = 32'h1F80_0000;
            enable_r         = 1'b1;
            tail_r           = 16'd104;
            depth_r          = 8'd0;
            circ_r           = 1'b0;
            frame_id_r       = 32'd0;
            ring_tail_r      = 8'd0;
            ack_consume_r    = 1'b0;
            ack_drop_r       = 1'b0;
            gemm_delay_i     = 8;
            gemm_err_at_i    = -1;
        end
    endtask

    // ---- 子程公共计数清零 ----
    task automatic clr_evt;
        begin
            ring_pub_cnt = 0; ring_ovf_cnt = 0; ring_ack_cnt = 0;
            shell_pub_cnt = 0; desc_evt_cnt = 0; eng_evt_cnt = 0;
        end
    endtask

    // ================= RUN F6A =================
    // 基础汇合门：tail=8 走 desc0..7（conv 桩 + view 零流量 + ADD desc7
    // 真引擎金样）；队列空 spin → ffe → walker 发环；shell 侧
    // ring_publish 必须为 0（发布权独占证）；ack_consume 收尾。
    task automatic run_f6a;
        reg [31:0] exp_bytes;
        begin
            eng_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                      47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload_f0.txt"});
            cfg_default;
            do_reset(5);
            clr_evt;
            tail_r = 16'd8;
            $display("[RUN F6A] tail=8 走 desc0..7（conv 桩+view+ADD 真引擎）");
            start_frame;
            walk_mark(8, 0, "F6A", -1);
            // 队列空：walker 停在 W_CHK 轮询（未 idle、未发环）
            if (wk_idle_w)     fail("F6A: 队列空后 walker 提前 idle（应 W_CHK 轮询）");
            if (wk_head_w != 16'd8 || wk_done_w != 16'd8)
                fail($sformatf("F6A: head/done 得 %0d/%0d 期 8/8", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0 || shell_pub_cnt != 0)
                fail("F6A: ffe 前出现发环");
            checks = checks + 3;
            // ffe → 发环
            pulse_ffe;
            wait_ring_pub(1, 100000, "F6A");
            exp_bytes = sum_range(0, 7);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("F6A: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1)      fail("F6A: seq != 1");
            if (ring_fid_w != 32'd0)      fail("F6A: frame_id != 0");
            if (shell_pub_cnt != 0)       fail("F6A: shell 侧出现 ring_publish（发布权须独占于 walker）");
            if (ffe_pend_r !== 1'b0)      fail("F6A: ffe 粘着未被 frame_end_clear 消费");
            checks = checks + 5;
            wait_idle(1000, "F6A");
            check_gemm_log(8, "F6A");
            check_no_resume(200, 8, "F6A");
            ack_consume;
            repeat (2) @(posedge clk_r);   // 尾指针 NBA 落地后再查空
            if (ring_ne_w) fail("F6A: ack 后环仍非空");
            else checks = checks + 1;
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F6A] 完：8 描述符 / GEMM 桩 %0d / PPU %0d / 发环 1 / rd %0d wr %0d",
                     gemm_log_q.size(), ppu_log_q.size(),
                     bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= RUN F6B =================
    // 事件语义四连（v1.1 §7 优先序的 walker↔shell 联动）。
    task automatic run_f6b;
        reg [31:0] exp_bytes;
        begin
            eng_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                      47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload_f0.txt"});

            // ---- B1：stop 温和停 @desc16（当条完成后停）----
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6B/B1] stop 温和停 @desc16");
            start_frame;
            walk_mark(16, 0, "F6B1", -1);
            wait_eng_busy(100000, "F6B1");
            pulse_stop;
            wait_walk_done(17, 3_000_000, "F6B1 stop后当条完成");
            cmp_golden("rd", 16, g_rm, "F6B1", 0);
            cmp_golden("wr", 16, g_wm, "F6B1", 0);
            wait_idle(1000, "F6B1");
            if (!stopped_w)            fail("B1: shell stopped 未置位");
            if (wk_head_w != 16'd17 || wk_done_w != 16'd17)
                fail($sformatf("B1: head/done 得 %0d/%0d 期 17/17", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0)     fail("B1: 温和停（非 last）不得发环");
            checks = checks + 3;
            check_no_resume(500, 17, "B1");

            // ---- B2：stop+last @desc103（当条完成且发环）----
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6B/B2] stop+last @desc103（整帧走完）");
            start_frame;
            walk_mark(103, 0, "F6B2", -1);
            wait_eng_busy(500000, "F6B2");
            pulse_stop;
            wait_walk_done(104, 3_000_000, "F6B2 stop后当条完成");
            cmp_golden("rd", 103, g_rm, "F6B2", 0);
            cmp_golden("wr", 103, g_wm, "F6B2", 0);
            wait_ring_pub(1, 100000, "F6B2");
            exp_bytes = sum_range(0, 103);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("B2: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1)  fail("B2: seq != 1");
            if (!stopped_w)           fail("B2: shell stopped 未置位");
            if (wk_head_w != 16'd104) fail("B2: head != 104");
            checks = checks + 4;
            wait_idle(1000, "F6B2");
            ack_consume;

            // ---- B3：abort @desc7 中途（丢弃帧）----
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6B/B3] abort 中途丢弃 @desc7");
            start_frame;
            walk_mark(7, 0, "F6B3", 7);        // desc7 自身不比（中断）
            wait_eng_busy(100000, "F6B3");
            repeat (200) @(posedge clk_r);     // 走进引擎中段再 abort
            pulse_abort;
            wait_idle(300000, "F6B3 abort落定");
            if (!stopped_w) fail("B3: shell stopped 未置位");
            if (wk_head_w != 16'd7 || wk_done_w != 16'd7)
                fail($sformatf("B3: abort 不得前进（head/done 得 %0d/%0d 期 7/7）",
                               wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0)   fail("B3: abort 帧不得发环");
            if (desc_evt_cnt != 0 || eng_evt_cnt != 0)
                fail("B3: abort 不是错误事件（desc/eng evt 须为 0）");
            checks = checks + 4;
            check_no_resume(500, 7, "B3");

            // ---- B4：ffe @desc16 中途（当条完成后立即发环）----
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6B/B4] ffe 中途强发环 @desc16");
            start_frame;
            walk_mark(16, 0, "F6B4", -1);
            wait_eng_busy(100000, "F6B4");
            pulse_ffe;
            wait_walk_done(17, 3_000_000, "F6B4 当条完成");
            cmp_golden("rd", 16, g_rm, "F6B4", 0);
            cmp_golden("wr", 16, g_wm, "F6B4", 0);
            wait_ring_pub(1, 100000, "F6B4");
            exp_bytes = sum_range(0, 16);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("B4: 环字节 得 %0d 期 %0d", ring_bytes_w, exp_bytes));
            if (ring_seq_w != 32'd1)  fail("B4: seq != 1");
            if (stopped_w)            fail("B4: ffe 非终态事件，stopped 须为 0");
            if (wk_head_w != 16'd17)  fail("B4: head != 17");
            if (shell_pub_cnt != 1)   fail("B4: shell 侧 ring_publish 须恰好 1（当条 ffe 判决交叉核对）");
            checks = checks + 5;
            wait_idle(1000, "F6B4");
            check_no_resume(500, 17, "B4");
            ack_consume;

            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 1;
            if (bfm_proto_err != 0)
                $display("[RUN F6B] 注：abort 中断在途致 AXI 协议计数 %0d（F3 B2 同例，报告不判死）",
                         bfm_proto_err);
            $display("[RUN F6B] 完：B1-B4 四事件语义核对毕 / rd %0d wr %0d",
                     bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ================= RUN F6C =================
    // 全帧整网回放门：5 帧 × 104 描述符（63 GEMM 桩 + 41 PPU）连发，
    // 帧间不复位；每帧 25 引擎任务帧参数化金样 + view/conv 零流量 +
    // GEMM 派发序 == ROM 卷积升序；帧末 last 发环逐帧核对；帧 1 后
    // 插 1 次 ack_consume。
    task automatic run_f6c;
        int k;
        reg [31:0] exp_bytes;
        begin
            eng_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                      47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            cfg_default;
            do_reset(5);               // 全程唯一一次复位（帧间不复位）
            clr_evt;
            for (k = 0; k < 5; k = k + 1) begin
                bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", k)});
                frame_id_r = k;
                $display("[RUN F6C] 帧%0d：104 描述符整网连发（63 GEMM 桩 + 41 PPU）", k);
                start_frame;
                walk_mark(104, k, $sformatf("F6C f%0d", k), -1);
                // desc103=last → W_PUB 自动发环
                wait_ring_pub(k + 1, 200000, $sformatf("F6C f%0d", k));
                exp_bytes = sum_range(0, 103);
                if (ring_bytes_w != exp_bytes)
                    fail($sformatf("帧%0d 环字节 得 %0d 期 %0d", k, ring_bytes_w, exp_bytes));
                if (ring_seq_w != k + 1)
                    fail($sformatf("帧%0d seq 得 %0d 期 %0d", k, ring_seq_w, k + 1));
                if (ring_fid_w != k)
                    fail($sformatf("帧%0d frame_id 得 %0d", k, ring_fid_w));
                if (shell_pub_cnt != k + 1)
                    fail($sformatf("帧%0d shell 侧 ring_publish 计数 %0d 期 %0d（逐帧各 1）",
                                   k, shell_pub_cnt, k + 1));
                checks = checks + 4;
                check_gemm_log(104, $sformatf("F6C f%0d", k));
                wait_idle(1000, $sformatf("F6C f%0d", k));
                if (k == 1) ack_consume;   // 帧 1 后插 1 次消费
                $display("[RUN F6C] 帧%0d 完：发环 %0d / GEMM 桩 %0d / PPU %0d / rd %0d wr %0d",
                         k, ring_pub_cnt, gemm_log_q.size(), ppu_log_q.size(),
                         bfm.rd_n, bfm.wr_n);
            end
            if (ring_pub_cnt != 5)
                fail($sformatf("全回放发环数=%0d 期 5", ring_pub_cnt));
            else checks = checks + 1;
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
        end
    endtask

    // ================= RUN F6D =================
    // 协议负例 + 边界六连。
    task automatic run_f6d;
        int i;
        reg [31:0] exp_bytes;
        begin
            eng_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                      47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload_f0.txt"});

            // ---- D1：desc50 valid=0 → walker 侧描述符错 ----
            $readmemh({prep_dir, "/desc_table_D1.hex"}, desc_rom);
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6D/D1] desc50 valid=0");
            start_frame;
            wait_idle(5_000_000, "D1 错误落定");
            if (desc_evt_cnt != 1)    fail($sformatf("D1: 描述符错事件 得%0d 期1", desc_evt_cnt));
            if (wk_errid_w != 16'd50) fail($sformatf("D1: walker_error_id 得 %0d 期 50", wk_errid_w));
            if (desc_evt_id != 8'd50) fail($sformatf("D1: err_desc_id 得 %0d 期 50", desc_evt_id));
            if (wk_head_w != 16'd50 || wk_done_w != 16'd50)
                fail($sformatf("D1: head/done 得 %0d/%0d 期 50/50", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0 || eng_evt_cnt != 0)
                fail("D1: 不得发环/引擎错");
            checks = checks + 5;
            check_no_resume(300, 50, "D1");

            // ---- D2：desc50 opcode=0x20 → 非法码同路径 ----
            $readmemh({prep_dir, "/desc_table_D2.hex"}, desc_rom);
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6D/D2] desc50 opcode=0x20（非法）");
            start_frame;
            wait_idle(5_000_000, "D2 错误落定");
            if (desc_evt_cnt != 1)      fail($sformatf("D2: 描述符错事件 得%0d 期1", desc_evt_cnt));
            if (desc_evt_op != 8'h20)   fail($sformatf("D2: err_op 得 %02X 期 20", desc_evt_op));
            if (wk_errid_w != 16'd50)   fail("D2: walker_error_id != 50");
            if (wk_head_w != 16'd50 || wk_done_w != 16'd50)
                fail("D2: head/done 须停于 50/50");
            if (ring_pub_cnt != 0)      fail("D2: 不得发环");
            checks = checks + 5;
            check_no_resume(300, 50, "D2");

            // ---- D3：desc7 w5 quant id=0x200 → loader 步 7 错 → W_ERR ----
            $readmemh({prep_dir, "/desc_table_D3.hex"}, desc_rom);
            cfg_default;
            do_reset(5);
            clr_evt;
            $display("[RUN F6D/D3] desc7 quant id 越界 → loader 错 → W_ERR");
            start_frame;
            wait_evt_cnt(1, "D3 引擎错误事件");
            repeat (300) @(posedge clk_r);     // W_ERR 须粘着（非 idle）
            if (wk_idle_w)          fail("D3: W_ERR 不得自行回 idle");
            if (!wk_run_w)          fail("D3: W_ERR 期 running 须为 1");
            if (wk_head_w != 16'd7 || wk_done_w != 16'd7)
                fail($sformatf("D3: head/done 得 %0d/%0d 期 7/7", wk_head_w, wk_done_w));
            if (!busy_w)            fail("D3: shell 未粘着（S_HALT 期 busy 须为 1；loader 错先于 DMA 启动，dma_halted 恒 0 属正常）");
            if (ring_pub_cnt != 0)  fail("D3: 引擎错不得发环");
            checks = checks + 6;
            pulse_soft;                            // 软复位仅释放 walker
            wait_idle(1000, "D3 soft_reset 释放");
            if (!busy_w)           fail("D3: soft_reset 不得释放 shell halt（复位分层）");
            else checks = checks + 1;

            // ---- D4：GEMM 桩错误注入 @desc5 → W_ERR ----
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            cfg_default;
            do_reset(5);
            clr_evt;
            gemm_err_at_i = 5;
            $display("[RUN F6D/D4] GEMM err 注入 @desc5 → W_ERR");
            start_frame;
            wait_evt_cnt(1, "D4 引擎错误事件");
            repeat (300) @(posedge clk_r);
            if (wk_idle_w)          fail("D4: W_ERR 不得自行回 idle");
            if (wk_head_w != 16'd5 || wk_done_w != 16'd5)
                fail($sformatf("D4: head/done 得 %0d/%0d 期 5/5", wk_head_w, wk_done_w));
            if (ring_pub_cnt != 0)  fail("D4: 引擎错不得发环");
            checks = checks + 4;
            pulse_soft;
            wait_idle(1000, "D4 soft_reset 释放");
            gemm_err_at_i = -1;
            check_no_resume(300, 0, "D4");   // soft_reset 清零 done，基准 0

            // ---- D5：circular depth=16 回绕 40 步 ----
            cfg_default;
            do_reset(5);
            clr_evt;
            depth_r = 8'd16;
            circ_r  = 1'b1;
            tail_r  = 16'd16;
            $display("[RUN F6D/D5] 环形 depth=16 回绕 40 步");
            start_frame;
            wait_walk_done(40, 3_000_000, "D5 回绕 40 步");
            if (wk_head_w != 16'd8)
                fail($sformatf("D5: 40 步回绕后 head 得 %0d 期 8（40 mod 16）", wk_head_w));
            else checks = checks + 1;
            // 环形队列非空（head=8 != tail=16）：ffe 后先走完当条
            // desc8（ADD，第 41 步=再次回绕到 8）再发环——v1.1 §7 语义
            pulse_ffe;
            wait_walk_done(41, 3_000_000, "D5 ffe 当条完成");
            wait_ring_pub(1, 200000, "D5");
            exp_bytes = sum_wrap(41, 16);
            if (ring_bytes_w != exp_bytes)
                fail($sformatf("D5: 环字节 得 %0d 期 %0d（回绕求和）", ring_bytes_w, exp_bytes));
            else checks = checks + 1;
            wait_idle(1000, "D5");
            ack_consume;

            // ---- D6：环容量边界（31 入环 + 第 32 溢出 + 空环 ack 错）----
            cfg_default;
            do_reset(5);
            clr_evt;
            tail_r = 16'd1;           // 仅 desc0（conv 桩）
            $display("[RUN F6D/D6] 环容量边界：tail=1 × 32 帧连发");
            for (i = 0; i < 32; i = i + 1) begin
                frame_id_r = i;
                ffe_pend_r = 1'b1;    // 帧内 desc0 完成后即发环
                start_frame;
                if (i < 31) wait_ring_pub(i + 1, 100000, $sformatf("D6 pub%0d", i));
                else        wait_ring_ovf(100000, "D6 第32次满环丢弃");
            end
            if (ring_pub_cnt != 31)
                fail($sformatf("D6: 入环计数 得%0d 期31", ring_pub_cnt));
            if (ring_ovf_cnt != 1)
                fail($sformatf("D6: 溢出计数 得%0d 期1（第 32 次满环丢弃）", ring_ovf_cnt));
            if (ring_seq_w != 32'd32)
                fail($sformatf("D6: seq 得 %0d 期 32（溢出间隙可见）", ring_seq_w));
            if (ring_head_w != 8'd31)
                fail($sformatf("D6: head_ptr 得 %0d 期 31", ring_head_w));
            checks = checks + 4;
            for (i = 0; i < 31; i = i + 1) ack_drop;
            repeat (2) @(posedge clk_r);   // 尾指针 NBA 落地后再查空
            if (ring_ne_w) fail("D6: 排空后环仍非空");
            else checks = checks + 1;
            ack_consume;              // 空环 ack → 协议错
            repeat (2) @(posedge clk_r);   // 错事件计数落地后再查
            if (ring_ack_cnt != 1)
                fail($sformatf("D6: 空环 ack 错事件 得%0d 期1", ring_ack_cnt));
            else checks = checks + 1;

            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 1;
            if (bfm_proto_err != 0)
                $display("[RUN F6D] 注：AXI 协议计数 %0d（负例中断在途，报告不判死）",
                         bfm_proto_err);
            $display("[RUN F6D] 完：D1-D6 六连毕 / rd %0d wr %0d",
                     bfm.rd_n, bfm.wr_n);
        end
    endtask

    // ---- 主控 ----
    initial begin
        errors = 0; checks = 0;
        ring_pub_cnt = 0; ring_ovf_cnt = 0; ring_ack_cnt = 0;
        shell_pub_cnt = 0; desc_evt_cnt = 0; eng_evt_cnt = 0;
        last_disp_idx = -1;
        enable_r = 1'b1;
        start_frame_r = 1'b0;
        stop_wk = 1'b0; abort_wk = 1'b0;
        ffe_sh_r = 1'b0; ffe_pend_r = 1'b0;
        soft_r = 1'b0;
        if (!$value$plusargs("PREP=%s", prep_dir))
            prep_dir = "E:/competition/4_metrics/logs/2026-09-23_yolo_ppu_f6_walker_run01/prep";
        if (!$value$plusargs("RUN=%s", run_s)) run_s = "F6A";
        if ($value$plusargs("FLOW=%s", flow_s)) vivado_flow = (flow_s == "vivado");
        cfg_default;
        rst_r = 1'b1;

        case (run_s)
        "F6A": run_f6a;
        "F6B": run_f6b;
        "F6C": run_f6c;
        "F6D": run_f6d;
        default: begin
            $display("FATAL: 未知 RUN=%s", run_s);
            final_fail("bad-run");
        end
        endcase

        if (bfm_proto_err != 0 && run_s != "F6B" && run_s != "F6D")
            fail($sformatf("协议违例 %0d", bfm_proto_err));
        if (xz_err != 0)
            fail($sformatf("控制面 X/Z 污染 %0d 拍", xz_err));
        $display("EES_SUMMARY run=%s checks=%0d errors=%0d rd=%0d wr=%0d",
                 run_s, checks, errors,
                 bfm.rd_n, bfm.wr_n);
        if (vivado_flow) begin
            // xsim 主证流：run 本地结果文件（启动器清单覆盖）
            fj = $fopen("f6_result.json", "w");
            $fdisplay(fj, "{\"run\":\"%s\",\"checks\":%0d,\"errors\":%0d}",
                      run_s, checks, errors);
            $fclose(fj);
        end
        if (errors == 0) begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT PASS ppu_f6_walker run=%s", run_s);
            else
                $display("EES_VIVADO_RESULT PASS ppu_f6_walker run=%s", run_s);
        end else begin
            if (!vivado_flow)
                $display("EES_MODELSIM_RESULT FAIL ppu_f6_walker run=%s errors=%0d",
                         run_s, errors);
            else
                $display("EES_VIVADO_RESULT FAIL ppu_f6_walker run=%s errors=%0d",
                         run_s, errors);
        end
        $finish;
    end

    // ---- 控制面 X/Z 守卫：关键控制信号出现 x 即计数（终局并入 errors）----
    always @(posedge clk_r) if (!rst_r)
        if ((^u_wk.state) === 1'bx || (busy_w === 1'bx) ||
            (ring_ready_w === 1'bx) || (wk_grant_w === 1'bx))
            xz_err = xz_err + 1;

    // ---- 全局看门狗：任何卡死硬停（正常最长 F6C ≈ 187 ms 仿真时间）----
    initial begin
        #500_000_000;
        $display("FATAL: F6 全局看门狗 500ms");
        final_fail("watchdog");
    end

endmodule
