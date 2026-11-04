/************************************************************************
 * File Name     : tb_ppu_gemm_engine.sv
 * Developer     : LSL
 * Date          : 2026-09-27
 * Module Name   : tb_ppu_gemm_engine
 * Description   : P2.1 单元门 TB。TB 充当三侧：
 *                 ① desc BRAM 口 B（1 拍延迟模型）；
 *                 ② DMA 对端存储器模型（ppu_dma_master 用户口镜像：rd 从
 *                    mirror/param 阵列供数，wr 落 y 槽区）；
 *                 ③ walker 槽激励（req 单脉冲 / done-err 收割 / abort）。
 *   载荷：K576 正典（b3_k576_mirror.bin 565,248 拍 + 64 行参数 + LUT），
 *         金像 = y 槽区逐块前 8·vc(s) 字节按块序 gather ==
 *         b3_k576_golden_y.bin（外排 y_got_runN.hex 供 sha256 对板证链）。
 *   场景：S0 全卷 PASS 对拍 → S1 运行中 abort（静默）→ S2 整卷重跑
 *         （恢复闭环再对拍）→ S3 非法 K desc（err 0x02）→
 *         S4 LUT 相位 DMA 错注入（err 0x04）→ S5 槽跨距地址单元门
 *         （探测槽 0/1/2/63/64/127 五字段标记：实际取数地址+锁存内容）。
 * Revision History:
 *   - V1.0 (2026-09-27) by LSL : P2.1 初版。
 *   - V1.1 (2026-09-27) by LSL : 金像映射修正——b3_k576_golden_y.bin 为
 *                 (oc,Ho,Wo) 张量展平而非块 gather 序（oracle reshape
 *                 即证），prep 改为张量→块 gather 转换后下发；y_got
 *                 外排改整串 $sformatf（嵌套拼接 run 号塌陷）；拆除
 *                 LUTW/YY/dbg 瞬态侦察（保留 WR/LD 有界采样作正典
 *                 寄存器序证据）。
 *   - V1.2 (2026-09-28) by LSL : 配引擎 V1.3（P2.2）——wr 模型撤
 *                 dma_kill（真 DMA W 通道 abort 后不截断在途请求，
 *                 E_ABORTD 以冲刷拍/自然排空收口）；strb=00 冲刷拍
 *                 （零字节写入）合法不写镜像。S0-S4 判据不变。
 *   - V1.3 (2026-09-28) by LSL : 配引擎 V1.8（P2.5 Gate G 修复回归）：
 *                 ①check_y 回读期望从 128*b 槽位律改紧凑累计律（原 TB
 *                 把 RTL 定址律当期望=放置缺陷 sim 盲区根因，板 H4）；
 *                 ②新增写请求地址律监视器（addr/len 逐块对紧凑期望，
 *                 总量断言 25600）；③wr 模型 +WCFG 背压/延迟配置面
 *                 （0 恒ready / 1 随机 / 2 每4停1 / 3 每4停3 / 4 随机
 *                 +wr_done B 链延迟 0..31，xorshift32 确定性随机源
 *                 +SEED）——V1.4 保持守卫回归面。
 *   - V1.4 (2026-09-28) by LSL : 配引擎 V2.0（P2.3 槽跨距修复）：①
 *                 desc_mem 扩全表 128x32=4096 字；②PREP 指向 p23fix
 *                 run（desc 布局 V2=跨距 32，原 prep 复刻引擎缺陷 16
 *                 跨距律=同类放置盲区）；③新增 S5 地址单元门——探测槽
 *                 0/1/2/63/64/127 各五字段独立标记（K 标记 0xFFF 非法
 *                 →EC_GEOM 快错），断言 E_FADDR 实际五次读地址=
 *                 32*fw+{3,4,8,10,11} 与锁存 dw 内容；旧码非零槽必败
 *                 （槽 0 同址=对照）。checks 644→662（+18）。
 ************************************************************************/
