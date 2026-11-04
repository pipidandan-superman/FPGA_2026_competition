/************************************************************************
 * File Name       : ppu_add_engine.v
 * Developer       : LSL
 * Date            : 2026-09-24
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_add_engine
 * Description     : PPU-F5 Add 引擎（单描述符）——两路独立读 FIFO
 *                   会合 + 五级流水逐字节双 requant 求和，输出走
 *                   ppu_byte_store_assembler，经 ppu_dma_master 搬移。
 *
 *   语义（probe 实测 desc7/16/19/28/31/40，intref 权威）：0x11 双输入
 *   同形相加——A_ = rne(a·m0, s0)，B_ = rne(b·m1, s1)，
 *   y = sat_i8(A_ + B_)；m0/s0 = quant[prof_in0]（bundle 槽 0）、
 *   m1/s1 = quant[prof_in1]（槽 1），随 descriptor 锁存。V2.1 起 CHW
 *   取 w14 元数据直入（=in0/in1/out.size，见 chw_i 口注；形状口已撤）。
 *
 *   V2.0 五级流水（Stage3-v3 Phase B，裁定 v3 第一阶段）：
 *     A（join 捕获：LUTRAM 头字节→a1/b1 寄存，rp 双弹+pop_cnt）
 *     B1（4×DSP48E1 并行部分积：m = m_hi_s·2^16 + m_lo_u，每侧
 *         8×16 两乘，|plo|<2^23、|phi|≤2^22 均落 24b）
 *     B2（64b 域先拓宽后 <<<16 移位合并→pa/pb）
 *     C1（移位+RNE 照抄 V1.1 表达式，10.1c 移位独立 wire 律）
 *     C2（sum+sat_i8→y）。
 *     stall_w = v5 && !asm_rdy（只看末级 valid 与 assembler ready），
 *     advance_w = !stall_w 为全流水/双弹/pop_cnt 的唯一 CE；所有级
 *     CE-mux 编码（advance 时装载/移位，停顿保持），禁独立置位/清零。
 *     v1..v5 打包 vch_r（bit0=v1..bit4=v5），任务边界（asm_start_r/
 *     dma_err）清 v 链——dma_err 必需（堵残留 v5 把垃圾字节推进下
 *     任务 assembler），asm_start_r 免费附带；数据寄存器（a1、p_xx、
 *     pa、q0、y）不复位，消费全 v 门控（参考核 yolo_ppu_add 已验证模式）。
 *     完成判据 = pop_cnt==CHW && 两 FIFO 空 && 两 funnel 空 &&
 *     vch==0（打包约简，漏一位即静默丢尾字节）→ asm_flush。
 *
 *   协议变化（对外仅一项）：done 晚 5 拍（流水填充）。DMA 读序/
 *   wr 拍数/稳态吞吐 1B/拍不变（assembler 不 ready 窗口间隔 ≥8 拍
 *   > 5 级重填）；CHW=0/stop/abort/dma_err 外部语义全不变。
 *
 *   机制（replan §PPU-F5 第 3 条原文落地）：单 DMA 读口上两路
 *   64B 块交替读（A0,B0,A1,B1,…；一侧读尽后另一侧独跑）→ 各自
 *   独立字节 FIFO（FD=128）→ 会合拍两 FIFO 头字节同弹；
 *   q = rne(prod >>> s) 逐位等价 GEMM 尾 V2.2 idiom：
 *     ru = n[s-1] & (|n[s-2:0]|!=0 | n[s])（s=0 旁路，rem=0 恒不进位）
 *   **每侧 ready 只由本侧状态构成**（funnel 空 && 本侧 FIFO 空位≥8），
 *   无跨侧组合串扰（replan 禁令）；会合弹出以两侧皆非空为准——
 *   这是 Add 双操作数语义本身，非流控耦合。
 *
 *   容量不变式（结构性，无死锁）：
 *     块 64B ≤ FD-8：拍接受门槛 空位≥8，一拍 8B 入 funnel，逐拍
 *     1B 转灌 FIFO，funnel 非空期本侧 beat_ready 关闭 → 单块内 FIFO
 *     净增 ≤64 < 128，永不溢出；会合两侧同弹使两侧液位同速回落。
 *   交替调度只看剩余字节数（不看 FIFO 液位）→ 读序确定：
 *     A,B 交替 64B 块 + 尾块 min(64, rem)——金样按此序生成（rd 金样
 *     = 交替流；尾拍窗口按 8B 内存实像补零，preload force_ff 同源）。
 *
 *   DMA：先 wr_req(out_base, CHW)（写先行），读块交替随后；退化
 *   CHW=0 无搬移直通 done；dma_err/abort 任一推进态弃权回 IDLE
 *   无 done（shell 粘错上报，同构 engine_mux）。
 * Dependencies    : ppu_byte_store_assembler.v。
 * Revision History:
 *   - V1.0 (2026-09-22) by LSL : F5-Add 初版（单描述符门 F5AA）。
 *   - V1.1 (2026-09-22) by LSL : 修 wr 数据 bug——`(pa_w>>>s0_r)+
 *       {concat ru}` 内联式在 10.1c 下无符号性递归传染 >>> 左操作数，
 *       负 a 走逻辑填充→假 7f 饱和；改为移位独立 wire + 符号常量加 ru
 *       （GEMM 尾 V2.2 同款；微测试双向验证：负 fa 全部修复、正 fa
 *       位恒等）。
 *   - V2.1 (2026-09-24) by LSL : CHW 元数据直入（用户裁定条件性 A 指示③
 *       结构修）：chw_i（=desc w14/out_bytes，desc_if 已寄存）启动拍直锁
 *       chw_r/a_rem_r/b_rem_r 与退化判据，删除 c_i*h_i*w_i 三次乘（v16
 *       该锥 137 失败端点 worst -5.511 的源头；不变量 w14==槽0 c·h·w
 *       全语料 118/118 验证含 D1-3 负表）；c_i/h_i/w_i 端口随之撤销。
 *   - V2.0 (2026-09-24) by LSL : Stage3-v3 Phase B 五级流水化——
 *       join 拍全组合锥 18.708ns（carry4=15+dsp+ramd，终点
 *       u_asm/acc_r）拆 A/B1/B2/C1/C2 五级寄存边界（u_add 201 失败
 *       端点目标清零）。bring-up 影子对拍件在文末 synthesis
 *       translate_off 块内（全回归过后删除）。
 *   - V2.2 (2026-09-25) by LSL : P1.4 小桶轮——C1 的 rm 掩码准静态
 *       预算化（POST_V19_SYSTEM_PLAN §P1.4"RTL 显式等价寄存"落法）。
 *       v21 routed 残量 u_add 12 条 s0/s1_r_reg..rep → q0/q1_r/D
 *       （ll 34-36，dpd 10.20，logic 6.19 主导）逐级取证：最差路径
 *       s0 译码 1 级 LUT6 后直接进入 rm0=(1<<(s0-1))-1 的 64b 减法
 *       借位链（14 级 CARRY4 连续 1.7ns）再接 AND/OR/barrel/加法。
 *       整改：s0_r/s1_r 任务期间准静态（仅启动拍写，v17 起不变量），
 *       故 rm0/rm1 掩码在启动锁存拍（S_IDLE，当前组合余量充足）预算
 *       存入 rm0_q_r/rm1_q_r（各 64b，数据寄存器纪律不复位——消费
 *       侧 s0_nz_w 前导门控 + 每任务启动拍必装载），C1 改引用寄存器，
 *       译码+借位链整体移出数据路径。等价性：rm0_q_r 逐拍恒等于原
 *       rm0_w 组合值（s0_r 准静态）；C1 流水拍数/v 链/advance 零变化
 *       ⟹ lat 零漂移（F7B 台账应精确保持 v21 值）。
 *   - V3.0 (2026-10-23) by hwglobal G-04 : B1/B2 并入 4 DSP 的 PCIN
 *       级联（cut3 C1 唯一合规项落地，cut3 报告 :126/:133-134）——
 *       B2 级两条 64b fabric 拼接加（pp_pa_w/pp_pb_w 各 ~16 CARRY4
 *       锥）消失：pal DSP 照常出 a1·m_lo（PREG=1），pah DSP 的 A 口
 *       改喂 a1<<16（25b 有符号装下：|a1|≤128 → |a1<<16|≤2^23 < 2^24）
 *       使 M=(a1·m_hi)<<16，Z=PCIN 收 pal 的 P → pah P = 全积。
 *       数学：m = m_hi·2^16 + m_lo 精确二补码分解；无回绕 |a1·m|
 *       ≤128·(2^31-1) < 2^38 ≪ 2^47（48b 全幅）→ 结合律逐位恒等
 *       （cut3 :126 复核：值域/位宽/A 口几何三条全过，未推翻）。
 *       DSP Δ=0（4→4 原址改造，2+2 链）；拍对齐：pal P 于 e1、pah P
 *       于 e2，与原 pal/pah_r(e1)→pa_r(e2) 逐沿同位；DSP PREG 免 CE
 *       安全（stall 期上游 a1_r/m*_r CE 门控保持，DSP 输入稳定重算
 *       同值；气泡 v 门控下游消费，与原 CE-mux 编码等价）。
 *       pa_r/pb_r 维持 64b（48b P 符号扩展），C1/C2 下游逐字不动。
 * Dependencies    : ppu_byte_store_assembler.v / unisim DSP48E1（V3.0）。
 ************************************************************************/

