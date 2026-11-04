/************************************************************************
 * File Name       : m9_w_feeder_v3.v
 * Developer       : M9.3 V3 issuer redesign line
 * Date            : 2026-10-13
 * Project Name    : YOLO object accel (M9.3 V3, 2026-10-13_yolo_m93_issuer_v3_run01)
 * Module Name     : m9_w_feeder_v3
 * Description     :
 *   Resident-W beat generator V3 -- BRAM-RESIDENT rewrite of
 *   m9_w_feeder.v (V1.0).  The W side of the frozen three-beat law
 *   with the per-(conv,rc,seg) 8-row W slab PRELOADED once into
 *   on-chip storage, instead of V1.0's per-k 8-sequential-byte DDR
 *   walk (16 cyc/k) with the whole slab re-read from DDR for every
 *   block (nb x W DDR traffic).
 *
 *   W layout law UNCHANGED (M8 PIPE w_index):
 *     waddr(r,k) = W_BASE + slab + rc_stride*rc + oc_stride*r
 *                  + seg_w_off + k
 *   w_beat contract UNCHANGED: one 64b beat per k,
 *   data[8r+:8] = wv[r][k], first = (k==0); dead rows (8*rc+r >= oc)
 *   are ZERO -- baked at preload time in V3 (V1.0 zeroed them at
 *   read time; byte-identical result).
 *
 *   Storage (build-phase mapping note): 8 rows x seg_k bytes,
 *   seg_k <= 2047 -> 16 KB max, KMAX=2304 kept as safe superset.
 *   Behavioral model here = per-row byte arrays; build phase maps
 *   each row to its own BRAM (single write port for preload, single
 *   async read port for serve -> NO TDP same-address hazard by
 *   construction; the discipline law still applies to any future
 *   shared-port variant: write lock + pointer schedule, TB must
 *   never fabricate conflicting accesses).
 *   SPEC DEVIATION LOGGED: spec 2.2 said "2048 x 72b" -- that depth
 *   is 12.5% short for kfull=2304 (needs 2304 line entries);
 *   per-row byte-wide RAMs x8 is the correct floor and is what the
 *   build phase will instantiate (xpm_memory / .veo verification
 *   pending).
 *
 *   Preload line port protocol = the v3 line protocol (pulsed
 *   requests, pipelined, in-order responses); downstream is the wrd
 *   channel of m9_axi_rd_v3 (V2.1 cache reused per spec 2.3).
 *   Preload requests cover ONLY live-row in-slab lines -- no wild
 *   reads (INJ-5C safety law preserved).
 *
 *   Residency: (rc, seg) match register; a start whose slab is
 *   resident goes straight to serve.  Reload on mismatch serializes
 *   preload-then-serve INSIDE this module; the cross-block /
 *   cross-conv hiding is the issuer's job (spec 2.4: early start).
 *
 * Dependencies    : none (behavioral storage; build phase replaces
 *                   with BRAM primitives)
 * Revision History:
 *   - V3.0 (2026-10-13) : initial release (Phase B, M9.3 V3 redesign).
 *   - V3.2 (2026-10-13) : ST_SERVE advance qualified by w_beat_valid.
 *                         valid is a registered pulse (default-cleared),
 *                         so the first SERVE cycle presents valid=0 while
 *                         the mux's w_beat_ready (blind to valid) is already
 *                         high -- unqualified advance swallowed k=0 and
 *                         shifted all W beats by one k (SEQ NB=4 smoke
 *                         hang at 573 beats = 191 triples; mux stranded
 *                         at ph=0 waiting a W beat the feeder had already
 *                         skipped past).
 *   - V3.3 (2026-10-13) : 8B-ALIGNMENT FIX.  W row bases are byte-granular
 *                         (oc/rc strides + segment offset; conv0
 *                         oc_stride=27 -> request addr 0x1b tripped the
 *                         axi_rd_v3 alignment guard on the v25 ladder).
 *                         Requests now go out aligned-down (line number =
 *                         row_base[31:3] + ij); the fill re-maps each
 *                         response byte to wbram position m = rj*8+bi-off_r
 *                         and the per-row line count jlines =
 *                         ceil((off+k)/8) covers the spill line.  The
 *                         engine-level TB line models had served the
 *                         request's natural byte window at ANY address,
 *                         masking this until the real aligned-line adapter
 *                         entered the loop (m94/seq/ovl gates re-run clean
 *                         after the change).
 *   - V3.4 (2026-10-13) : line-request pacing credit.  The axi_rd_v3
 *                         line port has no ready and sim-fatals at 16
 *                         outstanding (LSQ depth); the preload FSM now
 *                         holds new issues while (issued - responded)
 *                         >= 12 (unit-gate-proven pacing depth, margin 4
 *                         under the LSQ).  Without it the v25 ladder
 *                         tripped M9AXIRD3_FAIL LSQ overflow within the
 *                         first block's preload.
 *   - V3.5 (2026-10-14) : W storage = m9_bm_wblk (blk_mem_gen v8.4 TDP
 *                         IP, .veo instantiation, byte-write enable per
 *                         PG058).  The behavioral wbram byte array had
 *                         an async-reset write process + async function
 *                         reads that blocked ALL RAM inference (147K FF
 *                         + giant mux cones -> 48 GB synth memory, first
 *                         V3 bit attempt aborted by build-log
 *                         forensics).  Word j = 8B-line j interleaved
 *                         across 8 rows; phase-A/phase-B dual-port write
 *                         schedule with pendB depth-1 tail flush; serve
 *                         side pipelined through the port-B output
 *                         register (lossless 1-deep skid, issue gated
 *                         on drain).  Contracts (w_beat, preload line
 *                         port, pacing, residency) UNCHANGED.
 *                         IP-first law: 2026-10-14 user ruling.
 *   - V3.6 (2026-10-14) : CLOSED-FORM write map.  The V3.5 serial
 *                         cfound/cw0 priority chain was a ~20ns comb
 *                         cone onto the m9_bm_wblk port-A enable/WE
 *                         pins (post-route worst slack -8.38ns
 *                         @100MHz, all 8 worst paths into u_wblk
 *                         ENARDEN; physopt Explore could not close).
 *                         w0 is now closed-form (bytes are contiguous
 *                         in m): parallel per-byte evaluation, no
 *                         loop-carried chain.  Function proven
 *                         identical by the wf differential gate.
 *   - V3.7 (2026-10-14) : REGISTERED write map (wa/wx comb -> ra_*
 *                         regs, RAM port-A write 1 cycle after the
 *                         response).  V3.6 closed-form still failed
 *                         post-route WNS=-4.516 (physopt 32-745
 *                         "unclosable"); TNS did drop 34% proving the
 *                         RAM-pin direction right.
 *   - V3.8 (2026-10-14) : TWO-STAGE PIPELINED NARROW MAP, after
 *                         worst-path forensics (bit/worst_paths_v37.rpt):
 *                         V3.7's cone was 15-18 levels with 71% ROUTE
 *                         delay and per-line shared terms at fanout
 *                         150-300 (rc_r dead broadcast).  Per-line
 *                         terms (base'/kn/word-base/first-word pair)
 *                         are computed once into stage-1 registers at
 *                         the response edge; per-byte permutation runs
 *                         the next cycle from registers only (~5
 *                         levels, FF->FF); biased +8 tracking keeps
 *                         every per-byte add 4-5 bits wide.  RAM write
 *                         now fires TWO cycles after the response;
 *                         ST_SERVE exit additionally gated on
 *                         !s1_valid.  Biased-map identities: m' = m+8,
 *                         m[2:0]=m'[2:0], word(m)=(m'>>3)-1, ge8=m'>=8,
 *                         phase A iff m4[4:3]==first-valid m4[4:3].
 *   - V3.9 (2026-10-14) : CONGESTION + WNS, after forensics of the
 *                         third post-route FAIL (WNS=-3.870 TNS=-35862,
 *                         bit/worst_paths_v38.rpt + in-design cell
 *                         census):
 *                         (1) WNS: ij_reg cone carried the
 *                         cfg_oc_stride*ir multiply on a DSP48 (A->P
 *                         comb 3.84ns) mid-cone.  row_base is now
 *                         tracked incrementally (rb_i_reg/rb_r_reg,
 *                         +cfg_oc_stride per row advance, exact because
 *                         cursors step by one); the per-block entry
 *                         value gets a full cycle.
 *                         (2) CONGESTION: the stage-2 din SCATTER
 *                         (computed 6-bit index into 512b per source
 *                         byte) cost ~12K LUTs (ra_din 7051 + pb_din
 *                         4988 measured post-route).  GATHER form: one
 *                         shared 512-bit rotator (lane L <-- source
 *                         (L[2:0]-base4)&7, ~300 LUTs) feeds BOTH
 *                         target words; WE=0 lanes are don't-care at
 *                         the RAM; value-identical at every WE=1 lane
 *                         (m4[2:0]=(base4+bi)&7 => bi, the V3.8
 *                         bijection inverse).
 *                         (3) trace ring arrays: reset removed (see
 *                         m9_trace_v2b.v V3.9 note -- the 13,808-load
 *                         reset net routed 8.658ns to the CLRs,
 *                         failing recovery on 1,059 endpoints).
 ************************************************************************/
