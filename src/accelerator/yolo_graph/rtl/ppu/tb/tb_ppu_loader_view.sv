/************************************************************************
 * File Name       : tb_ppu_loader_view.sv
 * Developer       : LSL
 * Date            : 2026-09-23
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : tb_ppu_loader_view
 * Description     : ppu_loader V2.0 定长扫描门（指示④；11 类向量）。
 *                   黄金值 = view_vectors.txt（f3_prep.loader_mirror
 *                   生成；hw==0 域 V1.3 合同）。直驱 loader 端口（组包
 *                   规则转录自 ppu_desc_if.v）。
 *
 *   判定强度（不能只查不超时）：
 *     - 逐向量判决值（pass/err_step/err_bit/err_code）比对；
 *     - 判决时延精确检查（V2.0 定长推导值）：非 view=41 拍（步 1-8
 *       顺序扫描 + 判决沿）、view 快判=42 拍（+步 9 前置/快判沿）、
 *       view 迭代=70 拍（41+1 装载+28 轮）。早出（<exp，证明顺序
 *       检查未发生/老组合路径残留）、晚出、缺席均 FAIL；
 *     - 单脉冲检查（判决窗 exp+2 内无第二脉冲）；
 *     - 序列 4 条（类 10/11）：扫描中 reset、busy 期间新请求忽略
 *       （含换输入不污染锁存）、div→fast 背靠背、错误后恢复。
 *   黄金向量由 gen_view_vectors.py 生成；本 TB 不自带期望值。
 * Dependencies    : ppu_loader.v、view_vectors.txt（VEC=plusarg）。
 * Revision History:
 *   - V1.0 (2026-09-23) by LSL : A+ Stage 3 首版（V1.4 快=1/迭代=29）。
 *   - V2.0 (2026-09-24) by LSL : 指示④ V2.0 定长扫描——时延常数改
 *       41/42/70（推导见 ppu_loader.v V2.0 头注）；期望拍数按向量
 *       (div 类/view 算子) 自动推导；早出检查从"迭代类 +1 拍静默"
 *       推广为"全部向量 exp 拍前静默"。判定值/单脉冲/序列语义不变。
 ************************************************************************/
