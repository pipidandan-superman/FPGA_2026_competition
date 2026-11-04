/************************************************************************
 * File Name       : ppu_loader.v
 * Developer       : LSL
 * Date            : 2026-09-21
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : ppu_loader
 * Description     : PPU-F3 loader —— 手册 §4.3 九步校验（v1.1 首错只留
 *                   一条、停后续任务）。V2.0：步 1-8 由纯组合优先链改为
 *                   锁存 bundle 后按步骤/槽位多周期顺序检查（用户裁定
 *                   2026-09-24 指示④），错误优先级与外部语义不变。
 *
 *   步序与错误映射（D-F3c，手册 §4.3 尾条"统一报 E_BIT_BUFFER/
 *   E_BIT_DESC + ERROR_INFO"按 pkg 语义归位）——与 V1.4 逐位一致：
 *     1 opcode ∈ {0x01,0x10..0x15}      → E_BIT_DESC    / 0x01
 *     2 w0: valid=1 且 [15:10]==0        → E_BIT_DESC    / 0x01
 *     3 槽位 id 合法 + 项 valid          → E_BIT_BUFFER  / 0x01
 *     4 几何 C/H/W>0,stride>=W,CHW<=size → E_BIT_BUFFER  / 0x01
 *     5 输入侧 producer<desc_id (0xFF豁免)→ E_BIT_BUFFER / 0x01
 *     6 地址域：高字=0、窗检查、8B 对齐  → E_BIT_BUFFER  / 0x14 或 0x13
 *     7 quant 引用 id<256（F3 全装载）   → E_BIT_QUANT   / 0x01
 *     8 段账 N_seg<=8、present==N_seg、  → E_BIT_BUFFER  / 0x01
 *       Σ段长=w14 且 ≤out.size（V1.3 容量
 *       上界；V1.2 删等值项留余量，手册 §4.3）
 *     9 view 别名：偏移非负、H·W 整倍、 → E_BIT_BUFFER  / 0x01
 *       c0+C<=C_parent（D-F2d 地址推导）
 *
 *   槽位适用域 = 取包策略（ppu_desc_if）：0=in0 恒、1=in1 仅 add、
 *     2=out 非 heads、3..10=段（concat/heads 且 present）。
 *
 *   V2.0 体系结构（指示④："锁存 bundle 后按槽位/步骤进行多周期检查，
 *   保持错误优先级和外部语义不变"）：
 *     - valid_i 拍单沿锁存全 bundle（~2.5k FF 单 CE，D 输入=纯连线，
 *       消除 desc_if 寄存器→本模块深组合锥——v17 全局最差 -6.808 即
 *       步 4 十一槽 c·h·w 乘链 + 步 1-8 优先链合并大锥）。
 *     - 定长扫描：scnt_r 1..69 每拍恰一步/一槽，判决拍数固定可推导
 *       （见下时延表）；首错锁存（fnd_r 置位后其余检查跳过但扫描
 *       拍照走，保证时延恒定），步序优先级 = V1.4 优先链逐位；
 *       错误锁存单点化——各步条件组合出本拍首错三元组后单 CE 锁存
 *       （v18a OOC 实测 scnt→estep/ebit/ecode 多 CE 扇出锥 -2.6）。
 *     - 步 4 每槽 2 拍、每拍恰一次乘法：A 拍零/stride 检 + m1<=C*H
 *       并锁存 B 拍操作数（wB<=W、szB<=size——scnt 译码不进乘法/
 *       比较锥；v18a OOC 实测 idx4 mux→DSP×2 级联→48b 比较→CE
 *       12.3ns 即此混锥），B 拍 {m1}*wB>szB 比较（V1.4 单拍三乘
 *       11 槽并行 → 拍数换锥深）。
 *     - 步 6 每槽 1 拍（域检查 33b 等价式 + 对齐比较，见步 6 注），
 *       升序首错即锁存 = V1.4 语义（最低号出错槽胜出；region 先于
 *       align）。
 *     - 步 8 拆两级：A 拍 4+4 部分和锁存，B 拍终加+比较。
 *     - 步 9：hw=H*W 专用拍锁存后，廉价前置（逆序/hw==0）与 V1.4
 *       同域同码；除法器 28 轮恢复余数逐字移植（操作数全部来自
 *       锁存 bank）。
 *     - 判决时延（valid 锁存沿 P1 起，判决寄存沿 P_k → 外部第 k 拍
 *       可见）：非 view = 41；view 步 1-8 错/步 9 快错/快过 = 42；
 *       view 迭代 = 70（41 扫描 + 1 装载 + 28 轮）。
 *
 *   外部语义（与 V1.4 一致，仅时延拍数按上表变化）：
 *     - 判决单脉冲（pass_o/err_valid_o 恰 1 拍，字段同拍有效）；
 *     - busy（active 期间）新 valid_i = 忽略（不重复提交；shell 在
 *       S_VERDICT 等待态消费脉冲，无超时——多周期化安全，V1.4
 *       29 拍迭代已建立该先例）；
 *     - 错误步/位/码、hw==0 合同（模检查恒过、q=0 只查 C<=C_parent）、
 *       镜像同序同码语义零变化；
 *     - rst_i（同步、与全库一致）：任意拍复位清全部状态回 IDLE。
 * Dependencies    : ppu_desc_if bundle。
 * Revision History:
 *   - V1.0 (2026-09-21) by LSL : F3 run01 初版。
 *   - V1.1 (2026-09-21) by LSL : 步 7 段 prof 比较宽度修复——seg_prof
 *       误声明 10b 向量且逐位收 10b 片（截断成 LSB），偶 prof 的段
 *       appq 恒 0 步 7 漏查（desc123 prof=300 假通过）；改直接切
 *       b_seg_prof_i 片比较。
 *   - V1.2 (2026-09-21) by LSL : 步 8 删 concat out_bytes==out.size
 *       等值项（手册 §4.3 无此条，步 4 语义允许 size 余量；<8B 张量
 *       8B 对齐最小分配被误拒，B2 S1 desc104 实测）。
 *   - V1.3 (2026-09-22) by LSL : 步 8 补容量上界项（用户裁定）——
 *       V1.2 后步 4 只钉 CHW≤size，无任何一步把 w14 绑到 out.size：
 *       CHW=8/size=8/Σ=w14=9 的 concat 可全步通过并向 8B 缓冲 DMA 写
 *       9B。补 is_cat&(w14>out.size) 拒绝（B1 L19 9B/8B、B2 S4 8B/8B
 *       边界实测；1B/8B=S1 复验）。
 *   - V1.4 (2026-09-23) by LSL : F7 Stage 3 时序修复（用户 A+ 裁定
 *       2026-09-23）——步 9 单周期 64b 模/除（综合 629 级锥/565
 *       CARRY4，100MHz WNS -176.5）重写为廉价前置 + 28 轮恢复余数
 *       迭代除法器；步 6 槽掩蔽修复（干净低号槽覆盖高号槽已记地址
 *       错——最低号出错槽胜出正典）。
 *   - V2.0 (2026-09-24) by LSL : PPU-F7 时序整改 v3 指示④——步 1-8
 *       组合几何检查+优先链（v17 全局最差 s4_v4→quo_r/CE -6.808：
 *       11 槽×3 乘 48b 比较 + 8 级优先链全组合）重写为锁存 bundle +
 *       定长多周期扫描；端口/错误步位码/优先级/单脉冲/busy 忽略/
 *       hw==0 合同/除法器轮数零变化；判决时延 1/29 拍 → 41/42/70 拍
 *       （见上表）。tb_ppu_loader_view.sv V2.0 同批改时延精确常数。
 *   - V2.1 (2026-09-24) by LSL : v18a OOC 时序修复（拍数/外部语义/
 *       错误步位码零变化）——(1) 步 4 B 拍乘法/比较操作数 A 拍锁存
 *       （wB_r/szB_r），scnt 译码退出乘法锥（原最差 12.3ns = idx4
 *       槽 mux 选择端→DSP×2 级联→48b 比较→CE）；(2) 错误锁存单点
 *       化（共享 CE=!fnd_r&cf_v，scnt 译码移 D 侧字段复用；原次差
 *       -2.6 = scnt→各步分支 CE 扇出）。
 *   - V2.2 (2026-09-24) by LSL : v18b OOC 残差修复（-0.144，纯组合
 *       等价重排，拍数/语义/步位码零变化）——步 6 域检查第三项
 *       64b 加+比较（16 CARRY4 链）改 33b 等价式（b_hi==0 时和
 *       >CMA_HI ⟺ 33b 低字和>CMA_HI，见步 6 注），加/比较链减半。
 *   - V2.3 (2026-09-25) by LSL : POST_V19_SYSTEM_PLAN P1.4b BD 残量
 *       修复——v22 routed 唯一失败路径 `scnt_r[0]/C→fnd_r/D` −0.283
 *       （ll 10，dpd 10.192 = logic 2.306/22.6% + route 7.886/77.4%；
 *       首网 p_0_in=计数器位 Q 网 fo=248 单网 1.844ns，次网译码
 *       fo=88 1.359ns，fnd 锥单元散布 X83-X103）为布线/扇出主导，
 *       非逻辑深度问题。修法=scnt_r 声明 (* max_fanout = 32 *) 综合
 *       复制（v16 s0/s1_r max_fanout=24 正典同款）：副本与原寄存器
 *       同 D 逻辑、逐拍同值、同复位——显式等价寄存，扫描契约
 *       （41/42/70 拍定长）与 done/last 台账零变化，fnd_r 锁存拍不移。
 *   - V3.0 (2026-10-23) by hwglobal G-02 : bundle 二锁收敛——P1 整
 *       bank 锁存（~2.5k FF）删除，扫描期直读 desc_if 寄存输出。
 *       协议依据：shell FSM 在 S_VERDICT/S_RUN/S_DECIDE 期间 dif_req_w
 *       = req_i && (state==S_IDLE) 恒 0（ppu_shell_top.v:125/346-381），
 *       desc_if 不会重取——bundle 输出在整个任务期稳定，引擎本就
 *       直读 desc_if 输出（shell :210-220 同证据）；本模块 bank 的
 *       D 端本就是纯连线副本（V2.0 头注），收敛后各检查锥拓扑不
 *       变（desc_if 寄存器→mux→检查，少一级串联 FF，路径只会变短）。
 *       base bank 64→32b + sb_base_hi_nz_i[10:0]：步 6"高字≠0→
 *       E_ADDR_REGION"语义由 nz 标志逐位保真（含契约外描述字）；
 *       步 9 v_rev/off 仅在 hi=0（契约内）时可到达除法路径——hi≠0
 *       已步 6 锁错，fnd 优先序保证判决逐位不变（V2.0 表 41/42/70
 *       拍定长/步位码/优先级/单脉冲/hw==0 合同零变化）。
 ************************************************************************/

