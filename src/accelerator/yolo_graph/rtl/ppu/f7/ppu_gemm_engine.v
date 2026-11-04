/************************************************************************
 * File Name     : ppu_gemm_engine.v
 * Developer     : LSL
 * Date          : 2026-09-27
 * Module Name   : ppu_gemm_engine
 * Description   : P2.1 walker GEMM 槽执行体（conv 适配器）。
 *                 职责：接收单 conv 描述符（ABI v2 草案字 w3/w4/w8/w10/w11，
 *                 P2.2 门口呈报裁定），RTL 化 B3-S2 板证寄存器正典
 *                 （pl_b3s2.py arm_and_run / load_lut 序），驱动内部例化的
 *                 yolo_gemm_top V1.2，经 DMA 用户口（ppu_dma_master 用户侧
 *                 逐名镜像，P2.2 直连零改）搬运 LUT/参数/装载流/写出 y。
 *                 几何/链律逐条从计算产物转录（conv_packer.py /
 *                 b3_k576_meta.json），出处见 P2_1_ENGINE_DESIGN.md §4。
 *   FSM 主序：E_IDLE→FETCH→GEOM/GEOM2→PRM_LD→[LUT_LD]→块循环{PCTL×8→
 *         ROWVAL/NMASK→y arm→段{LDGRP→装载(直通 s_axis_ld,tlast 补拍)→
 *         LDLEN 校→GEOM→JOBCFG→CTRL=1→[pend 等待]}→WAIT→CHK}→E_DONE。
 *         E_ERR=err 脉冲+err_clr/soft_rst 恢复序幕；E_ABORT=静默取消
 *         （无 done 无 err）。块→(nt,rc,s) 用增量游标（免运行时除法）。
 *   注：多链段（K1152/2304）按串行 job_pend 等待实现（板证驱动为 start1
 *         流水），K576 单段不触及，留 P2.3+ 扩展门；PCTL 逐块全写为正典
 *         保守序（不做 rc 变化投机）。
 * Revision History:
 *   - V1.0 (2026-09-27) by LSL : P2.1 单元门初版（K576 全 320 块对拍
 *                 GEMM 线板证 golden SHA fdda4863…）。
 *   - V1.1 (2026-09-27) by LSL : AXI 子 FSM 接收门加 !cmd_done_r——
 *                 修复 done 拍旧地址重复接收（BRGSTAT 误读 STATUS /
 *                 PCTL 步骤截断 / LUT 半载三症同根）。
 *   - V1.2 (2026-09-27) by LSL : 板证字面两处对齐——①PCTL 写值
 *                 0x100|r（原 0x08|r，top 仅译 [2:0] 功能等价，非字面）；
 *                 ②grp 律两 case：单段链 grp=块奇偶 b&1（pl_p13_k576.py
 *                 blk_geom 板证），多段链 grp=段奇偶 seg%2（conv_packer.
 *                 program + K2304 J1/J2/J3=0x03/0x19/0x05 板证）。
 *   - V1.3 (2026-09-28) by LSL : P2.2 真互连加固——①新增 rcvr_o
 *                 （E_ABORT/E_ABORTS/E_ERR/E_ERRC/E_ERRS 期有效）供
 *                 f7_top 对第二 ppu_dma_master 施 wash 复位（err/abort
 *                 锁存仅 rst 可清，P2.1 单元门 TB 无此面）；②新增
 *                 E_ABORTD 排空态：abort 落在 y 写在途（y_armed 置位中
 *                 或 E_YARM 同拍 wr_req 握手）时不得直拆——DMA 受理即
 *                 发 AW，W 永不到流会在互连/HP 留死事务（共享 HP0 写
 *                 通道楔死）。统一收口 = strb=0 空拍补齐剩余 W 拍
 *                 （AXI 合法零字节写，帧已弃），核心 y 流在一级寄存节
 *                 被丢弃，等 wr_done（DMA_TMO 超时保活性）再入 E_ABORT。
 *                 语义对 P2.1 单元门判据不可见（TB V1.2 同步：strb=00
 *                 合法 + wr 模型撤 dma_kill）。
 *   - V1.4 (2026-09-28) by LSL : F7G-1 EC_YWR 根因修复（WDBG 事件面定
 *                 位）——①y 写一级寄存节加保持守卫：出口拍悬挂
 *                 （valid=1 且 !ready）期间不重算捕获，否则核已按
 *                 tready(=armed&&ready) 弹出的字被下一拍 ready=0 的
 *                 无条件重算清零（CLOBBER 丢字：系统面 BFM 随机 wready
 *                 1/8 密度 → 16 拍期望丢 2，实测 ysent=14/yfifo=0/
 *                 gbfm wexp=2；单元模型 wr_beat_ready 恒 1 故 P2.1 六
 *                 百判据不可见）。data 随 valid 成对捕获（悬挂期防数据
 *                 错位）。②E_CHKY1 的 !wr_done_seen 零等待判决改有界
 *                 轮询（E_CHKY0 过渡清 tmo，上限 DMA_TMO）：wr_done 走
 *                 AXI B 链有 ~10 拍尾延（单元模型仅 +2 拍），板级 B 延
 *                 时未知——零等待在系统/板面是潜伏误报源；真缺失仍于
 *                 DMA_TMO 报 EC_YWR（保活性不变）。
 *   - V1.5 (2026-09-28) by LSL : 参数阵列 64b 字形重构（综合面，零功能
 *                 意图）。BD v24 首综合 Synth 8-3391：prm 32b 形每拍双写
 *                 （64b DMA 拍拆两字）+ 读口 = 3 口，不可推断任何 RAM，
 *                 溶触发器 98304b 爆器件报错。重构：阵列改 [63:0]×1536，
 *                 每拍单写一字（字址=prm_wa>>1，prm_wa 仍按 32b 字计），
 *                 读侧 prm_ra 32b 粒度索引 + 半选多路恢复 32b 视图——
 *                 单写口 + 异步读 = 分布式 RAM 可推断形。语义等价：写序
 *                 与字内容不变，读出值逐位不变（P2.1 单元门 + F7G 门重证）。
 *   - V1.6 (2026-09-28) by LSL : GEOM 两级积流水化（时序面，零功能意图）。
 *                 v24 首轮 P&R WNS -4.725 根因 = 原组合 wire 链
 *                 nb_full=n_tile*rc_n → span_full=nb_full*tll（双 DSP 级联）
 *                 再加比较/截位/加法同拍 14.3ns（深违 162 端点全此簇）。
 *                 斩法：E_GEOM2 只算第 1 级积入 nb_full_q；新 E_GEOM2B 算
 *                 第 2 级积入 span_full_q；新 E_GEOM2C 全寄存源上做校验/
 *                 消费（prm_bt/rd_len 等独立小算数前置 E_GEOM2，仅
 *                 E_GEOM2C 置 rd_req_valid 后方生效，err 路径零发射不变）。
 *                 值逐位等价（同源同式，仅延 2 拍），+2 拍/描述符。
 *   - V1.7 (2026-09-28) by LSL : prm 读址块基址寄存（时序面，零功能意图）。
 *                 round-4 残余 WNS -0.695 根因 = rc_q→×24 乘加链(3×CARRY4)
 *                 →RAMD64E→MUXF7→cmd_wdata 10.5ns（route 占 58%）。块基址
 *                 prm_base_q=rc_q*24 改随 rc_q 各写点（复位/启动清零、
 *                 E_NEXTB 推进/回卷）同步维护，一寄/块；读址只剩步内小加
 *                 （pctl_step[4:2]*3+[1:0]）。值逐位等价，周期面不变。
 *   - V1.8 (2026-09-28) by LSL : P2.5 Gate G 根因修复——y 写地址固定跨距
 *                 改紧凑游标。原 y_addr = y_base + blk*128 假定每块 128B，
 *                 但 btt_w = vc(s)*8，Wo 非 16 倍数时尾条带仅 32B/块：P25
 *                 (Wo=20) 每行 8×128B+8×32B，地址却每块 +128 → 块间 96B
 *                 空洞（首洞=窗内偏移 1056）+ 流尾越窗溢出 9216B，末跨
 *                 40960B=1.6×25600（板 mirror_post.bin 独立重算逐位吻合，
 *                 见 P25_G_DEFECT_REPORT.md H4）。修复：新增 y_dst_off_q
 *                 紧凑游标（24b），复位/每描述符入口清零，E_NEXTB 确认
 *                 当前块 wr_done_seen 后按 btt_w 推进（异常路径不提交增量；
 *                 E_ABORTD 不触碰，下一描述符入口清零）；y_addr = y_base +
 *                 y_dst_off_q。wr_addr_o 仍在 E_PCTL 完成拍锁定（一请求一
 *                 稳定地址）；wr_len_o 仍为当前块 btt_w；V1.4 valid/data
 *                 成对捕获保持守卫不动。数值/ABI/环账零变化；DMA IP 与
 *                 BFM 不涉。sim 门同步：TB 回读期望从 128*b 槽位律改紧凑
 *                 累计律（原 TB 把 RTL 定址律当期望=放置缺陷盲区根因）。
 *   - V1.9 (2026-09-28) by LSL : V1.8 功能等价的时序加固（用户裁定采纳
 *                 codex 寄存器绝对地址方案）。V1.8 的 y_addr_w = y_base +
 *                 y_dst_off_q 把 32b 基址加法留在 wr_addr_o 锁存路径（与
 *                 V1.7 原路径同级）；r6 P&R 余量仅 WNS+0.042/WHS+0.020，
 *                 按"地址寄存器化"重构：游标改绝对地址寄存器 y_addr_q，
 *                 E_IDLE 入口一次锁 y_addr_q<=y_base（基址加法移出请求
 *                 路径），E_PCTL 锁存拍 wr_addr_o<=y_addr_q（FF→FF 零逻辑），
 *                 E_NEXTB 自环 y_addr_q<=y_addr_q+{24'd0,btt_w}（推进量仍
 *                 btt_w 通用律——非 128/32 硬编码，Wo=32 等几何不破）。
 *                 地址序列逐值等价（addr_k = y_base + Σ_{i<k} btt_i）；
 *                 异常路径仍零触碰；ABI/DMA/BFM 零涉。
 *   - V2.0 (2026-09-28) by LSL : P2.3 槽跨距缺陷修复（独立审查
 *                 P23_REPAIR_REVIEW.md 方案 A）。五处取数地址字偏移 4 位
 *                 改 5 位：{idx,4'w}=槽×16+字 → {idx,5'w}=槽×32+字，对齐
 *                 walker（f6:330/335 {head[6:0],5'd0/14}）与 shell
 *                 （ppu_desc_if 32 字跨距）的 128 槽×32 字同表布局。原 4
 *                 位截断使槽≥1 的 GEMM 取到 {idx+1,前槽高半区} 影子字
 *                 （槽 1 读字 19/20/24/26/27 落槽 0 后半区），槽 0 恰好
 *                 掩盖——F7S run1 idx=1 首次暴露。E_IDLE 用本拍输入
 *                 desc_idx_i（desc_idx_q 非阻塞尚未更新），E_FLATCH 后续
 *                 用锁存 desc_idx_q；7+5=12 位纯拼接零进位链，ABI v2 字
 *                 义/表布局/口宽/BRAM 读延迟/E_FADDR-E_FLATCH 节拍全不
 *                 变；V1.9 y 地址方案保留。最大合法字段址 127×32+11=4075
 *                 < 表末 4095。
 ************************************************************************/