`timescale 1ns/1ps

module tb_ppu_gemm_engine;

    // ---- 常量（prep 生成物 p21_meta.json 交叉核对） ----
    localparam [31:0] MIRROR_BASE = 32'h1000_0000;
    localparam [31:0] PARAM_BASE  = 32'h2000_0000;
    localparam integer MIRROR_BEATS = 565248;
    localparam integer Y_OFF   = 4423936;      // 0x438100 = 0x100+320*13824
    localparam integer Y_BYTES = 25600;        // V1.3：紧凑窗（320 块累计）
    localparam integer NB      = 320;
    localparam integer RC      = 8;
    localparam integer NSTRIP  = 2;
    localparam integer SLOT_CONV  = 5;
    localparam integer SLOT_BADK  = 6;
    localparam integer WATCH_CYC  = 30_000_000;
    localparam string  PREP =
        "E:/competition/4_metrics/logs/2026-09-28_yolo_p2_p23fix_run01/prep/";

    // ---- 时钟/复位 ----
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- 记账 ----
    integer cyc, checks, errors;
    always @(negedge clk) cyc = cyc + 1;

    // ---- DUT 面 ----
    reg         req_valid;
    reg  [6:0]  desc_idx;
    reg  [7:0]  opcode;
    wire        done_w, err_w, busy_w;
    wire [7:0]  err_code_w;
    reg         abort_p;
    wire [11:0] desc_rd_addr;
    reg  [31:0] desc_rd_data;

    wire        rd_req_valid;
    reg         rd_req_ready;
    wire [31:0] rd_addr;
    wire [23:0] rd_len;
    reg         rd_beat_valid;
    wire        rd_beat_ready;
    reg  [63:0] rd_beat_data;
    reg         rd_done;
    integer     rd_req_cnt;

    wire        wr_req_valid;
    reg         wr_req_ready;
    wire [31:0] wr_addr;
    wire [23:0] wr_len;
    wire        wr_beat_valid;
    reg         wr_beat_ready;
    wire [63:0] wr_beat_data;
    wire [7:0]  wr_beat_strb;
    reg         wr_done;
    integer     wr_done_cnt;

    reg         dma_err_pulse;
    reg  [7:0]  dma_err_code;

    ppu_gemm_engine dut (
        .clk_i(clk), .rst_i(rst),
        .req_valid_i(req_valid), .desc_idx_i(desc_idx), .opcode_i(opcode),
        .done_o(done_w), .err_o(err_w), .err_code_o(err_code_w),
        .busy_o(busy_w), .abort_i(abort_p),
        .desc_rd_addr_o(desc_rd_addr), .desc_rd_data_i(desc_rd_data),
        .rd_req_valid_o(rd_req_valid), .rd_req_ready_i(rd_req_ready),
        .rd_addr_o(rd_addr), .rd_len_o(rd_len),
        .rd_beat_valid_i(rd_beat_valid), .rd_beat_ready_o(rd_beat_ready),
        .rd_beat_data_i(rd_beat_data), .rd_done_i(rd_done),
        .wr_req_valid_o(wr_req_valid), .wr_req_ready_i(wr_req_ready),
        .wr_addr_o(wr_addr), .wr_len_o(wr_len),
        .wr_beat_valid_o(wr_beat_valid), .wr_beat_ready_i(wr_beat_ready),
        .wr_beat_data_o(wr_beat_data), .wr_beat_strb_o(wr_beat_strb),
        .wr_done_i(wr_done),
        .dma_err_pulse_i(dma_err_pulse), .dma_err_code_i(dma_err_code)
    );

    // ---- 载荷存储 ----
    reg [63:0] mirror [0:MIRROR_BEATS-1];
    reg [31:0] paramw [0:191];
    reg [31:0] desc_mem [0:4095];       // V1.4：全表 128x32（探测高槽位）
    reg [7:0]  golden  [0:25599];

    // ---- desc 口 B 模型（1 拍延迟） ----
    always @(posedge clk) desc_rd_data <= desc_mem[desc_rd_addr];

    // ---- DMA rd 模型 ----
    reg [1:0]  rds;               // 0 idle / 1 stream / 2 done / 3 err
    reg [31:0] rd_a;
    reg [19:0] rd_i, rd_n;
    reg [63:0] rd_cur;
    reg        fail_lut, dma_kill;

    function [63:0] fetch(input [31:0] a);
        integer b;
        begin
            if (a >= PARAM_BASE && a < PARAM_BASE + 32'd1536) begin
                b = (a - PARAM_BASE) >> 3;
                fetch = {paramw[2*b + 1], paramw[2*b]};
            end else if (a >= MIRROR_BASE &&
                         a < MIRROR_BASE + (MIRROR_BEATS << 3)) begin
                b = (a - MIRROR_BASE) >> 3;
                fetch = mirror[b];
            end else begin
                fetch = 64'hDEAD_BEEF_DEAD_BEEF;
                errors = errors + 1;
                $display("EES_P21_ERR [%0t] rd fetch outside model a=0x%08x",
                         $time, a);
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            rds <= 2'd0; rd_req_ready <= 1'b1; rd_beat_valid <= 1'b0;
            rd_done <= 1'b0; rd_cur <= 64'd0;
        end else begin
            rd_done <= 1'b0;
            case (rds)
              2'd0: if (rd_req_valid && rd_req_ready) begin
                  rd_a <= rd_addr; rd_n <= rd_len >> 3; rd_i <= 20'd0;
                  rd_req_cnt <= rd_req_cnt + 1;
                  if (fail_lut && rd_addr == MIRROR_BASE && rd_len == 24'd256)
                      rds <= 2'd3;                    // LUT 相位错误注入
                  else begin
                      rd_req_ready <= 1'b0;
                      rd_cur <= fetch(rd_addr);       // 首拍预取
                      rds <= 2'd1;
                  end
              end
              2'd1: begin
                  if (!rd_beat_valid) begin
                      rd_beat_valid <= 1'b1;
                      rd_beat_data  <= rd_cur;   // 首拍=接受沿预取值
                  end else if (rd_beat_ready) begin
                      if (rd_i == rd_n - 20'd1) begin
                          rd_beat_valid <= 1'b0;
                          rds <= 2'd2;
                      end else begin
                          rd_i <= rd_i + 20'd1;
                          // 逐拍内联取数：接收沿直取下一拍（rd_cur 同沿落地
                          // 不可链读）；未接收则保持——背压安全
                          rd_beat_data <= fetch(rd_a
                              + {12'd0, rd_i + 20'd1, 3'b000});
                      end
                  end
                  if (dma_kill) begin                 // abort：撤销在途流
                      rd_beat_valid <= 1'b0; rds <= 2'd0;
                      rd_req_ready  <= 1'b1;
                  end
              end
              2'd2: begin
                  rd_done <= 1'b1; rds <= 2'd0; rd_req_ready <= 1'b1;
              end
              2'd3: begin
                  dma_err_pulse <= 1'b1; rds <= 2'd0; rd_req_ready <= 1'b1;
              end
            endcase
        end
    end

    // dma_err_pulse 单拍化
    always @(posedge clk) if (dma_err_pulse) dma_err_pulse <= 1'b0;

    // ---- DMA wr 模型（V1.3：+WCFG/+SEED 背压与延迟配置面） ----
    //   wcfg=0 恒 ready（正典默认）；1 随机 ready；2 每 4 拍停 1 拍；
    //   3 每 4 拍停 3 拍；4 随机 ready + wr_done B 链延迟 0..31 拍
    //   （E_CHKY1 有界轮询上限 DMA_TMO=4096，延迟量安全）
    integer wcfg, wseed;
    reg [1:0]  wcfg_ph;
    integer    wdelay_left;
    reg [31:0] wrnd;                       // xorshift32 确定性随机源
    function [31:0] rnd_next;
        begin
            wrnd = (wrnd == 32'd0) ? 32'hDEAD_BEEF : wrnd;
            wrnd = wrnd ^ (wrnd << 13);
            wrnd = wrnd ^ (wrnd >> 17);
            wrnd = wrnd ^ (wrnd << 5);
            rnd_next = wrnd;
        end
    endfunction
    function wr_model_rdy;                 // 本拍 WREADY 决策
        reg [31:0] rv;
        begin
            case (wcfg)
              1, 4: begin rv = rnd_next(); wr_model_rdy = rv[0]; end
              2:    wr_model_rdy = (wcfg_ph != 2'd3);
              3:    wr_model_rdy = (wcfg_ph == 2'd0);
              default: wr_model_rdy = 1'b1;
            endcase
        end
    endfunction

    // ---- V1.8 写地址律监视器：期望=紧凑累计（TB 侧独立重算） ----
    integer mon_blk, mon_off, mon_req_chk;
    function integer exp_btt(input integer b);
        exp_btt = (((b / RC) % NSTRIP) == 0) ? 128 : 32;
    endfunction

    reg [1:0]  wrs;
    reg [31:0] wr_a;
    reg [19:0] wr_i, wr_n;
    always @(posedge clk) begin
        if (rst) begin
            wrs <= 2'd0; wr_req_ready <= 1'b1; wr_beat_ready <= 1'b0;
            wr_done <= 1'b0; wcfg_ph <= 2'd0; wdelay_left <= 0;
        end else begin
            wr_done <= 1'b0;
            case (wrs)
              2'd0: if (wr_req_valid && wr_req_ready) begin
                  wr_a <= wr_addr; wr_n <= wr_len >> 3; wr_i <= 20'd0;
                  // V1.3：区守卫改紧凑窗（25,600B）+32B 对齐
                  if (wr_addr < MIRROR_BASE + Y_OFF ||
                      wr_addr >= MIRROR_BASE + Y_OFF + Y_BYTES ||
                      (wr_addr[4:0] != 5'd0) || wr_len == 0) begin
                      errors = errors + 1;
                      $display("EES_P21_ERR [%0t] wr req outside compact y window a=0x%08x len=%0d",
                               $time, wr_addr, wr_len);
                  end
                  // 地址律监视：addr/len 逐块对紧凑期望
                  if (wr_addr != MIRROR_BASE + Y_OFF + mon_off ||
                      wr_len != exp_btt(mon_blk)) begin
                      errors = errors + 1;
                      $display("EES_P21_ERR [%0t] wr law blk=%0d a=0x%08x len=%0d exp_off=%0d exp_len=%0d",
                               $time, mon_blk, wr_addr, wr_len, mon_off,
                               exp_btt(mon_blk));
                  end else mon_req_chk = mon_req_chk + 1;
                  mon_off = mon_off + exp_btt(mon_blk);
                  mon_blk = mon_blk + 1;
                  wrs <= 2'd1; wcfg_ph <= 2'd0;
                  wr_beat_ready <= wr_model_rdy();
              end
              2'd1: begin
                  wcfg_ph <= wcfg_ph + 2'd1;
                  wr_beat_ready <= wr_model_rdy();
                  if (wr_beat_valid && wr_beat_ready) begin
                      // V1.2：strb=00 = E_ABORTD 冲刷拍（P2.2 正典，零
                      // 字节写入）合法——不写镜像不计错；部分 strobe 非法
                      if (wr_beat_strb == 8'hFF)
                          mirror[(wr_a - MIRROR_BASE
                                  + {12'd0, wr_i, 3'b000}) >> 3] <= wr_beat_data;
                      else if (wr_beat_strb != 8'h00) begin
                          errors = errors + 1;
                          $display("EES_P21_ERR [%0t] wr strb=%02x", $time,
                                   wr_beat_strb);
                      end
                      wr_i <= wr_i + 20'd1;
                      if (wr_i == wr_n - 20'd1) begin
                          wrs <= 2'd2; wr_beat_ready <= 1'b0;
                          // wcfg=4：B 链延迟 0..31 拍后才 wr_done
                          wdelay_left <= (wcfg == 4) ? (rnd_next() % 32) : 0;
                      end
                  end
                  // V1.2：撤销 dma_kill——真 DMA（ppu_dma_master）W 通道
                  // 在 abort 后不截断在途请求（引擎 E_ABORTD 以冲刷拍/
                  // 自然排空收口并等 wr_done），模型同步为受控收口
              end
              2'd2: begin
                  if (wdelay_left != 0) wdelay_left <= wdelay_left - 1;
                  else begin
                      wr_done <= 1'b1; wr_done_cnt <= wr_done_cnt + 1;
                      wrs <= 2'd0; wr_req_ready <= 1'b1;
                      if (wr_done_cnt % 64 == 63)
                          $display("EES_P21_INFO [%0t] blocks wr-done=%0d",
                                   $time, wr_done_cnt + 1);
                  end
              end
            endcase
        end
    end

    // ---- walker 激励任务 ----
    // 先等 busy 落回（E_ERRS/E_ABORTS 恢复段约 70 拍；不等则单拍 req
    // 脉冲会被恢复态吞掉 → 请求丢失 → 场景假超时）
    task issue_req(input [6:0] slot);
        begin
            while (busy_w && cyc < 12_000_000) @(negedge clk);
            repeat (2) @(negedge clk);
            mon_blk = 0; mon_off = 0;          // V1.3：地址律监视随新请求清
            req_valid = 1'b1; desc_idx = slot; opcode = 8'h01;
            @(negedge clk);
            req_valid = 1'b0;
        end
    endtask

    task wait_job(output reg got_done, output reg got_err,
                  input integer limit);
        begin
            got_done = 1'b0; got_err = 1'b0;
            while (!got_done && !got_err && cyc < limit) begin
                @(negedge clk);
                if (done_w) got_done = 1'b1;
                if (err_w)  got_err  = 1'b1;
            end
        end
    endtask

    // ---- 金像对拍 + 外排（V1.3：紧凑窗连续回读——原 128*b 槽位散读把
    //      RTL 定址律当期望=放置缺陷盲区，见板 H4） ----
    task check_y(input integer run_id, output integer bad_bytes);
        integer k, wbi;
        reg [63:0] wv;
        integer fd;
        begin
            bad_bytes = 0;
            // $sformatf 嵌 {} 拼接在 xsim 下串化塌陷（run 号丢失），
            // 整串一次 $sformatf 成形
            fd = $fopen($sformatf("%sy_got_run%0d.hex", PREP, run_id), "w");
            for (k = 0; k < Y_BYTES; k = k + 1) begin
                wbi = (Y_OFF + k) >> 3;
                wv = mirror[wbi];
                $fwrite(fd, "%02x\n", wv[8*((Y_OFF + k) & 7) +: 8]);
                if (wv[8*((Y_OFF + k) & 7) +: 8] !== golden[k])
                begin
                    bad_bytes = bad_bytes + 1;
                    if (bad_bytes <= 8)
                        $display("EES_P21_ERR [%0t] run%0d k=%0d got=%02x want=%02x",
                                 $time, run_id, k,
                                 wv[8*((Y_OFF + k) & 7) +: 8], golden[k]);
                end
            end
            $fclose(fd);
            if (bad_bytes == 0) checks = checks + NB;
        end
    endtask

    // ---- watchdog ----
    initial begin
        wait (rst == 1'b0);
        while (cyc < WATCH_CYC) @(negedge clk);
        $display("EES_P21_ERR WATCHDOG expiry cyc=%0d", cyc);
        $display("EES_P21_RESULT FAIL errors=%0d checks=%0d watchdog", errors,
                 checks);
        $finish;
    end

    // ---- 诊断：状态转移历史窗 + err 现场转储 ----
    integer hi;
    reg [5:0] st_hist [0:23];
    integer   st_tcyc [0:23];
    integer   dk, didx;
    initial begin
        hi = 0;
        for (dk = 0; dk < 24; dk = dk + 1) st_hist[dk] = 6'hxx;
    end
    always @(negedge clk) begin
        if (dut.state !== st_hist[hi]) begin
            hi = (hi + 1) % 24; st_hist[hi] = dut.state; st_tcyc[hi] = cyc;
        end
    end
    always @(negedge clk) if (err_w) begin
        $display("EES_P21_ERR err_code=0x%02x rd_q=0x%08x blk=%0d seg=%0d",
                 err_code_w, dut.rd_q, dut.blk, dut.seg);
        for (dk = 0; dk < 24; dk = dk + 1) begin
            didx = (hi + 1 + dk) % 24;
            if (st_hist[didx] !== 6'hxx)
                $display("  HIST cyc=%0d state=%0d", st_tcyc[didx],
                         st_hist[didx]);
        end
    end

    // ---- 调试：gemm 寄存器写侦听（非 LUTD，前 48 条）+ 装载流首拍 ----
    integer spy_n, spy_ld;
    initial begin spy_n = 0; spy_ld = 0; end
    always @(negedge clk) if (dut.u_gemm.s_axi_bvalid) begin
        if (dut.u_gemm.awaddr_r[7:0] != 8'h44 && spy_n < 48) begin
            $display("EES_P21_WR[%0d] a=%02x d=%08x", spy_n,
                     dut.u_gemm.awaddr_r[7:0], dut.u_gemm.wdata_r);
            spy_n = spy_n + 1;
        end
    end
    always @(negedge clk)
        if (spy_ld < 6 && dut.state == 6'd19
            && dut.rd_beat_valid_i && dut.ld_tready) begin
            $display("EES_P21_LD[%0d] beat=%h (mirror[32+%0d]=%h)", spy_ld,
                     dut.rd_beat_data_i, spy_ld, mirror[32 + spy_ld]);
            spy_ld = spy_ld + 1;
        end

    // ---- S5（P2.3 V2.0 槽跨距地址单元门）：E_FADDR 态采实际取数地址 ----
    integer s5_n;
    reg     s5_cap;
    reg [11:0] s5_addrs [0:7];
    always @(negedge clk)
        if (s5_cap && dut.state == 6'd1) begin            // E_FADDR
            if (s5_n < 8) s5_addrs[s5_n] = desc_rd_addr;
            s5_n = s5_n + 1;
        end

    // ---- S1 静默性锁存（s1_arm 窗口内捕获 done/err 脉冲） ----
    reg s1_arm, s1_done, s1_err;
    always @(negedge clk) begin
        if (s1_arm) begin
            if (done_w) s1_done <= 1'b1;
            if (err_w)  s1_err  <= 1'b1;
        end else begin
            s1_done <= 1'b0; s1_err <= 1'b0;
        end
    end

    // ---- 主序列 ----
    reg gd, ge;
    integer bad, err_a, cnt0;
    initial begin
        cyc = 0; checks = 0; errors = 0;
        req_valid = 0; desc_idx = 0; opcode = 0; abort_p = 0;
        dma_err_pulse = 0; dma_err_code = 8'h11;
        rd_req_cnt = 0; wr_done_cnt = 0;
        fail_lut = 0; dma_kill = 0;
        // V1.3：背压/延迟配置面（+WCFG 0..4，+SEED 任意，缺省 0/1）
        if (!$value$plusargs("WCFG=%d", wcfg))   wcfg = 0;
        if (!$value$plusargs("SEED=%d", wseed))  wseed = 1;
        wrnd = (32'h9E3779B9 * wseed) ^ 32'hC0FFEE11;
        mon_blk = 0; mon_off = 0; mon_req_chk = 0;
        $display("EES_P21_CFG wcfg=%0d seed=%0d", wcfg, wseed);

        $readmemh({PREP, "p21_mirror.hex"},  mirror);
        $readmemh({PREP, "p21_param.hex"},   paramw);
        $readmemh({PREP, "p21_desc.hex"},    desc_mem);
        $readmemh({PREP, "p21_golden_y.hex"}, golden);

        rst = 1'b1;
        repeat (16) @(negedge clk);
        rst = 1'b0;
        repeat (16) @(negedge clk);

        // ==== S0：全卷 K576 对拍 ====
        issue_req(SLOT_CONV);
        wait_job(gd, ge, cyc + 12_000_000);
        if (gd && !ge) begin
            check_y(0, bad);
            // V1.3：紧凑游标总量断言（末块后恰 25,600B，无空洞无越窗）
            if (mon_off == Y_BYTES && mon_blk == NB) checks = checks + 1;
            else begin
                errors = errors + 1;
                $display("EES_P21_ERR S0_CURSOR_TOTAL off=%0d blk=%0d want %0d/%0d",
                         mon_off, mon_blk, Y_BYTES, NB);
            end
            if (bad == 0)
                $display("EES_P21_STAGE S0_MAIN PASS cyc=%0d rd_req=%0d blk_wr=%0d mon_req=%0d",
                         cyc, rd_req_cnt, wr_done_cnt, mon_req_chk);
            else begin
                errors = errors + 1;
                $display("EES_P21_STAGE S0_MAIN FAIL bad_bytes=%0d", bad);
            end
        end else begin
            errors = errors + 1;
            $display("EES_P21_STAGE S0_MAIN FAIL done=%0d err=%0d code=0x%02x cyc=%0d",
                     gd, ge, err_code_w, cyc);
        end

        // ==== S1：运行中 abort（≥2 块 wr_done 后）静默取消 ====
        @(negedge clk);                 // S0 done 脉冲消隐（防 s1 锁存竞态）
        cnt0 = wr_done_cnt;
        s1_arm = 1'b1;
        issue_req(SLOT_CONV);
        err_a = errors;
        while (wr_done_cnt < cnt0 + 2 && !s1_done && !s1_err
               && cyc < 12_000_000)
            @(negedge clk);
        repeat (10) @(negedge clk);
        abort_p = 1'b1; dma_kill = 1'b1;
        @(negedge clk);
        abort_p = 1'b0; dma_kill = 1'b0;
        while (busy_w && cyc < 12_000_000) @(negedge clk);
        s1_arm = 1'b0;
        if (busy_w || s1_done || s1_err || errors != err_a) begin
            errors = errors + 1;
            $display("EES_P21_STAGE S1_ABORT FAIL busy=%0d done=%0d err=%0d cyc=%0d",
                     busy_w, s1_done, s1_err, cyc);
        end else
            $display("EES_P21_STAGE S1_ABORT PASS cyc=%0d blk_wr=%0d",
                     cyc, wr_done_cnt);

        // ==== S2：abort 后整卷重跑（恢复闭环） ====
        issue_req(SLOT_CONV);
        wait_job(gd, ge, cyc + 12_000_000);
        if (gd && !ge) begin
            check_y(2, bad);
            if (mon_off == Y_BYTES && mon_blk == NB) checks = checks + 1;
            else begin
                errors = errors + 1;
                $display("EES_P21_ERR S2_CURSOR_TOTAL off=%0d blk=%0d want %0d/%0d",
                         mon_off, mon_blk, Y_BYTES, NB);
            end
            if (bad == 0)
                $display("EES_P21_STAGE S2_RERUN PASS cyc=%0d rd_req=%0d blk_wr=%0d mon_req=%0d",
                         cyc, rd_req_cnt, wr_done_cnt, mon_req_chk);
            else begin
                errors = errors + 1;
                $display("EES_P21_STAGE S2_RERUN FAIL bad_bytes=%0d", bad);
            end
        end else begin
            errors = errors + 1;
            $display("EES_P21_STAGE S2_RERUN FAIL done=%0d err=%0d code=0x%02x cyc=%0d",
                     gd, ge, err_code_w, cyc);
        end

        // ==== S3：非法 K desc → err 0x02 ====
        issue_req(SLOT_BADK);
        wait_job(gd, ge, cyc + 100_000);
        if (!gd && ge && err_code_w == 8'h02) begin
            checks = checks + 1;
            $display("EES_P21_STAGE S3_BADK PASS code=0x%02x", err_code_w);
        end else begin
            errors = errors + 1;
            $display("EES_P21_STAGE S3_BADK FAIL done=%0d err=%0d code=0x%02x",
                     gd, ge, err_code_w);
        end
        while (busy_w && cyc < 12_000_000) @(negedge clk);

        // ==== S4：LUT 相位 DMA 错注入 → err 0x04 ====
        fail_lut = 1'b1;
        issue_req(SLOT_CONV);
        wait_job(gd, ge, cyc + 100_000);
        fail_lut = 1'b0;
        if (!gd && ge && err_code_w == 8'h04) begin
            checks = checks + 1;
            $display("EES_P21_STAGE S4_LUTERR PASS code=0x%02x", err_code_w);
        end else begin
            errors = errors + 1;
            $display("EES_P21_STAGE S4_LUTERR FAIL done=%0d err=%0d code=0x%02x",
                     gd, ge, err_code_w);
        end

        // ==== S5：P2.3 槽跨距地址单元门（探测槽 0/1/2/63/64/127） ====
        // 每槽五字段填不同标记，断言实际五次读地址 = 32*fw+{3,4,8,10,11}
        // 与锁存 dw 内容；K 标记低 12 位 0xFFF=非法 → EC_GEOM 0x02 快错
        // （E_GEOM 链律，DMA 前，无 wr 流量）。旧码（4 位字偏移 16*fw+w）
        // 在非零槽地址/内容皆错 → 本节失败；槽 0 两律同址恰掩盖（对照项）。
        begin : s5blk
            integer ps, fw, j, aok, cok, eok;
            reg [11:0] expa;
            s5_cap = 1'b1;
            for (ps = 0; ps < 6; ps = ps + 1) begin
                case (ps)
                    0: fw = 0; 1: fw = 1; 2: fw = 2; 3: fw = 63;
                    default: fw = (ps == 4) ? 64 : 127;
                endcase
                desc_mem[32*fw + 3]  = {8'hA5, fw[7:0], 16'h0003};
                desc_mem[32*fw + 4]  = {8'h5A, fw[7:0], 16'h0004};
                desc_mem[32*fw + 8]  = {8'hC3, fw[7:0], 16'h0008};
                desc_mem[32*fw + 10] = {8'h3C, fw[7:0], 16'h000A};
                desc_mem[32*fw + 11] = {fw[6:0], 13'd0, 12'hFFF};
                s5_n = 0;
                issue_req(fw[6:0]);
                wait_job(gd, ge, cyc + 100_000);
                aok = (s5_n == 5);
                expa = 32*fw + 3;
                if (s5_addrs[0] !== expa) aok = 0;
                expa = 32*fw + 4;
                if (s5_addrs[1] !== expa) aok = 0;
                expa = 32*fw + 8;
                if (s5_addrs[2] !== expa) aok = 0;
                expa = 32*fw + 10;
                if (s5_addrs[3] !== expa) aok = 0;
                expa = 32*fw + 11;
                if (s5_addrs[4] !== expa) aok = 0;
                cok = (dut.dw_oc_ho === {8'hA5, fw[7:0], 16'h0003})
                   && (dut.dw_wo    === {8'h5A, fw[7:0], 16'h0004})
                   && (dut.dw_arena === {8'hC3, fw[7:0], 16'h0008})
                   && (dut.dw_param === {8'h3C, fw[7:0], 16'h000A})
                   && (dut.dw_k_act[31:25] === fw[6:0])
                   && (dut.dw_k_act[11:0] === 12'hFFF);
                eok = (!gd && ge && err_code_w == 8'h02);
                if (aok && cok && eok) begin
                    checks = checks + 3;
                    $display("EES_P21_STAGE S5_SLOT%0d PASS addr/cnt/code a0=%0d",
                             fw, s5_addrs[0]);
                end else begin
                    errors = errors + 1;
                    $display("EES_P21_STAGE S5_SLOT%0d FAIL a=%0d/%0d/%0d/%0d/%0d(n=%0d) c=%0d e=%0d(d=%0d,e=%0d,code=%02x)",
                             fw, s5_addrs[0], s5_addrs[1], s5_addrs[2],
                             s5_addrs[3], s5_addrs[4], s5_n, cok, eok,
                             gd, ge, err_code_w);
                end
            end
            s5_cap = 1'b0;
        end

        $display("EES_P21_RESULT %s errors=%0d checks=%0d cyc=%0d rd_req=%0d blk_wr=%0d wcfg=%0d seed=%0d",
                 (errors == 0) ? "PASS" : "FAIL", errors, checks, cyc,
                 rd_req_cnt, wr_done_cnt, wcfg, wseed);
        $finish;
    end
endmodule
