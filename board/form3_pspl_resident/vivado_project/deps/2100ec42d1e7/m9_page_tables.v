/************************************************************************
 * File Name       : m9_page_tables.v
 * Developer       : C3 r12 build line (A 方案 BRAM IP 化, user ruling
 *                   2026-10-21: 大数组走 BRAM / 能 IP 就 IP)
 * Date            : 2026-10-21
 * Project Name    : YOLO object accel (C3 r12, A1_bram_plan.md v2.1)
 * Module Name     : m9_page_tables
 * Description     :
 *   M11a page-scheduling tables, BRAM IP 化重写（v2.1 设计冻结，
 *   competition-b6 设计审计双过）。存储三表 = blk_mem_gen 宽字核
 *   （1 行 = 1 窗；A1_bram_plan.md §1.3 逐表 lane 规格）：
 *
 *     m9_bm_pptab    32 行 x 256b（8 PPP 词/行）
 *     m9_bm_edgetab  32 行 x 256b（8 EDGE 词/行）
 *     m9_bm_jointab  32 行 x 640b（20 JOIN 词/行）
 *     pg_ram[0:7]    保留 FF（8x32b 页描述符，小状态，复位零语义）
 *
 *   V3.0（B3 改造，B 期 v2 呈件 R122 裁项 2 照准 2026-10-25）：
 *     三核 Memory_Type TDP→SDP（三 xci 同改：Simple_Dual_Port_RAM +
 *     Use_Byte_Write_Enable=false，宽度/深度/算法/输出寄存全不变）。
 *     SDP A 口纯写（无 douta）→ 写面与读回面全部重排：
 *       [写面 RMW] A 口整行写（wea 1bit，无字节使能）。tbl_we 全字
 *       写与 lds lane 写统一走行 RMW 引擎：B 口读行 → 目标词按
 *       lane 字节合并 → A 口整行写回。skid 1 深（pend）吸收
 *       back-to-back 写（AXI-Lite 单未完成写律下间隙 ≥3 拍，skid
 *       纯保险）。pg_ram 写（sel==11）不涉 BRAM，直通不变。
 *       [读回迁 B 口] req/gnt 对外契约不变：req 保持至 gnt、gnt 拍
 *       携带数据、gnt = 受理后 2 拍（受理拍 = B 口发起拍）。受理
 *       需 rmw_idle（读到写后行）。
 *       [B 口仲裁重写] 优先级 pref > rd > rmw > fill，单发律：每拍
 *       至多一发起，发起+1 拍为数据拍，各客户端捕获寄存器互不重叠。
 *       pref/fill 三核并行发起；rd/rmw 只发起目标单核（enb/addrb
 *       按目标选通）。fill_launch 增 rmw_idle 门 + FSM dirty→filling
 *       转移改挂 grant_fill（防止 rd/rmw 抢口后 filling 空转捕获）。
 *     B 口 READ_LATENCY=1 契约（V2.3b/r11 硅证正典）不变：输出寄存
 *     =false 未动；回填/预取发起-捕获错开一拍账不变。
 *
 *   组织律（字地址 a -> 行/行内词）：
 *     ppp/edge : row = a[7:3], w = a[2:0]（8 词/行）
 *     join     : row = a[9:5], w = a[4:0]（20 词/行）
 *
 *   窗口面（对外组合输出，位布局与 v1.0 逐位一致）：
 *     窗行先入 bank 寄存器再切片输出。bank = BRAM B 口（有效延迟 1，
 *     V2.3b：输出寄存=false 微仿真实证 bmg_latency_probe）后的寄存副本；
 *     pg_desc_o 保持 v1.0 组合语义
 *     （pg_ram 是 FF，always@* 读词后切片，window law 兼容）。
 *
 *   预取握手（页路径零拍变化，落地条件 1）：
 *     pg_pref（issuer 在 S_ADV 页推进分支拍拉高，共享 wire 复用
 *     L1522 完整条件链）当拍用 page_r+1 的描述符（组合）送三核 B 口
 *     并行读（IP B 口输出寄存=false 有效延迟 1，V2.3b 配置更正）→
 *     pg_pref_d 拍
 *     （=S_PGE0）拍末捕获 banks → bump 后 cycle1 起新窗有效
 *     （sanity 流水逐拍对齐保持，G2 零漂移）。
 *
 *   回填与就绪（doorbell 路径 issuer 零改，落地条件 2/4）：
 *     dirty 源 = reset（条件 4：复位必须 dirty=1/win_rdy=0，未定义初窗
 *     不得顶着就绪被消费）/ 任何写 / page_r 变化检测（S_DONE 回 0 与
 *     prefetch 后 page_d 追上等场景；预取已覆盖的再回填一次读同行，
 *     冗余但一致，正确性优先于聪明）。
 *     dirty 且无写 → dirty 拍三核 B 口并行发起（fill_launch）→ 下一拍
 *     （filling）出数、拍末捕获 banks → 再一拍 win_rdy=1。CSR 侧 pending
 *     锁存 + 就绪重发门控 start（禁止与门
 *     蒸发脉冲；运行期写表 = 违约由 CSR 侧 $fatal 守卫，本模块保留
 *     tbl_we&&lds_we 碰撞守卫与写-读不交织守卫）。
 *
 *   B 口仲裁不变式（落地条件 5）：pg_pref 预取（run）与 dirty 回填
 *   （setup）时间不相交（load/run 分离律）；同拍冲突 pg_pref 优先
 *   （仲裁最高级），sim 下 $fatal 违约守卫。
 *
 *   读回口（B 口，req/gnt 握手）：**对外接口自 v1.0 不变**——
 *   req 保持至 gnt，gnt 起 2 拍（req 受理拍 = B 口发起拍、BRAM
 *   数据拍、gnt 寄存拍）。CSR 读 FSM hold RVALID 至 gnt。pg_ram 读回
 *   （sel==2'b11）同握手返回，维持单一时序面。契约：setup 期表写与
 *   表读回不交织（在飞拍来写有 sim $fatal 守卫，PS AXI 间隙天然成立）。
 *   req 保持至 gnt，gnt 拍不接收新 req（防幽灵二次受理，V2.2 补）。
 *
 *   Dependencies    : m9_bm_pptab / m9_bm_edgetab / m9_bm_jointab
 *                     (blk_mem_gen 8.4, SDP, 无 COE 无复位)
 * Revision History:
 *   - V2.0 (2026-10-21) : BRAM IP 化重写（v1.0 M11a FF 数组版资源炸点
 *     见坑册 rtl 域「异步复位 FF 数组永不推断 RAM」条目）。
 *   - V2.1 (2026-10-21) : competition-b6 代码审计 D1-D3 修订——D1 join
 *     内网向量扩 1024b/128b + IP 端口切片（类型界检越界，elab 必 ERROR
 * 	   类）；D2 读回在飞拍写侵入 $fatal 守卫 + setup 写读不交织契约；
 *     D3 filling 拍 wr_any 吞 dirty 修复（dirty<=wr_any）+ win_rdy 定义
 *     收紧为 settled&&!dirty；pg_pref 守卫补 filling 条件闭合断言覆盖。
 *   - V2.2 (2026-10-21) : b6 部分打回补修——D1 第三处（join 读回选词
 *     join_douta_p 1024b pad）+ JOIN 读回越址 $fatal 守卫（与写口对齐）。
 *   - V2.3 (2026-10-21) : 自查修正 B 口发起/捕获同拍错误——IP 输出寄
 *     存致 READ_LATENCY=1，旧代码读发起拍即捕获 = 永采旧数（fill 首填
 *     垃圾窗/pref 新窗永不入 bank）。改 fill_launch（dirty 拍发起）+
 *     pg_pref_d（次拍捕获）；功能账与 A1 §1.1/§1.2 设计一致，实现错位。
 *   - V2.3b (2026-10-22) : IP 重配 Register_PortA/B_Output_of_Memory_
 *     Primitives=false（r11 硅证正典：m9_bm_wblk/hbuf 全 false 一拍约定；
 *     true 时硅上有效延迟 2 = DOB_REG 级，且 xsim 行为模型对孤立单拍读
 *     不吐数、功能梯结构性失明——micro-test evidence/bmg_latency_probe）。
 *     有效延迟 1 ⇒ V2.3 一拍偏斜正典不动，逻辑零改动，仅注释更正。
 *   - V3.0 (2026-10-25) : B3 改造（上见 Description V3.0 块；改造面 =
 *     三 xci SDP/去字节使能 + 读本文件；issuer/CSR 零改，模块对外端口
 *     零改。行 RMW + 读回迁 B 口 + B 口仲裁重写 + 碰撞守卫改写）。
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_page_tables (
    input  wire        clk        ,
    input  wire        rst_n      ,
    // ---- load face (CSR 0xE9 cursor / 0xEA data, setup phase only) ----
    input  wire        tbl_we     ,
    input  wire [1:0]  tbl_sel    ,
    input  wire [9:0]  tbl_addr   ,   // raw RAM row address
    input  wire [31:0] tbl_wdata  ,
    // ---- legacy partial-word write face (CSR 0xD8/0xDC/0xF4 v2.4
    //      routing; byte-lane writes into the SAME BRAMs) ----
    input  wire        lds_we     ,
    input  wire [1:0]  lds_sel    ,
    input  wire [9:0]  lds_addr   ,
    input  wire [31:0] lds_wdata  ,
    input  wire [3:0]  lds_lane   ,   // byte enables
    // ---- load readback face (req/gnt handshake, gnt 起 2 拍) ----------
    input  wire        tbl_rd_req ,
    input  wire [1:0]  tbl_rd_sel ,
    input  wire [9:0]  tbl_rd_addr,
    output reg         tbl_rd_gnt ,
    output reg  [31:0] tbl_rd_data,
    // ---- window read face ----------------------------------------------
    input  wire [2:0]  page_r     ,
    input  wire        pg_pref    ,   // next cycle bumps page (issuer
                                       // S_ADV branch shared-wire law)
    output reg  [31:0] pg_desc_o  ,   // v1.0 组合语义保持（FF 阵列）
    output wire [255:0] ppp_win_o ,
    output wire [63:0] edge_node_o,
    output wire [63:0] edge_prod_o,
    output wire [127:0] edge_win_o,
    output wire [639:0] join_win_o,
    output reg         win_rdy,       // window bank settled & no dirty
    // ---- 装载 FSM 反压面（呈批件 V2 C1 修订：纯 tap-off，零逻辑/零
    //      时序增量——L192 既有 wire 引出为输出；S_WAIT 等此口，禁固定
    //      拍距 pacing）------------------------------------------------
    output wire        rmw_idle
);

    // ---------------- pg_ram (page descriptors, FF, reset-zero law) -----
    reg [31:0] pg_ram [0:7];
    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (pi = 0; pi < 8; pi = pi + 1)
                pg_ram[pi] <= 32'd0;
        end else if (tbl_we && (tbl_sel == 2'b11))
            pg_ram[tbl_addr[2:0]] <= tbl_wdata;
    end

    // pg_desc_o 与 B 口行地址：v1.0 组合语义（always@* 读词后切片，
    // window law）。预取拍读 NEXT 页描述符，其余拍读 ACTIVE 页。
    reg [2:0]  pg_addr_c;
    reg [31:0] pg_desc_t;
    reg [4:0]  b_ppp_row, b_edge_row, b_join_row;
    always @(*) begin
        pg_addr_c  = pg_pref ? (page_r + 3'd1) : page_r;
        pg_desc_t  = pg_ram[pg_addr_c];          // 词先读后切片
        b_ppp_row  = pg_desc_t[14:10];
        b_edge_row = pg_desc_t[19:15];
        b_join_row = pg_desc_t[24:20];
        pg_desc_o  = pg_ram[page_r];             // v1.0 逐位语义
    end

    // ---------------- write decode（tbl/lds 合流，与 v2.x 一致）--------
    wire        wr_any   = tbl_we || lds_we;
    wire [1:0]  wr_sel   = tbl_we ? tbl_sel    : lds_sel;
    wire [9:0]  wr_addr  = tbl_we ? tbl_addr   : lds_addr;
    wire [31:0] wr_data  = tbl_we ? tbl_wdata  : lds_wdata;
    wire [3:0]  wr_lane  = tbl_we ? 4'b1111    : lds_lane;

    // ---------------- B3: RMW 写引擎（A 口 = SDP 纯写口）---------------
    // SDP 去字节使能 → A 口整行写（wea 1bit）。全字写(tbl_we)与 lds
    // lane 写统一为行 RMW：B 口读行（仲裁授权拍）→ 次拍 doutb 有效、
    // 目标词按 lane 字节合并 → 当拍 A 口整行写回（写于 MODIFY 拍沿
    // 提交）。skid 1 深（rm_pend）吸收 back-to-back 写。pg_ram 写
    // （sel==11）不涉 BRAM，直通 pg_ram，不进本引擎。
    wire        wr_br   = wr_any && (wr_sel != 2'b11);
    wire [4:0]  wr_row  = (wr_sel == 2'b10) ? wr_addr[9:5]
                                            : wr_addr[7:3];
    wire [4:0]  wr_widx = (wr_sel == 2'b10) ? wr_addr[4:0]
                                            : {2'b00, wr_addr[2:0]};

    localparam RM_IDLE = 2'd0, RM_READ = 2'd1, RM_MODIFY = 2'd2;
    reg [1:0]   rm_state;
    reg         rm_pend;
    reg [1:0]   rm_sel,  p_sel;
    reg [4:0]   rm_row,  p_row;
    reg [4:0]   rm_widx, p_widx;
    reg [31:0]  rm_data, p_data;
    reg [3:0]   rm_lane, p_lane;

    // C1 tap-off：原模块内 wire 原式引出为输出（呈批件 V2 修订声明：
    // 零逻辑改动、零时序增量；装载 FSM S_WAIT 以此为唯一反压判据）
    assign rmw_idle = (rm_state == RM_IDLE) && !rm_pend;

    // B 口仲裁授权（声明提前，驱动块见下）
    wire grant_pref, grant_rd, grant_rmw, grant_fill, b_rd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rm_state <= RM_IDLE; rm_pend <= 1'b0;
            rm_sel   <= 2'b00; rm_row  <= 5'd0; rm_widx <= 5'd0;
            rm_data  <= 32'd0; rm_lane <= 4'd0;
            p_sel    <= 2'b00; p_row   <= 5'd0; p_widx  <= 5'd0;
            p_data   <= 32'd0; p_lane  <= 4'd0;
        end else begin
            // skid 吸收：RM_READ 在飞时来新写 → 入 pend（RM_MODIFY
            // 拍内的新写由 MODIFY 分支直接接力，不入 pend）
            if (wr_br && (rm_state == RM_READ)) begin
                rm_pend <= 1'b1;
                p_sel   <= wr_sel;  p_row   <= wr_row;
                p_widx  <= wr_widx; p_data  <= wr_data;
                p_lane  <= wr_lane;
            end else if ((rm_state == RM_MODIFY) && rm_pend)
                rm_pend <= 1'b0;     // MODIFY 分支消耗 pend
            case (rm_state)
            RM_IDLE:
                if (wr_br) begin
                    rm_sel   <= wr_sel;  rm_row  <= wr_row;
                    rm_widx  <= wr_widx; rm_data <= wr_data;
                    rm_lane  <= wr_lane;
                    rm_state <= RM_READ;
                end
            RM_READ:
                if (grant_rmw) rm_state <= RM_MODIFY;
            RM_MODIFY:
                if (rm_pend) begin
                    rm_sel   <= p_sel;  rm_row  <= p_row;
                    rm_widx  <= p_widx; rm_data <= p_data;
                    rm_lane  <= p_lane;
                    rm_state <= RM_READ;
                end else if (wr_br) begin
                    rm_sel   <= wr_sel;  rm_row  <= wr_row;
                    rm_widx  <= wr_widx; rm_data <= wr_data;
                    rm_lane  <= wr_lane;
                    rm_state <= RM_READ;
                end else
                    rm_state <= RM_IDLE;
            default: rm_state <= RM_IDLE;
            endcase
        end
    end

    // 字节合并：lane[b] ? 新字节 : 旧字节（BRAM 字节使能语义在
    // RTL 层的等价实现——B3 去硬件字节使能后的标准补偿）
    function [31:0] mrg_word(input [31:0] old_w, input [31:0] new_w,
                             input [3:0] lane);
        integer cb;
        begin
            for (cb = 0; cb < 4; cb = cb + 1)
                mrg_word[cb*8 +: 8] = lane[cb] ? new_w[cb*8 +: 8]
                                               : old_w[cb*8 +: 8];
        end
    endfunction

    // A 口写驱动：MODIFY 拍对目标核 wea=1 整行写（doutb 当拍有效、
    // 组合合并、同拍提交——RMW 无额外延迟级）
    wire        rm_we      = (rm_state == RM_MODIFY);
    wire        rm_we_ppp  = rm_we && (rm_sel == 2'b00);
    wire        rm_we_edge = rm_we && (rm_sel == 2'b01);
    wire        rm_we_join = rm_we && (rm_sel == 2'b10);

    // ---------------- dirty / fill FSM（三表并行回填） -------------
    // reset 必须 dirty=1（落地条件 4）；发起在 dirty 拍（fill_launch，
    // 见上时序账），filling=1 拍 = 出数+捕获拍。
    // B3：dirty→filling 转移挂 grant_fill（rd/rmw 抢口时本拍不转移，
    // dirty 保持，下拍重试——杜绝 filling 空转捕获他客户端数据）。
    reg dirty, filling;
    reg [2:0] page_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dirty   <= 1'b1;
            filling <= 1'b0;
            page_d  <= 3'd0;
        end else begin
            page_d <= page_r;
            if (pg_pref && (dirty || filling)) begin
`ifndef SYNTHESIS
                // 条件 5 守卫：filling 拍 dirty 仍在位（NBA 末才清），原
                // 写法 filling 分支短路使本断言不可达——补 filling 条件
                // 闭合断言覆盖（competition-b6 非阻断备注采纳）。
                $fatal(1, "M9PGTBL_FAIL pg_pref while dirty (load/run violation)");
`endif
            end else if (filling) begin
                filling <= 1'b0;
                // D3（应修）：回填拍恰来一笔写时，bank 捕到写前内容——
                // 有写则保持脏，下轮重回填捕获写后内容（dirty 优先律）。
                dirty   <= wr_any;
            end else if (wr_any || (page_r != page_d)) begin
                dirty   <= 1'b1;
            end else if (dirty) begin
                if (grant_fill) filling <= 1'b1;  // B3：挂授权而非条件
            end
        end
    end

    // D3：win_rdy 定义收紧为「settled && !dirty」——回填拍若伴写，
    // dirty 保持 1（见 FSM），win_rdy 必须不置位（dirty 优先级高于
    // filling 捕获）；等下轮重回填捕获写后内容再就绪。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              win_rdy <= 1'b0;
        else if (wr_any || (page_r != page_d))
                                 win_rdy <= 1'b0;
        else if (filling)        win_rdy <= !wr_any;  // = 次拍 !dirty 语义
    end

    // B 口时序账（V2.3 自查修正 + V2.3b 配置更正）：IP B 口输出寄存 =
    // false（2026-10-22 裁定，对齐 r11 硅证正典）→ 有效延迟 1（地址/使能
    // 拍 T 采样，数据拍 T+1 出）。读发起与 bank 捕获必须错开一拍——
    // 旧实现同拍发起+捕获 = 永远采旧数（fill 路径上电首填即填垃圾窗，
    // pg_pref 路径新窗永不入 bank；elab 不检时序，功能梯必抓型）：
    //   回填：dirty 拍并行发起（fill_launch）→ filling 拍数据出、
    //         拍末捕获 banks、dirty 清、win_rdy 下一拍置 1；
    //   预取：pg_pref 拍发起（page_r+1 行址）→ pg_pref_d 拍
    //         （=S_PGE0）拍末捕获 → bump 后 cycle1 新窗有效（零漂移）。
    reg        pg_pref_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pg_pref_d <= 1'b0; else pg_pref_d <= pg_pref;
    // fill_launch = 请求（授权在仲裁器）；rmw_idle 门保证 A 口 RMW
    // 写提交拍与 B 口回填捕获拍永不同拍（否则 stale settle）。
    wire fill_launch = dirty && !filling && !wr_any && !pg_pref && rmw_idle;

    // ---------------- B 口仲裁（单发律）-------------------------------
    // 优先级 pref > rd > rmw > fill；每拍至多一发起，发起+1 拍为数据
    // 拍，各客户端捕获（bank / rd_data / rm MODIFY 用 doutb）互不重叠。
    // pref/fill 三核并行发起（enb 三核同拉）；rd/rmw 单核选通。
    // rd 受理需 rmw_idle：读到写后行（RMW A 写提交后发起）。
    // ---------------- readback（B 口；req/gnt 契约不变）----------------
    // 受理拍 = B 口发起拍（grant_rd）→ +1 拍 doutb 有效、选词锁存 →
    // +2 拍 gnt=1 且数据随 gnt（rd_data 于 +1 拍沿锁存，gnt 拍稳定）。
    // req 保持至 gnt；gnt 拍不接收新 req（!tbl_rd_gnt 旧值条件，V2.2）。
    reg        rd_pend, rd_inflight;
    reg [1:0]  rd_sel_q;
    reg [9:0]  rd_addr_q;
    wire [4:0] rd_row = (tbl_rd_sel == 2'b10) ? tbl_rd_addr[9:5]
                                              : tbl_rd_addr[7:3];
    assign grant_pref = pg_pref;
    assign grant_rd   = !grant_pref && rd_pend && rmw_idle;
    assign grant_rmw  = !grant_pref && !grant_rd && (rm_state == RM_READ);
    assign grant_fill = !grant_pref && !grant_rd && !grant_rmw && fill_launch;
    assign b_rd       = grant_pref | grant_rd | grant_rmw | grant_fill;

    // ---------------- window bank（BRAM B 口 READ_LATENCY=1 后捕获）----
    wire [255:0] ppp_doutb, edge_doutb;
    wire [639:0] join_doutb;
    wire [1023:0] join_doutb_p = {384'd0, join_doutb};   // D1 pad 形态沿用
    reg  [255:0] ppp_bank, edge_bank;
    reg  [639:0] join_bank;
    wire b_pref  = pg_pref_d;   // 捕获窗口 = 发起拍的下一拍
    wire b_fill  = filling;     // = grant_fill 的下一拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ppp_bank  <= 256'd0;
            edge_bank <= 256'd0;
            join_bank <= 640'd0;
        end else if (b_pref || b_fill) begin
            ppp_bank  <= ppp_doutb ;
            edge_bank <= edge_doutb;
            join_bank <= join_doutb;
        end
    end

    // ---------------- window outputs（bank 组合切片，位布局同 v1.0）-----
    assign ppp_win_o = ppp_bank;
    assign join_win_o = join_bank;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_edge_slice
            assign edge_node_o[gi*8 +: 8] = edge_bank[gi*32    +: 8];
            assign edge_prod_o[gi*8 +: 8] = edge_bank[gi*32+8  +: 8];
            assign edge_win_o [gi*16 +:16] = edge_bank[gi*32+16 +:16];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pend <= 1'b0; rd_inflight <= 1'b0;
            rd_sel_q <= 2'b00; rd_addr_q <= 10'd0;
            tbl_rd_gnt <= 1'b0; tbl_rd_data <= 32'd0;
        end else begin
            tbl_rd_gnt <= 1'b0;
            if (grant_rd) begin
                rd_pend     <= 1'b0;
                rd_inflight <= 1'b1;
                rd_sel_q    <= tbl_rd_sel;
                rd_addr_q   <= tbl_rd_addr;
            end else if (rd_inflight) begin
                rd_inflight <= 1'b0;
                tbl_rd_gnt  <= 1'b1;         // 数据随 gnt 同拍有效
                case (rd_sel_q)
                2'b00:   tbl_rd_data <= ppp_doutb     [rd_addr_q[2:0]*32 +: 32];
                2'b01:   tbl_rd_data <= edge_doutb    [rd_addr_q[2:0]*32 +: 32];
                2'b10:   tbl_rd_data <= join_doutb_p  [rd_addr_q[4:0]*32 +: 32];
                2'b11:   tbl_rd_data <= pg_ram   [rd_addr_q[2:0]];
                default: tbl_rd_data <= 32'd0;
                endcase
            end else if (tbl_rd_req && !tbl_rd_gnt) begin
                rd_pend <= 1'b1;   // 受理前挂起（仲裁等待），sel/addr 由
                                   // CSR 保持至 gnt，授权拍再锁存
            end
        end
    end

    // ---------------- B 口每核 enb/addrb 选通 --------------------------
    wire rd_ppp  = grant_rd  && (tbl_rd_sel == 2'b00);
    wire rd_edge = grant_rd  && (tbl_rd_sel == 2'b01);
    wire rd_join = grant_rd  && (tbl_rd_sel == 2'b10);
    wire rm_ppp  = grant_rmw && (rm_sel == 2'b00);
    wire rm_edge = grant_rmw && (rm_sel == 2'b01);
    wire rm_join = grant_rmw && (rm_sel == 2'b10);

    wire enb_ppp  = b_rd && (grant_pref || grant_fill || rd_ppp || rm_ppp);
    wire enb_edge = b_rd && (grant_pref || grant_fill || rd_edge || rm_edge);
    wire enb_join = b_rd && (grant_pref || grant_fill || rd_join || rm_join);

    wire [4:0] addrb_ppp  = rd_ppp ? rd_row : rm_ppp ? rm_row : b_ppp_row;
    wire [4:0] addrb_edge = rd_edge ? rd_row : rm_edge ? rm_row : b_edge_row;
    wire [4:0] addrb_join = rd_join ? rd_row : rm_join ? rm_row : b_join_row;

    // ---------------- RMW 合并行（MODIFY 拍组合驱动 A 口）--------------
    reg [255:0]  dina_ppp, dina_edge;
    reg [1023:0] dina_join;
    always @(*) begin
        dina_ppp  = ppp_doutb;
        dina_ppp [rm_widx[2:0]*32 +: 32] =
            mrg_word(ppp_doutb [rm_widx[2:0]*32 +: 32], rm_data, rm_lane);
        dina_edge = edge_doutb;
        dina_edge[rm_widx[2:0]*32 +: 32] =
            mrg_word(edge_doutb[rm_widx[2:0]*32 +: 32], rm_data, rm_lane);
        dina_join = join_doutb_p;   // D1 pad 形态基值 = 旧行（整行写回，
                                    // 非目标词保持——RMW 合并正确性依赖）
        dina_join[rm_widx*32 +: 32] =
            mrg_word(join_doutb_p[rm_widx*32 +: 32], rm_data, rm_lane);
    end

    // ---------------- BRAM IP instances（SDP，B3 重形）------------------
    // A 口：clka/ena/wea(1bit)/addra(行)/dina(整行)——纯写口。
    // B 口：clkb/enb/addrb/doutb——纯读口，READ_LATENCY=1（输出寄存
    // false，V2.3b 契约未动）。
    m9_bm_pptab u_pptab (
        .clka(clk), .ena(1'b1), .wea(rm_we_ppp),
        .addra(rm_row), .dina(dina_ppp),
        .clkb(clk), .enb(enb_ppp),
        .addrb(addrb_ppp), .doutb(ppp_doutb)
    );
    m9_bm_edgetab u_edgetab (
        .clka(clk), .ena(1'b1), .wea(rm_we_edge),
        .addra(rm_row), .dina(dina_edge),
        .clkb(clk), .enb(enb_edge),
        .addrb(addrb_edge), .doutb(edge_doutb)
    );
    m9_bm_jointab u_jointab (
        .clka(clk), .ena(1'b1), .wea(rm_we_join),
        .addra(rm_row), .dina(dina_join[639:0]),
        .clkb(clk), .enb(enb_join),
        .addrb(addrb_join), .doutb(join_doutb)
    );

    // ---------------- collision guard（sim-only，v1.0 律保留）-----------
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (tbl_we && lds_we)
            $fatal(1, "M9PGTBL_FAIL table-load/legacy-lane collision");
        // D2（契约保留）：读回在飞拍（受理拍、+1 数据拍）来一笔写
        // （新写脉冲）= setup 写读不交织违约。B3 另补 RMW 在飞第三
        // 写守卫（skid 1 深溢出 = PS 写速率契约违约）。
        if (wr_any && rd_inflight)
            $fatal(1, "M9PGTBL_FAIL table write during readback flight (setup write/read interleave)");
        if (wr_br && rm_pend)
            $fatal(1, "M9PGTBL_FAIL rmw skid overrun (3rd table write in flight)");
        if (tbl_we && ((tbl_sel == 2'b00 || tbl_sel == 2'b01) && (tbl_addr >= 10'd256)))
            $fatal(1, "M9PGTBL_FAIL load addr %0d >= 256 (sel=%0d)", tbl_addr, tbl_sel);
        if (tbl_we && (tbl_sel == 2'b10) && (tbl_addr >= 10'd640))
            $fatal(1, "M9PGTBL_FAIL load addr %0d >= 640 (JOIN)", tbl_addr);
        // JOIN 读回越址守卫与写口对齐——JOIN 读回 addr>=640 同属
        // PS 契约违例（pad 区数据无定义语义）。
        if (tbl_rd_req && (tbl_rd_sel == 2'b10) && (tbl_rd_addr >= 10'd640))
            $fatal(1, "M9PGTBL_FAIL readback addr %0d >= 640 (JOIN)", tbl_rd_addr);
        if (tbl_we && (tbl_sel == 2'b11) && (tbl_addr >= 10'd8))
            $fatal(1, "M9PGTBL_FAIL load addr %0d >= 8 (PAGE)", tbl_addr);
    end
`endif

endmodule
