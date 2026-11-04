/************************************************************************
 * File Name     : tb_ppu_mp5_engine.sv
 * Developer     : LSL
 * Date          : 2026-09-24
 * Project Name  : AMD embodied sorting / EES-331 XC7Z020
 * Module Name   : tb_ppu_mp5_engine
 * Description   : Stage3-v2 PPU-F5 MaxPool5 引擎级新门（v2 规格 §三
 *                 FIFO/背压/流水合同重证明）。
 *
 *   DUT: ppu_mp5_engine + ppu_byte_reader + ppu_byte_store_assembler +
 *   换芯 shim（eng_wrap_c.v：yolo_ppu_maxpool5 -> _c V2.2，P=3）。
 *   TB 建 DMA 双通道模型 + 内存阵列：
 *   - 读通道：req 握手 -> 随机停顿 8B 拍流（小端 lane0=低地址）->
 *     rd_done 脉冲；engine 不等 rd_done（reader 自管计数）；
 *   - 写通道：req 握手 -> 随机 ready 停顿收拍 -> strb 逐道展开写
 *     内存（小端）；strb 纪律（满拍 FF / 尾拍 (1<<rem)-1 / 死道为 0）、
 *     地址严格递增、字节数恰等 wr_len——丢/重/乱/早完/溢出全查；
 *   - golden：TB 直索引有效位掩码 max（结构=地址算术，与 DUT 流式
 *     行缓冲不同构；核级 13 例 golden 已把该模型形与 python pad 模型
 *     钉死等价，mp5u_a/b/c 三跑 26762/0）。
 *
 *   覆盖（v2 规格 §三清单逐项）：
 *   W=1 / W<5 / W=64 临界容量（wr_block 强制填满->测量 f_lvl 峰值，
 *   公式预测 L_max=(FD-thr)+P+B=253） / H=1 / H<5 / 多通道 / 全 -128 /
 *   全 127 / 双向随机停顿 / 连续任务（前一 done 后 1 拍即启） / 尾拍
 *   部分 strb（CHW%8!=0）与整拍收尾（CHW%8==0） / 流水中 reset 击杀
 *   重启全查 / 流水中 dma_err 弃权（无 done、busy 即落、核自排空）
 *   / CHW==0 直通 done（无任何 DMA 活动）/ W=65 闸永关看门狗可见
 *   （busy 悬持+闸全关+FIFO 空+复位可恢复）/ FIFO 同拍读写计数 /
 *   闸关周期计数 / 完成先后（done 必迟于 wr_done）。
 * Revision History:
 *   - V1.0 (2026-09-24) by LSL : f7tmg_run01 新建（mp5eng 门）。
 *   - V1.1 (2026-09-24) by LSL : 随引擎 V1.1 chw_i 元数据改接线
 *       （chw_in=cc·hh·ww 任务内现算；检查项/期望零变化）。
 ************************************************************************/

