// =====================================================================
// tb_yolo_gemm_dma_top_smoke.sv — run28b 冒烟门：BD 包装层
// yolo_gemm_dma_top（纯直通，X_INTERFACE_INFO 属性版）端口级验证。
// DUT=wrapper（wrapper 内例化 V1.2 core）。流程承袭 run27 G4 TB 逐字
// 任务体（axi_write/axi_read/gapn/dma_send_mode/y 收集器/wait_y_compare/
// cfg_block/run_block），规模收缩为 INIT + 3 块（mode 0/1/2 全三种流
// 图案）+ 终态 BRGSTAT。判据：errors=0、beats=3*81=243、sc=48*8=384、
// ywords=48、STATUS 错误位零、LDLEN 双 27。
// 权威数据：run27 证据目录 hex 旁车（只读）。TB 零数学模型。
// =====================================================================
`timescale 1ns / 1ps

module tb_yolo_gemm_dma_top_smoke;

    // ---- 时钟/复位 ----
    reg clk, rstn;
    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    // ---- AXI4-Lite ----
    reg  [31:0] awaddr;
    reg  [2:0]  awprot;
    reg         awvalid;
    wire        awready, wready, bvalid;
    reg  [31:0] wdata;
    reg         wvalid;
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

    // ---- DUT：BD 包装层 ----
    yolo_gemm_dma_top u_dut (
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
    integer checks, errors, sc_checks;
    integer beats_acc;
    integer y_word_cnt;
    integer stall_total, stall_reads;
    integer cyc;
    always @(negedge clk) cyc = cyc + 1;

    // ---- core 错误观察（穿 wrapper 到 u_gemm_core，proto/bank 边沿即错）----
    wire obs_proto_err = u_dut.u_gemm_core.core_proto_err;
    wire obs_bank_err  = u_dut.u_gemm_core.core_bank_err;
    reg proto_prev, bank_err_prev;
    always @(negedge clk) begin
        if (rstn) begin
            if (obs_proto_err && !proto_prev) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] proto_err", $time);
            end
            if (obs_bank_err && !bank_err_prev) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] bank_err", $time);
            end
        end
        proto_prev    = obs_proto_err;
        bank_err_prev = obs_bank_err;
    end

    // ---- 权威数据（run27 hex 旁车，只读）----
    reg [63:0] ld_beats  [0:259199];
    reg [63:0] slot_exp  [0:51199];
    reg [31:0] pctl_w    [0:47];
    reg [31:0] lut_b     [0:255];
    reg [63:0] y_got     [0:47];      //3 块 × 16 word 存档

    initial begin
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_ld.hex",     ld_beats);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_slots.hex",  slot_exp);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_pctl.hex",   pctl_w);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_lut.hex",    lut_b);
    end

    // ---- 寄存器地址（合同 §9，与 G4 TB 逐字一致）----
    localparam [31:0] A_ID     = 32'h00, A_CTRL   = 32'h04, A_STATUS = 32'h08;
    localparam [31:0] A_GEOM   = 32'h0C, A_ROWVAL = 32'h10, A_NMASK  = 32'h14;
    localparam [31:0] A_JOBCFG = 32'h18, A_LDGRP  = 32'h1C, A_P_BIAS = 32'h20;
    localparam [31:0] A_P_M    = 32'h24, A_P_SH   = 32'h28, A_PCTL   = 32'h2C;
    localparam [31:0] A_WDATA  = 32'h30, A_WDATA2 = 32'h34, A_WCTL   = 32'h38;
    localparam [31:0] A_LDSTAT = 32'h3C, A_LDLEN  = 32'h40, A_LUTD   = 32'h44;
    localparam [31:0] A_YSTAT  = 32'h48, A_YADDR  = 32'h4C, A_YDATA  = 32'h50;
    localparam [31:0] A_BRGSTAT= 32'h54, A_STALLCNT = 32'h58;

    // ---- AXI 基础任务（G4 逐字）----
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            awaddr = a; awprot = 3'd0; awvalid = 1'b1;
            wdata = d; wstrb = 4'hF; wvalid = 1'b1;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] write 0x%03x SLVERR", $time, a);
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
                $display("EES_SMK_ERR [%0t] read 0x%03x SLVERR", $time, a);
            end
            arvalid = 1'b0;
            @(negedge clk);
        end
    endtask

    task gapn(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    // ---- 随机种子（G4 同值）----
    integer rs1, rs2, rs3, rs4;

    // ---- MM2S BFM（G4 dma_send_mode 逐字）----
    task dma_send_mode(input integer b, input integer mode);
        integer bi, hold;
        begin
            bi = 0;
            while (bi < 81) begin
                @(negedge clk);
                if (bi == 81) begin
                    s_axis_ld_tvalid = 1'b0;
                end else if (mode == 1 && bi != 0
                             && ({$random(rs3)} % 8 == 0)) begin
                    s_axis_ld_tvalid = 1'b0;            //单拍气泡
                end else if (mode == 2 && bi != 0 && bi != 80
                             && ({$random(rs2)} % 8 == 0)) begin
                    hold = 5 + ({$random(rs1)} % 26);   //长反压 5..30
                    s_axis_ld_tvalid = 1'b0;
                    while (hold > 0) begin
                        @(negedge clk);
                        hold = hold - 1;
                    end
                    s_axis_ld_tvalid = 1'b1;
                    s_axis_ld_tdata  = ld_beats[b*81 + bi];
                    s_axis_ld_tlast  = (bi == 80);
                end else begin
                    s_axis_ld_tvalid = 1'b1;
                    s_axis_ld_tdata  = ld_beats[b*81 + bi];
                    s_axis_ld_tlast  = (bi == 80);
                end
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

    // ---- y tready 图案（G4 三态随机逐字）----
    reg y_force1;
    integer y_hold;
    always @(negedge clk) begin
        if (!rstn) begin
            m_axis_y_tready = 1'b1;
        end else if (y_force1) begin
            m_axis_y_tready = 1'b1;
        end else if (y_hold > 0) begin
            m_axis_y_tready = 1'b0;
            y_hold = y_hold - 1;
        end else begin
            m_axis_y_tready = 1'b1;
            if ({$random(rs4)} % 16 == 0)
                y_hold = {$random(rs1)} % 24;          //0..23 拍停顿
        end
    end

    // ---- y slot 收集器（G4 逐字）----
    reg        collect_en, tile_sig;
    integer    sw_q;
    reg [63:0] slot_got [0:15];
    always @(posedge clk) begin
        if (collect_en && m_axis_y_tvalid && m_axis_y_tready) begin
            if (sw_q < 16) slot_got[sw_q] = m_axis_y_tdata;
            if (^m_axis_y_tdata === 1'bx) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] X on y word %0d", $time, sw_q);
            end
            if (m_axis_y_tlast) begin
                if (sw_q != 15) begin
                    errors = errors + 1;
                    $display("EES_SMK_ERR [%0t] tlast at word %0d (exp 15)",
                             $time, sw_q);
                end
                tile_sig = 1;
            end
            sw_q = sw_q + 1;
            y_word_cnt = y_word_cnt + 1;
        end
    end

    // ---- driver 侧 arm 检查（G4 逐字）----
    function [3:0] arm_chk(input integer kind,
                           input [31:0] btt, input [31:0] addr);
        begin
            arm_chk = 4'd0;
            if (kind == 0 && btt != 32'd648) arm_chk = 4'd1;
            if (kind == 1 && btt != 32'd128) arm_chk = 4'd1;
            if (btt[2:0] != 3'd0 && arm_chk == 4'd0) arm_chk = 4'd2;
            if (addr[2:0] != 3'd0 && arm_chk == 4'd0) arm_chk = 4'd3;
        end
    endfunction

    // ---- 共用暂存 ----
    reg [31:0] rd, st;
    integer guard, r, q, g, bi;
    reg [63:0] wexp;

    // ---- 等一块 y 收齐 + 金对拍（G4 单跑版）----
    task wait_y_compare(input integer b);
        begin
            guard = 0;
            while (!(tile_sig && sw_q == 16) && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!(tile_sig && sw_q == 16)) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] y collect timeout b=%0d sw_q=%0d",
                         $time, b, sw_q);
            end else begin
                for (q = 0; q < 16; q = q + 1) begin
                    wexp = slot_exp[b*16 + q];
                    y_got[b*16 + q] = slot_got[q];
                    if (slot_got[q] !== wexp) begin
                        errors = errors + 1;
                        $display("EES_SMK_ERR [%0t] b=%0d q=%0d got=%016x want=%016x",
                                 $time, b, q, slot_got[q], wexp);
                    end else begin
                        sc_checks = sc_checks + 8;
                    end
                end
            end
        end
    endtask

    // ---- §10.2 配置组（G4 逐字）----
    task cfg_block(input integer gr);
        begin
            for (r = 0; r < 8; r = r + 1) begin
                axi_write(A_P_BIAS, pctl_w[(gr*8+r)*3 + 0]);
                axi_write(A_P_M,    pctl_w[(gr*8+r)*3 + 1]);
                axi_write(A_P_SH,   pctl_w[(gr*8+r)*3 + 2]);
                axi_write(A_PCTL,   {29'd0, 1'b1, r[2:0]});
            end
            axi_write(A_GEOM,   32'd27);
            axi_write(A_ROWVAL, 32'h0000_00FF);
            axi_write(A_NMASK,  32'h0000_FFFF);
            axi_write(A_JOBCFG, {27'd0, gr[0], gr[0], 1'b1, 1'b1, 1'b1});
        end
    endtask

    // ---- §10.2 每块正典序列（G4 逐字）----
    task run_block(input integer b, input integer mode);
        integer gr;
        begin
            gr = b & 1;
            cfg_block(gr);
            axi_write(A_LDGRP,  {30'd0, gr[0], gr[0]});
            if (arm_chk(0, 32'd648, 32'h0000_0100 + 648*b) != 4'd0
                || arm_chk(1, 32'd128, 32'h001F_A500 + 128*b) != 4'd0) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] arm_chk rejected good b=%0d",
                         $time, b);
            end
            collect_en = 1'b1; sw_q = 0; tile_sig = 1'b0;
            fork
                dma_send_mode(b, mode);
                begin
                    gapn(4);
                    axi_write(A_CTRL, 32'd1);
                end
            join
            guard = 0; st = 32'hFFFF_FFFF;
            axi_read(A_STATUS, st);
            while (!(st[0] == 1'b0 && st[5]) && guard < 50000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            if (!(st[0] == 1'b0 && st[5])) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] tile poll timeout b=%0d STATUS=%08x",
                         $time, b, st);
            end
            if (st[6] || st[7] || st[8] || st[9]) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] STATUS err bits %08x b=%0d",
                         $time, st, b);
            end
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd27 || rd[25:13] != 13'd27) begin
                errors = errors + 1;
                $display("EES_SMK_ERR [%0t] LDLEN=%08x b=%0d", $time, rd, b);
            end
            y_force1 = 1'b1;
            wait_y_compare(b);
            y_force1 = 1'b0;
            axi_read(A_STALLCNT, rd);
            stall_total = stall_total + rd;
            stall_reads = stall_reads + 1;
            collect_en = 1'b0;
            gapn(2);
        end
    endtask

    // ---- 看门狗 ----
    initial begin
        #1000;
        while (cyc < 2_000_000) @(negedge clk);
        $display("EES_SMK_ERR WATCHDOG expiry cyc=%0d", cyc);
        $finish;
    end

    // ---- 主流程 ----
    integer i;
    reg pass;
    initial begin
        cyc = 0; checks = 0; errors = 0; sc_checks = 0;
        beats_acc = 0; y_word_cnt = 0; stall_total = 0; stall_reads = 0;
        rs1 = 16'hA001; rs2 = 16'hB002; rs3 = 16'hC003; rs4 = 16'hD004;
        collect_en = 0; tile_sig = 0; sw_q = 0;
        y_force1 = 0; y_hold = 0;

        rstn = 1'b0;
        repeat (16) @(negedge clk);
        rstn = 1'b1;
        gapn(16);

        // INIT（§10.1）：ID + LUT 256 + 清 sticky
        axi_read(A_ID, rd);
        if (rd != 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_SMK_ERR ID=%08x", rd);
        end else checks = checks + 1;
        for (i = 0; i < 256; i = i + 1)
            axi_write(A_LUTD, {8'd0, i[7:0], lut_b[i][7:0]});
        axi_write(A_CTRL, 32'h4);
        gapn(4);
        $display("EES_SMK_STAGE INIT done t=%0t", $time);

        // 3 块 × 3 种流图案
        run_block(0, 0);
        run_block(1, 1);
        run_block(2, 2);

        // 对账
        if (beats_acc != 243) begin
            errors = errors + 1;
            $display("EES_SMK_ERR beats=%0d exp=243", beats_acc);
        end else checks = checks + 1;
        axi_read(A_BRGSTAT, rd);
        if (rd[2] || rd[3] || rd[4] || !rd[1]) begin
            errors = errors + 1;
            $display("EES_SMK_ERR end BRGSTAT=%08x", rd);
        end else checks = checks + 1;

        $writememh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run28b_newproj/smoke_y_slots.hex", y_got);

        pass = (errors == 0 && beats_acc == 243 && sc_checks == 384
                && y_word_cnt == 48);
        $display("EES_SMOKE_SUMMARY checks=%0d sc_checks=%0d errors=%0d beats=%0d ywords=%0d stall=%0d/%0d %s",
                 checks, sc_checks, errors, beats_acc, y_word_cnt,
                 stall_total, stall_reads, pass ? "PASS" : "FAIL");
        $finish;
    end

endmodule
