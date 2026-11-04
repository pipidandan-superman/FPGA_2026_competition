/************************************************************************
 * File Name     : tb_yolo_gemm_p13_k2304.sv
 * Developer     : LSL
 * Date          : 2026-09-20
 * Module Name   : tb_yolo_gemm_p13_k2304
 * Description   : run07 / P1.3 K2304 链门（model.22.cv2.2.0
 *                 [1024,1024,256] 三块 K 链 + bank 组重用）仿真门。
 *                 yolo_gemm_top V1.2 + array V2.3（零 RTL 改动档）+
 *                 run07 真实数据旁车。
 *   目的（D2 链语义 + 组重用）：
 *     - job1 GEOM=1024 act|first grp0 初始化累加器；job2 GEOM=1024
 *       act grp1（first=0 last=0 中间块，零 y 输出）；job3 GEOM=256
 *       act|last grp0（组重用：L3 在 job2 被接收=grp0 读窗结束后装载）
 *       ——只有末块出 y。
 *     - job2/job3 均在 busy 中排队（递交槽占用语义）。
 *   判据：
 *     LDLEN 1024/1024（块1、块2后）与 256/256（块3后）；STATUS 零错误位；
 *     tile_done 收口 busy=0；ycnt=80；数据==golden slots（10 字，tlast
 *     恰在第 10 字）；两用例（tile0/rc0 + tile9/rc7）间 soft_rst 恢复。
 * Revision History:
 *   - V1.0 (2026-09-20) by LSL : run07 链门初版（承袭
 *                 tb_yolo_gemm_p13_k1152.sv V1.0 结构）。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_p13_k2304;

    // ---- 时钟/复位 ----
    reg clk, rstn;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- AXI4-Lite 主侧（PS 角色，逐字承袭 run26/27 TB）----
    reg  [31:0] awaddr, wdata;
    reg  [2:0]  awprot;
    reg         awvalid, wvalid;
    wire        awready;
    wire        wready;
    wire        bvalid;
    reg         bready;
    reg  [3:0]  wstrb;
    wire [1:0]  bresp;
    reg  [31:0] araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready, rvalid;
    reg         rready;
    wire [31:0] rdata;
    wire [1:0]  rresp;

    // ---- AXI4-Stream ----
    reg  [63:0] s_axis_ld_tdata;
    reg         s_axis_ld_tvalid;
    wire        s_axis_ld_tready;
    reg         s_axis_ld_tlast;
    wire [63:0] m_axis_y_tdata;
    wire        m_axis_y_tvalid;
    reg         m_axis_y_tready;
    wire        m_axis_y_tlast;

    initial begin
        bready = 1'b1; rready = 1'b1;
        s_axis_ld_tdata = 64'd0;
        s_axis_ld_tvalid = 1'b0;
        s_axis_ld_tlast = 1'b0;
        m_axis_y_tready = 1'b1;
    end

    // ---- DUT ----
    yolo_gemm_top u_dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .s_axis_ld_tdata(s_axis_ld_tdata), .s_axis_ld_tvalid(s_axis_ld_tvalid),
        .s_axis_ld_tready(s_axis_ld_tready), .s_axis_ld_tlast(s_axis_ld_tlast),
        .m_axis_y_tdata(m_axis_y_tdata), .m_axis_y_tvalid(m_axis_y_tvalid),
        .m_axis_y_tready(m_axis_y_tready), .m_axis_y_tlast(m_axis_y_tlast)
    );

    // ---- 记账 ----
    integer checks, errors;
    integer beats_acc, y_word_cnt;
    integer cyc;
    always @(negedge clk) cyc = cyc + 1;

    // ---- 权威数据（run07 packer 旁车）----
    reg [63:0] ld_b1_0  [0:3071];  //t0r0 块1（GEOM 1024）
    reg [63:0] ld_b2_0  [0:3071];  //t0r0 块2（GEOM 1024）
    reg [63:0] ld_b3_0  [0:767];   //t0r0 块3（GEOM 256，组重用 grp0）
    reg [63:0] ld_b1_9  [0:3071];  //t9r7
    reg [63:0] ld_b2_9  [0:3071];
    reg [63:0] ld_b3_9  [0:767];
    reg [63:0] slot_0   [0:9];     //期望 10 字（law byte=r*10+cv）
    reg [63:0] slot_9   [0:9];
    reg [31:0] pctl_0   [0:23];    //8 x (b_eff,M,shift) rc=0
    reg [31:0] pctl_7   [0:23];    //rc=7
    reg [31:0] lut_b    [0:255];

    // ---- CSR 地址（合同 §9，承袭 G4 TB）----
    localparam [31:0] A_ID     = 32'h00, A_CTRL   = 32'h04, A_STATUS = 32'h08;
    localparam [31:0] A_GEOM   = 32'h0C, A_ROWVAL = 32'h10, A_NMASK  = 32'h14;
    localparam [31:0] A_JOBCFG = 32'h18, A_LDGRP  = 32'h1C, A_P_BIAS = 32'h20;
    localparam [31:0] A_P_M    = 32'h24, A_P_SH   = 32'h28, A_PCTL   = 32'h2C;
    localparam [31:0] A_LDSTAT = 32'h3C, A_LDLEN  = 32'h40, A_LUTD   = 32'h44;
    localparam [31:0] A_YSTAT  = 32'h48, A_BRGSTAT= 32'h54, A_STALLCNT = 32'h58;

    integer BEATS12 = 3072, BEATS3 = 768;

    // ---- AXI-Lite 主任务（逐字承袭 run26/27 G4 TB 原文）----
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            awaddr = a; awprot = 3'd0; awvalid = 1'b1;
            wdata = d; wstrb = 4'hF; wvalid = 1'b1;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] write 0x%03x SLVERR", $time, a);
            end
            awvalid = 1'b0; wvalid = 1'b0;
            @(negedge clk);
        end
    endtask

    task axi_read(input [31:0] a, output [31:0] d);
        begin
            @(negedge clk);
            araddr = a; arprot = 3'd0; arvalid = 1'b1;
            while (!rvalid) @(negedge clk);
            d = rdata;
            if (rresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] read 0x%03x SLVERR", $time, a);
            end
            arvalid = 1'b0;
            @(negedge clk);
        end
    endtask

    task gapn(input integer n);
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    // ---- MM2S BFM：连续流；sel 0..5 = b1/b2/b3 x {t0r0,t9r7} ----
    task dma_send(input integer sel);
        integer bi, bn;
        begin
            bn = (sel == 2 || sel == 5) ? BEATS3 : BEATS12;
            bi = 0;
            while (bi < bn) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                case (sel)
                    0: s_axis_ld_tdata = ld_b1_0[bi];
                    1: s_axis_ld_tdata = ld_b2_0[bi];
                    2: s_axis_ld_tdata = ld_b3_0[bi];
                    3: s_axis_ld_tdata = ld_b1_9[bi];
                    4: s_axis_ld_tdata = ld_b2_9[bi];
                    5: s_axis_ld_tdata = ld_b3_9[bi];
                endcase
                s_axis_ld_tlast  = (bi == bn - 1);
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) begin
                    bi = bi + 1;
                    beats_acc = beats_acc + 1;
                end
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0; s_axis_ld_tlast = 1'b0;
        end
    endtask

    // ---- y 收集器（posedge 采样；collect_en 场景门）----
    reg        collect_en, tile_sig;
    integer    sw_q, exp_n;
    reg [63:0] slot_got [0:15];
    always @(posedge clk) begin
        if (collect_en && m_axis_y_tvalid && m_axis_y_tready) begin
            if (sw_q < 16) slot_got[sw_q] = m_axis_y_tdata;
            if (^slot_got[(sw_q < 16) ? sw_q : 15] === 1'bx) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] X on y word %0d data=%016x",
                         $time, sw_q, m_axis_y_tdata);
            end
            if (m_axis_y_tlast) begin
                $display("EES_P13D_INFO [%0t] TLAST at word %0d (exp %0d)",
                         $time, sw_q, exp_n - 1);
                if (sw_q != exp_n - 1) begin
                    errors = errors + 1;
                    $display("EES_P13D_ERR [%0t] tlast at word %0d (exp %0d)",
                             $time, sw_q, exp_n - 1);
                end
                tile_sig = 1;
            end
            sw_q = sw_q + 1;
            y_word_cnt = y_word_cnt + 1;
        end
    end

    // ---- 共用暂存 ----
    reg [31:0] rd, st;
    integer guard, r, q, bi;

    // ---- 单用例：三块 K 链（组重用 0,1,0）----
    // cs: 0 = tile0/rc0, 1 = tile9/rc7
    task run_chain_case(input integer cs);
        begin
            // §10.2 配置组（PCTL 对应 rc 行组 + ROWVAL/NMASK）
            for (r = 0; r < 8; r = r + 1) begin
                if (cs == 0) begin
                    axi_write(A_P_BIAS, pctl_0[r*3 + 0]);
                    axi_write(A_P_M,    pctl_0[r*3 + 1]);
                    axi_write(A_P_SH,   pctl_0[r*3 + 2]);
                end else begin
                    axi_write(A_P_BIAS, pctl_7[r*3 + 0]);
                    axi_write(A_P_M,    pctl_7[r*3 + 1]);
                    axi_write(A_P_SH,   pctl_7[r*3 + 2]);
                end
                axi_write(A_PCTL,   {29'd0, 1'b1, r[2:0]});
            end
            axi_write(A_ROWVAL, 32'h0000_00FF);
            axi_write(A_NMASK,  32'h0000_03FF);
            // 块1：GEOM=1024 act|first grp0；流+start（start 落流窗内）
            axi_write(A_GEOM,   32'd1024);
            axi_write(A_JOBCFG, 32'h3);
            axi_write(A_LDGRP,  32'h0);
            collect_en = 1'b1; sw_q = 0; tile_sig = 1'b0; exp_n = 10;
            fork
                dma_send(cs == 0 ? 0 : 3);
                begin
                    gapn(4);
                    axi_write(A_CTRL, 32'd1);
                end
            join
            // 等 job1 递交槽清（feeder 收单）
            guard = 0; st = 32'hFFFF_FFFF;
            while (st[1] && guard < 2000) begin
                axi_read(A_STATUS, st); guard = guard + 1;
            end
            if (st[1]) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] job1 pend never cleared", $time);
            end
            gapn(16);
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd1024 || rd[25:13] != 13'd1024) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] LDLEN b1=%08x", $time, rd);
            end else checks = checks + 1;
            // 块2：grp1 装载 + job2 排队（GEOM=1024 act grp1，中间块）
            axi_write(A_LDGRP, 32'h3);
            dma_send(cs == 0 ? 1 : 4);
            gapn(16);
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd1024 || rd[25:13] != 13'd1024) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] LDLEN b2=%08x", $time, rd);
            end else checks = checks + 1;
            // job2 = act|w_grp|x_grp = 1+8+16 = 0x19（JOBCFG 位图 §9：
            // bit1=first bit3=w_grp bit4=x_grp。组选择双字段同置，与
            // LDGRP 律同源。首版误写 0x11（漏 bit3→W 读 grp0），二版误写
            // 0x13（错置 bit1→job2 被标首块、累加器重初始化）——两事故
            // 均由 Z1/Z2 零注入 + feeder 字流监测（W=1024/1024 全错、X
            // 全对）定位）
            axi_write(A_GEOM,   32'd1024);
            axi_write(A_JOBCFG, 32'h19);
            axi_write(A_CTRL,   32'd1);
            // 等 job2 被接收（=feeder 读完 grp0 的 job1 数据窗）
            guard = 0; st = 32'hFFFF_FFFF;
            while (st[1] && guard < 2000) begin
                axi_read(A_STATUS, st); guard = guard + 1;
            end
            if (st[1]) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] job2 pend never cleared", $time);
            end
            // 块3：grp0 组重用装载（job2 读 grp1，无冲突），job3 排队
            axi_write(A_LDGRP,  32'h0);
            dma_send(cs == 0 ? 2 : 5);
            gapn(16);
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd256 || rd[25:13] != 13'd256) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] LDLEN b3=%08x", $time, rd);
            end else checks = checks + 1;
            axi_write(A_GEOM,   32'd256);
            axi_write(A_JOBCFG, 32'h5);
            axi_write(A_CTRL,   32'd1);
            // 完成判据：busy=0 + tile_done + 队列空 + 无错误
            guard = 0; st = 32'hFFFF_FFFF;
            while ((st[0] || !st[5] || st[1]) && guard < 100000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            if (st[0] || !st[5] || st[1]) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] chain poll timeout STATUS=%08x",
                         $time, st);
            end
            if (st[6] || st[7] || st[8] || st[9] || st[2]) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] STATUS err bits %08x", $time, st);
            end
            // YSTAT ycnt 对账（10 字 x8B）
            axi_read(A_YSTAT, rd);
            if (rd[15:0] != 16'd80) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] YSTAT ycnt=%0d exp=80",
                         $time, rd[15:0]);
            end else checks = checks + 1;
            // y 收齐判定 + 数据对拍
            guard = 0;
            while (!(tile_sig && sw_q == 10) && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!(tile_sig && sw_q == 10)) begin
                errors = errors + 1;
                $display("EES_P13D_ERR [%0t] y collect timeout sw_q=%0d tile_sig=%0d",
                         $time, sw_q, tile_sig);
            end else begin
                for (q = 0; q < 10; q = q + 1) begin
                    if (slot_got[q] !== ((cs == 0) ? slot_0[q] : slot_9[q])) begin
                        errors = errors + 1;
                        $display("EES_P13D_ERR [%0t] q=%0d got=%016x want=%016x",
                                 $time, q, slot_got[q],
                                 (cs == 0) ? slot_0[q] : slot_9[q]);
                    end else checks = checks + 1;
                end
            end
            // STALLCNT 读清留档
            axi_read(A_STALLCNT, rd);
            collect_en = 1'b0;
            gapn(2);
        end
    endtask

    // ---- watchdog ----
    initial begin
        wait (rstn === 1'b1);
        while (cyc < 4_000_000) @(negedge clk);
        $display("EES_P13D_ERR WATCHDOG expiry cyc=%0d", cyc);
        $finish;
    end

    integer errors_a;
    initial begin
        cyc = 0; checks = 0; errors = 0;
        beats_acc = 0; y_word_cnt = 0;
        collect_en = 0; tile_sig = 0; sw_q = 0; exp_n = 0;

        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t0r0_b1.hex", ld_b1_0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t0r0_b2.hex", ld_b2_0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t0r0_b3.hex", ld_b3_0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t9r7_b1.hex", ld_b1_9);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t9r7_b2.hex", ld_b2_9);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_ld_t9r7_b3.hex", ld_b3_9);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_slots_t0r0.hex", slot_0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_slots_t9r7.hex", slot_9);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_pctl_t0.hex", pctl_0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_pctl_t7.hex", pctl_7);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run07_k2304_chain/p13c7_lut.hex", lut_b);

        rstn = 1'b0;
        repeat (16) @(negedge clk);
        rstn = 1'b1;
        gapn(16);

        // ---- 初始化（§10.1）：ID + LUT 256 ----
        axi_read(A_ID, rd);
        if (rd != 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_P13D_ERR ID=%08x", rd);
        end else checks = checks + 1;
        for (bi = 0; bi < 256; bi = bi + 1)
            axi_write(A_LUTD, {8'd0, bi[7:0], lut_b[bi][7:0]});
        axi_write(A_CTRL, 32'h4);            //清 sticky
        gapn(4);
        $display("EES_P13D_STAGE INIT done t=%0t", $time);

        // ==== CASE_T0R0：tile0/rc0（三块链 + 组重用）====
        run_chain_case(0);
        errors_a = errors;
        if (errors == 0)
            $display("EES_P13D_STAGE CASE_T0R0 PASS t=%0t", $time);
        else
            $display("EES_P13D_STAGE CASE_T0R0 FAIL errors=%0d t=%0t",
                     errors, $time);

        // 用例间恢复（soft_rst 清运行态，配置保留）
        axi_write(A_CTRL, 32'h2);
        gapn(8);
        axi_read(A_BRGSTAT, rd);
        if (rd != 32'd0) begin
            errors = errors + 1;
            $display("EES_P13D_ERR inter-case BRGSTAT=%08x", rd);
        end

        // ==== CASE_T9R7：tile9/rc7（末行/末块行边界）====
        run_chain_case(1);
        if (errors == errors_a)
            $display("EES_P13D_STAGE CASE_T9R7 PASS t=%0t", $time);
        else
            $display("EES_P13D_STAGE CASE_T9R7 FAIL errors+%0d t=%0t",
                     errors - errors_a, $time);

        $display("EES_P13D_RESULT %s errors=%0d checks=%0d beats=%0d ywords=%0d cyc=%0d",
                 (errors == 0) ? "PASS" : "FAIL", errors, checks,
                 beats_acc, y_word_cnt, cyc);
        $finish;
    end
endmodule
