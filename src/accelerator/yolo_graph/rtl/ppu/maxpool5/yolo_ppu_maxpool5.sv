/************************************************************************
 * File Name       : yolo_ppu_maxpool5.sv
 * Developer       : LSL
 * Date            : 2026-09-24
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_ppu_maxpool5
 * Description     : maxpool5 核——流式行缓冲 + 固定 5x5 窗 + 平衡 max 树
 *                   （Stage3-v2 结构整改落位：C 变体 V2.2 经 OOC routed
 *                   timing A/B/C 三比择优替换 A 正身，2026-09-24）。
 *                   替换前 A 正身（269 深全局延迟线 + 运行时动态下标 +
 *                   25 级串行比较链）备份于同目录
 *                   yolo_ppu_maxpool5.sv.a_v11_20260924.bak
 *                   （SHA256 35507DDC1ED9D2C733A3B3ADD049F90B5A9F0D8F4
 *                    7E137FD7BAC0E7351313E1C）。
 *                   A 在 100MHz 综合 routed WNS -56.709ns（数据路径
 *                   66.282ns 中 route 占 70.6%，84 级逻辑）；C 变体
 *                   OOC routed WNS 演进：V2.1(P=2 修正) +0.414 →
 *                   P=3 +0.233（关键路径移至插入锥）→ V2.2 插入路径
 *                   整改 +1.261 PASS（LUT 9736→3492，-64%；证据
 *                   f7tmg_run01/ooc_a|b|c2|c3|c4 + gate_mp5u_c +
 *                   gate_mp5eng）。
 *
 *   语义合同与 A 逐位相同（手册 2.2 / P2c 门金标准三方互证）：
 *     out[c,y,x] = max(有效位置 in[c, y-2..y+2, x-2..x+2])，pad=-128
 *     以"插入时掩码、种子 0x80"实现；CHW 线性同形流；每输入步 1 字节
 *     吞吐、pad 步自走；发射于 (pr>=2 && pc>=2) 的步、每通道恰 H*W。
 *
 *   结构（对 A 的替换，控制面不动、数据面重构）：
 *     - 4 条 64x8 行缓冲 lb_r[0..3]（LUTRAM 意图：异步读/同步写，
 *       read-during-write 返旧值）。网格行 g 的填充缓冲 = lb[rot_r]，
 *       行 g-k 在 lb[(rot-k)&3]；rot_r 自由跑 mod 4、每次行推进(含
 *       通道卷绕)+1、永不清零/复位。
 *     - 承重技巧（同址读写）：输入步 (g,pc) 上 lb[rot][pc] 同时读
 *       (行 g-4、窗行 r=0 的插入源) 与写 (行 g)——异步读返旧行 g-4
 *       值，恰为所需；行 g-4 的该列此后永不再读（此后只活在窗寄存
 *       器副本里），无损。
 *     - 固定窗 win_r[5][5]：win_r[r][t] = 已完成步的网格字节
 *       (pr-4+r, pc-4+t)。每步执行沿整体左移（FF→FF 直连无 mux），
 *       win_r[r][4] <= ins_val[r]（插入时掩码：该抽头网格位置自身
 *       的有效性 0<=g-4+r<H && pc<W，否则 0x80——与消费时掩码位等，
 *       因插入步即该抽头的网格位置）。r=4 恒由 in_data_i 喂（本拍
 *       接收字节=移位后 idx0 语义，A 的 V1.1 教训结构化保持）。
 *     - 新行第 0 步沿 win_r[r][0..3] <= 0x80（承重：旧关联尾随按左 pad
 *       节拍排空；清窗不挂行推进沿——发射树读沿后窗，行推进沿清窗会
 *       抹掉本步末列发射所需内容；通道卷绕=(0,0) 亦属新行第 0 步同律
 *       覆盖——故 win/lb/rot 无需任何清除，含跨通道）。
 *     - 平衡 max 树（25 个已掩码寄存器的纯 max，树旁零运行时算术）：
 *         S1（T+1 拍组合）：25 -> 13 (p1_w) -> 7 (m_r[0..6] 寄存)
 *         S2（T+2 拍组合）：7 -> 4 (q_w -> q_r[0..3] 寄存)
 *         S3（T+3 拍组合）：4 -> 2 (s_w) -> 1 -> out 寄存
 *       P=3（原 P=2；2026-09-24 ooc_c2 修正版 RTL routed WNS +0.414
 *       < 0.5ns 裕量线——S2 三级 smax 串行 9.5ns——按 v2 规格计划条款
 *       启用 q_r 插级后备）。
 *       v1/v2/v3_r 与树逐级流水，out_valid_o <= v3_r。
 *     - busy_o = (state!=IDLE)||v1_r||v2_r||v3_r||out_valid_o：末发射拍
 *       后 1 拍落（引擎完成三联 y_cnt==CHW && f_lvl==0 && !busy 保持
 *       健全；A 的 busy 早落教训由此关闭）。
 *     - 时延：发射步 T -> out_valid_o 于 T+1+P = T+4（A 为 T+1）；TB
 *       按累计流位置比对，兼容。X 安全：通道第 1 步起 win_r 25 格每步
 *       全写，首发射 (2,2) 前无 X 可达。
 *
 *   FIFO 合同（引擎侧，FD=256、thr=2W+8 不变）：最坏 pad 突发 B=2W+2
 *   字节；零溢出条件 thr >= B+P；W=64/P=3 时余量 3 字节（P<=6 全覆
 *   盖）——thr 无需改，见 11 号日志公式推导（ppu_mp5_engine.v 头注
 *   同文）。
 *
 *   MAXW 域：W<=64 不变（>64 由引擎闸永关呈现，看门狗可见）；读地址
 *   直取 pc[5:0]（V2.2 去 (pc<W) 门控：pc 可到 W+1=65，mod 64 回绕读
 *   垃圾值被列掩码 0x80 替换弃用；写仅输入步 pc<W<=64 恒在域内）。
 *   深度 64（非 66）：仅 0..W-1 承载真数据，66 无 LUTRAM 原语
 *   对应（对 v2 规格"深度 MAXW+2"的已标注偏差）。
 * Dependencies    : None (pure fabric).
 * Revision History:
 *   - V1.0/V1.1 (2026-09-19) by LSL : A 变体全局延迟线版（历史正身，
 *     现 yolo_ppu_maxpool5.sv.a_v11_20260924.bak；V1.1 修 r=4 窗行
 *     in_data 语义错位）。
 *   - V2.0-C (2026-09-23) by LSL : 流式行缓冲结构（Stage3-v2 规格
 *     §二 C 案；A/B/C 以 OOC routed timing 择优）。
 *   - V2.1-C (2026-09-24) by LSL : rot_r 上电 INIT + 清窗挂新行第 0 步
 *     （mp5u_c 首跑两错修复）；P=3 启用（ooc_c2 WNS+0.414<0.5ns 线，
 *     q_r 插级）。
 *   - V2.2-C (2026-09-24) by LSL : 插入路径整改（ooc_c3 最差
 *     cw_r→win_r[r][4]/D 9.7ns/8 级）：读地址去门控 + 行/列有效掩码
 *     寄存化随步推进（比较算术移出读 mux 路径）。
 *   - V2.3 (2026-09-24) by LSL : 择优落位——C 变体 V2.2 内容以正身
 *     模块名 yolo_ppu_maxpool5 替换 A（OOC 三比 ooc_a -59.863 /
 *     ooc_b -3.568 / ooc_c4(V2.2) +1.261；核单测 golden13_w64
 *     26762 检查 0 错；引擎门 mp5eng 2680 检查 0 错；A 备份并存）。
 ************************************************************************/