`timescale 1ns / 1ps

module tb_ppu_loader_view;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg valid = 1'b0;
    always #5 clk = ~clk;                      // 100 MHz

    // ---- bundle 驱动（组包规则转录自 ppu_desc_if.v）----
    reg  [7:0]   b_opcode  = 8'h0;
    reg  [15:0]  b_w0      = 16'h0;
    reg  [7:0]   b_desc_id = 8'h0;
    reg  [9:0]   b_in0 = 10'd0, b_in1 = 10'd0, b_out = 10'd0;
    reg  [15:0]  b_c = 16'd0, b_h = 16'd0, b_w = 16'd0, b_nseg = 16'd0;
    reg  [31:0]  b_out_bytes = 32'd0;
    reg  [7:0]   b_seg_present = 8'h0;
    reg  [79:0]  b_seg_prof   = 80'h0;
    reg  [255:0] b_seg_len    = 256'h0;
    reg  [703:0] sb_base      = 704'h0;
    reg  [351:0] sb_size      = 352'h0;
    reg  [351:0] sb_stride    = 352'h0;
    reg  [175:0] sb_c = 176'h0, sb_h = 176'h0, sb_w = 176'h0;
    reg  [10:0]  sb_valid = 11'h0, sb_fetched = 11'h0;
    reg  [87:0]  sb_prod  = 88'h0;
    reg  [9:0]   q_fetched = 10'h0;

    wire        pass_o, err_valid_o;
    wire [3:0]  err_step_o, err_bit_o;
    wire [7:0]  err_code_o;

    ppu_loader dut (
        .clk_i(clk), .rst_i(rst), .valid_i(valid),
        .b_opcode_i(b_opcode), .b_w0_i(b_w0), .b_desc_id_i(b_desc_id),
        .b_in0_i(b_in0), .b_in1_i(b_in1), .b_out_i(b_out),
        .b_c_i(b_c), .b_h_i(b_h), .b_w_i(b_w), .b_nseg_i(b_nseg),
        .b_out_bytes_i(b_out_bytes),
        .b_seg_present_i(b_seg_present), .b_seg_prof_i(b_seg_prof),
        .b_seg_len_i(b_seg_len),
        .sb_base_i(sb_base), .sb_size_i(sb_size), .sb_stride_i(sb_stride),
        .sb_c_i(sb_c), .sb_h_i(sb_h), .sb_w_i(sb_w),
        .sb_valid_i(sb_valid), .sb_fetched_i(sb_fetched),
        .sb_prod_i(sb_prod), .q_fetched_i(q_fetched),
        .pass_o(pass_o), .err_valid_o(err_valid_o),
        .err_step_o(err_step_o), .err_bit_o(err_bit_o),
        .err_code_o(err_code_o)
    );

    integer errors = 0;
    integer nvec = 0;

    // ---- 向量存储（读文件一次，全部驻留；序列可复用）----
    // 名字用 packed 向量（xsim $fscanf %s 不接受 string 型出参——正典
    // TB 仅 %h；%s 落 packed 右对齐零填充，与字符串字面量比较安全）
    reg  [8*32-1:0] v_name [0:63];
    reg  [7:0]  v_op  [0:63];
    reg  [15:0] v_w0  [0:63];
    reg  [7:0]  v_id  [0:63];
    reg  [15:0] v_c   [0:63], v_h [0:63], v_w [0:63], v_nseg [0:63];
    reg  [31:0] v_ob  [0:63];
    reg  [703:0] v_base [0:63];
    reg  [351:0] v_size [0:63], v_strd [0:63];
    reg  [175:0] v_sc [0:63], v_sh [0:63], v_sw [0:63];
    reg  [10:0]  v_sval [0:63], v_sfet [0:63];
    reg  [87:0]  v_sprod [0:63];
    reg  v_ev   [0:63];
    reg  [3:0]  v_es [0:63], v_eb [0:63];
    reg  [7:0]  v_ec [0:63];
    reg  v_div  [0:63];

    function integer findv(input [8*32-1:0] nm);
        integer k;
        begin
            findv = -1;
            for (k = 0; k < nvec; k = k + 1)
                if (v_name[k] == nm) findv = k;
        end
    endfunction

    task automatic apply_vec(input integer k);
        begin
            b_opcode    = v_op[k];
            b_w0        = v_w0[k];
            b_desc_id   = v_id[k];
            b_c         = v_c[k];
            b_h         = v_h[k];
            b_w         = v_w[k];
            b_nseg      = v_nseg[k];
            b_out_bytes = v_ob[k];
            sb_base     = v_base[k];
            sb_size     = v_size[k];
            sb_stride   = v_strd[k];
            sb_c        = v_sc[k];
            sb_h        = v_sh[k];
            sb_w        = v_sw[k];
            sb_valid    = v_sval[k];
            sb_fetched  = v_sfet[k];
            sb_prod     = v_sprod[k];
        end
    endtask

    task automatic check(input integer k, input integer cnt);
        begin
            if (v_ev[k] == 1'b0) begin
                if (pass_o !== 1'b1 || err_valid_o !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL verdict %0s lat=%0d: expect PASS, got pass=%b ev=%b (s=%0d)",
                             v_name[k], cnt, pass_o, err_valid_o, err_step_o);
                end else begin
                    $display("VEC %0s PASS lat=%0d", v_name[k], cnt);
                end
            end else begin
                if (err_valid_o !== 1'b1 || pass_o !== 1'b0 ||
                    err_step_o !== v_es[k] || err_bit_o !== v_eb[k] ||
                    err_code_o !== v_ec[k]) begin
                    errors = errors + 1;
                    $display("FAIL verdict %0s lat=%0d: expect ERR s=%0d b=%0d c=%02h, got ev=%b pass=%b s=%0d b=%0d c=%02h",
                             v_name[k], cnt, v_es[k], v_eb[k], v_ec[k],
                             err_valid_o, pass_o, err_step_o, err_bit_o, err_code_o);
                end else begin
                    $display("VEC %0s ERR s=%0d b=%0d c=%02h lat=%0d",
                             v_name[k], v_es[k], v_eb[k], v_ec[k], cnt);
                end
            end
        end
    endtask

    // ---- V2.0 定长时延推导（ppu_loader.v V2.0 头注时延表）----
    localparam [7:0]  OP_VIEW    = 8'h10;
    localparam integer LAT_NONVIEW  = 41;  // 非 view：步 1-8 扫描 + 判决沿
    localparam integer LAT_VIEWFAST = 42;  // view 快判（步1-8错/步9快错/hw0过）
    localparam integer LAT_DIV      = 70;  // view 迭代（41+1 装载+28 轮）

    function automatic integer explat(input integer k);
        begin
            if      (v_div[k])           explat = LAT_DIV;
            else if (v_op[k] == OP_VIEW) explat = LAT_VIEWFAST;
            else                         explat = LAT_NONVIEW;
        end
    endfunction

    // 单向量：valid 恰 1 拍 → 时延精确判定（V2.0 定长）→ 单脉冲检查
    task automatic run_vector(input integer k);
        integer cnt, exp, gotv;
        begin
            apply_vec(k);
            @(negedge clk);
            valid <= 1'b1;
            @(negedge clk);                       // P1 = valid 锁存沿已过
            valid <= 1'b0;
            exp  = explat(k);
            cnt  = 1;                             // N1 = 1（V1.0 计数约定保持）
            gotv = 0;
            // exp+2 拍窗：恰在 exp 拍出判决；早出/晚出/缺席/第二脉冲均 FAIL
            while (cnt < exp + 2) begin
                @(negedge clk);
                cnt = cnt + 1;
                if (!gotv && (pass_o !== 1'b0 || err_valid_o !== 1'b0)) begin
                    gotv = 1;
                    if (cnt != exp) begin
                        errors = errors + 1;
                        $display("FAIL latency %0s: 判决在 %0d 拍出现 != 期望 %0d",
                                 v_name[k], cnt, exp);
                    end
                    check(k, cnt);
                end else if (gotv && (pass_o !== 1'b0 || err_valid_o !== 1'b0)) begin
                    errors = errors + 1;
                    $display("FAIL multi-pulse %0s: 判决非单脉冲 @%0d",
                             v_name[k], cnt);
                end
            end
            if (!gotv) begin
                errors = errors + 1;
                $display("FAIL timeout %0s: %0d 拍窗内无判决", v_name[k], exp + 2);
            end
        end
    endtask

    // ---- 序列 1（类 10）：扫描中 reset → 清态回 IDLE → 重跑同向量 ----
    // （V2.0：+10 拍 ≈ 步 4 槽 3-4 扫描中；原 V1.0 为迭代中，语义同）
    task automatic seq_reset_mid_div(input integer k);
        integer j;
        begin
            $display("SEQ reset-mid-scan on %0s", v_name[k]);
            apply_vec(k);
            @(negedge clk);
            valid <= 1'b1;
            @(negedge clk);
            valid <= 1'b0;
            for (j = 0; j < 9; j = j + 1) @(negedge clk);   // 第 ~10 拍（扫描中）
            rst <= 1'b1;
            @(negedge clk);
            @(negedge clk);
            rst <= 1'b0;
            if (pass_o !== 1'b0 || err_valid_o !== 1'b0 || err_step_o !== 4'd0) begin
                errors = errors + 1;
                $display("FAIL reset-mid-scan %0s: 复位后输出未清（pass=%b ev=%b s=%0d）",
                         v_name[k], pass_o, err_valid_o, err_step_o);
            end
            @(negedge clk);
            @(negedge clk);
            if (pass_o !== 1'b0 || err_valid_o !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL reset-mid-scan %0s: 复位后有残留脉冲", v_name[k]);
            end
            run_vector(k);                        // 恢复：同向量重跑正确
        end
    endtask

    // ---- 序列 2（类 11a）：busy（扫描中）新请求忽略 + 换输入不污染 ----
    task automatic seq_busy_ignore(input integer ka, input integer kb);
        integer cnt, j, expa;
        begin
            $display("SEQ busy-ignore A=%0s B=%0s", v_name[ka], v_name[kb]);
            expa = explat(ka);
            apply_vec(ka);
            @(negedge clk);
            valid <= 1'b1;
            @(negedge clk);
            valid <= 1'b0;
            cnt = 1;
            @(negedge clk); cnt = cnt + 1;        // +2
            @(negedge clk); cnt = cnt + 1;        // +3
            @(negedge clk); cnt = cnt + 1;        // +4
            @(negedge clk); cnt = cnt + 1;        // +5：步 4 扫描中
            apply_vec(kb);                        // 换输入 + 新 valid（应忽略）
            valid <= 1'b1;
            @(negedge clk);
            valid <= 1'b0;
            cnt = cnt + 1;
            while ((pass_o === 1'b0 && err_valid_o === 1'b0) && cnt < 96)
                begin
                    @(negedge clk);
                    cnt = cnt + 1;
                end
            if (cnt >= 96) begin
                errors = errors + 1;
                $display("FAIL busy-ignore timeout: 96 拍无判决");
            end else begin
                check(ka, cnt);                   // 判决必须属于 A（锁存不污染）
                if (cnt != expa) begin
                    errors = errors + 1;
                    $display("FAIL busy-ignore latency: %0d != %0d", cnt, expa);
                end
            end
            for (j = 0; j < 34; j = j + 1) begin  // 无第二脉冲
                @(negedge clk);
                if (pass_o !== 1'b0 || err_valid_o !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL busy-ignore: 判决后出现多余脉冲 @%0d", j);
                end
            end
            run_vector(kb);                       // B 正常补跑
        end
    endtask

    // ---- 序列 3（类 11b）：div 判决拍上背靠背挂快向量 ----
    task automatic seq_back_to_back(input integer ka, input integer kb);
        integer cnt, expb, gotv;
        begin
            $display("SEQ back-to-back A=%0s(div) B=%0s(fast)", v_name[ka], v_name[kb]);
            expb = explat(kb);
            apply_vec(ka);
            @(negedge clk);
            valid <= 1'b1;
            @(negedge clk);
            valid <= 1'b0;
            cnt = 1;                              // N1 = 1（与 run_vector 同约定）
            while ((pass_o === 1'b0 && err_valid_o === 1'b0) && cnt < 96) begin
                @(negedge clk);
                cnt = cnt + 1;
            end
            check(ka, cnt);
            if (cnt != LAT_DIV) begin
                errors = errors + 1;
                $display("FAIL back-to-back A latency: %0d != %0d", cnt, LAT_DIV);
            end
            apply_vec(kb);                        // 同拍挂 B（active 已清）
            valid <= 1'b1;
            @(negedge clk);
            valid <= 1'b0;
            cnt = 1;                              // N1' = 1（B 锁存沿 P_B1 已过）
            gotv = 0;                             // （localpat 同 run_vector）
            while (cnt < expb + 2) begin
                @(negedge clk);
                cnt = cnt + 1;
                if (!gotv && (pass_o !== 1'b0 || err_valid_o !== 1'b0)) begin
                    gotv = 1;
                    if (cnt != expb) begin
                        errors = errors + 1;
                        $display("FAIL back-to-back B latency %0s: %0d 拍 != %0d",
                                 v_name[kb], cnt, expb);
                    end
                    check(kb, cnt);
                end else if (gotv && (pass_o !== 1'b0 || err_valid_o !== 1'b0)) begin
                    errors = errors + 1;
                    $display("FAIL back-to-back B multi-pulse %0s", v_name[kb]);
                end
            end
            if (!gotv) begin
                errors = errors + 1;
                $display("FAIL back-to-back B timeout %0s", v_name[kb]);
            end
        end
    endtask

    // ---- 主流程 ----
    string vecpath;
    reg [8*32-1:0] nm;
    reg [7:0] clsc;
    integer fd, code, k, ndiv;
    reg [31:0] f0bh, f0bl, f2bh, f2bl;    // base 高/低字：文件按两个 token 落
    reg [31:0] f0s, f0t, f2s, f2t;
    reg [15:0] f0c, f0h, f0w, f2c, f2h, f2w;
    reg [7:0]  f0p, f2p, segp, ec;
    reg        f0v, f2v, f0f, f2f, ev, qf;
    reg [3:0]  es, eb;                      // estep/ebit 是 1 位 hex 数字（dbg 实证 1b 截断）
    reg [79:0] segprof;
    reg [255:0] seglen;
    reg [7:0]  op, did;
    reg [15:0] w0, cc, hh, ww, ns;
    reg [31:0] ob;

    initial begin
        if (!$value$plusargs("VEC=%s", vecpath)) begin
            $display("EES_VIVADO_RESULT FAIL tb_ppu_loader_view no-VEC-plusarg");
            $finish;
        end
        fd = $fopen(vecpath, "r");
        if (fd == 0) begin
            $display("EES_VIVADO_RESULT FAIL tb_ppu_loader_view open-failed %s",
                     vecpath);
            $finish;
        end
        ndiv = 0;
        // 读全部向量（38 字段/行）
        forever begin
            // 38 个转换 = %s(名) + 36×%h(op..ec，base 拆 hi/lo 两 token)
            //   + %s(延迟类)；dbg_scanf 实证格式须与文件 token 数严格对齐
            code = $fscanf(fd,
                "%s %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %s",
                nm, op, w0, did, cc, hh, ww, ns, ob,
                segp, segprof, seglen, qf,
                f0bh, f0bl, f0s, f0t, f0c, f0h, f0w, f0v, f0p, f0f,
                f2bh, f2bl, f2s, f2t, f2c, f2h, f2w, f2v, f2p, f2f,
                ev, es, eb, ec, clsc);
            if (code != 38) break;                // EOF / 格式不符
            v_name[nvec] = nm;
            v_op[nvec] = op; v_w0[nvec] = w0; v_id[nvec] = did;
            v_c[nvec] = cc; v_h[nvec] = hh; v_w[nvec] = ww;
            v_nseg[nvec] = ns; v_ob[nvec] = ob;
            v_base[nvec]  = {512'b0, f2bh, f2bl, 64'b0, f0bh, f0bl};
            v_size[nvec]  = {256'b0, f2s, 32'b0, f0s};
            v_strd[nvec]  = {256'b0, f2t, 32'b0, f0t};
            v_sc[nvec]    = {128'b0, f2c, 16'b0, f0c};
            v_sh[nvec]    = {128'b0, f2h, 16'b0, f0h};
            v_sw[nvec]    = {128'b0, f2w, 16'b0, f0w};
            v_sval[nvec]  = {8'b0, f2v, 1'b0, f0v};
            v_sfet[nvec]  = {8'b0, f2f, 1'b0, f0f};
            v_sprod[nvec] = {64'b0, f2p, 8'b0, f0p};
            v_ev[nvec] = ev;
            v_es[nvec] = {3'b0, es};
            v_eb[nvec] = {3'b0, eb};
            v_ec[nvec] = ec;
            v_div[nvec] = (clsc == "d");
            if (v_div[nvec]) ndiv = ndiv + 1;
            nvec = nvec + 1;
            if (nvec >= 64) break;
        end
        $fclose(fd);
        if (nvec == 0) begin
            $display("EES_VIVADO_RESULT FAIL tb_ppu_loader_view empty-vector-file");
            $finish;
        end
        $display("TB_INFO vectors=%0d div=%0d", nvec, ndiv);

        // 复位释放
        repeat (4) @(negedge clk);
        rst <= 1'b0;
        repeat (2) @(negedge clk);
        if (pass_o !== 1'b0 || err_valid_o !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL idle: 复位后判决非零");
        end

        // ---- 全向量主循环（含步 1-8 早错 × 步 9 错同存优先级）----
        for (k = 0; k < nvec; k = k + 1) run_vector(k);

        // ---- 序列（类 10/11）----
        seq_reset_mid_div(findv("v03_mult_fail"));
        seq_busy_ignore(findv("v05_over_c_fail"), findv("v15_conv_pass_fast"));
        seq_back_to_back(findv("v01_off0_pass"), findv("v15_conv_pass_fast"));
        // 错误后恢复（类 11c）：err1 → PASS(div) → err9(div) → PASS(fast)
        run_vector(findv("v16_early_op_fail"));
        run_vector(findv("v01_off0_pass"));
        run_vector(findv("v05_over_c_fail"));
        run_vector(findv("v15_conv_pass_fast"));

        // 尾静默
        for (k = 0; k < 40; k = k + 1) begin
            @(negedge clk);
            if (pass_o !== 1'b0 || err_valid_o !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL tail: 空闲期出现判决脉冲");
            end
        end

        if (errors == 0)
            $display("EES_VIVADO_RESULT PASS tb_ppu_loader_view vectors=%0d seq=4",
                     nvec);
        else
            $display("EES_VIVADO_RESULT FAIL tb_ppu_loader_view errors=%0d",
                     errors);
        $finish;
    end

endmodule
