/************************************************************************
 * File Name       : yolo_reg_file_f7.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_reg_file_f7
 * Description     : PPU-F7 变体固定寄存器堆（0x000-0x2FF，FF，设计
 *                   文档 1_docs/yolo_axi_lite_csr_design_20260918 §4）。
 *                   自 yolo_reg_file V1.1 复制扩展（CSR 线板级冻结物
 *                   本体不动），F7 增量仅三处：
 *                     1. ERROR_STATUS 扩一位：bit10 = 引擎错误
 *                        （E_BIT_ENGINE_F7，walker err_evt_eng_o——
 *                        PPU ldr/dma 错与 GEMM 桩 err 共用；W1C）。
 *                        yolo_csr_pkg 冻结于 0-9，本位 localparam 本地
 *                        定义（keep in sync 纪律）。
 *                     2. A_DESC_DOORBELL bit1（原只置 frame_end_pending
 *                        粘着供 walker 消费）同步发出 ffe_pulse_o 单拍
 *                        脉冲供 ppu_shell_top.ffe_i（F6 TB ffe 事件
 *                        双落点的 CSR 化）。
 *                     3. A_DMA_CFG 字段布局定版（F7 合同）：
 *                        [23:0] AXI 超时拍数、[26:24] 读 outstanding
 *                        上限、[29:27] 写 outstanding 上限，[31:30] 保留
 *                        ——寄存器本体仍整字读写，切片在顶层。
 *                   其余语义（RW/R/W1C/pulse、ACK 尾针延拍、perf 计数）
 *                   逐位沿用 V1.1。
 * Dependencies    : yolo_csr_pkg.sv（冻结共用，未改）
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : F7 初版——自 yolo_reg_file V1.1 复制
 *                                + bit10 引擎错 + ffe 脉冲 + DMA_CFG
 *                                布局定版。
 *   - V1.1-G5 (2026-10-28) by Stage B PPU lane : candidate-only DMA_CFG
 *                                request/response qualification, sticky
 *                                profile/start faults, and gated host done.
 *   - V1.2-Closure (2026-10-28) by V25/PPU closure lane : Record top/m03
 *                                integration faults in existing ERROR_STATUS
 *                                bit10 with priority over same-cycle W1C.
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_reg_file_f7 (
    input  wire        clk_i            ,
    input  wire        rst_n            ,
    input  wire        soft_reset_i     ,  // pulse from CTRL.SOFT_RESET
    // CSR write port (pulse, one per accepted write)
    input  wire        csr_wr_valid_i   ,
    input  wire [15:0] csr_wr_addr_i    ,
    input  wire [31:0] csr_wr_data_i    ,
    // CSR read port (1 cycle latency)
    input  wire [15:0] csr_rd_addr_i    ,
    input  wire        csr_rd_valid_i   ,
    input  wire        csr_rd_ack_i     ,
    input  wire [1:0]  csr_rd_rsp_i     ,
    input  wire [31:0] csr_rd_data_i    ,
    output reg  [31:0] csr_rd_data_o    ,
    // ---- G5 heads profile / completion ----
    input  wire        heads_epoch_active_i,
    input  wire        csr_heads_start_accepted_i,
    input  wire        heads_gated_done_event_i,
    input  wire        heads_transaction_fault_i,
    input  wire        ppu_error_any_i  ,
    input  wire        epoch_invalid_i  ,
    output reg         heads_prelaunch_profile_valid_o,
    output reg         heads_profile_fault_sticky_o,
    output reg         heads_start_reject_sticky_o,
    output wire        heads_profile_fault_event_o,
    output wire        heads_host_done_o ,
    // ---- walker status / control ----
    input  wire        walker_idle_i    ,
    input  wire        walker_running_i ,
    input  wire        walker_frame_done_i,
    input  wire [7:0]  walker_cur_opcode_i,
    input  wire [15:0] walker_head_i    ,
    input  wire [15:0] walker_current_i ,
    input  wire [15:0] walker_done_i    ,
    input  wire [15:0] walker_error_id_i,
    output wire        ctrl_enable_o    ,
    output wire        ctrl_start_frame_o,  // pulse
    output wire        ctrl_stop_o      ,  // pulse
    output wire        ctrl_abort_o     ,  // pulse
    output wire        ctrl_clr_status_o,  // pulse
    output wire        ctrl_flush_cache_o, // pulse
    output wire        ctrl_soft_reset_o,  // pulse
    output wire        ctrl_arm_irq_o   ,
    // ---- descriptor queue ----
    output reg  [15:0] desc_count_o     ,
    output reg  [15:0] desc_tail_o      ,
    output wire        doorbell_commit_o,  // pulse
    output reg         frame_end_pending_o, // sticky, cleared by walker
    input  wire        frame_end_clear_i,  // pulse from walker
    output wire        ffe_pulse_o      ,  // F7: doorbell bit1 -> shell ffe_i
    output wire [7:0]  desc_depth_o     ,
    output wire        desc_circular_o  ,
    output reg  [11:0] desc_win_base_o  ,  // aperture window base (word)
    // ---- scheduler config ----
    output reg  [31:0] sched_cfg_o      ,
    // ---- result ring ----
    input  wire [7:0]  ring_head_ptr_i  ,
    input  wire        ring_not_empty_i ,
    input  wire [31:0] ring_seq_i       ,
    input  wire [31:0] ring_frame_id_i  ,
    input  wire [31:0] ring_head_bytes_i,
    input  wire        ring_publish_evt_i,  // one-cycle pulse on publish
    input  wire        ring_overflow_evt_i, // publish overflow event
    output reg  [7:0]  ring_tail_ptr_o  ,  // RW by PS, advanced by ACK
    output wire        ring_ack_consume_o,  // pulse
    output wire        ring_ack_drop_o  ,  // pulse
    output wire        ring_ack_retry_o ,  // pulse
    // ---- frame / input / head config (exported) ----
    output reg  [31:0] frame_id_reg_o   ,
    output reg  [31:0] frame_cfg_o      ,
    output reg  [31:0] input_base_lo_o  ,
    output reg  [31:0] input_base_hi_o  ,
    output reg  [31:0] input_stride_o   ,
    output reg  [31:0] head_base_lo_o   ,
    output reg  [31:0] head_base_hi_o   ,
    output reg  [31:0] head_stride_o    ,
    output reg  [31:0] head_format_o    ,
    output reg  [31:0] result_max_det_o ,
    output reg  [31:0] result_conf_q_o  ,
    // ---- model identity ----
    output reg  [31:0] model_id_o       ,
    output reg  [31:0] graph_crc_o      ,
    // ---- error aggregation ----
    input  wire [10:0] err_events_i     ,  // one-cycle set events (bit10 = F7 engine error)
    input  wire [7:0]  err_code_i       ,
    input  wire [7:0]  err_op_i         ,
    input  wire [7:0]  err_desc_id_i    ,
    input  wire [7:0]  err_port_i       ,
    output wire [10:0] error_status_o   ,
    // ---- dma / perf ----
    output reg  [31:0] dma_cfg_o        ,
    output wire [31:0] perf_cycles_o    ,
    // ---- interrupt ----
    output wire        irq_o
);

    import yolo_csr_pkg::*;

    // F7 local extension (pkg frozen at bits 0-9 -- keep in sync)
    localparam int E_BIT_ENGINE_F7 = 10;

    // ------------------------------------------------------------ --
    // latched state
    // ------------------------------------------------------------ --
    reg        enable_q, arm_irq_q;
    reg        heads_host_done_q;
    reg        f7_rd_inflight_q;
    reg [15:0] f7_rd_addr_q;
    reg [15:0] frame_seq;          // incremented on accepted heads start
    reg [10:0] error_status_q;
    reg [31:0] error_info_q;
    reg        res_valid_q, res_ovf_q, res_drop_q, res_owned_q;
    reg [31:0] perf_cycles_q;
    reg [31:0] desc_cfg_q;
    reg        ctrl_start_pulse, ctrl_stop_pulse, ctrl_abort_pulse;
    reg        ctrl_clr_pulse, ctrl_flush_pulse, dbell_commit_pulse;
    reg        ffe_pulse_q;
    reg        ack_consume_pulse, ack_drop_pulse, ack_retry_pulse;
    reg        perf_clear_pulse, soft_reset_pulse;

    assign ctrl_enable_o      = enable_q;
    assign ctrl_arm_irq_o     = arm_irq_q;
    assign error_status_o     = error_status_q;
    assign perf_cycles_o      = perf_cycles_q;
    assign desc_depth_o       = desc_cfg_q[7:0];
    assign desc_circular_o    = desc_cfg_q[16];
    assign ctrl_start_frame_o = ctrl_start_pulse;
    assign ctrl_stop_o        = ctrl_stop_pulse ;
    assign ctrl_abort_o       = ctrl_abort_pulse;
    assign ctrl_clr_status_o  = ctrl_clr_pulse  ;
    assign ctrl_flush_cache_o = ctrl_flush_pulse;
    assign ctrl_soft_reset_o  = soft_reset_pulse;
    assign doorbell_commit_o  = dbell_commit_pulse;
    assign ffe_pulse_o        = ffe_pulse_q;
    assign ring_ack_consume_o = ack_consume_pulse;
    assign ring_ack_drop_o    = ack_drop_pulse   ;
    assign ring_ack_retry_o   = ack_retry_pulse  ;
    assign heads_host_done_o = heads_host_done_q;

    // TABLE_RD_LATENCY=1 request/response bookkeeping.  The response uses
    // the top-level read-data mux, not a shadow DMA_CFG register.
    wire f7_rd_request_event = csr_rd_valid_i && !csr_rd_ack_i &&
                               !f7_rd_inflight_q;
    wire f7_rd_response_event = csr_rd_valid_i && csr_rd_ack_i &&
                                f7_rd_inflight_q;
    wire f7_rd_unexpected_completion = csr_rd_valid_i && csr_rd_ack_i &&
                                       !f7_rd_inflight_q;
    wire f7_rd_normal_ack_tail = !csr_rd_valid_i && csr_rd_ack_i &&
                                 !f7_rd_inflight_q;
    wire f7_rd_addr_change = f7_rd_inflight_q && csr_rd_valid_i &&
                             (csr_rd_addr_i != f7_rd_addr_q);
    wire f7_dma_cfg0_okay_read_completion = f7_rd_response_event &&
        (f7_rd_addr_q == A_DMA_CFG) && (csr_rd_addr_i == A_DMA_CFG) &&
        (csr_rd_rsp_i == 2'b00) && (csr_rd_data_i[29:27] === 3'd0);
    wire f7_dma_cfg_read_completion = f7_rd_response_event &&
        ((f7_rd_addr_q == A_DMA_CFG) || (csr_rd_addr_i == A_DMA_CFG));
    wire f7_bad_dma_cfg_read_completion = f7_dma_cfg_read_completion &&
                                          !f7_dma_cfg0_okay_read_completion;
    wire f7_live_profile_fault_event = heads_epoch_active_i &&
                                       (dma_cfg_o[29:27] !== 3'd0);
    assign heads_profile_fault_event_o = f7_rd_unexpected_completion ||
                                         f7_rd_addr_change ||
                                         f7_bad_dma_cfg_read_completion ||
                                         f7_live_profile_fault_event;

    wire f7_heads_invalidate_event = heads_profile_fault_event_o ||
                                     heads_transaction_fault_i ||
                                     ppu_error_any_i || epoch_invalid_i ||
                                     (ctrl_start_pulse &&
                                      !csr_heads_start_accepted_i);

    wire err_any = (error_status_q != 11'h0);

    // irq: armed && (gated host done or any error)
    assign irq_o = arm_irq_q && (heads_host_done_q || err_any);

    // ------------------------------------------------------------ --
    // main register process
    // ------------------------------------------------------------ --
    integer k;
    always @(posedge clk_i) begin
        if (!rst_n || soft_reset_i) begin
            enable_q           <= 1'b0;
            arm_irq_q          <= 1'b0;
            frame_seq          <= 16'h0;
            error_status_q     <= 11'h0;
            error_info_q       <= 32'h0;
            res_valid_q        <= 1'b0;
            res_ovf_q          <= 1'b0;
            res_drop_q         <= 1'b0;
            res_owned_q        <= 1'b0;
            model_id_o         <= 32'h0;
            graph_crc_o        <= 32'h0;
            frame_id_reg_o     <= 32'h0;
            frame_cfg_o        <= 32'h0;
            input_base_lo_o    <= 32'h0;
            input_base_hi_o    <= 32'h0;
            input_stride_o     <= 32'h0;
            head_base_lo_o     <= 32'h0;
            head_base_hi_o     <= 32'h0;
            head_stride_o      <= 32'h0;
            head_format_o      <= 32'h0;
            result_max_det_o   <= 32'h0;
            result_conf_q_o    <= 32'h0;
            desc_cfg_q         <= 32'h0;
            desc_win_base_o    <= 12'h0;
            desc_count_o       <= 16'h0;
            desc_tail_o        <= 16'h0;
            frame_end_pending_o<= 1'b0;
            sched_cfg_o        <= 32'h0;
            ring_tail_ptr_o    <= 8'h0;
            dma_cfg_o          <= 32'h0;
            perf_cycles_q      <= 32'h0;
            ctrl_start_pulse   <= 1'b0;
            ctrl_stop_pulse    <= 1'b0;
            ctrl_abort_pulse   <= 1'b0;
            ctrl_clr_pulse     <= 1'b0;
            ctrl_flush_pulse   <= 1'b0;
            dbell_commit_pulse <= 1'b0;
            ffe_pulse_q        <= 1'b0;
            ack_consume_pulse  <= 1'b0;
            ack_drop_pulse     <= 1'b0;
            ack_retry_pulse    <= 1'b0;
            perf_clear_pulse   <= 1'b0;
            soft_reset_pulse   <= 1'b0;
        end else begin
            // -------- pulses are single beat ------------------------- --
            ctrl_start_pulse   <= 1'b0;
            ctrl_stop_pulse    <= 1'b0;
            ctrl_abort_pulse   <= 1'b0;
            ctrl_clr_pulse     <= 1'b0;
            ctrl_flush_pulse   <= 1'b0;
            dbell_commit_pulse <= 1'b0;
            ffe_pulse_q        <= 1'b0;
            ack_consume_pulse  <= 1'b0;
            ack_drop_pulse     <= 1'b0;
            ack_retry_pulse    <= 1'b0;
            perf_clear_pulse   <= 1'b0;
            soft_reset_pulse   <= 1'b0;

            // -------- performance counter: free running, cleared on
            //          accepted heads start or PERF_CLEAR ---------------- --
            if (csr_heads_start_accepted_i || perf_clear_pulse) begin
                perf_cycles_q <= 32'h0;
            end else begin
                perf_cycles_q <= perf_cycles_q + 32'h1;
            end

            // -------- frame sequencing: raw CTRL start is not a frame start -
            if (csr_heads_start_accepted_i) begin
                frame_seq <= frame_seq + 16'h1;
            end

            // -------- error aggregation (sticky + info latch) --------- --
            if (err_events_i != 11'h0) begin
                error_status_q <= error_status_q | err_events_i;
                error_info_q   <= {err_port_i, err_desc_id_i,
                                   err_op_i, err_code_i};
            end

            // -------- result ring events ------------------------------ --
            if (ring_publish_evt_i) begin
                res_valid_q <= 1'b1;
                res_owned_q <= 1'b1;
            end
            if (ring_overflow_evt_i) res_ovf_q  <= 1'b1;
            if (ring_ack_drop_o)     res_drop_q <= 1'b1;
            if (ring_ack_consume_o || ring_ack_drop_o) res_owned_q <= 1'b0;

            // -------- ACK tail advance -------------------------------- --
            // Advances one cycle AFTER the ack pulse asserts: the pulse and
            // a same-edge tail advance made yolo_result_ring sample
            // not_empty_o against the already-advanced tail and latch a
            // false ack-on-empty protocol error on every legitimate ACK
            // that drained the ring (board l3r1, 2026-09-18).
            if (ring_ack_consume_o || ring_ack_drop_o)
                ring_tail_ptr_o <= ring_tail_ptr_o + 8'h1;

            // -------- PS write decode -------------------------------- --
            if (csr_wr_valid_i) begin
                case (csr_wr_addr_i)
                    A_CTRL: begin
                        enable_q         <= csr_wr_data_i[0];
                        soft_reset_pulse <= csr_wr_data_i[1];
                        ctrl_start_pulse <= csr_wr_data_i[2];
                        ctrl_stop_pulse  <= csr_wr_data_i[3];
                        ctrl_abort_pulse <= csr_wr_data_i[4];
                        ctrl_clr_pulse   <= csr_wr_data_i[5];
                        ctrl_flush_pulse <= csr_wr_data_i[6];
                        if (csr_wr_data_i[7]) arm_irq_q <= 1'b1;
                    end
                    A_ERROR_STATUS: begin
                        for (k = 0; k < 11; k = k + 1)
                            if (csr_wr_data_i[k]) error_status_q[k] <= 1'b0;
                    end
                    A_MODEL_ID      : model_id_o       <= csr_wr_data_i;
                    A_GRAPH_CRC     : graph_crc_o      <= csr_wr_data_i;
                    A_FRAME_ID      : frame_id_reg_o   <= csr_wr_data_i;
                    A_FRAME_CFG     : frame_cfg_o      <= csr_wr_data_i;
                    A_INPUT_BASE_LO : input_base_lo_o  <= csr_wr_data_i;
                    A_INPUT_BASE_HI : input_base_hi_o  <= csr_wr_data_i;
                    A_INPUT_STRIDE  : input_stride_o   <= csr_wr_data_i;
                    A_HEAD_BASE_LO  : head_base_lo_o   <= csr_wr_data_i;
                    A_HEAD_BASE_HI  : head_base_hi_o   <= csr_wr_data_i;
                    A_HEAD_STRIDE   : head_stride_o    <= csr_wr_data_i;
                    A_HEAD_FORMAT   : head_format_o    <= csr_wr_data_i;
                    A_RESULT_MAX_DET: result_max_det_o <= csr_wr_data_i;
                    A_RESULT_CONF_Q : result_conf_q_o  <= csr_wr_data_i;
                    A_RESULT_STATUS: begin
                        if (csr_wr_data_i[0]) res_valid_q <= 1'b0;
                        if (csr_wr_data_i[1]) res_ovf_q   <= 1'b0;
                        if (csr_wr_data_i[2]) res_drop_q  <= 1'b0;
                        if (csr_wr_data_i[4]) res_owned_q <= 1'b0;
                    end
                    A_RESULT_ACK: begin
                        ack_consume_pulse <= csr_wr_data_i[0];
                        ack_drop_pulse    <= csr_wr_data_i[1];
                        ack_retry_pulse   <= csr_wr_data_i[2];
                        // tail advance moved to the ring-events section
                        // (one cycle later); see comment there.
                    end
                    A_RESULT_RING_TAIL: ring_tail_ptr_o <= csr_wr_data_i[7:0];
                    A_DESC_CFG      : desc_cfg_q       <= csr_wr_data_i;
                    A_DESC_BASE     : desc_win_base_o  <= csr_wr_data_i[11:0];
                    A_DESC_COUNT    : desc_count_o     <= csr_wr_data_i;
                    A_DESC_TAIL     : desc_tail_o      <= csr_wr_data_i;
                    A_DESC_DOORBELL : begin
                        dbell_commit_pulse <= csr_wr_data_i[0];
                        if (csr_wr_data_i[1]) begin
                            frame_end_pending_o <= 1'b1;
                            ffe_pulse_q         <= 1'b1;  // F7: shell ffe_i
                        end
                    end
                    A_SCHED_CFG     : sched_cfg_o      <= csr_wr_data_i;
                    A_DMA_CFG       : dma_cfg_o        <= csr_wr_data_i;
                    A_PERF_CLEAR    : perf_clear_pulse <= csr_wr_data_i[0];
                    default: ; // unmapped offsets inside 0x000-0x2FF: ignored
                endcase
            end

            // -------- walker consumes the frame_end flag (clear wins
            //          over a simultaneous PS set) ---------------------- --
            if (frame_end_clear_i) frame_end_pending_o <= 1'b0;

            // Integration faults use the existing engine/integration error
            // bit.  This final priority prevents a same-cycle W1C from
            // erasing a new top-level response, profile or epoch failure.
            if (heads_transaction_fault_i || epoch_invalid_i ||
                heads_profile_fault_event_o) begin
                error_status_q[E_BIT_ENGINE_F7] <= 1'b1;
            end
        end
    end

    // G5 profile and host-done state.  Only an actual OKAY cfg0 read response
    // can arm the next frame; accepted start consumes the pre-state arm.
    always @(posedge clk_i) begin
        if (!rst_n || soft_reset_i) begin
            heads_host_done_q <= 1'b0;
            f7_rd_inflight_q <= 1'b0;
            f7_rd_addr_q <= 16'h0;
            heads_prelaunch_profile_valid_o <= 1'b0;
            heads_profile_fault_sticky_o <= 1'b0;
            heads_start_reject_sticky_o <= 1'b0;
        end else begin
            if (f7_rd_request_event) begin
                f7_rd_inflight_q <= 1'b1;
                f7_rd_addr_q <= csr_rd_addr_i;
            end else if (f7_rd_response_event) begin
                f7_rd_inflight_q <= 1'b0;
            end

            if (f7_rd_unexpected_completion || f7_rd_addr_change ||
                f7_live_profile_fault_event) begin
                heads_profile_fault_sticky_o <= 1'b1;
            end
            if (f7_bad_dma_cfg_read_completion) begin
                heads_profile_fault_sticky_o <= 1'b1;
            end
            if (ctrl_start_pulse && !csr_heads_start_accepted_i) begin
                heads_start_reject_sticky_o <= 1'b1;
            end

            if (f7_dma_cfg0_okay_read_completion &&
                !heads_epoch_active_i && !f7_heads_invalidate_event &&
                !heads_profile_fault_sticky_o &&
                !heads_start_reject_sticky_o) begin
                heads_prelaunch_profile_valid_o <= 1'b1;
            end
            if (csr_heads_start_accepted_i) begin
                heads_prelaunch_profile_valid_o <= 1'b0;
                heads_host_done_q <= 1'b0;
            end
            if (heads_gated_done_event_i && !f7_heads_invalidate_event) begin
                heads_prelaunch_profile_valid_o <= 1'b0;
                heads_host_done_q <= 1'b1;
            end
            if (f7_heads_invalidate_event) begin
                heads_prelaunch_profile_valid_o <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ --
    // STATUS register composition (combinational, latched on read)
    // ------------------------------------------------------------ --
    wire desc_empty = (walker_head_i == desc_tail_o);
    wire desc_full  = (({1'b0, desc_tail_o[7:0]} + 9'd1)
                       == {1'b0, walker_head_i[7:0]});

    wire [31:0] status_val = {frame_seq,            // [31:16]
                              walker_cur_opcode_i,  // [15:8]
                              ring_not_empty_i,     // [7] PS_ACK_WAIT
                              ring_not_empty_i,     // [6] HEAD_VALID
                              desc_full,            // [5] DESC_FULL
                              desc_empty,           // [4] DESC_EMPTY
                              err_any,              // [3] ERROR
                              heads_host_done_q,    // [2] gated HEADS_DONE
                              walker_running_i,     // [1] RUNNING
                              walker_idle_i};       // [0] IDLE

    // ------------------------------------------------------------ --
    // CSR read mux (registered, 1 cycle latency)
    // ------------------------------------------------------------ --
    always @(posedge clk_i) begin
        if (!rst_n) begin
            csr_rd_data_o <= 32'h0;
        end else begin
            case (csr_rd_addr_i)
                A_ID              : csr_rd_data_o <= YOLO_ID_VALUE;
                A_VERSION         : csr_rd_data_o <= YOLO_VERSION;
                A_CAP0            : csr_rd_data_o <= {5'b0, CAP_IRQ, CAP_HEAD_DMA,
                                                    CAP_GRAPH_OP, CAP_PE_LANES,
                                                    CAP_N_TILES, CAP_OC_TILES};
                A_CAP1            : csr_rd_data_o <= {8'h00, 8'd128,
                                                    8'd16, 8'd7};
                A_STATUS          : csr_rd_data_o <= status_val;
                A_ERROR_STATUS    : csr_rd_data_o <= {21'h0, error_status_q};
                A_ERROR_INFO      : csr_rd_data_o <= error_info_q;
                A_MODEL_ID        : csr_rd_data_o <= model_id_o;
                A_GRAPH_CRC       : csr_rd_data_o <= graph_crc_o;
                A_FRAME_ID        : csr_rd_data_o <= frame_id_reg_o;
                A_FRAME_CFG       : csr_rd_data_o <= frame_cfg_o;
                A_INPUT_BASE_LO   : csr_rd_data_o <= input_base_lo_o;
                A_INPUT_BASE_HI   : csr_rd_data_o <= input_base_hi_o;
                A_INPUT_STRIDE    : csr_rd_data_o <= input_stride_o;
                A_HEAD_BASE_LO    : csr_rd_data_o <= head_base_lo_o;
                A_HEAD_BASE_HI    : csr_rd_data_o <= head_base_hi_o;
                A_HEAD_STRIDE     : csr_rd_data_o <= head_stride_o;
                A_HEAD_BYTES      : csr_rd_data_o <= ring_head_bytes_i;
                A_HEAD_FORMAT     : csr_rd_data_o <= head_format_o;
                A_RESULT_SEQ      : csr_rd_data_o <= ring_seq_i;
                A_RESULT_FRAME_ID : csr_rd_data_o <= ring_frame_id_i;
                A_RESULT_STATUS   : csr_rd_data_o <= {27'h0, res_owned_q, 1'b0,
                                                    res_drop_q, res_ovf_q,
                                                    res_valid_q};
                A_RESULT_RING_HEAD: csr_rd_data_o <= {24'h0, ring_head_ptr_i};
                A_RESULT_RING_TAIL: csr_rd_data_o <= {24'h0, ring_tail_ptr_o};
                A_RESULT_MAX_DET  : csr_rd_data_o <= result_max_det_o;
                A_RESULT_CONF_Q   : csr_rd_data_o <= result_conf_q_o;
                A_DESC_CFG        : csr_rd_data_o <= desc_cfg_q;
                A_DESC_BASE       : csr_rd_data_o <= {20'h0, desc_win_base_o};
                A_DESC_COUNT      : csr_rd_data_o <= desc_count_o;
                A_DESC_HEAD       : csr_rd_data_o <= {16'h0, walker_head_i};
                A_DESC_TAIL       : csr_rd_data_o <= {16'h0, desc_tail_o};
                A_DESC_CURRENT    : csr_rd_data_o <= {16'h0, walker_current_i};
                A_DESC_DONE_COUNT : csr_rd_data_o <= {16'h0, walker_done_i};
                A_DESC_ERROR_ID   : csr_rd_data_o <= {16'h0, walker_error_id_i};
                A_SCHED_CFG       : csr_rd_data_o <= sched_cfg_o;
                A_SCHED_STATUS    : csr_rd_data_o <= 32'h0; // no compute engine yet
                A_DMA_CFG         : csr_rd_data_o <= dma_cfg_o;
                A_DMA_STATUS      : csr_rd_data_o <= 32'h0;
                A_DMA_RD_BYTES    : csr_rd_data_o <= 32'h0;
                A_DMA_WR_BYTES    : csr_rd_data_o <= 32'h0;
                A_CACHE_STATUS    : csr_rd_data_o <= 32'h0;
                A_PERF_CYCLES     : csr_rd_data_o <= perf_cycles_q;
                A_PERF_MACS_LO    : csr_rd_data_o <= 32'h0;
                A_PERF_MACS_HI    : csr_rd_data_o <= 32'h0;
                A_PERF_STALL      : csr_rd_data_o <= 32'h0;
                default           : csr_rd_data_o <= 32'h0;
            endcase
        end
    end

endmodule
