/************************************************************************
 * File Name       : m9_ldload_fsm.v
 * Developer       : 装载 FSM 实现执行线（主工程席 75，2026-10-25）
 * Date            : 2026-10-25
 * Project Name    : YOLO object accel (PL 内 AXI-Lite 字对齐装载 FSM)
 * Module Name     : m9_ldload_fsm
 * Description     :
 *   PL 内 AXI-Lite 字对齐装载 FSM（呈批件 V2 实施，用户已批准）：
 *   submission 2026-10-25_loadfsm_design_prep_run01（sha f533e279…）
 *   §2.1 寄存器图（0x100-0x118 七个字对齐口，WSTRB=1111 显式门控，
 *   窄写 = OKAY + 粘滞 err_code=1，LD_ERR 清除豁免——唯一豁免面 C4③）
 *   §2.2 五态 FSM（S_IDLE/S_LATCH/S_COMMIT/S_WAIT/S_ERR）：
 *     - S_WAIT 等 page_tables 新增 rmw_idle 输出端口反压（C1 纯
 *       tap-off），禁固定拍距 pacing；
 *     - sel==2'b11（PAGE/pg_ram 直通）一拍提交直接回 S_IDLE，
 *       不进 S_WAIT（C4④）；
 *     - 越界预检 PPP/EDGE addr>=256、JOIN addr>=640、PAGE addr>=8
 *       → err_code=2 不提交（§2.2 S_LATCH）；
 *     - armed（门铃已打、done 未升沿）期 LD_DATA 提交硬件硬门
 *       err_code=3（§2.5 RUNTIME_WRITE = CSR 侧 sim $fatal 的硬件化）。
 *   §2.3 四边角：①LD_LEN 写=新事务（同清 LD_CNT，done 电平再评估）
 *   ②LD_LEN=0 永 done 退化 no-expectation 模式（不禁装）③LD_ERR 写
 *   清除不要求 WSTRB=1111（G1 唯一豁免面）④sel==11 一拍提交。
 *   §2.4 写表复用既有 tbl_* 四口，CSR 内 OR 合流
 *   （tbl_we = tbl_we_w | ld_tbl_we）；游标自增与 EA 臂逐位等价
 *   （mod 256/256/640/8，G2；呈批件 §1.4 基准）。
 *   §2.5 错误面独立暴露：err 只进 LD_ERR 粘滞寄存器，零触 STATUS
 *   err[7:0]（C3 裁定选项 b）。局部 4bit 码：1=WSTRB_VIOL /
 *   2=ADDR_RANGE / 3=RUNTIME_WRITE / 4=SKID_OVERFLOW（保留不可达）/
 *   5=BUSY_COLLIDE（S_WAIT 反压期又来 LD_DATA，纯保险面）。
 *
 *   done 语义（C4②）：done = (LD_CNT >= LD_LEN) 纯电平比较器。
 *   LD_CNT 10bit，饱和于 3FF（防回绕令 done 振荡；呈件未预写此角，
 *   实施裁量记录于执行 run README）。
 *
 *   存储律：本模块零新存储——仅 ~40 个触发器（状态/配置/锁存），
 *   PPP/EDGE/JOIN/PAGE 四表全部复用既有 m9_page_tables 三核 BMG
 *   （大数组 BRAM-IP 铁律：本 FSM 无新表，无需新 IP）。
 *
 * Dependencies    : 由 m9_abi_v2_csr 例化（sibling-module 律，§2.2）
 * Revision History:
 *   - V1.0 (2026-10-25) : 呈批件 V2 首实施（本执行 run 影树）。
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_ldload_fsm (
    input  wire        clk          ,
    input  wire        rst_n        ,
    // ---- CSR 写译码 strobe（wr_go 拍限定，1 拍脉冲）------------------
    input  wire        ld_data_hit  ,  // 0x100 LD_DATA 写命中（WO 面）
    input  wire        ld_sel_hit   ,  // 0x104 LD_SEL   写命中
    input  wire        ld_addr_hit  ,  // 0x108 LD_ADDR  写命中
    input  wire        ld_len_hit   ,  // 0x10C LD_LEN   写命中
    input  wire        ld_err_hit   ,  // 0x114 LD_ERR   写命中（清除；
                                       //   G1 WSTRB 门控唯一豁免面 C4③）
    input  wire [31:0] wdata        ,  // w_data_q（写数据保持寄存）
    input  wire [3:0]  wstrb        ,  // w_strb_q（同拍锁存，G1 判据）
    // ---- 守卫面 -------------------------------------------------------
    input  wire        armed        ,  // 门铃已置位、done 未升沿
    input  wire        rmw_idle     ,  // page_tables C1 tap-off 输出
    // ---- 写表面（CSR 内与既有 tbl_* 四口 OR 合流，§2.4）--------------
    output wire        ld_tbl_we    ,
    output wire [1:0]  ld_tbl_sel   ,
    output wire [9:0]  ld_tbl_addr  ,
    output wire [31:0] ld_tbl_wdata ,
    // ---- 读回面（0x104/0x108/0x10C/0x110/0x114/0x118）----------------
    output wire        ld_busy      ,  // = (state != S_IDLE)
    output wire        ld_done      ,  // = (LD_CNT >= LD_LEN) 电平
    output wire [3:0]  ld_err_code  ,  // 粘滞 err（LD_ERR 写清 / rst_n）
    output wire [9:0]  ld_cnt       ,
    output wire [1:0]  ld_sel_o     ,
    output wire [9:0]  ld_addr_o    ,
    output wire [9:0]  ld_len_o
);

    // ---------------- 5 态（§2.2）+ 局部错误码（§2.5）------------------
    localparam S_IDLE   = 3'd0;
    localparam S_LATCH  = 3'd1;
    localparam S_COMMIT = 3'd2;
    localparam S_WAIT   = 3'd3;
    localparam S_ERR    = 3'd4;

    localparam E_NONE    = 4'd0;
    localparam E_WSTRB   = 4'd1;   // WSTRB_VIOL（G1 显式门控）
    localparam E_RANGE   = 4'd2;   // ADDR_RANGE（越界预检）
    localparam E_ARMED   = 4'd3;   // RUNTIME_WRITE（armed 硬门）
    localparam E_SKID    = 4'd4;   // SKID_OVERFLOW（保留，协议不可达）
    localparam E_COLLIDE = 4'd5;   // BUSY_COLLIDE（S_WAIT 期又来 LD_DATA）

    reg [2:0]  state;
    reg [1:0]  ld_sel_r;
    reg [9:0]  ld_addr_r;
    reg [9:0]  ld_len_r;
    reg [9:0]  ld_cnt_r;
    reg [3:0]  err_r;
    reg [31:0] lat_data;

    // 越界预检界限（§2.2 S_LATCH；sel==11 用 addr>=8 对齐 page_tables
    // L477-478 守卫；C4④）
    wire [9:0] lim = (ld_sel_r == 2'b10) ? 10'd640 :
                     (ld_sel_r == 2'b11) ? 10'd8   : 10'd256;
    wire addr_oob = (ld_addr_r >= lim);

    // G1 门控面 = 四装载提交寄存器（LD_ERR/LD_STAT 不受其限，§2.3③）
    wire gated_hit = ld_data_hit | ld_sel_hit | ld_addr_hit | ld_len_hit;
    wire wstrb_bad = (wstrb != 4'b1111);

    // ---------------- 主状态机（单 always 块，多驱动律）----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            ld_sel_r  <= 2'd0;
            ld_addr_r <= 10'd0;
            ld_len_r  <= 10'd0;
            ld_cnt_r  <= 10'd0;
            err_r     <= E_NONE;
            lat_data  <= 32'd0;
        end else begin
            case (state)
            // -------- S_IDLE：受理配置写；busy=0 -------------------------
            S_IDLE: begin
                if (ld_err_hit) begin
                    err_r <= E_NONE;            // C4③ 任何写命中即清
                end else if (gated_hit && wstrb_bad) begin
                    err_r <= E_WSTRB;           // G1：不提交 + 粘滞 err
                    state <= S_ERR;
                end else if (ld_len_hit) begin
                    ld_len_r <= wdata[9:0];     // C4① 新事务
                    ld_cnt_r <= 10'd0;          // 同清 CNT（done 再评估）
                end else if (ld_sel_hit) begin
                    ld_sel_r <= wdata[1:0];
                end else if (ld_addr_hit) begin
                    ld_addr_r <= wdata[9:0];    // 游标直设
                end else if (ld_data_hit) begin
                    if (armed) begin
                        err_r <= E_ARMED;       // §2.5 硬门（hardware
                        state <= S_ERR;         //   化 CSR sim $fatal）
                    end else if (addr_oob) begin
                        err_r <= E_RANGE;       // 越界预检：不提交
                        state <= S_ERR;
                    end else begin
                        lat_data <= wdata;      // S_LATCH 锁存拍
                        state    <= S_LATCH;
                    end
                end
            end
            // -------- S_LATCH：锁存拍（数据已入 lat_data）----------------
            S_LATCH: state <= S_COMMIT;
            // -------- S_COMMIT：一拍驱动 tbl_we + 游标自增（EA 臂同式，
            //          G2：PPP/EDGE mod 256、JOIN mod 640、PAGE mod 8）---
            S_COMMIT: begin
                ld_cnt_r  <= (ld_cnt_r == 10'h3FF) ? 10'h3FF
                                                   : ld_cnt_r + 10'd1;
                if (ld_sel_r == 2'b00 || ld_sel_r == 2'b01)
                    ld_addr_r <= (ld_addr_r == 10'd255) ? 10'd0
                                            : ld_addr_r + 10'd1;
                else if (ld_sel_r == 2'b10)
                    ld_addr_r <= (ld_addr_r == 10'd639) ? 10'd0
                                            : ld_addr_r + 10'd1;
                else
                    ld_addr_r <= (ld_addr_r == 10'd7) ? 10'd0
                                            : ld_addr_r + 10'd1;
                // C4④：PAGE（pg_ram 直通不进 RMW）一拍提交回 S_IDLE
                state <= (ld_sel_r == 2'b11) ? S_IDLE : S_WAIT;
            end
            // -------- S_WAIT：rmw_idle 端口反压（C1，禁固定拍距）---------
            S_WAIT: begin
                if (ld_err_hit) begin
                    err_r <= E_NONE;
                    state <= S_IDLE;
                end else if (rmw_idle) begin
                    state <= S_IDLE;            // busy=0
                end else if (ld_data_hit) begin
                    err_r <= E_COLLIDE;         // §2.5 code 5 保险面
                    state <= S_ERR;
                end else if (gated_hit && wstrb_bad) begin
                    err_r <= E_WSTRB;           // G1 对配置写同律
                    state <= S_ERR;
                end else if (ld_len_hit) begin
                    ld_len_r <= wdata[9:0];     // 配置写 S_WAIT 期仍受理
                    ld_cnt_r <= 10'd0;
                end else if (ld_sel_hit) begin
                    ld_sel_r <= wdata[1:0];
                end else if (ld_addr_hit) begin
                    ld_addr_r <= wdata[9:0];
                end
            end
            // -------- S_ERR：粘滞错误保持；LD_ERR 写清 / rst_n 复位 ------
            S_ERR: begin
                if (ld_err_hit) begin
                    err_r <= E_NONE;
                    state <= S_IDLE;
                end
                // 其余写命中一律忽略：错误面不能被楔死（C4③ 理由）
            end
            default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------- 写表面（S_COMMIT 组合一拍脉冲）--------------------
    assign ld_tbl_we    = (state == S_COMMIT);
    assign ld_tbl_sel   = ld_sel_r;
    assign ld_tbl_addr  = ld_addr_r;   // 自增在拍沿，当拍仍为提交地址
    assign ld_tbl_wdata = lat_data;

    // ---------------- 读回面 --------------------------------------------
    assign ld_busy     = (state != S_IDLE);
    assign ld_done     = (ld_cnt_r >= ld_len_r);   // C4② LEN=0 永 done
    assign ld_err_code = err_r;
    assign ld_cnt      = ld_cnt_r;
    assign ld_sel_o    = ld_sel_r;
    assign ld_addr_o   = ld_addr_r;
    assign ld_len_o    = ld_len_r;

endmodule
