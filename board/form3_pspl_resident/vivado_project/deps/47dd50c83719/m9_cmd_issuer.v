/************************************************************************
 * File Name       : m9_cmd_issuer.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_cmd_issuer
 * Description     :
 *   Per-block command FSM -- the PS replacement (02_m9_issuer_spec.md
 *   section 2): a cycle-level replay of pl_m3.load_lut + arm_and_run,
 *   the V2.4 board-green serial canon.
 *
 *     PRO  load_lut : 256x LUTD (i<<8)|lut[i], then CTRL=0x4 (err_clr)
 *     PREP block entry: strip ROM read, scatter arm (slot law)
 *     Q1   8 rows   : P_BIAS/P_M/P_SH (pctl ROM rc*8+r) + PCTL 0x100|r
 *     Q2   ROWVAL=0xFF (dead-row law: W pre-zeroed, gather truncates)
 *     G1   NMASK=strip.n_mask
 *     G2   LDGRP=seg0.ldgrp
 *     L1   start feeders -> wait stream done -> read LDLEN, closure
 *          check ld_w_len==ld_x_len==k_len (the _mm2s_seg read)
 *     G3   GEOM=k_len, JOBCFG=jobcfg, CTRL=1 (single chain: fire)
 *     W    poll STATUS until tile_done & !pend & !busy (job_acc of the
 *          first=1 job clears tile_done_st at issue, so a set bit here
 *          is THIS block's pulse); YSTAT gate (0x20000, ycnt==8*vc);
 *          BRGSTAT gate ([1] ld_done_st, [2:0]==0); wait scatter close
 *
 *   Block walk is fully incremental (rc wraps at RC -> nt++, s wraps
 *   at NS -> oy++) -- zero division.  M9.1 scope: single-segment chain
 *   only (cfg_nseg must be 1; the K1152/K2304 queue law is M9.4).
 *
 *   M9.3 overlap mode (cfg_overlap=1, load||compute + store||compute):
 *     per block b (parity p = b[0], groups ping-pong g0/g1):
 *       head    LDGRP={p,p} (early write), launch stream L(b) into
 *               group p right away -- it overlaps compute(b-1) reading
 *               group ~p (bank ld_ok flow control is group-safe)
 *       ride    polls for block b-1 (STATUS/YSTAT/BRGSTAT + scatter
 *               close) INSIDE the stream window; then arm scatter(b)
 *               and run Q1(b)+ROWVAL+NMASK -- array is idle (the poll
 *               gate core_busy==0 structurally enforces PCTL idle-only)
 *       close   wait stream L(b) end -> LDLEN -> GEOM/JOBCFG/CTRL=1
 *     CTRL(b) fires at stream(b) close; compute(b) then overlaps the
 *     NEXT block's stream.  Write order per block = [LDGRP, Q1 x32,
 *     ROWVAL, NMASK, GEOM, JOBCFG, CTRL] -- same 38 writes, LDGRP
 *     moved to block head; JOBCFG=cfg_s0_jc|(p?0x18:0).  progress_blk
 *     increments at scatter-close verify (polls), not at CTRL.  Block
 *     0 rides the same shape (no polls); the last block takes a final
 *     poll pass after CTRL so done implies the last arena slot closed.
 *
 *   ROM ports are registered 1-cycle reads -- the future BRAM row
 *   cache face of the plan blob (M9.1 drives them from $readmemh).
 *
 *   M9.4 conv-table walk (cfg_nconv>1, SEQ only): the issuer walks a
 *   per-conv ROM table (cv_iss/cv_geo/cv_wlay at shared cv_addr),
 *   reloading the LUT and the whole geometry/W-layout shadow set at
 *   every conv boundary (pl_m3 per-conv load_lut canon, unconditional
 *   -- switch window attributed in the ledger, not deduped).  Per-conv
 *   segments follow the frozen multi-seg canon (arm_and_run):
 *
 *     seg0 : LDGRP(g0) -> stream0 -> LDLEN -> GEOM/JOBCFG(j1, UNFIRED)
 *     i>=1 : LDGRP(gi) -> stream_i -> LDLEN -> [i==1: CTRL start1 ->
 *            pend] -> GEOM/JOBCFG(j_{i+1}) -> CTRL queue ->
 *            [i<nseg-1: pend] -> completion polls
 *
 *   (engine latches GEOM/JOBCFG into the job at CTRL commit -- a chain
 *   seg0 must NOT fire before seg1's start1; CTRL count == nseg/block).
 *   The x window k-decomposition is SEEDED per segment (k-chain taps
 *   are not channel-aligned for 3x3: 1024 = 113*9+7).
 *
 *   cfg_nconv<=1 keeps the V1.1 legacy single-conv path byte-stable
 *   (modes 0/1 regression law); walk mode rejects nseg not in 1..3
 *   (err=6).
 *
 *   M9 walk+overlap (V2.1, cfg_nconv>1 AND cfg_overlap, per-conv nseg
 *   == 1 only): the V1.1 block ping-pong law lifted across conv
 *   boundaries.  Per conv c (including conv 0) the LUT reload is
 *   DEFERRED into the first block's stream window (lut_pend/lut_ret_q1
 *   handshake); at a boundary the conv c+1 prologue (table latch ->
 *   PREP/ARM -> credit -> LDGRP={0,0} -> stream launch) runs while
 *   conv c's last block still computes, the pending polls of conv c's
 *   last block ride the new stream window (polls_pend), and after the
 *   polls close (array idle) the deferred LUT reload + Q1 nest inside
 *   the same stream window ahead of CTRL.  Golden/order law: same CSR
 *   write count as SEQ walk, LDGRP moved to the block head.  walk+ovl
 *   with a table nseg!=1 rejects with err=9 (multi-seg chain group
 *   reuse is not composed with overlap yet); an odd-NB conv boundary
 *   whose stream target group is still read-selected retries the
 *   credit poll until the reader drains (zero-overlap fallback, no
 *   legacy change: legacy ovl keeps the hard err=8).
 *
 *   AXI-Lite master: one outstanding op; aw+w presented together,
 *   each held until its own handshake (req-hold law); bready/rready
 *   held from op start until response.  err!=0 halts sticky (STOP
 *   hygiene: no unexplained compute holes); progress_blk is the ABI
 *   progress RO face of M9.5 (cumulative across convs in walk mode).
 *
 *   ROM line layouts (PC dump == RTL read, single source):
 *     pctl  [95:0] = {24'd0, sh8[71:64], m[63:32], bias[31:0]}
 *     strip [20:0] = {vc[20:16], n_mask[15:0]}
 *     lut   [7:0]  = LUT entry
 *     cv_iss [255:0] = {obuf[87:56], stride[55:24], nseg[23:22],
 *                       ns[21:18], rc[17:12], nb[11:0],
 *                       3 x seg[55:0] @88+56i:
 *                         {kw0[54:52], kh0[51:49], ic0[48:33],
 *                          woff[32:21], g[20:19], jc[18:11], k[10:0]}}
 *     cv_geo [105:0] = {xbase[105:74], law_fetch[73], first[72],
 *                       pw[71:68], ph[67:64], sw[63:60], sh[59:56],
 *                       kw[55:52], kh[51:48], w[47:32], h[31:16],
 *                       ic[15:0]}
 *     cv_wlay[167:0] = {ch_stride[167:136], oc[135:128],
 *                       oc_stride[127:96],
 *                       rc_stride[95:64], slab[63:32], wbase[31:0]}
 *                       (2a: m9_bm_wlay widened 136->168; ch_stride=0 is
 *                       the legacy h*w fallback -- SPEC v2 §6)
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 *   - V1.1 (2026-10-09) : M9.3 overlap mode (cfg_overlap): stream-first
 *     block head + polls/Q1 riding the stream window; LDGRP head write
 *     with ping-pong parity; scatter arm post-polls; fin pass closes
 *     the last block.  SEQ path (cfg_overlap=0) byte-identical to V1.0.
 *   - V2.0 (2026-10-09) : M9.4 conv-table walk (cfg_nconv>1): per-conv
 *     LUT reload + shadow switch + multi-segment chain (K1152 dual /
 *     K2304 triple group reuse) + x k-seed outputs.  Legacy nconv==1
 *     path byte-stable (modes 0/1 regression law).
 *   - V2.1 (2026-10-09) : M9 walk+overlap (cfg_nconv>1 AND cfg_overlap,
 *     per-conv nseg==1): deferred per-conv LUT reload nested in the
 *     first block's stream window + conv-boundary group handoff (ping-
 *     pong parity restarts at 0 each conv; boundary stream overlaps the
 *     previous conv's last compute; credit poll retries on an odd-NB
 *     boundary).  err=9 re-scoped to "walk+ovl nseg!=1".  SEQ walk
 *     (cfg_overlap=0) and legacy ovl (cfg_nconv<=1) byte-stable.
 *   - V2.2 (2026-10-10) : r6 ROM-widening batch -- plan ROM flat bases
 *     widened for NCONV_MAX=16: pbase/pctl_addr 10b->11b (2048 = 16 x
 *     128 rows), sbase/strip_addr 7b->8b (256 = 16 x 16), lbase/
 *     lut_addr 11b->12b (4096 = 16 x 256).  Address-plane only; the
 *     data plane, cv tables (16 deep) and cfg_nconv (5b) now encode 16.
 *     Legacy/walk writes byte-stable for <=8 convs (new MSBs stay 0 --
 *     r6 regression ladder law).  Replaces the r5-era structural cap
 *     (12-conv merged single frame now gateable; see r6 run01).
 *   - V2.2-r10 (2026-10-18) : ROM rebake (r10 run01, 25 live convs) --
 *     pctl 12b / strip 9b / lut 13b / cv_addr+conv_idx 5b (32-deep cv
 *     faces), conv_cnt 4b->5b, pbase/sbase/lbase + multiplier constants
 *     widened to match (r10 run README section 7).  The old 5-conv
 *     address map is value-identical (widths only; slot law pbase=
 *     idx*128 / sbase=idx*16 / lbase=idx*256 unchanged).
 *   - V2.3 (2026-10-14) : M10.1-v2 2a -- cv_wlay port widened 135:0 ->
 *     167:0 (m9_bm_wlay 136->168); new geo_ch_stride shadow output
 *     (cv_wlay[167:136], 0 = legacy h*w fallback in m9_x_window_v3).
 *     Walk table read unchanged otherwise; legacy path shadow = 0.
 *   - V3.0 (2026-10-16) : M10.2 m8 ABI v2.3 (DESIGN_m8_v23.md §3) --
 *     PPP trigger-table walk + three-line PL handshake.
 *       * doorbell-edge sanity (combinational, both paths): PPP table
 *         ascending/opcode/DESC-slot scan -> E_PPP_OPCODE 0x20 /
 *         E_PPP_ORDER 0x21 / E_PPP_DESC 0x22; LAYOUT one-hot +
 *         nconv>10-with-layouts -> E_LAYOUT_MISMATCH 0x24 /
 *         E_LAYOUT_RANGE 0x23.  sanity 全过才放行帧.
 *       * walk conv arrivals route through S_PPPG: while the table word
 *         at ppp_ptr matches the arriving conv index, fire
 *         ppu_start{frame_gen, ppp_ptr, desc_idx} and hold the consumer
 *         conv until ppu_done (strict serial per node; abort -> halt
 *         with ppu_done.err -- E_GEN_MISMATCH 0x25 lands here).  Empty
 *         table (first word EMPTY) falls straight through: v1 path
 *         structurally identical (T7 zero-leak basis).  Legacy
 *         (cfg_nconv<=1) never routes through the PPP gate (walk-domain
 *         feature, DESIGN §3.3).
 *       * ppp_ptr resets to 0 at the doorbell; monotone through the
 *         walk (table is conv_node-ascending by sanity).
 *   - V3.1-M11a (2026-10-18) : M11a graph-level page scheduling (SPEC_m11a
 *     v1.0 §2, ABI v2.4).  Walk frames may split into 1..8 pages
 *     (PAGE_CTRL npages count-1 encoding, 0 = single page = legacy):
 *       * page FSM S_PGE0/1/2 at the page-local conv-boundary end:
 *         S_PGE0 bumps page_r + watchdog refresh + trace page anchor;
 *         S_PGE1 pulses pg_adv {pg_base=gconv+1, pg_nconv=new-page
 *         nconv} to m9_hbuf_ctrl (sticky slot retention rearm);
 *         S_PGE2 resets conv_cnt/ppp_ptr, latches the new page's
 *         per-page nconv (descriptor [3:0]+1), bumps gconv.
 *       * gconv (6b) = running GLOBAL conv index; cv_addr/conv_idx now
 *         6b (63-conv D4 face).  Legacy: gconv == conv_cnt step for
 *         step (both start 0, increment at the same boundary) -> the
 *         6b faces are value-identical superset, zero drift.
 *       * Paged plan addressing is SLOT-based (D4 errata b46f81f2: 69
 *         slots, 6 convs doubled rc=32): pbase/sbase/lbase come from
 *         the cv_slot ROM face x 128/16/256 when paged_w; legacy keeps
 *         conv_cnt x 128/16/256 (r10 slot==conv law, zero drift).
 *         Address planes widen pctl 12->14b, strip 9->11b, lut 13->15b
 *         (truncate at the frozen wrappers, r10 precedent).
 *       * The PPP sanity scan reads the WINDOWED cfg_ppp_tab face (CSR
 *         v2.4 selects the active page's 8 words); page 0 base-0 window
 *         == legacy flat table -> zero drift.  Per-page re-validation
 *         samples the registered ppp_err_r at S_PGE3 -- the knife-B
 *         2-stage pipeline first holds the NEW window's scan during the
 *         3rd cycle after the S_PGE0 page bump (S_PGE2 is the settle
 *         cycle; sampling there read the OLD window -- G3 case-1 law).
 *       * Watchdog tmo max = 100M cycles paged / 50M legacy; refreshed
 *         at S_ADV / S_PGE0 / PPP-done (S_PPPW).
 *       * E_PGTABLE 0x26: paged frame (npages>1) without PAGE_CTRL
 *         auto_adv refused at the doorbell.
 *       * Repack hook (SPEC §4): rp_start_o pulses with the S_PPPF PPP
 *         fire (SPPF anchor), S_PPPW additionally waits rp_done_i when
 *         paged (legacy / float = no wait, zero drift).  The glue top
 *         FF covers the npages=1 degenerate path.
 *       * Frozen-wrapper floats on the new inputs are z-guarded to
 *         legacy values (npages=1, auto_adv=0, rp_done=1, cv_slot=0);
 *         r12 build wires the real faces.
 *   - V3.2-D1D2 (2026-10-26) : repack 配置面闭合 (D1) + issuer 判决锁存
 *                         (D2) 同修 (审计 R154 快裁 + R155 重裁; SPEC v3
 *                         新章《M11 repack 配置面闭合与判决锁存 (D1/D2
 *                         同修)》(2026-10-26 立项, 数字待 run04 回填)):
 *       * D2 判决锁存 (设计件 §3): ppp_vld/ppp_ab/ppp_err[7:0] 寄存器组,
 *         主 always 内无条件捕获 1-cycle ppu_done (单拍判决必达, 不靠
 *         FSM case 门); 清除点 = S_PPPF 点火拍 (ppu_start 同事件) +
 *         门铃帧首 (ppp_ptr 复位同事件); S_PPPW 判据 if(ppp_vld) 取代
 *         if(ppu_done), 内分支序保持原序 (abort->halt; paged 空转; 推进),
 *         abort 时 err<=ppp_err (锁存值, 非脉冲原线). 判决寄存器凌驾
 *         脉冲电平: stuck-high pdone 不再影响判据.
 *       * 看门狗边沿刷新修正案 (设计件 §4): if(ppu_done && !ppp_vld)
 *         timeout<=0 取代电平刷新 -- 仅捕获拍刷新一次, stuck-high 面
 *         不再饿死看门狗, "判决已到而 repack 挂死"类恢复 err=7 覆盖.
 *       * D1 rp_err ABI (R155 中案): 新增内部口 rp_err_i/rp_err_code_i
 *         (axi_top 接线点重映射码段 0x0E-0x12, 本模块零映射逻辑);
 *         S_PPPW fail-fast 主面: paged_w && rp_err_lvl ->
 *         err<=rp_err_code_m; st<=S_HALT (rp_err 时 rp_done 永 0, 不
 *         fail-fast 则新型挂死). ABI/CAP0 untouched (identity law).
 *   - V3.3-R160 (2026-10-26) : candidate-only SPPF closure.  Unique
 *         page2/ppp0/desc10/gconv26 anchor, SEQ rejection, local cv1
 *         epoch, ARM/WARM/START/WAIT microsequence, C6 armed shadow,
 *         and RP first-error-wins.  No CSR/ABI change.
 *   - V3.5-StageB (2026-10-28) : Candidate-only checked-bind execution fence,
 *         manual single-page close, full global producer keys, ARN0/1/2,
 *         repack-commit state, and 12/16-bit fail-closed counters.
 *   - V3.6-EngineClosure (2026-10-28) by LSL : Dense face geometry,
 *         dual-entry ROM switching, retained SPPF owner/shadow, and
 *         accepted-mode/verified-close integration.
 *   - V3.7-EngineDeepening (2026-10-28) by LSL : Arriving-row ROM/tag
 *         capture, full-row PPP re-gating, and producer-arm phase export.
 *   - V3.8-WidthRepair (2026-10-28) by LSL : Preserve the full six-bit rc
 *         launch value, including the legacy rc=32 path, without truncation.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_cmd_issuer (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv config (sampled while idle; held through run) ----
    input  wire [9:0]  cfg_nb        ,   // block count
    input  wire [5:0]  cfg_rc        ,   // rc blocks per nt
    input  wire [3:0]  cfg_ns        ,   // strips per oy
    input  wire [1:0]  cfg_nseg      ,   // M9.1: must be 1
    input  wire [10:0] cfg_s0_k      ,   // segment 0 k count
    input  wire [7:0]  cfg_s0_jc     ,   // segment 0 jobcfg
    input  wire [1:0]  cfg_s0_g      ,   // segment 0 ldgrp
    input  wire [31:0] cfg_stride    ,   // y_slot_stride (bytes)
    input  wire [31:0] cfg_obuf      ,   // arena out region base
    input  wire [31:0] cfg_ybase     ,   // M9.5c: y-arena runtime base (CSR
                                        // 0x04 PLAN_BASE).  Added to EVERY
                                        // obuf source (cfg_obuf legacy /
                                        // cv_iss[87:56] walk) before the
                                        // slot math -- the baked conv table
                                        // stays conv-RELATIVE and the board
                                        // relocates the whole arena with one
                                        // register write.  0 = legacy
                                        // absolute (all gates to date).
    input  wire        cfg_overlap   ,   // M9.3: load||compute ping-pong
    input  wire [4:0]  cfg_nconv     ,   // M9.4: conv count (<=1 legacy)
    // ---- per-conv geometry config (legacy passthrough / walk source;
    //      driven back out as the feeder cfg face, single source) ----
    input  wire [15:0] cfg_ic        ,
    input  wire [15:0] cfg_h         ,
    input  wire [15:0] cfg_w         ,
    input  wire [3:0]  cfg_kh        ,
    input  wire [3:0]  cfg_kw        ,
    input  wire [3:0]  cfg_sh        ,
    input  wire [3:0]  cfg_sw        ,
    input  wire [3:0]  cfg_ph        ,
    input  wire [3:0]  cfg_pw        ,
    input  wire        cfg_first      ,
    input  wire        cfg_law_fetch  ,
    input  wire [31:0] cfg_xbase      ,
    input  wire [31:0] cfg_wbase     ,
    input  wire [31:0] cfg_slab      ,
    input  wire [31:0] cfg_rc_stride ,
    input  wire [31:0] cfg_oc_stride ,
    input  wire [7:0]  cfg_oc        ,
    // ---- frame control ----
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,   // 1-cycle pulse: all blocks closed
    output reg  [7:0]  err           ,   // nonzero = halted (sticky)
    output reg  [15:0] progress_blk  ,   // reset-only cumulative epoch count
    output reg  [31:0] dbg_dual_transition,
    output reg  [31:0] dbg_last_face_close,
    output wire [31:0] tmo_max_w     ,
    output reg         epoch_invalid ,
    input  wire        axi_epoch_invalid_i,
    input  wire        dense_addr_err_i,
    // ---- ROM read ports (registered, 1-cycle) ----
    // r6 ROM-widening widths (2026-10-10): pctl 11b (16 convs x 128
    // rows), strip 8b (16 x 16), lut 12b (16 x 256) -- NCONV_MAX=16
    // cfg_nconv is 5b so the NCONV_MAX=16 endpoint is representable.  The
    // M9.5 10b/7b/11b law capped the walk at 8 convs (conv>=8 base wrap aliased conv 0-3; r5 r12
    // evidence arena_err=8707 first byte 0x40000 = conv8 obuf).
    // v2.4 (M11a/D4): address planes widened for slot-based paged
    // addressing (69 slots x 128/16/256 rows = 8832/1104/17664; 14b/11b/
    // 15b).  Legacy values occupy the low bits; the frozen wrappers
    // truncate with warnings (r10 width-propagation precedent, G1
    // unaffected).
    output reg  [13:0] pctl_addr     ,
    input  wire [95:0] pctl_data     ,
    output reg  [10:0] strip_addr    ,
    input  wire [20:0] strip_data    ,
    output reg  [14:0] lut_addr      ,
    input  wire [7:0]  lut_data      ,
    // ---- M9.4 conv-table ROM face (registered, 1-cycle) ----
    // v2.4: cv_addr/conv_idx widened 5b -> 6b (63-conv D4 face; truncates
    // at the frozen wrappers, r10 width-propagation precedent)
    output reg  [6:0]  cv_addr       ,
    input  wire [255:0] cv_iss       ,
    input  wire [105:0] cv_geo       ,
    // M10.1-v2 2a: m9_bm_wlay widened 136->168 (ch_stride[167:136])
    input  wire [167:0] cv_wlay      ,
    output reg  [5:0]  conv_idx      ,   // active conv (TB snoop/ledger)
    // ---- AXI4-Lite master -> u_yolo_gemm register face ----
    output reg  [7:0]  m_awaddr      ,
    output reg         m_awvalid     ,
    input  wire        m_awready     ,
    output reg  [31:0] m_wdata       ,
    output reg         m_wvalid      ,
    input  wire        m_wready      ,
    input  wire [1:0]  m_bresp       ,
    input  wire        m_bvalid      ,
    output reg         m_bready      ,
    output reg  [7:0]  m_araddr      ,
    output reg         m_arvalid     ,
    input  wire        m_arready     ,
    input  wire [31:0] m_rdata       ,
    input  wire [1:0]  m_rresp       ,
    input  wire        m_rvalid      ,
    output reg         m_rready      ,
    // ---- feeder/stream control (to m9_w_feeder + m9_x_window) ----
    output reg         ld_start      ,
    output reg  [9:0]  rt_oy         ,
    output reg  [3:0]  rt_s          ,
    output reg  [5:0]  rt_rc         ,
    output reg  [4:0]  rt_vc         ,
    output reg  [10:0] rt_k          ,
    output reg  [31:0] rt_segoff     ,
    output wire        rt_w_reuse    ,
    output wire        rt_w_only     ,
    output wire        rt_noload     ,
    output reg  [15:0] rt_koff_ic    ,   // M9.4: segment k-seed kIC
    output reg  [3:0]  rt_koff_kh    ,   // M9.4: segment k-seed kKH
    output reg  [3:0]  rt_koff_kw    ,   // M9.4: segment k-seed kKW
    input  wire        ld_w_busy     ,
    input  wire        ld_x_busy     ,
    // ---- feeder cfg face (geo/wlay shadow out; single source) ----
    output reg  [15:0] geo_ic        ,
    output reg  [15:0] geo_h         ,
    output reg  [15:0] geo_w         ,
    output reg  [3:0]  geo_kh        ,
    output reg  [3:0]  geo_kw        ,
    output reg  [3:0]  geo_sh        ,
    output reg  [3:0]  geo_sw        ,
    output reg  [3:0]  geo_ph        ,
    output reg  [3:0]  geo_pw        ,
    output reg         geo_first     ,
    output reg         geo_law_fetch ,
    output reg  [31:0] geo_xbase     ,
    // M10.1-v2 2a: channel byte stride shadow (0 = legacy h*w fallback
    // in m9_x_window_v3; nonzero = view-conv explicit stride)
    output reg  [31:0] geo_ch_stride ,
    output reg  [31:0] wl_wbase      ,
    output reg  [31:0] wl_slab       ,
    output reg  [31:0] wl_rc_stride  ,
    output reg  [31:0] wl_oc_stride  ,
    output reg  [7:0]  wl_oc         ,
    // ---- scatter control ----
    output reg         sc_arm        ,
    output reg  [31:0] sc_base       ,
    output reg  [4:0]  sc_vc         ,
    output reg         sc_up2x       ,   // 5b: producer materializes 2x
    output reg         sc_chw        ,
    output reg  [31:0] sc_ch_stride  ,
    output reg  [15:0] selected_write_bytes,
    output wire [31:0] sc_timeout_limit,
    output reg         paged_mode    ,
    output reg         conv_start    ,
    output reg         face_close    ,
    output wire        scatter_verified_close,
    output wire [31:0] dense_face_off,
    output wire [31:0] dense_face_expected_bytes,
    output wire        dense_face_geometry_err,
    input  wire [15:0] cfg_up2x      ,   // 5b: per-conv up2x bitmap (CSR 0xDE)
    input  wire        sc_done       ,
    input  wire        sc_err       ,
    // ---- 2e credit-gated release (SPEC §7) ----
    input  wire        chain_rel     ,   // CSR 0xE0[0], sampled at start
    input  wire        chain_go      ,   // hbuf: consumer conv credits OK
    output reg  [31:0] s2l_cnt       ,   // CSR 0xE4: S||L overlap cycles
    // 2e-fix: producer conv index for the hbuf capture/slot FSM.  conv_idx
    // (cons face) crosses the boundary EARLY in walk+ovl (S_CVRD at the
    // last block's fire), but the producer's tail scatter keeps writing
    // until its sc_done -- the hbuf producer gate must key on the DRAINED
    // conv, which the issuer knows exactly at the verified boundary close.
    output reg  [5:0]  prod_conv     ,
    // Observe-only scatter-context taps. These describe the block armed
    // by sc_arm, not the load-ahead rt_* command of a subsequent block.
    output wire [9:0]  trace_arm_oy  ,
    output wire [3:0]  trace_arm_s   ,
    output wire [5:0]  trace_arm_rc  ,
    output wire [1:0]  trace_arm_groups,
    output wire [1:0]  trace_arm_nseg,
    output wire [15:0] trace_arm_k_ic,
    output wire [3:0]  trace_arm_kh,
    output wire [3:0]  trace_arm_kw,
    output wire [10:0] trace_arm_k_len,
    output wire [3:0]  trace_arm_conv,
    output wire [3:0]  trace_arm_geom_kh,
    output wire [3:0]  trace_arm_geom_kw,
    // ---- v2.3 (M10.2 m8): PPP trigger table + three-line handshake ----
    input  wire [255:0] cfg_ppp_tab  ,   // CSR flat 8x32b trigger table
    input  wire [47:0]  cfg_layout_id,   // v2.4: 16 page-local conv x 3b
                                       // layout vector (48b face; legacy
                                       // branch reads [29:0] only -- the
                                       // frozen 30b wrapper zero-extends,
                                       // zero drift)
    input  wire [7:0]   frame_gen    ,   // CSR doorbell-latched generation
    input  wire [6:0]   ppu_desc_count,  // PPU island loaded-DESC count
                                         //   (E_PPP_DESC sanity凭据)
    output reg          ppu_start    ,   // 1-cycle pulse -> walker PL entry
    output reg  [17:0]  ppu_start_payload, // {frame_gen[7:0], seg_idx[2:0],
                                         //   desc_idx[6:0]} (DESIGN §3.1)
    input  wire         ppu_done     ,   // walker arbiter verdict pulse
    input  wire         ppu_done_abort,  // 1 = token/engine failure
    input  wire [7:0]   ppu_done_err ,   // abort err code (with pulse)
    input  wire         ppu_write_fence_i, // CHW AXI write/B fully drained
    // ---- v2.4 (M11a): page scheduling (SPEC_m11a §2) ----
    input  wire [2:0]   cfg_npages   ,   // PAGE_CTRL npages, count-1
                                        //   encoding (0 = 1 page = legacy)
    input  wire         cfg_pgauto   ,   // PAGE_CTRL auto_adv (paged frame
                                        //   legality, E_PGTABLE gate)
    input  wire [2:0]   cfg_schedule_page,
    input  wire [5:0]   cfg_gconv_base,
    input  wire [3:0]   cfg_nedge    ,
    input  wire         cfg_hbuf_restart,
    input  wire         bind_done_i  ,
    input  wire         bind_err_i   ,
    input  wire         pg_win_rdy_i ,
    output reg          bind_ready   ,
    output reg          execution_enable,
    output reg          hbuf_start   ,
    output wire [4:0]   hbuf_nconv   ,
    output wire [3:0]   hbuf_nedge   ,
    output wire         hbuf_segmented_mode,
    output reg          sppf_mode    ,
    output wire         sppf_pending_empty,
    output wire         sppf_prequal_ok,
    output wire         arn_req      ,
    output wire [2:0]   arn_page     ,
    output wire [5:0]   arn_gconv    ,
    input  wire         arn_ack_i    ,
    input  wire         arn_sealed_i ,
    input  wire         arn_err_i    ,
    input  wire [31:0]  pg_desc      ,   // active-page descriptor (CSR
                                        //   windowed face, §6.1)
    input  wire [6:0]   cv_slot      ,   // per-conv plan slot base (D4
                                        //   slot-doubling face; paged only)
    input  wire         rp_done_i    ,   // repack done (M11 repack hook;
                                        //   float = 1 = no wait, legacy)
    input  wire         rp_err_i     ,   // D1 (R155): repack err sticky
                                        //   level, mapped code 0x0E-0x12;
                                        //   float = 0 = no error, legacy
    input  wire [7:0]   rp_err_code_i,   // D1 (R155): mapped repack err
                                        //   code (consumed only under
                                        //   rp_err_lvl, fail-fast主面)
    output reg  [2:0]   page_r       ,   // active page (CSR window select +
                                        //   trace anchor payload)
    output reg          pg_adv       ,   // 1-cycle page advance -> hbuf rearm
    output reg  [5:0]   pg_base      ,   // new-page global conv base
    output reg  [4:0]   pg_nconv     ,   // new-page conv count (hbuf
                                        //   rearm legality bound)
    output reg  [2:0]   pg_nedge     ,   // new-page NEW-edge count
                                        //   (descriptor [6:4], hbuf rearm)
    output reg          pg_anchor    ,   // 1-cycle trace page anchor
    output reg  [2:0]   pg_anchor_page,  //   with the NEW page number
    output wire         rp_start_o   ,   // unique S_RP_START pulse
    input  wire         rp_busy_i    ,
    input  wire         rp_warm_i    ,
    input  wire         rp_pf_fault_i,
    input  wire         rp_pf_hang_i ,
    input  wire [23:0]  rp_bytes_i   ,
    output wire         rp_arm_o     ,
    output wire         rp_pf_abort_o,
    output wire         rp_sc_done_lvl,
    output wire [9:0]   rp_sc_blocks ,
    output wire [31:0]  rp_src_base_o,
    output wire [31:0]  rp_dst_base_o,
    output wire [15:0]  rp_c_o       ,
    output wire [15:0]  rp_h_o       ,
    output wire [15:0]  rp_w_o       ,
    output wire [15:0]  rp_vc_o      ,
    output wire [31:0]  rp_ypitch_o  ,
    output wire [15:0]  rp_nb_o      ,
    output wire         rp_commit_req,
    output reg          producer_arm_o,
    input  wire         repack_commit_i,
    input  wire         producer_commit_i,
    // ---- C3 r12 A 方案 (user ruling 2026-10-21): BRAM window prefetch
    //      strobe -- 拉高拍 = S_ADV 页推进分支拍（st<=S_PGE0 同拍），
    //      page_tables 据此当拍预取 page_r+1 窗行（A1_bram_plan.md v2.1
    //      §1.1；条件链共享 wire 律见下方 assign 注释）----
    output wire         pg_pref
);

    // ---------------- engine register offsets (byte) ----------------
    localparam [7:0] A_CTRL   = 8'h04, A_STATUS = 8'h08, A_GEOM   = 8'h0C,
                     A_ROWVAL = 8'h10, A_NMASK  = 8'h14, A_JOBCFG = 8'h18,
                     A_LDGRP  = 8'h1C, A_PBIAS  = 8'h20, A_PM     = 8'h24,
                     A_PSH    = 8'h28, A_PCTL   = 8'h2C, A_LUTD   = 8'h44,
                     A_LDLEN  = 8'h40, A_YSTAT  = 8'h48, A_BRG    = 8'h54,
                     A_LDSTAT = 8'h3C;

    localparam [31:0] TIMEOUT_MAX = 32'd50_000_000;   // 0.5 s @ 100 MHz
    // v2.4 (M11a): graph-mode watchdog budget (paged frames span pages;
    // 1.0 s @ 100 MHz).  Muxed per frame below (tmo_max_w).
    localparam [31:0] TIMEOUT_MAX_PG = 32'd100_000_000;

    // ---------------- main FSM ----------------
    localparam [5:0]
        S_IDLE  = 6'd0 ,
        S_LUTRD = 6'd1 , S_LUTD2 = 6'd27, S_LUTWR = 6'd2 , S_LUTEC = 6'd3 ,
        S_PREP  = 6'd4 , S_PREP2 = 6'd28, S_ARM   = 6'd5 ,
        S_Q1RD  = 6'd6 , S_Q1D2  = 6'd29, S_Q1W1  = 6'd7 , S_Q1W2  = 6'd8 ,
        S_Q1W3  = 6'd9 , S_Q1W4  = 6'd10, S_Q2    = 6'd11, S_G1    = 6'd12,
        S_G2    = 6'd13,
        S_L1    = 6'd14, S_L1W   = 6'd15, S_L1C   = 6'd16,
        S_G3A   = 6'd17, S_G3B   = 6'd18, S_G3C   = 6'd19,
        S_W     = 6'd20, S_W2    = 6'd21, S_W3    = 6'd22, S_W4    = 6'd23,
        S_ADV   = 6'd24, S_DONE  = 6'd25, S_HALT  = 6'd26,
        S_OAD   = 6'd30, S_OCR   = 6'd31,  // M9.3: arm-post-polls, credit
        // M9.4 walk states (multi-seg chain + per-conv table switch):
        //   S_CVRD/S_CVD2/S_CVLH : conv-table read + shadow latch
        //   S_SEG                : segment advance (latch next seg regs)
        //   S_CST                : CTRL start1 (chain seg1 fire)
        //   S_PST/S_PSQ          : post-start / post-queue completion polls
        S_CVRD  = 6'd32, S_CVD2 = 6'd33, S_CVLH = 6'd34, S_SEG  = 6'd35,
        S_CST   = 6'd36, S_PST  = 6'd37, S_PSQ  = 6'd38;
    // v2.3 PPP gate states (walk conv arrivals; DESIGN §3.3):
    //   S_PPPG gate   : table word at ppp_ptr matches arriving conv?
    //   S_PPPF fire   : ppu_start pulse (payload latched)
    //   S_PPPW wait   : hold consumer conv until ppu_done (abort->halt)
    localparam [5:0]
        S_PPPG  = 6'd39, S_PPPF = 6'd40, S_PPPW = 6'd41;
    // v2.4 page-advance states (M11a SPEC §2.4):
    //   S_PGE0 : bump page_r, watchdog refresh, trace page anchor
    //   S_PGE1 : pg_adv pulse {pg_base, pg_nconv} -> hbuf rearm
    //   S_PGE2 : SETTLE cycle -- the 2-stage PPP sanity pipeline (knife B)
    //            latches s1_r one cycle after the page_r bump and
    //            ppp_err_r the cycle after THAT (first valid DURING the
    //            3rd cycle post-bump).  Sampling ppp_err_r at the old
    //            S_PGE2 (= 2nd cycle) read the OLD window's scan -- G3
    //            case-1 proof: a poisoned new-page PPP word sailed
    //            through (err stayed 0, all 88 blocks ran).  One wait
    //            state, then:
    //   S_PGE3 : conv_cnt/ppp_ptr reset, new-page nconv latch, gconv+1,
    //            per-page PPP sanity sample (ppp_err_r now settled),
    //            fall into the PPP gate
    localparam [5:0]
        S_PGE0  = 6'd44, S_PGE1 = 6'd45, S_PGE2 = 6'd46, S_PGE3 = 6'd47,
        S_RP_ARM = 6'd48, S_RP_WARM = 6'd49,
        S_RP_START = 6'd50, S_RP_WAIT = 6'd51,
        S_BIND_WAIT = 6'd52, S_ARN0 = 6'd53, S_ARN1 = 6'd54,
        S_ARN2 = 6'd55, S_RP_COMMIT = 6'd56, S_CARRY_COMMIT = 6'd57;
    // v2.3 err codes (conv STATUS domain; avoid 1-10 + PPU island E_CODE)
    localparam [7:0] E_PPP_OPCODE     = 8'h20,
                     E_PPP_ORDER      = 8'h21,
                     E_PPP_DESC       = 8'h22,
                     E_LAYOUT_RANGE   = 8'h23,
                     E_LAYOUT_MISMATCH= 8'h24,
                     E_GEN_MISMATCH   = 8'h25;
    // v2.4 err code: paged frame without PAGE_CTRL auto_adv
    localparam [7:0] E_PGTABLE        = 8'h26;
    localparam [7:0] E_BIND           = 8'h27;
    localparam [7:0] E_COUNTER_WRAP   = 8'h28;
    localparam [7:0] E_ARN            = 8'h29;
    localparam [7:0] E_ARN_NOT_SEALED = 8'h2A;
    localparam [7:0] E_CVROW_TAG      = 8'h2B;
    localparam [7:0] E_RP_UNSEALED    = 8'h0E,
                     E_RP_NOT_ARMED   = 8'h0F,
                     E_RP_BUSY        = 8'h12;
    reg [5:0] st;

    // run latches
    reg [11:0] b_cnt;         // completed blocks
    reg [5:0]  rc_r, rcmax_r;
    // P1: hold RC across all spatial tiles for single-segment layers.
    reg        rc_outer_r;
    reg [11:0] spatial_total_r;
    reg [11:0] nt_r;
    reg [9:0]  oy_r;
    reg  [1:0] nseg_r;        // segments per block (1..3)
    reg  [1:0] seg_r;         // active segment index
    // Single-segment pairs keep both W groups resident. Multi-segment pairs
    // reuse each segment's X while only W is replaced for the odd RC.
    wire rc_pair_ss_w = rc_outer_r && (nseg_r == 2'd1) &&
                        (rcmax_r > 6'd1) && !rcmax_r[0] &&
                        (spatial_total_r != 12'd0);
    wire rc_pair_ms_w = (nseg_r == 2'd2) && (rcmax_r > 6'd1) && !rcmax_r[0] &&
                        (spatial_total_r != 12'd0);
    wire rc_pair_w = rc_pair_ss_w || rc_pair_ms_w;
    assign rt_w_reuse = rc_pair_ss_w && !rc_r[0] && (nt_r != 12'd0);
    assign rt_w_only  = (rc_pair_ss_w && rc_r[0] && (nt_r == 12'd0)) ||
                        (rc_pair_ms_w && rc_r[0]);
    assign rt_noload  = rc_pair_ss_w && rc_r[0] && (nt_r != 12'd0);
    wire ld_wait_busy = rt_w_only ? ld_w_busy :
                        (rt_w_reuse ? ld_x_busy : (ld_w_busy || ld_x_busy));
    reg [3:0]  s_r, ns_r;
    reg [3:0]  r_cur;         // Q1 row cursor
    reg [7:0]  lut_i;
    reg [4:0]  vc_r;
    reg [15:0] nmask_r;
    reg [15:0] arm_nmask;
    reg [10:0] k_r;
    reg [7:0]  jc_r;
    reg [1:0]  g_r;
    reg [31:0] stride_r, obuf_r;
    reg [31:0] timeout;
    reg        seen_busy;     // L1W two-phase wait latch
    reg        ovl_r;         // M9.3 overlap mode latch
    reg        fin_r;         // final-block poll pass
    reg  [4:0] vc_poll_r;     // pollee (b-1) expected vc, overlap polls
    // M9 walk+overlap (V2.1) handoff bits -- see header + DESIGN_WALK_OVL
    reg        polls_pend_r;  // a fired CTRL awaits its polls (S_W4 clears)
    reg        lut_pend_r;    // this conv's LUT reload deferred (S_CVLH set)
    reg        cv_load_en;    // g3r6 timing cut: registered strobe for the
                              // S_CVLH wide shadow-load group (set in
                              // S_CVD2, 1-cycle pulse).  Replaces the
                              // (st==S_CVLH) decode on ~30 load enables;
                              // g3r5 first-pass timing showed Vivado's CE
                              // restructuring merging that decode into a
                              // 339-load shared control net with a
                              // 24-level ppp_tab->CE cone (wns -0.603).
    reg        lut_ret_q1_r;  // LUT prologue returns to S_Q1RD (nested pos)
    // 2e credit-gated release (SPEC §7): CHAIN_REL mode + S||L telemetry
    reg        rel_r;         // CHAIN_REL (CSR 0xE0[0]) sampled at start

    // M9.4 conv-table walk latches
    reg        walk_r;        // cfg_nconv>1 mode
    reg  [4:0] conv_cnt;      // active conv index (0..nconv-1; r10: 5b,
                              // 25 live convs -- idx up to 24)
    reg  [4:0] nconv_r;       // latched cfg_nconv
    reg [11:0] nb_c;          // per-conv block count (table nb)
    reg [15:0] nb_tot;        // cumulative block base of this conv
    reg [11:0] swoff_r;       // current segment w_off (12b table field)
    reg [15:0] sk0ic_r;       // current segment k-seed kIC
    reg  [2:0] sk0kh_r;       // current segment k-seed kKH (3b table field)
    reg  [2:0] sk0kw_r;       // current segment k-seed kKW (3b table field)
    reg [55:0] seg_tab [0:2]; // per-seg {kw0,kh0,ic0,woff,g,jc,k} (55b)
    reg  [13:0] pbase;       // pctl ROM base = slot*128 (v2.4: 14b slot
                             // face; legacy slot==conv == r10 values)
    reg  [10:0] sbase;       // strip ROM base = slot*16  (v2.4: 11b)
    reg  [14:0] lbase;       // lut ROM base  = slot*256 (v2.4: 15b)
    reg         dual_entry_r;
    wire        entry_idx_w = dual_entry_r && (b_cnt >= 12'd160);
    wire [11:0] entry_base_w = entry_idx_w ? 12'd160 : 12'd0;
    wire [11:0] b_entry_w = b_cnt - entry_base_w;

    // v2.3 PPP walk registers (DESIGN §3): ppp_ptr walks the 8-word CSR
    // table once per frame; frame_gen_r latches the CSR generation at the
    // doorbell for both the ppu_start payload and later gen compare.
    // v2.4: the 8 words are the ACTIVE PAGE's window (CSR windowed face);
    // ppp_ptr is page-local, reset at the doorbell and at every page
    // advance.
    reg  [2:0]  ppp_ptr;      // active PPP table word (0..7)
    // D2 判决锁存 (设计件 §3, R154): 单拍判决捕获寄存器组
    reg         ppp_vld;      // verdict latched (取代 ppu_done 电平判据)
    reg         ppp_ab;       // latched abort
    reg  [7:0]  ppp_err;      // latched ppu_done_err
    reg  [7:0]  frame_gen_r;  // generation latched at doorbell

    // ---------------- R160 unique SPPF epoch / qualification ------------
    reg         cv1_epoch_active;
    reg         cv1_epoch_seal;
    reg  [7:0]  cv1_close_count;
    reg         sc_done_d;
    reg         rp_anchor_seen;
    reg         rp_anchor_consumed;
    reg         rp_armed_q;
    reg         rp_start_q;
    reg         rp_arm_q;
    reg         pending_at_start_q;
    reg         producer_sealed_this_db;
    reg         rp_anchor_required_q;
    reg         owner_valid_q;
    reg         owner_pgauto_q;
    reg  [3:0]  owner_npages_q;
    reg  [31:0] owner_ybase_q;
    reg  [31:0] producer_src_base_q;
    reg  [7:0]  producer_oc_q;
    reg  [15:0] producer_h_q;
    reg  [15:0] producer_w_q;
    reg  [4:0]  producer_vc_q;
    reg  [5:0]  producer_rc_q;
    reg  [11:0] producer_nb_q;
    wire        rp_geom_zero = (producer_oc_q == 8'd0) ||
                               (producer_h_q == 16'd0) ||
                               (producer_w_q == 16'd0) ||
                               (producer_vc_q == 5'd0);
    wire        rp_geom_valid = !rp_geom_zero &&
                                ({11'd0, producer_w_q} <=
                                 {22'd0, producer_vc_q});
    wire        rp_state_w = (st == S_RP_ARM) || (st == S_RP_WARM) ||
                             (st == S_RP_START) || (st == S_RP_WAIT) ||
                             (st == S_RP_COMMIT);
    assign      rp_pf_abort_o = (st == S_HALT) && (err != 8'd0);
    assign      rp_sc_done_lvl = cv1_epoch_seal;
    assign      rp_sc_blocks = {2'd0, cv1_close_count};
    assign      rp_src_base_o = producer_src_base_q;
    assign      rp_dst_base_o = producer_src_base_q;
    assign      rp_c_o = {8'd0, producer_oc_q};
    assign      rp_h_o = producer_h_q;
    assign      rp_w_o = producer_w_q;
    assign      rp_vc_o = {11'd0, producer_vc_q};
    assign      rp_ypitch_o = ({27'd0, producer_vc_q} *
                               {26'd0, producer_rc_q}) << 3;
    assign      rp_nb_o = {4'd0, producer_nb_q};

    // ---------------- v2.4 page-scheduling registers (SPEC §2) ----------
    // gconv = running GLOBAL conv index (6b, D4 63-conv face).  Legacy
    // walks keep gconv == conv_cnt value-exact (both step 0,1,2.. at the
    // same boundary) -> the widened cv_addr/conv_idx faces are a
    // zero-drift superset.
    reg  [5:0]  gconv;
    reg         manual_paged_r;
    reg  [2:0]  schedule_page_r;
    reg  [3:0]  npages_r;
    reg         pgauto_r;
    reg  [5:0]  post_bind_state;
    reg  [5:0]  arn_resume_state;
    reg         arn_reset_epoch_q;
    reg         arriving_cv_valid_q;
    reg  [6:0]  arriving_cv_slot_q;
    reg  [10:0] arriving_cv_tag_q;
    reg  [10:0] arriving_tag_next_q;
    reg         bind_window_waited;
    reg         hbuf_started;
    // page_r = active page register (0..npages-1); drives the CSR
    // windowed table face (pg_raddr) and the trace page anchor.
    // pg_base/pg_nconv/pg_anchor are the hbuf/trace page-advance face,
    // valid at the pg_adv pulse.
    // Frozen-wrapper float guards (sim-safety law): unconnected new
    // inputs decode to the legacy degenerate frame (npages=1, no repack
    // wait).  r12 build wires the real faces through the wrappers.
    wire [3:0]  npages_i  = (cfg_npages === 3'bzzz)  ? 4'd1 :
                            (cfg_npages == 3'd0)     ? 4'd1 :
                                    {1'b0, cfg_npages} + 4'd1; // count-1 enc
    wire        pgauto_i  = (cfg_pgauto === 1'bz)    ? 1'b0 : cfg_pgauto;
    wire        manual_paged_w = !pgauto_i && (cfg_nconv > 5'd1) &&
                                 ((npages_i > 4'd1) ||
                                  (cfg_schedule_page != 3'd0) ||
                                  (cfg_gconv_base != 6'd0));
    wire        rp_done_g = (rp_done_i === 1'bz)     ? 1'b1 : rp_done_i;
    wire        ppu_write_fence_g = (ppu_write_fence_i === 1'bz) ?
                                      1'b1 : ppu_write_fence_i;
    // D1 (R155): err face guards, frozen-wrapper float law对称
    // (rp_done_i 浮空=1 无等待 / rp_err_i 浮空=0 无错误 = legacy 退化).
    wire        rp_err_lvl  = (rp_err_i === 1'bz)    ? 1'b0 : rp_err_i;
    wire [7:0]  rp_err_code_m = (rp_err_code_i === 8'hzz) ? 8'h00
                                                      : rp_err_code_i;
    wire [6:0]  cv_slot_g = (cv_slot  === 7'bzzzzzzz)? 7'd0 : cv_slot;
    // paged frame = walk with npages > 1 (latched walk_r; at the
    // doorbell walk_r is still the PREVIOUS frame's value, so the
    // S_IDLE entry branch qualifies the npages check with the new
    // cfg_nconv>1 decode directly -- see below)
    wire        paged_w   = walk_r && ((npages_r > 4'd1) || manual_paged_r);
    wire [3:0]  npages_eff = pgauto_r ? npages_r : 4'd1;
    wire        repack_commit_g = (repack_commit_i === 1'bz) ? 1'b0 :
                                  repack_commit_i;
    wire        producer_commit_g = (producer_commit_i === 1'bz) ? 1'b0 :
                                    producer_commit_i;
    assign      arn_req = (st == S_ARN0);
    assign      arn_page = schedule_page_r;
    assign      arn_gconv = gconv;
    wire [10:0] arriving_context_now = {arn_reset_epoch_q, pgauto_r,
                                        schedule_page_r, gconv};
    wire        arriving_row_qual = arriving_cv_valid_q &&
                                    (arriving_cv_tag_q == arriving_context_now);
    wire        arn_first_row = (conv_cnt == 5'd0) &&
                                (gconv == cfg_gconv_base);
    wire        arn_sealed_ok = arn_first_row || arn_sealed_i;
    assign      rp_commit_req = (st == S_RP_COMMIT);
    wire        arm_accept_shadow = (st == S_RP_WARM) && rp_arm_o &&
                                    !rp_busy_i && rp_geom_valid &&
                                    !rp_err_lvl && !rp_pf_fault_i &&
                                    cv1_epoch_seal &&
                                    (cv1_close_count == 8'd160);
    wire        rp_pf_explicit = rp_pf_fault_i;
    // R164: native 03/04 is registered on the actual arm edge.  Arbitrate
    // the identical geometry refusal in that same issuer WARM cycle so the
    // old native rp_err=0 cannot be misdiagnosed as NOT_ARMED.  Native still
    // independently latches 03/04; these are its specified ABI mappings.
    wire        rp_arm_geom_fault = (st == S_RP_WARM) && rp_arm_o &&
                                    !rp_geom_valid;
    wire [7:0]  rp_arm_geom_code = rp_geom_zero ? 8'h11 : 8'h10;
    wire        rp_explicit_fault = rp_err_lvl || rp_pf_explicit ||
                                    rp_arm_geom_fault;
    wire [7:0]  rp_explicit_code = rp_err_lvl ?
                                    ((rp_err_code_m == 8'd0) ? E_RP_BUSY :
                                                               rp_err_code_m) :
                                    rp_pf_explicit ? E_RP_UNSEALED :
                                    rp_arm_geom_code;
    assign      rp_start_o = rp_start_q && !rp_err_lvl && !rp_pf_fault_i &&
                               !rp_pf_hang_i;
    assign      rp_arm_o   = rp_arm_q && !rp_err_lvl && !rp_pf_fault_i &&
                             !rp_pf_hang_i;
    // per-page conv count: descriptor nconv field is count-1 ([3:0])
    wire [4:0]  pg_nconv_w = {1'b0, pg_desc[3:0]} + 5'd1;

    // ---------------- C3 r12 A 方案: pg_pref 共享条件链 -------------------
    // 落地条件 1（competition-b6）：pg_pref 必须是 S_ADV 页推进分支
    // （st<=S_PGE0，全 issuer 唯一，L1510-1522 区）条件链的**同一表达式**
    // 副本抽成 wire——此处逐词复用该分支的嵌套条件，禁重写（防推导漂移）：
    //   st==S_ADV（assign 外层） && walk_r && {2'd0,b_cnt}==nb_c-12'd1
    //   && conv_cnt==nconv_r-5'd1 && !({1'b0,page_r}==npages_i-4'd1)
    // 时序账（A1_bram_plan.md §1.1）：本拍拉高 -> page_tables 当拍送
    // page_r+1 的 B 口读地址 -> S_PGE0 拍初 bank 为新窗 -> bump 后
    // cycle1 起消费者见新窗（sanity 流水逐拍对齐保持，页路径零拍变化）。
    assign pg_pref = (st == S_ADV) && walk_r && pgauto_r
                   && (b_cnt == nb_c - 12'd1)
                   && (conv_cnt == nconv_r - 5'd1)
                   && ({1'b0, page_r} != npages_r - 4'd1);
    // plan slot base: paged = D4 slot face (slot doubling aware), legacy
    // = conv_cnt (r10 slot==conv law).  slot 7 stays reserved for the
    // M10P4.cv2 rc=32 doubling in the baked face, exactly as r10.
    wire [6:0]  slot_w    = paged_w ? arriving_cv_slot_q :
                            {2'b00, conv_cnt};
    wire [6:0]  second_slot_w = slot_w + 7'd1;
    // watchdog budget: graph mode (paged) gets the 2x page-span budget
    assign tmo_max_w = paged_w ? TIMEOUT_MAX_PG : TIMEOUT_MAX;
    assign sc_timeout_limit = tmo_max_w;
    wire manual_epoch_start_bad = manual_paged_w &&
                                  (cfg_schedule_page > 3'd4);
    wire sppf_pending_present = cv1_epoch_active || cv1_epoch_seal ||
                                (cv1_close_count != 8'd0) || owner_valid_q;
    wire sppf_pending_legal = cv1_epoch_active && cv1_epoch_seal &&
                              (cv1_close_count == 8'd160) && owner_valid_q &&
                              producer_commit_g &&
                              (owner_pgauto_q == pgauto_i) &&
                              (owner_npages_q == npages_i) &&
                              (owner_ybase_q == cfg_ybase);
    wire sppf_start_bad = sppf_pending_present &&
                          (!manual_paged_w || !sppf_pending_legal);
    assign sppf_pending_empty = !sppf_pending_present;
    assign sppf_prequal_ok = !sppf_pending_present ||
                             (manual_paged_w && sppf_pending_legal);
    wire accepted_mode_change = (st != S_IDLE) && (st != S_DONE) &&
                                (st != S_HALT) &&
                                ((npages_i != npages_r) ||
                                 (pgauto_i != pgauto_r));
    wire manual_pending_carry_ok = manual_paged_r && cv1_epoch_active &&
                                   cv1_epoch_seal &&
                                   (cv1_close_count == 8'd160) &&
                                   producer_sealed_this_db &&
                                   producer_commit_g &&
                                   !pending_at_start_q &&
                                   !rp_anchor_required_q &&
                                   !rp_anchor_seen;
    wire epoch_done_ok = (!cv1_epoch_active &&
                          (!rp_anchor_required_q || rp_anchor_consumed)) ||
                         manual_pending_carry_ok;
    wire manual_producer_commit_wait = manual_paged_r && cv1_epoch_active &&
                                       cv1_epoch_seal &&
                                       (cv1_close_count == 8'd160) &&
                                       producer_sealed_this_db &&
                                       !producer_commit_g &&
                                       !pending_at_start_q &&
                                       !rp_anchor_required_q &&
                                       !rp_anchor_seen;
    wire manual_bind_range_bad = manual_paged_r &&
                                 (({3'd0, gconv} +
                                   {4'd0, pg_nconv_w}) > 9'd63);
    assign hbuf_nconv = ((npages_i > 4'd1) || manual_paged_w) ?
                        pg_nconv_w : cfg_nconv;
    assign hbuf_nedge = ((npages_i > 4'd1) || manual_paged_w) ?
                        {1'b0, pg_desc[6:4]} : cfg_nedge;
    assign hbuf_segmented_mode = manual_paged_r;
    function [4:0] popcount16;
        input [15:0] value;
        integer pc_i;
        begin
            popcount16 = 5'd0;
            for (pc_i = 0; pc_i < 16; pc_i = pc_i + 1) begin
                popcount16 = popcount16 + {4'd0, value[pc_i]};
            end
        end
    endfunction
    wire [4:0] arm_valid_rows_legacy = popcount16(arm_nmask);
    wire arm_up2x_w = 1'b0;  // DIAG_ARM_UP2X_OFF: coherent ordinary-CHW contract
    wire [9:0] arm_valid_product_legacy = arm_valid_rows_legacy *
                                              strip_data[20:16];
    wire [15:0] selected_legacy_w = arm_up2x_w ?
                                 {6'd0, strip_data[20:16], 5'b00000} :
                                 (arm_nmask == 16'hFFFF) ?
                                 {8'd0, strip_data[20:16], 3'b000} :
                                 {6'd0, arm_valid_product_legacy};
    wire [9:0] arm_row_base = {1'b0, rc_r, 3'b000};
    wire [9:0] arm_oc_ext = {2'd0, wl_oc};
    wire [9:0] arm_rows_rem = arm_oc_ext - arm_row_base;
    wire       arm_rows_positive = (arm_oc_ext != 10'd0) &&
                                   (arm_oc_ext > arm_row_base);
    wire [4:0] arm_valid_rows = !arm_rows_positive ? 5'd0 :
                                (arm_rows_rem >= 10'd8) ? 5'd8 :
                                arm_rows_rem[4:0];
    // n_mask describes spatial pixels, never output-channel rows.  The
    // channel count comes only from wl_oc/rc; this is required for OC=7 heads.
    wire arm_mask_legal = (arm_nmask == 16'hFFFF) ||
                          (arm_nmask == 16'h00FF) ||
                          (arm_nmask == 16'h000F) ||
                          (arm_nmask == 16'h03FF);
    wire [9:0] arm_valid_product = arm_valid_rows * strip_data[20:16];
    wire [15:0] selected_contract_w = arm_up2x_w ?
                                 {6'd0, strip_data[20:16], 5'b00000} :
                                 {6'd0, arm_valid_product};
    // Preserve the dense-prefix contract for regular masks and use the exact
    // popcount byte count for legal sparse masks.  Non-prefix masks are not a
    // reason to reject a compact block.
    wire [15:0] selected_arm_w = arm_mask_legal ? selected_contract_w :
                                                 selected_legacy_w;
    wire arm_contract_err = paged_w &&
                            ((strip_data[20:16] == 5'd0) ||
                             !arm_rows_positive || (selected_arm_w == 16'd0) ||
                             (arm_up2x_w && ((arm_valid_rows != 5'd8) ||
                                             (arm_nmask != 16'hFFFF))));
    wire [23:0] face_ch_bytes = {16'd0, wl_oc} * {8'd0, geo_h};
    wire [39:0] face_pixels = {16'd0, face_ch_bytes} * {24'd0, geo_w};
    // Regular paged convs materialize CHW directly.  SPPF slot 28 keeps
    // the existing slot+repack path; dual-slot RC=32 adds the second half's
    // 16-RC (128-channel) offset when b>=160.
    wire [15:0] chw_out_h = (geo_sh == 4'd2)
                          ? (((geo_h + {11'd0, geo_ph, 1'b0} - geo_kh) >> 1) + 16'd1)
                          : ((geo_h + {11'd0, geo_ph, 1'b0} - geo_kh) + 16'd1);
    wire [15:0] chw_out_w = (geo_sw == 4'd2)
                          ? (((geo_w + {11'd0, geo_pw, 1'b0} - geo_kw) >> 1) + 16'd1)
                          : ((geo_w + {11'd0, geo_pw, 1'b0} - geo_kw) + 16'd1);
    wire [31:0] chw_plane_stride = {16'd0, chw_out_h} * {16'd0, chw_out_w};
    wire [5:0]  chw_rc = rc_r + (entry_idx_w ? 6'd16 : 6'd0);
    wire [31:0] chw_rc_offset = {26'd0, chw_rc} * (chw_plane_stride << 3);
    wire [31:0] chw_oy_offset = {22'd0, oy_r} * {16'd0, chw_out_w};
    wire        chw_mode_w = paged_w && !arm_up2x_w;
    wire [31:0] chw_block_base = obuf_r + chw_rc_offset + chw_oy_offset
                               + {24'd0, s_r, 4'd0};
    assign dense_face_off = obuf_r - cfg_ybase;
    assign dense_face_expected_bytes = arm_up2x_w ?
                                       {face_pixels[29:0], 2'b00} :
                                       face_pixels[31:0];
    assign dense_face_geometry_err = (face_pixels == 40'd0) ||
                                     (arm_up2x_w ? (|face_pixels[39:30]) :
                                                   (|face_pixels[39:32]));
    // ---------------- AXI op-sequencer ----------------
    // axf_start (1-cycle) launches; axf_busy holds; axf_done (1-cycle)
    // closes; axf_rdata latches the read result.
    reg        axf_start, axf_we;
    reg [7:0]  axf_addr;
    reg [31:0] axf_wdata;
    reg        axf_busy, axf_done;
    reg [31:0] axf_rdata;

    localparam [1:0] AX_IDLE = 2'd0, AX_HS = 2'd1, AX_B = 2'd2, AX_R = 2'd3;
    reg [1:0]  ax_st;
    reg        ax_we_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ax_st <= AX_IDLE; ax_we_r <= 1'b0;
            m_awvalid <= 1'b0; m_wvalid <= 1'b0; m_bready <= 1'b0;
            m_arvalid <= 1'b0; m_rready <= 1'b0;
            m_awaddr <= 8'd0; m_wdata <= 32'd0; m_araddr <= 8'd0;
            axf_busy <= 1'b0; axf_done <= 1'b0; axf_rdata <= 32'd0;
        end else begin
            axf_done <= 1'b0;                       // pulse default
            case (ax_st)
            AX_IDLE: if (axf_start) begin
                ax_we_r  <= axf_we;
                if (axf_we) begin
                    m_awaddr  <= axf_addr;
                    m_wdata   <= axf_wdata;
                    m_awvalid <= 1'b1; m_wvalid <= 1'b1; m_bready <= 1'b1;
                end else begin
                    m_araddr  <= axf_addr;
                    m_arvalid <= 1'b1; m_rready <= 1'b1;
                end
                axf_busy <= 1'b1;
                ax_st <= AX_HS;
            end
            AX_HS: if (ax_we_r) begin
                if (m_awvalid && m_awready) m_awvalid <= 1'b0;
                if (m_wvalid  && m_wready ) m_wvalid  <= 1'b0;
                if (!m_awvalid && !m_wvalid) ax_st <= AX_B;
                // valids hold until their own handshake (req-hold law)
            end else begin
                if (m_arvalid && m_arready) begin
                    m_arvalid <= 1'b0;
                    ax_st <= AX_R;
                end
            end
            AX_B: if (m_bvalid && m_bready) begin
                m_bready <= 1'b0;
                axf_busy <= 1'b0; axf_done <= 1'b1;
                ax_st <= AX_IDLE;
            end else
                m_bready <= 1'b1;                   // hold
            AX_R: if (m_rvalid && m_rready) begin
                axf_rdata <= m_rdata;
                m_rready <= 1'b0;
                axf_busy <= 1'b0; axf_done <= 1'b1;
                ax_st <= AX_IDLE;
            end else
                m_rready <= 1'b1;                   // hold
            default: ax_st <= AX_IDLE;
            endcase
        end
    end

    // helper wires over the latched read result
    wire [12:0] ldlen_w = axf_rdata[12:0];
    wire [12:0] ldlen_x = axf_rdata[25:13];
    // overlap polls check block b-1 (or NB-1 on the fin pass) -> vc_poll_r
    wire [15:0] ycnt_exp = {8'd0, (ovl_r ? vc_poll_r : vc_r), 3'b000};
    // LDGRP write value: SEQ = cfg, OVL = ping-pong parity {p,p}
    wire [1:0]  g_cur = ovl_r ? (b_cnt[0] ? 2'd3 : 2'd0) :
                        (rc_pair_ss_w && rc_r[0]) ? 2'd1 : g_r;
    // Only single-segment odd jobs remap to W1/X0; multi-segment groups stay.
    wire [7:0]  jc_cur = ovl_r ? (jc_r | (b_cnt[0] ? 8'h18 : 8'h00)) :
                         !rc_pair_ss_w ? jc_r :
                         (rc_r[0] ? ((jc_r & 8'hE7) | 8'h08) : (jc_r & 8'hE7));
    assign trace_arm_oy     = oy_r;
    assign trace_arm_s      = s_r;
    assign trace_arm_rc     = rc_r;
    // {x_read_group,w_read_group}, exactly the JOBCFG read-bank bits.
    assign trace_arm_groups = g_cur;
    assign trace_arm_nseg   = nseg_r;
    assign trace_arm_k_ic   = sk0ic_r;
    assign trace_arm_kh     = {1'b0, sk0kh_r};
    assign trace_arm_kw     = {1'b0, sk0kw_r};
    assign trace_arm_k_len  = k_r;
    assign trace_arm_conv   = conv_cnt[3:0];   // observe-only tap: stays 4b
                              // (trace contract; conv>=16 aliases -- the
                              // r10 ledger/README item-4 trace probe widening
                              // is the sim-side follow-up)
    assign trace_arm_geom_kh = geo_kh;
    assign trace_arm_geom_kw = geo_kw;

    // M9.4: memory words first, then bit-select (V2001 law).  Layout:
    //   seg[54:52] kw0 | [51:49] kh0 | [48:33] ic0 | [32:21] woff(12b)
    //        | [20:19] g | [18:11] jc | [10:0] k
    wire [55:0] seg0_w = seg_tab[2'd0];          // block-start segment
    wire [55:0] segn_w = seg_tab[seg_r + 2'd1];  // next segment (S_SEG)

    assign busy = (st != S_IDLE) && (st != S_HALT);
    assign done = (st == S_DONE);
    assign scatter_verified_close = (st == S_W4) && sc_done && !sc_err;

    // ---------------- v2.3 PPP sanity (two-stage, g3r9 knife B) ---------
    // DESIGN §3.3-1: scan words 0..7 up to the first EMPTY sentinel.
    // Kept words must carry a legal engine_mux opcode (0x11 add / 0x12
    // xfer / 0x13 maxpool5), conv_node non-descending (multi-word same
    // node legal = SPPF chain, but NOT after a ppp_last word), and a
    // desc_idx strictly below the PPU island's loaded-DESC count.  All
    // words after the first EMPTY are tail garbage by the PS load law
    // (整表重写或写至表尾) -- ignored.  Empty table = trivially sane =
    // v1 structural identity.
    //
    // g3r9 knife B (user ruling 2026-10-17: restructure over brute force):
    // the sequential 8-word scan was one ~22-LUT-level cone from
    // cfg_ppp_tab (u_csr) to ppp_err_r_reg/D -- the g3r8 residual
    // worst-path family (route 81%).  Cut the scan at word 4 into two
    // free-running stages (11+11 levels): stage 1 scans words 0..3 into
    // pipeline regs, stage 2 continues words 4..7 into ppp_err_r.  Scan
    // inputs are quasi-static at the doorbell (PS write-then-ring law;
    // ppu_desc_count is constant 7'd0 in silicon, m9_v25_top_v3), so the
    // settled value is bit-identical and the doorbell samples it exactly
    // as before -- err latch cycle, codes and PPP>layout priority all
    // unchanged.  Consumer audit: the only reader of the sanity pair is
    // the S_IDLE doorbell branch (KNIFE_B_ISSUER_ERR_SAMPLING_CHECK).
    reg [7:0]  ppp_err_c;         // stage-2 output (final err)
    reg        ppp_seen_empty;
    reg [4:0]  ppp_node_last_c;   // conv_node of the last kept word
    reg        ppp_plast_c;       // its ppp_last bit
    reg [7:0]  ppp_err_s1_c;      // stage-1 outputs (words 0..3)
    reg        ppp_seen_empty_s1_c;
    reg [4:0]  ppp_node_last_s1_c;
    reg        ppp_plast_s1_c;
    // stage-1 pipeline regs -- declared HERE because stage-2 below reads
    // them (Verilog-2001: declaration must precede use)
    reg [7:0]  ppp_err_s1_r;
    reg        ppp_seen_empty_s1_r;
    reg [4:0]  ppp_node_last_s1_r;
    reg        ppp_plast_s1_r;
    integer    ppp_k1;
    integer    ppp_k2;
    reg [4:0]  ppp_op1_c;         // stage-1 word temporaries
    reg [4:0]  ppp_nd1_c;
    reg [6:0]  ppp_ds1_c;
    reg        ppp_pl1_c;
    reg [4:0]  ppp_op_c;          // stage-2 word temporaries
    reg [4:0]  ppp_nd_c;
    reg [6:0]  ppp_ds_c;
    reg        ppp_pl_c;
    always @* begin : ppp_scan_s1                 // words 0..3
        ppp_err_s1_c        = 8'd0;
        ppp_seen_empty_s1_c = 1'b0;
        ppp_node_last_s1_c  = 5'd0;
        ppp_plast_s1_c      = 1'b0;
        for (ppp_k1 = 0; ppp_k1 < 4; ppp_k1 = ppp_k1 + 1) begin
            // DESIGN §2.2 erratum v1.0.1: opcode is [4:0] (0x11/0x12/0x13
            // need 5 bits to stay engine_mux-same-valued); fields shifted
            ppp_op1_c = cfg_ppp_tab[ppp_k1*32    +: 5];
            ppp_nd1_c = cfg_ppp_tab[ppp_k1*32+5  +: 5];
            ppp_ds1_c = cfg_ppp_tab[ppp_k1*32+10 +: 7];
            ppp_pl1_c = cfg_ppp_tab[ppp_k1*32+18];
            if (!ppp_seen_empty_s1_c && ppp_err_s1_c == 8'd0) begin
                if (ppp_op1_c == 5'h0)
                    ppp_seen_empty_s1_c = 1'b1;    // EMPTY sentinel: stop
                else if (ppp_op1_c != 5'h11 && ppp_op1_c != 5'h12 &&
                         ppp_op1_c != 5'h13 && ppp_op1_c != 5'h14)
                    ppp_err_s1_c = E_PPP_OPCODE;
                else if (ppp_nd1_c < ppp_node_last_s1_c)
                    ppp_err_s1_c = E_PPP_ORDER;    // strict descent
                else if (ppp_plast_s1_c && (ppp_nd1_c == ppp_node_last_s1_c))
                    ppp_err_s1_c = E_PPP_ORDER;    // word after ppp_last
                else if (ppp_ds1_c >= ppu_desc_count)
                    ppp_err_s1_c = E_PPP_DESC;     // unloaded DESC slot
                else begin
                    ppp_node_last_s1_c = ppp_nd1_c;
                    ppp_plast_s1_c     = ppp_pl1_c;
                end
            end
        end
    end
    always @* begin : ppp_scan_s2                 // words 4..7
        ppp_err_c       = ppp_err_s1_r;
        ppp_seen_empty  = ppp_seen_empty_s1_r;
        ppp_node_last_c = ppp_node_last_s1_r;
        ppp_plast_c     = ppp_plast_s1_r;
        for (ppp_k2 = 4; ppp_k2 < 8; ppp_k2 = ppp_k2 + 1) begin
            ppp_op_c = cfg_ppp_tab[ppp_k2*32    +: 5];
            ppp_nd_c = cfg_ppp_tab[ppp_k2*32+5  +: 5];
            ppp_ds_c = cfg_ppp_tab[ppp_k2*32+10 +: 7];
            ppp_pl_c = cfg_ppp_tab[ppp_k2*32+18];
            if (!ppp_seen_empty && ppp_err_c == 8'd0) begin
                if (ppp_op_c == 5'h0)
                    ppp_seen_empty = 1'b1;         // EMPTY sentinel: stop
                else if (ppp_op_c != 5'h11 && ppp_op_c != 5'h12 &&
                         ppp_op_c != 5'h13 && ppp_op_c != 5'h14)
                    ppp_err_c = E_PPP_OPCODE;
                else if (ppp_nd_c < ppp_node_last_c)
                    ppp_err_c = E_PPP_ORDER;        // strict descent
                else if (ppp_plast_c && (ppp_nd_c == ppp_node_last_c))
                    ppp_err_c = E_PPP_ORDER;        // word after ppp_last
                else if (ppp_ds_c >= ppu_desc_count)
                    ppp_err_c = E_PPP_DESC;         // unloaded DESC slot
                else begin
                    ppp_node_last_c = ppp_nd_c;
                    ppp_plast_c     = ppp_pl_c;
                end
            end
        end
    end

    // ---------------- v2.3 LAYOUT sanity (combinational) ----------------
    // DESIGN §4.1/§4.3: per-conv 3b field must be one-hot-or-zero
    // (multi-bit = E_LAYOUT_MISMATCH); legacy nconv>10 with any non-
    // default layout = E_LAYOUT_RANGE (10-conv vector boundary).
    // v2.4: the paged branch scans the full 16 page-local fields (48b
    // vector; per-page nconv <= 16 by the 4b descriptor field, so the
    // RANGE exit is structurally unnecessary paged).  Legacy branch is
    // byte-identical to v2.3 (10 fields + the 0x23 range check) -- the
    // 48b face truncates to the legacy 30b at the frozen wrapper.
    reg [7:0] layout_err_c;
    reg [2:0] layout_f_c;
    integer   layout_k;
    always @* begin
        layout_err_c = 8'd0;
        if (paged_w) begin
            for (layout_k = 0; layout_k < 16; layout_k = layout_k + 1) begin
                layout_f_c = cfg_layout_id[layout_k*3 +: 3];
                if ((layout_f_c & (layout_f_c - 3'd1)) != 3'd0)
                    layout_err_c = E_LAYOUT_MISMATCH;
            end
        end else begin
            for (layout_k = 0; layout_k < 10; layout_k = layout_k + 1) begin
                layout_f_c = cfg_layout_id[layout_k*3 +: 3];
                if ((layout_f_c & (layout_f_c - 3'd1)) != 3'd0)
                    layout_err_c = E_LAYOUT_MISMATCH;
            end
            if ((cfg_nconv > 5'd10) && (cfg_layout_id[29:0] != 30'd0))
                layout_err_c = E_LAYOUT_RANGE;
        end
    end

    // ---------------- g3r8 timing cut: registered sanity ------------------
    // ppp_err_c / layout_err_c are deep combinational scans of cfg_ppp_tab /
    // cfg_layout_id (~22 LUT levels).  Feeding the S_IDLE doorbell enables
    // with them directly put the ENTIRE legacy shadow-load group CE on a
    // ppp_tab_reg -> CE critical cone (g3r7 first pass: wns=-1.500ns,
    // 497 endpoints, all geo_*/wl_* CE pins; physopt second chance made it
    // WORSE, -1.791ns -- empirical proof of the no-brute-force ruling).
    // PS law: table/vector are written BEFORE the doorbell (write-then-
    // ring) and stable for many cycles, so a free-running register samples
    // exactly the value the doorbell edge sees.  Zero state machines / zero
    // cycles added: S_IDLE reads the registered pair instead of the raw
    // combinational pair; first-error-wins ordering (PPP outranks layout)
    // and all err codes unchanged.
    reg [7:0] ppp_err_r;
    reg [7:0] layout_err_r;
    // g3r9 knife B stage-1 pipeline regs are declared up with the scan
    // blocks (stage-2 reads them); ppp_err_r now latches the STAGE-2 cone
    // (words 4..7 continued from those regs), so the 22-level single cone
    // becomes 11+11 across a register.

    // ---------------- v2.3 active-word decode (S_PPPG gate face) ---------
    // Memory word first, then bit-select (V2001 law -- same style as the
    // seg_tab face above).  ppp_w is the table word ppp_ptr currently
    // points at; ppp_hit_w asks "does this word fire for the ARRIVING
    // conv?" (non-EMPTY opcode + node match).
    wire [31:0] ppp_w    = cfg_ppp_tab[{ppp_ptr, 5'd0} +: 32];
    wire [4:0]  ppp_op_w = ppp_w[4:0];
    wire [4:0]  ppp_nd_w = ppp_w[9:5];
    wire [6:0]  ppp_ds_w = ppp_w[16:10];
    wire        ppp_pl_w = ppp_w[18];
    wire        ppp_hit_w = (ppp_op_w != 5'h0) &&
                            (ppp_nd_w == conv_cnt);   // r10: both 5b now
    wire        rp_anchor_id = 1'b0;  // slot 28 uses direct CHW; no carry repack

    // 2e telemetry (SPEC §7.4): S||L overlap cycles = producer
    // scatter-close pending (polls outstanding) while a load stream runs.
    // Identically 0 through v1..2d (consumer never started before producer
    // sc_done); first non-zero under CHAIN_REL=1 is the mechanism proof
    // (T5).  Cleared at the doorbell (clear_on_frame law).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     s2l_cnt <= 32'd0;
        else if (start) s2l_cnt <= 32'd0;
        else if (polls_pend_r && (ld_w_busy || ld_x_busy))
            s2l_cnt <= s2l_cnt + 32'd1;
    end

    wire counter_wrap_adv = (st == S_ADV) &&
                            ((b_cnt == 12'hFFF) ||
                             (!ovl_r && (progress_blk == 16'hFFFF)) ||
                             (walk_r && (b_cnt == nb_c - 12'd1) &&
                              (nb_tot > (16'hFFFF - {4'd0, nb_c}))));
    wire counter_wrap_close = (st == S_W4) && ovl_r && sc_done &&
                              !sc_err && (progress_blk == 16'hFFFF);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; err <= 8'd0; progress_blk <= 16'd0;
            dbg_dual_transition <= 32'd0;
            dbg_last_face_close <= 32'd0;
            b_cnt <= 12'd0; rc_r <= 6'd0; rcmax_r <= 6'd0;
            rc_outer_r <= 1'b0; spatial_total_r <= 12'd0;
            nt_r <= 10'd0; oy_r <= 10'd0; s_r <= 4'd0; ns_r <= 4'd0;
            r_cur <= 4'd0; lut_i <= 8'd0; vc_r <= 5'd0; nmask_r <= 16'd0;
            k_r <= 11'd0; jc_r <= 8'd0; g_r <= 2'd0;
            arm_nmask <= 16'd0;
            selected_write_bytes <= 16'd0;
            paged_mode <= 1'b0;
            conv_start <= 1'b0;
            face_close <= 1'b0;
            epoch_invalid <= 1'b0;
            stride_r <= 32'd0; obuf_r <= 32'd0;
            timeout <= 32'd0; seen_busy <= 1'b0;
            ovl_r <= 1'b0; fin_r <= 1'b0; vc_poll_r <= 5'd0;
            rel_r <= 1'b0;
            prod_conv <= 6'd0;
            polls_pend_r <= 1'b0; lut_pend_r <= 1'b0; lut_ret_q1_r <= 1'b0;
            cv_load_en <= 1'b0;
            ppp_err_r <= 8'd0; layout_err_r <= 8'd0;   // g3r8 registered sanity
            ppp_err_s1_r <= 8'd0; ppp_seen_empty_s1_r <= 1'b0;  // g3r9 s1
            ppp_node_last_s1_r <= 5'd0; ppp_plast_s1_r <= 1'b0;
            walk_r <= 1'b0; conv_cnt <= 5'd0; nconv_r <= 5'd1;
            nb_c <= 12'd0; nb_tot <= 16'd0; nseg_r <= 2'd0; seg_r <= 2'd0;
            swoff_r <= 12'd0; sk0ic_r <= 16'd0; sk0kh_r <= 3'd0;
            sk0kw_r <= 3'd0; seg_tab[0] <= 56'd0; seg_tab[1] <= 56'd0;
            seg_tab[2] <= 56'd0; pbase <= 12'd0; sbase <= 9'd0; lbase <= 13'd0;
            dual_entry_r <= 1'b0;
            ld_start <= 1'b0; sc_arm <= 1'b0; sc_up2x <= 1'b0;
            sc_chw <= 1'b0; sc_ch_stride <= 32'd0;
            rt_oy <= 10'd0; rt_s <= 4'd0; rt_rc <= 6'd0; rt_vc <= 5'd0;
            rt_k <= 11'd0; rt_segoff <= 32'd0;
            rt_koff_ic <= 16'd0; rt_koff_kh <= 4'd0; rt_koff_kw <= 4'd0;
            cv_addr <= 5'd0; conv_idx <= 5'd0;
            geo_ic <= 16'd0; geo_h <= 16'd0; geo_w <= 16'd0;
            geo_kh <= 4'd0; geo_kw <= 4'd0; geo_sh <= 4'd0; geo_sw <= 4'd0;
            geo_ph <= 4'd0; geo_pw <= 4'd0; geo_first <= 1'b0;
            geo_law_fetch <= 1'b0; geo_xbase <= 32'd0;
            geo_ch_stride <= 32'd0;
            wl_wbase <= 32'd0; wl_slab <= 32'd0; wl_rc_stride <= 32'd0;
            wl_oc_stride <= 32'd0; wl_oc <= 8'd0;
            pctl_addr <= 12'd0; strip_addr <= 9'd0; lut_addr <= 13'd0;
            axf_start <= 1'b0; axf_we <= 1'b0;
            axf_addr <= 8'd0; axf_wdata <= 32'd0;
            ppu_start <= 1'b0; ppu_start_payload <= 18'd0;
            ppp_ptr <= 3'd0; frame_gen_r <= 8'd0;
            // D2 判决锁存复位 (V3.2-D1D2)
            ppp_vld <= 1'b0; ppp_ab <= 1'b0; ppp_err <= 8'd0;
            // v2.4 page-scheduling state
            gconv <= 6'd0; page_r <= 3'd0;
            manual_paged_r <= 1'b0;
            schedule_page_r <= 3'd0;
            npages_r <= 4'd1;
            pgauto_r <= 1'b0;
            post_bind_state <= S_IDLE;
            arn_resume_state <= S_IDLE;
            arn_reset_epoch_q <= 1'b0;
            arriving_cv_valid_q <= 1'b0;
            arriving_cv_slot_q <= 7'd0;
            arriving_cv_tag_q <= 11'd0;
            arriving_tag_next_q <= 11'd0;
            bind_window_waited <= 1'b0;
            hbuf_started <= 1'b0;
            bind_ready <= 1'b0;
            execution_enable <= 1'b0;
            hbuf_start <= 1'b0;
            sppf_mode <= 1'b0;
            pg_adv <= 1'b0; pg_base <= 6'd0; pg_nconv <= 5'd0;
            pg_nedge <= 3'd0;
            pg_anchor <= 1'b0; pg_anchor_page <= 3'd0;
            rp_start_q <= 1'b0;
            rp_arm_q <= 1'b0;
            producer_arm_o <= 1'b0;
            cv1_epoch_active <= 1'b0;
            cv1_epoch_seal <= 1'b0;
            cv1_close_count <= 8'd0;
            sc_done_d <= 1'b0;
            rp_anchor_seen <= 1'b0;
            rp_anchor_consumed <= 1'b0;
            rp_armed_q <= 1'b0;
            pending_at_start_q <= 1'b0;
            producer_sealed_this_db <= 1'b0;
            rp_anchor_required_q <= 1'b0;
            owner_valid_q <= 1'b0;
            owner_pgauto_q <= 1'b0;
            owner_npages_q <= 4'd1;
            owner_ybase_q <= 32'd0;
            producer_src_base_q <= 32'd0;
            producer_oc_q <= 8'd0;
            producer_h_q <= 16'd0;
            producer_w_q <= 16'd0;
            producer_vc_q <= 5'd0;
            producer_rc_q <= 6'd0;
            producer_nb_q <= 12'd0;
        end else begin
            ld_start <= 1'b0;                       // pulse defaults
            sc_arm   <= 1'b0;
            axf_start<= 1'b0;
            ppu_start<= 1'b0;                       // v2.3 pulse default
            cv_load_en <= 1'b0;                     // g3r6 pulse default
            pg_adv  <= 1'b0;                        // v2.4 pulse defaults
            pg_anchor <= 1'b0;
            rp_start_q <= 1'b0;
            rp_arm_q <= 1'b0;
            producer_arm_o <= 1'b0;
            conv_start <= 1'b0;
            face_close <= 1'b0;
            hbuf_start <= 1'b0;
            sc_done_d <= sc_done;
            ppp_err_s1_r      <= ppp_err_s1_c;      // g3r9 knife B stage-1
            ppp_seen_empty_s1_r <= ppp_seen_empty_s1_c;   // free-running
            ppp_node_last_s1_r <= ppp_node_last_s1_c;     // sample
            ppp_plast_s1_r    <= ppp_plast_s1_c;
            ppp_err_r    <= ppp_err_c;              // stage-2 (words 4..7)
            layout_err_r <= layout_err_c;           // sample (table stable
                                                    // well before doorbell)
            // ---- D2 判决单拍捕获 (设计件 §3): 无条件, 与 timeout 计数
            //      同级常驻采样, 不靠 FSM case 门 -- 1-cycle ppu_done 任意
            //      到达拍必被捕获. 清除写在本块之后 (帧首/S_PPPF), 同拍
            //      到达的旧帧尾判决被清除覆盖丢弃 (最后赋值赢律) ----
            if (ppu_done) begin
                ppp_vld <= 1'b1;
                ppp_ab  <= ppu_done_abort;
                ppp_err <= ppu_done_err;
            end
            if (start) begin
                frame_gen_r <= frame_gen;
                ppp_ptr     <= 3'd0;
                ppp_vld     <= 1'b0;
                bind_ready  <= 1'b0;
                execution_enable <= 1'b0;
                bind_window_waited <= 1'b0;
                hbuf_started <= 1'b0;
                npages_r <= npages_i;
                pgauto_r <= pgauto_i;
                dual_entry_r <= 1'b0;
                arn_reset_epoch_q <= 1'b1;
                arriving_cv_valid_q <= 1'b0;
                sppf_mode   <= sppf_pending_legal ||
                               (pgauto_i && (cfg_nconv > 5'd1));
                paged_mode  <= (cfg_nconv > 5'd1) &&
                               ((npages_i > 4'd1) || manual_paged_w);
                pending_at_start_q <= sppf_pending_legal;
                producer_sealed_this_db <= 1'b0;
                rp_anchor_required_q <= sppf_pending_legal;
                rp_anchor_seen <= 1'b0;
                rp_anchor_consumed <= 1'b0;
                if (manual_epoch_start_bad || sppf_start_bad ||
                    axi_epoch_invalid_i || dense_addr_err_i) begin
                    epoch_invalid <= 1'b1;
                end
            end

            if (ppu_done_abort || rp_explicit_fault || sc_err ||
                dense_addr_err_i || axi_epoch_invalid_i ||
                accepted_mode_change) begin
                arriving_cv_valid_q <= 1'b0;
            end

            if (1'b0 && sc_arm && paged_w && (slot_w == 7'd28) &&
                (b_cnt == 12'd0)) begin
                if (!sppf_pending_present) begin
                    producer_arm_o <= 1'b1;
                    cv1_epoch_active <= 1'b1;
                    cv1_epoch_seal <= 1'b0;
                    cv1_close_count <= 8'd0;
                    owner_valid_q <= 1'b1;
                    owner_pgauto_q <= pgauto_r;
                    owner_npages_q <= npages_r;
                    owner_ybase_q <= cfg_ybase;
                    producer_src_base_q <= obuf_r;
                    producer_oc_q <= wl_oc;
                    producer_h_q <= geo_h;
                    producer_w_q <= geo_w;
                    producer_vc_q <= strip_data[20:16];
                    producer_rc_q <= rcmax_r;
                    producer_nb_q <= nb_c;
                end else if (err == 8'd0) begin
                    err <= E_RP_BUSY;
                    st <= S_HALT;
                end
            end

            if (cv1_epoch_active && scatter_verified_close && !sc_arm) begin
                if (cv1_close_count < 8'd159) begin
                    cv1_close_count <= cv1_close_count + 8'd1;
                end else if (cv1_close_count == 8'd159) begin
                    cv1_close_count <= 8'd160;
                    cv1_epoch_seal <= 1'b1;
                    producer_sealed_this_db <= 1'b1;
                    rp_anchor_required_q <= pgauto_r;
                end else if (err == 8'd0) begin
                    err <= E_RP_BUSY;
                    st <= S_HALT;
                end
            end

            if (rp_explicit_fault || rp_pf_hang_i) begin
                rp_armed_q <= 1'b0;
            end else if ((st == S_RP_WAIT) && rp_start_q) begin
                rp_armed_q <= 1'b0;
            end else if (arm_accept_shadow) begin
                rp_armed_q <= 1'b1;
            end

            if (st != S_IDLE && st != S_HALT && st != S_DONE)
                timeout <= timeout + 32'd1;
            else
                timeout <= 32'd0;
            if ((timeout >= tmo_max_w) && !rp_state_w && (err == 8'd0)) begin
                err <= 8'd7; st <= S_HALT;
            end
            // D2 看门狗边沿刷新修正案 (设计件 §4, V3.2-D1D2):
            // 仅捕获拍 (ppp_vld 旧值=0) 刷新一次, 取代 S_PPPW 电平刷新;
            // stuck-high pdone 不再饿死看门狗, "判决已到而 repack 挂死"
            // 类恢复 err=7 兜底覆盖. 位置在 timeout 检查之后 (case 前),
            // 与原版 S_PPPW 内刷新的优先级相同 (case 内无其它刷新) --
            if (ppu_done && !ppp_vld) timeout <= 32'd0;

            // C5: every active state consumes RP faults on every cycle.
            // This later assignment outranks the watchdog above; an older
            // error remains sticky (first-error-wins).
            if (rp_explicit_fault && (st != S_IDLE) &&
                (st != S_DONE) && (st != S_HALT)) begin
                if (err == 8'd0) begin
                    err <= rp_explicit_code;
                end
                st <= S_HALT;
            end else if (rp_pf_hang_i && rp_state_w) begin
                // Missing RLAST is a hang contract, not an explicit RP fault.
                // Keep all four RP states live until their own watchdog; the
                // combinational gates above suppress both arm and start.
                if (timeout >= tmo_max_w) begin
                    if (err == 8'd0) begin
                        err <= 8'd7;
                    end
                    st <= S_HALT;
                end
            end else if ((sc_err || dense_addr_err_i || axi_epoch_invalid_i ||
                          accepted_mode_change ||
                          (bind_err_i && hbuf_started)) &&
                         (st != S_IDLE) && (st != S_DONE) && (st != S_HALT)) begin
                if (err == 8'd0) begin
                    err <= sc_err ? 8'd5 : E_BIND;
                end
                if (dense_addr_err_i || axi_epoch_invalid_i ||
                    accepted_mode_change || bind_err_i) begin
                    epoch_invalid <= 1'b1;
                end
                st <= S_HALT;
            end else if (counter_wrap_adv || counter_wrap_close) begin
                if (err == 8'd0) begin
                    err <= E_COUNTER_WRAP;
                end
                st <= S_HALT;
            end else begin
            case (st)
            S_IDLE: if (start && err == 8'd0) begin
                // ---- v2.3 doorbell-edge sanity (DESIGN §3.3): refuse the
                // frame BEFORE any walk begins if the PPP table or layout
                // vector is malformed.  First-error-wins: PPP table errors
                // outrank layout errors (both are PS load bugs; ordering
                // only fixes the reported code). ----
                if (manual_epoch_start_bad || sppf_start_bad ||
                    axi_epoch_invalid_i || dense_addr_err_i) begin
                    err <= E_BIND;
                end else if ((cfg_nconv > 5'd1) &&
                             ((npages_i > 4'd1) || manual_paged_w) &&
                             cfg_overlap) begin
                    err <= E_LAYOUT_MISMATCH;
                end else if (ppp_err_r != 8'd0) begin
                    err <= ppp_err_r;
                end else if (layout_err_r != 8'd0) begin
                    err <= layout_err_r;
                end else if (cfg_nconv > 5'd1) begin
                    // Auto retains the original multi-page walk.  Manual
                    // accepts exactly one checked page and closes at its end.
                    walk_r  <= 1'b1;
                    manual_paged_r <= manual_paged_w;
                    nconv_r <= ((npages_i > 4'd1) || manual_paged_w) ?
                               pg_nconv_w : cfg_nconv;
                    conv_cnt<= 5'd0;
                    gconv   <= cfg_gconv_base;
                    page_r  <= 3'd0;
                    schedule_page_r <= cfg_schedule_page;
                    pg_base <= cfg_gconv_base;
                    nb_tot  <= 16'd0;
                    b_cnt <= 12'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                    s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                    ovl_r <= cfg_overlap; fin_r <= 1'b0;
                    rel_r <= chain_rel;
                    prod_conv <= cfg_gconv_base;
                    polls_pend_r <= 1'b0;
                    lut_pend_r <= 1'b0; lut_ret_q1_r <= 1'b0;
                    cv_addr <= cfg_gconv_base;
                    post_bind_state <= S_PPPG;
                    st <= S_BIND_WAIT;
                end else if (cfg_nseg != 2'd1) begin
                    err <= 8'd6;                    // legacy single-seg guard
                end else begin
                    // ---- legacy path (byte-stable, modes 0/1) ----
                    walk_r <= 1'b0; nconv_r <= 5'd1; conv_cnt <= 5'd0;
                    manual_paged_r <= 1'b0;
                    gconv <= cfg_gconv_base;
                    page_r <= 3'd0;
                    schedule_page_r <= 3'd0;
                    rel_r <= chain_rel;
                    prod_conv <= cfg_gconv_base;
                    nb_tot <= 16'd0; nseg_r <= 2'd1; seg_r <= 2'd0;
                    swoff_r <= 12'd0;
                    sk0ic_r <= 16'd0; sk0kh_r <= 3'd0; sk0kw_r <= 3'd0;
                    pbase <= 12'd0; sbase <= 9'd0; lbase <= 13'd0;
                    cv_addr <= 5'd0;
                    rcmax_r <= (cfg_rc == 6'd0) ? 6'd1 : cfg_rc;
                    rc_outer_r <= 1'b0; spatial_total_r <= 12'd0;
                    ns_r    <= (cfg_ns == 4'd0) ? 4'd1 : cfg_ns;
                    k_r     <= cfg_s0_k; jc_r <= cfg_s0_jc; g_r <= cfg_s0_g;
                    stride_r<= cfg_stride; obuf_r <= cfg_ybase + cfg_obuf;
                    ovl_r   <= cfg_overlap; fin_r <= 1'b0;
                    b_cnt <= 12'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                    s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                    // feeder cfg shadow = port passthrough (single source)
                    geo_ic <= cfg_ic; geo_h <= cfg_h; geo_w <= cfg_w;
                    geo_kh <= cfg_kh; geo_kw <= cfg_kw;
                    geo_sh <= cfg_sh; geo_sw <= cfg_sw;
                    geo_ph <= cfg_ph; geo_pw <= cfg_pw;
                    geo_first <= cfg_first; geo_law_fetch <= cfg_law_fetch;
                    geo_xbase <= cfg_xbase;
                    geo_ch_stride <= 32'd0;   // legacy: h*w fallback
                    wl_wbase <= cfg_wbase; wl_slab <= cfg_slab;
                    wl_rc_stride <= cfg_rc_stride;
                    wl_oc_stride <= cfg_oc_stride; wl_oc <= cfg_oc;
                    lut_addr <= 13'd0;
                    post_bind_state <= S_LUTRD;
                    st <= S_BIND_WAIT;
                end
            end
            S_BIND_WAIT: begin
                // Configuration is latched, but no ROM/PPP/RP/AXI/load/scatter
                // transaction is legal until the atomic HBUF bind completes.
                // A page change clears win_rdy one cycle after acceptance;
                // bind_window_waited prevents the stale ready level from
                // launching the builder with the previous page's banks.
                if ((hbuf_started && bind_err_i) || epoch_invalid ||
                    axi_epoch_invalid_i || dense_addr_err_i ||
                    manual_bind_range_bad) begin
                    err <= E_BIND;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else if (!hbuf_started) begin
                    bind_window_waited <= 1'b1;
                    if (bind_window_waited && pg_win_rdy_i) begin
                        hbuf_start <= 1'b1;
                        hbuf_started <= 1'b1;
                        nconv_r <= hbuf_nconv;
                    end
                end else if (bind_done_i) begin
                    bind_ready <= 1'b1;
                    execution_enable <= 1'b1;
                    if (paged_mode) begin
                        arn_resume_state <= post_bind_state;
                        st <= S_ARN0;
                    end else begin
                        st <= post_bind_state;
                    end
                end
            end
            S_ARN0: begin
                arriving_cv_valid_q <= 1'b0;
                cv_addr <= gconv;
                arriving_tag_next_q <= arriving_context_now;
                if (arn_err_i) begin
                    err <= E_ARN;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else begin
                    st <= S_ARN1;
                end
            end
            S_ARN1: begin
                // The ROM samples the arriving address at this edge.  HBUF
                // backpressure can delay ACK, but no early data capture is
                // permitted; the global watchdog bounds an ACK hang.
                if (arn_err_i) begin
                    err <= E_ARN;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else if (arn_ack_i) begin
                    st <= S_ARN2;
                end
            end
            S_ARN2: begin
                if (arn_err_i) begin
                    err <= E_ARN;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else if (!arn_sealed_ok) begin
                    err <= E_ARN_NOT_SEALED;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else begin
                    arriving_cv_slot_q <= cv_slot_g;
                    arriving_cv_tag_q <= arriving_tag_next_q;
                    arriving_cv_valid_q <= 1'b1;
                    st <= arn_resume_state;
                end
            end
            // ================= v2.3 PPP gate (DESIGN §3) ==================
            // Entered at frame start (conv 0) and at every conv boundary
            // (conv_cnt already advanced = the ARRIVING conv).  Gate,
            // fire, wait; falls through to S_CVRD untouched when no PPP
            // word matches -- empty table = v1 structural identity.
            S_PPPG: begin
                if (paged_w && !arriving_row_qual) begin
                    err <= E_CVROW_TAG;
                    epoch_invalid <= 1'b1;
                    st <= S_HALT;
                end else if (ppp_hit_w && !ppu_write_fence_g) begin
                    st <= S_PPPG;  // wait until all producer CHW writes are in DDR
                end else if (rp_anchor_id && rp_anchor_required_q) begin
                    if (rp_err_lvl) begin
                        err <= (rp_err_code_m == 8'd0) ? E_RP_BUSY :
                                                        rp_err_code_m;
                        st <= S_HALT;
                    end else if (ovl_r) begin
                        err <= E_LAYOUT_MISMATCH;
                        st <= S_HALT;
                    end else if (rp_anchor_seen) begin
                        err <= E_RP_BUSY;
                        st <= S_HALT;
                    end else if (rp_pf_explicit) begin
                        err <= E_RP_UNSEALED;
                        st <= S_HALT;
                    end else begin
                        rp_anchor_seen <= 1'b1;
                        st <= S_RP_ARM;
                    end
                end else begin
                    if (rp_anchor_id) begin
                        rp_anchor_seen <= 1'b1;
                    end
                    st <= ppp_hit_w ? S_PPPF : S_CVRD;
                end
            end
            S_PPPF: begin
                // fire: 1-cycle ppu_start; payload = {gen, seg, desc}
                // (trigger/payload separation -- §2.3 arithmetic: full
                // fields cannot inline in one word, geometry lives in the
                // PPU DESC slots this desc_idx selects).
                ppu_start        <= 1'b1;
                ppu_start_payload<= {frame_gen_r, ppp_ptr, ppp_ds_w};
                ppp_vld          <= 1'b0;           // D2: S_PPPF 点火拍
                                                    // 清除, 新 walker 等待窗
                // R160: only S_RP_START owns the paged repack start.
                st <= S_PPPW;
            end
            S_PPPW: begin
                // wait: walker arbiter verdict -- D2 (设计件 §3): 判据改
                // 锁存 if(ppp_vld), 取代电平 if(ppu_done); 判决单拍已被
                // 无条件捕获, stuck-high pdone 不再影响判据 (凌驾律).
                // Watchdog (err=7) covers a hung walker (timeout runs in
                // all non-IDLE states; 刷新 = 捕获边沿, 见主块修正案).
                // v2.4: paged 帧 repack 等待嵌入此态 (rp_done_i float=1 =
                // 无等待, legacy/截断期字节稳定); D1 (R155): rp_err 粘着
                // 级 fail-fast 主面 -- rp_err 时 rp_done 永 0, 不 fail-
                // fast 则引入新型挂死 (run03 型). 内分支序保持原序:
                // abort->halt; paged 空转; else 推进.
                if (ppp_vld) begin
                    if (ppp_ab) begin
                        err <= ppp_err;             // E_GEN_MISMATCH etc.
                        st <= S_HALT;
                    end else if (paged_w && rp_err_lvl) begin
                        err <= rp_err_code_m;       // D1 fail-fast (映射码)
                        st <= S_HALT;
                    end else begin
                        if (rp_anchor_seen && !rp_anchor_consumed) begin
                            rp_anchor_consumed <= 1'b1;
                            cv1_epoch_active <= 1'b0;
                            cv1_epoch_seal <= 1'b0;
                            cv1_close_count <= 8'd0;
                            owner_valid_q <= 1'b0;
                            producer_src_base_q <= 32'd0;
                            producer_oc_q <= 8'd0;
                            producer_h_q <= 16'd0;
                            producer_w_q <= 16'd0;
                            producer_vc_q <= 5'd0;
                            producer_rc_q <= 6'd0;
                            producer_nb_q <= 12'd0;
                        end
                        ppp_ptr <= ppp_ptr + 3'd1;  // same-node chain word
                        st <= S_PPPG;               // re-gate (SPPF chain)
                    end
                end
            end
            S_RP_ARM: begin
                if (rp_explicit_fault) begin
                    err <= rp_explicit_code;
                    st <= S_HALT;
                end else if (!cv1_epoch_seal ||
                             (cv1_close_count != 8'd160)) begin
                    err <= E_RP_UNSEALED;
                    st <= S_HALT;
                end else if (rp_busy_i) begin
                    err <= E_RP_BUSY;
                    st <= S_HALT;
                end else if (timeout >= tmo_max_w) begin
                    err <= 8'd7;
                    st <= S_HALT;
                end else if (!producer_commit_g) begin
                    st <= S_RP_ARM;
                end else begin
                    rp_arm_q <= 1'b1;
                    st <= S_RP_WARM;
                end
            end
            S_RP_WARM: begin
                // R164 first-error-wins: an already-latched issuer error is
                // terminal and must not be overwritten by a later native
                // arm-refusal code.  The native arm pulse has already been
                // emitted, so its own sticky error remains observable.
                if (err != 8'd0) begin
                    st <= S_HALT;
                end else if (rp_explicit_fault) begin
                    err <= rp_explicit_code;
                    st <= S_HALT;
                end else if (!(rp_armed_q || arm_accept_shadow) ||
                             !cv1_epoch_seal ||
                             (cv1_close_count != 8'd160)) begin
                    err <= (rp_armed_q || arm_accept_shadow) ?
                           E_RP_UNSEALED : E_RP_NOT_ARMED;
                    st <= S_HALT;
                end else if (timeout >= tmo_max_w) begin
                    err <= 8'd7;
                    st <= S_HALT;
                end else if (rp_warm_i) begin
                    st <= S_RP_START;
                end
            end
            S_RP_START: begin
                if (rp_explicit_fault) begin
                    err <= rp_explicit_code;
                    st <= S_HALT;
                end else if (!rp_armed_q) begin
                    err <= E_RP_NOT_ARMED;
                    st <= S_HALT;
                end else if (!rp_warm_i || !cv1_epoch_seal ||
                             (cv1_close_count != 8'd160)) begin
                    err <= E_RP_UNSEALED;
                    st <= S_HALT;
                end else if (rp_busy_i) begin
                    err <= E_RP_BUSY;
                    st <= S_HALT;
                end else if (timeout >= tmo_max_w) begin
                    err <= 8'd7;
                    st <= S_HALT;
                end else if (!producer_commit_g) begin
                    st <= S_RP_START;
                end else begin
                    rp_start_q <= 1'b1;
                    st <= S_RP_WAIT;
                end
            end
            S_RP_WAIT: begin
                if (rp_explicit_fault) begin
                    err <= rp_explicit_code;
                    st <= S_HALT;
                end else if (rp_done_g && (rp_bytes_i != 24'd12800)) begin
                    err <= E_RP_UNSEALED;
                    st <= S_HALT;
                end else if (timeout >= tmo_max_w) begin
                    err <= 8'd7;
                    st <= S_HALT;
                end else if (rp_done_g && (rp_bytes_i == 24'd12800)) begin
                    st <= S_RP_COMMIT;
                end
            end
            S_RP_COMMIT: begin
                if (rp_explicit_fault) begin
                    err <= rp_explicit_code;
                    st <= S_HALT;
                end else if (timeout >= tmo_max_w) begin
                    err <= 8'd7;
                    st <= S_HALT;
                end else if (repack_commit_g) begin
                    st <= S_PPPF;
                end
            end
            // ================= M9.4 conv-table read (walk) =================            // entered at frame start (conv 0) and at every conv boundary;
            // LUT reload + full shadow switch is UNCONDITIONAL per conv
            // (pl_m3 per-conv load_lut canon -- switch window goes to the
            // ledger, not a dedup optimization).
            S_CVRD: begin
                arriving_cv_valid_q <= 1'b0;
                cv_addr <= paged_w ? arriving_cv_slot_q : {1'b0, gconv};
                conv_idx<= gconv;                 // global graph identity
                // 2e-fix: SEQ walk reaches here only after the previous
                // conv's last verified close -> conv_cnt is drain-safe.
                // walk+ovl reaches here EARLY (last block's fire) -> hold
                // prod_conv until the verified boundary close (S_W4).
                if (!ovl_r) prod_conv <= gconv;
                st <= S_CVD2;
            end
            S_CVD2: begin
                st <= S_CVLH;                       // ROM data cycle C+2
                cv_load_en <= 1'b1;                 // g3r6: fires the shadow
            end                                     // load group next cycle
            S_CVLH: begin
                // g3r6 timing cut: the wide UNCONDITIONAL shadow-load
                // group moved to the registered cv_load_en strobe at the
                // bottom of this always block -- same cycle (en fires
                // exactly during S_CVLH), same values, still firing even
                // on the err/HALT sub-branches below (the originals were
                // above the branch conditions, law preserved).  Only the
                // conditional work stays here.
                // v2.3 layout combo check (DESIGN §4.3): a tile-declared
                // conv (layout bit1) MUST carry an explicit slot stride --
                // stride 0 would silently read the h*w plane law into
                // slot steps (wrong-data class) = the refused combo.
                // Doorbell sanity already bounds layout!=0 to nconv<=10
                // legacy; paged pages carry up to 16 page-local convs
                // (48b vector), so the index guard widens to 16 paged.
                if ((conv_cnt < (paged_w ? 5'd16 : 5'd10)) &&
                    (cfg_layout_id[conv_cnt*3 +: 3] == 3'b010) &&
                    (cv_wlay[167:136] == 32'd0)) begin
                    err <= E_LAYOUT_MISMATCH;
                    st <= S_HALT;
                end else begin
                // v2.4: plan bases are SLOT-based paged (D4 slot-doubling
                // face, 69 slots) and conv-based legacy (r10 slot==conv,
                // byte-identical values).  Widths: pbase 14b / sbase 11b /
                // lbase 15b (frozen wrappers truncate, r10 precedent).
                pbase <= {slot_w, 7'd0};           // slot x 128 rows
                sbase <= {1'b0, slot_w, 4'd0};     // slot x 16 rows
                lbase <= {slot_w, 8'd0};           // slot x 256 rows
                if (cv_iss[23:22] == 2'd0) begin
                    err <= 8'd6;                  // nseg must be 1..3
                    st <= S_HALT;
                end else if (walk_r && ovl_r) begin
                    // walk+ovl (V2.1): per-conv nseg must be 1 -- the
                    // multi-seg chain group-reuse queue law is not
                    // composed with overlap (err=9, re-scoped)
                    if (cv_iss[23:22] != 2'd1) begin
                        err <= 8'd9; st <= S_HALT;
                    end else begin
                        // defer the LUT reload into the first block's
                        // stream window (S_OAD nests it post-polls)
                        lut_pend_r <= 1'b1;
                        st <= S_PREP;
                    end
                end else
                    st <= S_LUTRD;                // per-conv LUT reload
                end
            end

            // ================= LUT prologue =================
            S_LUTRD: begin
                lut_addr <= lbase + {3'd0, lut_i}; // ROM: addr cycle C,
                st <= S_LUTD2;                     // data cycle C+2
            end
            S_LUTD2: st <= S_LUTWR;
            S_LUTWR:
                if (axf_done) begin
                    if (lut_i == 8'd255) st <= S_LUTEC;
                    else begin
                        lut_i <= lut_i + 8'd1;
                        st <= S_LUTRD;
                    end
                end else if (!axf_busy) begin
                    axf_addr <= A_LUTD; axf_we <= 1'b1;
                    axf_wdata <= {16'd0, lut_i, lut_data};
                    axf_start <= 1'b1;
                end
            S_LUTEC:
                if (axf_done) begin
                    timeout <= 32'd0;              // fresh per-frame window
                    // walk+ovl nested reload returns into the first
                    // block's Q1; the prologue-position reload (legacy /
                    // SEQ walk) falls through to S_PREP as before
                    st <= lut_ret_q1_r ? S_Q1RD : S_PREP;
                    lut_ret_q1_r <= 1'b0;
                end else if (!axf_busy) begin
                    axf_addr <= A_CTRL; axf_we <= 1'b1;
                    axf_wdata <= 32'd4;             // err_clr (load_lut canon)
                    axf_start <= 1'b1;
                end

            // ================= per-block =================
            S_PREP: begin
                if (b_cnt == 12'd0) begin
                    conv_start <= 1'b1;
                end
                if ((b_cnt == 12'd0) && paged_w &&
                    dense_face_geometry_err) begin
                    err <= E_LAYOUT_MISMATCH;
                    st <= S_HALT;
                end else begin
                strip_addr <= sbase + {3'd0, s_r};  // ROM: addr cycle C,
                if (walk_r) begin
                    // block start: reset to segment 0 (per-block latch --
                    // S_PREP runs exactly once per block, from S_ADV or
                    // the conv LUT epilogue)
                    seg_r   <= 2'd0;
                    k_r     <= seg0_w[10:0];
                    jc_r    <= seg0_w[18:11];
                    g_r     <= seg0_w[20:19];
                    swoff_r <= seg0_w[32:21];
                    sk0ic_r <= seg0_w[48:33];
                    sk0kh_r <= seg0_w[51:49];
                    sk0kw_r <= seg0_w[54:52];
                end
                st <= S_PREP2;                      // data cycle C+2
                end
            end
            S_PREP2: begin
                arm_nmask <= strip_data[15:0];
                st <= S_ARM;
            end
            S_ARM: begin
                vc_poll_r <= vc_r;          // ovl: iter b polls block b-1
                nmask_r <= strip_data[15:0];
                vc_r    <= strip_data[20:16];
                // y slot = obuf + stride*b (b CONV-LOCAL: pl_m3/golden
                // law -- each conv's arm_and_run restarts its own slot
                // walk at obuf+0; global nb_tot indexing put conv1+ at
                // +prevNB slots, M9.4 run02 arena evidence)
                if (chw_mode_w)
                    sc_base <= chw_block_base;
                else
                    sc_base <= obuf_r + stride_r * {20'd0, b_cnt};
                sc_vc   <= strip_data[20:16];
                sc_up2x <= arm_up2x_w;
                sc_chw  <= chw_mode_w;
                sc_ch_stride <= chw_plane_stride;
                selected_write_bytes <= selected_arm_w;
                // r10 guard: cfg_up2x is a 16-conv bitmap; conv 16+ would be
                // an out-of-range select (x in sim, index-alias in synth) --
                // 0 = no 2x until the ABI widens the CSR (driver ruling).
                if (arm_contract_err) begin
                    if (gconv < 6'd21)
                        dbg_dual_transition <= {1'b0, gconv, slot_w, nb_c, rcmax_r};
                    dbg_last_face_close <= {2'd0, gconv, nb_c, b_cnt};
                    err <= E_LAYOUT_MISMATCH;
                    st <= S_HALT;
                end else begin
                    if (!ovl_r)
                        sc_arm  <= 1'b1;         // ovl arms post-polls (S_OAD)
                    r_cur   <= 4'd0;
                    st <= ovl_r ? S_OCR : S_Q1RD;
                end
            end
            S_OCR:                               // credit: target grp ok?
                if (axf_done) begin
                    // LDSTAT {1:0 w_ld_ok, 3:2 x_ld_ok}; p = b_cnt[0]
                    if (axf_rdata[{2'd1, b_cnt[0]}] &&
                        axf_rdata[{2'd0, b_cnt[0]}])
                        st <= S_G2;
                    else if (walk_r)
                        ;   // walk+ovl odd-NB boundary: target group is
                            // read-selected; re-poll (below) until the
                            // reader drains -- ld_ok rises at rd_busy=0.
                            // Zero-overlap fallback, group flow control
                            // keeps the TDP law structurally.  Legacy
                            // ovl keeps the hard err=8 below.
                    else begin
                        err <= 8'd8; st <= S_HALT;
                    end
                end else if (!axf_busy) begin
                    axf_addr <= A_LDSTAT; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            S_Q1RD: begin
                // pctl ROM index = conv*128 + rc*8 + r (concat would give
                // rc*16+r); legacy pbase==0
                pctl_addr <= pbase + {2'd0, rc_r, 3'b000} + {7'd0, r_cur};
                st <= S_Q1D2;
            end
            S_Q1D2: st <= S_Q1W1;
            S_Q1W1:                                 // P_BIAS
                if (axf_done) st <= S_Q1W2;
                else if (!axf_busy) begin
                    axf_addr <= A_PBIAS; axf_we <= 1'b1;
                    axf_wdata <= pctl_data[31:0];
                    axf_start <= 1'b1;
                end
            S_Q1W2:                                 // P_M
                if (axf_done) st <= S_Q1W3;
                else if (!axf_busy) begin
                    axf_addr <= A_PM; axf_we <= 1'b1;
                    axf_wdata <= pctl_data[63:32];
                    axf_start <= 1'b1;
                end
            S_Q1W3:                                 // P_SH
                if (axf_done) st <= S_Q1W4;
                else if (!axf_busy) begin
                    axf_addr <= A_PSH; axf_we <= 1'b1;
                    axf_wdata <= {24'd0, pctl_data[71:64]};
                    axf_start <= 1'b1;
                end
            S_Q1W4:                                 // PCTL strobe
                if (axf_done) begin
                    if (r_cur == 4'd7) st <= S_Q2;
                    else begin r_cur <= r_cur + 4'd1; st <= S_Q1RD; end
                end else if (!axf_busy) begin
                    axf_addr <= A_PCTL; axf_we <= 1'b1;
                    axf_wdata <= 32'h00000100 | {28'd0, r_cur}; //{we,p_row}
                    axf_start <= 1'b1;
                end
            S_Q2:                                   // ROWVAL=0xFF
                if (axf_done) st <= S_G1;
                else if (!axf_busy) begin
                    axf_addr <= A_ROWVAL; axf_we <= 1'b1;
                    axf_wdata <= 32'h000000FF;
                    axf_start <= 1'b1;
                end
            S_G1:                                   // NMASK
                if (axf_done) st <= ovl_r ? S_L1W : S_G2;
                else if (!axf_busy) begin
                    axf_addr <= A_NMASK; axf_we <= 1'b1;
                    axf_wdata <= {16'd0, nmask_r};
                    axf_start <= 1'b1;
                end
            S_G2:                                   // LDGRP
                if (axf_done) st <= rt_noload ? S_G3A : S_L1;
                else if (!axf_busy) begin
                    axf_addr <= A_LDGRP; axf_we <= 1'b1;
                    axf_wdata <= {30'd0, g_cur};
                    axf_start <= 1'b1;
                end
            S_L1: begin                             // launch the stream
                ld_start <= 1'b1;
                rt_oy <= oy_r; rt_s <= s_r; rt_rc <= rc_r; rt_vc <= vc_r;
                rt_k <= k_r; rt_segoff <= {20'd0, swoff_r};
                // M9.4 k-seed face (legacy seeds are zero = V1.0 law)
                rt_koff_ic <= sk0ic_r;
                rt_koff_kh <= {1'b0, sk0kh_r};
                rt_koff_kw <= {1'b0, sk0kw_r};
                seen_busy <= 1'b0;
                // ovl: polls(b-1) + Q1(b) ride inside the stream window
                // (stream span >> poll+Q1 ~350 cyc at 17.3 cyc/beat).
                // walk+ovl: a conv boundary block is b_cnt==0 but still
                // carries the previous conv's pending polls -- the
                // polls_pend bit (not the block index) picks the head.
                if (ovl_r)
                    st <= (b_cnt == 12'd0 && !polls_pend_r)
                         ? S_OAD : S_W;
                else
                    st <= S_L1W;
            end
            S_L1W: begin                            // wait only channels used here
                if (ld_wait_busy) seen_busy <= 1'b1;
                if (seen_busy && !ld_wait_busy)
                    st <= S_L1C;
            end
            S_L1C:                                  // LDLEN closure read
                if (axf_done) begin
                    // k_r is 11-bit: zero-extend, never part-select [12:0]
                    // (out-of-range bits read as X and poison the compare)
                    if (rt_w_only ?
                        ((ldlen_w == {2'd0, k_r}) && (ldlen_x == 13'd0)) :
                        (((rt_w_reuse && (ldlen_w == 13'd0)) ||
                          (!rt_w_reuse && (ldlen_w == {2'd0, k_r}))) &&
                         (ldlen_x == {2'd0, k_r})))
                        // walk seg1: CTRL start1 precedes GEOM/JOBCFG
                        // (golden order LDGRP,CTRL,GEOM,JOBCFG,CTRL)
                        st <= (walk_r && seg_r == 2'd1) ? S_CST : S_G3A;
                    else begin
                        err <= 8'd1; st <= S_HALT;
                    end
                end else if (!axf_busy) begin
                    axf_addr <= A_LDLEN; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            S_G3A:                                  // GEOM=k_len
                if (axf_done) st <= S_G3B;
                else if (!axf_busy) begin
                    axf_addr <= A_GEOM; axf_we <= 1'b1;
                    axf_wdata <= {21'd0, k_r};
                    axf_start <= 1'b1;
                end
            S_G3B:                                  // JOBCFG
                // walk chain seg0 arms job(seg0) but does NOT fire it --
                // the engine latches GEOM/JOBCFG at CTRL commit, and a
                // chain seg0 must stay unfired until seg1's start1
                if (axf_done)
                    st <= (walk_r && seg_r == 2'd0 && nseg_r > 2'd1)
                         ? S_SEG : S_G3C;
                else if (!axf_busy) begin
                    axf_addr <= A_JOBCFG; axf_we <= 1'b1;
                    axf_wdata <= {24'd0, jc_cur};
                    axf_start <= 1'b1;
                end
            S_G3C:                                  // CTRL=1 fire/queue
                if (axf_done) begin
                    if (ovl_r) polls_pend_r <= 1'b1;   // fired, polls due
                    st <= ovl_r ? S_ADV :
                         (walk_r && nseg_r > 2'd1 &&
                          seg_r != nseg_r - 2'd1) ? S_PSQ : S_W;
                end else if (!axf_busy) begin
                    axf_addr <= A_CTRL; axf_we <= 1'b1;
                    axf_wdata <= 32'd1;
                    axf_start <= 1'b1;
                end

            // ================= M9.4 chain segment states (walk) ==========
            S_SEG: begin
                // segment advance: latch the next segment's regs
                seg_r   <= seg_r + 2'd1;
                k_r     <= segn_w[10:0];
                jc_r    <= segn_w[18:11];
                g_r     <= segn_w[20:19];
                swoff_r <= segn_w[32:21];
                sk0ic_r <= segn_w[48:33];
                sk0kh_r <= segn_w[51:49];
                sk0kw_r <= segn_w[54:52];
                st <= S_G2;
            end
            S_CST:                                  // CTRL start1 (seg1)
                if (axf_done) st <= S_PST;
                else if (!axf_busy) begin
                    axf_addr <= A_CTRL; axf_we <= 1'b1;
                    axf_wdata <= 32'd1;
                    axf_start <= 1'b1;
                end
            S_PST: begin
                // wait job(seg0) dequeued (STATUS.pend clear) before the
                // queue CTRL -- CTRL while job_pend is an engine error
                if (axf_done) begin
                    if (axf_rdata[9:6] != 4'd0) begin
                        err <= 8'd2; st <= S_HALT;
                    end else if (!axf_rdata[1])
                        st <= S_G3A;
                    // else: stay and re-issue the poll read
                end else if (!axf_busy) begin
                    axf_addr <= A_STATUS; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            end
            S_PSQ: begin
                // post-queue pend wait: queued job dequeued ==> previous
                // job finished ==> its read group is free (group-reuse
                // law for K2304 0->3->0: seg2 may stream into g0 only
                // after job(seg0) -- a g0 reader -- is done)
                if (axf_done) begin
                    if (axf_rdata[9:6] != 4'd0) begin
                        err <= 8'd2; st <= S_HALT;
                    end else if (!axf_rdata[1])
                        st <= S_SEG;
                    // else: stay and re-issue the poll read
                end else if (!axf_busy) begin
                    axf_addr <= A_STATUS; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            end
            S_W:                                    // STATUS poll loop
                if (axf_done) begin
                    if (axf_rdata[9:6] != 4'd0) begin
                        err <= 8'd2; st <= S_HALT;
                    end else if (axf_rdata[5] && !axf_rdata[1] &&
                                 !axf_rdata[0])
                        st <= S_W2;
                    // else: stay and re-issue the poll read
                end else if (!axf_busy) begin
                    axf_addr <= A_STATUS; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            S_W2:                                   // YSTAT gate
                if (axf_done) begin
                    if ((axf_rdata & 32'h00020000) != 32'd0 &&
                        axf_rdata[15:0] == ycnt_exp)
                        st <= S_W3;
                    else begin
                        err <= 8'd3; st <= S_HALT;
                    end
                end else if (!axf_busy) begin
                    axf_addr <= A_YSTAT; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            S_W3:                                   // BRGSTAT gate
                if (axf_done) begin
                    // pl_m3 law: (brg>>2)&0x7==0 && brg&0x2 -- bit1 is
                    // ld_done_st (required SET); [2:0]==0 would contradict
                    if (axf_rdata[1] && axf_rdata[4:2] == 3'd0)
                        st <= S_W4;
                    else begin
                        err <= 8'd4; st <= S_HALT;
                    end
                end else if (!axf_busy) begin
                    axf_addr <= A_BRG; axf_we <= 1'b0;
                    axf_start <= 1'b1;
                end
            S_W4:                                   // scatter close
                // 2e (SPEC §7.1) credit-gated release -- ARCHITECTURAL
                // VERDICT (2026-10-15, xsim evidence): the early release
                // is DISABLED and rel=1 degenerates to the verified close.
                // The engine DOES queue one job deep (job_pend & core
                // job_ready), so an early CTRL fire is legal -- but the
                // single y_scatter unit serializes on sc_done: arming
                // the consumer's scatter while the producer's tail
                // scatter drains re-aims the in-flight writes (t17:
                // conv1 y region poisoned, 1993 arena diffs).  Safe
                // order is sc_done -> arm -> fire, which is exactly
                // the existing ovl flow, so an early release buys only
                // the S_W4 spin -- no compute overlap.  The CHAIN_REL
                // plumbing (CSR 0xE0, S2L/SKEW telemetry, rel_r) stays:
                // the counters measure the S||L wait class either way.
                if (sc_done) begin
                    if (sc_done && sc_err) begin err <= 8'd5; st <= S_HALT; end
                    else if (ovl_r) begin
                        // ovl busy-edge law: the S_W spin above waits
                        // for loads-done + engine idle, so the stream
                        // launched at this block's S_L1 has fully
                        // loaded -- the S_L1W tail (S_G1 -> S_L1W) must
                        // not wait for a busy edge that came and went
                        // during the polls (walk+ovl S_L1W hang,
                        // 2026-10-15).  Holds for the early-release arm
                        // too (same S_W gate).
                        seen_busy <= 1'b1;
                        // ovl: a verified scatter close == one block done;
                        // an EARLY release is not a verified close -- keep
                        // the poll bit set so the producer's outstanding
                        // sc_done is not double-accounted later
                        if (sc_done) begin
                            progress_blk <= progress_blk + 16'd1;
                            polls_pend_r <= 1'b0;    // fired block accounted
                            // 2e-fix: the verified boundary close = the
                            // previous conv drained -> the hbuf producer
                            // face advances.  In walk+ovl conv_idx crossed
                            // at S_CVRD (fire of the last block); the
                            // producer's tail scatter still writes until
                            // this sc_done (wm-short seal deadlock,
                            // t17 2026-10-15).  b_cnt==0 + conv_cnt!=0 =
                            // first block of a non-first conv = exactly
                            // one event per boundary.
                            if (b_cnt == 12'd0 && conv_cnt != 5'd0)
                                prod_conv <= gconv;
                        end
                        st <= fin_r ? S_DONE : S_OAD;
                    end
                    else st <= S_ADV;
                end
            S_OAD: begin                            // ovl: arm scatter(b)
                sc_arm <= 1'b1;  // sc_base/sc_vc already latched at S_ARM
                if (walk_r && lut_pend_r) begin
                    // walk+ovl: nest this conv's deferred LUT reload
                    // here (array idle -- the polls above just closed;
                    // the first block's stream is still loading)
                    lut_pend_r  <= 1'b0;
                    lut_ret_q1_r<= 1'b1;           // return to S_Q1RD
                    st <= S_LUTRD;
                end else
                    st <= S_Q1RD;
            end
            S_ADV: begin
                b_cnt <= b_cnt + 12'd1;
                if (!ovl_r)
                    // global count (legacy nb_tot==0 == V1.0 value)
                    progress_blk <= progress_blk + 16'd1;
                timeout <= 32'd0;                   // fresh per-block window
                if (rc_pair_w && (spatial_total_r != 12'd0)) begin
                    if (!rc_r[0]) begin
                        // First job of pair: hold this exact X tile for job 1.
                        rc_r <= rc_r + 6'd1;
                    end else if (nt_r == spatial_total_r - 12'd1) begin
                        nt_r <= 10'd0; s_r <= 4'd0; oy_r <= 10'd0;
                        if (rc_r == rcmax_r - 6'd1)
                            rc_r <= 6'd0;
                        else
                            rc_r <= rc_r + 6'd1;
                    end else begin
                        // Return to the same pair's even RC for the next tile.
                        rc_r <= rc_r - 6'd1;
                        nt_r <= nt_r + 10'd1;
                        if (s_r == ns_r - 4'd1) begin
                            s_r <= 4'd0;
                            oy_r <= oy_r + 10'd1;
                        end else
                            s_r <= s_r + 4'd1;
                    end
                end else if (rc_outer_r && (spatial_total_r != 12'd0)) begin
                    if (nt_r == spatial_total_r - 12'd1) begin
                        nt_r <= 10'd0; s_r <= 4'd0; oy_r <= 10'd0;
                        if (rc_r == rcmax_r - 6'd1)
                            rc_r <= 6'd0;
                        else
                            rc_r <= rc_r + 6'd1;
                    end else begin
                        nt_r <= nt_r + 10'd1;
                        if (s_r == ns_r - 4'd1) begin
                            s_r <= 4'd0;
                            oy_r <= oy_r + 10'd1;
                        end else
                            s_r <= s_r + 4'd1;
                    end
                end else if (rc_r == rcmax_r - 6'd1) begin
                    rc_r <= 6'd0;
                    nt_r <= nt_r + 10'd1;
                    if (s_r == ns_r - 4'd1) begin
                        s_r <= 4'd0;
                        oy_r <= oy_r + 10'd1;
                    end else
                        s_r <= s_r + 4'd1;
                end else
                    rc_r <= rc_r + 6'd1;
                if (dual_entry_r && (b_cnt == 12'd159)) begin
                    if (gconv < 6'd21)
                        dbg_dual_transition <= {gconv, slot_w, second_slot_w, nb_c};
                    rc_r <= 6'd0;
                    nt_r <= 10'd0;
                    s_r <= 4'd0;
                    oy_r <= 10'd0;
                    pbase <= {second_slot_w, 7'd0};
                    sbase <= {1'b0, second_slot_w, 4'd0};
                    lbase <= {second_slot_w, 8'd0};
                    wl_wbase <= wl_wbase + (wl_rc_stride << 4);
                end
                if (walk_r) begin
                    // ---- M9.4: conv boundary = per-conv nb from table ----
                    if (b_cnt == nb_c - 12'd1) begin
                        dbg_last_face_close <= {2'd0, gconv, nb_c, b_cnt};
                        face_close <= 1'b1;
                        nb_tot <= nb_tot + {4'd0, nb_c};
                        if (conv_cnt == nconv_r - 5'd1) begin
                            // ---- v2.4: page-local conv end.  Frame end
                            //      only when the ACTIVE page is the last
                            //      (legacy: npages==1, page_r==0 ->
                            //      byte-identical to the v2.3 frame-end
                            //      branch); otherwise the page FSM ----
                            if (manual_paged_r ||
                                ({1'b0, page_r} == npages_eff - 4'd1)) begin
                                if (!epoch_done_ok) begin
                                    if (manual_producer_commit_wait) begin
                                        st <= S_CARRY_COMMIT;
                                    end else begin
                                        err <= E_RP_UNSEALED;
                                        st <= S_HALT;
                                    end
                                end else if (ovl_r) begin
                                    // walk+ovl: the last block's polls are
                                    // still pending (they ride the NEXT
                                    // block's stream in ovl flow; there is
                                    // none) -- fin pass closes the frame
                                    fin_r <= 1'b1;
                                    vc_poll_r <= vc_r;
                                    st <= S_W;
                                end else
                                    st <= S_DONE;
                            end else
                                st <= S_PGE0;
                        end else begin
                            conv_cnt <= conv_cnt + 5'd1;
                            gconv    <= gconv + 6'd1;   // v2.4 global idx
                            // cursor reset (later NBAs win over the
                            // incremental walk above)
                            b_cnt <= 12'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                            s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                            arn_resume_state <= S_PPPG;
                            if (paged_mode) begin
                                st <= S_ARN0;
                            end else begin
                                st <= S_PPPG;
                            end
                            // v2.3: conv boundary routes through ARN/PPP;
                        end
                    end else
                        st <= S_PREP;
                end else if (b_cnt == {2'd0, cfg_nb} - 12'd1) begin
                    if (ovl_r) begin
                        // fin pass: close the last block fully (polls +
                        // scatter) so done implies the last slot settled
                        fin_r <= 1'b1;
                        vc_poll_r <= vc_r;
                        st <= S_W;
                    end else
                        st <= S_DONE;
                end else
                    st <= S_PREP;
            end
            // ================= v2.4 page advance (SPEC §2.4) =============
            // Reached from the S_ADV conv-boundary branch when the active
            // page's convs are all closed and the frame has more pages.
            // Rearm adds ZERO AXI-Lite writes (the G2 no-AXI law): the new
            // page's tables come from the windowed CSR face (page_r
            // bump), the per-conv plan from the slot-based cv/cv_slot
            // faces, and the hbuf slot pool re-arms off the pg_adv pulse.
            S_PGE0: begin
                // page bump + watchdog refresh + trace page anchor.  The
                // CSR windowed face follows page_r combinationally; the
                // registered PPP sanity (2 free-running sample stages)
                // re-settles exactly 2 cycles later -- S_PGE2 samples it,
                // the doorbell sample law.
                page_r         <= page_r + 3'd1;
                schedule_page_r <= schedule_page_r + 3'd1;
                pg_anchor      <= 1'b1;
                pg_anchor_page <= schedule_page_r + 3'd1;
                timeout        <= 32'd0;       // watchdog page refresh
                st <= S_PGE1;
            end
            S_PGE1: begin
                // hbuf rearm face: the new page's global conv base and
                // conv count, valid on the pg_adv cycle (hbuf samples
                // them together).
                pg_adv   <= 1'b1;
                pg_base  <= gconv + 6'd1;      // new page's conv 0 (global)
                pg_nconv <= pg_nconv_w;        // NEW-page descriptor nconv
                pg_nedge <= pg_desc[6:4];      // NEW-page new-edge count
                st <= S_PGE2;
            end
            S_PGE2: begin
                // settle cycle only (see the state-constant block: the
                // sanity pair needs the 3rd cycle post-bump to hold the
                // NEW window's scan).  No side effects.
                st <= S_PGE3;
            end
            S_PGE3: begin
                if (ppp_err_r != 8'd0) begin
                    // new-page PPP window failed the sanity -- same
                    // first-error-wins codes as the doorbell
                    err <= ppp_err_r;
                    st  <= S_HALT;
                end else begin
                    conv_cnt <= 5'd0;          // page-local conv restart
                    nconv_r  <= pg_nconv_w;    // new-page per-page nconv
                    gconv    <= gconv + 6'd1;  // global conv crosses too
                    ppp_ptr  <= 3'd0;          // PPP window restart
                    // G2 fix (2026-10-18): cursor reset MUST fire on the
                    // page-advance branch too -- the in-page conv boundary
                    // (S_ADV) zeroes this same set, but the page branch
                    // bypassed it: the new page's conv 0 entered its LUT
                    // reload with lut_i=255 (ONE entry written, then the
                    // epilogue), and b_cnt/s_r/oy_r/rc_r/nt_r stayed at
                    // the closing block's values (conv truncated to 1
                    // block, strip/geometry cursors stale, load-beat
                    // overrun).  Same later-NBA-wins law as S_ADV.
                    b_cnt <= 12'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                    s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                    arn_resume_state <= S_PPPG;
                    st <= S_ARN0;
                end
            end
            S_CARRY_COMMIT: begin
                // DB2/DB6 local scatter close precedes the shared AXI/B fence.
                // Wait for the real producer commit; the ordinary watchdog
                // bounds this state and no RP arm/start is emitted here.
                if (epoch_done_ok) begin
                    st <= S_DONE;
                end else if (!manual_producer_commit_wait) begin
                    err <= E_RP_UNSEALED;
                    st <= S_HALT;
                end
            end
            S_DONE: begin
                // v2.4: window face back to page 0 before the next
                // doorbell (S_IDLE samples the page-0 descriptor into
                // nconv_r).  Legacy: page_r never left 0 -- no-op.
                // Keep the completed page identity stable until the next
                // atomic acceptance explicitly latches a new checked tag.
                st <= S_IDLE;
            end
            S_HALT: ;                               // sticky
            default: st <= S_IDLE;
            endcase
            end

            // g3r6 timing cut: the wide conv-shadow load group fires off
            // the registered cv_load_en strobe (set in S_CVD2, default-
            // cleared every other cycle) -- fires exactly during the
            // S_CVLH cycle, same values as the originals.  board round-4
            // fix (2026-10-09) note moved with the loads: cv_geo/cv_wlay
            // carry PLANE-RELATIVE offsets only (m9_m94_dump packs x_off
            // / w_off_acc into the tables; every xsim gate ran with CSR
            // X/W bases = 0, so the missing plane base was invisible in
            // sim).  Walk mode must add the CSR plane bases (0x08/0x0C)
            // exactly the way obuf_r adds cfg_ybase -- otherwise the
            // readers AR at absolute 0x0..plane_top (board round-4:
            // every MAC product zero, y = requant(bias) for 100% of
            // payload bytes, plane fills invisible; Y path unaffected
            // because obuf_r already added its base).
            if (cv_load_en) begin
                nb_c    <= cv_iss[11:0];
                dual_entry_r <= paged_w && (cv_iss[11:0] == 12'd320) &&
                                (cv_iss[17:12] == 6'd32);
                rcmax_r <= (paged_w && (cv_iss[11:0] == 12'd320) &&
                            (cv_iss[17:12] == 6'd32)) ? 6'd16 :
                           cv_iss[17:12];
                rc_outer_r <= 1'b0;
                case (cv_iss[17:12])
                    6'd1:  spatial_total_r <= cv_iss[11:0];
                    6'd2:  spatial_total_r <= (cv_iss[11:0] + 12'd1) >> 1;
                    6'd4:  spatial_total_r <= (cv_iss[11:0] + 12'd3) >> 2;
                    6'd8:  spatial_total_r <= (cv_iss[11:0] + 12'd7) >> 3;
                    6'd16: spatial_total_r <= (cv_iss[11:0] + 12'd15) >> 4;
                    6'd32: spatial_total_r <= (cv_iss[11:0] + 12'd31) >> 5;
                    default: spatial_total_r <= 12'd0;
                endcase
                if ((cv_iss[23:22] == 2'd1) && (cv_iss[17:12] > 6'd1))
                    rc_outer_r <= 1'b1;
                ns_r    <= cv_iss[21:18];
                nseg_r  <= cv_iss[23:22];
                stride_r<= cv_iss[55:24];
                obuf_r  <= cfg_ybase + cv_iss[87:56];
                seg_tab[0] <= cv_iss[143:88];
                seg_tab[1] <= cv_iss[199:144];
                seg_tab[2] <= cv_iss[255:200];
                geo_ic  <= cv_geo[15:0];  geo_h  <= cv_geo[31:16];
                geo_w   <= cv_geo[47:32];  geo_kh <= cv_geo[51:48];
                geo_kw  <= cv_geo[55:52];  geo_sh <= cv_geo[59:56];
                geo_sw  <= cv_geo[63:60];  geo_ph <= cv_geo[67:64];
                geo_pw  <= cv_geo[71:68];
                geo_first     <= cv_geo[72];
                geo_law_fetch <= cv_geo[73];
                geo_xbase     <= cfg_xbase + cv_geo[105:74];
                wl_wbase      <= cfg_wbase + cv_wlay[31:0];
                wl_slab       <= cv_wlay[63:32];
                wl_rc_stride  <= cv_wlay[95:64];
                if (gconv == 6'd21)
                    dbg_dual_transition <= cv_wlay[95:64];
                wl_oc_stride  <= cv_wlay[127:96];
                wl_oc         <= cv_wlay[135:128];
                // 2a: channel stride tail field (0 = legacy h*w fallback)
                geo_ch_stride <= cv_wlay[167:136];
            end
        end
    end

endmodule
