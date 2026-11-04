/************************************************************************
 * File Name       : tb_ppu_shell.sv
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_ppu_shell
 * Description     : PPU-F3 单描述符 shell 门仿真 TB。
 *   RUN=A：装载门 104/104（14 XFER 拓扑金样逐拍比对 + 16 view 零
 *          流量 + 74 非搬运算子 validate-only；desc103=last 唯一发环）。
 *   RUN=B1：19 例装载负例（L1..L19，步/位/码逐例精确 + 零 AXI 流量
 *          + 无 desc_done），例间复位。L19=V1.3 容量上界（9B>8B）。
 *   RUN=B2：S1/S2 合成 XFER + S4 容量边界正例（8B/8B，V1.3）+
 *          DMA 故障 D1(RRESP)/D2(BRESP)/
 *          D3(timeout)/D4(W 背压)/D5(在途复位) + 事件 E1(abort)/
 *          E2(stop+last→发环)/E3(ffe 强发环)。
 *   RUN=F4：图级子图（2026-09-22）：5 RTL XFER 连续派发，真软件张量
 *          金样（f4_prep.py）：SG1 Concat→Conv(软)→Concat（desc20/59）、
 *          SG2 Upsample→Concat（desc50）、SG3 Conv→Concat（desc47）、
 *          SG4 heads（desc103，149100B，identity 六段）。
 *   RUN=F5A：Upsample2 单描述符门（2026-09-22，ppu_ups_engine 首跑）：
 *          正典 desc49/58（真张量）+ 合成 desc108/109/110（非方/极小），
 *          零发环；金样=f5_prep.py。
 *   RUN=F5B：Upsample2×XFER 相邻 3 task 子图门（2026-09-22）：两尺度
 *          SG-A{49 UPS→50 XFER}/SG-B{58 UPS→59 XFER}，UPS 出 buf 不预载
 *          ——本 run 内 RTL 写→XFER 读回（BFM 写贯通），证引擎间经 DDR
 *          真实邻接；金样=f5b_prep.py。
 *   RUN=F5C：三尺度 neck 子图门（2026-09-22）：8 RTL 任务连发（4 上游
 *          CAT+2 UPS+2 下游 CAT，40×40/20×20/10×10）；金样=f5c_prep.py。
 *   RUN=F5D：全帧整网回放门（2026-09-22）：16 数据面 PPU 任务（13 CAT+
 *          2 UPS+HEADS，升序=拓扑序）× 5 帧（语料全集）连发；帧间**不复
 *          位**（preload_f{k} 重载=同址全量覆盖，兼证跨帧无状态泄漏）；
 *          金样=f5d_prep.py（rd/wr_golden_f{k}_{di} 帧参数化）。
 *   RUN=F5MA：MaxPool5 单描述符门（2026-09-22，ppu_mp5_engine 首跑）：
 *          正典 desc44（SPPF 首环真张量，in==out 同形）+ 合成
 *          desc111/112/113（全-128/边角 H<5/极小 (1,1,1)）；金样=f5m_prep.py。
 *   RUN=F5MD：MaxPool5 全帧整网回放门（2026-09-22）：19 数据面 PPU 任务
 *          （13 CAT+3 MP5+2 UPS+HEADS，升序=拓扑序）× 5 帧（语料全集）
 *          连发；帧间**不复位**；金样=f5md_prep.py（帧参数化）。
 *          （F5MB=SPPF 四任务子图、F5MC=三尺度 neck 11 任务门，见
 *          run_f5m_b/run_f5m_c 注释与各证据目录 STATUS。）
 *   RUN=F5AA：Add 单描述符门（2026-09-22，ppu_add_engine 首跑）：正典
 *          desc7（真张量真 profile 双 requant）+ 合成 desc124..127（恒等
 *          m=2^30/s=30 / 平局 m=2^30/s=31 全奇字节 tie / 非对称饱和
 *          s0=23+s1=0 旁路 / 极小 (1,1,1) 尾拍），quant 槽 200..202 splice；
 *          rd 金样=64B 块 A/B 交替流（引擎读序确定，金样同序生成）；
 *          金样=f5aa_prep.py。
 *   RUN=F5AB：Add 相邻 3 task 子图门（2026-09-22）：双链 {16,19,20}+
 *          {28,31,32}（ADD→ADD→CAT），链内 ADD 出 buf17/buf29 不预载
 *          ——RTL 写→后继读回（DDR 往返）；金样=f5ab_prep.py。
 *   RUN=F5AC：Add 多任务混合门（2026-09-22）：6 ADD+其消费 CAT 共 10 任务
 *          连发（7,8,16,19,20,28,31,32,40,41 拓扑序）；金样=f5ac_prep.py。
 *   RUN=F5AD：Add 全帧整网回放门（2026-09-22）：25 数据面 PPU 任务
 *          （13 CAT+6 ADD+3 MP5+2 UPS+HEADS=全部，升序=拓扑序）× 5 帧
 *          （语料全集）连发；帧间**不复位**；金样=f5ad_prep.py（帧参数化）。
 *   数据/金样全部来自 prep 工件（+PREP 目录），TB 不自造期望。
 *   marker：EES_SUMMARY + EES_MODELSIM_RESULT（正典）。
 * Dependencies    : ppu_shell_top + ppu_axi_bfm + prep 工件。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-22) by LSL : F5A 任务（run_f5a；Upsample2 门）。
 *   - V1.2 (2026-09-22) by LSL : F5B 任务（run_f5b；UPS→XFER 邻接门）。
 *   - V1.3 (2026-09-22) by LSL : F5C 任务（run_f5c；三尺度 neck 门）。
 *   - V1.4 (2026-09-22) by LSL : F5D 任务（run_f5d；全帧整网回放门；
 *          cmp_golden 增帧参 fr<0 时不带 _f{k} 后缀，旧调用不变）。
 *   - V1.5 (2026-09-22) by LSL : F5M-A 任务（run_f5m_a；MaxPool5
 *          单描述符门，ppu_mp5_engine 首跑）。
 *   - V1.6 (2026-09-22) by LSL : F5M-B 任务（run_f5m_b；SPPF 四任务
 *          子图门：3xMP5 RTL→RTL 链 + CAT XFER 邻接）。
 *   - V1.7 (2026-09-22) by LSL : F5M-C 任务（run_f5m_c；三尺度 neck
 *          11 任务门：6 CAT+3 MP5+2 UPS 混合连发）。
 *   - V1.8 (2026-09-22) by LSL : F5M-D 任务（run_f5m_d；MaxPool5 全帧
 *          整网回放门：19 任务/帧 × 5 帧无复位连发）。
 *   - V1.9 (2026-09-22) by LSL : F5A 类梯四任务（run_f5aa_a..d；Add
 *          单描述符/相邻子图/多任务混合/全帧 25 任务×5 帧整网回放）。
 *   - V1.10 (2026-09-24) by LSL : xsim 同拍读回竞态修复——
 *          wait_desc_done 观测拍后多等一拍再返回（任务线程在 xsim
 *          调度序下先于事件计数监视块执行，F5M-D 发环检查读数落后
 *          一事件；A 核判别测证与被测核无关，见 f7tmg_run01/
 *          gate_f5md_a；ModelSim 基线不受影响）。
 ************************************************************************/