module ppu_add_engine (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        start_i,           // loader pass 后启动（脉冲）
    input  wire [31:0] in0_base_i,        // A 路基址（槽 0 低字）
    input  wire [31:0] in1_base_i,        // B 路基址（槽 1 低字）
    input  wire [31:0] out_base_i,        // 输出基址（槽 2 低字）
    input  wire [31:0] chw_i,             // CHW 元数据（=desc w14/out_bytes，
                                          //   desc_if 已寄存输出；不变量
                                          //   w14==槽0 c·h·w 已全语料验证
                                          //   2026-09-24：118/118 含 D1-3）
    input  wire [31:0] m0_i,              // quant[prof_in0]（bundle 槽 0）
    input  wire [5:0]  s0_i,
    input  wire [31:0] m1_i,              // quant[prof_in1]（bundle 槽 1）
    input  wire [5:0]  s1_i,
    // DMA 接口
    output reg         rd_req_valid_o,
    input  wire        rd_req_ready_i,
    output reg  [31:0] rd_addr_o,
    output reg  [23:0] rd_len_o,
    input  wire        rd_beat_valid_i,
    output wire        rd_beat_ready_o,
    input  wire [63:0] rd_beat_data_i,
    input  wire        rd_done_i,
    output reg         wr_req_valid_o,
    input  wire        wr_req_ready_i,
    output reg  [31:0] wr_addr_o,
    output reg  [23:0] wr_len_o,
    output wire        wr_beat_valid_o,
    input  wire        wr_beat_ready_i,
    output wire [63:0] wr_beat_data_o,
    output wire [7:0]  wr_beat_strb_o,
    input  wire        wr_done_i,
    input  wire        dma_err_i,         // DMA 错误/abort（取消推进）
    output reg         done_o,            // 引擎完成（写妥语义，§4.2）
    output wire        busy_o
);

    localparam [3:0] S_IDLE=4'd0, S_WREQ=4'd1, S_RUN=4'd2,
                     S_FLUSH=4'd3, S_VDONE=4'd4;
    localparam integer FD    = 128;               // 每侧字节 FIFO 深
    localparam [31:0] CHUNK = 32'd64;             // 交替读块长（8 拍整）

    reg [3:0]  state_r;
    reg [31:0] in0_base_r, in1_base_r, out_base_r;
    reg [31:0] chw_r;                             // C·H·W（三槽同长）
    reg [31:0] m0_r, m1_r;                        // profile 随描述符锁存
    (* max_fanout = 24 *) reg [5:0] s0_r;         // 准静态（start 拍锁存）：
    (* max_fanout = 24 *) reg [5:0] s1_r;         //   高扇出 C1 移位控制网
    reg [63:0] rm0_q_r, rm1_q_r;                 // C1 RNE 掩码预算（V2.2：
                                                  //   =(1<<(s-1))-1 启动拍算
                                                  //   好；s 准静态故逐拍恒
                                                  //   等于原 C1 组合值）
                                                  //   复制减 net 延迟（OOC
                                                  //   归因：数据锥 +1.8ns，
                                                  //   仅 s 常量锥 -0.209）
    reg [31:0] pop_cnt_r;                         // 已准入（双弹）字节数
    reg        wr_done_all_r;

    // ---- 两侧读游标（剩读字节 / 已读偏移）----
    reg [31:0] a_rem_r, b_rem_r, a_off_r, b_off_r;
    reg        side_r;                            // 下一块属谁（交替）
    reg        reading_r;                         // 一块在途（req→done）
    reg        pend_side_r;                       // 已发请求侧（握手用）
    reg        cur_side_r;                        // 在途块侧（拍归属）
    reg [6:0]  cur_len_r;                         // 在途块长
    reg [6:0]  cur_rem_r;                         // 在途块未收字节

    // ---- 两侧 intake funnel（一拍 8B → 逐拍 1B 转灌 FIFO）----
    reg [63:0] fun_a_d_r, fun_b_d_r;
    reg [3:0]  fun_a_cnt_r, fun_b_cnt_r;          // 0..8

    // ---- 两侧独立字节 FIFO ----
    reg [7:0]  fa_mem [0:FD-1];
    reg [7:0]  fb_mem [0:FD-1];
    reg [6:0]  fa_wp_r, fb_wp_r, fa_rp_r, fb_rp_r;
    reg [7:0]  fa_lvl_r, fb_lvl_r;                // 0..128

    // ---- 拍接受（ready 只含本侧状态：funnel 空 && 空位≥8）----
    wire [7:0] fa_free_w = FD[7:0] - fa_lvl_r;
    wire [7:0] fb_free_w = FD[7:0] - fb_lvl_r;
    wire       fun_cur_emp_w = cur_side_r ? (fun_b_cnt_r == 4'd0)
                                          : (fun_a_cnt_r == 4'd0);
    wire [7:0] ffree_cur_w   = cur_side_r ? fb_free_w : fa_free_w;
    assign rd_beat_ready_o = (state_r == S_RUN) && reading_r &&
                             fun_cur_emp_w && (ffree_cur_w >= 8'd8);
    wire       beat_fire_w = rd_beat_valid_i && rd_beat_ready_o;
    wire [3:0] beat_nv_w   = (cur_rem_r > 4'd8) ? 4'd8
                                                : {1'b0, cur_rem_r[3:0]};

    // ---- funnel 转灌（1B/拍；funnel 非空期本侧不再收拍）----
    wire fun_a_dr_w = (fun_a_cnt_r != 4'd0);
    wire fun_b_dr_w = (fun_b_cnt_r != 4'd0);

    // ---- 会合弹出（两 FIFO 头同弹；assembler 握手经流水末级）----
    wire        asm_rdy_w, asm_idle_w;
    wire [7:0]  fa_q_w = fa_mem[fa_rp_r];
    wire [7:0]  fb_q_w = fb_mem[fb_rp_r];

    // ---- 全局流水控制：stall 只看末级 valid 与 assembler ready ----
    reg  [4:0]  vch_r;                           // v 链（bit0=v1..bit4=v5）
    wire stall_w   = vch_r[4] && !asm_rdy_w;      // v5 反压
    wire advance_w = !stall_w;                    // 全流水/双弹唯一 CE
    wire jnA_w     = (state_r == S_RUN) && (fa_lvl_r != 8'd0)
                   && (fb_lvl_r != 8'd0) && advance_w;
    wire dma_abort_w = dma_err_i && (state_r != S_IDLE)
                                  && (state_r != S_VDONE);

    // ---- A 级：join 捕获（断 LUTRAM→全锥；路径 rp→RAMD→a1_r）----
    reg  [7:0]   a1_r, b1_r;

    // ---- B1/B2 级：8×16 部分积 ×4 DSP48E1 改 2+2 PCIN 级联对
    //      （V3.0 G-04，cut3 C1；恒等证明/拍对齐/无回绕见头注）----
    // A/B 口位宽：A[29:0]（乘用 A[24:0]），B[17:0]；DSP 乘法恒二补码
    // 有符号——与原 $signed 行为一致。m_lo 17b 正数、m_hi 16b 带符号。
    wire [29:0] dsp_al_a_w  = {{22{a1_r[7]}}, a1_r};          // pal_a A=a1
    wire [29:0] dsp_ah_a_w  = {{6{a1_r[7]}}, a1_r, 16'b0};    // pah_a A=a1<<16
    wire [17:0] dsp_bl_a_w  = {1'b0, m0_r[15:0]};             // m0_lo（正）
    wire [17:0] dsp_bh_a_w  = {{2{m0_r[31]}}, m0_r[31:16]};   // m0_hi（带符号）
    wire [29:0] dsp_al_b_w  = {{22{b1_r[7]}}, b1_r};
    wire [29:0] dsp_ah_b_w  = {{6{b1_r[7]}}, b1_r, 16'b0};
    wire [17:0] dsp_bl_b_w  = {1'b0, m1_r[15:0]};
    wire [17:0] dsp_bh_b_w  = {{2{m1_r[31]}}, m1_r[31:16]};
    wire [47:0] dsp_pc_a_w, dsp_p_a_w;
    wire [47:0] dsp_pc_b_w, dsp_p_b_w;

    DSP48E1 #(
        .AREG(0), .BREG(0), .MREG(0), .PREG(0),
        .ACASCREG(0), .BCASCREG(0), .ADREG(0),
        .OPMODEREG(0), .INMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_dsp_al_a (
        .CLK(clk_i), .RSTP(1'b0), .CEP(1'b0),
        .A(dsp_al_a_w), .B(dsp_bl_a_w),
        .OPMODE(7'b0000101),                 // P = M（X=M, Y=0, Z=0）
        .ALUMODE(4'b0000), .INMODE(5'b00000), .CARRYINSEL(3'b000),
        .C(48'd0), .D(25'd0), .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0), .MULTSIGNIN(1'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0), .CED(1'b0),
        .CEINMODE(1'b0), .CEM(1'b0),
        .P(), .PCOUT(dsp_pc_a_w),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .UNDERFLOW(),
        .PATTERNDETECT(), .PATTERNBDETECT()
    );
    DSP48E1 #(
        .AREG(0), .BREG(0), .MREG(0), .PREG(1),
        .ACASCREG(0), .BCASCREG(0), .ADREG(0),
        .OPMODEREG(0), .INMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_dsp_ah_a (
        .CLK(clk_i), .RSTP(1'b0), .CEP(1'b1),
        .A(dsp_ah_a_w), .B(dsp_bh_a_w), .PCIN(dsp_pc_a_w),
        .OPMODE(7'b0010101),                 // P = M + PCIN（X=M, Z=PCIN）
        .ALUMODE(4'b0000), .INMODE(5'b00000), .CARRYINSEL(3'b000),
        .C(48'd0), .D(25'd0), .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .MULTSIGNIN(1'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0), .CED(1'b0),
        .CEINMODE(1'b0), .CEM(1'b0),
        .P(dsp_p_a_w), .PCOUT(),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .UNDERFLOW(),
        .PATTERNDETECT(), .PATTERNBDETECT()
    );
    DSP48E1 #(
        .AREG(0), .BREG(0), .MREG(0), .PREG(0),
        .ACASCREG(0), .BCASCREG(0), .ADREG(0),
        .OPMODEREG(0), .INMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_dsp_al_b (
        .CLK(clk_i), .RSTP(1'b0), .CEP(1'b0),
        .A(dsp_al_b_w), .B(dsp_bl_b_w),
        .OPMODE(7'b0000101),                 // P = M
        .ALUMODE(4'b0000), .INMODE(5'b00000), .CARRYINSEL(3'b000),
        .C(48'd0), .D(25'd0), .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .PCIN(48'd0), .MULTSIGNIN(1'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0), .CED(1'b0),
        .CEINMODE(1'b0), .CEM(1'b0),
        .P(), .PCOUT(dsp_pc_b_w),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .UNDERFLOW(),
        .PATTERNDETECT(), .PATTERNBDETECT()
    );
    DSP48E1 #(
        .AREG(0), .BREG(0), .MREG(0), .PREG(1),
        .ACASCREG(0), .BCASCREG(0), .ADREG(0),
        .OPMODEREG(0), .INMODEREG(0), .ALUMODEREG(0),
        .CARRYINREG(0), .CARRYINSELREG(0)
    ) u_dsp_ah_b (
        .CLK(clk_i), .RSTP(1'b0), .CEP(1'b1),
        .A(dsp_ah_b_w), .B(dsp_bh_b_w), .PCIN(dsp_pc_b_w),
        .OPMODE(7'b0010101),                 // P = M + PCIN
        .ALUMODE(4'b0000), .INMODE(5'b00000), .CARRYINSEL(3'b000),
        .C(48'd0), .D(25'd0), .CARRYIN(1'b0),
        .ACIN(30'd0), .BCIN(18'd0), .MULTSIGNIN(1'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEB1(1'b0), .CEB2(1'b0),
        .CEC(1'b0), .CECARRYIN(1'b0), .CECTRL(1'b0), .CED(1'b0),
        .CEINMODE(1'b0), .CEM(1'b0),
        .P(dsp_p_b_w), .PCOUT(),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .UNDERFLOW(),
        .PATTERNDETECT(), .PATTERNBDETECT()
    );

    // B2 级寄存：48b P 符号扩展回 64b（下游 C1/C2 表达式逐字不动）；
    // e2 沿位与原 pal/pah_r(e1)+拼接加(e2) 完全对齐（头注 V3.0）。
    wire signed [63:0] pp_pa_w = {{16{dsp_p_a_w[47]}}, dsp_p_a_w};
    wire signed [63:0] pp_pb_w = {{16{dsp_p_b_w[47]}}, dsp_p_b_w};
    reg  signed [63:0] pa_r, pb_r;                // int64 全积（=V1 直乘）

    // ---- C1 级：双 RNE 商（移位独立 wire 律保持；表达式照抄 V1.1）----
    wire        s0_nz_w = (s0_r != 6'd0);
    wire        s1_nz_w = (s1_r != 6'd0);
    wire [63:0] rm0_w = rm0_q_r;                 // V2.2 预算值直用（原
                                                  //   (1<<(s0_r-1))-1 译码
                                                  //   +64b 减借位链移至启动
                                                  //   拍；等价证明见头注）
    wire [63:0] rm1_w = rm1_q_r;
    wire        ru0_w = s0_nz_w && pa_r[s0_r - 6'd1] &&
                        ((|(pa_r & rm0_w)) || pa_r[s0_r]);
    wire        ru1_w = s1_nz_w && pb_r[s1_r - 6'd1] &&
                        ((|(pb_r & rm1_w)) || pb_r[s1_r]);
    // 商移位独立成 wire（符号性自决；GEMM 尾 V2.2 同款）：不可内联进
    // 含无符号拼接的 + 式——10.1c 会把无符号性递归传给 >>> 左操作数，
    // 算术移位退化逻辑填充（负 a → 巨大正 q0 → 假 7f 饱和，微测试实证）
    wire signed [63:0] sh0_w = pa_r >>> s0_r;
    wire signed [63:0] sh1_w = pb_r >>> s1_r;
    wire signed [63:0] q0_w = sh0_w + (ru0_w ? 64'sd1 : 64'sd0);
    wire signed [63:0] q1_w = sh1_w + (ru1_w ? 64'sd1 : 64'sd0);
    reg  signed [63:0] q0_r, q1_r;

    // ---- C2 级：求和 + 单次 sat_i8（sat_i32 中间界被 sat_i8 吸收）----
    wire signed [63:0] c2_sum_w = q0_r + q1_r;
    wire [7:0]  c2_y_w = (c2_sum_w > 64'sd127)  ? 8'h7F :
                         (c2_sum_w < -64'sd128) ? 8'h80 : c2_sum_w[7:0];
    reg  [7:0]  y_r;

    reg         asm_start_r, asm_flush_r;

    ppu_byte_store_assembler u_asm (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(asm_start_r), .flush_i(asm_flush_r),
        .in_valid_i(vch_r[4]), .in_data_i(y_r),
        .in_ready_o(asm_rdy_w),
        .beat_valid_o(wr_beat_valid_o), .beat_ready_i(wr_beat_ready_i),
        .beat_data_o(wr_beat_data_o), .beat_strb_o(wr_beat_strb_o),
        .idle_o(asm_idle_w),
        .acc_cnt_o(), .out_full_o()
    );

    assign busy_o = (state_r != S_IDLE);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r <= S_IDLE;
            in0_base_r <= 32'd0; in1_base_r <= 32'd0; out_base_r <= 32'd0;
            chw_r <= 32'd0;
            m0_r <= 32'd0; m1_r <= 32'd0; s0_r <= 6'd0; s1_r <= 6'd0;
            pop_cnt_r <= 32'd0;
            wr_done_all_r <= 1'b0;
            a_rem_r <= 32'd0; b_rem_r <= 32'd0; a_off_r <= 32'd0; b_off_r <= 32'd0;
            side_r <= 1'b0; reading_r <= 1'b0;
            pend_side_r <= 1'b0; cur_side_r <= 1'b0;
            cur_len_r <= 7'd0; cur_rem_r <= 7'd0;
            fun_a_d_r <= 64'd0; fun_b_d_r <= 64'd0;
            fun_a_cnt_r <= 4'd0; fun_b_cnt_r <= 4'd0;
            fa_wp_r <= 7'd0; fb_wp_r <= 7'd0; fa_rp_r <= 7'd0; fb_rp_r <= 7'd0;
            fa_lvl_r <= 8'd0; fb_lvl_r <= 8'd0;
            vch_r <= 5'd0;
            asm_start_r <= 1'b0; asm_flush_r <= 1'b0;
            rd_req_valid_o <= 1'b0; wr_req_valid_o <= 1'b0;
            rd_addr_o <= 32'd0; rd_len_o <= 24'd0;
            wr_addr_o <= 32'd0; wr_len_o <= 24'd0;
            done_o <= 1'b0;
            // 数据寄存器（a1/b1/pal*/pah*/pa/pb/q0/q1/y/rm0_q/rm1_q）
            // 不复位：消费全 v 门控，v 链失效兜底（参考核已验证模式；
            // rm_q 消费另有 s*_nz_w 前导门控，且每任务启动拍必重装载）
        end else begin
            // 脉冲缺省
            asm_start_r <= 1'b0;
            asm_flush_r <= 1'b0;
            done_o      <= 1'b0;

            // 写妥脉冲全局锁存（S_FLUSH 等待期不丢拍）
            if (wr_done_i)
                wr_done_all_r <= 1'b1;

            // ---- v 链：任务边界清 + advance 移位（CE-mux，禁独立
            //      置位/清零——边界清是复位集的一部分，非流内竞态）----
            if (asm_start_r || dma_abort_w)
                vch_r <= 5'd0;    // dma_err 必需：堵残留 v5 推垃圾进
                                  // 下任务 assembler；asm_start 免费附带
            else if (advance_w)
                vch_r <= {vch_r[3:0], jnA_w};

            // ---- 五级数据通路（统一 advance CE；气泡载旧值由 v 门控）----
            if (advance_w) begin
                if (jnA_w) begin              // A：join 捕获（保持式）
                    a1_r <= fa_q_w;
                    b1_r <= fb_q_w;
                end
                // B1/B2：DSP 级联对自时序（pal PREG=e1 / pah PREG=e2），
                // 无 RTL 级寄存；stall 期上游 CE 门控保持、DSP 重算同值
                pa_r    <= pp_pa_w;           // B2：DSP P 符号扩展（48→64b）
                pb_r    <= pp_pb_w;
                q0_r    <= q0_w;              // C1：移位+RNE
                q1_r    <= q1_w;
                y_r     <= c2_y_w;            // C2：求和+饱和
            end

            // ---- 拍接受 → funnel（本侧 ready 已含 funnel 空）----
            if (beat_fire_w) begin
                if (cur_side_r) begin
                    fun_b_d_r   <= rd_beat_data_i;
                    fun_b_cnt_r <= beat_nv_w;
                end else begin
                    fun_a_d_r   <= rd_beat_data_i;
                    fun_a_cnt_r <= beat_nv_w;
                end
                cur_rem_r <= (cur_rem_r > 7'd8) ? (cur_rem_r - 7'd8) : 7'd0;
            end

            // ---- funnel → FIFO（1B/拍；同拍两动作独立指针）----
            if (fun_a_dr_w) begin
                fa_mem[fa_wp_r] <= fun_a_d_r[7:0];
                fa_wp_r <= fa_wp_r + 7'd1;
                fun_a_d_r <= {8'd0, fun_a_d_r[63:8]};
                fun_a_cnt_r <= fun_a_cnt_r - 4'd1;
            end
            if (fun_b_dr_w) begin
                fb_mem[fb_wp_r] <= fun_b_d_r[7:0];
                fb_wp_r <= fb_wp_r + 7'd1;
                fun_b_d_r <= {8'd0, fun_b_d_r[63:8]};
                fun_b_cnt_r <= fun_b_cnt_r - 4'd1;
            end

            // ---- 会合弹出（两侧头同弹；FIFO 读异步旧值）----
            if (jnA_w) begin
                fa_rp_r <= fa_rp_r + 7'd1;
                fb_rp_r <= fb_rp_r + 7'd1;
                pop_cnt_r <= pop_cnt_r + 32'd1;
            end
            fa_lvl_r <= fa_lvl_r + (fun_a_dr_w ? 8'd1 : 8'd0)
                                  - (jnA_w ? 8'd1 : 8'd0);
            fb_lvl_r <= fb_lvl_r + (fun_b_dr_w ? 8'd1 : 8'd0)
                                  - (jnA_w ? 8'd1 : 8'd0);

            // DMA 错误/abort：任一推进态弃权回 IDLE（无 done）
            if (dma_abort_w) begin
                state_r <= S_IDLE;
                rd_req_valid_o <= 1'b0;
                wr_req_valid_o <= 1'b0;
                reading_r <= 1'b0;
            end else begin
            case (state_r)
            // ---- 启动锁存（profile 随 descriptor）----
            S_IDLE: begin
                if (start_i) begin
                    in0_base_r <= in0_base_i;
                    in1_base_r <= in1_base_i;
                    out_base_r <= out_base_i;
                    chw_r  <= chw_i;                  // w14 直入（V2.1：删
                                                      // c_i*h_i*w_i 启动拍
                                                      // 三乘——用户裁定
                                                      // 条件性 A 指示③）
                    m0_r   <= m0_i;  s0_r <= s0_i;
                    m1_r   <= m1_i;  s1_r <= s1_i;
                    rm0_q_r <= (s0_i == 6'd0) ? 64'd0
                              : ((64'd1 << (s0_i - 6'd1)) - 64'd1);
                    rm1_q_r <= (s1_i == 6'd0) ? 64'd0
                              : ((64'd1 << (s1_i - 6'd1)) - 64'd1);
                    pop_cnt_r <= 32'd0;
                    a_rem_r <= chw_i;                 // 两侧同长（同形）
                    b_rem_r <= chw_i;
                    a_off_r <= 32'd0; b_off_r <= 32'd0;
                    side_r <= 1'b0; reading_r <= 1'b0;
                    fun_a_cnt_r <= 4'd0; fun_b_cnt_r <= 4'd0;
                    fa_wp_r <= 7'd0; fb_wp_r <= 7'd0;
                    fa_rp_r <= 7'd0; fb_rp_r <= 7'd0;
                    fa_lvl_r <= 8'd0; fb_lvl_r <= 8'd0;
                    wr_done_all_r <= 1'b0;
                    if (chw_i == 32'd0)
                        state_r <= S_VDONE;       // 退化：无搬移
                    else
                        state_r <= S_WREQ;
                end
            end
            // ---- 总写请求（concat/mp5 同构：写先行）----
            S_WREQ: begin
                if (!wr_req_valid_o) begin
                    wr_req_valid_o <= 1'b1;
                    wr_addr_o <= out_base_r;
                    wr_len_o  <= chw_r[23:0];
                end else if (wr_req_ready_i) begin
                    wr_req_valid_o <= 1'b0;
                    asm_start_r    <= 1'b1;       // 整条流一次复位累加器
                                                  // （附带清 v 链）
                    state_r        <= S_RUN;
                end
            end
            // ---- 流推进：交替块调度 + 收拍 + 会合（并发）----
            S_RUN: begin
                // 块调度（序只看剩余量——确定序，金样同源）
                if (!reading_r && !rd_req_valid_o &&
                    ((a_rem_r != 32'd0) || (b_rem_r != 32'd0))) begin
                    if ((side_r == 1'b0 && a_rem_r != 32'd0) ||
                        (side_r == 1'b1 && b_rem_r == 32'd0)) begin
                        pend_side_r <= 1'b0;      // A 轮
                        rd_addr_o   <= in0_base_r + a_off_r;
                        rd_len_o    <= (a_rem_r > CHUNK) ?
                                       CHUNK[23:0] : a_rem_r[23:0];
                    end else begin
                        pend_side_r <= 1'b1;      // B 轮
                        rd_addr_o   <= in1_base_r + b_off_r;
                        rd_len_o    <= (b_rem_r > CHUNK) ?
                                       CHUNK[23:0] : b_rem_r[23:0];
                    end
                    rd_req_valid_o <= 1'b1;
                end
                // 请求受妥 → 在途块落定
                if (rd_req_valid_o && rd_req_ready_i) begin
                    rd_req_valid_o <= 1'b0;
                    reading_r      <= 1'b1;
                    cur_side_r     <= pend_side_r;
                    cur_len_r      <= rd_len_o[6:0];
                    cur_rem_r      <= rd_len_o[6:0];
                end
                // 块读尽 → 游标推进 + 交替翻转
                if (rd_done_i) begin
                    reading_r <= 1'b0;
                    if (cur_side_r == 1'b0) begin
                        a_off_r <= a_off_r + {25'd0, cur_len_r};
                        a_rem_r <= a_rem_r - {25'd0, cur_len_r};
                    end else begin
                        b_off_r <= b_off_r + {25'd0, cur_len_r};
                        b_rem_r <= b_rem_r - {25'd0, cur_len_r};
                    end
                    side_r <= ~cur_side_r;
                end
                // 完成判据：准入计数 + 两侧排空 + 流水排空（v 链
                // 打包约简；正确性 = 今条件 + 流水排空合取）
                if ((pop_cnt_r == chw_r) && (fa_lvl_r == 8'd0)
                    && (fb_lvl_r == 8'd0) && (fun_a_cnt_r == 4'd0)
                    && (fun_b_cnt_r == 4'd0) && (vch_r == 5'd0)) begin
                    asm_flush_r <= 1'b1;
                    state_r     <= S_FLUSH;
                end
            end
            // ---- 冲刷等待：assembler 排空 + 写妥 ----
            S_FLUSH: begin
                if (asm_idle_w && wr_done_all_r)
                    state_r <= S_VDONE;
            end
            // ---- 完成脉冲 ----
            S_VDONE: begin
                done_o  <= 1'b1;
                state_r <= S_IDLE;
            end
            default: state_r <= S_IDLE;
            endcase
            end
        end
    end

    // Phase B 影子对拍件已删除（2026-09-24）：全 13 门回归零失配后按
    // 计划撤除（translate_off 本就不进综合，bit 级等价；保留期证据 =
    // gate_addeng/gate_f5m console 的 sd_err=0 与 E5A_ADD_SHADOW_FAIL
    // 零出现，日志 14 号 §二）。

endmodule
