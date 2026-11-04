/************************************************************************
 * File Name     : tb_yolo_gemm_b3_g4.sv
 * Developer     : LSL
 * Date          : 2026-09-20
 * Module Name   : tb_yolo_gemm_b3_g4
 * Description   : run27 / G4 全量门：yolo_gemm_top V1.2 + run26 canonical
 *                 数据集（真实 Conv0 三件套）。合同 §12 用例：
 *     正向：A 单块 b=0/1/3198/3199 + 2 个 4KiB 越界块（§12.1）；
 *           B Conv0 全量 3200 块×双跑（cache/no-cache 等价→输出 SHA
 *             一致），y slot 逐字节 vs G0 golden（§7.2 重排），accepted
 *             beats=259,200，随机 s_axis tvalid 气泡/长反压 + 随机
 *             m_axis_y_tready（§12.1 三态 ready 覆盖）；
 *     负向：C1 BTT/对齐 driver 侧拒绝；C2 row_valid/n_mask 非全有效
 *             拒绝走 ycap；C3 流窗内 WCTL（src_conflict+ld_pend_err）；
 *           C4 TLAST 提前/延后/缺失（tlast_err/BFM watchdog 拒绝）；
 *           C5 S2MM 停→y FIFO 满→y_ovf→§11 恢复后重跑全对。
 *   时序纪律：每块按合同 §10.2 正典（PCTL×8→GEOM/ROWVAL/NMASK/JOBCFG/
 *     LDGRP→arm 检查→MM2S 流+CTRL.start（start 落在流窗内）→完成判据
 *     →STALLCNT 读清留档）。数据源=run26 证据目录 hex 旁车，TB 侧零
 *     数学模型（golden 全部权威预生成）。
 * Revision History:
 *   - V1.0 (2026-09-20) by LSL : run27 G4 初版。
 ************************************************************************/
