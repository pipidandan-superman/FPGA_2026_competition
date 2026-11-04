/************************************************************************
 * File Name       : ppu_axi_bfm.sv
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_axi_bfm
 * Description     : PPU-F3 TB 用 AXI4 64b 从端 BFM（稀疏内存模型，
 *                   按 8B 拍地址键控 mem[addr[31:3]]）。preload 任务灌
 *                   入 f3_prep preload.txt（addr data strb）。
 *
 *   行为：AR/R、AW/W/B 独立；R 拍随机延迟；WREADY 可配间歇拉低
 *   （D4 背压），B 固定延迟；请求按序（DUT 单 ID 合同）。
 *   协议检查（cfg_check_en）：地址 8B 对齐、burst 不跨 4KiB、
 *   WSTRB 自 lane0 连续（(s+1)&s==0）、AW 陪衬 W 拍、读/写在途
 *   ≤4、读未装载标记（unloaded_cnt，金样路径必为 0）。
 *   故障注入：cfg_fault_r_beat 全局读拍号 RRESP 错、cfg_fault_b_req
 *   写请求号 BRESP 错、cfg_stall_after 该读拍后 RVALID 永停（超时）。
 *   观测：rd_addr_lg/rd_data_lg、wr_addr_lg/wr_data_lg/wr_strb_lg
 *   （TB 层级取用，窗口比对 f3_prep 金样）。
 * Dependencies    : 无（TB 专用，非综合）。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : cfg_stall_after 永停改拍间生效（原仅拦
 *       新 burst 首拍，单 burst 连续流内不停，D3 超时门失效实测）。
 *   - V1.2 (2026-09-23) by LSL : 拍日志容量对数增长（原逐拍 new[n+1] 整块
 *       重分配在 xsim 下 O(N²) churn，F6B 11.5 万拍即 1.1GB 撞墙）；
 *       有效拍数改 rd_n/wr_n，clear_logs 只清计数。
 *   - V1.3 (2026-09-29) by LSL : 新增 cfg_zero_strb_ok 端口——ppu_dma_master
 *       V1.3 错误保持期写排干补发全零 strobe 拍（AXI 合法 no-op），该窗内
 *       零 strobe 豁免原"全零即违例"检查；未连通/0 全严不变（sfh 第 5 轮
 *       探针实证：幻影 AW 留 AW 队列为 M3S 软复位死锁根因，排干为正解）。
 ************************************************************************/

