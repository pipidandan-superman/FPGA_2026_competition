/************************************************************************
 * File Name     : tb_yolo_gemm_p13_mask.sv
 * Developer     : LSL
 * Date          : 2026-09-20
 * Module Name   : tb_yolo_gemm_p13_mask
 * Description   : run03 / P1.3 K576 masked-tile y-tlast 缺陷复现门。
 *                 yolo_gemm_top V1.2 + run02 K576 正典数据（真实
 *                 block 0 / block 8，TB 零数学模型）。
 *   背景（板上证据 run02 attempt2 + 5 实验探针矩阵）：
 *     - b=8（n_mask=0x000F）：y 数据 32B 与 golden 紧凑 law 逐位一致，
 *       但流上无 tlast —— BTT=32 EOL-late(0x5011)、BTT>=40 悬挂。
 *     - b=0（n_mask=0xFFFF）：16 字 + tlast 干净（对照）。
 *   RTL 推因：S_TAIL 固定扫满 128 ti，掩码 tile 末有效 y 拍（ti=115+D）
 *       早于扫掠终点 ~12 拍；tile_done（TAILW 出口）晚于末字被弹 ~7 拍
 *       → top 桥 4 条 tlast 合并路径全部 miss。
 *   判据：
 *     CASE_FULL  b=0 n_mask=0xFFFF：16 字，tlast 恰在第 16 字，数据==golden
 *     CASE_MASK  b=8 n_mask=0x000F：4 字，tlast 恰在第 4 字，数据==golden
 *     （当前 RTL 预期 CASE_MASK tlast 缺失 → 复现；修复后双绿）
 * Revision History:
 *   - V1.0 (2026-09-20) by LSL : run03 缺陷复现初版。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_p13_mask;

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

    // ---- 权威数据（run03 hexgen 旁车）----
    reg [63:0] ld_b0    [0:1727];   //block 0（满 tile 对照）
    reg [63:0] ld_b8    [0:1727];   //block 8（掩码 tile 缺陷块）
    reg [63:0] slot_b0  [0:15];     //期望 16 字（满 law）
    reg [63:0] slot_b8  [0:3];      //期望 4 字（紧凑 law）
    reg [31:0] pctl_w   [0:23];     //8 x (b_eff,M,shift) rc=0/g=0
    reg [31:0] lut_b    [0:255];

    // ---- CSR 地址（合同 §9，承袭 G4 TB）----
    localparam [31:0] A_ID     = 32'h00, A_CTRL   = 32'h04, A_STATUS = 32'h08;
    localparam [31:0] A_GEOM   = 32'h0C, A_ROWVAL = 32'h10, A_NMASK  = 32'h14;
    localparam [31:0] A_JOBCFG = 32'h18, A_LDGRP  = 32'h1C, A_P_BIAS = 32'h20;
    localparam [31:0] A_P_M    = 32'h24, A_P_SH   = 32'h28, A_PCTL   = 32'h2C;
    localparam [31:0] A_LDSTAT = 32'h3C, A_LDLEN  = 32'h40, A_LUTD   = 32'h44;
    localparam [31:0] A_YSTAT  = 32'h48, A_BRGSTAT= 32'h54, A_STALLCNT = 32'h58;

    integer BEATS = 1728;
    integer K576  = 576;

    // ---- AXI-Lite 主任务（逐字承袭 run26/27 G4 TB 原文）----
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            awaddr = a; awprot = 3'd0; awvalid = 1'b1;
            wdata = d; wstrb = 4'hF; wvalid = 1'b1;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] write 0x%03x SLVERR", $time, a);
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
                $display("EES_P13_ERR [%0t] read 0x%03x SLVERR", $time, a);
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

    // ---- MM2S BFM：连续流（本 TB 不注入气泡，聚焦 tlast 时序）----
    task dma_send(input integer sel);   //0=block0 1=block8
        integer bi;
        begin
            bi = 0;
            while (bi < BEATS) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                s_axis_ld_tdata  = (sel == 0) ? ld_b0[bi] : ld_b8[bi];
                s_axis_ld_tlast  = (bi == BEATS - 1);
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
                $display("EES_P13_ERR [%0t] X on y word %0d data=%016x",
                         $time, sw_q, m_axis_y_tdata);
            end
            if (m_axis_y_tlast) begin
                $display("EES_P13_INFO [%0t] TLAST at word %0d (exp %0d)",
                         $time, sw_q, exp_n - 1);
                if (sw_q != exp_n - 1) begin
                    errors = errors + 1;
                    $display("EES_P13_ERR [%0t] tlast at word %0d (exp %0d)",
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

    // ---- 单用例：配置 -> 流+start -> 完成判据 -> y 对拍 ----
    task run_case(input integer sel, input [15:0] nmask,
                  input integer en);
        begin
            // §10.2 配置组（PCTL rc=0 行组 + GEOM/ROWVAL/NMASK/JOBCFG）
            for (r = 0; r < 8; r = r + 1) begin
                axi_write(A_P_BIAS, pctl_w[r*3 + 0]);
                axi_write(A_P_M,    pctl_w[r*3 + 1]);
                axi_write(A_P_SH,   pctl_w[r*3 + 2]);
                axi_write(A_PCTL,   {29'd0, 1'b1, r[2:0]});
            end
            axi_write(A_GEOM,   K576);
            axi_write(A_ROWVAL, 32'h0000_00FF);
            axi_write(A_NMASK,  {16'd0, nmask});
            axi_write(A_JOBCFG, 32'h7);       //act|first|last, g=0
            axi_write(A_LDGRP,  32'h0);
            // y 收集器武装
            collect_en = 1'b1; sw_q = 0; tile_sig = 1'b0; exp_n = en;
            // MM2S 流 + CTRL.start（start 落在流窗内，§10.2 正典）
            fork
                dma_send(sel);
                begin
                    gapn(4);
                    axi_write(A_CTRL, 32'd1);
                end
            join
            // 完成判据：busy=0 + tile_done + 无错误
            guard = 0; st = 32'hFFFF_FFFF;
            axi_read(A_STATUS, st);
            while (!(st[0] == 1'b0 && st[5]) && guard < 50000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            if (!(st[0] == 1'b0 && st[5])) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] tile poll timeout STATUS=%08x",
                         $time, st);
            end
            if (st[6] || st[7] || st[8] || st[9]) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] STATUS err bits %08x", $time, st);
            end
            // LDLEN 对账（576/576）
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd576 || rd[25:13] != 13'd576) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] LDLEN=%08x", $time, rd);
            end
            // YSTAT ycnt 对账（满 128 / 掩码 32）
            axi_read(A_YSTAT, rd);
            if (rd[15:0] != (en * 8)) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] YSTAT ycnt=%0d exp=%0d",
                         $time, rd[15:0], en * 8);
            end
            // y 收齐判定（tlast 已到且字数=期望；无 tlast 则超时暴露）
            guard = 0;
            while (!(tile_sig && sw_q == en) && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!(tile_sig && sw_q == en)) begin
                errors = errors + 1;
                $display("EES_P13_ERR [%0t] y collect timeout sw_q=%0d tile_sig=%0d (tlast missing)",
                         $time, sw_q, tile_sig);
                for (q = 0; q < sw_q && q < 16; q = q + 1) begin
                    if (sel == 0) begin
                        if (slot_got[q] !== slot_b0[q]) begin
                            errors = errors + 1;
                            $display("EES_P13_ERR [%0t] q=%0d got=%016x want=%016x",
                                     $time, q, slot_got[q], slot_b0[q]);
                        end else checks = checks + 1;
                    end else begin
                        if (slot_got[q] !== slot_b8[q]) begin
                            errors = errors + 1;
                            $display("EES_P13_ERR [%0t] q=%0d got=%016x want=%016x",
                                     $time, q, slot_got[q], slot_b8[q]);
                        end else checks = checks + 1;
                    end
                end
            end else begin
                for (q = 0; q < en; q = q + 1) begin
                    if (slot_got[q] !== ((sel == 0) ? slot_b0[q]
                                                    : slot_b8[q])) begin
                        errors = errors + 1;
                        $display("EES_P13_ERR [%0t] q=%0d got=%016x",
                                 $time, q, slot_got[q]);
                    end else checks = checks + 1;
                end
            end
            // STALLCNT 读清留档
            axi_read(A_STALLCNT, rd);
            collect_en = 1'b0;
            gapn(2);
        end
    endtask

    // ---- watchdog（等复位释放再计时；届时 cyc 已由主序列初始化）----
    initial begin
        wait (rstn === 1'b1);
        while (cyc < 4_000_000) @(negedge clk);
        $display("EES_P13_ERR WATCHDOG expiry cyc=%0d", cyc);
        $finish;
    end

    integer errors_a;
    initial begin
        cyc = 0; checks = 0; errors = 0;
        beats_acc = 0; y_word_cnt = 0;
        collect_en = 0; tile_sig = 0; sw_q = 0; exp_n = 0;

        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_ld_b0.hex", ld_b0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_ld_b8.hex", ld_b8);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_slots_b0.hex", slot_b0);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_slots_b8.hex", slot_b8);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_pctl.hex", pctl_w);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_p1_3_run03_mask_tlast_sim/p13_lut.hex", lut_b);

        rstn = 1'b0;
        repeat (16) @(negedge clk);
        rstn = 1'b1;
        gapn(16);

        // ---- 初始化（§10.1）：ID + LUT 256 ----
        axi_read(A_ID, rd);
        if (rd != 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_P13_ERR ID=%08x", rd);
        end else checks = checks + 1;
        for (bi = 0; bi < 256; bi = bi + 1)
            axi_write(A_LUTD, {8'd0, bi[7:0], lut_b[bi][7:0]});
        axi_write(A_CTRL, 32'h4);            //清 sticky
        gapn(4);
        $display("EES_P13_STAGE INIT done t=%0t", $time);

        // ==== CASE_FULL：b=0 n_mask=0xFFFF（对照，现 RTL 应绿）====
        run_case(0, 16'hFFFF, 16);
        errors_a = errors;
        if (errors == 0)
            $display("EES_P13_STAGE CASE_FULL PASS t=%0t", $time);
        else
            $display("EES_P13_STAGE CASE_FULL FAIL errors=%0d t=%0t",
                     errors, $time);

        // 用例间恢复（soft_rst 清运行态，配置保留）
        axi_write(A_CTRL, 32'h2);
        gapn(8);
        axi_read(A_BRGSTAT, rd);
        if (rd != 32'd0) begin
            errors = errors + 1;
            $display("EES_P13_ERR inter-case BRGSTAT=%08x", rd);
        end

        // ==== CASE_MASK：b=8 n_mask=0x000F（缺陷块）====
        run_case(1, 16'h000F, 4);
        if (errors == errors_a)
            $display("EES_P13_STAGE CASE_MASK PASS t=%0t", $time);
        else
            $display("EES_P13_STAGE CASE_MASK FAIL errors+%0d t=%0t",
                     errors - errors_a, $time);

        $display("EES_P13_MASK_RESULT %s errors=%0d checks=%0d beats=%0d ywords=%0d cyc=%0d",
                 (errors == 0) ? "PASS" : "FAIL", errors, checks,
                 beats_acc, y_word_cnt, cyc);
        $finish;
    end
endmodule