module yolo_ppu_maxpool5 #(
    parameter integer MAXW = 64          //行缓冲容量上界（W 域）
) (
    input  wire        clk_i,      //运算时钟
    input  wire        rst_i,      //同步复位，高有效（回 ST_IDLE，清脉冲）
    // ---- task start（ST_IDLE 时采样）----
    input  wire        start_i,    //启动脉冲
    input  wire [15:0] c_i,        //通道数 C
    input  wire [15:0] h_i,        //输入/输出高 H
    input  wire [15:0] w_i,        //输入/输出宽 W
    // ---- input byte stream（CHW 线性序）----
    output wire        in_ready_o, //本拍可收输入字节（输入步）
    input  wire        in_valid_i,
    input  wire [7:0]  in_data_i,
    // ---- output byte stream（CHW 线性序，同形）----
    output reg         out_valid_o,
    output reg  [7:0]  out_data_o,
    output reg         out_last_o, //末字节同拍脉冲
    output wire        busy_o
);

    localparam [1:0]  ST_IDLE = 2'd0;
    localparam [1:0]  ST_RUN  = 2'd1;

    // ---- 控制面（与 A 同名同步，引擎/TB 亲切）----
    reg [1:0]  state_r;
    reg [15:0] cw_r, ch_r;           //锁存 W/H
    reg [15:0] ctot_r;               //锁存 C
    reg [15:0] pr_r, pc_r;           //处理网格游标（行 [0,H+2)，列 [0,W+2)）
    reg [15:0] c_r;                  //通道计数
    // 上电初值 0（Xilinx INIT 正典）：不复位（复位会破坏缓冲↔行映射），
    // 但 sim/上电 X 索引会把 X 灌进窗（2026-09-24 mp5u_c 首跑教训）。
    reg [1:0] rot_r = 2'd0;           //行缓冲轮转（自由跑，永不清零）
    reg [7:0] m_r [0:6];            //S1->S2 边界：7 幸存者
    reg [7:0] q_r [0:3];            //S2->S3 边界：4 幸存者（P=3 插入）
    reg        v1_r, l1_r;           //valid/last 流水第 1 拍
    reg        v2_r, l2_r;           //valid/last 流水第 2 拍
    reg        v3_r, l3_r;           //valid/last 流水第 3 拍
    reg        colv_q_r;             //列有效（当前游标步 pc<W）寄存版
    reg [4:0]  rv_q_r;               //行有效位 r=0..4（当前游标步）寄存版
                                     //（V2.2 插入路径整改：掩码随步推进，
                                     //  比较算术移出 lb 读路径；不变量：
                                     //  rv_q_r[r]&&colv_q_r ≡ 组合版行/列
                                     //  有效——仅 step_w 沿更新+start 装载，
                                     //  冻结步保值）

    wire input_step_w = (pr_r < ch_r) && (pc_r < cw_r);
    wire step_w       = input_step_w ? in_valid_i : 1'b1;
    wire rowadv_w     = step_w && (pc_r == cw_r + 16'd1);
    // 清窗挂"新行第 0 步"而非行推进沿：发射树读沿后窗，行推进沿清窗
    // 会把本步末列发射的窗内容抹成 0x80（2026-09-24 mp5u_c 首跑
    // beat9=80 教训）；(pr,0) 步无发射，清窗安全。含 (0,0)=通道卷绕。
    wire rowstart_w   = step_w && (pc_r == 16'd0);
    wire emit_w       = step_w && (pr_r >= 16'd2) && (pc_r >= 16'd2);
    wire last_step_w  = (c_r == ctot_r - 16'd1)
                      && (pr_r == ch_r + 16'd1)
                      && (pc_r == cw_r + 16'd1);

    assign in_ready_o = (state_r == ST_RUN) && input_step_w;
    assign busy_o     = (state_r != ST_IDLE) || v1_r || v2_r || v3_r
                      || out_valid_o;

    // ---- 行缓冲：4 x MAXW x 8，异步读/同步写（LUTRAM 意图）----
    // 网格行 g-k 在 lb_r[(rot-k)&3]；窗行 r <-> 网格行 pr-4+r <->
    // 缓冲 (rot+r)&3（r=0 即填充缓冲自身：同址读写承重技巧）。
    reg [7:0] lb_r [0:3][0:MAXW-1];
    // V2.2：地址不带 (pc<W) 门控 mux——pc 到 W+1≤65 时 [5:0] mod 64 回绕，
    // pad 步读到的垃圾值被列掩码弃用（0x80 替换）；换得读路径前置
    // 比较链消失（ooc_c3 最差路径 cw_r→…→win_r[r][4]/D 的前半段）。
    wire [5:0] lb_ra_w = pc_r[5:0];

    // ---- 插入值：行有效 && 列有效 ? 源 : 0x80（掩码折入插入）----
    // 行 r 的网格行 = pr-4+r：有效 <=> (pr >= 4-r) && (pr-4+r < H)；
    // r=4 恒本步行（in_data_i），其行有效&&列有效恰 = input_step_w。
    // V2.2：掩码用寄存版（rv_q_r/colv_q_r，随步推进）——16 位比较算术
    // （原 rowval/colval 两组 CARRY4）移出 64:1 读 mux 之后的路径，
    // 比较独占一拍（pr_r/ch_r→比较→rv_q_r/D）裕量充足。
    wire [7:0] ins_val_w [0:4];
    genvar gr;
    generate
        for (gr = 0; gr < 4; gr = gr + 1) begin : g_ins
            assign ins_val_w[gr] = (rv_q_r[gr] && colv_q_r)
                                 ? lb_r[(rot_r + gr) & 3][lb_ra_w]
                                 : 8'h80;
        end
    endgenerate
    assign ins_val_w[4] = (rv_q_r[4] && colv_q_r) ? in_data_i : 8'h80;

    // ---- 下一步游标与下一步掩码（掩码预计算；仅 step_w 沿采样入寄存）----
    wire        padcol_nx_w  = (pc_r == cw_r + 16'd1);
    wire [15:0] pc_nx_w      = padcol_nx_w ? 16'd0 : (pc_r + 16'd1);
    wire        lastrow_nx_w = (pr_r == ch_r + 16'd1);
    wire [15:0] pr_nx_w      = padcol_nx_w
                             ? (lastrow_nx_w ? 16'd0 : pr_r + 16'd1)
                             : pr_r;
    wire        colv_nx_w    = (pc_nx_w < cw_r);
    wire [4:0]  rv_nx_w;
    genvar gm;
    generate
        for (gm = 0; gm < 4; gm = gm + 1) begin : g_rv
            assign rv_nx_w[gm] = (pr_nx_w >= 16'd4 - gm)
                              && (pr_nx_w < ch_r + 16'd4 - gm);
        end
    endgenerate
    assign rv_nx_w[4] = (pr_nx_w < ch_r);

    // ---- 固定 5x5 窗：win_r[r][t] = 已完成步网格 (pr-4+r, pc-4+t) ----
    reg [7:0] win_r [0:4][0:4];

    // ---- 平衡 max 树：S1 = 25->13->7（m_r 寄存），S2 = 7->4（q_r 寄存），
    //      S3 = 4->2->1 ----
    function [7:0] smax(input [7:0] a, input [7:0] b);
        smax = ($signed(a) > $signed(b)) ? a : b;
    endfunction
    wire [7:0] p1_w [0:12];
    wire [7:0] m_w  [0:6];
    wire [7:0] q_w  [0:3];
    wire [7:0] s_w  [0:1];
    // S1 第一级：25 个已掩码窗寄存器按平坦序 k=r*5+t 相邻配对
    //（12 对 + 旁路末元 k=24 -> 13 幸存者）
    genvar gt;
    generate
        for (gt = 0; gt < 12; gt = gt + 1) begin : g_p1
            assign p1_w[gt] = smax(win_r[(2*gt)/5][(2*gt)%5],
                                   win_r[(2*gt+1)/5][(2*gt+1)%5]);
        end
    endgenerate
    assign p1_w[12] = win_r[4][4];                       //25 奇数：旁路末元
    generate
        for (gt = 0; gt < 6; gt = gt + 1) begin : g_m
            assign m_w[gt] = smax(p1_w[2*gt], p1_w[2*gt+1]);
        end
    endgenerate
    assign m_w[6] = p1_w[12];                            //13 奇数：旁路
    // S2（T+2 拍）：7 -> 4，q_r 寄存。P=3 启用记录：ooc_c2 实测
    // m_r->out 三级 smax 串行 9.5ns / WNS+0.414 < 0.5ns 裕量线
    //（2026-09-24，按 v2 规格计划"routed WNS<0.5ns 时启用"条款）。
    assign q_w[0] = smax(m_r[0], m_r[1]);
    assign q_w[1] = smax(m_r[2], m_r[3]);
    assign q_w[2] = smax(m_r[4], m_r[5]);
    assign q_w[3] = m_r[6];                              //7 奇数：旁路
    // S3（T+3 拍组合）：4 -> 2 -> 1
    assign s_w[0] = smax(q_r[0], q_r[1]);
    assign s_w[1] = smax(q_r[2], q_r[3]);
    wire [7:0] fin_w = smax(s_w[0], s_w[1]);

    integer r, t, i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_r     <= ST_IDLE;
            out_valid_o <= 1'b0;
            out_last_o  <= 1'b0;
            v1_r        <= 1'b0;
            v2_r        <= 1'b0;
            v3_r        <= 1'b0;
            // win_r/lb_r/rot_r 刻意不清：插入掩码+行推进清除保证陈旧
            // 数据（含跨通道/上电 X）永不被当有效消费（见文件头）。
        end else begin
            //默认单拍脉冲（valid 管线以 v1/v2/v3 传递）
            v1_r <= 1'b0;

            case (state_r)
                ST_IDLE: begin
                    if (start_i) begin
                        cw_r   <= w_i;
                        ch_r   <= h_i;
                        ctot_r <= c_i;
                        pr_r   <= 16'd0;
                        pc_r   <= 16'd0;
                        c_r    <= 16'd0;
                        //掩码寄存装载（游标 (0,0)）：列 (0<W)、行仅 r=4
                        colv_q_r <= (w_i != 16'd0);
                        rv_q_r   <= {(h_i != 16'd0), 4'b0000};
                        state_r <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (step_w) begin
                        //行缓冲写：仅输入步、地址 pc(<W 在域内)
                        if (input_step_w)
                            lb_r[rot_r][lb_ra_w] <= in_data_i;

                        //窗整体左移 + 掩码插入（FF->FF 直连；行推进
                        //清除后置——非阻塞末次赋值胜出）
                        for (r = 0; r < 5; r = r + 1) begin
                            for (t = 0; t < 4; t = t + 1)
                                win_r[r][t] <= win_r[r][t+1];
                            win_r[r][4] <= ins_val_w[r];
                            if (rowstart_w)
                                for (t = 0; t < 4; t = t + 1)
                                    win_r[r][t] <= 8'h80;
                        end
                        if (rowadv_w)
                            rot_r <= rot_r + 2'd1;

                        //掩码推进到下一步游标（仅执行步更新；冻结步
                        //保值——与组合版等价的不变量承重）
                        colv_q_r <= colv_nx_w;
                        rv_q_r   <= rv_nx_w;

                        //发射进流水（S1 组合于 T+1 拍吃 win_r 快照）
                        v1_r <= emit_w;
                        l1_r <= last_step_w;

                        //游标推进：与 A 逐字相同
                        if (pc_r == cw_r + 16'd1) begin
                            pc_r <= 16'd0;
                            if (pr_r == ch_r + 16'd1) begin
                                pr_r <= 16'd0;
                                c_r  <= c_r + 16'd1;
                                if (last_step_w)
                                    state_r <= ST_IDLE;
                            end else begin
                                pr_r <= pr_r + 16'd1;
                            end
                        end else begin
                            pc_r <= pc_r + 16'd1;
                        end
                    end
                end

                default: state_r <= ST_IDLE;
            endcase

            // ---- S1/S2 寄存（自由跑：win_r 不变的步上重算同值，无害）----
            for (i = 0; i < 6; i = i + 1)
                m_r[i] <= m_w[i];
            m_r[6] <= m_w[6];
            for (i = 0; i < 4; i = i + 1)
                q_r[i] <= q_w[i];
            v2_r   <= v1_r;
            l2_r   <= l1_r;
            v3_r   <= v2_r;
            l3_r   <= l2_r;

            // ---- S3 寄存：树顶 + valid/last ----
            out_data_o  <= fin_w;
            out_valid_o <= v3_r;
            out_last_o  <= v3_r && l3_r;
        end
    end

endmodule
