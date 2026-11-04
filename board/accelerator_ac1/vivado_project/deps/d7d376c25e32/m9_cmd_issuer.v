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
    output reg  [11:0] progress_blk  ,   // blocks completed (across convs)
    // ---- ROM read ports (registered, 1-cycle) ----
    // r6 ROM-widening widths (2026-10-10): pctl 11b (16 convs x 128
    // rows), strip 8b (16 x 16), lut 12b (16 x 256) -- NCONV_MAX=16
    // cfg_nconv is 5b so the NCONV_MAX=16 endpoint is representable.  The
    // M9.5 10b/7b/11b law capped the walk at 8 convs (conv>=8 base wrap aliased conv 0-3; r5 r12
    // evidence arena_err=8707 first byte 0x40000 = conv8 obuf).
    output reg  [11:0] pctl_addr     ,
    input  wire [95:0] pctl_data     ,
    output reg  [8:0]  strip_addr    ,
    input  wire [20:0] strip_data    ,
    output reg  [12:0] lut_addr      ,
    input  wire [7:0]  lut_data      ,
    // ---- M9.4 conv-table ROM face (registered, 1-cycle) ----
    output reg  [4:0]  cv_addr       ,
    input  wire [255:0] cv_iss       ,
    input  wire [105:0] cv_geo       ,
    // M10.1-v2 2a: m9_bm_wlay widened 136->168 (ch_stride[167:136])
    input  wire [167:0] cv_wlay      ,
    output reg  [4:0]  conv_idx      ,   // active conv (TB snoop/ledger)
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
    output reg  [4:0]  rt_rc         ,
    output reg  [4:0]  rt_vc         ,
    output reg  [10:0] rt_k          ,
    output reg  [31:0] rt_segoff     ,
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
    output reg  [3:0]  prod_conv     ,
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
    input  wire [29:0]  cfg_layout_id,   // CSR 10 conv x 3b layout vector
    input  wire [7:0]   frame_gen    ,   // CSR doorbell-latched generation
    input  wire [6:0]   ppu_desc_count,  // PPU island loaded-DESC count
                                         //   (E_PPP_DESC sanity凭据)
    output reg          ppu_start    ,   // 1-cycle pulse -> walker PL entry
    output reg  [17:0]  ppu_start_payload, // {frame_gen[7:0], seg_idx[2:0],
                                         //   desc_idx[6:0]} (DESIGN §3.1)
    input  wire         ppu_done     ,   // walker arbiter verdict pulse
    input  wire         ppu_done_abort,  // 1 = token/engine failure
    input  wire [7:0]   ppu_done_err     // abort err code (with pulse)
);

    // ---------------- engine register offsets (byte) ----------------
    localparam [7:0] A_CTRL   = 8'h04, A_STATUS = 8'h08, A_GEOM   = 8'h0C,
                     A_ROWVAL = 8'h10, A_NMASK  = 8'h14, A_JOBCFG = 8'h18,
                     A_LDGRP  = 8'h1C, A_PBIAS  = 8'h20, A_PM     = 8'h24,
                     A_PSH    = 8'h28, A_PCTL   = 8'h2C, A_LUTD   = 8'h44,
                     A_LDLEN  = 8'h40, A_YSTAT  = 8'h48, A_BRG    = 8'h54,
                     A_LDSTAT = 8'h3C;

    localparam [31:0] TIMEOUT_MAX = 32'd50_000_000;   // 0.5 s @ 100 MHz

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
    // v2.3 err codes (conv STATUS domain; avoid 1-10 + PPU island E_CODE)
    localparam [7:0] E_PPP_OPCODE     = 8'h20,
                     E_PPP_ORDER      = 8'h21,
                     E_PPP_DESC       = 8'h22,
                     E_LAYOUT_RANGE   = 8'h23,
                     E_LAYOUT_MISMATCH= 8'h24,
                     E_GEN_MISMATCH   = 8'h25;
    reg [5:0] st;

    // run latches
    reg [9:0]  b_cnt;         // completed blocks
    reg [5:0]  rc_r, rcmax_r;
    reg [9:0]  nt_r, oy_r;
    reg [3:0]  s_r, ns_r;
    reg [3:0]  r_cur;         // Q1 row cursor
    reg [7:0]  lut_i;
    reg [4:0]  vc_r;
    reg [15:0] nmask_r;
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
    reg [11:0] nb_tot;        // cumulative block base of this conv
    reg  [1:0] nseg_r;        // segments per block (1..3)
    reg  [1:0] seg_r;         // active segment index
    reg [11:0] swoff_r;       // current segment w_off (12b table field)
    reg [15:0] sk0ic_r;       // current segment k-seed kIC
    reg  [2:0] sk0kh_r;       // current segment k-seed kKH (3b table field)
    reg  [2:0] sk0kw_r;       // current segment k-seed kKW (3b table field)
    reg [55:0] seg_tab [0:2]; // per-seg {kw0,kh0,ic0,woff,g,jc,k} (55b)
    reg  [11:0] pbase;        // pctl ROM base = conv*128 (r10: 12b)
    reg  [8:0]  sbase;        // strip ROM base = conv*16  (r10: 9b)
    reg  [12:0] lbase;        // lut ROM base = conv*256  (r10: 13b)

    // v2.3 PPP walk registers (DESIGN §3): ppp_ptr walks the 8-word CSR
    // table once per frame; frame_gen_r latches the CSR generation at the
    // doorbell for both the ppu_start payload and later gen compare.
    reg  [2:0]  ppp_ptr;      // active PPP table word (0..7)
    reg  [7:0]  frame_gen_r;  // generation latched at doorbell

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
    wire [1:0]  g_cur = ovl_r ? (b_cnt[0] ? 2'd3 : 2'd0) : g_r;
    // JOBCFG write value: SEQ = cfg, OVL = read groups follow parity
    wire [7:0]  jc_cur = ovl_r ? (jc_r | (b_cnt[0] ? 8'h18 : 8'h00)) : jc_r;
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
                         ppp_op1_c != 5'h13)
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
                         ppp_op_c != 5'h13)
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
    // (multi-bit = E_LAYOUT_MISMATCH); nconv>10 with any non-default
    // layout = E_LAYOUT_RANGE (10-conv vector boundary, v2.4 expansion
    // is the documented exit).
    reg [7:0] layout_err_c;
    reg [2:0] layout_f_c;
    integer   layout_k;
    always @* begin
        layout_err_c = 8'd0;
        for (layout_k = 0; layout_k < 10; layout_k = layout_k + 1) begin
            layout_f_c = cfg_layout_id[layout_k*3 +: 3];
            if ((layout_f_c & (layout_f_c - 3'd1)) != 3'd0)
                layout_err_c = E_LAYOUT_MISMATCH;
        end
        if ((cfg_nconv > 5'd10) && (cfg_layout_id != 30'd0))
            layout_err_c = E_LAYOUT_RANGE;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; err <= 8'd0; progress_blk <= 10'd0;
            b_cnt <= 10'd0; rc_r <= 6'd0; rcmax_r <= 6'd0;
            nt_r <= 10'd0; oy_r <= 10'd0; s_r <= 4'd0; ns_r <= 4'd0;
            r_cur <= 4'd0; lut_i <= 8'd0; vc_r <= 5'd0; nmask_r <= 16'd0;
            k_r <= 11'd0; jc_r <= 8'd0; g_r <= 2'd0;
            stride_r <= 32'd0; obuf_r <= 32'd0;
            timeout <= 32'd0; seen_busy <= 1'b0;
            ovl_r <= 1'b0; fin_r <= 1'b0; vc_poll_r <= 5'd0;
            rel_r <= 1'b0;
            prod_conv <= 4'd0;
            polls_pend_r <= 1'b0; lut_pend_r <= 1'b0; lut_ret_q1_r <= 1'b0;
            cv_load_en <= 1'b0;
            ppp_err_r <= 8'd0; layout_err_r <= 8'd0;   // g3r8 registered sanity
            ppp_err_s1_r <= 8'd0; ppp_seen_empty_s1_r <= 1'b0;  // g3r9 s1
            ppp_node_last_s1_r <= 5'd0; ppp_plast_s1_r <= 1'b0;
            walk_r <= 1'b0; conv_cnt <= 5'd0; nconv_r <= 5'd1;
            nb_c <= 12'd0; nb_tot <= 12'd0; nseg_r <= 2'd0; seg_r <= 2'd0;
            swoff_r <= 12'd0; sk0ic_r <= 16'd0; sk0kh_r <= 3'd0;
            sk0kw_r <= 3'd0; seg_tab[0] <= 56'd0; seg_tab[1] <= 56'd0;
            seg_tab[2] <= 56'd0; pbase <= 12'd0; sbase <= 9'd0; lbase <= 13'd0;
            ld_start <= 1'b0; sc_arm <= 1'b0; sc_up2x <= 1'b0;
            rt_oy <= 10'd0; rt_s <= 4'd0; rt_rc <= 5'd0; rt_vc <= 5'd0;
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
        end else begin
            ld_start <= 1'b0;                       // pulse defaults
            sc_arm   <= 1'b0;
            axf_start<= 1'b0;
            ppu_start<= 1'b0;                       // v2.3 pulse default
            cv_load_en <= 1'b0;                     // g3r6 pulse default
            ppp_err_s1_r      <= ppp_err_s1_c;      // g3r9 knife B stage-1
            ppp_seen_empty_s1_r <= ppp_seen_empty_s1_c;   // free-running
            ppp_node_last_s1_r <= ppp_node_last_s1_c;     // sample
            ppp_plast_s1_r    <= ppp_plast_s1_c;
            ppp_err_r    <= ppp_err_c;              // stage-2 (words 4..7)
            layout_err_r <= layout_err_c;           // sample (table stable
                                                    // well before doorbell)
            if (start) begin
                frame_gen_r <= frame_gen;           // doorbell latch (§3.2)
                ppp_ptr     <= 3'd0;                // reset at doorbell
            end

            if (st != S_IDLE && st != S_HALT && st != S_DONE)
                timeout <= timeout + 32'd1;
            else
                timeout <= 32'd0;
            if (timeout >= TIMEOUT_MAX) begin
                err <= 8'd7; st <= S_HALT;
            end

            case (st)
            // ================= LUT prologue =================
            S_IDLE: if (start && err == 8'd0) begin
                // ---- v2.3 doorbell-edge sanity (DESIGN §3.3): refuse the
                // frame BEFORE any walk begins if the PPP table or layout
                // vector is malformed.  First-error-wins: PPP table errors
                // outrank layout errors (both are PS load bugs; ordering
                // only fixes the reported code). ----
                if (ppp_err_r != 8'd0) begin
                    err <= ppp_err_r;
                end else if (layout_err_r != 8'd0) begin
                    err <= layout_err_r;
                end else if (cfg_nconv > 5'd1) begin
                    // ---- M9.4 conv-table walk: cfg_overlap=0 = SEQ
                    //      canon (V2.0, byte-stable); cfg_overlap=1 =
                    //      walk+ovl (V2.1) -- per-conv nseg==1 enforced
                    //      at S_CVLH (err=9) ----
                    walk_r  <= 1'b1;
                    nconv_r <= cfg_nconv;
                    conv_cnt<= 5'd0;
                    nb_tot  <= 12'd0;
                    b_cnt <= 10'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                    s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                    ovl_r <= cfg_overlap; fin_r <= 1'b0;
                    rel_r <= chain_rel;
                    prod_conv <= 4'd0;
                    polls_pend_r <= 1'b0;
                    lut_pend_r <= 1'b0; lut_ret_q1_r <= 1'b0;
                    cv_addr <= 5'd0;           // conv 0 table read
                    // v2.3: walk entry routes through the PPP gate (conv 0
                    // table words may be preceded by PPP segments -- e.g.
                    // SPPF chain head).  Legacy nconv<=1 path never enters
                    // the gate (byte-stable identity law).
                    st <= S_PPPG;
                end else if (cfg_nseg != 2'd1) begin
                    err <= 8'd6;                    // legacy single-seg guard
                end else begin
                    // ---- legacy path (byte-stable, modes 0/1) ----
                    walk_r <= 1'b0; nconv_r <= 5'd1; conv_cnt <= 5'd0;
                    rel_r <= chain_rel;
                    prod_conv <= 4'd0;
                    nb_tot <= 12'd0; nseg_r <= 2'd1; seg_r <= 2'd0;
                    swoff_r <= 12'd0;
                    sk0ic_r <= 16'd0; sk0kh_r <= 3'd0; sk0kw_r <= 3'd0;
                    pbase <= 12'd0; sbase <= 9'd0; lbase <= 13'd0;
                    cv_addr <= 5'd0;
                    rcmax_r <= (cfg_rc == 6'd0) ? 6'd1 : cfg_rc;
                    ns_r    <= (cfg_ns == 4'd0) ? 4'd1 : cfg_ns;
                    k_r     <= cfg_s0_k; jc_r <= cfg_s0_jc; g_r <= cfg_s0_g;
                    stride_r<= cfg_stride; obuf_r <= cfg_ybase + cfg_obuf;
                    ovl_r   <= cfg_overlap; fin_r <= 1'b0;
                    b_cnt <= 10'd0; rc_r <= 6'd0; nt_r <= 10'd0;
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
                    st <= S_LUTRD;
                end
            end
            // ================= v2.3 PPP gate (DESIGN §3) ==================
            // Entered at frame start (conv 0) and at every conv boundary
            // (conv_cnt already advanced = the ARRIVING conv).  Gate,
            // fire, wait; falls through to S_CVRD untouched when no PPP
            // word matches -- empty table = v1 structural identity.
            S_PPPG: begin
                // gate: word at ppp_ptr belongs to the arriving conv?
                st <= ppp_hit_w ? S_PPPF : S_CVRD;
            end
            S_PPPF: begin
                // fire: 1-cycle ppu_start; payload = {gen, seg, desc}
                // (trigger/payload separation -- §2.3 arithmetic: full
                // fields cannot inline in one word, geometry lives in the
                // PPU DESC slots this desc_idx selects).
                ppu_start        <= 1'b1;
                ppu_start_payload<= {frame_gen_r, ppp_ptr, ppp_ds_w};
                st <= S_PPPW;
            end
            S_PPPW: begin
                // wait: walker arbiter verdict.  Watchdog (err=7) covers a
                // hung walker (timeout runs in all non-IDLE states).
                if (ppu_done) begin
                    if (ppu_done_abort) begin
                        err <= ppu_done_err;        // E_GEN_MISMATCH etc.
                        st <= S_HALT;
                    end else begin
                        ppp_ptr <= ppp_ptr + 3'd1;  // same-node chain word
                        st <= S_PPPG;               // re-gate (SPPF chain)
                    end
                end
            end
            // ================= M9.4 conv-table read (walk) =================
            // entered at frame start (conv 0) and at every conv boundary;
            // LUT reload + full shadow switch is UNCONDITIONAL per conv
            // (pl_m3 per-conv load_lut canon -- switch window goes to the
            // ledger, not a dedup optimization).
            S_CVRD: begin
                cv_addr <= conv_cnt;              // table read for this conv
                conv_idx<= conv_cnt;              // TB snoop face
                // 2e-fix: SEQ walk reaches here only after the previous
                // conv's last verified close -> conv_cnt is drain-safe.
                // walk+ovl reaches here EARLY (last block's fire) -> hold
                // prod_conv until the verified boundary close (S_W4).
                if (!ovl_r) prod_conv <= conv_cnt[3:0];
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
                // Doorbell sanity already bounds layout!=0 to nconv<=10,
                // so conv_cnt<10 keeps the vector index in range.
                if ((conv_cnt < 5'd10) &&
                    (cfg_layout_id[conv_cnt*3 +: 3] == 3'b010) &&
                    (cv_wlay[167:136] == 32'd0)) begin
                    err <= E_LAYOUT_MISMATCH;
                    st <= S_HALT;
                end else begin
                pbase <= conv_cnt * 12'd128;       // flat ROM bases (r10 widths)
                sbase <= conv_cnt * 9'd16;
                lbase <= conv_cnt * 13'd256;
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
            S_PREP2: st <= S_ARM;
            S_ARM: begin
                vc_poll_r <= vc_r;          // ovl: iter b polls block b-1
                nmask_r <= strip_data[15:0];
                vc_r    <= strip_data[20:16];
                // y slot = obuf + stride*b (b CONV-LOCAL: pl_m3/golden
                // law -- each conv's arm_and_run restarts its own slot
                // walk at obuf+0; global nb_tot indexing put conv1+ at
                // +prevNB slots, M9.4 run02 arena evidence)
                sc_base <= obuf_r + stride_r * {20'd0, b_cnt};
                sc_vc   <= strip_data[20:16];
                sc_up2x <= (conv_cnt < 5'd16) ? cfg_up2x[conv_cnt] : 1'b0;
                // r10 guard: cfg_up2x is a 16-conv bitmap; conv 16+ would be
                // an out-of-range select (x in sim, index-alias in synth) --
                // 0 = no 2x until the ABI widens the CSR (driver ruling).
                if (!ovl_r)
                    sc_arm  <= 1'b1;         // ovl arms post-polls (S_OAD)
                r_cur   <= 4'd0;
                st <= ovl_r ? S_OCR : S_Q1RD;
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
                if (axf_done) st <= S_L1;
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
                    st <= (b_cnt == 10'd0 && !polls_pend_r)
                         ? S_OAD : S_W;
                else
                    st <= S_L1W;
            end
            S_L1W: begin                            // busy-edge wait (D1 law)
                if (ld_w_busy || ld_x_busy) seen_busy <= 1'b1;
                if (seen_busy && !ld_w_busy && !ld_x_busy)
                    st <= S_L1C;
            end
            S_L1C:                                  // LDLEN closure read
                if (axf_done) begin
                    // k_r is 11-bit: zero-extend, never part-select [12:0]
                    // (out-of-range bits read as X and poison the compare)
                    if (ldlen_w == {2'd0, k_r} && ldlen_x == {2'd0, k_r})
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
                            progress_blk <= progress_blk + 10'd1;
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
                            if (b_cnt == 10'd0 && conv_cnt != 5'd0)
                                prod_conv <= conv_cnt[3:0];
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
                b_cnt <= b_cnt + 10'd1;
                if (!ovl_r)
                    // global count (legacy nb_tot==0 == V1.0 value)
                    progress_blk <= nb_tot + {2'd0, b_cnt} + 12'd1;
                timeout <= 32'd0;                   // fresh per-block window
                if (rc_r == rcmax_r - 6'd1) begin
                    rc_r <= 6'd0;
                    nt_r <= nt_r + 10'd1;
                    if (s_r == ns_r - 4'd1) begin
                        s_r <= 4'd0;
                        oy_r <= oy_r + 10'd1;
                    end else
                        s_r <= s_r + 4'd1;
                end else
                    rc_r <= rc_r + 6'd1;
                if (walk_r) begin
                    // ---- M9.4: conv boundary = per-conv nb from table ----
                    if ({2'd0, b_cnt} == nb_c - 12'd1) begin
                        nb_tot <= nb_tot + nb_c;
                        if (conv_cnt == nconv_r - 5'd1) begin
                            if (ovl_r) begin
                                // walk+ovl: the last block's polls are
                                // still pending (they ride the NEXT
                                // block's stream in ovl flow; there is
                                // none) -- fin pass closes the frame
                                fin_r <= 1'b1;
                                vc_poll_r <= vc_r;
                                st <= S_W;
                            end else
                                st <= S_DONE;
                        end else begin
                            conv_cnt <= conv_cnt + 5'd1;
                            // cursor reset (later NBAs win over the
                            // incremental walk above)
                            b_cnt <= 10'd0; rc_r <= 6'd0; nt_r <= 10'd0;
                            s_r <= 4'd0; oy_r <= 10'd0; lut_i <= 8'd0;
                            st <= S_PPPG;      // v2.3: conv boundary routes
                                                // through the PPP gate; falls
                                                // to S_CVRD when no PPP word
                                                // matches the arriving conv
                                                // (conv_cnt already advanced,
                                                // S_PPPG compares against it)
                        end
                    end else
                        st <= S_PREP;
                end else if (b_cnt == cfg_nb - 10'd1) begin
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
            S_DONE: st <= S_IDLE;
            S_HALT: ;                               // sticky
            default: st <= S_IDLE;
            endcase

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
                rcmax_r <= cv_iss[17:12];
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
                wl_oc_stride  <= cv_wlay[127:96];
                wl_oc         <= cv_wlay[135:128];
                // 2a: channel stride tail field (0 = legacy h*w fallback)
                geo_ch_stride <= cv_wlay[167:136];
            end
        end
    end

endmodule