`timescale 1ns / 1ps

module m9_w_feeder_v3 (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv W layout config ----
    input  wire [31:0] cfg_wbase     ,   // W region base (arena byte addr)
    input  wire [31:0] cfg_slab      ,   // w_index.base (layer slab start)
    input  wire [31:0] cfg_rc_stride ,
    input  wire [31:0] cfg_oc_stride ,   // == K
    input  wire [7:0]  cfg_oc        ,   // output channels
    // ---- per-block/per-segment runtime ----
    input  wire [4:0]  rt_rc         ,
    input  wire [10:0] rt_k          ,   // segment k count
    input  wire [31:0] rt_seg_off    ,   // seg w_off_in_slab (bytes)
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    // ---- W PRELOAD line port (v3 protocol; wrd channel cache behind) ----
    output reg  [31:0] paddr_line    ,
    output reg         preq_line     ,
    input  wire [63:0] pdata_line    ,
    input  wire        pvalid_line   ,
    // ---- W beat outlet -- contract unchanged ----
    output reg  [63:0] w_beat_data   ,
    output reg         w_beat_first  ,   // (k==0)
    output reg         w_beat_valid  ,
    input  wire        w_beat_ready
);

    localparam ST_IDLE = 3'd0, ST_PRE = 3'd1, ST_SERVE = 3'd2,
               ST_DONE = 3'd3;
    reg [2:0]  st;

    // latched runtime
    reg [10:0] k_r;
    reg [4:0]  rc_r;
    reg [31:0] seg_r;

    // residency
    reg        res_valid;
    reg [4:0]  res_rc;
    reg [31:0] res_seg;

    // preload cursors
    reg [3:0]  ir;                      // issue row  0..7
    reg [11:0] ij;                      // issue line 0..jlines_i-1
    reg [3:0]  rr;                      // response row
    reg [11:0] rj;                      // response line

    // 8*rc + r as ARITHMETIC (legacy law row_abs = {rc_r, r_cur} works
    // only because its row cursor is 3-bit; ir/rr are 4-bit here, and
    // {rc_r, ir} would be a 9-bit concat silently truncated to 8 --
    // with rc=1 that turned row_abs into 16+r and dead-marked every row)
    wire [7:0]  row_abs_i = {rc_r, 3'b000} + {4'b0000, ir};
    wire [7:0]  row_abs_r = {rc_r, 3'b000} + {4'b0000, rr};
    wire        dead_i    = (row_abs_i >= cfg_oc);
    wire        dead_r    = (row_abs_r >= cfg_oc);
    // V3.3: W row bases are NOT 8B-aligned in general -- oc/rc strides and
    // the segment byte offset are byte-granular (conv0 oc_stride=27 landed
    // a request on addr 0x1b and tripped the axi_rd_v3 alignment guard on
    // the v25 ladder).  Requests go out ALIGNED DOWN to the 8B line; the
    // in-line byte offset off(row) re-maps each response byte onto the
    // block column m = rj*8 + bi - off_r (the write-map comb above), and
    // the per-row line count jlines(row) = ceil((off+k)/8) covers the
    // spill line when off>0 (the V3.2-era engine-level TB served the
    // request's natural byte window for ANY address, which masked this
    // until the real aligned-line adapter entered the loop).
    // V3.9 (2026-10-14): row_base tracked INCREMENTALLY in registers.
    // Post-route forensics (bit/worst_paths_v38.rpt): the V3.8
    // combinational cfg_oc_stride*ir multiply sat mid-cone on a DSP48
    // (A->P comb = 3.84ns) between the issuer launch regs and ij_reg,
    // 15 levels, WNS=-3.870.  ir/rr step by exactly one per row, so
    // row_base += cfg_oc_stride at each row advance is value-exact; the
    // per-block init (one 32x5 multiply + three adds, FF->FF) gets a
    // full 10ns cycle, and the ij next-state cone collapses to a
    // 12-bit add + compare from registers.
    reg [31:0] rb_i_reg;              // issue-side row_base of current ir
    reg [31:0] rb_r_reg;              // response-side row_base of current rr
    wire [31:0] row_base_i = rb_i_reg;
    wire [31:0] row_base_r = rb_r_reg;
    // entry value from rt_* (not rc_r/seg_r): those are latched the SAME
    // edge the preload starts, so the registered values would be stale.
    wire [31:0] rb_entry = cfg_wbase + cfg_slab
                         + cfg_rc_stride * {27'd0, rt_rc}
                         + rt_seg_off;
    wire [2:0]  off_i = row_base_i[2:0];
    wire [2:0]  off_r = row_base_r[2:0];
    wire [11:0] jlines_i = ({9'd0, off_i} + {1'b0, k_r} + 12'd7) >> 3;
    wire [11:0] jlines_r = ({9'd0, off_r} + {1'b0, k_r} + 12'd7) >> 3;
    // issue address: aligned line (row_base_i[31:3] + ij) * 8
    wire [31:0] line_addr = {row_base_i[31:3] + {17'd0, ij}, 3'b000};

    assign busy = (st != ST_IDLE);
    assign done = (st == ST_DONE);

    // per-serve-k beat select: 8 row lanes out of the RAM word (pure
    // function of the port-B data + the on-output-reg cursor's lane --
    // no module-memory read in a continuous assign, so the xsim
    // continuous-assign memory pitfall does not apply)
    function [63:0] beat_sel;
        input [511:0] w;
        input [2:0]   lane;      // ka_d[2:0]
        integer r;
        begin
            for (r = 0; r < 8; r = r + 1)
                beat_sel[8*r +: 8] = w[8*(r*8 + lane) +: 8];
        end
    endfunction

    // ---------------- W block storage: m9_bm_wblk (BMG TDP IP, PG058) ---
    // Word j (9b addr, 0..287) = 8B-line j of the W block, line-interleaved
    // across the 8 rows: word byte lane (r*8+b) = row r, line-byte b.
    //   beat(k)    : word k[10:3] on port B, lane (r*8+k[2:0]) per row r.
    //   fill(rr,rj): response byte bi lands at column m = rj*8+bi-off_r
    //                (dead rows off=0) -> word m[10:3], lane rr*8+m[2:0].
    // V3.5 (2026-10-14): replaces the behavioral wbram byte array whose
    // async-reset write process + async function reads blocked ALL RAM
    // inference (147K FF + giant mux cones -> 48 GB synth memory, first
    // V3 bit attempt aborted; caught by build-log forensics).  Per the
    // IP-first law the storage is now a blk_mem_gen TDP instance (.veo
    // template, byte-write enable per PG058).
    // Write schedule: phase A of each response line goes out on port A
    // the same cycle; the phase-B tail (only when off_r misaligns the 8
    // bytes across two words) is deferred to port B the NEXT cycle via
    // pendB (depth 1).  Port B is idle during ST_PRE by FSM construction
    // (writes happen only in ST_PRE, reads only in ST_SERVE), so the
    // sustained 1-response/cycle stream is absorbed: A+B = 2 word-writes
    // per cycle in the worst case.  Same-word A/B collision lanes are
    // disjoint by construction (line L tail lanes < line L+1 head lanes).
    // ST_PRE exit waits for rr==8 && !pb_pend so the last tail flushes
    // before the first serve read claims port B.
    reg         rd_pend;          // serve: RAM output reg data awaiting bus
    reg  [10:0] ka;               // serve issue cursor (address presented)
    reg  [10:0] ka_d;             // cursor of the beat on wb_dout (lane sel)

    reg         pb_pend;          // preload: phase-B tail awaiting port B
    reg  [8:0]  pb_addr;
    reg  [63:0] pb_we;
    reg  [511:0] pb_din;
    // V3.7/V3.8 REGISTERED WRITE MAP: the write map reaches these
    // registers TWO cycles after its response (stage-1 line terms ->
    // stage-2 byte permutation -> ra_*/pb_*); the RAM port-A write then
    // fires the cycle after.  Post-route physopt declared the V3.6 comb
    // cone (rj/off/k signed compares -> 64-bit byte-enable + 512-bit
    // din straight onto the RAMB36 pins) unclosable at WNS=-4.5; the FF
    // boundaries give every sub-cone a full cycle.  Port A is write-only
    // and ST_SERVE is gated on !ra_pend && !pb_pend && !s1_valid, so
    // the delay is safe by construction.
    reg          ra_pend;
    reg  [8:0]   ra_addr;
    reg  [63:0]  ra_we;
    reg  [511:0] ra_din;

    // fill write map -- V3.8 (2026-10-14) TWO-STAGE PIPELINED NARROW MAP.
    // Forensics (bit/worst_paths_v37.rpt, post-route): the V3.6/3.7 cone
    // was 15-18 levels, 71% ROUTE delay (14.3ns datapath vs 10ns period),
    // with per-line shared terms (cw0, cm signed compares, dead_r) at
    // fanout 150-300.  Restructure: per-LINE terms computed ONCE into
    // stage-1 registers at the response edge; per-BYTE permutation the
    // next cycle from those registers only (~5 levels, FF->FF).
    //   byte bi -> column m = rj*8 + bi - off_x  (off_x = dead?0:off_r)
    //   biased tracking: m' = m + 8, base' = rj*8 - off_x + 8 (>0);
    //     m[2:0]  = m'[2:0]            (bias 8 == 0 mod 8)
    //     word(m) = (m' >> 3) - 1      (subtracting 8 borrows one word)
    //     ge8     = m' >= 8
    //   per byte: m4 = base'[3:0] + bi (5 bits, <=22); ge8 = |base'[12:4]
    //     | m4[4] | m4[3]; valid = kn_pos & (kn_ge8 | (kn_lo > bi)) where
    //     kn' = k_r + 8 - base' (only sign, >=8, and low 3 bits needed:
    //     kn_pos = k_r+8 > base', kn_ge8 = k_r >= base', kn_lo =
    //     (k_r - base')[2:0]); word = wbase' + m4[4:3] with
    //     wbase' = {base'[11:4],1'b0} - 1; phase A iff m4[4:3] equals the
    //     first valid byte's (m4first = base'[3:0] + lo, lo = (rj==0 &&
    //     !dead) ? off_r : 0) -- 2-bit compare, no 9-bit equality.
    //   lane = {rr, m[2:0]} is a bijection (add-constant mod 8), so each
    //   lane is written at most once per line -- same guarantee as V3.6.
    reg          s1_valid;        // stage-1 regs hold an un-drained line
    reg  [63:0]  s1_pd;           // captured pdata_line
    reg          s1_dead;
    reg  [2:0]   s1_rr;
    reg  [3:0]   s1_base4;        // base'[3:0]
    reg          s1_ge8hi;        // |base'[12:4]
    reg  [8:0]   s1_wbase;        // {base'[11:4],1'b0} - 1
    reg          s1_knpos;        // k_r + 8 >  base'  (any byte valid)
    reg          s1_knge8;        // k_r     >= base'  (all 8 bytes valid)
    reg  [2:0]   s1_knlo;         // (k_r - base')[2:0]
    reg  [1:0]   s1_wf2;          // first-valid-byte word pair m4first[4:3]
    // stage-1 comb outputs
    reg          t1_ge8hi;
    reg  [8:0]   t1_wbase;
    reg          t1_knpos, t1_knge8;
    reg  [2:0]   t1_knlo;
    // stage-1 comb: per-line terms (full 10ns budget, small fanout)
    reg  [12:0]  basep;
    reg  [3:0]   off_x;
    reg  [4:0]   m4first;
    always @* begin
        off_x    = dead_r ? 4'd0 : {1'b0, off_r};
        basep    = {1'b0, rj, 3'b000} + (13'd8 - {9'd0, off_x});
        m4first  = {1'b0, basep[3:0]}
                 + ((rj == 12'd0 && !dead_r) ? {2'b00, off_r} : 5'd0);
        t1_ge8hi = |basep[12:4];
        t1_wbase = {basep[11:4], 1'b0} - 9'd1;
        t1_knpos = ({2'b00, k_r} + 13'd8) > basep;
        t1_knge8 = {2'b00, k_r} >= basep;
        t1_knlo  = k_r[2:0] - basep[2:0];
    end
    // stage-2 comb: per-byte permutation (from s1 regs only)
    reg  [8:0]   t_wa_addr, t_wx_addr;
    reg  [63:0]  t_wa_we,   t_wx_we;
    reg  [511:0] t_wa_din,  t_wx_din;
    reg          t_wa_go,   t_wx_go;
    reg  [4:0]   m4;
    integer bi;
    // V3.9 (2026-10-14) GATHER-FORM din.  Post-route cell census on the
    // V3.8 build: the scatter form below cost ~12K LUTs in the two din
    // cones (ra_din 7051 + pb_din 4988) -- a computed 6-bit index into a
    // 512-bit vector per source byte replicates decode+AND per byte.
    // The byte at lane L ALWAYS comes from source byte (L[2:0]-base4)&7
    // (inverse of the scatter map: m4[2:0]=(base4+bi)&7 => bi), so one
    // shared 512-bit rotator (~300 LUTs) feeds BOTH target words; lanes
    // with WE=0 are don't-care at the RAM (byte-WE masks them), and the
    // dead-row zero fill rides the s1_dead term.  Value-identical at
    // every WE=1 lane, proven from the V3.8 bijection identities.
    wire [511:0] s1_din_rot;
    genvar gl;
    generate
        for (gl = 0; gl < 64; gl = gl + 1) begin : g_rot
            localparam integer GI = gl;
            wire [2:0] bsel = GI[2:0] - s1_base4[2:0];
            assign s1_din_rot[8*gl +: 8] =
                s1_dead ? 8'h00 : s1_pd[8*bsel +: 8];
        end
    endgenerate
    always @* begin
        t_wa_addr = 9'd0;   t_wx_addr = 9'd0;
        t_wa_we   = 64'd0;  t_wx_we   = 64'd0;
        t_wa_din  = 512'd0; t_wx_din  = 512'd0;
        t_wa_go   = 1'b0;   t_wx_go   = 1'b0;
        m4 = 5'd0;
        if (s1_valid) begin
            t_wa_din = s1_din_rot;
            t_wx_din = s1_din_rot;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                m4 = {1'b0, s1_base4} + bi[3:0];
                if ((s1_ge8hi | m4[4] | m4[3]) &&
                    (s1_knpos && (s1_knge8 || (s1_knlo > bi[2:0])))) begin
                    if (m4[4:3] == s1_wf2) begin
                        t_wa_addr = s1_wbase + {7'd0, m4[4:3]};
                        t_wa_we[{s1_rr, m4[2:0]}]   = 1'b1;
                    end else begin
                        t_wx_addr = s1_wbase + {7'd0, m4[4:3]};
                        t_wx_we[{s1_rr, m4[2:0]}]   = 1'b1;
                    end
                end
            end
            t_wa_go = |t_wa_we;
            t_wx_go = |t_wx_we;
        end
    end

    // serve side comb
    wire        serve_drain = !w_beat_valid || w_beat_ready;
    wire        serve_issue = (st == ST_SERVE) && serve_drain;

    wire [511:0] wb_dout;
    m9_bm_wblk u_wblk (
        .clka  (clk),                          // input wire clka
        .ena   (ra_pend),                      // input wire ena
        .wea   (ra_we),                        // input wire [63 : 0] wea
        .addra (ra_addr),                      // input wire [8 : 0] addra
        .dina  (ra_din),                       // input wire [511 : 0] dina
        .douta (),                             // output wire [511 : 0] douta
        .clkb  (clk),                          // input wire clkb
        .enb   (pb_pend || serve_issue),       // input wire enb
        .web   (pb_pend ? pb_we  : 64'd0),     // input wire [63 : 0] web
        .addrb (pb_pend ? pb_addr : ka[10:3]), // input wire [8 : 0] addrb
        .dinb  (pb_pend ? pb_din : 512'd0),    // input wire [511 : 0] dinb
        .doutb (wb_dout)                       // output wire [511 : 0] doutb
    );

    wire pre_done_line = (rj == (jlines_r - 12'd1));

    // V3.4: line-request pacing credit.  The axi_rd_v3 line port has NO
    // ready -- it sim-fatals at 16 outstanding (LSQ depth).  Sustained
    // 1/cycle issue outruns the DDR round-trip, so the preload holds new
    // issues while (issued - responded) >= 12 -- the same pacing depth the
    // axi_rd_v3 unit gate was proven at (margin 4 under the LSQ).
    reg [4:0] inflight;
    wire      issue_ok   = (inflight < 5'd12);
    wire      issue_fire = (st == ST_PRE) && (ir < 4'd8) && !dead_i
                         && (ij < jlines_i) && issue_ok;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            preq_line <= 1'b0;
            w_beat_valid <= 1'b0;
            res_valid <= 1'b0;
            rd_pend <= 1'b0;
            ka <= 11'd0;
            ka_d <= 11'd0;
            pb_pend <= 1'b0;
            rb_i_reg <= 32'd0;
            rb_r_reg <= 32'd0;
        end else begin
            preq_line    <= 1'b0;                 // default pulse
            // w_beat_valid HOLDS until accepted (valid-ready law): the
            // beat register is only cleared on a drain; a stalled beat
            // is re-presented until w_beat_ready -- required because
            // the RAM output register only guarantees stability, not
            // re-capture, and downstream rdy can lag valid by a cycle
            if (w_beat_valid && w_beat_ready)
                w_beat_valid <= 1'b0;
            if (st != ST_SERVE) rd_pend <= 1'b0;  // no stray captures
            case (st)
            ST_IDLE: if (start) begin
                rc_r  <= rt_rc;
                k_r   <= rt_k;
                seg_r <= rt_seg_off;
                ka    <= 11'd0;
                inflight <= 5'd0;
                if (res_valid && (res_rc == rt_rc) && (res_seg == rt_seg_off)) begin
                    st <= ST_SERVE;                 // resident: no preload
                end else begin
                    ir <= 4'd0; ij <= 12'd0;
                    rr <= 4'd0; rj <= 12'd0;
                    rb_i_reg <= rb_entry;
                    rb_r_reg <= rb_entry;
                    st <= ST_PRE;
                end
            end
            // ---- preload: pipelined line fetch, row-major ----
            ST_PRE: begin
                // issue side: dead rows skip entirely (response side
                // zero-fills); live rows issue one line per cycle
                if (ir < 4'd8) begin
                    if (dead_i) begin
                        ir <= ir + 4'd1;            // whole dead row, 1 cyc
                        rb_i_reg <= rb_i_reg + cfg_oc_stride;
                    end else if ((ij < jlines_i) && issue_ok) begin
                        paddr_line <= line_addr;
                        preq_line  <= 1'b1;
                        if (ij == jlines_i - 12'd1) begin
                            ij <= 12'd0;
                            ir <= ir + 4'd1;
                            rb_i_reg <= rb_i_reg + cfg_oc_stride;
                        end else
                            ij <= ij + 12'd1;
                    end
                end
                // response side: walks EVERY (row, line) pair.  Dead
                // rows self-advance (zero fill through the write map,
                // dead_r selects 8'h00 data and off_x=0); live rows
                // consume in-order pvalid_line beats.  V3.8 two-stage
                // pipeline: this response's line terms + data are
                // captured into stage-1 regs; the PREVIOUS line's map
                // is drained into ra_*/pb_* FIRST (before this edge's
                // s1 reload clobbers it), so back-to-back responses
                // sustain 1/cycle.  RAM port A fires the cycle after
                // the drain; a phase-B tail flushes on port B the same
                // cycle (A and B ports are independent).
                // stage-2 drain (must precede the stage-1 capture below:
                // both sample/write s1 on the same edge, last write wins)
                if (s1_valid) begin
                    ra_addr <= t_wa_addr;
                    ra_we   <= t_wa_we;
                    ra_din  <= t_wa_din;
                    ra_pend <= t_wa_go;
                    pb_addr <= t_wx_addr;
                    pb_we   <= t_wx_we;
                    pb_din  <= t_wx_din;
                    pb_pend <= t_wx_go;
                    s1_valid <= 1'b0;
                end else begin
                    if (ra_pend) ra_pend <= 1'b0;   // port-A write drained
                    if (pb_pend) pb_pend <= 1'b0;   // port-B flush drained
                end
                // stage-1 capture at response.  rr<8 gate (carried from
                // the V3.6 comb contract): dead_r stays true past row 7,
                // so without it dead-row self-advance would recapture
                // s1 every cycle, hold ra_pend at 1, and block the exit
                // while rr ran away (caught by wf3l W2 probe).
                if ((rr < 4'd8) && ((dead_r) || (pvalid_line))) begin
                    s1_valid <= 1'b1;
                    s1_pd    <= pdata_line;
                    s1_dead  <= dead_r;
                    s1_rr    <= rr[2:0];
                    s1_base4 <= basep[3:0];
                    s1_ge8hi <= t1_ge8hi;
                    s1_wbase <= t1_wbase;
                    s1_knpos <= t1_knpos;
                    s1_knge8 <= t1_knge8;
                    s1_knlo  <= t1_knlo;
                    s1_wf2   <= m4first[4:3];
                    if (pre_done_line) begin
                        rj <= 12'd0;
                        rr <= rr + 4'd1;
                        rb_r_reg <= rb_r_reg + cfg_oc_stride;
                    end else
                        rj <= rj + 12'd1;
                end
                // done when the response cursor has left the last line
                // of row 7 AND every pending stage (line terms, port-A
                // write, port-B tail) has drained -- the serve FSM
                // reads port B, so it cannot start earlier
                if ((rr == 4'd8) && !pb_pend && !ra_pend && !s1_valid) begin
                    res_valid <= 1'b1;
                    res_rc    <= rc_r;
                    res_seg   <= seg_r;
                    st <= ST_SERVE;
                end
                // V3.4 pacing credit update (issue and response can land
                // in the same cycle -> net zero)
                case ({issue_fire, pvalid_line})
                    2'b10:   inflight <= inflight + 5'd1;
                    2'b01:   inflight <= inflight - 5'd1;
                    default: ;
                endcase
            end
            // ---- serve: pipelined RAM read, 1 beat/k, ready-gated ----
            // The IP's port-B output register holds wb_dout stable until
            // the next read completes, making it a lossless 1-deep skid:
            // a new address is issued only while the previous beat is
            // being (or has been) drained, so a bus stall can never
            // clobber data still on the output pins.
            ST_SERVE: begin
                if (rd_pend && serve_drain) begin
                    // load the word addressed by ka (one read-latency
                    // ago) into the beat register; valid holds until
                    // the drain below clears it
                    w_beat_data  <= beat_sel(wb_dout, ka_d[2:0]);
                    w_beat_first <= (ka_d == 11'd0);
                    w_beat_valid <= 1'b1;
                    rd_pend      <= 1'b0;
                end
                // last beat drained -> done (V3.2 law: advance only on
                // actual presentation)
                if (w_beat_valid && w_beat_ready &&
                    (ka_d == k_r - 11'd1))
                    st <= ST_DONE;
                if (serve_issue) begin
                    rd_pend <= 1'b1;
                    ka_d    <= ka;
                    if (ka != k_r - 11'd1) ka <= ka + 11'd1;
                end
            end
            ST_DONE: st <= ST_IDLE;               // done is a 1-cycle pulse
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