`timescale 1ns/1ps

module tb_ppu_mp5_engine;

    // ---- DUT 连线 ----
    reg         clk, rst, start;
    reg  [31:0] in0_base, out_base;
    reg  [15:0] c_in, h_in, w_in;
    reg  [31:0] chw_in;                   // V1.1：chw_i 元数据直驱（=cc·hh·ww）
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

    ppu_mp5_engine u_dut (
        .clk_i(clk), .rst_i(rst), .start_i(start),
        .in0_base_i(in0_base), .out_base_i(out_base),
        .c_i(c_in), .h_i(h_in), .w_i(w_in),
        .chw_i(chw_in),
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
    localparam [31:0] IN_BASE  = 32'h0000_1000;
    localparam [31:0] OUT_BASE = 32'h0000_2000;
    reg [7:0] mem [0:MEMSZ-1];
    localparam integer MAXE = 8192;
    reg [7:0] exp_arr [0:MAXE-1];
    integer cur_chw;
    reg rd_req_seen, wr_req_seen;

    // ---- 输入填充（0=随机 1=全80 2=全7F 3=确定性混合）+ 输出毒化 ----
    task fill_input(input integer cc, input integer hh, input integer ww,
                    input integer mode);
        integer i, n;
        begin
            n = cc * hh * ww;
            for (i = 0; i < n; i = i + 1) begin
                if (mode == 0)      mem[IN_BASE + i] = $random(rs_fill);
                else if (mode == 1) mem[IN_BASE + i] = 8'h80;
                else if (mode == 2) mem[IN_BASE + i] = 8'h7F;
                else                mem[IN_BASE + i] = (i * 37 + 11) & 8'hFF;
            end
            for (i = 0; i < 2048; i = i + 1)
                mem[OUT_BASE + i] = 8'hEE;
        end
    endtask

    // ---- golden：按输出位置直接索引的掩码 max（异构于 DUT 流式结构）----
    task gen_golden(input integer cc, input integer hh, input integer ww);
        integer c, y, x, yy, xx, y0, y1, x0, x1;
        reg [7:0] m;
        begin
            for (c = 0; c < cc; c = c + 1)
                for (y = 0; y < hh; y = y + 1)
                    for (x = 0; x < ww; x = x + 1) begin
                        y0 = (y - 2 > 0) ? y - 2 : 0;
                        y1 = (y + 2 < hh - 1) ? y + 2 : hh - 1;
                        x0 = (x - 2 > 0) ? x - 2 : 0;
                        x1 = (x + 2 < ww - 1) ? x + 2 : ww - 1;
                        m = 8'h80;
                        for (yy = y0; yy <= y1; yy = yy + 1)
                            for (xx = x0; xx <= x1; xx = xx + 1)
                                if ($signed(mem[IN_BASE + c*hh*ww + yy*ww + xx])
                                    > $signed(m))
                                    m = mem[IN_BASE + c*hh*ww + yy*ww + xx];
                        exp_arr[c*hh*ww + y*ww + x] = m;
                    end
        end
    endtask

    // ---- DMA 读通道 BFM：req -> 随机停顿拍流 -> rd_done ----
    reg        rdg_on;
    reg [31:0] rdg_addr;
    integer    rdg_len, rdg_sent;
    reg        rdv_hold;
    integer    rd_stall_pct;
    integer    rs_rdg;
    integer    l;
    reg [31:0] ba;
    initial begin
        rdg_on = 0; rdv_hold = 0; rd_beat_valid = 0;
        rd_beat_data = 0; rd_done = 0; rd_stall_pct = 0; rs_rdg = 77;
    end
    always @(posedge clk) begin
        if (rst) begin
            rdg_on <= 1'b0; rdv_hold <= 1'b0;
            rd_beat_valid <= 1'b0; rd_done <= 1'b0;
        end else begin
            rd_done <= 1'b0;
            if (rd_req_valid && rd_req_ready) begin
                rdg_on   <= 1'b1;
                rdg_addr <= rd_addr;
                rdg_len  <= rd_len;
                rdg_sent <= 0;
                rdv_hold <= 1'b0;
            end else if (rdg_on && !rdv_hold) begin
                if (({$random(rs_rdg)} % 100) >= rd_stall_pct) begin
                    ba = rdg_addr + rdg_sent;
                    for (l = 0; l < 8; l = l + 1)
                        rd_beat_data[8*l +: 8] <= mem[ba + l];
                    rd_beat_valid <= 1'b1;
                    rdv_hold      <= 1'b1;
                end
            end else if (rdg_on && rdv_hold && rd_beat_ready) begin
                rd_beat_valid <= 1'b0;
                rdv_hold      <= 1'b0;
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
    reg        wr_done_task;      // 本任务 wr_done 已发（早完判据）
    reg        wr_block;          // 临界容量：强制 ready=0 至 FIFO 停涨
    integer    wl, rem_b;
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
        if (rst) begin
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
                    $display("EES_MP5ENG_ERR [%0t] strb=%02h want=%02h got=%0d len=%0d",
                             $time, wr_beat_strb, estrb, wrg_got, wrg_len);
                end else
                    checks = checks + 1;
                for (wl = 0; wl < 8; wl = wl + 1) begin
                    if (wr_beat_strb[wl]) begin
                        wa = wrg_addr + wrg_got;
                        if (wa != OUT_BASE + wrg_got)
                            wr_order_ok <= 1'b0;
                        mem[wa] = wr_beat_data[8*wl +: 8];
                        wrg_got = wrg_got + 1;      //单 always 写者，阻塞累计
                    end else if (wl >= rem_b) begin
                        dl = wr_beat_data[8*wl +: 8];
                        if (dl !== 8'h00) begin
                            errors = errors + 1;
                            $display("EES_MP5ENG_ERR [%0t] dead lane %0d =%02h",
                                     $time, wl, dl);
                        end
                    end
                end
                if (wrg_got >= wrg_len) begin
                    wrg_on  <= 1'b0;
                    wr_done <= 1'b1;
                    wr_done_task <= 1'b1;
                end
            end
        end
    end

    // ---- req 地址/长度核对 + 双请求必现（chw>0 任务）----
    always @(posedge clk) if (!rst) begin
        if (rd_req_valid && rd_req_ready) begin
            rd_req_seen <= 1'b1;
            if (rd_addr != IN_BASE || rd_len != cur_chw) begin
                errors = errors + 1;
                $display("EES_MP5ENG_ERR rd req addr=%0h len=%0d want (%0h,%0d)",
                         rd_addr, rd_len, IN_BASE, cur_chw);
            end else
                checks = checks + 1;
        end
        if (wr_req_valid && wr_req_ready) begin
            wr_req_seen <= 1'b1;
            if (wr_addr != OUT_BASE || wr_len != cur_chw) begin
                errors = errors + 1;
                $display("EES_MP5ENG_ERR wr req addr=%0h len=%0d want (%0h,%0d)",
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
            $display("EES_MP5ENG_ERR [%0t] done && busy", $time);
        end
        if (!wr_done_task && cur_chw != 0) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR [%0t] done before wr_done", $time);
        end
    end

    // ---- FIFO/闸监控（S_RUN=4'd3）+ 临界容量放行 ----
    integer fifo_max, gate_off_cyc, same_rw, srun_cyc, fifo_stall;
    integer same_rw_total;
    initial begin
        fifo_max = 0; gate_off_cyc = 0; same_rw = 0; srun_cyc = 0;
        fifo_stall = 0; same_rw_total = 0;
    end
    always @(posedge clk) begin
        if (!rst && u_dut.state_r == 4'd3) begin
            srun_cyc = srun_cyc + 1;
            if (u_dut.f_lvl_r > fifo_max) begin
                fifo_max = u_dut.f_lvl_r;
                fifo_stall = 0;
            end else
                fifo_stall = fifo_stall + 1;
            if (u_dut.f_lvl_r > 256) begin
                errors = errors + 1;
                $display("EES_MP5ENG_ERR [%0t] FIFO level %0d > 256",
                         $time, u_dut.f_lvl_r);
            end
            if (u_dut.push_w && u_dut.emit_fire_w)
                same_rw = same_rw + 1;
            if (!u_dut.gate_w)
                gate_off_cyc = gate_off_cyc + 1;
            if (wr_block && ((fifo_max >= 150 && fifo_stall >= 60)
                             || fifo_stall >= 500))
                wr_block = 1'b0;  //放行判据双轨：填满(≥150)停滞 60 拍，
                                  //或任意停滞 500 拍（防中通道关闸死锁——
                                  //c=1 时闸必在通道中段关，fifo_max 只到
                                  //FD-thr+ε≈125，永不触 150；T8 二跑教训）
        end
    end

    // ---- 通用任务驱动 ----
    task run_task(input integer tno,
                  input integer cc, hh, ww,
                  input integer mode, rsp, wsp,
                  input integer expect_no_done,
                  input integer use_block,
                  input [127:0] tname);
        integer n, i, tw, tlim;
        begin
            n = cc * hh * ww;
            cur_chw = n;
            done_cnt = 0; wr_done_task = 0;
            rd_stall_pct = rsp; wr_stall_pct = wsp;
            fifo_max = 0; gate_off_cyc = 0; same_rw = 0;
            srun_cyc = 0; fifo_stall = 0; wr_block = 0;
            rd_req_seen = 0; wr_req_seen = 0;
            fill_input(cc, hh, ww, mode);
            gen_golden(cc, hh, ww);
            if (use_block) wr_block = 1'b1;
            @(negedge clk);
            start = 1'b1; c_in = cc; h_in = hh; w_in = ww; chw_in = n;
            @(negedge clk);
            start = 1'b0;
            tw = 0; tlim = 6*n + 32*(hh + ww) + 6000;
            while (done_cnt == 0 && tw < tlim) begin
                @(negedge clk);
                tw = tw + 1;
            end
            if (expect_no_done) begin
                //W=65 域界：闸永关看门狗可见（busy 悬持/闸全关/FIFO 空）
                if (done_cnt != 0) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d unexpected done", tno);
                end else
                    checks = checks + 1;
                if (!busy) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d busy dropped w/o done", tno);
                end
                if (gate_off_cyc != srun_cyc) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d gate opened for W>64", tno);
                end else
                    checks = checks + 1;
                if (fifo_max != 0) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d FIFO moving with gate shut",
                             tno);
                end
                @(negedge clk); rst = 1'b1;
                repeat (2) @(negedge clk);
                rst = 1'b0;
                repeat (5) @(negedge clk);
                if (busy) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d busy after recovery", tno);
                end else
                    checks = checks + 1;
                $display("EES_MP5ENG_INFO T%0d %0s WATCHDOG-VISIBLE ok srun=%0d",
                         tno, tname, srun_cyc);
            end else begin
                if (done_cnt == 0) begin
                    errors = errors + 1;
                    $display("EES_MP5ENG_ERR T%0d no done within %0d cyc",
                             tno, tlim);
                end else if (n == 0) begin
                    //CHW==0 直通：done 恰一次且零 DMA 活动
                    if (done_cnt != 1) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d done x%0d", tno, done_cnt);
                    end else
                        checks = checks + 1;
                    if (rd_req_seen || wr_req_seen) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d DMA activity for CHW=0",
                                 tno);
                    end else
                        checks = checks + 1;
                end else begin
                    if (done_cnt != 1) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d done x%0d", tno, done_cnt);
                    end
                    if (!rd_req_seen || !wr_req_seen) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d missing DMA reqs", tno);
                    end else
                        checks = checks + 1;
                    if (wrg_got != n) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d write bytes %0d != %0d (lost/dup)",
                                 tno, wrg_got, n);
                    end else
                        checks = checks + 1;
                    if (!wr_order_ok) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d write order/addr break",
                                 tno);
                    end else
                        checks = checks + 1;
                    for (i = 0; i < n; i = i + 1) begin
                        if (mem[OUT_BASE + i] !== exp_arr[i]) begin
                            errors = errors + 1;
                            if (errors < 40)
                                $display("EES_MP5ENG_ERR T%0d byte%0d got=%02h want=%02h",
                                         tno, i, mem[OUT_BASE + i], exp_arr[i]);
                        end else
                            checks = checks + 1;
                    end
                    if (use_block) begin
                        if (gate_off_cyc == 0) begin
                            errors = errors + 1;
                            $display("EES_MP5ENG_ERR T%0d block never closed gate",
                                     tno);
                        end else
                            checks = checks + 1;
                        //W=64 关闸阈 f_lvl>FD-thr=120：必须真实抵达关闸区
                        if (fifo_max < 121) begin
                            errors = errors + 1;
                            $display("EES_MP5ENG_ERR T%0d closure depth not reached (fifo_max=%0d)",
                                     tno, fifo_max);
                        end else
                            checks = checks + 1;
                    end
                    //收尾静默 + 无额外 done
                    repeat (20) @(negedge clk);
                    if (busy) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d busy after done", tno);
                    end
                    if (wr_beat_valid) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d beat after done", tno);
                    end
                    if (done_cnt != 1) begin
                        errors = errors + 1;
                        $display("EES_MP5ENG_ERR T%0d extra done in quiet", tno);
                    end
                end
                same_rw_total = same_rw_total + same_rw;
                $display("EES_MP5ENG_INFO T%0d %0s done wr=%0d fifo_max=%0d gate_off=%0d same_rw=%0d",
                         tno, tname, n, fifo_max, gate_off_cyc, same_rw);
            end
            wr_block = 1'b0;    //任务退出兜底清零（防超时路径遗留阻塞）
            cur_chw = 0;
        end
    endtask

    integer erc;
    initial begin
        checks = 0; errors = 0; rs_fill = 20260924;
        start = 0; c_in = 0; h_in = 0; w_in = 0; chw_in = 0; dma_err = 0;
        in0_base = IN_BASE; out_base = OUT_BASE;
        rd_req_ready = 1'b1; wr_req_ready = 1'b1;
        done_cnt = 0; cur_chw = 0;
        wr_done_task = 0; rd_req_seen = 0; wr_req_seen = 0;
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;

        // ===== 规格 §三 清单 =====
        run_task( 1, 1, 1, 1, 0, 10, 10, 0, 0, "w1h1");
        run_task( 2, 1, 3, 3, 0, 25, 25, 0, 0, "w3h3-both-lt5");
        run_task( 3, 1, 1, 7, 0, 25, 25, 0, 0, "h1w7");
        run_task( 4, 1, 7, 1, 0, 25, 25, 0, 0, "w1h7");
        run_task( 5, 3, 5, 6, 0, 20, 20, 0, 0, "3ch-partial-tail");
        run_task( 6, 1, 4, 4, 1, 10, 10, 0, 0, "all-128");
        run_task( 7, 1, 4, 4, 2, 10, 10, 0, 0, "all-127");
        run_task( 8, 1, 8, 64, 0,  5, 40, 0, 1, "w64-crit-fifo");
        run_task(17, 2, 8, 64, 0, 10, 90, 0, 0, "w64-severe-drain");
        run_task( 9, 1, 6, 6, 0, 25, 25, 0, 0, "stall-rand");
        run_task(10, 1, 6, 6, 3, 25, 25, 0, 0, "consecutive");
        run_task(11, 1, 1, 0, 0,  0,  0, 0, 0, "chw0-direct");
        run_task(15, 1, 1, 64, 0, 15, 30, 0, 0, "h1w64-burstW");
        run_task(16, 4, 9,11, 0, 25, 25, 0, 0, "4ch-stall");

        // ===== T12 流水中途 reset 击杀 + 重启全查 =====
        cur_chw = 2*4*5;
        done_cnt = 0; wr_done_task = 0;
        rd_stall_pct = 25; wr_stall_pct = 25;
        fifo_max = 0; gate_off_cyc = 0; same_rw = 0;
        srun_cyc = 0; fifo_stall = 0; wr_block = 0;
        rd_req_seen = 0; wr_req_seen = 0;
        fill_input(2, 4, 5, 0);
        gen_golden(2, 4, 5);
        @(negedge clk);
        start = 1'b1; c_in = 2; h_in = 4; w_in = 5; chw_in = 2*4*5;
        @(negedge clk);
        start = 1'b0;
        repeat (60) @(negedge clk);   //击杀点取中流：(2,4,5) 全程 >90 拍
        if (!busy) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR T12 kill point misconfigured (not busy)");
        end
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);
        if (done_cnt != 0) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR T12 done after reset kill");
        end else
            checks = checks + 1;
        if (busy) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR T12 busy after reset kill");
        end else
            checks = checks + 1;
        run_task(12, 2, 4, 5, 0, 25, 25, 0, 0, "rstkill-rerun");
        $display("EES_MP5ENG_INFO T12 reset-kill done");

        // ===== T13 流水中途 dma_err 弃权 + 重启全查 =====
        cur_chw = 1*6*6;
        done_cnt = 0; wr_done_task = 0;
        rd_stall_pct = 25; wr_stall_pct = 25;
        fifo_max = 0; gate_off_cyc = 0; same_rw = 0;
        srun_cyc = 0; fifo_stall = 0; wr_block = 0;
        rd_req_seen = 0; wr_req_seen = 0;
        fill_input(1, 6, 6, 0);
        gen_golden(1, 6, 6);
        @(negedge clk);
        start = 1'b1; c_in = 1; h_in = 6; w_in = 6; chw_in = 1*6*6;
        @(negedge clk);
        start = 1'b0;
        repeat (70) @(negedge clk);
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
            $display("EES_MP5ENG_ERR T13 busy not dropped after dma_err");
        end else
            checks = checks + 1;
        if (done_cnt != 0) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR T13 done after dma_err");
        end else
            checks = checks + 1;
        erc = 0;                       //核自行排空（push 被状态闸断）
        while (u_dut.u_core.busy_o && erc < 800) begin
            @(negedge clk);
            erc = erc + 1;
        end
        if (u_dut.u_core.busy_o) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR T13 core never drained");
        end else
            checks = checks + 1;
        repeat (30) @(negedge clk);
        run_task(13, 1, 6, 6, 0, 25, 25, 0, 0, "dmaerr-rerun");
        $display("EES_MP5ENG_INFO T13 dma_err abort done");

        // ===== T14 W=65 闸永关（看门狗可见）=====
        run_task(14, 1, 4, 65, 0, 10, 10, 1, 0, "w65-gate-shut");

        // ===== 同拍 FIFO 读写必须在某任务中真实发生 =====
        if (same_rw_total == 0) begin
            errors = errors + 1;
            $display("EES_MP5ENG_ERR no same-cycle FIFO r/w observed");
        end else
            checks = checks + 1;
        $display("EES_MP5ENG_INFO same-cycle FIFO r/w total=%0d", same_rw_total);

        $display("EES_SUMMARY checks=%0d errors=%0d", checks, errors);
        if (errors == 0)
            $display("EES_MODELSIM_RESULT PASS");
        else
            $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

    //全局看门狗
    initial begin
        #80_000_000;
        $display("EES_MP5ENG_ERR global watchdog");
        $display("EES_MODELSIM_RESULT FAIL");
        $finish;
    end

endmodule
