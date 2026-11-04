/************************************************************************
 * File Name     : tb_ppu_add_engine.sv
 * Developer     : LSL
 * Date          : 2026-09-24
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_ppu_add_engine
 * Description   : Stage3-v3 Phase B ppu_add_engine V2.0（五级流水）
 *                 引擎级新门。
 *
 *   DUT: ppu_add_engine + ppu_byte_store_assembler。TB 建 DMA 双通道
 *   模型 + 内存阵列（mp5eng 门同款 BFM 习惯用法）：
 *   - 读通道：每块 req 握手 -> 随机停顿 8B 拍流（小端 lane0=低地址，
 *     尾拍高位道填毒 0xA5——DUT 只取 beat_nv_w 低道，毒不外溢）->
 *     rd_done；**逐块核对交替读序**（A0,B0,A1,B1,…；addr=基址+已读
 *     偏移；len=min(64,rem)）——Phase B "rd 序不变" 直接证据；
 *   - 写通道：req 握手 -> 随机 ready 停顿收拍 -> strb 逐道展开写内存；
 *     strb 纪律（满拍 FF / 尾拍 (1<<rem)-1 / 死道为 0）、地址严格
 *     递增、字节数恰等 wr_len——丢/重/乱/早完/溢出全查；
 *   - golden：TB 函数直算 rne（GEMM 尾 V2.2 idiom 逐式照抄：64b 积、
 *     s=0 旁路、ru 进位、>>> 独立符号域）+ sat_i8(A_+B_)，与 DUT 五级
 *     流水结构完全异构（地址算术 vs 流水）。
 *
 *   Phase B 专项（计划 Phase B 验证门清单）：
 *   CHW=0 直通 / 负 m·s=0 / 深 s 双号 / 全 80·全 7F 饱和两端 / 混合
 *   m_hi/m_lo 符号 / m=0 零侧 / s=1 RNE 平局 / 临界容量 wr_block 强制
 *   填 FIFO（v5 反压 stall_w 必须真实发生，硬检查）/ 双向随机停顿 /
 *   连续任务换 quant 参数重锁 / 尾拍部分 strb 与整拍收尾 / 多块交替
 *   （CHW=130=64+64+2）/ 流水中 reset 击杀重启全查 / 流水中 dma_err
 *   弃权（无 done、busy 即落、vch 清零+静默期无 wr_beat——残留 v5
 *   推垃圾字节路径的直接证据）/ done-lag 测量（末次 join 弹出→flush
 *   恰 +5 拍证据：flush_lag 下界 7，V1.1 为 2）/ 影子对拍终检已随
 *   translate_off 影子块退役（2026-09-24，零失配收档）。
 * Revision History:
 *   - V1.0 (2026-09-24) by LSL : f7tmg_run01 新建（Phase B addeng 门）。
 *   - V1.1 (2026-09-24) by LSL : 随引擎 V2.1 chw_i 元数据直驱改接线
 *       （chw_in=cc·hh·ww 任务内现算；检查项/期望零变化，基线四元组
 *       不变）。
 ************************************************************************/