`timescale 1ns/1ps

module ppu_axi_bfm (
    input  wire        clk_i,
    input  wire        rst_i,
    // ---- AXI4 slave 侧 ----
    input  wire        arvalid_i,
    output reg         arready_o,
    input  wire [31:0] araddr_i,
    input  wire [3:0]  arlen_i,
    output reg         rvalid_o,
    output reg  [63:0] rdata_o,
    output reg  [1:0]  rresp_o,
    output reg         rlast_o,
    input  wire        rready_i,
    input  wire        awvalid_i,
    output reg         awready_o,
    input  wire [31:0] awaddr_i,
    input  wire [3:0]  awlen_i,
    input  wire        wvalid_i,
    output reg         wready_o,
    input  wire [63:0] wdata_i,
    input  wire [7:0]  wstrb_i,
    input  wire        wlast_i,
    output reg         bvalid_o,
    output reg  [1:0]  bresp_o,
    input  wire        bready_i,
    // ---- 配置（TB 驱动）----
    input  integer     cfg_r_lat,         // R 拍间随机延迟上限（含 0）
    input  integer     cfg_fault_r_beat,  // 全局读拍号 RRESP 注入（0=off）
    input  wire [1:0]  cfg_fault_r_resp,
    input  integer     cfg_stall_after,   // 该读拍号后 RVALID 永停（0=off）
    input  integer     cfg_fault_b_req,   // 写请求号 BRESP 注入（0=off）
    input  integer     cfg_b_delay,       // BVALID 额外延迟
    input  integer     cfg_w_stall,       // >0：每 4 拍接受后拉低此长
    input  wire        cfg_check_en,
    input  wire        cfg_zero_strb_ok,  // master 错误排干零 strobe 拍豁免
    // ---- 观测（计数口；日志数组 TB 层级取用）----
    output longint unsigned rd_cnt,
    output longint unsigned wr_cnt,
    output integer     proto_err,
    output integer     unloaded_cnt
);

    localparam [1:0] RESP_OKAY = 2'b00, RESP_EXOKAY = 2'b01,
                     RESP_SLVERR = 2'b10, RESP_DECERR = 2'b11;

    // ---- 稀疏内存 ----
    bit [63:0] mem [bit [28:0]];
    int unsigned ld_n;

    // ---- 日志数组（TB 层级取用；V1.2 容量对数增长，有效拍数看 rd_n/wr_n）----
    bit [31:0] rd_addr_lg [];
    bit [63:0] rd_data_lg [];
    bit [31:0] wr_addr_lg [];
    bit [63:0] wr_data_lg [];
    bit [7:0]  wr_strb_lg [];
    int unsigned rd_n, wr_n;            // 有效拍数（消费者用；勿再取 .size()）
    int unsigned rd_cap, wr_cap;        // 已分配容量

    // ---- 队列/状态 ----
    bit [31:0] ar_addr_q [$];
    bit [3:0]  ar_len_q  [$];
    bit [31:0] aw_addr_q [$];
    bit [3:0]  aw_len_q  [$];
    bit [1:0]  b_resp_q  [$];

    reg        r_run;
    reg [31:0] r_addr_r;
    reg [3:0]  r_left_r;
    reg [7:0]  r_gap_r;
    reg        r_stall_q;

    int        w_expect;                  // 当前 AW burst 剩余拍数
    bit [31:0] w_cur_addr;
    int        b_push_cnt;                // 已入 B 队的写请求序号

    int        w_run_cnt;                 // WREADY 间歇计数
    int        w_st_cnt;
    int        b_gap_r;

    int        lfsr_r;

    longint unsigned r_beat_tot;
    int        aw_out_cnt, ar_out_cnt;

    assign rd_cnt = rd_n;
    assign wr_cnt = wr_n;

    function automatic bit [63:0] rd_word(input bit [31:0] a);
        bit [28:0] key = a[31:3];
        if (mem.exists(key))
            return mem[key];
        return 64'd0;
    endfunction

    function automatic bit mem_hit(input bit [31:0] a);
        return mem.exists(a[31:3]);
    endfunction

    // RRESP：当拍是否为注入拍（1 基全局拍号；隐式位宽折算）
    wire r_fault_now = (cfg_fault_r_beat != 0) &&
                       ((r_beat_tot + 1) == cfg_fault_r_beat);

    // ---- preload ----
    task automatic load_preload(string p);
        int fd, n;
        bit [31:0] a; bit [63:0] d; bit [7:0] s;
        begin
            fd = $fopen(p, "r");
            if (fd == 0) begin
                $display("FATAL: open preload %s failed", p);
                $finish;
            end
            ld_n = 0;
            forever begin
                n = $fscanf(fd, "%h %h %h\n", a, d, s);
                if (n != 3) break;
                for (int j = 0; j < 8; j++)
                    if (s[j]) mem[a[31:3]][8*j +: 8] = d[8*j +: 8];
                ld_n++;
            end
            $fclose(fd);
            $display("[BFM] preload %0d beats from %s", ld_n, p);
        end
    endtask

    task automatic clear_logs;
        begin
            // V1.2：只清计数保留容量（xsim 免重分配；内容按计数失效）
            rd_n = 0; wr_n = 0;
            r_beat_tot = 0; b_push_cnt = 0;
        end
    endtask

    // ---- 组合 R 拍呈现 ----
    always @* begin
        rdata_o = rd_word(r_addr_r);
        rresp_o = r_fault_now ? cfg_fault_r_resp : RESP_OKAY;
        rlast_o = r_run && (r_left_r == 4'd0);
    end

    // ---- 拍日志（V1.2：容量翻倍，总量 O(N)；原逐拍 new[n+1] 为 O(N²)
    //      分配 churn，xsim 引擎实测 1.1GB 撞墙，ModelSim 恰能扛）----
    function automatic void log_rd(input bit [31:0] a);
        begin
            if (rd_n == rd_cap) begin
                rd_cap = (rd_cap == 0) ? 4096 : rd_cap * 2;
                rd_addr_lg = new[rd_cap](rd_addr_lg);
                rd_data_lg = new[rd_cap](rd_data_lg);
            end
            rd_addr_lg[rd_n] = a;
            rd_data_lg[rd_n] = rd_word(a);
            rd_n++;
        end
    endfunction

    function automatic void log_wr(input bit [31:0] a, input bit [63:0] d,
                                   input bit [7:0] s);
        begin
            if (wr_n == wr_cap) begin
                wr_cap = (wr_cap == 0) ? 4096 : wr_cap * 2;
                wr_addr_lg = new[wr_cap](wr_addr_lg);
                wr_data_lg = new[wr_cap](wr_data_lg);
                wr_strb_lg = new[wr_cap](wr_strb_lg);
            end
            wr_addr_lg[wr_n] = a; wr_data_lg[wr_n] = d; wr_strb_lg[wr_n] = s;
            wr_n++;
        end
    endfunction

    wire w_fire = wvalid_i && wready_o;
    wire b_fire = bvalid_o && bready_i;

    always @(posedge clk_i) begin
        bit [31:0] a_cur;
        int        exp_cur;
        if (rst_i) begin
            arready_o <= 1'b0; awready_o <= 1'b0; wready_o <= 1'b0;
            bvalid_o <= 1'b0; bresp_o <= RESP_OKAY;
            rvalid_o <= 1'b0; r_run <= 1'b0; r_gap_r <= 0; r_stall_q <= 1'b0;
            r_addr_r <= 32'd0; r_left_r <= 4'd0;
            w_expect <= 0; w_cur_addr <= 32'd0;
            w_run_cnt <= 0; w_st_cnt <= 0;
            r_beat_tot = 0; b_push_cnt = 0;   // 故障注入按测试窗重起
            lfsr_r <= 32'h5A33C71E;
            proto_err <= 0; unloaded_cnt <= 0;
            ar_addr_q.delete(); ar_len_q.delete();
            aw_addr_q.delete(); aw_len_q.delete(); b_resp_q.delete();
        end else begin
            lfsr_r <= lfsr_r * 1664525 + 1013904223;

            // ---- AR 接受 ----
            arready_o <= ((lfsr_r[7:5]) != 3'b000);
            if (arready_o && arvalid_i) begin
                if (cfg_check_en) begin
                    if (araddr_i[2:0] != 3'd0)
                        proto_err <= proto_err + 1;
                    if ((araddr_i[11:0] + {8'd0, arlen_i} + 12'd1) > 13'h1000)
                        proto_err <= proto_err + 1;
                end
                ar_addr_q.push_back(araddr_i);
                ar_len_q.push_back(arlen_i);
            end

            // ---- R 发射 ----
            if (cfg_stall_after != 0 && r_beat_tot >= cfg_stall_after)
                r_stall_q <= 1'b1;
            if (rvalid_o && rready_i) begin
                if (!mem_hit(r_addr_r)) begin
                    unloaded_cnt <= unloaded_cnt + 1;
                    if (cfg_check_en)
                        $display("[BFM] WARN read unloaded @%08X t=%0t",
                                 r_addr_r, $time);
                end
                log_rd(r_addr_r);
                r_beat_tot <= r_beat_tot + 1;
                if (r_stall_q) begin
                    // V1.1：永停须拍间生效——原实现仅拦新 burst 首拍，
                    // 单 burst 8 拍连续流内 rvalid 不落，stall 形同虚设
                    // （D3 desc106 单 burst 8 拍全交付实测）；交付本拍后
                    // 撤 rvalid 且不再续拍（AXI 拍间 wait 合法，burst 冻结）。
                    rvalid_o <= 1'b0;
                end else if (r_left_r == 4'd0) begin
                    rvalid_o <= 1'b0;
                    r_run <= 1'b0;
                    r_gap_r <= (lfsr_r[15:8] % (cfg_r_lat + 1));
                end else begin
                    r_addr_r <= r_addr_r + 32'd8;
                    r_left_r <= r_left_r - 4'd1;
                end
            end else if (!rvalid_o && !r_stall_q &&
                         ar_addr_q.size() > 0 && r_gap_r == 0) begin
                rvalid_o <= 1'b1;
                r_run    <= 1'b1;
                r_addr_r <= ar_addr_q[0];
                r_left_r <= ar_len_q[0];
                ar_addr_q.pop_front();
                ar_len_q.pop_front();
            end else if (!rvalid_o && r_gap_r != 0) begin
                r_gap_r <= r_gap_r - 1;
            end

            // ---- AW 接受 ----
            awready_o <= ((lfsr_r[19:17]) != 3'b000);
            if (awready_o && awvalid_i) begin
                if (cfg_check_en) begin
                    if (awaddr_i[2:0] != 3'd0)
                        proto_err <= proto_err + 1;
                    if ((awaddr_i[11:0] + {8'd0, awlen_i} + 12'd1) > 13'h1000)
                        proto_err <= proto_err + 1;
                end
                aw_addr_q.push_back(awaddr_i);
                aw_len_q.push_back(awlen_i);
            end

            // ---- WREADY 图样 ----
            if (cfg_w_stall > 0) begin
                if (w_st_cnt != 0)
                    w_st_cnt <= w_st_cnt - 1;
                else if (w_run_cnt >= 4) begin
                    w_st_cnt  <= cfg_w_stall - 1;
                    w_run_cnt <= 0;
                end
                wready_o <= (w_st_cnt == 0);
                if (w_fire) w_run_cnt <= w_run_cnt + 1;
            end else begin
                wready_o <= ((lfsr_r[23:21]) != 3'b000);
            end

            // ---- W 拍（新 burst 首拍同拍解析 AW 队首）----
            if (w_fire) begin
                // V1.3：全零 strobe 拍在 master 错误排干窗（cfg_zero_strb_ok=1）
                // 为合法 AXI no-op 豁免；未连通/0 时保持全严（原检查语义）。
                if (cfg_check_en && (wstrb_i == 8'd0) &&
                    (cfg_zero_strb_ok !== 1'b1))
                    proto_err <= proto_err + 1;
                if (cfg_check_en && (((wstrb_i + 8'd1) & wstrb_i) != 8'd0))
                    proto_err <= proto_err + 1;
                if (w_expect == 0) begin
                    if (aw_addr_q.size() > 0) begin
                        a_cur  = aw_addr_q[0];
                        exp_cur = aw_len_q[0] + 1;
                        aw_addr_q.pop_front();
                        aw_len_q.pop_front();
                    end else begin
                        if (cfg_check_en)
                            proto_err <= proto_err + 1;  // 无 AW 陪衬
                        a_cur = 32'hFFFF_FFF8;           // 标记弃置
                        exp_cur = 1;
                    end
                end else begin
                    a_cur   = w_cur_addr;
                    exp_cur = w_expect;
                end
                // WLAST 必与 burst 末拍同拍
                if (cfg_check_en && (wlast_i != (exp_cur == 1)))
                    proto_err <= proto_err + 1;
                // 合并内存 + 日志
                for (int j = 0; j < 8; j++)
                    if (wstrb_i[j])
                        mem[a_cur[31:3]][8*j +: 8] = wdata_i[8*j +: 8];
                log_wr(a_cur, wdata_i, wstrb_i);
                if (wlast_i && exp_cur == 1) begin
                    b_push_cnt = b_push_cnt + 1;         // burst 完成 → B
                    b_resp_q.push_back(
                        (cfg_fault_b_req != 0 &&
                         b_push_cnt == cfg_fault_b_req)
                        ? RESP_DECERR : RESP_OKAY);
                    w_expect   <= 0;
                end else begin
                    w_expect   <= exp_cur - 1;
                end
                w_cur_addr <= a_cur + 32'd8;
            end

            // ---- B 发射 ----
            if (b_fire) begin
                bvalid_o <= 1'b0;
                if (b_resp_q.size() > 0)
                    b_resp_q.pop_front();
            end
            if (!bvalid_o && b_resp_q.size() > 0) begin
                if (cfg_b_delay > 0) begin
                    if (b_gap_r == 0) begin
                        bvalid_o <= 1'b1;
                        bresp_o  <= b_resp_q[0];
                    end else
                        b_gap_r <= b_gap_r - 1;
                end else begin
                    bvalid_o <= 1'b1;
                    bresp_o  <= b_resp_q[0];
                end
            end else if (!bvalid_o && b_resp_q.size() == 0) begin
                b_gap_r <= cfg_b_delay[7:0];
            end

            // ---- 在途检查 ----
            ar_out_cnt = ar_addr_q.size() + (r_run ? 1 : 0);
            aw_out_cnt = aw_addr_q.size() + ((w_expect != 0) ? 1 : 0)
                         + (bvalid_o ? 1 : 0);
            if (cfg_check_en && (ar_out_cnt > 4 || aw_out_cnt > 4))
                proto_err <= proto_err + 1;
        end
    end

endmodule