`timescale 1ns/1ps

module ppu_gemm_engine (
    // ---- 时钟/复位（F7 外壳同域） ----
    input  wire        clk_i,
    input  wire        rst_i,            // 同步高有效
    // ---- walker GEMM 槽（ppu_gemm_stub_f7 同形 + busy_o；单脉冲派发） ----
    input  wire        req_valid_i,
    input  wire [6:0]  desc_idx_i,
    input  wire [7:0]  opcode_i,
    output reg         done_o,           // 单脉冲
    output reg         err_o,            // 单脉冲
    output reg  [7:0]  err_code_o,       // 与 err_o 同拍有效，保持到下个 req
    output wire        busy_o,           // 高=占用（含恢复段）
    input  wire        abort_i,          // 静默取消
    output wire        rcvr_o,           // 恢复段指示（E_ABORT/E_ABORTS/
                                         // E_ERR/E_ERRC/E_ERRS；不含
                                         // E_ABORTD——排空期 DMA 须存活）
    // ---- desc BRAM 口 B（walker W_ENG 让渡期专用；1 拍读延迟） ----
    output reg  [11:0] desc_rd_addr_o,
    input  wire [31:0] desc_rd_data_i,
    // ---- DMA 用户侧（ppu_dma_master 用户口逐名镜像；P2.2 直连） ----
    output reg         rd_req_valid_o,
    input  wire        rd_req_ready_i,
    output reg  [31:0] rd_addr_o,
    output reg  [23:0] rd_len_o,
    input  wire        rd_beat_valid_i,
    output wire        rd_beat_ready_o,  // 装载段=gemm tready 直通（零缓冲）
    input  wire [63:0] rd_beat_data_i,
    input  wire        rd_done_i,
    output reg         wr_req_valid_o,
    input  wire        wr_req_ready_i,
    output reg  [31:0] wr_addr_o,
    output reg  [23:0] wr_len_o,
    output reg         wr_beat_valid_o,
    input  wire        wr_beat_ready_i,
    output reg  [63:0] wr_beat_data_o,
    output reg  [7:0]  wr_beat_strb_o,
    input  wire        wr_done_i,
    // ---- DMA 错误注入面（对端 ppu_dma_master err_pulse_o/err_code_o） ----
    input  wire        dma_err_pulse_i,
    input  wire [7:0]  dma_err_code_i
);

    // =================================================================
    // yolo_gemm_top 寄存器面（合同 §9；仅引擎用到的子集）
    // =================================================================
    localparam [7:0] R_CTRL   = 8'h04, R_STATUS = 8'h08, R_GEOM  = 8'h0C;
    localparam [7:0] R_ROWVAL = 8'h10, R_NMASK  = 8'h14, R_JOBCFG= 8'h18;
    localparam [7:0] R_LDGRP  = 8'h1C, R_P_BIAS = 8'h20, R_P_M   = 8'h24;
    localparam [7:0] R_P_SH   = 8'h28, R_PCTL   = 8'h2C, R_LDLEN = 8'h40;
    localparam [7:0] R_LUTD   = 8'h44, R_YSTAT  = 8'h48, R_BRGSTAT=8'h54;

    // 错误码（设计纪要 §6）
    localparam [7:0] EC_OPCODE = 8'h01, EC_GEOM   = 8'h02, EC_PRMDMA = 8'h03;
    localparam [7:0] EC_LUTDMA = 8'h04, EC_LOADDMA= 8'h05, EC_LDLEN  = 8'h06;
    localparam [7:0] EC_TMOUT  = 8'h07, EC_STATUS = 8'h08, EC_BRG    = 8'h09;
    localparam [7:0] EC_YCNT   = 8'h0A, EC_YWR    = 8'h0B;

    localparam [23:0] WAIT_TMO  = 24'hF_FFFF;  // 作业/pend 轮询上限 ~1M 次
    localparam [23:0] DMA_TMO   = 24'd4096;    // rd_done 缺席守卫
    localparam [7:0]  RST_SETTLE= 8'd64;       // soft_rst 后恢复等待

    // =================================================================
    // 主 FSM 状态
    // =================================================================
    localparam [5:0]
        E_IDLE=6'd0,  E_FADDR=6'd1,  E_FLATCH=6'd2, E_GEOM=6'd3,  E_GEOM2=6'd4,
        E_PRMREQ=6'd5,E_PRMDATA=6'd6,E_PRMDONE=6'd7,E_LUTREQ=6'd8,E_LUTDATA=6'd9,
        E_LUTWR=6'd10,E_LUTDN=6'd11, E_LUTCLR=6'd12,E_LUTCHK=6'd13,E_PCTL=6'd14,
        E_YARM=6'd15, E_LDGRPW=6'd16,E_SEGSET=6'd17,E_SEGREQ=6'd18,E_SEGDAT=6'd19,
        E_SEGDONE=6'd20,E_LDCHK0=6'd21,E_LDCHK1=6'd22,E_GEOMW=6'd23,
        E_JOBCFGW=6'd24,E_STARTW=6'd25,E_PENDW=6'd26,E_WAIT=6'd27,
        E_CHKB0=6'd28,E_CHKB1=6'd29,E_CHKY0=6'd30,E_CHKY1=6'd31,E_NEXTB=6'd32,
        E_DONE=6'd33, E_ERR=6'd34,  E_ERRC=6'd35, E_ERRS=6'd36, E_ABORT=6'd37,
        E_ABORTS=6'd38, E_ABORTD=6'd39,
        E_GEOM2B=6'd40, E_GEOM2C=6'd41;            // V1.6 GEOM 两级积流水

    reg [5:0]  state;

    // 恢复段指示：wash 复位窗 excl. E_ABORTD（W 突发排空中 DMA 不得复位）
    assign rcvr_o = (state == E_ABORT) || (state == E_ABORTS) ||
                    (state == E_ERR)   || (state == E_ERRC)   ||
                    (state == E_ERRS);

    // ---- desc 抓取 ----
    reg [6:0]  desc_idx_q;
    reg [2:0]  fcnt;                     // 0..4 → 字 {3,4,8,10,11}
    reg [31:0] dw_oc_ho, dw_wo, dw_arena, dw_param, dw_k_act;

    // ---- 几何派生 ----
    reg [11:0] kon;
    reg        has_act;
    reg [3:0]  n_strips;                 // ≤8（E_GEOM2 校）
    reg [15:0] rc_n;                     // ceil(oc/8) ≤64（校）
    reg [19:0] n_tile;
    reg [19:0] nb;                       // N_TILE*RC
    reg [23:0] tll;                      // 24*K
    reg [31:0] y_base;                   // arena+0x100+NB*tll
    reg [1:0]  nseg;
    reg [11:0] seg_k [0:2];

    // ---- 块/段游标（增量式：块→nt=b/RC, rc=b%RC, s=nt%n_strips） ----
    reg [5:0]  rc_q;
    reg [19:0] nt_q;
    reg [3:0]  s_q;
    reg [19:0] blk;
    reg [1:0]  seg;
    reg [23:0] cum;                      // 段累计字节偏移
    reg [19:0] seg_beats, seg_total;

    // ---- LUT 装载 ----
    reg [4:0]  lut_beat;                 // 0..31
    reg [2:0]  lut_byte;                 // 0..7
    reg [63:0] lut_data_q;
    reg [5:0]  pctl_step;                // 0..33（32 PCTL 写 + ROWVAL + NMASK）

    // ---- 参数阵列：行×12B=3 字/行（bias|M|sh）；≤512 行 → 1536 字；异步读 ----
    // V1.5：64b 字形——32b 形每拍双写+读口=3 口不可推断 RAM（Synth 8-3391）；
    //       单写口（64b/拍）+ 异步读 → 分布式 RAM；读侧半选恢复 32b 视图
    reg [63:0] prm [0:1535];
    reg [11:0] prm_wa, prm_bc, prm_bt;
    // V1.7：块基址寄存（rc_q*24 随块推进，一寄/块）——读址只剩步内小加，
    //       斩 rc_q→乘加链→RAM→半选 10.5ns 路径（round-4 WNS -0.695 根因）
    reg [11:0] prm_base_q;                         // = rc_q*24（rc_q 各写点同步维护）
    wire [11:0] prm_ra = prm_base_q
                       + {9'd0, pctl_step[4:2]} * 12'd3
                       + {10'd0, pctl_step[1:0]};  // 32b 字粒度读索引
    reg  [63:0] prm_rw;                            // 读暂存（Verilog 元素位选非法）
    always @(*) prm_rw = prm[prm_ra[11:1]];

    // ---- 流完成旗标（rd_done 是脉冲，跨态捕获） ----
    reg        rd_done_seen, wr_done_seen;
    reg        y_armed;
    reg [4:0]  y_sent_q;                   // 本块已握手 W 拍（arm 时清）
    reg [5:0]  fl_left_q;                  // E_ABORTD 冲刷剩余拍
    reg [31:0] y_addr_q;                   // V1.9：y 绝对地址寄存器（E_IDLE 锁
                                           // y_base，E_NEXTB 按 btt_w 推进；
                                           // wr_addr_o 锁存路径 FF→FF 零逻辑，
                                           // 基址加法移出请求路径——r6 余量
                                           // WNS+0.042 下的时序加固）

    // ---- 轮询/恢复 ----
    reg [23:0] tmo;
    reg [7:0]  settle;
    reg [7:0]  err_code_q;
    reg [31:0] rd_q;

    // ---- AXI-Lite 命令面（主 FSM → 子 FSM） ----
    reg         cmd_start;
    reg         cmd_wr;
    reg  [7:0]  cmd_addr;
    reg  [31:0] cmd_wdata;
    wire        cmd_done;
    wire [31:0] cmd_rdata;

    assign busy_o = (state != E_IDLE);

    // ---- 块内派生线（strip vc/nmask/btt/y 地址；连续组合，无除法） ----
    // V1.6：GEOM 两级积改寄存（原 wire 串行链 n_tile*rc_n*tll = 双 DSP 级联
    //       + 比较/加法同拍 14.3ns > 10ns，v24 首轮 WNS -4.725 根因）
    reg [35:0] nb_full_q;                          // 全宽积（守卫后才截位）
    reg [59:0] span_full_q;                        // NB*tll 字节跨距
    wire [15:0] s_x16   = {12'd0, s_q} * 16'd16;
    wire [15:0] wo_rem  = dw_wo[15:0] - s_x16;
    wire [4:0]  vc_w    = (wo_rem >= 16'd16) ? 5'd16 : {11'd0, wo_rem[4:0]};
    wire [16:0] nm_full = (17'd1 << vc_w) - 17'd1;
    wire [15:0] nmask_w = nm_full[15:0];
    wire [7:0]  btt_w   = {vc_w, 3'd0};
    // V1.8/V1.9：固定跨距 blk*128 改紧凑推进（尾条带 32B 块不再跳 128——
    // Wo 非 16 倍数时原律留 96B 块间空洞并越窗溢出，P25 板 H4 根因）。
    // V1.9：地址即寄存器 y_addr_q（绝对），请求路径无加法器。
    wire [23:0] blk_tll = {4'd0, blk} * tll;   // NB*tll<2^24 已在 GEOM2 守卫

    // ---- 装载 tlast（总拍数-1 处组合补拍） ----
    wire ld_tlast = (seg_beats == seg_total - 1'b1);

    // =================================================================
    // 内部 yolo_gemm_top V1.2 例化（单一 module_ref，P2.2 换装点）
    // =================================================================
    wire        s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_arready;
    wire [1:0]  s_axi_bresp, s_axi_rresp;
    wire        s_axi_rvalid;
    wire [31:0] s_axi_rdata;
    reg  [31:0] ax_awaddr, ax_wdata, ax_araddr;
    reg  [2:0]  ax_awprot, ax_arprot;
    reg  [3:0]  ax_wstrb;
    reg         ax_awvalid, ax_wvalid, ax_arvalid;
    wire        ld_tready;
    wire [63:0] y_tdata;
    wire        y_tvalid, y_tlast;

    yolo_gemm_top u_gemm (
        .s_axi_aclk    (clk_i),
        .s_axi_aresetn (~rst_i),
        .s_axi_awaddr  (ax_awaddr),  .s_axi_awprot (ax_awprot),
        .s_axi_awvalid (ax_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata   (ax_wdata),   .s_axi_wstrb  (ax_wstrb),
        .s_axi_wvalid  (ax_wvalid),  .s_axi_wready (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),.s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready  (1'b1),
        .s_axi_araddr  (ax_araddr),  .s_axi_arprot (ax_arprot),
        .s_axi_arvalid (ax_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),.s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),.s_axi_rready(1'b1),
        // 装载流：DMA rd → s_axis_ld 直通（零缓冲；tlast 引擎补拍）
        .s_axis_ld_tdata (rd_beat_data_i),
        .s_axis_ld_tvalid(rd_beat_valid_i && (state == E_SEGDAT)),
        .s_axis_ld_tready(ld_tready),
        .s_axis_ld_tlast (ld_tlast && (state == E_SEGDAT)),
        // y 流：m_axis_y → DMA wr 直通（一级寄存器节，len 计拍）
        .m_axis_y_tdata (y_tdata),  .m_axis_y_tvalid(y_tvalid),
        .m_axis_y_tready(y_armed && wr_beat_ready_i),
        .m_axis_y_tlast (y_tlast)
    );

    // rd 就绪路由：装载段随 gemm tready（背压透传）；参数/LUT 段引擎自收
    assign rd_beat_ready_o = (state == E_SEGDAT)  ? ld_tready :
                             ((state == E_PRMDATA) || (state == E_LUTDATA))
                             ? 1'b1 : 1'b0;

    // =================================================================
    // AXI-Lite 主侧子 FSM（aw/w 独立握手并发；ar→r）
    // =================================================================
    localparam [2:0] S_IDLE=3'd0, S_AW=3'd1, S_B=3'd2, S_AR=3'd3, S_R=3'd4;
    reg [2:0]  axs;
    reg        ax_aw_done, ax_w_done;
    reg        cmd_done_r;
    reg [31:0] cmd_rdata_r;

    assign cmd_done  = cmd_done_r;
    assign cmd_rdata = cmd_rdata_r;

    always @(posedge clk_i) begin
        if (rst_i) begin
            axs <= S_IDLE; cmd_done_r <= 1'b0; cmd_rdata_r <= 32'd0;
            ax_awvalid <= 1'b0; ax_wvalid <= 1'b0; ax_arvalid <= 1'b0;
            ax_aw_done <= 1'b0; ax_w_done <= 1'b0;
            ax_awaddr <= 32'd0; ax_wdata <= 32'd0; ax_araddr <= 32'd0;
            ax_awprot <= 3'd0; ax_arprot <= 3'd0; ax_wstrb <= 4'hF;
        end else begin
            cmd_done_r <= 1'b0;                        // 单脉冲
            case (axs)
              // done 拍禁收：cmd_start 在 done 拍仍高（主 FSM 清零落在
              // 沿后），此拍接收会采样到旧 cmd_addr → 重复执行上一条命令
              // （E_WAIT 完成支路同沿重发 BRGSTAT 曾因此重读 STATUS 0x28；
              //   E_PCTL/E_LUTWR 连续发起型曾因此步骤截断/LUT 半载）。
              S_IDLE: if (cmd_start && !cmd_done_r) begin
                  if (cmd_wr) begin
                      ax_awaddr <= {24'd0, cmd_addr}; ax_wdata <= cmd_wdata;
                      ax_awvalid <= 1'b1; ax_wvalid <= 1'b1;
                      ax_aw_done <= 1'b0; ax_w_done <= 1'b0;
                      axs <= S_AW;
                  end else begin
                      ax_araddr <= {24'd0, cmd_addr}; ax_arvalid <= 1'b1;
                      axs <= S_AR;
                  end
              end
              S_AW: begin
                  if (ax_awvalid && s_axi_awready) ax_aw_done <= 1'b1;
                  if (ax_wvalid   && s_axi_wready) ax_w_done  <= 1'b1;
                  if (ax_aw_done || (ax_awvalid && s_axi_awready))
                      ax_awvalid <= 1'b0;
                  if (ax_w_done  || (ax_wvalid  && s_axi_wready))
                      ax_wvalid  <= 1'b0;
                  if ((ax_aw_done || (ax_awvalid && s_axi_awready)) &&
                      (ax_w_done  || (ax_wvalid  && s_axi_wready)))
                      axs <= S_B;
              end
              S_B: if (s_axi_bvalid) begin
                  cmd_done_r <= 1'b1;                  // bresp 不查（全译码）
                  axs <= S_IDLE;
              end
              S_AR: if (s_axi_arready) begin
                  ax_arvalid <= 1'b0; axs <= S_R;
              end
              S_R: if (s_axi_rvalid) begin
                  cmd_rdata_r <= s_axi_rdata; cmd_done_r <= 1'b1;
                  axs <= S_IDLE;
              end
              default: axs <= S_IDLE;
            endcase
        end
    end

    // =================================================================
    // 主 FSM
    // =================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= E_IDLE; done_o <= 1'b0; err_o <= 1'b0; err_code_o <= 8'd0;
            cmd_start <= 1'b0; cmd_wr <= 1'b0; cmd_addr <= 8'd0;
            cmd_wdata <= 32'd0;
            rd_req_valid_o <= 1'b0; rd_addr_o <= 32'd0; rd_len_o <= 24'd0;
            wr_req_valid_o <= 1'b0; wr_addr_o <= 32'd0; wr_len_o <= 24'd0;
            wr_beat_valid_o <= 1'b0; wr_beat_data_o <= 64'd0;
            wr_beat_strb_o <= 8'hFF;
            desc_rd_addr_o <= 12'd0; fcnt <= 3'd0;
            y_armed <= 1'b0; rd_done_seen <= 1'b0; wr_done_seen <= 1'b0;
            y_sent_q <= 5'd0; fl_left_q <= 6'd0;
            y_addr_q <= 32'd0;                   // V1.9：地址寄存器随复位清
            settle <= 8'd0; tmo <= 24'd0; err_code_q <= 8'd0;
            blk <= 20'd0; seg <= 2'd0; cum <= 24'd0;
            rc_q <= 6'd0; nt_q <= 20'd0; s_q <= 4'd0;
            prm_base_q <= 12'd0;                     // V1.7：基址随 rc_q 同步清
            lut_beat <= 5'd0; lut_byte <= 3'd0;
            prm_wa <= 12'd0; prm_bc <= 12'd0; prm_bt <= 12'd0;
        end else begin
            // ---- 单脉冲消隐 ----
            done_o <= 1'b0; err_o <= 1'b0;

            // ---- 流完成旗标捕获（任意态） ----
            if (rd_done_i) rd_done_seen <= 1'b1;
            if (wr_done_i) begin
                wr_done_seen <= 1'b1; y_armed <= 1'b0;
            end

            // ---- y 写通道一级寄存节（tvalid/tdata/tready 三态一致；
            //      E_ABORTD 期由态内冲刷逻辑 override 供拍，此处不出拍
            //      （防自然路径在冲刷后加拍破坏突发计数）。
            //      V1.4 保持守卫：出口拍悬挂（valid=1 且 !ready）期间不
            //      重算捕获——核已按 tready(=armed&&ready) 弹出的字若被
            //      下一拍 ready=0 的无条件重算清零即 CLOBBER 丢字（系统
            //      面随机 wready 必现；单元模型 ready 恒 1 不可见）。----
            if (state != E_ABORTD) begin
                if (!wr_beat_valid_o || wr_beat_ready_i) begin
                    wr_beat_valid_o <= y_armed && y_tvalid
                                       && wr_beat_ready_i;
                    wr_beat_data_o  <= y_tdata;
                end
            end
            // 已握手拍记账（arm 清零；冲刷拍也计入——fl_left 入口一次定）
            if (wr_beat_valid_o && wr_beat_ready_i)
                y_sent_q <= y_sent_q + 5'd1;

            // ---- DMA 错误：占用态 → E_ERR（码按相位） ----
            if (dma_err_pulse_i && state != E_IDLE && state != E_DONE &&
                state != E_ERR  && state != E_ERRC && state != E_ERRS &&
                state != E_ABORT && state != E_ABORTS) begin
                err_code_q <= (state == E_PRMREQ || state == E_PRMDATA ||
                               state == E_PRMDONE) ? EC_PRMDMA :
                              (state == E_LUTREQ || state == E_LUTDATA ||
                               state == E_LUTWR  || state == E_LUTDN) ? EC_LUTDMA :
                              EC_LOADDMA;
                rd_req_valid_o <= 1'b0; wr_req_valid_o <= 1'b0;
                y_armed <= 1'b0; cmd_start <= 1'b0;
                state <= E_ERR;
            end else
            case (state)
              // -------------------------------------------------------
              E_IDLE: if (req_valid_i) begin
                  desc_idx_q <= desc_idx_i;
                  err_code_o <= 8'd0;
                  blk <= 20'd0; seg <= 2'd0; cum <= 24'd0;
                  rc_q <= 6'd0; nt_q <= 20'd0; s_q <= 4'd0;
                  prm_base_q <= 12'd0;                 // V1.7：基址随 rc_q 同步清
                  // V1.9：y_addr_q 改在 E_GEOM2C 随 y_base 同拍锁存（描述符
                  // 几何校验过才立地址；E_IDLE 时描述符尚未取数）
                  wr_done_seen <= 1'b0; rd_done_seen <= 1'b0;
                  if (opcode_i != 8'h01) begin
                      err_code_q <= EC_OPCODE; state <= E_ERR;
                  end else begin
                      fcnt <= 3'd0;
                      desc_rd_addr_o <= {desc_idx_i, 5'd3};
                      state <= E_FADDR;
                  end
              end
              // ---- desc 抓取（字序 3,4,8,10,11；口 B 1 拍延迟，2 拍/字；
              //      V2.0 槽跨距 32：{idx[6:0],5'w} 对齐 walker/shell 同表布局） ----
              E_FADDR: state <= E_FLATCH;
              E_FLATCH: begin
                  case (fcnt)
                    3'd0: dw_oc_ho <= desc_rd_data_i;
                    3'd1: dw_wo    <= desc_rd_data_i;
                    3'd2: dw_arena <= desc_rd_data_i;
                    3'd3: dw_param <= desc_rd_data_i;
                    default: dw_k_act <= desc_rd_data_i;
                  endcase
                  state <= E_GEOM;
                  if (fcnt != 3'd4) begin
                      fcnt <= fcnt + 3'd1;
                      case (fcnt)
                        3'd0: desc_rd_addr_o <= {desc_idx_q, 5'd4};
                        3'd1: desc_rd_addr_o <= {desc_idx_q, 5'd8};
                        3'd2: desc_rd_addr_o <= {desc_idx_q, 5'd10};
                        default: desc_rd_addr_o <= {desc_idx_q, 5'd11};
                      endcase
                      state <= E_FADDR;
                  end
              end
              // ---- 几何/链律派生（值寄存，合法性留 GEOM2 统一校） ----
              E_GEOM: begin
                  kon     <= dw_k_act[11:0];
                  has_act <= dw_k_act[12];
                  n_strips<= (dw_wo[15:0] + 16'd15) >> 4;
                  rc_n    <= (dw_oc_ho[15:0] + 16'd7) >> 3;
                  n_tile  <= dw_oc_ho[31:16]
                             * (((dw_wo[15:0] + 16'd15) >> 4));
                  tll     <= {12'd0, dw_k_act[11:0]} * 24'd24;
                  state <= E_GEOM2;
                  // 链律（conv_packer.b1_chain 逐字转录）
                  if (dw_k_act[11:0] <= 12'd576) begin
                      nseg <= 2'd1; seg_k[0] <= dw_k_act[11:0];
                  end else if (dw_k_act[11:0] == 12'd1024) begin
                      nseg <= 2'd1; seg_k[0] <= 12'd1024;
                  end else if (dw_k_act[11:0] == 12'd1152) begin
                      nseg <= 2'd2; seg_k[0] <= 12'd1024; seg_k[1] <= 12'd128;
                  end else if (dw_k_act[11:0] == 12'd2304) begin
                      nseg <= 2'd3; seg_k[0] <= 12'd1024;
                      seg_k[1] <= 12'd1024; seg_k[2] <= 12'd256;
                  end else begin
                      err_code_q <= EC_GEOM; state <= E_ERR;
                  end
              end
              // ---- GEOM 校验/派生（V1.6：两级积各一拍，斩串行 DSP 链）----
              E_GEOM2: begin
                  nb_full_q <= n_tile * rc_n;      // 第 1 级积（单 DSP 拍）
                  // 独立小算术前置（源均寄存：rc_n/dw_param；原序值等价，
                  // 仅在 E_GEOM2C 置 valid 后方生效，err 路径不发射）
                  prm_bt  <= rc_n[11:0] * 12'd12;  // RC*8 行×12B/8 = RC*12 拍
                  prm_wa  <= 12'd0; prm_bc <= 12'd0;
                  rd_addr_o <= dw_param;
                  rd_len_o  <= {16'd0, rc_n} * 24'd96;  // RC*8*12 B
                  state <= E_GEOM2B;
              end
              E_GEOM2B: begin
                  span_full_q <= nb_full_q * tll;  // 第 2 级积（源=已寄存积）
                  state <= E_GEOM2C;
              end
              E_GEOM2C: begin
                  if (dw_oc_ho[15:0] == 16'd0 || dw_oc_ho[31:16] == 16'd0 ||
                      dw_wo[15:0] == 16'd0 || n_strips > 4'd8 ||
                      rc_n > 16'd64 || nb_full_q >= 36'd1048576 ||
                      span_full_q >= 60'd16777216) begin
                      err_code_q <= EC_GEOM; state <= E_ERR;
                  end else begin
                      nb      <= nb_full_q[19:0];
                      y_base  <= dw_arena + 32'h100 + {8'd0, span_full_q[23:0]};
                      // V1.9：绝对地址寄存器同拍同表达式锁存——与 y_base
                      // 共享同一 32b 加法器（纯并行 FF 目标，零新增逻辑），
                      // 基址加法自此离开 wr_addr_o 请求路径
                      y_addr_q <= dw_arena + 32'h100 + {8'd0, span_full_q[23:0]};
                      rd_req_valid_o <= 1'b1;
                      state <= E_PRMREQ;
                  end
              end
              // ---- 参数段 DMA（RC*8 行 ×24B → 内部阵列，2 字/拍） ----
              E_PRMREQ: if (rd_req_valid_o && rd_req_ready_i) begin
                  rd_req_valid_o <= 1'b0;
                  state <= E_PRMDATA;
              end
              E_PRMDATA: if (rd_beat_valid_i) begin
                  // V1.5：每拍单写 64b 字（字址=prm_wa>>1；prm_wa 仍按 32b 字计）
                  prm[prm_wa[11:1]] <= rd_beat_data_i;
                  prm_wa <= prm_wa + 12'd2;
                  prm_bc <= prm_bc + 12'd1;
                  if (prm_bc == prm_bt - 12'd1) begin
                      tmo <= 24'd0; state <= E_PRMDONE;
                  end
              end
              E_PRMDONE: begin
                  if (rd_done_seen) begin
                      rd_done_seen <= 1'b0;
                      if (has_act) begin
                          rd_addr_o <= dw_arena; rd_len_o <= 24'd256;
                          rd_req_valid_o <= 1'b1;
                          lut_beat <= 5'd0; lut_byte <= 3'd0;
                          state <= E_LUTREQ;
                      end else begin
                          pctl_step <= 6'd0; state <= E_PCTL;
                      end
                  end else if (tmo >= DMA_TMO) begin
                      err_code_q <= EC_PRMDMA; state <= E_ERR;
                  end else tmo <= tmo + 24'd1;
              end
              // ---- LUT 段装载（256B → LUTD×256，随收随写） ----
              E_LUTREQ: if (rd_req_valid_o && rd_req_ready_i) begin
                  rd_req_valid_o <= 1'b0;
                  state <= E_LUTDATA;
              end
              E_LUTDATA: if (rd_beat_valid_i) begin
                  lut_data_q <= rd_beat_data_i;
                  state <= E_LUTWR;
              end
              E_LUTWR: begin
                  if (!cmd_done) begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_LUTD;
                      cmd_wdata <= {16'd0, lut_beat, lut_byte,
                                    lut_data_q[8*lut_byte +: 8]};
                  end
                  if (cmd_done) begin
                      cmd_start <= 1'b0;
                      if (lut_byte == 3'd7) begin
                          if (lut_beat == 5'd31) begin
                              tmo <= 24'd0; state <= E_LUTDN;
                          end else begin
                              lut_beat <= lut_beat + 5'd1; lut_byte <= 3'd0;
                              state <= E_LUTDATA;
                          end
                      end else lut_byte <= lut_byte + 3'd1;
                  end
              end
              E_LUTDN: begin
                  if (rd_done_seen) begin
                      rd_done_seen <= 1'b0;
                      cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_CTRL;
                      cmd_wdata <= 32'h4;                 // err_clr 正典
                      state <= E_LUTCLR;
                  end else if (tmo >= DMA_TMO) begin
                      err_code_q <= EC_LUTDMA; state <= E_ERR;
                  end else tmo <= tmo + 24'd1;
              end
              E_LUTCLR: if (cmd_done) begin
                  cmd_start <= 1'b1; cmd_wr <= 1'b0; cmd_addr <= R_STATUS;
                  state <= E_LUTCHK;
              end
              E_LUTCHK: if (cmd_done) begin
                  cmd_start <= 1'b0;
                  if (cmd_addr == R_STATUS) begin
                      if (cmd_rdata[9:6] != 4'd0) begin
                          err_code_q <= EC_STATUS; state <= E_ERR;
                      end else begin
                          cmd_start <= 1'b1; cmd_addr <= R_BRGSTAT;
                      end
                  end else begin
                      if (cmd_rdata[4:2] != 3'd0) begin
                          err_code_q <= EC_BRG; state <= E_ERR;
                      end else begin
                          pctl_step <= 6'd0; state <= E_PCTL;
                      end
                  end
              end
              // ---- 块循环：PCTL×8 + ROWVAL/NMASK（正典逐块全写，34 步） ----
              E_PCTL: begin
                  if (!cmd_done) begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b1;
                      if (pctl_step < 6'd32) begin
                          if (pctl_step[1:0] == 2'd3) begin
                              cmd_addr <= R_PCTL;
                              // 板证字面 0x100|r（bit8=we, [2:0]=行）
                              cmd_wdata <= {23'd0, 1'b1, 5'd0,
                                             pctl_step[4:2]};
                          end else begin
                              cmd_addr <= (pctl_step[1:0] == 2'd0) ? R_P_BIAS :
                                          (pctl_step[1:0] == 2'd1) ? R_P_M
                                                                   : R_P_SH;
                              cmd_wdata <= prm_ra[0] ? prm_rw[63:32]
                                                     : prm_rw[31:0];
                          end
                      end else if (pctl_step == 6'd32) begin
                          cmd_addr <= R_ROWVAL; cmd_wdata <= 32'h0000_00FF;
                      end else begin
                          cmd_addr <= R_NMASK;  cmd_wdata <= {16'd0, nmask_w};
                      end
                  end
                  if (cmd_done) begin
                      cmd_start <= 1'b0;
                      if (pctl_step == 6'd33) begin
                          // V1.9：FF→FF 直取（原 y_addr_w=y_base+游标 的 32b
                          // 加法已移至 E_GEOM2C 一次性完成）
                          wr_addr_o <= y_addr_q; wr_len_o <= {16'd0, btt_w};
                          wr_req_valid_o <= 1'b1;
                          state <= E_YARM;
                      end else pctl_step <= pctl_step + 6'd1;
                  end
              end
              // ---- y 写 arm（每块一次，首段前） ----
              E_YARM: if (wr_req_valid_o && wr_req_ready_i) begin
                  wr_req_valid_o <= 1'b0; y_armed <= 1'b1;
                  y_sent_q <= 5'd0;                  // 拍记账随 arm 清零
                  cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_LDGRP;
                  // grp 律两 case：单段链=块奇偶 b&1（pl_p13_k576
                  // blk_geom 板证）；多段链=段奇偶 seg%2 → 3/0
                  cmd_wdata <= (nseg == 2'd1) ? {30'd0, blk[0], blk[0]}
                                              : {30'd0, seg[0], seg[0]};
                  state <= E_LDGRPW;
              end
              E_LDGRPW: if (cmd_done) begin
                  cmd_start <= 1'b0;
                  rd_addr_o <= dw_arena + 32'h100 + {8'd0, blk_tll}
                               + {8'd0, cum};
                  rd_len_o  <= {12'd0, seg_k[seg]} * 24'd24;
                  seg_beats <= 20'd0;
                  seg_total <= {17'd0, seg_k[seg]} * 20'd3;
                  rd_req_valid_o <= 1'b1;
                  state <= E_SEGREQ;
              end
              E_SEGREQ: if (rd_req_valid_o && rd_req_ready_i) begin
                  rd_req_valid_o <= 1'b0;
                  state <= E_SEGDAT;
              end
              E_SEGDAT: if (rd_beat_valid_i && ld_tready) begin
                  seg_beats <= seg_beats + 20'd1;
                  if (ld_tlast) begin tmo <= 24'd0; state <= E_SEGDONE; end
              end
              E_SEGDONE: begin
                  if (rd_done_seen) begin
                      rd_done_seen <= 1'b0;
                      cmd_start <= 1'b1; cmd_wr <= 1'b0; cmd_addr <= R_LDLEN;
                      state <= E_LDCHK0;
                  end else if (tmo >= DMA_TMO) begin
                      err_code_q <= EC_LOADDMA; state <= E_ERR;
                  end else tmo <= tmo + 24'd1;
              end
              E_LDCHK0: if (cmd_done) begin
                  cmd_start <= 1'b0; rd_q <= cmd_rdata; state <= E_LDCHK1;
              end
              E_LDCHK1: begin
                  if (rd_q[12:0] != seg_k[seg] || rd_q[25:13] != seg_k[seg])
                      begin err_code_q <= EC_LDLEN; state <= E_ERR; end
                  else begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_GEOM;
                      cmd_wdata <= {20'd0, seg_k[seg]}; state <= E_GEOMW;
                  end
              end
              E_GEOMW: if (cmd_done) begin
                  cmd_start <= 1'b1; cmd_addr <= R_JOBCFG; cmd_wr <= 1'b1;
                  cmd_wdata <= {24'd0, has_act}
                               | ((seg == 2'd0) ? 32'h2 : 32'h0)
                               | ((seg == nseg - 2'd1) ? 32'h4 : 32'h0)
                               // grp 位同 LDGRP 两 case 律（K576 板证
                               // 单段=块奇偶；K2304 J1/J2/J3=段奇偶）
                               | ((((nseg == 2'd1) ? blk[0] : seg[0])
                                   ? 1'b1 : 1'b0) ? 32'h18 : 32'h0);
                  state <= E_JOBCFGW;
              end
              E_JOBCFGW: if (cmd_done) begin
                  cmd_start <= 1'b1; cmd_addr <= R_CTRL; cmd_wr <= 1'b1;
                  cmd_wdata <= 32'h1; state <= E_STARTW;
              end
              E_STARTW: if (cmd_done) begin
                  cmd_start <= 1'b0; tmo <= 24'd0;
                  if (seg == nseg - 2'd1) state <= E_WAIT;
                  else                     state <= E_PENDW;
              end
              // ---- 非束段：串行等 job_pend 清（多段路径，K576 不触及） ----
              E_PENDW: begin
                  if (!cmd_start && !cmd_done) begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b0; cmd_addr <= R_STATUS;
                  end
                  if (cmd_done) begin
                      cmd_start <= 1'b0;
                      if (cmd_rdata[1] == 1'b0) begin
                          cum <= cum + 24'd24 * {12'd0, seg_k[seg]};
                          seg <= seg + 2'd1;
                          cmd_start <= 1'b1; cmd_wr <= 1'b1;
                          cmd_addr <= R_LDGRP;
                          // 下一链段 grp=(seg+1)%2（RHS 用旧值取反）
                          cmd_wdata <= {30'd0, ~seg[0], ~seg[0]};
                          state <= E_LDGRPW;
                      end else if (tmo >= WAIT_TMO) begin
                          err_code_q <= EC_TMOUT; state <= E_ERR;
                      end else tmo <= tmo + 24'd1;
                  end
              end
              // ---- 束段作业完成轮询：busy=0 & tile_done & pend=0 ----
              E_WAIT: begin
                  if (!cmd_start && !cmd_done) begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b0; cmd_addr <= R_STATUS;
                  end
                  if (cmd_done) begin
                      cmd_start <= 1'b0; rd_q <= cmd_rdata;
                      if (cmd_rdata[1:0] == 2'b00 && cmd_rdata[5]) begin
                          if (cmd_rdata[9:6] != 4'd0) begin
                              err_code_q <= EC_STATUS; state <= E_ERR;
                          end else begin
                              cmd_start <= 1'b1; cmd_addr <= R_BRGSTAT;
                              state <= E_CHKB0;
                          end
                      end else if (tmo >= WAIT_TMO) begin
                          err_code_q <= EC_TMOUT; state <= E_ERR;
                      end else tmo <= tmo + 24'd1;
                  end
              end
              E_CHKB0: if (cmd_done) begin
                  cmd_start <= 1'b0; rd_q <= cmd_rdata; state <= E_CHKB1;
              end
              E_CHKB1: begin
                  if (rd_q[4:2] != 3'd0 || rd_q[1] == 1'b0) begin
                      err_code_q <= EC_BRG; state <= E_ERR;
                  end else begin
                      cmd_start <= 1'b1; cmd_wr <= 1'b0; cmd_addr <= R_YSTAT;
                      state <= E_CHKY0;
                  end
              end
              E_CHKY0: if (cmd_done) begin
                  cmd_start <= 1'b0; rd_q <= cmd_rdata; tmo <= 24'd0;
                  state <= E_CHKY1;
              end
              E_CHKY1: begin
                  if (rd_q[15:0] != {11'd0, btt_w}) begin
                      err_code_q <= EC_YCNT; state <= E_ERR;
                  end else if (!wr_done_seen) begin
                      // V1.4：y 写收尾有界等待——wr_done 走 AXI B 链有
                      // ~10 拍尾延（单元模型 +2 拍），零等待判决在系统/
                      // 板级 B 延时下令 EC_YWR 误报；DMA_TMO 内真缺失
                      // 仍报（保活性不变）。
                      if (tmo >= DMA_TMO) begin
                          err_code_q <= EC_YWR; state <= E_ERR;
                      end else tmo <= tmo + 24'd1;
                  end else state <= E_NEXTB;
              end
              E_NEXTB: begin
                  if (blk + 20'd1 >= nb) begin
                      state <= E_DONE;
                  end else begin
                      // V1.8/V1.9：当前块 wr_done_seen 已成立（E_CHKY1 判据），
                      // 为下一块推进紧凑地址——btt_w 通用推进量（非 128/32
                      // 硬编码，保 Wo=32 等几何），异常路径不经此不提交增量
                      y_addr_q <= y_addr_q + {24'd0, btt_w};
                      blk <= blk + 20'd1; seg <= 2'd0; cum <= 24'd0;
                      wr_done_seen <= 1'b0; pctl_step <= 6'd0;
                      if (rc_q + 6'd1 == rc_n[5:0]) begin
                          rc_q <= 6'd0; nt_q <= nt_q + 20'd1;
                          s_q <= (s_q + 4'd1 == n_strips) ? 4'd0 : s_q + 4'd1;
                          prm_base_q <= 12'd0;        // V1.7：随 rc_q 回卷清
                      end else begin
                          rc_q <= rc_q + 6'd1;
                          prm_base_q <= prm_base_q + 12'd24;  // V1.7：随块推进
                      end
                      state <= E_PCTL;
                  end
              end
              E_DONE: begin
                  done_o <= 1'b1; state <= E_IDLE;
              end
              // ---- 错误恢复序幕：err 脉冲 + err_clr + soft_rst ----
              E_ERR: begin
                  err_o <= 1'b1; err_code_o <= err_code_q;
                  cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_CTRL;
                  cmd_wdata <= 32'h4;
                  state <= E_ERRC;
              end
              E_ERRC: if (cmd_done) begin
                  cmd_start <= 1'b0;
                  cmd_start <= 1'b1; cmd_wdata <= 32'h2;    // soft_rst
                  settle <= RST_SETTLE; state <= E_ERRS;
              end
              E_ERRS: begin
                  if (cmd_done) cmd_start <= 1'b0;
                  if (settle != 8'd0) settle <= settle - 8'd1;
                  else if (!cmd_start) state <= E_IDLE;
              end
              // ---- 静默中止：无 done/err，soft_rst 恢复 ----
              E_ABORT: begin
                  cmd_start <= 1'b1; cmd_wr <= 1'b1; cmd_addr <= R_CTRL;
                  cmd_wdata <= 32'h2;
                  settle <= RST_SETTLE; state <= E_ABORTS;
              end
              E_ABORTS: begin
                  if (cmd_done) cmd_start <= 1'b0;
                  if (settle != 8'd0) settle <= settle - 8'd1;
                  else if (!cmd_start) state <= E_IDLE;
              end
              // ---- abort 排空（V1.3）：y 写在途 → 冲刷收口再拆 ----
              // 统一策略：以 strb=0 空拍补齐剩余 W 拍（AXI 合法零字节写，
              // y 区无需保真——帧已弃）。核心 y 流经一级寄存节被本态
              // override 丢弃（tready 照常，无背压死锁）；DMA 按自身
              // 突发计划收 wlast/B → wr_done。tmo 超时保活性（余突发交
              // f7_top wash 复位处置，仅病理态触及）。
              E_ABORTD: begin
                  if (cmd_done) cmd_start <= 1'b0;
                  if (fl_left_q != 6'd0 &&
                      (!wr_beat_valid_o || wr_beat_ready_i)) begin
                      wr_beat_valid_o <= 1'b1;
                      wr_beat_data_o  <= 64'd0;
                      wr_beat_strb_o  <= 8'h00;
                      fl_left_q <= fl_left_q - 6'd1;
                  end
                  if (wr_done_i) begin
                      wr_beat_valid_o <= 1'b0;
                      wr_beat_strb_o  <= 8'hFF;     // 满拍恢复（后续块）
                      state <= E_ABORT;             // y_armed 已被全局捕获清零
                  end else if (tmo >= DMA_TMO) begin
                      y_armed <= 1'b0;
                      wr_beat_valid_o <= 1'b0;
                      wr_beat_strb_o  <= 8'hFF;
                      state <= E_ABORT;
                  end else tmo <= tmo + 24'd1;
              end
              default: state <= E_IDLE;
            endcase

            // ---- abort：任意占用态（恢复态除外）→ 静默取消 ----
            // V1.3：y 写在途（y_armed 置位中，或本拍 E_YARM wr_req 握手
            // ——请求已被 DMA 受理、AW 可能已在互连在途）改入 E_ABORTD
            // 冲刷收口，其余直入 E_ABORT。冲刷剩余拍 = vc − 已握手拍；
            // E_YARM 同拍 abort 的拍记账清零未生效，取整 vc。
            if (abort_i && state != E_IDLE && state != E_ABORT &&
                state != E_ABORTS && state != E_ABORTD) begin
                if (y_armed || (state == E_YARM && wr_req_valid_o &&
                                wr_req_ready_i)) begin
                    rd_req_valid_o <= 1'b0; cmd_start <= 1'b0;
                    tmo <= 24'd0;
                    fl_left_q <= (state == E_YARM) ? {1'b0, vc_w}
                                  : ({1'b0, vc_w} - {1'b0, y_sent_q});
                    state <= E_ABORTD;      // E_YARM 支路的 y_armed<=1 保留
                end else begin
                    state <= E_ABORT; cmd_start <= 1'b0;
                    rd_req_valid_o <= 1'b0; wr_req_valid_o <= 1'b0;
                    y_armed <= 1'b0;
                end
            end
        end
    end

endmodule