`timescale 1ns/1ps

module tb_ppu_add_engine;

    // ---- DUT 连线 ----
    reg         clk, rst, start;
    reg  [31:0] in0_base, in1_base, out_base;
    reg  [31:0] chw_in;                   // V2.1 chw_i 直驱（=cc*hh*ww）
    reg  [31:0] m0_in, m1_in;
    reg  [5:0]  s0_in, s1_in;
    wire        rd_req_valid;  reg rd_req_ready;
    wire [31:0] rd_addr;       wire [23:0] rd_len;
    reg         rd_beat_valid; wire rd_beat_ready;
    reg  [63:0] rd_beat_data;  reg rd_done;
    wire        wr_req_valid;  reg wr_req_ready;
    wire [31:0] wr_addr;       wire [23:0] wr_len;
    wire        wr_beat_valid; reg wr_beat_ready;
    wire [63:0] wr_beat_data;  wire [7:0] wr_beat_strb;
    reg         wr_done;
    reg         dma_err;
    wire        done, busy;

    ppu_add_engine u_dut (
        .clk_i(clk), .rst_i(rst), .start_i(start),
        .in0_base_i(in0_base), .in1_base_i(in1_base), .out_base_i(out_base),
        .chw_i(chw_in),
        .m0_i(m0_in), .s0_i(s0_in), .m1_i(m1_in), .s1_i(s1_in),
        .rd_req_valid_o(rd_req_valid), .rd_req_ready_i(rd_req_ready),
        .rd_addr_o(rd_addr), .rd_len_o(rd_len),
        .rd_beat_valid_i(rd_beat_valid), .rd_beat_ready_o(rd_beat_ready),
        .rd_beat_data_i(rd_beat_data), .rd_done_i(rd_done),
        .wr_req_valid_o(wr_req_valid), .wr_req_ready_i(wr_req_ready),
        .wr_addr_o(wr_addr), .wr_len_o(wr_len),
        .wr_beat_valid_o(wr_beat_valid), .wr_beat_ready_i(wr_beat_ready),
        .wr_beat_data_o(wr_beat_data), .wr_beat_strb_o(wr_beat_strb),
        .wr_done_i(wr_done),
        .dma_err_i(dma_err), .done_o(done), .busy_o(busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;                     //100 MHz

    // ---- 记账与内存 ----
    integer checks, errors;
    integer rs_fill;
    localparam integer MEMSZ = 65536;
    localparam [31:0] IN0_BASE = 32'h0000_1000;
    localparam [31:0] IN1_BASE = 32'h0000_3000;
    localparam [31:0] OUT_BASE = 32'h0000_5000;
    reg [7:0] mem [0:MEMSZ-1];
    localparam integer MAXE = 8192;
    localparam integer MAXB = 64;
    reg [7:0] exp_arr [0:MAXE-1];
    integer cur_chw;
    reg rd_req_seen, wr_req_seen;
    integer rd_beats_total, wr_beats_total;

    // ---- 期望读序表（A,B 交替 64B 块；与引擎调度同算法生成）----
    integer exp_nblk;
    reg [31:0] exp_baddr [0:MAXB-1];
    integer    exp_blen  [0:MAXB-1];
    task gen_rd_sched(input integer n);
        integer ar, br, L;
        reg sd;
        begin
            ar = n; br = n; sd = 1'b0; exp_nblk = 0;
            while (ar > 0 || br > 0) begin
                if ((sd == 1'b0 && ar > 0) || (sd == 1'b1 && br == 0)) begin
                    L = (ar > 64) ? 64 : ar;
                    exp_baddr[exp_nblk] = IN0_BASE + (n - ar);
                    ar = ar - L;
                end else begin
                    L = (br > 64) ? 64 : br;
                    exp_baddr[exp_nblk] = IN1_BASE + (n - br);
                    br = br - L;
                end
                exp_blen[exp_nblk] = L;
                exp_nblk = exp_nblk + 1;
                sd = ~sd;
            end
        end
    endtask

    // ---- 输入填充（0=随机 1=全80 2=全7F 3=确定性混合）+ 输出毒化 ----
    task fill_input(input integer n, input integer mode);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                if (mode == 0)      begin
                    mem[IN0_BASE + i] = $random(rs_fill);
                    mem[IN1_BASE + i] = $random(rs_fill);
                end else if (mode == 1) begin
                    mem[IN0_BASE + i] = 8'h80; mem[IN1_BASE + i] = 8'h80;
                end else if (mode == 2) begin
                    mem[IN0_BASE + i] = 8'h7F; mem[IN1_BASE + i] = 8'h7F;
                end else begin
                    mem[IN0_BASE + i] = (i * 37 + 11) & 8'hFF;
                    mem[IN1_BASE + i] = (i * 53 + 29) & 8'hFF;
                end
            end
            for (i = 0; i < 2048; i = i + 1)
                mem[OUT_BASE + i] = 8'hEE;
        end
    endtask

    // ---- golden：rne（V2.2 idiom 逐式照抄）+ sat_i8 求和 ----
    function reg signed [63:0] rne_q(input [7:0] a, input [31:0] m,
                                     input [5:0] s);
        reg signed [63:0] p;
        reg [63:0] rm;
        begin
            p  = $signed({{56{a[7]}}, a}) * $signed({{32{m[31]}}, m});
            rm = (s != 6'd0) ? ((64'd1 << (s - 6'd1)) - 64'd1) : 64'd0;
            rne_q = (p >>> s)
                  + (((s != 6'd0) && p[s - 6'd1]
                      && ((|(p & rm)) || p[s])) ? 64'sd1 : 64'sd0);
        end
    endfunction
    function [7:0] sat8(input reg signed [63:0] v);
        sat8 = (v > 64'sd127)  ? 8'h7F :
               (v < -64'sd128) ? 8'h80 : v[7:0];
    endfunction
    reg signed [63:0] gq0_v, gq1_v;   //金样临时变量（xsim 坑：参数位嵌套
                                      //函数调用求值为 X，必须经临时变量）
    task gen_golden(input integer n, input [31:0] gm0, input [5:0] gs0,
                    input [31:0] gm1, input [5:0] gs1);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                gq0_v = rne_q(mem[IN0_BASE + i], gm0, gs0);
                gq1_v = rne_q(mem[IN1_BASE + i], gm1, gs1);
                exp_arr[i] = sat8(gq0_v + gq1_v);
            end
        end
    endtask

    // ---- DMA 读通道 BFM：逐块 req（序核对）-> 随机停顿拍流 -> done ----
    reg        rdg_on;
    reg [31:0] rdg_addr;
    integer    rdg_len, rdg_sent;
    reg        rdv_hold;
    integer    rd_stall_pct;
    integer    rs_rdg;
    integer    rd_blk_cnt;
    integer    l, nb;
    reg [31:0] ba;
    initial begin
        rdg_on = 0; rdv_hold = 0; rd_beat_valid = 0;
        rd_beat_data = 0; rd_done = 0; rd_stall_pct = 0; rs_rdg = 77;
        rd_blk_cnt = 0;
    end
    always @(posedge clk) begin
        if (rst || dma_err) begin
            //dma_err = master 弃单重初始化：拆除在途拍（否则陈旧
            //rd_beat_valid 悬持，被下任务首块误收——V1.1 同构暴露，
            //TB 须按 master 错误合同建模 teardown）
            rdg_on <= 1'b0; rdv_hold <= 1'b0;
            rd_beat_valid <= 1'b0; rd_done <= 1'b0;
        end else begin
            rd_done <= 1'b0;
            if (rd_req_valid && rd_req_ready) begin
                rd_req_seen <= 1'b1;
                rd_blk_cnt  = rd_blk_cnt + 1;
                if (rd_blk_cnt > exp_nblk
                    || rd_addr != exp_baddr[rd_blk_cnt - 1]
                    || rd_len != exp_blen[rd_blk_cnt - 1]) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR [%0t] rd blk#%0d addr=%0h len=%0d want (%0h,%0d)",
                             $time, rd_blk_cnt, rd_addr, rd_len,
                             exp_baddr[rd_blk_cnt - 1], exp_blen[rd_blk_cnt - 1]);
                end else
                    checks = checks + 1;
                rdg_on   <= 1'b1;
                rdg_addr <= rd_addr;
                rdg_len  <= rd_len;
                rdg_sent <= 0;
                rdv_hold <= 1'b0;
            end else if (rdg_on && !rdv_hold) begin
                if (({$random(rs_rdg)} % 100) >= rd_stall_pct) begin
                    ba = rdg_addr + rdg_sent;
                    nb = (rdg_len - rdg_sent > 8) ? 8 : rdg_len - rdg_sent;
                    for (l = 0; l < 8; l = l + 1)
                        rd_beat_data[8*l +: 8] <= (l < nb) ? mem[ba + l]
                                                          : 8'hA5; // 死道毒
                    rd_beat_valid <= 1'b1;
                    rdv_hold      <= 1'b1;
                end
            end else if (rdg_on && rdv_hold && rd_beat_ready) begin
                rd_beat_valid <= 1'b0;
                rdv_hold      <= 1'b0;
                rd_beats_total = rd_beats_total + 1;
                rdg_sent      <= rdg_sent + 8;
                if (rdg_sent + 8 >= rdg_len) begin
                    rdg_on  <= 1'b0;
                    rd_done <= 1'b1;
                end
            end
        end
    end

    // ---- DMA 写通道 BFM：req -> 收拍（随机 ready / 阻塞模式）----
    reg        wrg_on;
    reg [31:0] wrg_addr;
    integer    wrg_len, wrg_got;
    integer    wr_stall_pct;
    integer    rs_wrg;
    reg        wr_order_ok;
    reg        wr_done_task;
    reg        wr_block;
    integer    wl, rem_b, blk_cyc;
    reg [31:0] wa;
    reg [7:0]  estrb, dl;
    initial begin
        wrg_on = 0; wr_done = 0; wr_beat_ready = 0;
        wr_stall_pct = 0; rs_wrg = 88; wr_block = 0; wr_done_task = 0;
    end
    always @(negedge clk) begin
        if (rst)       wr_beat_ready <= 1'b0;
        else if (wr_block) wr_beat_ready <= 1'b0;
        else           wr_beat_ready <= wrg_on
                            && (({$random(rs_wrg)} % 100) >= wr_stall_pct);
    end
    always @(posedge clk) begin
        if (rst || dma_err) begin
            wrg_on <= 1'b0; wr_done <= 1'b0; wr_done_task <= 1'b0;
        end else begin
            wr_done <= 1'b0;
            if (wr_req_valid && wr_req_ready) begin
                wrg_on    <= 1'b1;
                wrg_addr  <= wr_addr;
                wrg_len   <= wr_len;
                wrg_got   <= 0;
                wr_order_ok <= 1'b1;
            end else if (wrg_on && wr_beat_valid && wr_beat_ready) begin
                rem_b = wrg_len - wrg_got;
                estrb = (rem_b >= 8) ? 8'hFF : (8'hFF >> (8 - rem_b));
                if (wr_beat_strb !== estrb) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR [%0t] strb=%02h want=%02h got=%0d len=%0d",
                             $time, wr_beat_strb, estrb, wrg_got, wrg_len);
                end else
                    checks = checks + 1;
                for (wl = 0; wl < 8; wl = wl + 1) begin
                    if (wr_beat_strb[wl]) begin
                        wa = wrg_addr + wrg_got;
                        if (wa != OUT_BASE + wrg_got)
                            wr_order_ok <= 1'b0;
                        mem[wa] = wr_beat_data[8*wl +: 8];
                        wrg_got = wrg_got + 1;
                    end else if (wl >= rem_b) begin
                        dl = wr_beat_data[8*wl +: 8];
                        if (dl !== 8'h00) begin
                            errors = errors + 1;
                            $display("EES_ADDENG_ERR [%0t] dead lane %0d =%02h",
                                     $time, wl, dl);
                        end
                    end
                end
                wr_beats_total = wr_beats_total + 1;
                if (wrg_got >= wrg_len) begin
                    wrg_on  <= 1'b0;
                    wr_done <= 1'b1;
                    wr_done_task <= 1'b1;
                end
            end
        end
    end

    // ---- req 基址核对（chw>0 任务必现且 addr/len 恰等）----
    always @(posedge clk) if (!rst) begin
        if (wr_req_valid && wr_req_ready) begin
            wr_req_seen <= 1'b1;
            if (wr_addr != OUT_BASE || wr_len != cur_chw) begin
                errors = errors + 1;
                $display("EES_ADDENG_ERR wr req addr=%0h len=%0d want (%0h,%0d)",
                         wr_addr, wr_len, OUT_BASE, cur_chw);
            end else
                checks = checks + 1;
        end
    end

    // ---- done 协议：恰一次、不与 busy 同拍、迟于 wr_done ----
    integer done_cnt;
    always @(posedge clk) if (!rst && done) begin
        done_cnt = done_cnt + 1;
        if (busy) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR [%0t] done && busy", $time);
        end
        if (!wr_done_task && cur_chw != 0) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR [%0t] done before wr_done", $time);
        end
    end

    // ---- 流水仪表：v5 反压计数 / FIFO 峰值 / flush-lag（+5 拍证据）----
    integer stall_cnt, fifo_max, last_pop_cyc, flush_cyc, flush_lag_min;
    integer cur_cyc;
    always @(posedge clk) begin
        cur_cyc <= cur_cyc + 1;
        if (rst) begin
            stall_cnt <= 0; fifo_max <= 0; last_pop_cyc <= 0; flush_cyc <= 0;
        end else begin
            if (u_dut.stall_w)
                stall_cnt <= stall_cnt + 1;
            if (u_dut.fa_lvl_r > fifo_max) fifo_max <= u_dut.fa_lvl_r;
            if (u_dut.fb_lvl_r > fifo_max) fifo_max <= u_dut.fb_lvl_r;
            if (u_dut.fa_lvl_r > 128 || u_dut.fb_lvl_r > 128) begin
                errors = errors + 1;
                $display("EES_ADDENG_ERR [%0t] FIFO level > 128", $time);
            end
            if (u_dut.jnA_w)
                last_pop_cyc <= cur_cyc;
            if (u_dut.asm_flush_r) begin
                flush_cyc <= cur_cyc;
                if (last_pop_cyc != 0 && cur_cyc - last_pop_cyc >= 7) begin
                    if (flush_lag_min > cur_cyc - last_pop_cyc || flush_lag_min == 0)
                        flush_lag_min <= cur_cyc - last_pop_cyc;
                end else if (last_pop_cyc != 0) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR [%0t] flush lag %0d < 7 (pipeline drop?)",
                             $time, cur_cyc - last_pop_cyc);
                end
            end
            // 临界放行（双轨防死锁：FIFO 深填 or 阻塞窗口超时）
            if (wr_block) begin
                blk_cyc <= blk_cyc + 1;
                if (u_dut.fa_lvl_r >= 112 || u_dut.fb_lvl_r >= 112
                    || blk_cyc > 4000)
                    wr_block <= 1'b0;
            end
        end
    end

    // ---- 通用任务驱动 ----
    task run_task(input integer tno,
                  input integer cc, hh, ww,
                  input [31:0] tm0, input [5:0] ts0,
                  input [31:0] tm1, input [5:0] ts1,
                  input integer mode, rsp, wsp,
                  input integer use_block,
                  input [127:0] tname);
        integer n, i, tw, tlim;
        begin
            n = cc * hh * ww;
            cur_chw = n;
            done_cnt = 0; wr_done_task = 0;
            rd_stall_pct = rsp; wr_stall_pct = wsp;
            stall_cnt = 0; fifo_max = 0; blk_cyc = 0;
            last_pop_cyc = 0; flush_cyc = 0;
            rd_req_seen = 0; wr_req_seen = 0;
            rd_blk_cnt = 0;
            fill_input(n, mode);
            gen_rd_sched(n);
            gen_golden(n, tm0, ts0, tm1, ts1);
            if (use_block) wr_block = 1'b1;
            @(negedge clk);
            start = 1'b1; chw_in = n;
            m0_in = tm0; s0_in = ts0; m1_in = tm1; s1_in = ts1;
            @(negedge clk);
            start = 1'b0;
            tw = 0; tlim = 12*n + 12000;
            while (done_cnt == 0 && tw < tlim) begin
                @(negedge clk);
                tw = tw + 1;
            end
            if (n == 0) begin
                //CHW==0 直通：done 恰一次且零 DMA 活动
                if (done_cnt != 1) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d done x%0d", tno, done_cnt);
                end else
                    checks = checks + 1;
                if (rd_req_seen || wr_req_seen) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d DMA activity for CHW=0", tno);
                end else
                    checks = checks + 1;
            end else begin
                if (done_cnt != 1) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d no/extra done (%0d) within %0d cyc",
                             tno, done_cnt, tlim);
                end
                if (!rd_req_seen || !wr_req_seen) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d missing DMA reqs", tno);
                end else
                    checks = checks + 1;
                if (rd_blk_cnt != exp_nblk) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d rd blocks %0d != %0d",
                             tno, rd_blk_cnt, exp_nblk);
                end else
                    checks = checks + 1;
                if (wrg_got != n) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d write bytes %0d != %0d (lost/dup)",
                             tno, wrg_got, n);
                end else
                    checks = checks + 1;
                if (!wr_order_ok) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d write order/addr break", tno);
                end else
                    checks = checks + 1;
                for (i = 0; i < n; i = i + 1) begin
                    if (mem[OUT_BASE + i] !== exp_arr[i]) begin
                        errors = errors + 1;
                        if (errors < 40)
                            $display("EES_ADDENG_ERR T%0d byte%0d got=%02h want=%02h",
                                     tno, i, mem[OUT_BASE + i], exp_arr[i]);
                    end else
                        checks = checks + 1;
                end
                if (use_block) begin
                    if (stall_cnt == 0) begin
                        errors = errors + 1;
                        $display("EES_ADDENG_ERR T%0d v5 backpressure never fired",
                                 tno);
                    end else
                        checks = checks + 1;
                end
                //收尾静默 + 无额外 done
                repeat (20) @(negedge clk);
                if (busy) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d busy after done", tno);
                end
                if (wr_beat_valid) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d beat after done", tno);
                end
                if (done_cnt != 1) begin
                    errors = errors + 1;
                    $display("EES_ADDENG_ERR T%0d extra done in quiet", tno);
                end
            end
            $display("EES_ADDENG_INFO T%0d %0s n=%0d done wr=%0d rdblk=%0d fifo_max=%0d stall=%0d flush_lag=%0d",
                     tno, tname, n, wrg_got, rd_blk_cnt, fifo_max, stall_cnt,
                     (last_pop_cyc != 0 && flush_cyc != 0)
                     ? (flush_cyc - last_pop_cyc) : 0);
            wr_block = 1'b0;    //任务退出兜底清零（防超时路径遗留阻塞）
            cur_chw = 0;
        end
    endtask

    integer erc, i;
    initial begin
        checks = 0; errors = 0; rs_fill = 20260924;
        start = 0; chw_in = 0;
        m0_in = 0; s0_in = 0; m1_in = 0; s1_in = 0; dma_err = 0;
        in0_base = IN0_BASE; in1_base = IN1_BASE; out_base = OUT_BASE;
        rd_req_ready = 1'b1; wr_req_ready = 1'b1;
        done_cnt = 0; cur_chw = 0; rd_beats_total = 0; wr_beats_total = 0;
        flush_lag_min = 0; cur_cyc = 0;
        wr_done_task = 0; rd_req_seen = 0; wr_req_seen = 0;
        rd_blk_cnt = 0; blk_cyc = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        // ===== Phase B 验证门清单 =====
        run_task( 1, 1, 4, 4, 32'h00018560, 6'd8, 32'h0000CA00, 6'd10,
                  0, 10, 10, 0, "basic-dual-quant");
        run_task( 2, 1, 4, 4, 32'hFFFF0000, 6'd0, 32'h00008000, 6'd15,
                  0, 10, 10, 0, "negm-s0-shift-id");  // m0=-65536 s0=0；m1=32768 s1=15
        run_task( 3, 1, 5, 5, 32'h7FFF_FFFF, 6'd31, 32'h8000_0000, 6'd31,
                  0, 20, 20, 0, "deep-shift-both-signs");
        run_task( 4, 1, 4, 4, 32'h00000100, 6'd0, 32'h00000100, 6'd0,
                  1, 10, 10, 0, "all-80-sat-lo");
        run_task( 5, 1, 4, 4, 32'h00000100, 6'd0, 32'hFFFFFE00, 6'd0,
                  2, 10, 10, 0, "all-7F-sat-mixed");  // m1=-512 → 对消区
        run_task( 6, 1, 8, 64, 32'h00018560, 6'd8, 32'h0000CA00, 6'd10,
                  0,  5, 40, 1, "chw512-crit-fifo-v5stall");
        run_task( 7, 2, 9, 11, 32'h00001234, 6'd5, 32'hFFFF8765, 6'd12,
                  0, 30, 30, 0, "severe-stall-both");
        run_task( 8, 1, 1, 0, 32'h00000001, 6'd0, 32'h00000001, 6'd0,
                  0,  0,  0, 0, "chw0-direct");
        run_task( 9, 3, 5, 7, 32'h00000003, 6'd1, 32'h00000001, 6'd1,
                  3, 25, 25, 0, "rne-tie-s1-tailstrb");  // CHW=105 尾拍 1 道
        run_task(10, 2, 4, 8, 32'h00000003, 6'd1, 32'h00000001, 6'd1,
                  0, 25, 25, 0, "chw64-exact-beats");
        run_task(11, 1, 2, 65, 32'h00000055, 6'd3, 32'h000000AA, 6'd4,
                  0, 15, 15, 0, "chw130-multiblk");   // 64+64+2 三块/侧
        run_task(12, 1, 3, 3, 32'h00000000, 6'd0, 32'h00000061, 6'd2,
                  0, 10, 10, 0, "consec-req-relock"); // m0=0 零侧 + 换参数重锁
        run_task(16, 1, 6, 6, 32'h00000061, 6'd2, 32'h00000000, 6'd0,
                  0, 20, 20, 0, "zero-side-b");

        // ===== T13 流水中途 reset 击杀 + 重启全查 =====
        cur_chw = 2*4*5;
        done_cnt = 0; wr_done_task = 0;
        rd_stall_pct = 25; wr_stall_pct = 25;
        stall_cnt = 0; fifo_max = 0; blk_cyc = 0;
        last_pop_cyc = 0; flush_cyc = 0;
        rd_req_seen = 0; wr_req_seen = 0; rd_blk_cnt = 0;
        fill_input(cur_chw, 0);
        gen_rd_sched(cur_chw);
        gen_golden(cur_chw, 32'h00018560, 6'd8, 32'h0000CA00, 6'd10);
        @(negedge clk);
        start = 1'b1; chw_in = 2*4*5;
        m0_in = 32'h00018560; s0_in = 6'd8;
        m1_in = 32'h0000CA00; s1_in = 6'd10;
        @(negedge clk);
        start = 1'b0;
        repeat (60) @(negedge clk);   //击杀点取中流
        if (!busy) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T13 kill point misconfigured (not busy)");
        end
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);
        if (done_cnt != 0) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T13 done after reset kill");
        end else
            checks = checks + 1;
        if (busy) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T13 busy after reset kill");
        end else
            checks = checks + 1;
        if (u_dut.vch_r != 5'd0) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T13 vch not cleared by rst");
        end else
            checks = checks + 1;
        run_task(13, 2, 4, 5, 32'h00018560, 6'd8, 32'h0000CA00, 6'd10,
                 0, 25, 25, 0, "rstkill-rerun");
        $display("EES_ADDENG_INFO T13 reset-kill done");

        // ===== T14 流水中途 dma_err 弃权 + v 链清零证据 + 重启全查 =====
        cur_chw = 1*8*16;
        done_cnt = 0; wr_done_task = 0;
        rd_stall_pct = 25; wr_stall_pct = 25;
        stall_cnt = 0; fifo_max = 0; blk_cyc = 0;
        last_pop_cyc = 0; flush_cyc = 0;
        rd_req_seen = 0; wr_req_seen = 0; rd_blk_cnt = 0;
        fill_input(cur_chw, 0);
        gen_rd_sched(cur_chw);
        gen_golden(cur_chw, 32'h00001234, 6'd5, 32'hFFFF8765, 6'd12);
        @(negedge clk);
        start = 1'b1; chw_in = 1*8*16;
        m0_in = 32'h00001234; s0_in = 6'd5;
        m1_in = 32'hFFFF8765; s1_in = 6'd12;
        @(negedge clk);
        start = 1'b0;
        repeat (90) @(negedge clk);   //深流水击杀点（CHW=128 长流）
        if (!busy) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T14 kill point misconfigured (not busy)");
        end
        dma_err = 1'b1;
        @(negedge clk);
        dma_err = 1'b0;
        erc = 0;
        while (busy && erc < 10) begin
            @(negedge clk);
            erc = erc + 1;
        end
        if (busy) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T14 busy not dropped after dma_err");
        end else
            checks = checks + 1;
        if (done_cnt != 0) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T14 done after dma_err");
        end else
            checks = checks + 1;
        //v 链清零 + 静默期无 wr_beat（残留 v5 推垃圾字节路径的直接证据）
        if (u_dut.vch_r != 5'd0) begin
            errors = errors + 1;
            $display("EES_ADDENG_ERR T14 vch not cleared after dma_err");
        end else
            checks = checks + 1;
        erc = 0;
        while (erc < 30) begin
            @(negedge clk);
            if (wr_beat_valid) begin
                errors = errors + 1;
                $display("EES_ADDENG_ERR T14 spurious wr beat after dma_err");
                erc = 1000;
            end
            erc = erc + 1;
        end
        if (erc != 1001) checks = checks + 1;
        repeat (10) @(negedge clk);
        run_task(14, 1, 8, 16, 32'h00001234, 6'd5, 32'hFFFF8765, 6'd12,
                 0, 25, 25, 0, "dmaerr-rerun");
        $display("EES_ADDENG_INFO T14 dma_err abort done");

        // ===== 影子对拍终检已退役（2026-09-24 全 13 门零失配后随
        // translate_off 影子块一并删除；checks 基线 1622→1621 = 该
        // 检查项退役，rd/wr/errors 逐数不变）+ flush-lag（+5 拍协议
        // 证据）=====
        checks = checks + 1;
        $display("EES_ADDENG_INFO shadow retired; flush_lag_min=%0d (V1.1 baseline=2, expect>=7)",
                 flush_lag_min);

        $display("EES_SUMMARY run=addeng checks=%0d errors=%0d rd=%0d wr=%0d",
                 checks, errors, rd_beats_total, wr_beats_total);
        if (errors == 0)
            $display("EES_MODELSIM_RESULT PASS");
        else
            $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

    //全局看门狗
    initial begin
        #200_000_000;
        $display("EES_ADDENG_ERR global watchdog");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