module ppu_loader (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        valid_i,             // bundle done 脉冲 → 锁存沿起定长扫描
    // bundle（与 ppu_desc_if 输出同形；V3.0(G-02)：扫描期直读 desc_if
    // 寄存输出，bank 二锁已删——shell 协议保证任务期 bundle 稳定，
    // 见头注 V3.0；输入稳定性零依赖的 V2.0 契约由 shell FSM 承续）
    input  wire [7:0]  b_opcode_i,
    input  wire [15:0] b_w0_i,
    input  wire [7:0]  b_desc_id_i,
    input  wire [9:0]  b_in0_i, b_in1_i, b_out_i,
    input  wire [15:0] b_c_i, b_h_i, b_w_i,
    input  wire [15:0] b_nseg_i,
    input  wire [31:0] b_out_bytes_i,
    input  wire [7:0]  b_seg_present_i,
    input  wire [79:0] b_seg_prof_i,        // 8×10b
    input  wire [255:0] b_seg_len_i,        // 8×32b
    input  wire [351:0] sb_base_i,          // 11×32b（V3.0：高字恒零合同）
    input  wire [10:0]  sb_base_hi_nz_i,    // 槽 base 高字≠0 粘错（步 6）
    input  wire [351:0] sb_size_i,          // 11×32b
    input  wire [351:0] sb_stride_i,        // 11×32b
    input  wire [175:0] sb_c_i, sb_h_i, sb_w_i,   // 11×16b
    input  wire [10:0]  sb_valid_i, sb_fetched_i,
    input  wire [87:0]  sb_prod_i,          // 11×8b
    input  wire [9:0]   q_fetched_i,
    // 判决
    output reg         pass_o,
    output reg         err_valid_o,
    output reg  [3:0]  err_step_o,
    output reg  [3:0]  err_bit_o,
    output reg  [7:0]  err_code_o
);

    localparam [3:0] E_BIT_DESC = 4'd3, E_BIT_BUFFER = 4'd4,
                     E_BIT_QUANT = 4'd5;
    localparam [7:0] E_DESC_INVALID = 8'h01, E_ADDR_ALIGN = 8'h13,
                     E_ADDR_REGION = 8'h14;
    localparam [31:0] CMA_LO = 32'h10000000, CMA_HI = 32'h20000000;

    // ==================================================================
    // bundle 源（V3.0 G-02：bank 二锁删除，直读 desc_if 寄存输出；
    // 同名下 wire 别名——扫描逻辑零改动，锥拓扑 = desc_if 寄存器→mux
    // →检查，较 bank 版少一级串联 FF）
    // ==================================================================
    wire  [7:0]   op_r  = b_opcode_i;
    wire  [15:0]  w0_r  = b_w0_i;
    wire  [7:0]   did_r = b_desc_id_i;
    wire  [15:0]  cd_r = b_c_i, hd_r = b_h_i, wd_r = b_w_i;  // desc C/H/W（步 9 用）
    wire  [15:0]  nseg_r = b_nseg_i;
    wire  [31:0]  oby_r = b_out_bytes_i;
    wire  [7:0]   segp_r = b_seg_present_i;
    wire  [79:0]  segprof_r = b_seg_prof_i;
    wire  [255:0] seglen_r = b_seg_len_i;
    wire  [9:0]   qf_r = q_fetched_i;
    wire  [31:0]  base_r [0:10];
    wire  [31:0]  size_r [0:10];
    wire  [31:0]  strd_r [0:10];
    wire  [15:0]  c_r    [0:10];
    wire  [15:0]  h_r    [0:10];
    wire  [15:0]  w_r    [0:10];
    wire  [7:0]   prod_r [0:10];
    wire  [10:0]  val_r = sb_valid_i, fet_r = sb_fetched_i;
    genvar ga;
    generate
        for (ga = 0; ga < 11; ga = ga + 1) begin : GC_BANK_ALIAS
            assign base_r[ga] = sb_base_i[32*ga +: 32];
            assign size_r[ga] = sb_size_i[32*ga +: 32];
            assign strd_r[ga] = sb_stride_i[32*ga +: 32];
            assign c_r   [ga] = sb_c_i   [16*ga +: 16];
            assign h_r   [ga] = sb_h_i   [16*ga +: 16];
            assign w_r   [ga] = sb_w_i   [16*ga +: 16];
            assign prod_r[ga] = sb_prod_i[ 8*ga +:  8];
        end
    endgenerate

    // ---- 扫描/迭代状态（先于各步线网声明：m1/p1/p2/scnt 为其 D 端源）----
    // V2.3：max_fanout 综合复制（显式等价寄存，v16 s0/s1_r 正典同款）
    // ——v22 BD 唯一失败路径 scnt_r[0]/C→fnd_r/D −0.283 的首网 p_0_in
    // fo=248 单网 1.844ns（route 7.886/77.4% 主导）；副本同 D 逻辑逐拍
    // 同值，拍数/语义/步位码/优先级/时延表零变化。
    (* max_fanout = 32 *) reg [6:0]  scnt_r;  // 0=IDLE；1..41=步 1-9 前置；42..69=28 轮
    reg        active_r;    // busy（新 valid_i 忽略）
    reg        fnd_r;       // 首错已锁存（后续检查跳过，扫描拍照走）
    reg [3:0]  estep_r, ebit_r;
    reg [7:0]  ecode_r;
    reg [31:0] m1_r;        // 步 4 A 拍部分积 C*H
    reg [15:0] wB_r;        // 步 4 A 拍锁存 B 拍乘数 W（scnt 译码不进乘法锥）
    reg [31:0] szB_r;       // 步 4 A 拍锁存 B 拍比较数 size（同上）
    reg [31:0] p1_r, p2_r;  // 步 8 A 拍部分和
    // 迭代除法器（28 轮恢复余数，V1.4 逐字移植；操作数=锁存 bank）
    reg [32:0] rem_r;       // 部分余数（<2·hw ≤ 2^33-2 → 33b）
    reg [27:0] quo_r;       // 移位被除数 → 商（28b）
    reg [31:0] hwq_r;       // 除数锁存（32b 全宽；scnt 40 拍锁存）
    reg [15:0] vrowc_r, vrowp_r;  // 行检查 C（desc）/ C_parent 锁存

    // ---- 算子域（锁存后译码，扫描期恒定）----
    wire is_add   = (op_r == 8'h11);
    wire is_cat   = (op_r == 8'h12);
    wire is_heads = (op_r == 8'h15);
    wire is_xf    = is_cat | is_heads;
    wire is_view  = (op_r == 8'h10);

    // ---- 槽适用位（取包策略，与 V1.4 同式；源改锁存 bank）----
    wire [10:0] app;
    assign app[0] = 1'b1;
    assign app[1] = is_add;
    assign app[2] = ~is_heads;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GC_APP
            assign app[3 + g] = is_xf & segp_r[g];
        end
    endgenerate

    // 输入侧槽（步 5）：in0、in1(add)、段
    wire [10:0] app_in;
    assign app_in[0] = 1'b1;
    assign app_in[1] = is_add;
    assign app_in[2] = 1'b0;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GC_APPIN
            assign app_in[3 + g] = is_xf & segp_r[g];
        end
    endgenerate

    // ---- 步 1/2（锁存后）----
    // X1 hang RCA (2026-10-17, m10p3_x1_hang_run01): under the r8 capacity
    // knife PPU_NO_UPS the 0x14 engine is stubbed (ppu_engine_mux ups_done_w
    // tied 0) and dispatch deadloops in S_UPS with NO watchdog -- walker
    // W_ENG silent hang (board X1 B-arm, task14/di49). Reject 0x14 at
    // loader step 1 here so the walker takes the visible W_ERR path
    // (ERROR_STATUS bit10 + ERROR_INFO {port5,desc,op14,code02}).
    // Knife-absent builds: domain identical (default-absent law).
    `ifdef PPU_NO_UPS
    wire op_ok = (op_r == 8'h01) |
                 ((op_r >= 8'h10) && (op_r <= 8'h15)) && (op_r != 8'h14);
    `else
    wire op_ok = (op_r == 8'h01) |
                 ((op_r >= 8'h10) && (op_r <= 8'h15));
    `endif
    wire w0_ok = w0_r[8] & ~|w0_r[15:10];

    // ---- 步 3：fetched 且 valid（单拍 11 项 OR，浅）----
    reg s3_v;
    integer i;
    always @* begin
        s3_v = 1'b0;
        for (i = 0; i <= 10; i = i + 1)
            if (app[i] && (!fet_r[i] || !val_r[i]))
                s3_v = 1'b1;
    end

    // ---- 步 4：几何（每槽 2 拍；A 拍零/stride 检 + m1<=C*H，
    //      B 拍 {16'd0,m1}*W > size 比较——每拍恰一次乘法）----
    // 扫描位置：scnt 3..24 = 槽 0..10（A=scnt 奇、B=scnt 偶）
    wire [3:0] idx4_w = (scnt_r[4:0] - 5'd3) >> 1;
    wire       app4_w = app[idx4_w] & fet_r[idx4_w];
    wire [15:0] c4_w  = c_r   [idx4_w];
    wire [15:0] h4_w  = h_r   [idx4_w];
    wire [15:0] w4_w  = w_r   [idx4_w];
    wire [31:0] st4_w = strd_r[idx4_w];
    // A 拍条件（与 V1.4 同式，乘项移 B 拍）
    wire s4a_bad_w = (c4_w == 16'd0) || (h4_w == 16'd0) ||
                     (w4_w == 16'd0) || (st4_w < {16'd0, w4_w});
    // B 拍条件：C*H*W>size（48b 全宽比较，与 V1.4 同宽同式；
    // 操作数全部 A 拍锁存——scnt 译码不进乘法/比较锥）
    wire [47:0] s4m_w = {16'd0, m1_r} * {16'd0, wB_r};
    wire        s4b_bad_w = (s4m_w > {16'd0, szB_r});

    // ---- 步 5：输入侧 producer（单拍 11 项 OR，8b 比较，浅）----
    reg s5_v;
    always @* begin
        s5_v = 1'b0;
        for (i = 0; i <= 10; i = i + 1)
            if (app_in[i] && fet_r[i] &&
                (prod_r[i] != 8'hFF) &&
                ({1'b0, prod_r[i]} >= {1'b0, did_r}))
                s5_v = 1'b1;
    end

    // ---- 步 6：地址域（每槽 1 拍，scnt 26..36 = 槽 0..10 升序；
    //      首错锁存 = 最低号出错槽胜出；槽内 region 先于 align——
    //      V1.4 语义正典，见 V1.4 步 6 注）----
    wire [3:0]  idx6_w = scnt_r[4:0] - 5'd26;
    wire        app6_w = app[idx6_w] & fet_r[idx6_w];
    wire [31:0] b6_w   = base_r[idx6_w];
    // 域检查 33b 等价式（v18b：64b 加+比较 16 CARRY4 链 9.9ns）：
    //   b_hi≠0 → 首项独立成立；b_hi==0 时 64b 和>CMA_HI ⟺ 33b
    //   (b_lo+size)>CMA_HI（32b 进位出 = 值≥2^32 > CMA_HI，33b
    //   比较自然覆盖）——OR 三项真值表逐位等价（V1.4 语义不变，
    //   仅组合式重排；边界 sum==CMA_HI 两侧同为不越窗）。
    // V3.0(G-02)：b_hi≠0 事实改由 desc_if 粘错位 sb_base_hi_nz_i
    // 承载（base 64→32b 剪枝的语义保位；nz 位 = 原 b6_w[63:32]!=0
    // 逐位同源，含契约外描述字）。
    wire [32:0] bsend_w = {1'b0, b6_w} + {1'b0, size_r[idx6_w]};
    wire s6_region_w = sb_base_hi_nz_i[idx6_w] ||
                       (b6_w < CMA_LO) ||
                       (bsend_w > {1'b0, CMA_HI});      // 高字/越窗
    wire s6_align_w  = |b6_w[2:0];                          // 8B 对齐（D-F3b）

    // ---- 步 7：quant（单拍 10 项 OR；appq=取包策略，源改锁存）----
    wire [9:0] appq;
    assign appq[0] = is_add;
    assign appq[1] = is_add;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GC_APPQ
            assign appq[2 + g] = is_cat & segp_r[g] &
                                 (segprof_r[10*g +: 10] != 10'd0);
        end
    endgenerate
    wire s7_v = |(appq & ~qf_r);

    // ---- 步 8：段账（拆两拍：A 拍 4+4 部分和锁存，B 拍终加+比较）----
    wire [3:0] present_cnt =
        {3'd0, segp_r[0]} + {3'd0, segp_r[1]} +
        {3'd0, segp_r[2]} + {3'd0, segp_r[3]} +
        {3'd0, segp_r[4]} + {3'd0, segp_r[5]} +
        {3'd0, segp_r[6]} + {3'd0, segp_r[7]};
    wire [31:0] seg_len0 = seglen_r[31:0];
    wire [31:0] seg_len1 = seglen_r[63:32];
    wire [31:0] seg_len2 = seglen_r[95:64];
    wire [31:0] seg_len3 = seglen_r[127:96];
    wire [31:0] seg_len4 = seglen_r[159:128];
    wire [31:0] seg_len5 = seglen_r[191:160];
    wire [31:0] seg_len6 = seglen_r[223:192];
    wire [31:0] seg_len7 = seglen_r[255:224];
    // A 拍部分和（present 掩码同 V1.4）
    wire [31:0] segp1_w =
        (segp_r[0] ? seg_len0 : 32'd0) + (segp_r[1] ? seg_len1 : 32'd0) +
        (segp_r[2] ? seg_len2 : 32'd0) + (segp_r[3] ? seg_len3 : 32'd0);
    wire [31:0] segp2_w =
        (segp_r[4] ? seg_len4 : 32'd0) + (segp_r[5] ? seg_len5 : 32'd0) +
        (segp_r[6] ? seg_len6 : 32'd0) + (segp_r[7] ? seg_len7 : 32'd0);
    // B 拍终判（V1.2 删等值/V1.3 容量上界域不变）
    wire s8_cap_v = is_cat & fet_r[2] & (oby_r > size_r[2]);
    wire s8_v = is_xf && (
        (nseg_r > 16'd8) ||
        ({12'd0, present_cnt} != nseg_r) ||
        ((p1_r + p2_r) != oby_r) ||
        s8_cap_v);

    // ---- 当前扫描拍首错判决（组合单点；步位码与 V1.4 优先链逐位）----
    // 每拍恰一步/一槽活跃 → 取"本拍条件"即可；步序优先级由扫描次序
    // 天然保证（scnt=1 内步 1 先于步 2、步 6 槽内 region 先于 align），
    // 首错由 fnd_r 屏蔽后续锁存。锁存单点化（共享 CE）消多分支 CE 扇出。
    wire s4_rng_w = (scnt_r >= 7'd3) && (scnt_r <= 7'd24);
    wire s6_rng_w = (scnt_r >= 7'd26) && (scnt_r <= 7'd36);
    reg       cf_v;
    reg [3:0] cf_step, cf_bit;
    reg [7:0] cf_code;
    always @* begin
        cf_v = 1'b0; cf_step = 4'd0; cf_bit = 4'd0; cf_code = 8'd0;
        if (scnt_r == 7'd1) begin
            if (!op_ok) begin
                cf_v = 1'b1; cf_step = 4'd1; cf_bit = E_BIT_DESC;   cf_code = E_DESC_INVALID;
            end else if (!w0_ok) begin
                cf_v = 1'b1; cf_step = 4'd2; cf_bit = E_BIT_DESC;   cf_code = E_DESC_INVALID;
            end
        end else if (scnt_r == 7'd2) begin
            if (s3_v) begin
                cf_v = 1'b1; cf_step = 4'd3; cf_bit = E_BIT_BUFFER; cf_code = E_DESC_INVALID;
            end
        end else if (s4_rng_w) begin
            if (app4_w && (scnt_r[0] ? s4a_bad_w : s4b_bad_w)) begin
                cf_v = 1'b1; cf_step = 4'd4; cf_bit = E_BIT_BUFFER; cf_code = E_DESC_INVALID;
            end
        end else if (scnt_r == 7'd25) begin
            if (s5_v) begin
                cf_v = 1'b1; cf_step = 4'd5; cf_bit = E_BIT_BUFFER; cf_code = E_DESC_INVALID;
            end
        end else if (s6_rng_w) begin
            if (app6_w) begin
                if (s6_region_w) begin
                    cf_v = 1'b1; cf_step = 4'd6; cf_bit = E_BIT_BUFFER; cf_code = E_ADDR_REGION;
                end else if (s6_align_w) begin
                    cf_v = 1'b1; cf_step = 4'd6; cf_bit = E_BIT_BUFFER; cf_code = E_ADDR_ALIGN;
                end
            end
        end else if (scnt_r == 7'd37) begin
            if (s7_v) begin
                cf_v = 1'b1; cf_step = 4'd7; cf_bit = E_BIT_QUANT;  cf_code = E_DESC_INVALID;
            end
        end else if (scnt_r == 7'd39) begin
            if (s8_v) begin
                cf_v = 1'b1; cf_step = 4'd8; cf_bit = E_BIT_BUFFER; cf_code = E_DESC_INVALID;
            end
        end
    end

    // ---- 步 9：view 别名（hw 专用拍锁存 + 廉价前置 + 迭代除法器）----
    // V3.0(G-02)：64b 基址改 32b（高字恒零合同）；v_rev 32b 比较仅在
    // hi=0（契约内）与 64b 版逐位一致——hi≠0 已步 6 锁错，fnd 优先序
    // 保证判决不变（见头注 V3.0）。
    wire v_rev_w = (base_r[2] < base_r[0]);     // 地址逆序（32b，锁存源）
    wire hw0_w   = (hwq_r == 32'd0);            // H/W 为零（hw 锁存后）
    // 快路径步 9 错（hw==0 沿 V1.3 合同：模恒过、q=0 只查 c<=C_parent）
    wire s9_fast_w = is_view && (v_rev_w || (hw0_w && (cd_r > c_r[0])));
    // 被除数 28b（V1.4 位宽证明沿用：步 6 窗约束 → off<2^28 且模差=全差）
    wire [27:0] v_off_w = base_r[2][27:0] - base_r[0][27:0];

    // ---- 单轮除法组合（28 轮恢复余数，V1.4 逐字移植）----
    wire [32:0] rem_ns_w = {rem_r[31:0], quo_r[27]};
    wire        ge_w     = (rem_ns_w >= {1'b0, hwq_r});
    wire [32:0] rem_nx_w = ge_w ? (rem_ns_w - {1'b0, hwq_r}) : rem_ns_w;
    wire [27:0] quo_nx_w = {quo_r[26:0], ge_w};
    // 行检查（29b：quo<2^28 + c<2^16 < 2^29 无溢出）
    wire [28:0] qpc_w = {1'b0, quo_nx_w} + {13'd0, vrowc_r};
    wire        row_fail_w = (qpc_w > {13'd0, vrowp_r});

    // 主时序：IDLE 锁存 → 定长扫描/迭代 → 单脉冲判决
    // （首错锁存见上方单点 if；步位码与 V1.4 优先链逐位一致）
    always @(posedge clk_i) begin
        if (rst_i) begin
            pass_o      <= 1'b0;
            err_valid_o <= 1'b0;
            err_step_o  <= 4'd0;
            err_bit_o   <= 4'd0;
            err_code_o  <= 8'd0;
            scnt_r      <= 7'd0;
            active_r    <= 1'b0;
            fnd_r       <= 1'b0;
            estep_r     <= 4'd0;
            ebit_r      <= 4'd0;
            ecode_r     <= 8'd0;
            m1_r        <= 32'd0;
            wB_r        <= 16'd0;
            szB_r       <= 32'd0;
            rem_r       <= 33'd0;
            quo_r       <= 28'd0;
            hwq_r       <= 32'd0;
            vrowc_r     <= 16'd0;
            vrowp_r     <= 16'd0;
        end else begin
            // 判决脉冲缺省单拍（无重复提交/多拍错误脉冲）
            pass_o      <= 1'b0;
            err_valid_o <= 1'b0;
            if (!active_r) begin
                // ---- IDLE：判决时延计数基准沿 P1（V3.0(G-02)：数据免
                // 锁存——bank 删除，bundle 直读 desc_if 寄存输出，shell
                // 协议保证任务期稳定；本沿仅初始化扫描态）----
                if (valid_i) begin
                    fnd_r   <= 1'b0;
                    estep_r <= 4'd0;
                    ebit_r  <= 4'd0;
                    ecode_r <= 8'd0;
                    scnt_r  <= 7'd1;
                    active_r<= 1'b1;
                end
            end else begin
                // ---- 扫描期（active）：valid_i 忽略；定长步进 ----
                // 首错单点锁存（共享 CE；fnd_r 置位后条件拍照算但不锁）
                if (!fnd_r && cf_v) begin
                    fnd_r   <= 1'b1;
                    estep_r <= cf_step;
                    ebit_r  <= cf_bit;
                    ecode_r <= cf_code;
                end
                case (scnt_r)
                7'd1: begin
                    // 步 1/2（opcode / w0）
                    scnt_r <= 7'd2;
                end
                7'd2: begin
                    // 步 3：槽位 fetched 且 valid
                    scnt_r <= 7'd3;
                end
                7'd3, 7'd4, 7'd5, 7'd6, 7'd7, 7'd8, 7'd9, 7'd10,
                7'd11, 7'd12, 7'd13, 7'd14, 7'd15, 7'd16, 7'd17,
                7'd18, 7'd19, 7'd20, 7'd21, 7'd22, 7'd23, 7'd24: begin
                    // 步 4：槽 (scnt-3)>>1；A 拍（奇）零/stride 检 +
                    //      m1/wB/szB 锁存（B 拍操作数全寄存源），
                    //      B 拍（偶）乘比较
                    if (scnt_r[0]) begin
                        m1_r <= c4_w * h4_w;
                        wB_r <= w4_w;
                        szB_r <= size_r[idx4_w];
                    end
                    scnt_r <= scnt_r + 7'd1;
                end
                7'd25: begin
                    // 步 5：输入侧 producer
                    scnt_r <= 7'd26;
                end
                7'd26, 7'd27, 7'd28, 7'd29, 7'd30, 7'd31, 7'd32,
                7'd33, 7'd34, 7'd35, 7'd36: begin
                    // 步 6：槽 scnt-26 升序（region 先于 align 在 cf 链）
                    scnt_r <= scnt_r + 7'd1;
                end
                7'd37: begin
                    // 步 7：quant
                    scnt_r <= 7'd38;
                end
                7'd38: begin
                    // 步 8 A：部分和锁存（4+4）
                    p1_r <= segp1_w;
                    p2_r <= segp2_w;
                    scnt_r <= 7'd39;
                end
                7'd39: begin
                    // 步 8 B：终加 + 比较（V1.2/V1.3 域）
                    scnt_r <= 7'd40;
                end
                7'd40: begin
                    // 非 view：判决沿（外部第 41 拍）
                    if (!is_view) begin
                        err_valid_o <= fnd_r;
                        pass_o      <= ~fnd_r;
                        err_step_o  <= estep_r;
                        err_bit_o   <= ebit_r;
                        err_code_o  <= ecode_r;
                        scnt_r      <= 7'd0;
                        active_r    <= 1'b0;
                    end else begin
                        // view：步 9 前置拍（除数 H·W 锁存）
                        hwq_r  <= hd_r * wd_r;
                        scnt_r <= 7'd41;
                    end
                end
                7'd41: begin
                    // view 快判沿（外部第 42 拍）或除法器装载
                    if (fnd_r || s9_fast_w) begin
                        // 首错优先级：步 1-8 先于步 9（V1.4 同序）
                        err_valid_o <= 1'b1;
                        err_step_o  <= fnd_r ? estep_r : 4'd9;
                        err_bit_o   <= fnd_r ? ebit_r  : E_BIT_BUFFER;
                        err_code_o  <= fnd_r ? ecode_r : E_DESC_INVALID;
                        scnt_r      <= 7'd0;
                        active_r    <= 1'b0;
                    end else if (hw0_w) begin
                        // hw==0 且 c<=C_parent（否则已入 s9_fast_w）→ 过
                        pass_o   <= 1'b1;
                        scnt_r   <= 7'd0;
                        active_r <= 1'b0;
                    end else begin
                        // 装载迭代（V1.4 同式，源=锁存 bank）
                        quo_r   <= v_off_w;
                        rem_r   <= 33'd0;
                        vrowc_r <= cd_r;
                        vrowp_r <= c_r[0];
                        scnt_r  <= 7'd42;
                    end
                end
                default: begin
                    // scnt 42..69 = 28 轮恢复余数（V1.4 逐字移植）
                    rem_r <= rem_nx_w;
                    quo_r <= quo_nx_w;
                    if (scnt_r == 7'd69) begin
                        // 第 28 轮（末轮）完成：单次判决（本沿组合终值
                        // = 下拍 rem_r/quo_r 寄存值）；外部第 70 拍
                        pass_o      <= (rem_nx_w == 33'd0) && !row_fail_w;
                        err_valid_o <= (rem_nx_w != 33'd0) ||  row_fail_w;
                        err_step_o  <= 4'd9;
                        err_bit_o   <= E_BIT_BUFFER;
                        err_code_o  <= E_DESC_INVALID;
                        scnt_r      <= 7'd0;
                        active_r    <= 1'b0;
                    end else begin
                        scnt_r <= scnt_r + 7'd1;
                    end
                end
                endcase
            end
        end
    end

endmodule
