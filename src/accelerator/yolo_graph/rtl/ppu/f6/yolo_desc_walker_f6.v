/************************************************************************
 * File Name       : yolo_desc_walker_f6.v
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_desc_walker_f6
 * Description     : PPU-F6 walker/CSR 汇合版调度器。独立副本扩展自
 *                   yolo_desc_walker.sv V2.0（CSR 线板级冻结物，本体
 *                   不动）：word0/1/2/14 公共位、队列/环结果合同逐位
 *                   沿用；walk-through 换成 v1.1 §7 引擎派发握手——
 *
 *   walker 读 w0/w14（port B）→ opcode[7:4] 解复用（§1：0x0→GEMM
 *   通路 / 0x1→PPU 引擎 / 其余→非法描述符错）→ engine_req_valid +
 *   desc_index(+opcode) 单拍脉冲 → 引擎经同一 port B 读其余字段
 *   （walker 派发后停查，port_grant_o=1 期间端口让渡）→ engine_done
 *   后 head 才前进（顺序屏障：下一描述符绝不在前一项 done 前派发）。
 *
 *   端口让渡时序（F7 control_subsystem 集成须守同一合同）：
 *     cycle T-1  W_W14D 判决，state/req 寄存沿；
 *     cycle T    state=W_ENG、port_grant_o=1、ppu_req_valid_o=1；
 *     cycle T+1  shell S_FETCH、desc_if 首址上 port（grant 已生效）；
 *     engine_done 拍 grant 即回落（W_CHK），walker 下一址最早 T+2。
 *   本模块纯 Verilog-2001（RTL 铁律 .v；V2.0 原件为 .sv 但正文零
 *   package 引用，存在 Verilog 等价物）。
 *
 *   事件优先序（v1.1 §7 冻结，engine_done 到达时定案）：
 *     abort（丢弃帧：不前进、不发环、回 idle）＞ stop（当前描述符
 *     完成后停：done 照常、last 到则照常发环）＞ ffe（当前描述符
 *     完成后立即发环，不等 last、不再续走）＞ last（发环）。
 *     引擎错误（PPU ldr/dma、GEMM err）：W_ERR 粘着至 soft_reset，
 *     首错即停后续任务（§9），不发环。
 * Dependencies    : 无（原 V2.0 的 yolo_csr_pkg import 为摆设，剔除）。
 * Revision History:
 *   - V3.0 (2026-09-23) by LSL : PPU-F6 引擎派发扩展（replan §PPU-F6
 *       五步：独立副本/单读者 port B/engine_req+done 回接/表读延迟
 *       合同=1 拍同步读/环发布权独占——本模块是唯一 pub 源，PPU 侧
 *       ring_publish 仅作 TB 交叉核对，不接环）。
 *   - V3.1 (2026-09-28) by LSL : P2.3-C 引擎错误上下文补锁——W_ENG 且
 *       eng_err 同拍锁存 err_op_o<=w0_opcode、err_desc_id_o<=
 *       walker_head_o[7:0]（原只发 err_evt_eng_o，ERROR_INFO 的
 *       op/desc_id 停留陈旧值）。错误码/事件优先级/W_ERR 粘着/done/
 *       发环语义零变化。
 *   - V2.0 (2026-09-18) by LSL : 基线（见 yolo_desc_walker.sv）。
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_desc_walker_f6 (
    input  wire        clk_i              ,
    input  wire        rst_n              ,
    input  wire        soft_reset_i       ,
    // control (from register file)
    input  wire        enable_i           ,
    input  wire        start_frame_i      ,  // pulse
    input  wire        stop_i             ,  // pulse: graceful stop
    input  wire        abort_i            ,  // pulse: discard frame
    input  wire        doorbell_commit_i  ,  // informational (tail polled)
    input  wire        frame_end_pending_i,  // sticky, set by doorbell
    output reg         frame_end_clear_o  ,  // pulse when consumed
    // queue state
    input  wire [15:0] desc_tail_i        ,
    input  wire [15:0] desc_count_i       ,  // informational
    input  wire [7:0]  desc_depth_i       ,
    input  wire        desc_circular_i    ,
    output reg  [15:0] walker_head_o      ,
    output reg  [15:0] walker_current_o   ,
    output reg  [15:0] walker_done_o      ,
    output reg  [15:0] walker_error_id_o  ,
    output reg  [7:0]  cur_opcode_o       ,
    output reg         walker_idle_o      ,
    output reg         walker_running_o   ,
    output reg         walker_frame_done_o,
    // descriptor BRAM port B（单读者：W_ENG 期间让渡给引擎取包）
    output reg  [11:0] desc_rd_addr_o     ,
    input  wire [31:0] desc_rd_data_i     ,
    output wire        port_grant_o       ,  // 1 = 引擎取包期（mux 选引擎侧地址）
    // ---- 引擎派发：PPU 后端（opcode[7:4]==0x1）----
    output reg         ppu_req_valid_o    ,  // 单拍脉冲（顺序屏障保证 shell 空闲）
    output reg  [6:0]  ppu_desc_idx_o     ,
    input  wire        ppu_busy_i         ,  // shell busy_o
    input  wire        ppu_desc_done_i    ,  // shell desc_done_o（仲裁判决，abort 无此拍）
    input  wire        ppu_stopped_i      ,  // shell stopped_o（stop/abort 定案粘着）
    input  wire        ppu_ldr_err_i      ,  // shell ldr_err_valid_o（脉冲）
    input  wire        ppu_dma_halted_i   ,  // shell dma_halted_o（电平）
    // ---- 引擎派发：GEMM 后端（opcode[7:4]==0x0，B3 通路占位合同）----
    output reg         gemm_req_valid_o   ,  // 单拍脉冲
    output reg  [6:0]  gemm_desc_idx_o    ,
    output reg  [7:0]  gemm_opcode_o      ,
    input  wire        gemm_done_i        ,
    input  wire        gemm_err_i         ,
    // publish handshake (to result ring) —— 本模块为唯一发布源
    output reg         pub_valid_o        ,
    input  wire        pub_ready_i        ,
    output wire [31:0] pub_bytes_o        ,  // accumulated output bytes
    // error reporting
    output reg         err_evt_desc_o     ,  // pulse -> ERROR_STATUS bit3
    output reg  [7:0]  err_op_o           ,
    output reg  [7:0]  err_desc_id_o      ,
    output reg         err_evt_eng_o      ,  // pulse: 引擎错误（F7 接 ERROR_STATUS 新位）
    // ---- v2.3 PL 派发入口（M10.2 m8，DESIGN §3.4；运行标签律：与
    //      0x114 队列路径不得混用于同一 run——ppp_mode=1 / des_mode=1）----
    input  wire        ppu_start_pl_i     ,  // conv issuer 触发脉冲
    input  wire [17:0] ppp_payload_pl_i   ,  // {frame_id[7:0], seg_idx[2:0], desc_idx[6:0]}
    input  wire [7:0]  frame_token_pl_i   ,  // conv CSR doorbell 世代
    input  wire        token_valid_pl_i   ,  // 脉冲：锁存 current_gen
    input  wire [7:0]  ppu_ldr_code_i     ,  // shell loader 错误码（abort 面透传）
    output reg         ppu_done_pl_o      ,  // 判决脉冲 -> conv issuer
    output reg         ppp_done_abort_pl_o,  // 1 = token/引擎失败
    output reg  [7:0]  ppp_done_err_pl_o     // abort err 码（随脉冲有效）
);

    // ------------------------------------------------------------ --
    // states
    //   W_W0A / W_W0D : word0 address issued / word0 data on port B
    //   W_W14A / W_W14D: word14 address issued / word14 data + dispatch
    //   W_ENG          : 引擎在跑（端口让渡，等 done/err/abort 落定）
    //   W_ERR          : 引擎错误粘着（至 soft_reset；首错停后续）
    // ------------------------------------------------------------ --
    localparam [3:0] W_IDLE = 4'd0,
                     W_CHK  = 4'd1,
                     W_W0A  = 4'd2,
                     W_W0D  = 4'd3,
                     W_W14A = 4'd4,
                     W_W14D = 4'd5,
                     W_ENG  = 4'd6,
                     W_PUB  = 4'd7,
                     W_DONE = 4'd8,
                     W_ERR  = 4'd9;

    reg [3:0]  state;
    reg [3:0]  next_state;
    reg [31:0] w0_q;
    reg [31:0] bytes_acc;
    reg        eng_sel_ppu;                     // 1=本描述符派发 PPU / 0=GEMM
    reg        stop_run_q, abort_run_q;         // 运行期事件粘着（W_ENG 出口消费）

    // ---- v2.3 PL 派发面（DESIGN §3.2/§3.4）----
    // cur_gen_q 唯一来源 = frame_token 线（不碰 PPU 岛 0x43C2 CSR，
    // PPU ABI V1.1 零改动）。每次 ppu_start 比对 payload.frame_id vs
    // cur_gen_q，不等 → 不派发，回 abort done（E_GEN_MISMATCH）。
    // pl_mode_q 标记在飞描述符来自 PL 入口：done 出口改走 ppu_done_pl_o
    // + W_IDLE（不进队列续走/发环——发布面归 0x114 路径，运行标签律）。
    reg [7:0]  cur_gen_q;
    reg        pl_mode_q;
    reg [2:0]  pl_seg_q;                        // 在飞段 seg_idx（诊断面）
    localparam [7:0] E_GEN_MISMATCH_PL = 8'h25; // conv STATUS 域（v2.3 表）
    localparam [7:0] E_PPU_DMA_PL      = 8'h26; // 同表延伸：dma-halt 透传
                                                 // （shell dma 面无码，bit-only）

    wire [7:0] w0_opcode = w0_q[7:0];
    wire       w0_valid  = w0_q[8];
    wire       w0_last   = w0_q[9];

    assign pub_bytes_o  = bytes_acc;
    assign port_grant_o = (state == W_ENG);

    // effective descriptor depth (0 -> full 128-entry table)
    wire [7:0] eff_depth = (desc_depth_i == 8'd0) ? 8'd128 : desc_depth_i;

    wire [15:0] head_plus1 = walker_head_o + 16'd1;
    wire [15:0] head_next  = (desc_circular_i && (head_plus1[7:0] == eff_depth))
                             ? 16'h0 : head_plus1;

    wire queue_empty = (walker_head_o == desc_tail_i);

    // 派发解复用（v1.1 §1）：[7:4]=0 → GEMM；=1 → PPU；≥2 → 非法
    wire op_is_ppu  = (w0_opcode[7:4] == 4'h1);
    wire op_is_gemm = (w0_opcode[7:4] == 4'h0);
    wire op_illegal = !op_is_ppu && !op_is_gemm;

    // W_ENG 出口条件
    wire eng_done   = eng_sel_ppu ? ppu_desc_done_i : gemm_done_i;
    wire eng_err    = eng_sel_ppu ? (ppu_ldr_err_i || ppu_dma_halted_i)
                                  : gemm_err_i;
    wire eng_abort_settled = abort_run_q && (!eng_sel_ppu || ppu_stopped_i);

    // ---- v2.3 PL 入口仲裁（DESIGN §3.2）：gen 比对在触发拍 ----
    wire       pl_gen_ok_w  = (ppp_payload_pl_i[17:10] == cur_gen_q);
    wire       pl_start_ok_w = ppu_start_pl_i && pl_gen_ok_w;
    wire       pl_gen_bad_w  = ppu_start_pl_i && !pl_gen_ok_w;

    // ------------------------------------------------------------ --
    // FSM block 1 : state register
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state <= W_IDLE;
        end else if (soft_reset_i) begin
            state <= W_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ------------------------------------------------------------ --
    // FSM block 2 : next-state logic
    // ------------------------------------------------------------ --
    always @(*) begin
        next_state = state;
        case (state)
            W_IDLE: begin
                if (pl_start_ok_w)
                    // v2.3 PL 直派入口：gen 匹配才进（仲裁见下）——
                    // head := desc_idx 由数据面块做，这里直接取包
                    next_state = W_W0A;
                else if (start_frame_i && enable_i)
                    next_state = W_CHK;
            end
            W_CHK: begin
                if (stop_i || abort_i)
                    next_state = W_IDLE;
                else if (!queue_empty)
                    next_state = W_W0A;
                else if (frame_end_pending_i)
                    next_state = W_PUB;
            end
            W_W0A: begin
                next_state = W_W0D;
            end
            W_W0D: begin
                next_state = W_W14A;
            end
            W_W14A: begin
                next_state = W_W14D;
            end
            W_W14D: begin
                if (!w0_valid || op_illegal)
                    next_state = W_IDLE;      // invalid descriptor: error
                else
                    next_state = W_ENG;       // dispatch（含 last：done 后判）
            end
            W_ENG: begin
                if (pl_mode_q) begin
                    // v2.3 PL face：帧可中止语义——done/err 都回 W_IDLE，
                    // 不进 W_ERR 粘着（帧权在 conv issuer；判决经
                    // ppu_done_pl_o 面回传）。发布/续走归 0x114 路径。
                    if (eng_err || eng_done)
                        next_state = W_IDLE;
                end
                else if (eng_err)
                    next_state = W_ERR;       // 首错即停（§9）
                else if (eng_done)
                    // 定案序：abort 已被 done 前置条件排除（abort 帧无
                    // done）；done 后 last/ffe > stop > 续走
                    next_state = (w0_last || frame_end_pending_i) ? W_PUB
                                 : ((stop_run_q || ppu_stopped_i) ? W_IDLE
                                  : W_CHK);
                else if (eng_abort_settled)
                    next_state = W_IDLE;      // abort 落定：丢弃，不前进
            end
            W_PUB: begin
                if (pub_valid_o && pub_ready_i)
                    next_state = W_DONE;
            end
            W_DONE: begin
                next_state = W_IDLE;
            end
            W_ERR: begin
                next_state = W_ERR;           // 粘着至 soft_reset
            end
            default: begin
                next_state = W_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------ --
    // FSM block 3 : registered outputs (pulses and status)
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            pub_valid_o        <= 1'b0;
            frame_end_clear_o  <= 1'b0;
            walker_frame_done_o<= 1'b0;
            err_evt_desc_o     <= 1'b0;
            err_evt_eng_o      <= 1'b0;
            err_op_o           <= 8'h0;
            err_desc_id_o      <= 8'h0;
            walker_idle_o      <= 1'b1;
            walker_running_o   <= 1'b0;
            // v2.3 PL face
            ppu_done_pl_o      <= 1'b0;
            ppp_done_abort_pl_o<= 1'b0;
            ppp_done_err_pl_o  <= 8'h0;
            cur_gen_q          <= 8'h0;
        end else begin
            // defaults: single-beat pulses self-clear
            frame_end_clear_o   <= 1'b0;
            walker_frame_done_o <= 1'b0;
            err_evt_desc_o      <= 1'b0;
            err_evt_eng_o       <= 1'b0;
            ppu_done_pl_o       <= 1'b0;

            // v2.3: generation latch (sole source = frame_token line)
            if (token_valid_pl_i)
                cur_gen_q <= frame_token_pl_i;

            // v2.3: gen mismatch -> refuse + abort done (no dispatch,
            // no W_ERR sticky -- frame-abortable semantics).  Idle-scoped
            // like the PL entry arm (DESIGN §3.4 "idle 时 ppu_start 到达");
            // a start that lands while busy is outside the run contract
            // (issuer waits done) -> lost to the conv-side watchdog.
            if (pl_gen_bad_w && state == W_IDLE) begin
                ppu_done_pl_o       <= 1'b1;
                ppp_done_abort_pl_o <= 1'b1;
                ppp_done_err_pl_o   <= E_GEN_MISMATCH_PL;
            end

            // v2.3: PL dispatch success verdict (W_ENG exit, no eng err)
            if (state == W_ENG && pl_mode_q && eng_done && !eng_err) begin
                ppu_done_pl_o       <= 1'b1;
                ppp_done_abort_pl_o <= 1'b0;
            end

            // v2.3: PL engine failure verdict (loader code if present,
            // else the segment-failure carry -- dma face is bit-only)
            if (state == W_ENG && pl_mode_q && eng_err) begin
                ppu_done_pl_o       <= 1'b1;
                ppp_done_abort_pl_o <= 1'b1;
                ppp_done_err_pl_o   <= ppu_ldr_err_i ? ppu_ldr_code_i
                                                    : E_PPU_DMA_PL;
            end

            // v2.3: PL descriptor invalid (word0) -> abort done
            if (state == W_W14D && pl_mode_q && (!w0_valid || op_illegal)) begin
                ppu_done_pl_o       <= 1'b1;
                ppp_done_abort_pl_o <= 1'b1;
                ppp_done_err_pl_o   <= E_PPU_DMA_PL;
            end

            // publish handshake: assert on entry, hold until accepted
            if (state == W_PUB && pub_ready_i)
                pub_valid_o <= 1'b0;
            else if (next_state == W_PUB)
                pub_valid_o <= 1'b1;

            // consume the sticky frame_end flag when it triggers publish
            // （last 与 ffe 同帧到也一并消费——帧已终，旗语归零）
            if (next_state == W_PUB && frame_end_pending_i)
                frame_end_clear_o <= 1'b1;

            // frame complete
            if (state == W_PUB && next_state == W_DONE)
                walker_frame_done_o <= 1'b1;

            // invalid / illegal descriptor -> protocol error
            if (state == W_W14D && (!w0_valid || op_illegal)) begin
                err_evt_desc_o <= 1'b1;
                err_op_o       <= w0_opcode;
                err_desc_id_o  <= walker_head_o[7:0];
            end

            // engine error -> event pulse + 错误上下文同拍锁存（W_ERR 粘着
            // 由状态机承载）。P2.3-C：原只发事件，err_op_o/err_desc_id_o
            // 停留陈旧值（f6:266 只发 err_evt_eng_o；仅非法描述符路径
            // f6:261-262 锁存 → 引擎错时 ERROR_INFO.desc_id 恒陈旧 0，
            // B5 槽 0 掩盖、F7S run1 idx=1 首次暴露）。上下文寄存器与事件
            // 同拍更新，ppu_f7_top 组合映射后由 CSR 后续沿采样；desc_id
            // 表达式沿用非法描述符路径 head[7:0] 全工程约定（有效槽 0-127
            // 内与 {1'b0,head[6:0]} 同值，不靠截断掩盖越界——越界由
            // desc_depth/eff_depth 机制另行拒绝）。错误码/事件优先级/
            // W_ERR 粘着/done/发环语义零变化。
            if (state == W_ENG && eng_err) begin
                err_evt_eng_o <= 1'b1;
                err_op_o      <= w0_opcode;
                err_desc_id_o <= walker_head_o[7:0];
            end

            // status flags track the state register
            walker_idle_o    <= (next_state == W_IDLE);
            walker_running_o <= (next_state != W_IDLE);
        end
    end

    // ------------------------------------------------------------ --
    // datapath: BRAM addressing, accumulation, dispatch, pointers
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            desc_rd_addr_o  <= 12'h0;
            w0_q            <= 32'h0;
            bytes_acc       <= 32'h0;
            walker_head_o   <= 16'h0;
            walker_current_o<= 16'h0;
            walker_done_o   <= 16'h0;
            walker_error_id_o <= 16'h0;
            cur_opcode_o    <= 8'h0;
            eng_sel_ppu     <= 1'b0;
            stop_run_q      <= 1'b0;
            abort_run_q     <= 1'b0;
            ppu_req_valid_o <= 1'b0;
            ppu_desc_idx_o  <= 7'd0;
            gemm_req_valid_o<= 1'b0;
            gemm_desc_idx_o <= 7'd0;
            gemm_opcode_o   <= 8'h0;
            pl_mode_q       <= 1'b0;
            pl_seg_q        <= 3'd0;
        end else if (soft_reset_i) begin
            desc_rd_addr_o  <= 12'h0;
            w0_q            <= 32'h0;
            bytes_acc       <= 32'h0;
            walker_head_o   <= 16'h0;
            walker_current_o<= 16'h0;
            walker_done_o   <= 16'h0;
            walker_error_id_o <= 16'h0;
            cur_opcode_o    <= 8'h0;
            eng_sel_ppu     <= 1'b0;
            stop_run_q      <= 1'b0;
            abort_run_q     <= 1'b0;
            ppu_req_valid_o <= 1'b0;
            ppu_desc_idx_o  <= 7'd0;
            gemm_req_valid_o<= 1'b0;
            gemm_desc_idx_o <= 7'd0;
            gemm_opcode_o   <= 8'h0;
            pl_mode_q       <= 1'b0;
            pl_seg_q        <= 3'd0;
        end else begin
            // engine req 为单拍脉冲（顺序屏障：仅派发给已空闲引擎）
            ppu_req_valid_o  <= 1'b0;
            gemm_req_valid_o <= 1'b0;

            // v2.3 PL 入口锁存 + head := desc_idx + word0 槽基地址
            // （绕过队列尾针轮询；读地址法与 W_CHK 出口同款）
            if (state == W_IDLE && pl_start_ok_w) begin
                pl_mode_q      <= 1'b1;
                pl_seg_q       <= ppp_payload_pl_i[9:7];
                walker_head_o  <= {9'd0, ppp_payload_pl_i[6:0]};
                desc_rd_addr_o <= {ppp_payload_pl_i[6:0], 5'd0};
            end
            // v2.3 PL 出口：判决已发（ppu_done_pl_o 面），撤在飞标记
            if (pl_mode_q && ((state == W_ENG && next_state == W_IDLE) ||
                              (state == W_W14D && next_state == W_IDLE &&
                               (!w0_valid || op_illegal))))
                pl_mode_q <= 1'b0;

            // new frame: reset queue pointers and accumulation
            if (state == W_IDLE && next_state == W_CHK) begin
                walker_head_o     <= 16'h0;
                walker_current_o  <= 16'h0;
                walker_done_o     <= 16'h0;
                walker_error_id_o <= 16'h0;
                cur_opcode_o      <= 8'h0;
                bytes_acc         <= 32'h0;
            end

            // issue word0 read when leaving W_CHK with work pending
            if (state == W_CHK && next_state == W_W0A)
                desc_rd_addr_o <= {walker_head_o[6:0], 5'd0};

            // word0 data on port B: capture it, issue word14 read
            if (state == W_W0D) begin
                w0_q           <= desc_rd_data_i;
                desc_rd_addr_o <= {walker_head_o[6:0], 5'd14};
            end

            // word14 data on port B: accumulate + dispatch（w14 数据在
            // W_W14D 当拍有效——V2.0 同款地址/数据双拍时序）
            if (state == W_W14D && w0_valid && !op_illegal) begin
                bytes_acc        <= bytes_acc + desc_rd_data_i;
                cur_opcode_o     <= w0_opcode;
                walker_current_o <= walker_head_o;
                eng_sel_ppu      <= op_is_ppu;
                if (op_is_ppu) begin
                    ppu_req_valid_o <= 1'b1;
                    ppu_desc_idx_o  <= walker_head_o[6:0];
                end else begin
                    gemm_req_valid_o<= 1'b1;
                    gemm_desc_idx_o <= walker_head_o[6:0];
                    gemm_opcode_o   <= w0_opcode;
                end
            end
            if (state == W_W14D && (!w0_valid || op_illegal))
                walker_error_id_o <= walker_head_o;

            // W_ENG 期间粘住 PS stop/abort（done 定案时消费）
            if (stop_i)
                stop_run_q <= 1'b1;
            if (state == W_ENG && (next_state != W_ENG))
                stop_run_q <= 1'b0;
            if (abort_i)
                abort_run_q <= 1'b1;
            if (state == W_ENG && (next_state != W_ENG))
                abort_run_q <= 1'b0;

            // engine done: advance queue pointers（abort/错误路径不前进）
            if (state == W_ENG && eng_done && !eng_err) begin
                walker_head_o <= head_next;
                walker_done_o <= walker_done_o + 16'd1;
            end
        end
    end

    // doorbell_commit is informational only (tail pointer is polled);
    // keep the port for contract stability
    wire unused_doorbell = doorbell_commit_i;
    wire unused_count    = desc_count_i;
    wire unused_busy     = ppu_busy_i;   // 备用：TB 断言 req|->!busy 用

endmodule