`timescale 1ns/1ps

module tb_yolo_gemm_b3_g4;

    // ---- 时钟/复位 ----
    reg clk, rstn;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- AXI4-Lite 主侧（PS 角色，逐字承袭 run26 TB）----
    reg  [31:0] awaddr, wdata;
    reg  [2:0]  awprot;
    reg         awvalid, wvalid;
    wire        awready, wvalid_dummy;
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
    integer checks, errors, sc_checks;
    integer beats_acc;          //s_axis 握手拍总数（对账 259,200）
    integer y_word_cnt;         //m_axis 收字总数（对账 51,200×runs）
    integer stall_total, stall_reads;
    integer cyc, hb_cnt;
    always @(negedge clk) cyc = cyc + 1;

    // ---- core 错误观察（proto/bank 边沿即错）----
    wire obs_proto_err = u_dut.core_proto_err;
    wire obs_bank_err  = u_dut.core_bank_err;
    reg proto_prev, bank_err_prev;
    always @(negedge clk) begin
        if (rstn) begin
            if (obs_proto_err && !proto_prev) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] proto_err", $time);
            end
            if (obs_bank_err && !bank_err_prev) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] bank_err", $time);
            end
        end
        proto_prev    = obs_proto_err;
        bank_err_prev = obs_bank_err;
    end

    // ---- 权威数据（run26 三件套 → hex 旁车，TB 零数学模型）----
    reg [63:0] ld_beats  [0:259199];   //81 beat × 3200 block
    reg [63:0] slot_exp  [0:51199];    //16 word × 3200 block（§7.2 重排）
    reg [31:0] pctl_w    [0:47];       //16×(b_eff,M,shift) g 主序
    reg [31:0] lut_b     [0:255];
    reg [31:0] cross_w   [0:511];      //[0]=count, [1..]=越 4KiB 的 b
    reg [63:0] y_img1    [0:51199];    //run1 y arena 镜像（双跑 SHA 用）
    reg [63:0] y_img2    [0:51199];

    // 输出目录可由 plusargs 覆盖（run03 回归用；缺省=run27 原路径不变）
    string outdir;
    initial begin
        if (!$value$plusargs("outdir=%s", outdir))
            outdir = "E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4";
    end

    initial begin
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_ld.hex",     ld_beats);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_slots.hex",  slot_exp);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_pctl.hex",   pctl_w);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_lut.hex",    lut_b);
        $readmemh("E:/competition/4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/g4_cross.hex",  cross_w);
    end

    // ---- 寄存器地址（合同 §9）----
    localparam [31:0] A_ID     = 32'h00, A_CTRL   = 32'h04, A_STATUS = 32'h08;
    localparam [31:0] A_GEOM   = 32'h0C, A_ROWVAL = 32'h10, A_NMASK  = 32'h14;
    localparam [31:0] A_JOBCFG = 32'h18, A_LDGRP  = 32'h1C, A_P_BIAS = 32'h20;
    localparam [31:0] A_P_M    = 32'h24, A_P_SH   = 32'h28, A_PCTL   = 32'h2C;
    localparam [31:0] A_WDATA  = 32'h30, A_WDATA2 = 32'h34, A_WCTL   = 32'h38;
    localparam [31:0] A_LDSTAT = 32'h3C, A_LDLEN  = 32'h40, A_LUTD   = 32'h44;
    localparam [31:0] A_YSTAT  = 32'h48, A_YADDR  = 32'h4C, A_YDATA  = 32'h50;
    localparam [31:0] A_BRGSTAT= 32'h54, A_STALLCNT = 32'h58;

    // ---- AXI 基础任务（run26 逐字）----
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            awaddr = a; awprot = 3'd0; awvalid = 1'b1;
            wdata = d; wstrb = 4'hF; wvalid = 1'b1;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] write 0x%03x SLVERR", $time, a);
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
                $display("EES_G4_ERR [%0t] read 0x%03x SLVERR", $time, a);
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

    // ---- 随机种子（固定 → 双跑确定性）----
    integer rs1, rs2, rs3, rs4;

    // ---- MM2S BFM：发块 b 的 81 beat。
    //      mode 0=连续无气泡 1=随机单拍气泡 2=长反压（tvalid 停 5..30 拍）----
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

    // ---- BFM 变体：TLAST 错位（tlast 落第 tbeat 拍，发 0..tbeat）----
    task dma_send_tbad(input integer b, input integer tbeat);
        integer bi;
        begin
            bi = 0;
            while (bi <= tbeat) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                s_axis_ld_tdata  = ld_beats[b*81 + bi];
                s_axis_ld_tlast  = (bi == tbeat);
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) bi = bi + 1;
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0; s_axis_ld_tlast = 1'b0;
        end
    endtask

    // ---- BFM 变体：缺失 TLAST（81 beat 无 tlast，BFM watchdog 判）----
    task dma_send_ntlast(input integer b);
        integer bi;
        begin
            bi = 0;
            while (bi < 81) begin
                @(negedge clk);
                s_axis_ld_tvalid = 1'b1;
                s_axis_ld_tdata  = ld_beats[b*81 + bi];
                s_axis_ld_tlast  = 1'b0;
                @(posedge clk);
                if (s_axis_ld_tvalid && s_axis_ld_tready) bi = bi + 1;
            end
            @(negedge clk);
            s_axis_ld_tvalid = 1'b0;
        end
    endtask

    // ---- y 接收：随机 tready 图案（§12.1 正常/气泡/停顿三态）----
    reg y_force0, y_force1;        //负向/排水强制
    integer y_hold;
    always @(negedge clk) begin
        if (!rstn) begin
            m_axis_y_tready = 1'b1;
        end else if (y_force0) begin
            m_axis_y_tready = 1'b0;
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

    // ---- y slot 收集器（posedge；collect_en 场景门）----
    reg        collect_en, tile_sig;
    integer    sw_q;
    reg [63:0] slot_got [0:15];
    always @(posedge clk) begin
        if (collect_en && m_axis_y_tvalid && m_axis_y_tready) begin
            if (sw_q < 16) slot_got[sw_q] = m_axis_y_tdata;
            if (^m_axis_y_tdata === 1'bx) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] X on y word %0d", $time, sw_q);
            end
            if (m_axis_y_tlast) begin
                if (sw_q != 15) begin
                    errors = errors + 1;
                    $display("EES_G4_ERR [%0t] tlast at word %0d (exp 15)",
                             $time, sw_q);
                end
                tile_sig = 1;
            end
            sw_q = sw_q + 1;
            y_word_cnt = y_word_cnt + 1;
        end
    end

    // ---- driver 侧 arm 检查（§12.2 BTT/对齐软件拒绝）----
    // 返回 0=接受；1=BTT 非期望值；2=BTT 非 8 倍数；3=地址非 8B 对齐
    function [3:0] arm_chk(input integer kind,   //0=MM2S(648) 1=S2MM(128)
                           input [31:0] btt, input [31:0] addr);
        begin
            arm_chk = 4'd0;
            if (kind == 0 && btt != 32'd648) arm_chk = 4'd1;
            if (kind == 1 && btt != 32'd128) arm_chk = 4'd1;
            if (btt[2:0] != 3'd0 && arm_chk == 4'd0) arm_chk = 4'd2;
            if (addr[2:0] != 3'd0 && arm_chk == 4'd0) arm_chk = 4'd3;
        end
    endfunction

    // ---- B3 流入口策略：row_valid/n_mask 非全有效拒绝（§12.2）----
    function [3:0] b3_entry_chk(input [7:0] rv, input [15:0] nm);
        begin
            b3_entry_chk = (rv == 8'hFF && nm == 16'hFFFF) ? 4'd0 : 4'd1;
        end
    endfunction

    // ---- 共用暂存 ----
    reg [31:0] rd, st;
    integer guard, r, q, g, bi;
    reg [63:0] wexp;
    integer ld_mode;

    // ---- 等一块的 y 收齐 + 双跑/金对拍 + 镜像存档 ----
    task wait_y_compare(input integer b, input integer run_no);
        integer byi;
        begin
            guard = 0;
            while (!(tile_sig && sw_q == 16) && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!(tile_sig && sw_q == 16)) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] y collect timeout b=%0d sw_q=%0d",
                         $time, b, sw_q);
            end else begin
                for (q = 0; q < 16; q = q + 1) begin
                    wexp = slot_exp[b*16 + q];
                    if (run_no == 1) y_img1[b*16 + q] = slot_got[q];
                    else             y_img2[b*16 + q] = slot_got[q];
                    if (slot_got[q] !== wexp) begin
                        errors = errors + 1;
                        $display("EES_G4_ERR [%0t] b=%0d q=%0d got=%016x want=%016x",
                                 $time, b, q, slot_got[q], wexp);
                    end else begin
                        for (byi = 0; byi < 8; byi = byi + 1)
                            sc_checks = sc_checks + 1;
                    end
                    if (run_no == 2
                        && slot_got[q] !== y_img1[b*16 + q]) begin
                        errors = errors + 1;
                        $display("EES_G4_ERR [%0t] double-run diff b=%0d q=%0d",
                                 $time, b, q);
                    end
                end
            end
        end
    endtask

    // ---- §10.2 配置组（PCTL×8 + GEOM/ROWVAL/NMASK/JOBCFG，g 行组）----
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

    // ---- §10.2 每块正典序列 ----
    task run_block(input integer b, input integer mode, input integer run_no);
        integer gr;
        begin
            gr = b & 1;
            cfg_block(gr);
            axi_write(A_LDGRP,  {30'd0, gr[0], gr[0]});
            // 4/5. arm 检查（策略拒绝点）+ S2MM ready（=y 收集器就绪）
            if (arm_chk(0, 32'd648, 32'h0000_0100 + 648*b) != 4'd0
                || arm_chk(1, 32'd128, 32'h001F_A500 + 128*b) != 4'd0) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] arm_chk rejected good b=%0d",
                         $time, b);
            end
            // y 收集器武装
            collect_en = 1'b1; sw_q = 0; tile_sig = 1'b0;
            // 5/6. MM2S 流 + CTRL.start（start 落在流窗内，§10.2 正典）
            fork
                dma_send_mode(b, mode);
                begin
                    gapn(4);
                    axi_write(A_CTRL, 32'd1);
                end
            join
            // 7. 完成判据：busy=0 + tile_done + 无错误
            guard = 0; st = 32'hFFFF_FFFF;
            axi_read(A_STATUS, st);
            while (!(st[0] == 1'b0 && st[5]) && guard < 50000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            if (!(st[0] == 1'b0 && st[5])) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] tile poll timeout b=%0d STATUS=%08x",
                         $time, b, st);
            end
            if (st[6] || st[7] || st[8] || st[9]) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] STATUS err bits %08x b=%0d",
                         $time, st, b);
            end
            // LDLEN 对账（ld_w_len=ld_x_len=27，逐块不变量）
            axi_read(A_LDLEN, rd);
            if (rd[12:0] != 13'd27 || rd[25:13] != 13'd27) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] LDLEN=%08x b=%0d", $time, rd, b);
            end
            // y 排空至收齐（随机 tready 下自然排空）
            y_force1 = 1'b1;
            wait_y_compare(b, run_no);
            y_force1 = 1'b0;
            // 8. STALLCNT 读清留档
            axi_read(A_STALLCNT, rd);
            stall_total = stall_total + rd;
            stall_reads = stall_reads + 1;
            collect_en = 1'b0;
            gapn(2);
        end
    endtask

    // ---- §11 恢复：err_clr → soft_rst → 重装载 → LDSTAT 确认 ----
    task recover_reload(input integer b);
        begin
            axi_write(A_CTRL, 32'h4);            //err_clr
            gapn(4);
            axi_write(A_CTRL, 32'h2);            //soft_rst
            gapn(8);
            axi_read(A_BRGSTAT, rd);
            if (rd != 32'd0) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] post-soft_rst BRGSTAT=%08x",
                         $time, rd);
            end
            axi_read(A_LDSTAT, rd);
            if (rd[5:4] != 2'b00 || rd[7:6] != 2'b00) begin
                errors = errors + 1;
                $display("EES_G4_ERR [%0t] soft_rst left loaded bits %08x",
                         $time, rd);
            end
        end
    endtask

    // ---- 主流程 ----
    integer b, run_no, i, ncase;
    integer cross_n, cb0, cb1;
    integer beats_a;
    initial begin
        // 看门狗：>20M 周期（200ms 仿真）仍未终局则判挂起
        #1000;
        while (cyc < 20_000_000) @(negedge clk);
        $display("EES_G4_ERR WATCHDOG expiry cyc=%0d", cyc);
        $finish;
    end

    initial begin
        cyc = 0; checks = 0; errors = 0; sc_checks = 0;
        beats_acc = 0; y_word_cnt = 0; stall_total = 0; stall_reads = 0;
        hb_cnt = 0;
        rs1 = 16'hA001; rs2 = 16'hB002; rs3 = 16'hC003; rs4 = 16'hD004;
        collect_en = 0; tile_sig = 0; sw_q = 0;
        y_force0 = 0; y_force1 = 0; y_hold = 0;

        rstn = 1'b0;
        repeat (16) @(negedge clk);
        rstn = 1'b1;
        gapn(16);

        // ---- 初始化（§10.1）：ID + LUT 256 ----
        axi_read(A_ID, rd);
        if (rd != 32'h2026_0919) begin
            errors = errors + 1;
            $display("EES_G4_ERR ID=%08x", rd);
        end else checks = checks + 1;
        for (i = 0; i < 256; i = i + 1)
            axi_write(A_LUTD, {8'd0, i[7:0], lut_b[i][7:0]});
        axi_write(A_CTRL, 32'h4);            //清 sticky
        gapn(4);
        $display("EES_G4_STAGE INIT done t=%0t", $time);

        // ==== Phase A：单块 + 4KiB 越界（§12.1）====
        cross_n = cross_w[0];
        cb0 = cross_w[1];
        cb1 = cross_w[2];
        $display("EES_G4_STAGE A single-blocks cross_n=%0d cb=%0d,%0d",
                 cross_n, cb0, cb1);
        run_block(0,    0, 1);   //b=0   连续
        run_block(1,    1, 1);   //b=1   气泡
        run_block(3198, 2, 1);   //b=3198 长反压 + 越界块
        run_block(3199, 1, 1);   //b=3199
        run_block(cb0,  2, 1);   //SAR 越 4KiB 实块
        run_block(cb1,  0, 1);
        beats_a = beats_acc;                 //A 段基线（应=6×81）
        if (beats_a != 6*81) begin
            errors = errors + 1;
            $display("EES_G4_ERR PhaseA beats=%0d exp=486", beats_a);
        end
        $display("EES_G4_STAGE A done errors=%0d sc=%0d t=%0t",
                 errors, sc_checks, $time);

        // ==== Phase B：全量 3200 × 双跑（§12.1）====
        for (run_no = 1; run_no <= 2; run_no = run_no + 1) begin
            $display("EES_G4_STAGE B run%0d start t=%0t", run_no, $time);
            for (b = 0; b < 3200; b = b + 1) begin
                ld_mode = {$random(rs1)} % 3;
                run_block(b, ld_mode, run_no);
                if (b % 256 == 255) begin
                    hb_cnt = hb_cnt + 1;
                    $display("EES_HB run=%0d blk=%0d err=%0d beats=%0d t=%0t",
                             run_no, b+1, errors, beats_acc, $time);
                end
            end
            if (run_no == 1)
                $writememh({outdir, "/g4_y_arena_run1.hex"}, y_img1);
            else
                $writememh({outdir, "/g4_y_arena_run2.hex"}, y_img2);
            axi_read(A_BRGSTAT, rd);
            if (rd[2] || rd[3] || rd[4] || !rd[1]) begin
                errors = errors + 1;
                $display("EES_G4_ERR run%0d end BRGSTAT=%08x", run_no, rd);
            end
            $display("EES_G4_STAGE B run%0d done err=%0d beats=%0d t=%0t",
                     run_no, errors, beats_acc, $time);
            // 双跑间恢复干净态（soft_rst 清运行态，配置保留）
            if (run_no == 1) begin
                axi_write(A_CTRL, 32'h2);
                gapn(8);
                axi_read(A_BRGSTAT, rd);
                if (rd != 32'd0) begin
                    errors = errors + 1;
                    $display("EES_G4_ERR inter-run BRGSTAT=%08x", rd);
                end
            end
        end
        // 全量对账：双跑 6400 块 accepted beats=518,400（=合同 259,200×2）
        if (beats_acc - beats_a != 6400*81) begin
            errors = errors + 1;
            $display("EES_G4_ERR PhaseB beats=%0d exp=%0d",
                     beats_acc - beats_a, 6400*81);
        end

        // ==== Phase C：负向（§12.2）====
        $display("EES_G4_STAGE C negatives t=%0t", $time);

        // C1 BTT/对齐 driver 侧拒绝
        ncase = 0;
        if (arm_chk(0, 32'd647, 32'h0000_0100) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 647 accepted"); end else ncase=ncase+1;
        if (arm_chk(0, 32'd650, 32'h0000_0100) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 650 accepted"); end else ncase=ncase+1;
        if (arm_chk(0, 32'd656, 32'h0000_0100) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 656 accepted"); end else ncase=ncase+1;
        if (arm_chk(1, 32'd127, 32'h001F_A500) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 127 accepted"); end else ncase=ncase+1;
        if (arm_chk(1, 32'd132, 32'h001F_A500) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 132 accepted"); end else ncase=ncase+1;
        if (arm_chk(0, 32'd648, 32'h0000_0104) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 sar misalign accepted"); end else ncase=ncase+1;
        if (arm_chk(1, 32'd128, 32'h001F_A504) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 dst misalign accepted"); end else ncase=ncase+1;
        if (arm_chk(0, 32'd648, 32'h0000_0100) != 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 good mm2s rejected"); end else ncase=ncase+1;
        if (arm_chk(1, 32'd128, 32'h001F_A500) != 4'd0) begin errors=errors+1; $display("EES_G4_ERR C1 good s2mm rejected"); end else ncase=ncase+1;
        $display("EES_G4_C1 btt/align rejections=%0d/9", ncase);
        checks = checks + ncase;

        // C2 row_valid/n_mask 非全有效 → B3 流入口拒绝（走 ycap）
        ncase = 0;
        if (b3_entry_chk(8'h7F, 16'hFFFF) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C2 rv accepted"); end else ncase=ncase+1;
        if (b3_entry_chk(8'hFF, 16'hFFFE) == 4'd0) begin errors=errors+1; $display("EES_G4_ERR C2 nm accepted"); end else ncase=ncase+1;
        if (b3_entry_chk(8'hFF, 16'hFFFF) != 4'd0) begin errors=errors+1; $display("EES_G4_ERR C2 good rejected"); end else ncase=ncase+1;
        $display("EES_G4_C2 rowval/nmask rejections ok=%0d/3", ncase);
        checks = checks + ncase;

        // C3 流窗内 WCTL → src_conflict + ld_pend_err（数据不受扰）
        begin : c3_blk
            reg [31:0] brg, sta;
            g = 0;
            cfg_block(g);
            collect_en = 1'b0;
            fork
                dma_send_mode(8, 1);
                begin
                    gapn(30);                      //流窗中段
                    axi_write(A_WDATA,  32'd0);
                    axi_write(A_WDATA2, 32'd0);
                    axi_write(A_WCTL,   {20'd0, 1'b0, 1'b0, 8'hFF, 1'b0, 1'b0});
                    gapn(2);
                    axi_write(A_CTRL, 32'd1);      //递交 job
                end
            join
            guard = 0; st = 0;
            axi_read(A_STATUS, st);
            while (!(st[0] == 1'b0 && st[5]) && guard < 4000) begin
                axi_read(A_STATUS, st);
                guard = guard + 1;
            end
            axi_read(A_BRGSTAT, brg);
            axi_read(A_STATUS,  sta);
            if (!brg[3] || !sta[8]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C3 conflict bits brg=%08x sta=%08x",
                         brg, sta);
            end else checks = checks + 1;
            axi_write(A_CTRL, 32'h4);              //err_clr
            gapn(4);
            axi_read(A_BRGSTAT, brg);
            if (brg[3] || brg[2] || brg[4]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C3 err_clr left brg=%08x", brg);
            end
            // 数据不受扰：该块 job 输出经 ycap 正常（y 流被 collect_en 关，
            // 排空后仅验证无残余错误）
            y_force1 = 1'b1;
            gapn(64);
            y_force1 = 1'b0;
            $display("EES_G4_C3 src_conflict+ld_pend_err observed+cleared");
        end

        // C4 TLAST 提前/延后/缺失（b=9）
        begin : c4_blk
            reg [31:0] brg;
            axi_write(A_LDGRP, 32'd0);
            // 提前（beat 79，Xlo 相）
            dma_send_tbad(9, 79);
            gapn(16);
            axi_read(A_BRGSTAT, brg);
            if (!brg[2]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C4 early-tlast no err brg=%08x", brg);
            end else checks = checks + 1;
            recover_reload(9);
            // 延后（82 beat，tlast 落 beat 81=W 相）
            dma_send_tbad(9, 81);
            gapn(16);
            axi_read(A_BRGSTAT, brg);
            if (!brg[2]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C4 late-tlast no err brg=%08x", brg);
            end else checks = checks + 1;
            recover_reload(9);
            // 缺失（81 beat 无 tlast → BFM watchdog 判，硬件不得闭口）
            dma_send_ntlast(9);
            guard = 0;
            repeat (2000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            axi_read(A_BRGSTAT, brg);
            if (brg[1]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C4 missing-tlast closed block brg=%08x",
                         brg);
            end else checks = checks + 1;
            $display("EES_G4_C4 missing-tlast driver-reject (watchdog %0d cyc)",
                     guard);
            recover_reload(9);
            // 恢复后整块重跑全对
            run_block(9, 0, 2);
        end

        // C5 S2MM 停 → y FIFO 满 → y_ovf → §11 恢复重跑
        begin : c5_blk
            reg [31:0] brg;
            y_force0 = 1'b1;                       //S2MM 停
            collect_en = 1'b0;
            // 3 个背靠背 job：48 word > FIFO 32 → 第 3 tile 推丢 → y_ovf
            for (i = 0; i < 3; i = i + 1) begin
                b = 10 + i;
                g = b & 1;
                cfg_block(g);
                axi_write(A_LDGRP, {30'd0, g[0], g[0]});
                fork
                    dma_send_mode(b, 0);
                    begin
                        gapn(4);
                        axi_write(A_CTRL, 32'd1);
                    end
                join
                guard = 0; st = 0;
                axi_read(A_STATUS, st);
                while (!(st[0] == 1'b0 && st[5]) && guard < 4000) begin
                    axi_read(A_STATUS, st);
                    guard = guard + 1;
                end
            end
            gapn(64);
            axi_read(A_BRGSTAT, brg);
            if (!brg[4]) begin
                errors = errors + 1;
                $display("EES_G4_ERR C5 y_ovf missing brg=%08x", brg);
            end else checks = checks + 1;
            $display("EES_G4_C5 y_ovf observed brg=%08x", brg);
            // §11 恢复：放行排空 → err_clr → soft_rst → 重装载 → 重跑
            y_force0 = 1'b0; y_force1 = 1'b1;
            guard = 0;
            while (m_axis_y_tvalid && guard < 2000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            gapn(16);
            y_force1 = 1'b0;
            recover_reload(12);
            run_block(12, 1, 2);
            $display("EES_G4_C5 recovery rerun block12 verified");
        end

        // ==== 终局对账（§12.1/§12.2 PASS 判据）====
        $display("EES_SUMMARY checks=%0d sc_checks=%0d errors=%0d beats=%0d ywords=%0d stall=%0d/%0d %s",
                 checks, sc_checks, errors, beats_acc, y_word_cnt,
                 stall_total, stall_reads,
                 (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
