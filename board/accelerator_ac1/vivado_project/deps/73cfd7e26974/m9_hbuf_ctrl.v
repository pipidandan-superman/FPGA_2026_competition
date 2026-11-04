/************************************************************************
 * File Name       : m9_hbuf_ctrl.v
 * Developer       : M10.1 layer_chain line
 * Date            : 2026-10-14
 * Project Name    : YOLO object accel (M10.1-v2 phase 2b,
 *                   2026-10-14_yolo_m10p1_v2b_run01)
 * Module Name     : m9_hbuf_ctrl
 * Description     :
 *   Layer-chain handoff buffer controller, v2 (edge table + slot table,
 *   SPEC_layer_chain_v2.md §3.1/3.3, ABI v2.2 §8).  Sibling-composition
 *   law: every frozen core stays BYTE-IDENTICAL; this module is a pure
 *   adapter-level add-on (m9_intra_axi_top_v3 V3.2).  The v1 single-
 *   chain path (CHAIN_MASK 0x58, NEDGE=0) is kept cycle/byte identical.
 *
 *   V1 recap (single chain):
 *     producer conv(i-1) Y byte writes (y_scatter port tap, pure
 *     observe) -> in-window bytes also written into HBUF (m9_bm_hbuf
 *     BMG TDP 4096x64, byte-write A port per m9_bm_wblk precedent)
 *     -> consumer conv(i) X line reads served from HBUF B port when
 *     CHAIN_MASK[conv_idx]=1 (routing mux in the adapter else never
 *     reaches this module).  slot_base auto-captured from first armed
 *     Y write; window = addr[31:15] == slot_base[31:15]; watermark
 *     credit gate; E_CHAIN_OVF=11 report-only sticky on out-of-window
 *     serves.  Chain base translation law (v2 增补契约): reads arrive
 *     ALREADY translated into Y space by the adapter.
 *
 *   V2 additions (EDGE_CNT = CHAIN_NEDGE 0xD0 > 0, sampled at doorbell):
 *     - CHAIN_EDGE table (spec §3.1): entry s = {consumer_idx[7:0],
 *       window_size[15:0]} + 2d producer field (0xD8[15:8]); producer =
 *       consumer_idx-1 (adjacent walk law §3.2-1) or explicit field-1
 *       (§5.1 branch).  One slot per UNIQUE PRODUCER (2d); consumers
 *       sharing a producer share the slot read-only (refcount = consumer
 *       count of the slot).
 *     - Slot table (spec §3.3): NSLOT=8 x {base, watermark, state};
 *       FREE -> ARM (producer conv active, base pending) -> CAP (base
 *       captured, watermark rising on in-window writes) -> SEAL
 *       (producer conv advanced; serve-ready) -> FREE (consumer conv
 *       advanced / next start).
 *     - Exact windows: in-window = (addr - base) < window_size
 *       (replaces the v1 32KB-page check in edge mode; the page check
 *       remains the v1 fallback at NEDGE=0).  All slot windows pack
 *       into one 32KB page by the compiler boxing law (§3.2-2), so the
 *       BMG index addr[14:3] stays collision-free across slots.
 *     - Walk serialization law (v1, T2 probe-proven: sc_done serializes
 *       conv drains): at most one producer captures and at most one
 *       consumer serves at any cycle, so the single BMG write/read
 *       session and the single 16-deep read queue are shared by all
 *       slots time-multiplexed.
 *     - Base capture law (unchanged): slot base = address of the
 *       producer's FIRST byte written while armed; compiler layout law
 *       (producer Y == consumer X volume == window_size at offset 0)
 *       makes [base, base+window) exact.
 *     - E_CHAIN_CFG=12 legality (reported here; frame reject synthesized
 *       by the adapter, frozen issuer untouched, same law as
 *       E_CHAIN_MASK=10): duplicate consumer_idx / node==0 /
 *       node>=nconv / NEDGE>NSLOT / window==0 / window>32KB.
 *
 *   Constraints: single chain per frame in v1 mode; edge mode <= NSLOT
 *   edges; producer slot 32KB-page packing; SEQ walk mode.  HBUF depth
 *   4096 words = 32KB.
 *
 * Dependencies    : m9_bm_hbuf (blk_mem_gen 8.4 TDP, .veo instantiation)
 * Revision History:
 *   - V1.0 (2026-10-14) : first release (M10.1 mechanism bring-up).
 *   - V2.0 (2026-10-14) : edge/slot tables (phase 2b, ABI v2.2 §8);
 *                         v1 path preserved byte-identical at NEDGE=0.
 *   - V2.1 (2026-10-14) : timing closure -- producer base/wm write port
 *                         pipelined through a 1-deep writeback register
 *                         (C02b build #1 worst path node_r->st_wm CE =
 *                         -0.485ns / 325 endpoints).  Protocol-invisible
 *                         by walk serialization; self-healing laws in the
 *                         slot-FSM comment.  Functionally byte-identical
 *                         (wm final value and serve coverage unchanged).
 *   - V2.2 (2026-10-14) : timing closure round 2 -- all per-cycle edge
 *                         decode precomputed at the start edge:
 *                         node_m1_r (producer idx = node-1 registers,
 *                         kills the subtract in every match loop) and
 *                         route_r (16-bit cons_route bitmap, chain_sel
 *                         becomes a register read).  Pure transforms of
 *                         start-sampled state; zero protocol change.
 *   - V2.3 (2026-10-14) : timing closure round 3 -- REVERTED.  Piped the
 *                         BMG write tap (wea/addra/dina) and moved the
 *                         chain ledger/ovf_err onto the rsp registers.
 *                         xsim 10/10 PASS (ledgers byte-identical) but
 *                         the build REGRESSED to wns -0.676 / 486 ep:
 *                         at 94.5% slice utilization the added pipe regs
 *                         worsened congestion (placement has no slack
 *                         to absorb even a few FF).  Lesson: with slice
 *                         util >~90%, timing closure moves to the impl
 *                         strategy (spread logic), not more pipelining.
 *   - V2.4 (2026-10-15) : phase 2d -- branch/residual (spec §5).  Edge
 *                         table gains an explicit producer field (CSR
 *                         0xD8[15:8]; 0 = adjacent-walk fallback, else
 *                         prod = field-1).  Slots become PRODUCER-keyed:
 *                         consumers sharing a producer map to ONE slot
 *                         (read-only window share; refcount = popcount of
 *                         the slot consumer bitmap).  Release = positional
 *                         max-consumer law: conv_idx > slot max consumer
 *                         (walk serialization makes it identical to
 *                         refcount==0 -- a per-serve decrement would be
 *                         WRONG: a consumer reads many beats across its
 *                         whole conv pass).  Same-producer-different-
 *                         window tables rejected (E_CHAIN_CFG=12; one
 *                         slot = one capture).  Degenerate exactness:
 *                         all-2b tables (prod field 0) rebuild the V2.2
 *                         slot assignment cycle/byte-identically.
 *   - V2.4a (2026-10-15): timing closure @50MHz -- the V2.4 comb builder
 *                         was a 23-level LUT chain (wns -1.278, 49
 *                         failing slot_*_r endpoints); replaced by a
 *                         start-sequenced FIXED 8-cycle sequential build
 *                         (snapshot at start, one edge/cycle, slot regs
 *                         sampled one cycle after the last edge commits).
 *                         Build result identical; 9-cycle latency is
 *                         architecturally invisible (walk reads slots only
 *                         after compute begins).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_hbuf_ctrl #(
    parameter integer NSLOT = 8
) (
    input  wire        clk            ,
    input  wire        rst_n          ,
    // ---- frame control ----
    input  wire        start          ,   // doorbell pulse (sample + clear)
    input  wire [15:0] cfg_chain_mask ,   // CSR 0x58 (v1 mode)
    input  wire [3:0]  cfg_nedge      ,   // CSR 0xD0 (v2 mode; 0 = v1)
    input  wire [63:0] edge_node      ,   // 8 x consumer_idx (CSR 0xD4/0xD8)
    input  wire [63:0] edge_prod      ,   // 2d: 8 x producer field (0=adj)
    input  wire [127:0] edge_win      ,   // 8 x window_size (CSR 0xD4/0xDC)
    input  wire [4:0]  cfg_nconv      ,   // legality bound (node < nconv)
    output wire        chain_any      ,   // v1: |mask_r  v2: NEDGE!=0
    output wire        chain_sel      ,   // read routed to HBUF this cycle
    input  wire [3:0]  conv_idx       ,   // issuer active conv (cons face)
    input  wire [3:0]  prod_conv      ,   // 2e-fix: DRAINED producer conv
                                          //   (capture/slot-FSM prod key;
                                          //   advances at the verified
                                          //   boundary close, not at the
                                          //   walk+ovl early crossing)
    // ---- Y write tap (observe-only on the y_scatter byte port) ----
    input  wire [31:0] yaddr          ,
    input  wire        yreq           ,
    input  wire [7:0]  ywdata         ,
    // ---- X line read face (chained requests only; pulse in, in-order) --
    input  wire [31:0] lr_addr        ,   // ALREADY translated to Y space
    input  wire        lr_req         ,
    output wire [63:0] lr_data        ,
    output wire        lr_valid       ,
    // ---- DDR line queue guard (adapter counts u_xrd outstanding) ----
    input  wire        ddr_q_empty    ,
    // ---- ledger / error ----
    output reg  [31:0] cnt_chain_bytes,   // CSR 0x5C (+8/serve both modes)
    output reg         ovf_err        ,   // E_CHAIN_OVF=11 sticky
    output reg         cfg_err        ,   // E_CHAIN_CFG=12 sticky (report)
    // ---- 2e credit-gated release (SPEC §7) ----
    output wire        chain_go       ,   // consumer conv credits OK (early
                                          //   release gate for the issuer)
    output reg  [31:0] skew_max         // CSR 0xE8: max unconsumed captured
                                          //   bytes behind the consumer head
,
    output reg         join_cfg_err      // 5b: E_CHAIN_JOIN=13 sticky (non-
                                          //   adjacent duplicate consumer =
                                          //   malformed concat join)
,
    // ---- r7 debug aperture (2026-10-16): pure-observation slot-FSM /
    //      capture / serve telemetry, read on the board via the CSR
    //      cursor pair 0xF8 (select) / 0xFC (data).  Own registers
    //      below; ZERO fanout into any logic (observation-only law). ----
    output reg  [255:0] hb_dbg
);

    localparam HBUF_AW = 12;               // 4096 words x 8B = 32KB
    localparam [1:0] ST_FREE  = 2'd0;
    localparam [1:0] ST_ARM   = 2'd1;      // producer active, base pending
    localparam [1:0] ST_CAP   = 2'd2;      // base captured, watermark rising
    localparam [1:0] ST_SEAL  = 2'd3;      // producer drained, serve-ready

    // ---------------- sampled config (doorbell edge) ----------------
    reg [15:0] mask_r;
    reg [3:0]  nedge_r;
    // per-EDGE sampled table (legality probe face)
    reg [7:0]  node_r  [0:NSLOT-1];
    reg [7:0]  eprod_r [0:NSLOT-1];
    reg [15:0] win_r   [0:NSLOT-1];
    // per-SLOT derived map (2d producer-keyed; V2.2 degenerate-exact:
    // all-fallback tables rebuild slot i == edge i with prod = node-1,
    // single-bit consumer mask, maxc = node -- every FSM condition below
    // evaluates identically to V2.2's node_m1_r/node_r decode)
    reg [3:0]  nslot_r;
    reg [3:0]  slot_prod_r  [0:NSLOT-1];
    reg [15:0] slot_win_r   [0:NSLOT-1];
    reg [15:0] slot_cmask_r [0:NSLOT-1];  // consumers served by this slot
    reg [3:0]  slot_maxc_r  [0:NSLOT-1];  // max consumer (release law)
    reg [15:0] route_r;                 // cons_route bitmap precomputed
    integer si;
    // cons_route bitmap: route_n[c] = (c appears in the raw edge table).
    // Pure function of the start-sampled table; the per-cycle chain_sel
    // collapses to a register read.
    integer rc;
    reg [15:0] route_n;
    always @(*) begin
        route_n = 16'd0;
        for (rc = 0; rc < NSLOT; rc = rc + 1)
            if (rc < cfg_nedge)
                route_n[edge_node[rc*8 +: 4]] = 1'b1;
    end

    // ---- 2d slot-map builder (V2.4a: start-sequenced 8-cycle build) ----
    // Effective producer per edge: explicit field (low-nibble val-1) or
    // adjacent fallback (node-1).  Slot = unique effective producer in
    // first-appearance order; consumers sharing a producer map to the
    // SAME slot (spec §5.1 read-only window share; refcount = popcount of
    // the slot's consumer bitmap).  Window comes from the group's first
    // edge -- the adapter/hbuf legality has already rejected same-
    // producer-different-window tables, and a rejected frame never runs.
    //
    // V2.4a timing rework (2026-10-15): the V2.4 start-edge COMB builder
    // was a 23-level LUT chain out of the cfg regs (wns -1.278 @50MHz,
    // 49 failing endpoints, every one a slot_*_r capture).  The build
    // inputs are frozen by the arm-last law from the last edge write to
    // the doorbell, so the builder now runs as a FIXED 8-cycle sequential
    // pass after start -- one edge per cycle, <=5-level comb per step --
    // and the slot regs are sampled one cycle after the last edge commits.
    // The walk FSM reads slot_*_r/nslot_r only after compute begins
    // (>=1000 beats later), so the 9-cycle build latency is
    // architecturally invisible.  Build result is cycle/byte IDENTICAL to
    // the V2.4 comb builder (same first-appearance order, same updates).
    reg [7:0]  snap_node [0:NSLOT-1];
    reg [7:0]  snap_prod [0:NSLOT-1];
    reg [15:0] snap_win  [0:NSLOT-1];
    reg [3:0]  snap_nedge;
    reg        bld_run;
    reg [3:0]  bld_cnt;
    reg        bld_done;
    reg [3:0]  bk_nslot;
    reg [3:0]  bk_sprod  [0:NSLOT-1];
    reg [15:0] bk_swin   [0:NSLOT-1];
    reg [15:0] bk_smask  [0:NSLOT-1];
    reg [3:0]  bk_smaxc  [0:NSLOT-1];
    // per-cycle effective producer of edge[bld_cnt] vs slots built so far
    wire [3:0] bld_prod = (snap_prod[bld_cnt] != 8'd0)
                          ? (snap_prod[bld_cnt][3:0] - 4'd1)
                          : (snap_node[bld_cnt][3:0] - 4'd1);
    integer ms;
    reg        bld_found;
    reg [3:0]  bld_tgt;
    always @(*) begin
        bld_found = 1'b0;
        bld_tgt   = 4'd0;
        for (ms = 0; ms < NSLOT; ms = ms + 1)
            if (!bld_found && (ms[3:0] < bk_nslot) &&
                (bk_sprod[ms] == bld_prod)) begin
                bld_found = 1'b1;
                bld_tgt   = ms[3:0];
            end
    end
    wire bld_last = (bld_cnt == 4'd7);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bld_run <= 1'b0; bld_cnt <= 4'd0; bld_done <= 1'b0;
            snap_nedge <= 4'd0; bk_nslot <= 4'd0;
            for (si = 0; si < NSLOT; si = si + 1) begin
                snap_node[si] <= 8'd0;
                snap_prod[si] <= 8'd0;
                snap_win[si]  <= 16'd0;
                bk_sprod[si] <= 4'hF;        // invalid marker (never matches)
                bk_swin[si]  <= 16'd0;
                bk_smask[si] <= 16'd0;
                bk_smaxc[si] <= 4'd0;
            end
        end else if (start) begin
            // snapshot the frozen cfg (arm-last law) and launch the build
            bld_run    <= 1'b1;
            bld_cnt    <= 4'd0;
            bld_done   <= 1'b0;
            snap_nedge <= cfg_nedge;
            bk_nslot   <= 4'd0;
            for (si = 0; si < NSLOT; si = si + 1) begin
                snap_node[si] <= edge_node[si*8 +: 8];
                snap_prod[si] <= edge_prod[si*8 +: 8];
                snap_win[si]  <= edge_win[si*16 +: 16];
                bk_sprod[si] <= 4'hF;
                bk_swin[si]  <= 16'd0;
                bk_smask[si] <= 16'd0;
                bk_smaxc[si] <= 4'd0;
            end
        end else if (bld_run) begin
            bld_done <= bld_last;
            if (bld_last) bld_run <= 1'b0;
            else          bld_cnt <= bld_cnt + 4'd1;
            if (bld_cnt < snap_nedge) begin
                if (bld_found) begin
                    bk_smask[bld_tgt][snap_node[bld_cnt][3:0]] <= 1'b1;
                    if (snap_node[bld_cnt][3:0] > bk_smaxc[bld_tgt])
                        bk_smaxc[bld_tgt] <= snap_node[bld_cnt][3:0];
                end else begin
                    bk_sprod[bk_nslot] <= bld_prod;
                    bk_swin[bk_nslot]  <= snap_win[bld_cnt];
                    bk_smask[bk_nslot] <= (16'd1 << snap_node[bld_cnt][3:0]);
                    bk_smaxc[bk_nslot] <= snap_node[bld_cnt][3:0];
                    bk_nslot           <= bk_nslot + 4'd1;
                end
            end
        end else begin
            bld_done <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_r <= 16'd0; nedge_r <= 4'd0; route_r <= 16'd0;
            nslot_r <= 4'd0;
            for (si = 0; si < NSLOT; si = si + 1) begin
                node_r[si]    <= 8'd0;
                eprod_r[si]   <= 8'd0;
                win_r[si]     <= 16'd0;
                slot_prod_r[si]  <= 4'd0;
                slot_win_r[si]   <= 16'd0;
                slot_cmask_r[si] <= 16'd0;
                slot_maxc_r[si]  <= 4'd0;
            end
        end else begin
            if (start) begin
                mask_r  <= cfg_chain_mask;
                nedge_r <= cfg_nedge;
                route_r <= route_n;
                for (si = 0; si < NSLOT; si = si + 1) begin
                    node_r[si]  <= edge_node[si*8 +: 8];
                    eprod_r[si] <= edge_prod[si*8 +: 8];
                    win_r[si]   <= edge_win[si*16 +: 16];
                end
            end
            // slot map sampled one cycle after the 8-cycle build finishes
            if (bld_done) begin
                nslot_r <= bk_nslot;
                for (si = 0; si < NSLOT; si = si + 1) begin
                    slot_prod_r[si]  <= bk_sprod[si];
                    slot_win_r[si]   <= bk_swin[si];
                    slot_cmask_r[si] <= bk_smask[si];
                    slot_maxc_r[si]  <= bk_smaxc[si];
                end
            end
        end
    end

    wire edge_mode = (nedge_r != 4'd0);

    // v1 single-chain derived index (V1.0 law, unchanged)
    reg [3:0] consumer_idx;
    integer   bi;
    always @(*) begin
        consumer_idx = 4'd0;
        for (bi = 0; bi < 16; bi = bi + 1)
            if (mask_r[bi] && (consumer_idx == 4'd0))
                consumer_idx = bi[3:0];
    end
    wire [3:0] producer_idx = consumer_idx - 4'd1;

    assign chain_any = edge_mode ? 1'b1 : (|mask_r);

    // ---------------- v2 legality (E_CHAIN_CFG=12 report) --------------
    // adapter latches this at start and synthesizes the reject frame
    // (frozen issuer untouched, same synthesized-done law as
    // E_CHAIN_MASK=10).  Regs are sampled at start and stable within
    // the frame, so one combinational pass is enough.
    // 2d additions: explicit producer field must satisfy producer <
    // consumer (walk-order; catches self-loops and forward refs) and
    // producer < nconv; edges sharing an effective producer must carry
    // the IDENTICAL window (one shared slot = one capture, spec §5.1).
    function [3:0] eff_prod;
        input [7:0] node;
        input [7:0] pfield;
        begin
            eff_prod = (pfield != 8'd0) ? (pfield[3:0] - 4'd1)
                                        : (node[3:0] - 4'd1);
        end
    endfunction
    integer li, lj, lk;
    reg legality_bad;
    reg join_bad;      // 5b: malformed-join class (E_CHAIN_JOIN=13)
    always @(*) begin
        legality_bad = (nedge_r > 4'd8);            // NSLOT=8
        join_bad     = 1'b0;
        for (li = 0; li < NSLOT; li = li + 1) begin
            if (li < nedge_r) begin
                if ((node_r[li] == 8'd0) ||
                    (node_r[li] >= {3'd0, cfg_nconv}))
                    legality_bad = 1'b1;
                if ((win_r[li] == 16'd0) || (win_r[li] > 16'd32768))
                    legality_bad = 1'b1;
                // 2d: explicit producer ordering + bounds (full 8-bit
                // field; the low-nibble map above is only trustworthy
                // once these pass)
                if ((eprod_r[li] != 8'd0) &&
                    (((eprod_r[li] - 8'd1) >= node_r[li]) ||
                     ((eprod_r[li] - 8'd1) >= {3'd0, cfg_nconv})))
                    legality_bad = 1'b1;
                // 5b/5d (M10.5): multi-edge consumer (concat join) RUN
                // law.  A consumer may occupy a RUN of >=1 consecutive
                // edges (run >=2 = join group; the compiler emits the
                // group's producer edges consecutively, lowest channel
                // segment first).  The old blanket duplicate-node
                // reject (2d era, one edge per consumer) lifted to an
                // adjacency law (5b, TWO adjacent edges) and now
                // generalizes to N-edge runs (5d delta #5: a >16-rc
                // producer spans several conv entries -- the single
                // prod_conv key law gives each entry its own slot --
                // so every entry owns one edge):
                //   (a) the same node reappearing after a DIFFERENT
                //       node's edge (two runs) = malformed join ->
                //       join_cfg_err (E_CHAIN_JOIN=13) instead of the
                //       generic cfg_err (12), so probes can tell a
                //       malformed join apart from the 2d reject
                //       classes.  Per-edge 2d checks (bounds/window/
                //       producer ordering) run unchanged on every edge.
                //   (b) within a run all effective producers must be
                //       DISTINCT -- a same-producer pair anywhere in
                //       the run keeps the 2d malformed-dup semantics
                //       (E_CHAIN_CFG=12, cfg_dup probe baseline
                //       preserved; the old adjacent-pair test is the
                //       N=2 case of this clause).
                for (lj = li + 1; lj < NSLOT; lj = lj + 1)
                    if ((lj < nedge_r) && (node_r[lj] == node_r[li])) begin
                        for (lk = li + 1; lk < lj; lk = lk + 1)
                            if ((lk < nedge_r) &&
                                (node_r[lk] != node_r[li]))
                                join_bad = 1'b1;
                        if (eff_prod(node_r[li], eprod_r[li])
                            == eff_prod(node_r[lj], eprod_r[lj]))
                            legality_bad = 1'b1;
                    end
            end
        end
        // 2d: shared-producer single-window law
        for (li = 0; li < NSLOT; li = li + 1)
            if (li < nedge_r)
                for (lj = li + 1; lj < NSLOT; lj = lj + 1)
                    if ((lj < nedge_r) &&
                        (eff_prod(node_r[li], eprod_r[li])
                         == eff_prod(node_r[lj], eprod_r[lj])) &&
                        (win_r[li] != win_r[lj]))
                        legality_bad = 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      cfg_err <= 1'b0;
        else if (start)  cfg_err <= 1'b0;
        else if (edge_mode && legality_bad)
            cfg_err <= 1'b1;   // sticky report (frame reject is adapter's)
    end

    // 5b: malformed-join sticky (separate code 13 so probes distinguish
    // it from the 2d reject classes folded into cfg_err=12)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      join_cfg_err <= 1'b0;
        else if (start)  join_cfg_err <= 1'b0;
        else if (edge_mode && join_bad)
            join_cfg_err <= 1'b1;
    end

    // ---------------- slot table (edge mode) -------------------------
    reg [1:0]  st_state [0:NSLOT-1];
    reg [31:0] st_base  [0:NSLOT-1];
    reg [31:0] st_wm    [0:NSLOT-1];
    // 5d timing fix (Track B, page-shared upper bound law): per-slot
    // registered window upper bound.  All slots share addr[31:15] (one
    // 32KB page, L11 packing law) and win <= 32768, so the window test
    // "base <= head < base+win" splits into page-eq + two 15-bit compares
    // on the registered bound, halving the read-path comb depth (r1-r3
    // WNS -0.7..-1.15ns, 100% of worst-400 paths in this chain).
    reg [14:0] st_hibound [0:NSLOT-1];  // min(base[14:0]+win, 32767)
    reg        st_hisat   [0:NSLOT-1];  // base+win >= 32768 -> no upper test

    // producer match: slot whose producer conv is the DRAINED producer
    // (2e-fix 2026-10-15).  conv_idx crosses the conv boundary EARLY in
    // walk+ovl (at the last block's fire), but the producer's tail
    // scatter keeps writing until its sc_done -- keying capture on
    // conv_idx sealed the slot wm-short (896/1024) and deadlocked the
    // consumer (t17).  prod_conv (issuer export) advances only at the
    // verified boundary close, so the tail writes are captured and the
    // slot seals full.  Walk serialization law: at most one match.
    integer pk;
    reg [3:0] prod_slot;
    reg       prod_act;
    always @(*) begin
        prod_slot = 4'd0; prod_act = 1'b0;
        for (pk = 0; pk < NSLOT; pk = pk + 1)
            if (!prod_act && (pk < nslot_r) &&
                ((st_state[pk] == ST_ARM) || (st_state[pk] == ST_CAP)) &&
                (prod_conv == slot_prod_r[pk])) begin
                prod_slot = pk[3:0];
                prod_act  = 1'b1;
            end
    end

    // arm: FREE slot whose producer conv just became the drained producer
    integer ak;
    reg [3:0] arm_slot;
    reg       arm_now;
    always @(*) begin
        arm_slot = 4'd0; arm_now = 1'b0;
        for (ak = 0; ak < NSLOT; ak = ak + 1)
            if (!arm_now && (ak < nslot_r) &&
                (st_state[ak] == ST_FREE) &&
                (prod_conv == slot_prod_r[ak])) begin
                arm_slot = ak[3:0];
                arm_now  = 1'b1;
            end
    end

    // consumer serve match: SEALED (or still-capturing -- 2e-fix: the
    // credit gate below paces reads by the watermark, so a CAP slot is
    // servable exactly to its wm; the SEAL requirement would re-serialize
    // the consumer behind the producer drain and defeat CHAIN_REL) slot
    // serving this conv (2d: the slot's consumer bitmap -- a shared
    // producer slot answers EVERY one of its consumers, refcount =
    // popcount of the bitmap)
    // 5b (M10.5): PER-READ slot resolution.  The 2d/2e match keyed on the
    // consumer alone (first cmask slot) cannot serve a concat join, whose
    // consumer owns TWO slots (A/B producer windows, disjoint 32KB pages).
    // The match is now keyed on the QUEUE-HEAD read address: the slot whose
    // window CONTAINS head_addr and whose consumer bitmap covers conv_idx.
    // Slot windows are page-disjoint, so the match is unique; a read whose
    // address falls in no live slot simply finds no match -> cons_act=0 ->
    // serve_e stalls (the v1 "no slot yet = STALL, never OVF" law carries
    // over verbatim: A-side reads arriving before A's capture, or B-side
    // reads before B's capture, both stall until their slot captures).
    // Out-of-window reads (translation mismatch) keep the zero-response +
    // E_CHAIN_OVF path via e_in_win below.
    // ---- read queue (declared ahead of the 5b per-read consumer match,
    // which keys on the queue-head address) ----
    reg [31:0] q_addr [0:15];
    reg [4:0]  q_wr, q_rd;
    reg [4:0]  q_cnt;
    wire       q_full  = (q_cnt == 5'd16);
    wire       q_empty = (q_cnt == 5'd0);
    wire [31:0] head_addr = q_addr[q_rd[3:0]];
    integer ck;
    reg [3:0] cons_slot;
    reg       cons_act;
    always @(*) begin
        cons_slot = 4'd0; cons_act = 1'b0;
        for (ck = 0; ck < NSLOT; ck = ck + 1)
            if (!cons_act && (ck < nslot_r) &&
                ((st_state[ck] == ST_SEAL) ||
                 (st_state[ck] == ST_CAP)) &&
                slot_cmask_r[ck][conv_idx] &&
                // Track B: registered page-shared bound (== the old
                // "(head_addr - st_base) < win" under the L11 one-page /
                // win<=32KB invariants, with wrap-below-base excluded by
                // the >= base test exactly as the unsigned wrap did)
                (head_addr[31:15] == st_base[ck][31:15]) &&
                (head_addr[14:0]  >= st_base[ck][14:0])  &&
                (st_hisat[ck] ||
                 (head_addr[14:0] < st_hibound[ck]))) begin
                cons_slot = ck[3:0];
                cons_act  = 1'b1;
            end
    end

    // 5b: consumer-level live-slot presence (address-agnostic) -- the
    // STALL gatekeeper.  A queued read for a consumer with NO live slot
    // stalls (v1 law); a read whose address fits no slot window takes the
    // zero-response + E_CHAIN_OVF path below.  cons_cred: ANY serving slot
    // of this consumer has data past its base -- the 2e chain_go semantics
    // generalized to multi-slot consumers.  Both MUST stay address-
    // agnostic: with an empty pull queue head_addr is garbage, and a
    // spurious miss would freeze the issuer's fire decision (deadlock).
    integer ak2;
    reg       cons_any;
    reg       cons_cred;
    always @(*) begin
        cons_any  = 1'b0;
        cons_cred = 1'b0;
        for (ak2 = 0; ak2 < NSLOT; ak2 = ak2 + 1)
            if ((ak2 < nslot_r) &&
                ((st_state[ak2] == ST_SEAL) ||
                 (st_state[ak2] == ST_CAP)) &&
                slot_cmask_r[ak2][conv_idx]) begin
                cons_any = 1'b1;
                if (st_wm[ak2] > st_base[ak2])
                    cons_cred = 1'b1;
            end
    end

    // 5d board fix (2026-10-15, err=11 spurious on silicon): cons_all_cap
    // -- EVERY slot serving this consumer has captured (CAP/SEAL).  A
    // no-window read may only take the zero-response + E_CHAIN_OVF=11 arm
    // once the frame's whole slot configuration for this consumer is
    // materialized; while any sibling slot is still FREE/ARM (base
    // pending), an unmatched in-page read is an OVERLAPPED PROLOGUE read
    // for that sibling (v1 law generalized to multi-slot cat consumers)
    // and must STALL, not zero-serve.  Board evidence: J04 frame=1 fired
    // err=11 at prog=48 (consumer's first block) -- the early-released
    // consumer raced to B-window reads while the B sibling slot was
    // uncaptured; xsim's 1-cycle DDR never opens that window.  The 5b
    // comment above already claimed "both stall until their slot
    // captures"; this fix makes the implementation match the claim.  The
    // spec ovf probe (all slots SEAL by its consumer pass) still reaches
    // the OVF arm -- the delay is a stall, not a semantics change.
    integer ak3;
    reg       cons_all_cap;
    always @(*) begin
        cons_all_cap = 1'b1;
        for (ak3 = 0; ak3 < NSLOT; ak3 = ak3 + 1)
            if ((ak3 < nslot_r) && slot_cmask_r[ak3][conv_idx] &&
                !((st_state[ak3] == ST_SEAL) ||
                  (st_state[ak3] == ST_CAP)))
                cons_all_cap = 1'b0;
    end

    // chain_sel (mode mux; v1 expression byte-identical).  Routing is a
    // pure function of the edge table + conv_idx -- NEVER of slot state:
    // reads arriving in the conv-switch/seal cycle must already queue in
    // the HBUF (v1 law), else they misroute to DDR and the frame reads
    // garbage.  The serve gate below (cons_act/credit) is what waits.
    // V2.2: the edge decode is precomputed into route_r at the start
    // edge, so the per-cycle path is a single register read.
    assign chain_sel = edge_mode ? route_r[conv_idx]
                                 : (chain_any && mask_r[conv_idx]);

    // 2e (SPEC §7.1): early-release credit export.  Pure function of the
    // sampled slot map + live slot state.  In the walk+ovl release window
    // conv_idx already indexes the CONSUMER node (the boundary crosses
    // before producer sc_done), so this is exactly credits(j); prefetch =
    // first block (SPEC §14.2 conservative: slot_valid 即放).  The serve
    // gate (watermark compare) is untouched -- per-line pacing stays the
    // only consumer-internal synchronization (§7.2 self-sync law).
    assign chain_go = edge_mode && route_r[conv_idx] && cons_cred;

    // slot FSM + capture (edge mode); v1 single-slot state below.
    // arm/capture/seal/release conditions are mutually exclusive per
    // slot within a cycle (arm: FREE & conv==slot_prod; capture: ARM/CAP
    // & conv==slot_prod; seal: ARM/CAP & conv>slot_prod; release: SEAL &
    // conv>slot_maxc).
    //
    // V2.1 timing closure (2026-10-14 C02b build: node_r->st_wm CE was the
    // -0.485ns / 325-endpoint worst class): the producer watermark/base
    // write port is pipelined through a 1-deep writeback register.  Walk
    // serialization guarantees at most one producer, hence one event in
    // flight; the consumer cannot serve until the producer drains (sc_done
    // law), so a 1-cycle table lag is protocol-invisible.  Self-healing
    // laws: (a) a CAP in flight blocks re-detect (cap_e gate) so the second
    // byte can never double-capture; its watermark catch-up is covered by
    // the third byte's WM event, and the final wm == base+window
    // regardless (bytes arrive in order, wm = last+1).  (b) a serve
    // evaluated one cycle early against a stale wm simply stalls (no pop,
    // no ledger side effect) and re-evaluates covered next cycle.
    reg        swb_we;      // producer event pending apply
    reg        swb_cap;     // 1 = CAP (base+wm+state), 0 = wm rise
    reg [3:0]  swb_slot;
    reg [31:0] swb_base;    // CAP: captured base
    reg [31:0] swb_wm;      // new watermark (yaddr+1)
    wire swb_pend = swb_we;
    // Track B: bound sum at capture time (17 bits: 32767 + 65535 max)
    wire [16:0] hb_sum = {2'b00, swb_base[14:0]} + {1'b0, slot_win_r[swb_slot]};

    wire cap_e = edge_mode && prod_act && yreq &&
                 (st_state[prod_slot] == ST_ARM) &&
                 !(swb_pend && swb_cap);   // no double-capture (a)
    wire wmr_e = edge_mode && prod_act && yreq &&
                 (st_state[prod_slot] == ST_CAP) &&
                 ((yaddr - st_base[prod_slot])
                  < {16'd0, slot_win_r[prod_slot]});

    integer fi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            swb_we <= 1'b0; swb_cap <= 1'b0; swb_slot <= 4'd0;
            swb_base <= 32'd0; swb_wm <= 32'd0;
        end else if (start) begin
            swb_we <= 1'b0; swb_cap <= 1'b0; swb_slot <= 4'd0;
            swb_base <= 32'd0; swb_wm <= 32'd0;
        end else begin
            swb_we   <= cap_e || wmr_e;
            swb_cap  <= cap_e;
            swb_slot <= prod_slot;
            swb_base <= yaddr;            // valid on cap_e only
            swb_wm   <= yaddr + 32'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (fi = 0; fi < NSLOT; fi = fi + 1) begin
                st_state[fi] <= ST_FREE;
                st_base[fi]  <= 32'd0;
                st_wm[fi]    <= 32'd0;
                st_hibound[fi] <= 15'd0;
                st_hisat[fi]   <= 1'b0;
            end
        end else if (start) begin
            for (fi = 0; fi < NSLOT; fi = fi + 1) begin
                st_state[fi] <= ST_FREE;
                st_base[fi]  <= 32'd0;
                st_wm[fi]    <= 32'd0;
                st_hibound[fi] <= 15'd0;
                st_hisat[fi]   <= 1'b0;
            end
        end else if (edge_mode) begin
            if (swb_pend) begin
                if (swb_cap) begin
                    st_base[swb_slot]  <= swb_base;
                    st_wm[swb_slot]    <= swb_wm;
                    st_state[swb_slot] <= ST_CAP;
                    st_hibound[swb_slot] <= (hb_sum >= 17'd32768)
                                            ? 15'h7FFF : hb_sum[14:0];
                    st_hisat[swb_slot]   <= (hb_sum >= 17'd32768);
                end else begin
                    st_wm[swb_slot]    <= swb_wm;
                end
            end
            if (arm_now)
                st_state[arm_slot] <= ST_ARM;
            for (fi = 0; fi < NSLOT; fi = fi + 1) begin
                if ((fi < nslot_r) && (st_state[fi] != ST_FREE)) begin
                    // seal when the DRAINED producer conv has advanced
                    // past (2e-fix: prod_conv, not conv_idx -- the latter
                    // crosses early in walk+ovl while the tail scatter
                    // is still writing; seal keyed on it cut the slot
                    // wm-short and deadlocked the consumer)
                    if ((st_state[fi] == ST_ARM || st_state[fi] == ST_CAP) &&
                        (prod_conv > slot_prod_r[fi]))
                        st_state[fi] <= ST_SEAL;
                    // release when EVERY consumer conv has advanced past
                    // (2d positional max-consumer law == refcount==0 by
                    // walk serialization; V2.2 degenerate: maxc = the
                    // single consumer; consumer-side key stays conv_idx:
                    // reads of consumer k are done once the walk has
                    // crossed past k, and the frame's fin pass re-verifies
                    // the last producer drain)
                    else if ((st_state[fi] == ST_SEAL) &&
                             (conv_idx > slot_maxc_r[fi]))
                        st_state[fi] <= ST_FREE;
                end
            end
        end
    end

    // ---------------- per-frame state (v1 single slot, unchanged) -----
    reg        arm_r;                    // v1 capture armed (conv seen)
    reg        slot_valid;
    reg [31:0] slot_base;
    reg [31:0] watermark;                // first not-yet-written address

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arm_r <= 1'b0; slot_valid <= 1'b0;
            slot_base <= 32'd0; watermark <= 32'd0;
        end else if (start) begin
            arm_r <= 1'b0; slot_valid <= 1'b0;
            slot_base <= 32'd0; watermark <= 32'd0;
        end else if (!edge_mode) begin
            if (!arm_r && (conv_idx == producer_idx))
                arm_r <= 1'b1;
            if (arm_r && !slot_valid && yreq) begin
                slot_base  <= yaddr;
                slot_valid <= 1'b1;
            end
            // hbuf_wr (below) covers the capture-cycle byte too
            if (yreq && ((slot_valid &&
                          (yaddr[31:15] == slot_base[31:15]))
                         || (!slot_valid && arm_r)))
                watermark <= yaddr + 32'd1;
        end
    end

    // ---------------- HBUF write port (both modes) --------------------
    // v1 capture cycle = the producer's very first byte (offset 0 law);
    // edge mode = any byte while a producer is active and in-page.
    // 2e-fix: the CAP branch is bounded by the EXACT window (not the
    // shared 32KB page) -- with the producer keyed on the drained conv,
    // a later producer's early writes (walk+ovl overlap) must not be
    // strobed into this slot's BMG region.
    wire v1_writing = !edge_mode &&
                      (yreq && ((slot_valid &&
                                 (yaddr[31:15] == slot_base[31:15]))
                                || (!slot_valid && arm_r)));
    wire e_writing  = edge_mode && prod_act && yreq &&
                      ((st_state[prod_slot] == ST_ARM) ||
                       ((yaddr - st_base[prod_slot])
                        < {16'd0, slot_win_r[prod_slot]}));
    wire        hbuf_wr = v1_writing || e_writing;
    wire [HBUF_AW-1:0] wr_word = yaddr[HBUF_AW+2:3];

    // byte-lane write strobe (byte-write law per m9_bm_wblk precedent)
    reg [7:0] wea;
    always @(*) begin
        wea = 8'h00;
        if (hbuf_wr)
            wea = 8'b0000_0001 << yaddr[2:0];
    end

    // ---------------- read queue (16 deep, in-order, shared) ----------

    // v1 window/cover (32KB page law, unchanged)
    wire        v1_head_in_win = slot_valid &&
                                 (head_addr[31:15] == slot_base[31:15]);
    wire        v1_head_covered = v1_head_in_win &&
                                  ({head_addr[31:3], 3'b000} + 32'd8
                                   <= watermark);
    // edge window/cover (Track B registered-bound law; identical to the
    // old unsigned-subtract test under the L11 one-page invariants)
    wire        e_in_win   = cons_act &&
                (head_addr[31:15] == st_base[cons_slot][31:15]) &&
                (head_addr[14:0]  >= st_base[cons_slot][14:0])  &&
                (st_hisat[cons_slot] ||
                 (head_addr[14:0] < st_hibound[cons_slot]));
    wire        e_covered  = e_in_win &&
                             ({head_addr[31:3], 3'b000} + 32'd8
                              <= st_wm[cons_slot]);

    wire head_in_win  = edge_mode ? e_in_win  : v1_head_in_win;
    wire head_covered = edge_mode ? e_covered : v1_head_covered;
    // serve one entry per cycle: covered reads go to the BMG, out-of-
    // window reads get a zero response (error already flagged).  No
    // slot yet (producer's first write pending / no sealed slot for
    // this consumer) = STALL, never OVF: overlapped prologue reads
    // legitimately arrive before capture (v1 law, kept for edge mode).
    // v1: serve_v1 is byte-identical to V1.0 (slot_valid && (covered ||
    // !in_win)); edge: cons_any && (e_covered || (!e_in_win &&
    // cons_all_cap)) -- 5d: the zero-response arm additionally requires
    // every sibling slot captured (cons_all_cap above), so an unmatched
    // read for an uncaptured sibling STALLS instead of spuriously
    // flagging E_CHAIN_OVF=11 on silicon (board J04 frame=1 prog=48).
    wire serve_v1 = !q_empty && slot_valid && ddr_q_empty &&
                    (v1_head_covered || !v1_head_in_win);
    wire serve_e  = !q_empty && cons_any && ddr_q_empty &&
                    (e_covered || (!e_in_win && cons_all_cap));
    wire serve    = edge_mode ? serve_e : serve_v1;

    // 2e telemetry (SPEC §7.4): SKEW_MAX = max over the frame of the
    // unconsumed captured bytes behind the consumer head, sampled at each
    // serve.  Cleared at the doorbell (clear_on_frame law).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         skew_max <= 32'd0;
        else if (start)     skew_max <= 32'd0;
        else if (serve_e && e_in_win &&
                 (st_wm[cons_slot] >= head_addr) &&
                 ((st_wm[cons_slot] - head_addr) > skew_max))
            skew_max <= st_wm[cons_slot] - head_addr;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_wr <= 5'd0; q_rd <= 5'd0; q_cnt <= 5'd0;
        end else if (start) begin
            q_wr <= 5'd0; q_rd <= 5'd0; q_cnt <= 5'd0;
        end else begin
            if (lr_req && !q_full) begin
                q_addr[q_wr[3:0]] <= lr_addr;
                q_wr <= q_wr + 5'd1;
            end
            if (serve) begin
                q_rd <= q_rd + 5'd1;
            end
            case ({lr_req && !q_full, serve})
            2'b10: q_cnt <= q_cnt + 5'd1;
            2'b01: q_cnt <= q_cnt - 5'd1;
            default: q_cnt <= q_cnt;
            endcase
        end
    end

`ifndef SYNTHESIS
    // 5d F3: the enqueue-drop (lr_req && q_full) is STRUCTURALLY
    // UNREACHABLE, not just guarded -- proven burst/depth invariant:
    //   (1) x_window issues at most n_lines<=5 requests per tap burst
    //       (m9_x_window_v3 sim-fatal on span>5 lines, L156/L392);
    //   (2) bursts are serialized with full drain between them
    //       (ST_LINE waits rcnt==n_lines before the next tap);
    //   (3) the issuer runs ONE consumer conv at a time, so a single
    //       16-deep queue serves one burst stream.
    // Hence q_cnt <= 5 at any lr_req and the drop arm of the enqueue
    // is defensive dead code.  This assertion converts it from a
    // SILENT drop into a LOUD sim failure if the invariant is ever
    // broken by a future change (bigger bursts / second requester).
    always @(posedge clk) begin
        if (rst_n && lr_req && q_full)
            $fatal(1, "M9HBUF_FAIL read-queue drop: lr_req at q_full (burst/depth invariant broken)");
    end
`endif

    // ---------------- response pipe (1 deep) --------------------------
    reg        rsp_valid_r, rsp_zero_r;
    wire       bmb_rd = serve && head_in_win;   // BMG B-port read strobe
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid_r <= 1'b0; rsp_zero_r <= 1'b0;
        end else if (start) begin
            rsp_valid_r <= 1'b0; rsp_zero_r <= 1'b0;
        end else begin
            rsp_valid_r <= serve;
            rsp_zero_r  <= serve && !head_in_win;
        end
    end

    // ---------------- error + ledger ----------------------------------
    // CHAIN_CNT = DELIVERED bytes (ABI v2.1 0x5C "HBUF delivered"):
    // +8 per served line, zero-response OVF responses included (they
    // are delivered responses too).  Both modes share the ledger.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ovf_err <= 1'b0; cnt_chain_bytes <= 32'd0;
        end else if (start) begin
            ovf_err <= 1'b0; cnt_chain_bytes <= 32'd0;
        end else begin
            if (serve && !head_in_win)
                ovf_err <= 1'b1;             // E_CHAIN_OVF=11 (report-only)
            if (serve)
                cnt_chain_bytes <= cnt_chain_bytes + 32'd8;
        end
    end

    // ---------------- r7 debug aperture (observation-only) ------------
    // Counters latch WHY the capture path stayed silent on silicon
    // (board J04 err=11 probe: skew=0 + all-zero serves).  One always
    // block, own regs, no fanout into logic.  Word map (cursor 0..7):
    //   0 {8'd0, st_state[7..0] (2b ea), 4'd0, nslot_r}
    //   1 {arm_cnt[15:0], cap_cnt[15:0]}
    //   2 slot_prod_r[0..7] packed 4b ea
    //   3 first_cap_yaddr (0 if never captured)
    //   4 {8'd0, last_cap_slot, first_cap_slot, cap_mask, arm_mask}
    //   5 serve_hit_cnt (serve && head_in_win)
    //   6 serve_miss_cnt (serve && !head_in_win)
    //   7 {yreq_prod_cnt[15:0], cap_try_cnt[15:0]}
    reg [15:0] dbg_arm_cnt, dbg_cap_cnt, dbg_yreq_cnt, dbg_captry_cnt;
    reg [31:0] dbg_hit_cnt, dbg_miss_cnt;
    reg [31:0] dbg_first_cap_yaddr;
    reg [7:0]  dbg_arm_mask, dbg_cap_mask;
    reg [3:0]  dbg_first_cap_slot, dbg_last_cap_slot;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_arm_cnt <= 16'd0; dbg_cap_cnt <= 16'd0;
            dbg_yreq_cnt <= 16'd0; dbg_captry_cnt <= 16'd0;
            dbg_hit_cnt <= 32'd0; dbg_miss_cnt <= 32'd0;
            dbg_first_cap_yaddr <= 32'd0;
            dbg_arm_mask <= 8'd0; dbg_cap_mask <= 8'd0;
            dbg_first_cap_slot <= 4'd0; dbg_last_cap_slot <= 4'd0;
        end else if (start) begin
            dbg_arm_cnt <= 16'd0; dbg_cap_cnt <= 16'd0;
            dbg_yreq_cnt <= 16'd0; dbg_captry_cnt <= 16'd0;
            dbg_hit_cnt <= 32'd0; dbg_miss_cnt <= 32'd0;
            dbg_first_cap_yaddr <= 32'd0;
            dbg_arm_mask <= 8'd0; dbg_cap_mask <= 8'd0;
            dbg_first_cap_slot <= 4'd0; dbg_last_cap_slot <= 4'd0;
        end else begin
            if (arm_now) begin
                dbg_arm_cnt <= dbg_arm_cnt + 16'd1;
                dbg_arm_mask[arm_slot] <= 1'b1;
            end
            if (cap_e) begin
                dbg_cap_cnt <= dbg_cap_cnt + 16'd1;
                dbg_cap_mask[swb_slot] <= 1'b1;
                dbg_last_cap_slot <= swb_slot;
                if (dbg_cap_cnt == 16'd0) begin
                    dbg_first_cap_yaddr <= yaddr;
                    dbg_first_cap_slot <= swb_slot;
                end
            end
            if (yreq && prod_act) begin
                dbg_yreq_cnt <= dbg_yreq_cnt + 16'd1;
                if (st_state[prod_slot] == ST_ARM)
                    dbg_captry_cnt <= dbg_captry_cnt + 16'd1;
            end
            if (serve && head_in_win)  dbg_hit_cnt <= dbg_hit_cnt + 32'd1;
            if (serve && !head_in_win) dbg_miss_cnt <= dbg_miss_cnt + 32'd1;
        end
    end

    always @(*) begin
        hb_dbg = 256'd0;
        hb_dbg[3:0]     = nslot_r;
        hb_dbg[19:4]    = {st_state[7], st_state[6], st_state[5], st_state[4],
                           st_state[3], st_state[2], st_state[1], st_state[0]};
        hb_dbg[63:32]   = {dbg_arm_cnt, dbg_cap_cnt};
        hb_dbg[95:64]   = {slot_prod_r[7], slot_prod_r[6], slot_prod_r[5],
                           slot_prod_r[4], slot_prod_r[3], slot_prod_r[2],
                           slot_prod_r[1], slot_prod_r[0]};
        hb_dbg[127:96]  = dbg_first_cap_yaddr;
        hb_dbg[159:128] = {8'd0, dbg_last_cap_slot, dbg_first_cap_slot,
                           dbg_cap_mask, dbg_arm_mask};
        hb_dbg[191:160] = dbg_hit_cnt;
        hb_dbg[223:192] = dbg_miss_cnt;
        hb_dbg[255:224] = {dbg_yreq_cnt, dbg_captry_cnt};
    end

`ifndef SYNTHESIS
    // 5e debug: first-OVF state dump (err=11 root-cause instrumentation;
    // removed from synthesis by the guard, zero netlist impact).
    integer di;
    reg ovf_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ovf_seen <= 1'b0;
        else if (start) ovf_seen <= 1'b0;
        else if (serve && !head_in_win && !ovf_seen) begin
            ovf_seen <= 1'b1;
            $display("M9HBUF_OVF_DUMP t=%0t head=%h conv=%0d q_cnt=%0d any=%b act=%b allcap=%b em=%b nslot=%0d ddrq=%b",
                     $time, head_addr, conv_idx, q_cnt, cons_any, cons_act,
                     cons_all_cap, edge_mode, nslot_r, ddr_q_empty);
            for (di = 0; di < NSLOT; di = di + 1)
                $display("M9HBUF_OVF_SLOT %0d st=%0d base=%h wm=%h win=%0d hib=%0d hisat=%b cmask=%h prod=%0d",
                         di, st_state[di], st_base[di], st_wm[di],
                         slot_win_r[di], st_hibound[di], st_hisat[di],
                         slot_cmask_r[di], slot_prod_r[di]);
        end
    end
`endif

    // ---------------- HBUF (BMG TDP, .veo port-for-port) --------------
    wire [63:0] doutb;
    m9_bm_hbuf u_hbuf (
        .clka (clk),                        // input wire clka
        .ena  (1'b1),                       // input wire ena
        .wea  (wea),                        // input wire [7:0] wea
        .addra(wr_word),                    // input wire [11:0] addra
        .dina ({8{ywdata}}),                // input wire [63:0] dina
        .douta(),                           // output wire [63:0] douta
        .clkb (clk),                        // input wire clkb
        .enb  (bmb_rd),                     // input wire enb
        .web  (8'h00),                      // input wire [7:0] web
        .addrb(head_addr[HBUF_AW+2:3]),     // input wire [11:0] addrb
        .dinb (64'd0),                      // input wire [63:0] dinb
        .doutb(doutb)                       // output wire [63:0] doutb
    );

    assign lr_valid = rsp_valid_r;
    assign lr_data  = rsp_zero_r ? 64'd0 : doutb;

endmodule