`timescale 1ns/1ps

module tb_ppu_shell;

    // ---- 时钟/激励 ----
    reg clk_r, rst_r;
    reg         req_r;
    reg  [6:0]  desc_idx_r;
    reg  [31:0] head_base_r;
    reg         stop_r, abort_r, ffe_r;
    reg  [23:0] tmo_cfg_r;
    reg  [2:0]  rd_os_r, wr_os_r;

    // ---- DUT 接线 ----
    wire [11:0] desc_addr_w;
    wire [31:0] desc_din_w;
    wire [9:0]  buf_addr_w, qt_addr_w;
    wire [31:0] buf_din_w, qt_din_w;

    wire [31:0] araddr_w; wire [3:0] arlen_w; wire [2:0] arsize_w;
    wire [1:0]  arburst_w; wire arvalid_w; wire arready_w;
    wire [63:0] rdata_w; wire [1:0] rresp_w; wire rlast_w;
    wire rvalid_w, rready_w;
    wire [31:0] awaddr_w; wire [3:0] awlen_w; wire [2:0] awsize_w;
    wire [1:0]  awburst_w; wire awvalid_w; wire awready_w;
    wire [63:0] wdata_w; wire [7:0] wstrb_w;
    wire wlast_w, wvalid_w, wready_w;
    wire [1:0] bresp_w; wire bvalid_w, bready_w;

    wire        busy_w, desc_done_w, ring_pub_w, stopped_w;
    wire [2:0]  cause_w;
    wire        ldr_ev_w, dma_ev_w, dma_halt_w, eng_busy_w;
    wire [3:0]  ldr_step_w, ldr_bit_w, dma_bit_w;
    wire [7:0]  ldr_code_w;

    // ---- BFM 配置 ----
    integer cfg_r_lat, cfg_fault_r_beat, cfg_stall_after;
    reg [1:0] cfg_fault_r_resp;
    integer cfg_fault_b_req, cfg_b_delay, cfg_w_stall;
    reg cfg_check_en;

    ppu_shell_top dut (
        .clk_i(clk_r), .rst_i(rst_r),
        .req_i(req_r), .desc_idx_i(desc_idx_r),
        .head_base_i(head_base_r),
        .stop_i(stop_r), .abort_i(abort_r), .ffe_i(ffe_r),
        .timeout_cfg_i(tmo_cfg_r),
        .rd_outst_cfg_i(rd_os_r), .wr_outst_cfg_i(wr_os_r),
        .desc_addr_o(desc_addr_w), .desc_din_i(desc_din_w),
        .buf_addr_o(buf_addr_w),   .buf_din_i(buf_din_w),
        .qt_addr_o(qt_addr_w),     .qt_din_i(qt_din_w),
        .araddr_o(araddr_w), .arlen_o(arlen_w),
        .arsize_o(arsize_w), .arburst_o(arburst_w),
        .arvalid_o(arvalid_w), .arready_i(arready_w),
        .rdata_i(rdata_w), .rresp_i(rresp_w),
        .rlast_i(rlast_w), .rvalid_i(rvalid_w), .rready_o(rready_w),
        .awaddr_o(awaddr_w), .awlen_o(awlen_w),
        .awsize_o(awsize_w), .awburst_o(awburst_w),
        .awvalid_o(awvalid_w), .awready_i(awready_w),
        .wdata_o(wdata_w), .wstrb_o(wstrb_w),
        .wlast_o(wlast_w), .wvalid_o(wvalid_w), .wready_i(wready_w),
        .bresp_i(bresp_w), .bvalid_i(bvalid_w), .bready_o(bready_w),
        .busy_o(busy_w),
        .desc_done_o(desc_done_w), .ring_publish_o(ring_pub_w),
        .done_cause_o(cause_w), .stopped_o(stopped_w),
        .ldr_err_valid_o(ldr_ev_w), .ldr_err_step_o(ldr_step_w),
        .ldr_err_bit_o(ldr_bit_w), .ldr_err_code_o(ldr_code_w),
        .dma_err_valid_o(dma_ev_w), .dma_err_bit_o(dma_bit_w),
        .dma_halted_o(dma_halt_w), .eng_busy_o(eng_busy_w)
    );

    wire [63:0] bfm_rd_cnt, bfm_wr_cnt;    // BFM 口为 longint：4 态网可接
    integer bfm_proto_err, bfm_unloaded;

    ppu_axi_bfm bfm (
        .clk_i(clk_r), .rst_i(rst_r),
        .arvalid_i(arvalid_w), .arready_o(arready_w),
        .araddr_i(araddr_w), .arlen_i(arlen_w),
        .rvalid_o(rvalid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w), .rready_i(rready_w),
        .awvalid_i(awvalid_w), .awready_o(awready_w),
        .awaddr_i(awaddr_w), .awlen_i(awlen_w),
        .wvalid_i(wvalid_w), .wready_o(wready_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w), .wlast_i(wlast_w),
        .bvalid_o(bvalid_w), .bresp_o(bresp_w), .bready_i(bready_w),
        .cfg_r_lat(cfg_r_lat), .cfg_fault_r_beat(cfg_fault_r_beat),
        .cfg_fault_r_resp(cfg_fault_r_resp),
        .cfg_stall_after(cfg_stall_after),
        .cfg_fault_b_req(cfg_fault_b_req), .cfg_b_delay(cfg_b_delay),
        .cfg_w_stall(cfg_w_stall), .cfg_check_en(cfg_check_en),
        .rd_cnt(bfm_rd_cnt), .wr_cnt(bfm_wr_cnt),
        .proto_err(bfm_proto_err), .unloaded_cnt(bfm_unloaded)
    );

    // ---- 表 ROM（1 拍同步读：addr k → din k+1，desc_if 合同）----
    reg [31:0] desc_rom [0:4095];
    reg [31:0] buf_rom  [0:1023];
    reg [31:0] qt_rom   [0:1023];
    reg [31:0] desc_din_r, buf_din_r, qt_din_r;
    always @(posedge clk_r) begin
        desc_din_r <= desc_rom[desc_addr_w];
        buf_din_r  <= buf_rom [buf_addr_w];
        qt_din_r   <= qt_rom  [qt_addr_w];
    end
    assign desc_din_w = desc_din_r;
    assign buf_din_w  = buf_din_r;
    assign qt_din_w   = qt_din_r;

    // ---- 事件计数 ----
    integer ring_cnt, done_cnt, errors, checks;

    always @(posedge clk_r) begin
        if (!rst_r) begin
            if (ring_pub_w) ring_cnt = ring_cnt + 1;
            if (desc_done_w) done_cnt = done_cnt + 1;
        end
    end

    initial begin clk_r = 1'b0; forever #5 clk_r = ~clk_r; end

    string prep_dir, run_s;

    task automatic fail(string s);
        begin
            errors = errors + 1;
            $display("[%0t] FAIL: %s", $time, s);
        end
    endtask

    task automatic do_reset(int n);
        begin
            rst_r <= 1'b1;
            repeat (n) @(posedge clk_r);
            rst_r <= 1'b0;
            repeat (2) @(posedge clk_r);
        end
    endtask

    task automatic dispatch(int idx);
        begin
            @(negedge clk_r);
            req_r    <= 1'b1;
            desc_idx_r <= idx;
            @(negedge clk_r);
            req_r    <= 1'b0;
        end
    endtask

    task automatic pulse_stop;   begin @(negedge clk_r); stop_r <= 1'b1; @(negedge clk_r); stop_r <= 1'b0; end endtask
    task automatic pulse_ffe;    begin @(negedge clk_r); ffe_r  <= 1'b1; @(negedge clk_r); ffe_r  <= 1'b0; end endtask
    task automatic pulse_abort;  begin @(negedge clk_r); abort_r<= 1'b1; @(negedge clk_r); abort_r<= 1'b0; end endtask

    task automatic wait_desc_done(int tmo, string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (desc_done_w) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: desc_done 超时 %0d 拍", tag, tmo));
                    $display("EES_MODELSIM_RESULT FAIL %s timeout", tag);
                    $finish;
                end
            end
            // V1.9（2026-09-24）xsim 同拍读回竞态：desc_done 观测拍上，
            // 任务线程先于事件计数监视块（L188 阻塞赋值 ring_cnt/done_cnt）
            // 执行——检查点读数落后一个事件。A 核判别测实证（f7tmg_run01/
            // gate_f5md_a：A 核 xsim 复跑 F5M-D 呈与 C 核逐条同构十错，
            // 证与被测核无关；ModelSim 2026-09-22 基线为监视块先执行的
            // 调度序故 PASS）。返回前多等一拍令同拍计数落定：该拍 DUT
            // 已 idle、零新事件，窗口语义与检查强度不变。
            @(posedge clk_r);
            checks = checks + 1;
        end
    endtask

    // 粘着信号镜像（reg 变量）：wait_sticky 须按 ref 传变量——SV task 的
    // input 实参是调用瞬间的值拷贝，wire 传入后永远读到旧值 0，B1 曾全
    // 例假超时（run01 runB1_run1 实测：DUT 已发 LDR_ERR 而 TB 拍不到）。
    reg ldr_ev_c, dma_ev_c, stopped_c;
    always @(*) begin
        ldr_ev_c  = ldr_ev_w;
        dma_ev_c  = dma_ev_w;
        stopped_c = stopped_w;
    end

    task automatic wait_sticky(ref logic sig, input int tmo, input string tag);
        int t;
        begin
            t = 0;
            forever begin
                @(posedge clk_r);
                if (sig === 1'b1) break;
                t = t + 1;
                if (t > tmo) begin
                    fail($sformatf("%s: 粘着信号超时 %0d 拍", tag, tmo));
                    $display("EES_MODELSIM_RESULT FAIL %s timeout", tag);
                    $finish;
                end
            end
            checks = checks + 1;
        end
    endtask

    function automatic bit in_list(int v, int q [$]);
        begin
            in_list = 1'b0;
            foreach (q[k])
                if (q[k] == v) in_list = 1'b1;
        end
    endfunction

    // ---- 金样窗口比对（addr/data/strb 逐拍；fr>=0 → 帧参数化文件名）----
    task automatic cmp_golden(string kind, int di,
                              longint unsigned mark, string tag,
                              int fr = -1);
        int fd, n, code;
        string f, why;
        bit [31:0] ea; bit [63:0] ed; bit [7:0] es;
        longint unsigned got, sz;
        begin
            f = (fr < 0) ? $sformatf("%s/%s_golden_%0d.txt", prep_dir, kind, di)
                         : $sformatf("%s/%s_golden_f%0d_%0d.txt",
                                     prep_dir, kind, fr, di);
            fd = $fopen(f, "r");
            if (fd == 0) begin
                fail($sformatf("%s: 打不开 %s", tag, f));
                return;
            end
            sz  = (kind == "rd") ? bfm.rd_n
                                 : bfm.wr_n;
            n   = 0;
            why = "";
            code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            while (code == 3 && why == "") begin
                if (mark + n >= sz)
                    why = $sformatf("拍数不足：log=%0d 期望≥%0d",
                                    sz - mark, n + 1);
                else if (kind == "rd") begin
                    if (bfm.rd_addr_lg[mark+n] != ea ||
                        bfm.rd_data_lg[mark+n] != ed)
                        why = $sformatf("rd 拍%0d: 得 %08X/%016X 期 %08X/%016X",
                            n, bfm.rd_addr_lg[mark+n], bfm.rd_data_lg[mark+n],
                            ea, ed);
                end else begin
                    if (bfm.wr_addr_lg[mark+n] != ea ||
                        bfm.wr_data_lg[mark+n] != ed ||
                        bfm.wr_strb_lg[mark+n] != es)
                        why = $sformatf("wr 拍%0d: 得 %08X/%016X/%02X 期 %08X/%016X/%02X",
                            n, bfm.wr_addr_lg[mark+n], bfm.wr_data_lg[mark+n],
                            bfm.wr_strb_lg[mark+n], ea, ed, es);
                end
                n = n + 1;
                code = $fscanf(fd, "%h %h %h\n", ea, ed, es);
            end
            $fclose(fd);
            got = sz - mark;
            if (why != "")
                fail($sformatf("%s: desc%0d %s %s", tag, di, kind, why));
            else if (got != n)
                fail($sformatf("%s: desc%0d %s 拍数 得%0d 期%0d",
                               tag, di, kind, got, n));
            else begin
                checks = checks + 2;
                $display("[%0t] %s desc%0d %s BITEXACT %0d 拍",
                         $time, tag, di, kind, n);
            end
        end
    endtask

    // ---- 缺省配置 ----
    task automatic cfg_default;
        begin
            cfg_r_lat        = 2;
            cfg_fault_r_beat = 0;
            cfg_fault_r_resp = 2'b10;
            cfg_stall_after  = 0;
            cfg_fault_b_req  = 0;
            cfg_b_delay      = 2;
            cfg_w_stall      = 0;
            cfg_check_en     = 1'b1;
            tmo_cfg_r        = 24'd100;
            rd_os_r          = 3'd4;
            wr_os_r          = 3'd4;
            stop_r           = 1'b0;
            abort_r          = 1'b0;
            ffe_r            = 1'b0;
            head_base_r      = 32'h1F80_0000;
        end
    endtask

    // ================= RUN A =================
    task automatic run_a;
        int xfer_q [$];
        int views_q [$];
        int i;
        longint unsigned rm, wm;
        int rc0, dc0;
        string tag;
        begin
            xfer_q  = '{8,20,32,41,47,50,56,59,65,68,74,77,83,103};
            views_q = '{3,4,12,13,24,25,36,37,52,53,61,62,70,71,79,80};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN A] 104 描述符顺序派发开始");
            for (i = 0; i < 104; i++) begin
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dc0 = done_cnt;
                tag = $sformatf("A");
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("A desc%0d", i));
                if (in_list(i, xfer_q)) begin
                    cmp_golden("rd", i, rm, tag);
                    cmp_golden("wr", i, wm, tag);
                    if (i == 103) begin
                        if (cause_w != 3'd2)
                            fail("desc103 done_cause != LAST");
                        if (ring_cnt != rc0 + 1)
                            fail("desc103 未发布结果环");
                        checks = checks + 2;
                    end else begin
                        if (ring_cnt != rc0)
                            fail($sformatf("desc%0d 非法发环", i));
                        checks = checks + 1;
                    end
                end else if (in_list(i, views_q)) begin
                    if (bfm.rd_n != rm ||
                        bfm.wr_n != wm)
                        fail($sformatf("view desc%0d 不应产生 AXI 流量", i));
                    checks = checks + 1;
                end else begin
                    if (bfm.rd_n != rm ||
                        bfm.wr_n != wm)
                        fail($sformatf("validate-only desc%0d 不应产生流量", i));
                    checks = checks + 1;
                end
            end
            if (ring_cnt != 1) fail($sformatf("全帧发环数=%0d 期 1", ring_cnt));
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 3;
            $display("[RUN A] 完：104 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN B1 =================
    task automatic run_b1;
        int cd [0:18];
        int cs [0:18];
        int cb [0:18];
        int cc [0:18];
        int k;
        longint unsigned rm, wm;
        int rc0, dc0;
        begin
            cd = '{110,111,112,113,114,115,116,117,118,119,
                   120,121,122,123,124,125,126,127,108};
            cs = '{1,1,2,2,3,3,4,4,4,5,6,6,6,7,8,8,9,9,8};
            cb = '{3,3,3,3,4,4,4,4,4,4,4,4,4,5,4,4,4,4,4};
            cc = '{1,1,1,1,1,1,1,1,1,1,20,20,19,1,1,1,1,1,1};
            $readmemh({prep_dir, "/desc_table_B.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_B.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            cfg_default;
            $display("[RUN B1] 19 例装载负例开始（B 表）");
            for (k = 0; k < 19; k++) begin
                do_reset(3);
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dc0 = done_cnt;
                dispatch(cd[k]);
                wait_sticky(ldr_ev_c, 20000,
                            $sformatf("B1 L%0d", k + 1));
                if (ldr_step_w != cs[k][3:0] || ldr_bit_w != cb[k][3:0] ||
                    ldr_code_w != cc[k][7:0])
                    fail($sformatf("L%0d(desc%0d): 得 step=%0d bit=%0d code=%0d 期 %0d/%0d/%0d",
                        k+1, cd[k], ldr_step_w, ldr_bit_w, ldr_code_w,
                        cs[k], cb[k], cc[k]));
                else begin
                    checks = checks + 3;
                    $display("[%0t] B1 L%0d desc%0d step=%0d bit=%0d code=%0d 命中",
                             $time, k+1, cd[k], ldr_step_w, ldr_bit_w, ldr_code_w);
                end
                if (bfm.rd_n != rm || bfm.wr_n != wm)
                    fail($sformatf("L%0d: 负例不应产生 AXI 流量", k+1));
                if (done_cnt != dc0)
                    fail($sformatf("L%0d: 负例不应 desc_done", k+1));
                if (ring_cnt != rc0)
                    fail($sformatf("L%0d: 负例不应发环", k+1));
                checks = checks + 3;
            end
        end
    endtask

    // ================= RUN B2 =================
    task automatic run_b2;
        longint unsigned rm, wm;
        int rc0, dc0;
        begin
            $readmemh({prep_dir, "/desc_table_B.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_B.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            // B2 读域预置（S1/S2/E2/D4/D5 数据金样比对须真图像；
            // run01 B2_run1 漏灌 → 全 0 数据逐拍失配实测）
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;

            // ---- S1：desc104 单字节段（1 拍尾 strb）----
            do_reset(3);
            rm = bfm.rd_n; wm = bfm.wr_n;
            rc0 = ring_cnt;
            dispatch(104);
            wait_desc_done(100000, "B2 S1");
            cmp_golden("rd", 104, rm, "B2");
            cmp_golden("wr", 104, wm, "B2");
            if (ring_cnt != rc0) fail("S1 不应发环");
            checks = checks + 1;

            // ---- S2：desc105 0B+40B 段（0 长段跳过 D-F3j）----
            do_reset(3);
            rm = bfm.rd_n; wm = bfm.wr_n;
            dispatch(105);
            wait_desc_done(100000, "B2 S2");
            cmp_golden("rd", 105, rm, "B2");
            cmp_golden("wr", 105, wm, "B2");

            // ---- S4：desc107 8B/8B 容量边界（V1.3 正例，用户裁定）----
            // w14=Σ=8=size=CHW——满容量合法（等值边界非余量）；若 V1.3
            // 误写为等值语义此例仍过，配合 L19(9B) 区分上界/等值两种实现
            do_reset(3);
            rm = bfm.rd_n; wm = bfm.wr_n;
            rc0 = ring_cnt;
            dispatch(107);
            wait_desc_done(100000, "B2 S4");
            cmp_golden("rd", 107, rm, "B2");
            cmp_golden("wr", 107, wm, "B2");
            if (ring_cnt != rc0) fail("S4 不应发环");
            checks = checks + 1;

            // ---- E2：stop + desc106(last) → 完成后停 + 照常发环 ----
            do_reset(3);
            rm = bfm.rd_n; wm = bfm.wr_n;
            rc0 = ring_cnt;
            dispatch(106);
            repeat (10) @(posedge clk_r);
            pulse_stop;
            wait_desc_done(100000, "B2 E2");
            cmp_golden("rd", 106, rm, "B2");
            cmp_golden("wr", 106, wm, "B2");
            if (cause_w != 3'd4)      fail("E2 cause != STOP");
            if (ring_cnt != rc0 + 1)  fail("E2 stop+last 未发环");
            if (!stopped_w)           fail("E2 未置 stopped");
            checks = checks + 3;
            $display("[%0t] B2 E2 stop+last：发环 + stopped ✓", $time);

            // ---- E3：ffe 强发环（desc105 非 last）----
            do_reset(3);
            rc0 = ring_cnt;
            dispatch(105);
            repeat (10) @(posedge clk_r);
            pulse_ffe;
            wait_desc_done(100000, "B2 E3");
            if (cause_w != 3'd3)      fail("E3 cause != FFE");
            if (ring_cnt != rc0 + 1)  fail("E3 未强发环");
            if (stopped_w)            fail("E3 不应 stopped");
            checks = checks + 3;
            $display("[%0t] B2 E3 ffe：强发环 ✓", $time);

            // ---- E1：abort → 丢弃（无 done/无发环/stopped/cause=abort）----
            do_reset(3);
            cfg_check_en = 1'b0;             // 取消余流协议检查
            rc0 = ring_cnt; dc0 = done_cnt;
            dispatch(106);
            repeat (30) @(posedge clk_r);
            pulse_abort;
            wait_sticky(stopped_c, 20000, "B2 E1");
            if (cause_w != 3'd5)      fail("E1 cause != ABORT");
            if (ring_cnt != rc0)      fail("E1 abort 不应发环");
            if (done_cnt != dc0)      fail("E1 abort 不应 desc_done");
            checks = checks + 4;
            $display("[%0t] B2 E1 abort：丢弃帧 ✓", $time);
            cfg_check_en = 1'b1;

            // ---- D1：RRESP SLVERR（全局读拍 3）→ E_BIT_DMA_RD ----
            do_reset(3);
            cfg_fault_r_beat = 3;
            dc0 = done_cnt;
            dispatch(106);
            wait_sticky(dma_ev_c, 50000, "B2 D1");
            if (dma_bit_w != 4'd1) fail($sformatf("D1 bit=%0d 期 1", dma_bit_w));
            if (done_cnt != dc0)   fail("D1 不应 desc_done");
            checks = checks + 3;
            $display("[%0t] B2 D1 RRESP 错 → E_BIT_DMA_RD ✓", $time);
            cfg_fault_r_beat = 0;

            // ---- D2：BRESP DECERR（写请求 1）→ E_BIT_DMA_WR ----
            do_reset(3);
            cfg_fault_b_req = 1;
            dc0 = done_cnt;
            dispatch(106);
            wait_sticky(dma_ev_c, 50000, "B2 D2");
            if (dma_bit_w != 4'd2) fail($sformatf("D2 bit=%0d 期 2", dma_bit_w));
            if (done_cnt != dc0)   fail("D2 不应 desc_done");
            checks = checks + 3;
            $display("[%0t] B2 D2 BRESP 错 → E_BIT_DMA_WR ✓", $time);
            cfg_fault_b_req = 0;

            // ---- D3：R 永停 + 小超时 → E_BIT_TIMEOUT ----
            do_reset(3);
            cfg_stall_after = 2;
            tmo_cfg_r = 24'd8;              // 8×1024 拍无进展
            dc0 = done_cnt;
            dispatch(106);
            wait_sticky(dma_ev_c, 60000, "B2 D3");
            if (dma_bit_w != 4'd7) fail($sformatf("D3 bit=%0d 期 7", dma_bit_w));
            if (done_cnt != dc0)   fail("D3 不应 desc_done");
            checks = checks + 3;
            $display("[%0t] B2 D3 超时 → E_BIT_TIMEOUT ✓", $time);
            cfg_stall_after = 0;
            tmo_cfg_r = 24'd100;

            // ---- D4：W 长背压（流闸压测）→ 仍逐拍 BITEXACT ----
            do_reset(3);
            cfg_w_stall = 16;
            rm = bfm.rd_n; wm = bfm.wr_n;
            dispatch(106);
            wait_desc_done(300000, "B2 D4");
            cmp_golden("rd", 106, rm, "B2");
            cmp_golden("wr", 106, wm, "B2");
            if (bfm_proto_err != 0)
                fail($sformatf("D4 协议违例 %0d", bfm_proto_err));
            checks = checks + 1;
            $display("[%0t] B2 D4 W 背压 BITEXACT ✓", $time);
            cfg_w_stall = 0;

            // ---- D5：在途复位 → 重派发完成且数据正确 ----
            do_reset(3);
            cfg_r_lat = 10;                 // 拉长读窗，确保在途
            dispatch(106);
            repeat (170) @(posedge clk_r);  // 取包(~135 拍)后入传输窗
            do_reset(8);                    // 传输中途复位（BFM 队列清、内存留）
            cfg_r_lat = 2;
            rm = bfm.rd_n; wm = bfm.wr_n;
            rc0 = ring_cnt;
            dispatch(106);
            wait_desc_done(100000, "B2 D5");
            cmp_golden("rd", 106, rm, "B2");
            cmp_golden("wr", 106, wm, "B2");
            if (ring_cnt != rc0 + 1) fail("D5 重跑后应发环（last）");
            checks = checks + 1;
            $display("[%0t] B2 D5 在途复位重跑 ✓", $time);
        end
    endtask

    // ================= RUN F4 =================
    // 图级子图对拍（replan §PPU-F4；数据=f4_prep 真软件张量，非 PRNG）。
    // 5 个 RTL XFER 任务连续派发（无中途复位）：
    //   SG1 desc20→desc59：Concat→Conv(软)→Concat 混合链（正典图无
    //        concat→concat 直连边，此为最贴图链型）；
    //   SG2 desc50（Upsample 软→Concat）；SG3 desc47（Conv/MaxPool 软→Concat）；
    //   SG4 desc103（heads 六段 identity，149100B）。
    // 逐描述符 rd/wr 金样 BITEXACT + desc103=last 唯一发环。
    task automatic run_f4;
        int f4_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f4_q = '{20, 59, 50, 47, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F4] 5 RTL 任务连续派发（真张量子图对拍）");
            foreach (f4_q[k]) begin
                i   = f4_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F4 desc%0d", i));
                cmp_golden("rd", i, rm, "F4");
                cmp_golden("wr", i, wm, "F4");
                if (i == 103) begin
                    if (cause_w != 3'd2)
                        fail("desc103 done_cause != LAST");
                    if (ring_cnt != rc0 + 1)
                        fail("desc103 未发布结果环");
                    checks = checks + 2;
                end else begin
                    if (ring_cnt != rc0)
                        fail($sformatf("desc%0d 非法发环", i));
                    checks = checks + 1;
                end
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F4] 完：5 RTL desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5A =================
    // Upsample2 单描述符门（replan §PPU-F5 第一步；ppu_ups_engine 首跑）。
    // 5 任务连续派发（无中途复位），无 last 描述符（全程零发环）：
    //   正典 desc49/58（真软件张量：desc c/h/w=输出 dims，输入形状=
    //        in0 槽 dims——shell V1.1 槽 0 接线；w14=4·CHW_in=out.size）；
    //   合成 desc108/109/110（in=(5,6,7)/(3,4,3)/(1,2,3)，非方+极小例，
    //        buf 112..117@0x1800xxxx，PRNG 确定性）。
    // 逐描述符 rd/wr 金样 BITEXACT（wr=行对重排顺序流 == 软件
    // repeat(2,axis=2).repeat(2,axis=3)）。
    task automatic run_f5a;
        int f5_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5_q = '{49, 58, 108, 109, 110};
            $readmemh({prep_dir, "/desc_table_F5.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_F5.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5A] 5 Upsample2 任务连续派发（正典真张量+合成向量）");
            foreach (f5_q[k]) begin
                i   = f5_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5A desc%0d", i));
                cmp_golden("rd", i, rm, "F5A");
                cmp_golden("wr", i, wm, "F5A");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5A] 完：5 Upsample2 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5B =================
    // Upsample2×XFER 相邻 3 task 子图门（replan §PPU-F5 第二步）。
    // 两尺度各一严格 3 task 子图（probe_f5b.py 实测，buf50/59 消费者唯一）：
    //   SG-A desc48(conv 软)→desc49(UPS RTL)→buf50→desc50(XFER RTL)←buf34
    //   SG-B desc57(conv 软)→desc58(UPS RTL)→buf59→desc59(XFER RTL)←buf22
    // 关键：buf50/buf59 **不预载**——UPS 写入（本 run）后 XFER 立即读回，
    // BFM 稀疏内存写贯通承载引擎间经 DDR 的 RTL→RTL 链；XFER rd 金样
    // 段 0 = 软件 upsample 出（与 UPS wr 金样同源，联立即证传递一致）。
    // 4 任务连续派发（UPS→其消费者紧随，混合 opcode 无中途复位），零发环。
    task automatic run_f5b;
        int f5b_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5b_q = '{49, 50, 58, 59};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5B] 4 RTL 任务连续派发（UPS→XFER 邻接×两尺度；UPS 出 buf 不预载）");
            foreach (f5b_q[k]) begin
                i   = f5b_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5B desc%0d", i));
                cmp_golden("rd", i, rm, "F5B");
                cmp_golden("wr", i, wm, "F5B");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5B] 完：2 UPS + 2 XFER desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5C =================
    // Upsample2 三尺度 neck 子图门（replan §PPU-F5 第三步）。
    // 8 RTL 任务连发（拓扑序 20,32,47,56 → 49,58 → 50,59），UPS 链一跳
    // conv 邻域整圈（probe_f5c 实测，全图 UPS→CAT 边仅此两条）：
    //   40×40: CAT20→buf21→conv(软)→buf22↘CAT59←buf59←UPS58←conv(软)←CAT56
    //   20×20: CAT32→buf33→conv(软)→buf34↘CAT50←buf50←UPS49；CAT56→UPS58 入
    //   10×10: CAT47→buf48→conv(软)→buf49=UPS49 入
    // 软件边界 19 buf 预载；buf50/59 不预载（RTL 写→XFER 读回，F5b 同）。
    // 金样=f5c_prep.py；零发环（无 last）。
    task automatic run_f5c;
        int f5c_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5c_q = '{20, 32, 47, 56, 49, 58, 50, 59};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5C] 8 RTL 任务连发（三尺度 neck：4 CAT+2 UPS+2 CAT；拓扑序）");
            foreach (f5c_q[k]) begin
                i   = f5c_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5C desc%0d", i));
                cmp_golden("rd", i, rm, "F5C");
                cmp_golden("wr", i, wm, "F5C");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5C] 完：6 CAT + 2 UPS desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5D =================
    // 全帧整网回放门（replan §PPU-F5 第四步「N 帧整网回放」；语料全集
    // =5 帧，load_frames/G0 golden_index 台账，证据记 replan 偏差）。
    // RTL 任务集=当前引擎全集的数据面 PPU 任务（升序=拓扑序）：
    //   13 CAT（8,20,32,41,47,50,56,59,65,68,74,77,83——其中 7 个为首次
    //     RTL 执行）+ 2 UPS（49,58）+ HEADS（103，每帧发环 done=LAST）。
    //   VIEW 零 DMA 流量不入（F3 A 门已覆全 104 描述符 loader 语义）。
    // 每帧：bfm.load_preload(preload_f{k})（同址全量覆盖）→ 16 任务连发
    // → 逐任务 rd/wr 金样（_f{k}_{di} 帧参数化）。帧间**不复位**——
    // 兼证跨帧无状态泄漏；UPS 出 buf50/59 帧内 RTL 写→XFER 读回（F5b）。
    task automatic run_f5d;
        int f5d_q [$];
        int i, k, rc0;
        longint unsigned rm, wm;
        begin
            f5d_q = '{8, 20, 32, 41, 47, 49, 50, 56, 58, 59,
                      65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            cfg_default;
            do_reset(5);               // 全程唯一一次复位（帧间不复位）
            ring_cnt = 0; done_cnt = 0;
            for (k = 0; k < 5; k = k + 1) begin
                bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", k)});
                $display("[RUN F5D] 帧%0d preload 重载（同址覆盖，无复位连发 16 任务）", k);
                foreach (f5d_q[t]) begin
                    i   = f5d_q[t];
                    rm  = bfm.rd_n;
                    wm  = bfm.wr_n;
                    rc0 = ring_cnt;
                    dispatch(i);
                    wait_desc_done(3_000_000, $sformatf("F5D f%0d desc%0d", k, i));
                    cmp_golden("rd", i, rm, "F5D", k);
                    cmp_golden("wr", i, wm, "F5D", k);
                    if (i == 103) begin
                        if (cause_w != 3'd2)
                            fail($sformatf("帧%0d desc103 done_cause != LAST", k));
                        if (ring_cnt != rc0 + 1)
                            fail($sformatf("帧%0d desc103 未发布结果环", k));
                        checks = checks + 2;
                    end else begin
                        if (ring_cnt != rc0)
                            fail($sformatf("帧%0d desc%0d 非法发环", k, i));
                        checks = checks + 1;
                    end
                end
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5D] 完：5 帧 × 16 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d（期 5）",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
            if (ring_cnt != 5)
                fail($sformatf("全回放发环数=%0d 期 5", ring_cnt));
        end
    endtask

    // ================= RUN F5M-A =================
    // MaxPool5 单描述符门（replan §PPU-F5 第二步；ppu_mp5_engine 首跑）。
    // 4 任务连续派发（无中途复位），无 last 描述符（全程零发环）：
    //   正典 desc44（SPPF 三连池首环真软件张量：desc c/h/w=槽 dims=
    //        (128,10,10) 同形；w14=CHW=12800=out.size）；
    //   合成 desc111/112/113（in=(2,6,5) 全-128 / (2,3,7) 边角 H<5 非方
    //        / (1,1,1) 极小 pad 主导，buf 118..123@0x1800xxxx）。
    // 逐描述符 rd/wr 金样 BITEXACT（wr == 软件 maxpool5 掩码窗 max
    // 原始 int8 无 requant；独立参考 mp5_ref 主机侧已钉死）。
    task automatic run_f5m_a;
        int f5m_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5m_q = '{44, 111, 112, 113};
            $readmemh({prep_dir, "/desc_table_F5M.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_F5M.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5M-A] 4 MaxPool5 任务连续派发（正典真张量+合成向量）");
            foreach (f5m_q[k]) begin
                i   = f5m_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5M-A desc%0d", i));
                cmp_golden("rd", i, rm, "F5M-A");
                cmp_golden("wr", i, wm, "F5M-A");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5M-A] 完：4 MaxPool5 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5M-B =================
    // MaxPool5×XFER 相邻子图门（replan §PPU-F5 第二步 b；SPPF 四任务）。
    // 拓扑（probe 实测）：buf44(预载=conv 软件边界) → 44 MP5 → buf45
    //   → 45 MP5 → buf46 → 46 MP5 → buf47 → 47 CAT(4 段 buf44..47)
    //   → buf48。内含严格 3 task XFER 相邻子图 {45,46,47}。
    // 关键（F5b 同机制）：buf45/46/47 不预载——本 run 内 RTL 写→
    // 后继读回，mp5→mp5 RTL→RTL 链 + mp5→concat XFER 邻接全走 DDR
    // 往返；金样联立（前任务 wr BITEXACT + 后任务 rd BITEXACT ⇒
    // 传递一致）。4 任务连发零复位，零发环。
    task automatic run_f5m_b;
        int f5mb_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5mb_q = '{44, 45, 46, 47};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5M-B] 4 RTL 任务连发（SPPF：3xMP5 链→CAT；buf45/46/47 不预载=RTL 写→读回）");
            foreach (f5mb_q[k]) begin
                i   = f5mb_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5M-B desc%0d", i));
                cmp_golden("rd", i, rm, "F5M-B");
                cmp_golden("wr", i, wm, "F5M-B");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5M-B] 完：3 MP5 + 1 CAT desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5M-C =================
    // MaxPool5 三尺度 neck 子图门（replan §PPU-F5 第三步 c）。
    // F5c 同域 neck 扩入 SPPF 三连池——11 RTL 任务连发（拓扑序
    // 20,32,56 → 44,45,46（mp5 链）→ 47（SPPF CAT）→ 49,58 → 50,59），
    // 三尺度 40×40/20×20/10×10 全覆盖；混合 opcode（CAT×6+MP5×3+UPS×2）
    // 跨任务连续派发零复位。RTL 写区不预载：buf45/46/47（SPPF 链）
    // + buf50/59（UPS 出）+ 上游 CAT 出——RTL 写→读回（DDR 往返）；
    // 软件边界 16 buf 预载（F5c 19 − SPPF 三 buf）。金样=f5mc_prep.py。
    task automatic run_f5m_c;
        int f5mc_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5mc_q = '{20, 32, 56, 44, 45, 46, 47, 49, 58, 50, 59};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5M-C] 11 RTL 任务连发（三尺度 neck+SPPF：6 CAT+3 MP5+2 UPS；拓扑序零复位）");
            foreach (f5mc_q[k]) begin
                i   = f5mc_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5M-C desc%0d", i));
                cmp_golden("rd", i, rm, "F5M-C");
                cmp_golden("wr", i, wm, "F5M-C");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5M-C] 完：6 CAT + 3 MP5 + 2 UPS desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5M-D =================
    // MaxPool5 类梯第 4 步：全帧整网回放门（replan §PPU-F5 第四步的
    // MaxPool5 版）。RTL 任务集 = F5d 16 任务 + SPPF 三连池 = **19 任务/
    // 帧**（13 CAT + 3 MP5 + 2 UPS + HEADS，升序=拓扑序：44→45→46 恰为
    // SPPF 链序）× 5 帧（语料全集）连发；帧间**不复位**（preload_f{k}
    // 重载=同址全量覆盖，兼证跨帧无状态泄漏）。预载 = F5d 42 buf −
    // buf45/46/47（SPPF 链帧内 RTL 写→MP5/CAT 读回，DDR 往返；buf44
    // 仍预载=conv43 软件边界）；heads 出=HEAD_BASE，desc103 每帧发环。
    // 金样=f5md_prep.py（rd/wr_golden_f{k}_{di} 帧参数化）。
    task automatic run_f5m_d;
        int f5md_q [$];
        int i, k, rc0;
        longint unsigned rm, wm;
        begin
            f5md_q = '{8, 20, 32, 41, 44, 45, 46, 47, 49, 50, 56, 58, 59,
                      65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            cfg_default;
            do_reset(5);               // 全程唯一一次复位（帧间不复位）
            ring_cnt = 0; done_cnt = 0;
            for (k = 0; k < 5; k = k + 1) begin
                bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", k)});
                $display("[RUN F5M-D] 帧%0d preload 重载（同址覆盖，无复位连发 19 任务）", k);
                foreach (f5md_q[t]) begin
                    i   = f5md_q[t];
                    rm  = bfm.rd_n;
                    wm  = bfm.wr_n;
                    rc0 = ring_cnt;
                    dispatch(i);
                    wait_desc_done(3_000_000, $sformatf("F5M-D f%0d desc%0d", k, i));
                    cmp_golden("rd", i, rm, "F5M-D", k);
                    cmp_golden("wr", i, wm, "F5M-D", k);
                    if (i == 103) begin
                        if (cause_w != 3'd2)
                            fail($sformatf("帧%0d desc103 done_cause != LAST", k));
                        if (ring_cnt != rc0 + 1)
                            fail($sformatf("帧%0d desc103 未发布结果环", k));
                        checks = checks + 2;
                    end else begin
                        if (ring_cnt != rc0)
                            fail($sformatf("帧%0d desc%0d 非法发环", k, i));
                        checks = checks + 1;
                    end
                end
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5M-D] 完：5 帧 × 19 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d（期 5）",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
            if (ring_cnt != 5)
                fail($sformatf("全回放发环数=%0d 期 5", ring_cnt));
        end
    endtask

    // ================= RUN F5AA =================
    // Add 单描述符门（replan §PPU-F5 第三步；ppu_add_engine 首跑）。
    // 5 任务连续派发（无中途复位），无 last 描述符（全程零发环）：
    //   正典 desc7（neck 首个 add：(16,80,80)=102400B 真张量；真 profile
    //        双 requant m0=0x737AB900/s0=31、m1=0x43BD77FD/s1=30，
    //        probe 已证 RNE 复算==store[out]）；
    //   合成 desc124..127（quant 槽 200..202 splice，buf 112..123
    //        @0x18002400 段）：
    //     124 恒等 (3,5,7)=105B：m0=m1=2^30/s=30 → y=sat_i8(a+b)
    //         （尾拍 105%8=1）；
    //     125 平局 (2,3,11)=66B：m=2^30/s=31 → 每奇字节恰 tie
    //         （rem=half，向偶进位；尾块 2B=1 拍 2 有效 lane）；
    //     126 非对称饱和 (4,2,9)=72B：m0=2^30/s0=23（巨值→±饱和）、
    //         m1=0x40/s1=0（s=0 旁路路征）；
    //     127 极小 (1,1,1)=1B：单拍 1 有效 lane（块=1B，块尾窗口
    //         读预载补零实像）。
    // rd 金样 = 引擎确定读序（64B 块 A/B 交替 + 尾块 min(64,rem)，
    // 一侧读尽独跑）——prep 同序生成；wr 金样 = 软件 add 输出
    // （rne×2+sat，独立参考 add_ref 主机侧钉死）。
    task automatic run_f5aa_a;
        int f5aa_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5aa_q = '{7, 124, 125, 126, 127};
            $readmemh({prep_dir, "/desc_table_F5AA.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_F5AA.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_F5AA.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5AA] 5 Add 任务连续派发（正典真张量真 profile+合成四味）");
            foreach (f5aa_q[k]) begin
                i   = f5aa_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5AA desc%0d", i));
                cmp_golden("rd", i, rm, "F5AA");
                cmp_golden("wr", i, wm, "F5AA");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5AA] 完：5 Add desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5AB =================
    // Add 相邻 3 task 子图门（replan §PPU-F5 第三步 b；双链）。
    // 拓扑（表实况 2026-09-22 probe）：{16,19,20}=16 ADD(双 conv 入
    // buf16/buf14)→buf17→19 ADD(in0=buf19, in1=buf17)→buf20→
    //   20 CAT(段 13/14/17/20)；{28,31,32} 同构（28→buf29→31(in1=buf29)
    //   →buf32→32 CAT 段 25/26/29/32）。ADD→ADD RTL→RTL 链 + ADD→CAT
    //   XFER 邻接一次全闭。链内 ADD 出 buf17/20/29/32（恰为后继 CAT 入段）
    //   不预载——本 run 内 RTL 写→后继读回（DDR 往返）；金样联立
    //   （前任务 wr BITEXACT + 后任务 rd BITEXACT ⇒ 传递一致）。
    // 6 任务连发零复位，零发环。
    task automatic run_f5ab;
        int f5ab_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5ab_q = '{16, 19, 20, 28, 31, 32};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5AB] 6 RTL 任务连发（双 ADD->ADD->CAT 链；buf17/29/19/31 不预载=RTL 写->读回）");
            foreach (f5ab_q[k]) begin
                i   = f5ab_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5AB desc%0d", i));
                cmp_golden("rd", i, rm, "F5AB");
                cmp_golden("wr", i, wm, "F5AB");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5AB] 完：4 ADD + 2 CAT desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5AC =================
    // Add 多任务混合门（replan §PPU-F5 第三步 c；全 ADD 域）。
    // 10 RTL 任务连发（拓扑序 7,8,16,19,20,28,31,32,40,41）= 全部
    // 6 ADD + 其消费 CAT（三尺度 80×80/40×40/20×20 全覆盖：7/16/19
    // @80×80、28/31 @40×40、40 @20×20）。混合 opcode（ADD×6+CAT×4）
    // 跨任务连续派发零复位。RTL 写区不预载（ADD 出 buf8/17/20/29/32/41
    // + CAT 出）；软件边界 buf 预载。金样=f5ac_prep.py。
    task automatic run_f5ac;
        int f5ac_q [$];
        int i, rc0;
        longint unsigned rm, wm;
        begin
            f5ac_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            bfm.load_preload({prep_dir, "/preload.txt"});
            cfg_default;
            do_reset(5);
            ring_cnt = 0; done_cnt = 0;
            $display("[RUN F5AC] 10 RTL 任务连发（6 ADD+4 CAT 全 ADD 域；拓扑序零复位）");
            foreach (f5ac_q[k]) begin
                i   = f5ac_q[k];
                rm  = bfm.rd_n;
                wm  = bfm.wr_n;
                rc0 = ring_cnt;
                dispatch(i);
                wait_desc_done(3_000_000, $sformatf("F5AC desc%0d", i));
                cmp_golden("rd", i, rm, "F5AC");
                cmp_golden("wr", i, wm, "F5AC");
                if (ring_cnt != rc0)
                    fail($sformatf("desc%0d 非法发环", i));
                checks = checks + 1;
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5AC] 完：6 ADD + 4 CAT desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
        end
    endtask

    // ================= RUN F5AD =================
    // Add 全帧整网回放门（replan §PPU-F5 第三步 d；Add 类梯收官）。
    // 25 数据面 PPU 任务/帧（=F5MD 19 + 6 ADD = 13 CAT+6 ADD+3 MP5+
    // 2 UPS+HEADS —— **全部**数据面 PPU 任务，升序=拓扑序）× 5 帧
    // （语料全集）连发；帧间**不复位**（preload_f{k} 同址全量覆盖，
    // 兼证跨帧无状态泄漏；125 次连发无一状态残留）。预载 = 软件边界
    // buf（conv 产物等）——RTL 写区（ADD/MP5/UPS/CAT 出）不预载，
    // 全走 RTL 写→后继读回 DDR 往返；heads 出=HEAD_BASE，desc103
    // 每帧发环。金样=f5ad_prep.py（rd/wr_golden_f{k}_{di} 帧参数化）。
    task automatic run_f5ad;
        int f5ad_q [$];
        int i, k, rc0;
        longint unsigned rm, wm;
        begin
            f5ad_q = '{7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46,
                      47, 49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103};
            $readmemh({prep_dir, "/desc_table_A.hex"}, desc_rom);
            $readmemh({prep_dir, "/buf_table_A.hex"},  buf_rom);
            $readmemh({prep_dir, "/quant_table_A.hex"}, qt_rom);
            cfg_default;
            do_reset(5);               // 全程唯一一次复位（帧间不复位）
            ring_cnt = 0; done_cnt = 0;
            for (k = 0; k < 5; k = k + 1) begin
                bfm.load_preload({prep_dir, $sformatf("/preload_f%0d.txt", k)});
                $display("[RUN F5AD] 帧%0d preload 重载（同址覆盖，无复位连发 25 任务）", k);
                foreach (f5ad_q[t]) begin
                    i   = f5ad_q[t];
                    rm  = bfm.rd_n;
                    wm  = bfm.wr_n;
                    rc0 = ring_cnt;
                    dispatch(i);
                    wait_desc_done(3_000_000, $sformatf("F5AD f%0d desc%0d", k, i));
                    cmp_golden("rd", i, rm, "F5AD", k);
                    cmp_golden("wr", i, wm, "F5AD", k);
                    if (i == 103) begin
                        if (cause_w != 3'd2)
                            fail($sformatf("帧%0d desc103 done_cause != LAST", k));
                        if (ring_cnt != rc0 + 1)
                            fail($sformatf("帧%0d desc103 未发布结果环", k));
                        checks = checks + 2;
                    end else begin
                        if (ring_cnt != rc0)
                            fail($sformatf("帧%0d desc%0d 非法发环", k, i));
                        checks = checks + 1;
                    end
                end
            end
            if (bfm_proto_err != 0)
                fail($sformatf("AXI 协议违例 %0d", bfm_proto_err));
            if (bfm_unloaded != 0)
                fail($sformatf("读未装载拍 %0d", bfm_unloaded));
            checks = checks + 2;
            $display("[RUN F5AD] 完：5 帧 × 25 desc / rd %0d 拍 / wr %0d 拍 / 发环 %0d（期 5）",
                     bfm.rd_n, bfm.wr_n, ring_cnt);
            if (ring_cnt != 5)
                fail($sformatf("全回放发环数=%0d 期 5", ring_cnt));
        end
    endtask

    // ---- 主控 ----
    integer run_sel;
    initial begin
        errors = 0; checks = 0;
        ring_cnt = 0; done_cnt = 0;
        req_r = 0; desc_idx_r = 0;
        if (!$value$plusargs("PREP=%s", prep_dir))
            prep_dir = "E:/competition/4_metrics/logs/2026-09-21_yolo_ppu_f3_shell_run01/prep";
        if (!$value$plusargs("RUN=%s", run_s)) run_s = "A";
        cfg_default;
        rst_r = 1'b1;

        case (run_s)
        "A":  run_a;
        "B1": run_b1;
        "B2": run_b2;
        "F4": run_f4;
        "F5A": run_f5a;
        "F5B": run_f5b;
        "F5C": run_f5c;
        "F5D": run_f5d;
        "F5MA": run_f5m_a;
        "F5MB": run_f5m_b;
        "F5MC": run_f5m_c;
        "F5MD": run_f5m_d;
        "F5AA": run_f5aa_a;
        "F5AB": run_f5ab;
        "F5AC": run_f5ac;
        "F5AD": run_f5ad;
        default: begin
            $display("FATAL: 未知 RUN=%s", run_s);
            $display("EES_MODELSIM_RESULT FAIL bad-run");
            $finish;
        end
        endcase

        if (bfm_proto_err != 0 && run_s != "B2")
            fail($sformatf("协议违例 %0d", bfm_proto_err));
        $display("EES_SUMMARY run=%s checks=%0d errors=%0d rd=%0d wr=%0d",
                 run_s, checks, errors,
                 bfm.rd_n, bfm.wr_n);
        if (errors == 0)
            $display("EES_MODELSIM_RESULT PASS ppu_f3_shell run=%s", run_s);
        else begin
            $display("EES_MODELSIM_RESULT FAIL ppu_f3_shell run=%s errors=%0d",
                     run_s, errors);
            $finish;
        end
        $finish;
    end

endmodule
