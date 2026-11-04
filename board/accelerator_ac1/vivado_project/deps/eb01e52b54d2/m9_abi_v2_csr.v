/************************************************************************
 * File Name       : m9_abi_v2_csr.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_abi_v2_csr
 * Description     :
 *   M9.5b ABI v2 CSR slave (02_m9_issuer_spec.md section 7 m9_intra_top
 *   bullet: CAP0/PLAN_BASE/ARENA_BASE/W_BASE/DOORBELL/progress RO).
 *   AXI4-Lite 32b from-face; the V2.5 wrapper instantiates it and it
 *   owns every PS-visible register.  Frame law (M9.5 gate):
 *
 *     setup : PS writes CFG and base registers + loads the plan BRAM
 *     frame : PS writes DOORBELL once -> start pulse -> zero PS
 *             until done (帧中零 PS 证明)
 *
 *   Register map (word offsets):
 *     0x00 CAP0      RO  32'h4D39_0220 ("M9" v2.2 BCD, M10.1-v2 2a ch_stride)
 *     0x04 PLAN_BASE RW  plan blob DDR base (台账 reference; the blob
 *                          body streams through the plan BRAM faces)
 *     0x08 ARENA_BASE RW -> cfg_xbase (x window HP0 read base)
 *     0x0C W_BASE    RW  -> cfg_wbase (w feeder HP3 read base)
 *     0x10 CFG0  RW  nb[9:0] rc[5:0]@10 ns[3:0]@16 nseg[1:0]@20 nconv[3:0]@24
 *     0x14 CFG1  RW  ic[15:0] h[15:0]@16
 *     0x18 CFG2  RW  w[15:0] kh[3:0]@16 kw[3:0]@20 sh[3:0]@24 sw[3:0]@28
 *     0x1C CFG3  RW  ph[3:0] pw[3:0]@4 first@8 law_fetch@9 overlap@10
 *                    oc[7:0]@16
 *     0x20 CFG4  RW  s0_k[10:0] s0_jc[7:0]@11 s0_g[1:0]@19
 *     0x24 CFG5  RW  stride
 *     0x28 CFG6  RW  obuf
 *     0x2C CFG7  RW  slab
 *     0x30 CFG8  RW  rc_stride
 *     0x34 CFG9  RW  oc_stride
 *     0x38 DOORBELL  WO  any write -> 1-cycle start pulse (reads 0)
 *     0x3C STATUS    RO  busy@0 done@1 err[7:0]@8
 *     0x40 PROGRESS  RO  progress_blk[11:0]
 *     0x44 CNT0      RO  cnt_beats[31:0] (widened from 19b, V1.1 below)
 *     0x48 CNT1      RO  cnt_csr_w[15:0] cnt_y_blocks[9:0]@16
 *     0x4C CNT2      RO  cnt_y_bytes[19:0]
 *     0x50 CNT3      RO  cnt_stall[31:0]
 *     0x54 TICK      RO  tick_cnt[31:0] (P2 clock probe)
 *     0x58 CHAIN_MASK RW cfg_chain_mask[15:0] (ABI v2.1 layer_chain;
 *                          bit i=1 -> conv i X from HBUF; sampled at the
 *                          doorbell-start edge by m9_hbuf_ctrl; bit0 /
 *                          multi-bit / non-walk rejected -> E_CHAIN_MASK=10)
 *     0x5C CHAIN_CNT  RO cnt_chain_bytes[31:0] (HBUF delivered bytes;
 *                          cleared at doorbell start, M10.1 ledger)
 *     0xCC CAP1      RO  32'h4D39_1000 | NSLOT (ABI v2.2 phase 2b edge/
 *                          slot-table capability; NSLOT=8 -> 0x4D39_1008)
 *     0xD0 CHAIN_NEDGE RW cfg_nedge[3:0] (edge count; 0 = v1 CHAIN_MASK
 *                          mode; sampled at doorbell start)
 *     0xD4 CHAIN_EDGE_IDX RW edge table cursor [3:0] (0..NEDGE-1)
 *     0xD8 CHAIN_EDGE_NODE RW {edge_prod,edge_node}[edge_idx] <=
 *                          wdata[15:0]  (2d: wdata[7:0]=consumer conv idx;
 *                          wdata[15:8]=producer field, 0 = adjacent-walk
 *                          fallback prod=node-1 (v1/2b superset face),
 *                          else prod = field-1 explicit (spec §5.1 branch:
 *                          one producer serving multiple consumers from a
 *                          shared read-only slot).  CAP1 UNCHANGED
 *                          0x4D39_1008 -- old drivers write [15:8]=0 ->
 *                          byte-identical 2b behaviour.)
 *     0xDC CHAIN_EDGE_WIN  RW edge_win[edge_idx] <= wdata[15:0]
 *                          (window_size bytes; compiler boxes all chained
 *                          producer slots into one 32KB page, spec §3.2;
 *                          2d law: edges sharing a producer MUST carry the
 *                          identical window -- one slot, one capture)
 *     ---- ABI v2.3 (M10.2 m8, DESIGN_m8_v23.md §1) ----
 *     0xE9 PPP_CURSOR  RW  ppp_cur[2:0] segment-table cursor (direct set
 *                          on write of data[2:0])
 *     0xEA PPP_DATA    RW  ppp_tab[ppp_cur] <= wdata, cursor auto-inc
 *                          modulo 8 (read: no inc, JOIN 0xF0/0xF4 law)
 *     0xEB LAYOUT_ID   RW  10 conv x 3 bit layout select vector; reset 0
 *                          = all-default = v1 semantics
 *     0xED CAP3        RO  32'h4D39_0A08 ([7:0]=8 PPP seg capacity,
 *                          [15:8]=10 LAYOUT conv limit, family 0x4D39)
 *     ---- G3 (M10.2 OVF 补盲, RUNBOOK_5d §11) ----
 *     0xE2 OVF_STAT  RO {15'd0, ovf_trig, ovf_tot[15:0]} / WO = re-arm
 *     0xE6 OVF_CUR   RW  ring read cursor [3:0] (direct set, PPP law)
 *     0xEE OVF_DATA  RO  ovf_ring[ovf_cur] (no auto-inc, JOIN law)
 *     0xEF reserved (v2.4 expansion, unassigned this batch)
 *     0x38 DOORBELL    WO  v2.3: wdata[7:0] = frame generation, latched
 *                          at the start pulse edge (frame_gen level +
 *                          frame_token pulse to the walker island)
 *
 *   All config writes land only in registers -- the engine samples them
 *   at the doorbell start edge (issuer start law), so mid-frame PS
 *   writes cannot disturb a running frame.
 *
 *   Handshake law (xsim native canon): B/R hold until accepted, no
 *   default clear; ready faces combinational on the outstanding state,
 *   so a slow PS master can never lose a beat.
 *
 *   Proven-core discipline: sibling module; changes no proven core.
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 *   - V1.1 (2026-10-13) : CNT0 (0x44) readback widened to the full 32-bit
 *     cnt_beats (m9_intra_top V1.6); small-count consumers unaffected
 *     (value identical, zero-extension was implicit).
 *   - V1.2 (2026-10-14) : ABI v2.1 layer_chain (M10.1): CHAIN_MASK 0x58
 *     RW + CHAIN_CNT 0x5C RO; CAP0 0x4D39_0200 -> 0x4D39_0210 (v2.1 BCD)
 *     -> 0x4D39_0220 (M10.1-v2 phase 2a, 2026-10-14: ch_stride decoupling
 *     silicon, new-silicon-new-criterion law).
 *     0x04-0x54 semantics byte-identical.
 *   - V1.3 (2026-10-14) : ABI v2.2 phase 2b edge table: CAP1 0xCC RO,
 *     CHAIN_NEDGE 0xD0 RW, CHAIN_EDGE_IDX 0xD4 RW (table cursor),
 *     CHAIN_EDGE_NODE 0xD8 / CHAIN_EDGE_WIN 0xDC index-indirect RW with
 *     readback.  tr_we aperture excludes 0xCC-0xDC; read mux gets
 *     explicit cases so the new window is not routed into the trace
 *     aperture by the >=0x60 default.  0x00-0x5C semantics identical.
 *   - V2.3 (2026-10-16) : M10.2 m8 ABI upgrade (DESIGN_m8_v23.md, five
 *     rulings CLOSED b8302bd1).  PPP segment table 8x1W (0xE9/0xEA
 *     cursor+data pair), LAYOUT_ID 10x3b (0xEB), CAP3 0xED RO
 *     0x4D39_0A08, CAP0 -> 0x4D39_0230.  DOORBELL wdata[7:0] = frame
 *     generation (frame_gen latch + frame_token pulse).  tr_we aperture:
 *     the whole (0xE8,0xF0) band is carved out (indirect word tables
 *     need clean write AND read sides; 0xE9-0xEF writes no longer fan
 *     the trace ring -- trace anchors go explicit events, G2 law).
 *     New state lives ONLY in the ppp/layout always block below
 *     (multi-driver single-block law, cfg_chain_rel/dbg_cur precedent).
 *     v1 path structurally identical with an empty table (first word
 *     opcode=0x00 EMPTY at reset).
 *   - V2.3+G3 (2026-10-16) : OVF AW-capture window 0xE2/0xE6/0xEE (16-deep
 *     rolling m2-AW-address ring, E_CHAIN_OVF rising-edge trigger latch,
 *     ring keeps rolling post-trigger; see RUNBOOK_5d §11).  Explicit
 *     read cases close the >=0x60 trace-default leak that used to expose
 *     ring-payload garbage at these orphan addresses.  Zero datapath
 *     fanout (observation-only law).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_abi_v2_csr (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- AXI4-Lite slave (PS GP face) ----
    input  wire [7:0]  s_awaddr      ,
    input  wire [2:0]  s_awprot      ,
    input  wire        s_awvalid     ,
    output wire        s_awready     ,
    input  wire [31:0] s_wdata       ,
    input  wire [3:0]  s_wstrb       ,
    input  wire        s_wvalid      ,
    output wire        s_wready      ,
    output reg  [1:0]  s_bresp       ,
    output reg         s_bvalid      ,
    input  wire        s_bready      ,
    input  wire [7:0]  s_araddr      ,
    input  wire [2:0]  s_arprot      ,
    input  wire        s_arvalid     ,
    output wire        s_arready     ,
    output reg  [31:0] s_rdata       ,
    output reg  [1:0]  s_rresp       ,
    output reg         s_rvalid      ,
    input  wire        s_rready      ,
    // ---- engine status/counters (RO face) ----
    input  wire        busy          ,
    input  wire        done          ,
    input  wire [7:0]  err           ,
    input  wire [11:0] progress_blk  ,
    input  wire [31:0] cnt_beats     ,
    input  wire [15:0] cnt_csr_w     ,
    input  wire [19:0] cnt_y_bytes   ,
    input  wire [9:0]  cnt_y_blocks  ,
    input  wire [31:0] cnt_stall     ,
    input  wire [31:0] cnt_chain_bytes,  // M10.1: HBUF delivered bytes
    // ---- 2e credit-gated release telemetry (SPEC §7.4) ----
    input  wire [31:0] s2l_cnt        ,  // CHAIN_S2L_CNT (issuer)
    input  wire [31:0] skew_max       ,  // CHAIN_SKEW_MAX (hbuf)
    // ---- r7 debug aperture: hbuf slot-FSM/capture/serve telemetry ----
    input  wire [511:0] hb_dbg        ,  // 8 words, cursor-selected
    output reg  [3:0]  dbg_cur        ,  // CSR 0xF8 (write=select/read=rb)
    // ---- G3 (M10.2): OVF AW-capture tap (m2 write master; observe-only,
    // zero fanout into any engine logic -- RUNBOOK_5d §11 补盲 CSR) ----
    input  wire        mon_awvalid   ,
    input  wire        mon_awready   ,
    input  wire [31:0] mon_awaddr    ,
    // ---- config outputs to the wrapper (sampled at start) ----
    output reg  [31:0] plan_base     ,
    output reg  [31:0] arena_base    ,
    output reg  [31:0] w_base        ,
    output reg  [9:0]  cfg_nb        ,
    output reg  [5:0]  cfg_rc        ,
    output reg  [3:0]  cfg_ns        ,
    output reg  [1:0]  cfg_nseg      ,
    output reg  [4:0]  cfg_nconv     ,
    output reg  [15:0] cfg_ic        ,
    output reg  [15:0] cfg_h         ,
    output reg  [15:0] cfg_w         ,
    output reg  [3:0]  cfg_kh        ,
    output reg  [3:0]  cfg_kw        ,
    output reg  [3:0]  cfg_sh        ,
    output reg  [3:0]  cfg_sw        ,
    output reg  [3:0]  cfg_ph        ,
    output reg  [3:0]  cfg_pw        ,
    output reg         cfg_first     ,
    output reg         cfg_law_fetch ,
    output reg         cfg_overlap   ,
    output reg  [7:0]  cfg_oc        ,
    output reg  [10:0] cfg_s0_k      ,
    output reg  [7:0]  cfg_s0_jc     ,
    output reg  [1:0]  cfg_s0_g      ,
    output reg  [31:0] cfg_stride    ,
    output reg  [31:0] cfg_obuf      ,
    output reg  [31:0] cfg_slab      ,
    output reg  [31:0] cfg_rc_stride ,
    output reg  [31:0] cfg_oc_stride ,
    output reg  [15:0] cfg_chain_mask,  // M10.1 ABI v2.1 (CSR 0x58)
    // ---- M10.1-v2 phase 2b edge table (ABI v2.2 0xD0-0xDC) ----
    output reg  [3:0]  cfg_nedge     ,  // CHAIN_NEDGE (0 = v1 mask mode)
    output reg  [63:0] cfg_edge_node ,  // 8 x consumer_idx[7:0]
    output reg  [63:0] cfg_edge_prod ,  // 2d: 8 x producer field[7:0]
    output reg  [127:0] cfg_edge_win ,  // 8 x window_size[15:0]
    output wire [639:0] cfg_join_tab ,   // 5b: 20-word join-region table (flat)
    // ---- M10.1-v2 phase 2e (ABI 0xE0, SPEC §7.5) ----
    output reg         cfg_chain_rel ,  // CHAIN_REL: 1 = credit-gated
    output reg  [15:0] cfg_up2x      ,  // 5b: CHAIN_UP2X producer bitmap
                                        //   release (sampled at start)
    // ---- ABI v2.3 (M10.2 m8, DESIGN_m8_v23.md §1/§2) ----
    output wire [255:0] cfg_ppp_tab  ,  // 8 x 32b PPP trigger table (flat,
                                        //   generate-sliced like cfg_join_tab)
    output wire [29:0]  cfg_layout_id,  // 10 conv x 3b layout select
    output reg  [7:0]   frame_gen    ,  // doorbell-latched frame generation
    output reg          frame_token  ,  // 1-cycle pulse with start (walker
                                        //   island latches its current_gen)
    // ---- doorbell start pulse ----
    output reg         start,
    output wire        tr_we,
    output wire [11:0] tr_waddr,
    output wire [31:0] tr_wdata,
    output wire [11:0] tr_raddr,
    input  wire [31:0] tr_rdata
);

    // ---------------- write path ----------------
    // Independent AW / W capture (board-proven canon: V2.4
    // yolo_axi_lite_slave.sv).  AXI4-Lite lets the master present AW and
    // W in DIFFERENT cycles; V1.0 gated both readies on aw_seen||w_seen,
    // demanding a same-cycle pair.  The PS GP0 auto protocol converter
    // staggers AW/W, so the first board write deadlocked the GP
    // interconnect and took down the whole PS (read channel unaffected,
    // CAP0/RO reads returned fine -- board_run01 stepB evidence).  The
    // xsim BFM happened to pair AW+W in one cycle, which is why every
    // gate stayed green.  New AW/W are blocked only while B is pending;
    // commit ordering (one register write per AW+W pair) is unchanged.
    reg        aw_seen, w_seen;
    reg [7:0]  aw_addr_q;
    reg [31:0] w_data_q;
    wire       wr_go   = aw_seen && w_seen;

    // Observe-only trace CSR aperture. Existing configuration decode is intact.
    // 2b: the edge-table window 0xCC-0xDC stays inside the CSR slave (the
    // trace block owns 0x60-0xC4 + ring payload and ignores these anyway;
    // exclusion kept for aperture cleanliness).
    // 5b (M10.5): carve 0xF0 (JOIN_CURSOR) / 0xF4 (JOIN_DATA) out of the
    // trace payload aperture (>0xE8) for the piecewise join-region table.
    // v2.3 (M10.2 m8): the WHOLE (0xE8,0xF0) band is carved out (DESIGN
    // §1.3-4) -- the six free slots 0xE9-0xEF now carry the PPP/LAYOUT
    // indirect word tables, which need clean write AND read sides.  New
    // aperture = [0x60,0xCB] U [0xDD,0xDF] U [0xF5,0xFF].  0xEE/0xEF
    // reserved-address write observation is lost with the band; trace
    // anchors go explicit events (G2 law).
    assign tr_we = wr_go && (aw_addr_q >= 8'h60) &&
                   ((aw_addr_q < 8'hCC) ||
                    ((aw_addr_q > 8'hDC) && (aw_addr_q < 8'hE0)) ||
                    (aw_addr_q > 8'hF4));
    assign tr_waddr = {4'd0, aw_addr_q};
    assign tr_wdata = w_data_q;
    assign tr_raddr = {4'd0, s_araddr};

    // ---------------- 2b edge table state ----------------------------
    // 2e fix (10-15 board ladder): cfg_chain_rel lives ENTIRELY in this
    // block.  It was ALSO reset in the main config block below -> two
    // always blocks driving one flop = Synth 8-6859 multi-driven; Vivado
    // dropped the 0xE0 write path (xsim scheduled the edge block last so
    // the TB passed -- classic sim/synth divergence).  Single driver now.
    reg [3:0]  edge_idx;
    // 5b join-region table: 4 regions x 5 words = 20 words, flat cursor.
    // Word layout per region i (words 5i..5i+4):
    //   5i+0 xj_lo  (X-plan byte offset of region start, after cfg_xbase)
    //   5i+1 xj_hi  (end exclusive; hi<=lo disables the region)
    //   5i+2 split  (A-side byte count; off<split -> A, else B)
    //   5i+3 yA_base (Y-space base of producer A's slot)
    //   5i+4 yB_base (Y-space base of producer B's slot)
    // Written via 0xF0 cursor + 0xF4 data (write auto-increments the
    // cursor, modulo 20).  Lives ONLY in this block (multi-drive law).
    reg [4:0]  join_cur;
    reg [31:0] join_tab [0:19];
    // 5b CHAIN_UP2X: per-conv producer bitmap (CSR 0xDE).  Driven as the
    // output reg directly in this block's reset/write FSM (multi-drive
    // law, same as cfg_chain_rel above).
    integer    ei;
    genvar     gj;
    generate for (gj = 0; gj < 20; gj = gj + 1) begin : G_JOINOUT
        assign cfg_join_tab[gj*32 +: 32] = join_tab[gj];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_idx      <= 4'd0;
            cfg_nedge     <= 4'd0;
            cfg_edge_node <= 64'd0;
            cfg_edge_prod <= 64'd0;
            cfg_edge_win  <= 128'd0;
            cfg_chain_rel <= 1'b0;
            cfg_up2x      <= 16'd0;
            join_cur      <= 5'd0;
            dbg_cur       <= 4'd0;   // r8 single-drive law: owned ONLY by
                                     // this block (0xF8 write below); the
                                     // main-block reset copy made it
                                     // multi-driven -> Vivado dropped the
                                     // 0xF8 path on silicon (r7 probe-dead
                                     // root cause, 10-16)
            for (ei = 0; ei < 20; ei = ei + 1)
                join_tab[ei] <= 32'd0;
        end else if (wr_go) begin
            case (aw_addr_q)
            8'hD0: cfg_nedge <= w_data_q[3:0];
            8'hD4: edge_idx  <= w_data_q[3:0];
            8'hF0: join_cur  <= w_data_q[4:0];
            8'hF4: begin
                join_tab[join_cur] <= w_data_q;
                join_cur <= (join_cur == 5'd19) ? 5'd0
                                                : join_cur + 5'd1;
            end
            8'hD8: begin
                for (ei = 0; ei < 8; ei = ei + 1)
                    if (edge_idx == ei[3:0]) begin
                        cfg_edge_node[ei*8 +: 8] <= w_data_q[7:0];
                        cfg_edge_prod[ei*8 +: 8] <= w_data_q[15:8];
                    end
            end
            8'hDC: begin
                for (ei = 0; ei < 8; ei = ei + 1)
                    if (edge_idx == ei[3:0])
                        cfg_edge_win[ei*16 +: 16] <= w_data_q[15:0];
            end
            // 2e (SPEC §7.5): CHAIN_REL mode bit; [31:1] reserved
            8'hE0: cfg_chain_rel <= w_data_q[0];
            // 5b (M10.5): CHAIN_UP2X per-conv producer bitmap: conv c's
            // scatter materializes the nearest-2x image into its slot
            // (4x bytes, block pitch = 4*stride).  0xDE sits in the
            // trace-carved 0xDD-0xDF gap (no PS decode collision).
            8'hDE: cfg_up2x <= w_data_q[15:0];
            // r7 debug aperture cursor (select word 0..7; readback at 0xF8)
            8'hF8: dbg_cur <= w_data_q[3:0];
            default: ;
            endcase
        end
    end

    reg        r_awready, r_wready;
    assign s_awready = r_awready;
    assign s_wready  = r_wready;

    // ---------------- v2.3 PPP / LAYOUT state ---------------------------
    // DESIGN_m8_v23.md §1.2/§2: 8-word trigger-scheduling table (1 word
    // per segment; payload addresses/geometry live in the PPU DESC slots
    // the word POINTS AT -- trigger/payload separation, §2.3 arithmetic)
    // + 10-conv x 3b layout vector.  Driven ONLY here (multi-driver
    // single-block law; cfg_chain_rel / dbg_cur precedent).  Reset =
    // all-zero table = every opcode 0x00 EMPTY = v1 structural identity
    // (T7 zero-leak basis); layout all-default = v1 semantics.
    //   W0 word layout (DESIGN §2.2):
    //     [3:0]   opcode   0x00 EMPTY sentinel (scan stops), 0x11 add,
    //                     0x12 xfer(cat), 0x13 maxpool5 (engine_mux codes)
    //     [8:4]   conv_node[4:0]  trigger point (issuer chain walk)
    //     [15:9]  desc_idx[6:0]   PPU DESC slot (walker direct dispatch)
    //     [16]    req_requant     trailing non-identity requant pass
    //     [17]    ppp_last        last segment of this conv_node (consumer
    //                     release anchor, SPPF 3-level ordering)
    //     [31:18] rsvd (write-ignored, read-zero; v2.4 capacity fields)
    reg [2:0]  ppp_cur;
    reg [31:0] ppp_tab [0:7];
    reg [29:0] layout_id;
    integer    pi;
    genvar     gp;
    generate for (gp = 0; gp < 8; gp = gp + 1) begin : G_PPPOUT
        assign cfg_ppp_tab[gp*32 +: 32] = ppp_tab[gp];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ppp_cur   <= 3'd0;
            layout_id <= 30'd0;
            for (pi = 0; pi < 8; pi = pi + 1)
                ppp_tab[pi] <= 32'd0;
        end else if (wr_go) begin
            case (aw_addr_q)
            // cursor direct-set (read/write both at ppp_cur; no inc)
            8'hE9: ppp_cur <= w_data_q[2:0];
            // data write: slot <= wdata, cursor auto-inc MOD 8 (7->0);
            // read does NOT inc (JOIN 0xF0/0xF4 same law)
            8'hEA: begin
                ppp_tab[ppp_cur] <= w_data_q;
                ppp_cur <= ppp_cur + 3'd1;
            end
            // 10 conv x 3b layout vector; [31:30] unwired (read drops)
            8'hEB: layout_id <= w_data_q[29:0];
            default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen <= 1'b0; w_seen <= 1'b0;
            r_awready <= 1'b1; r_wready <= 1'b1;
            aw_addr_q <= 8'd0; w_data_q <= 32'd0;
            s_bvalid <= 1'b0; s_bresp <= 2'd0;
            start <= 1'b0;
            frame_gen <= 8'd0;      // v2.3: doorbell generation latch
            frame_token <= 1'b0;    // v2.3: 1-cycle pulse with start
            plan_base <= 32'd0; arena_base <= 32'd0; w_base <= 32'd0;
            cfg_nb <= 10'd0; cfg_rc <= 6'd0; cfg_ns <= 4'd0;
            cfg_nseg <= 2'd0; cfg_nconv <= 5'd0;
            cfg_ic <= 16'd0; cfg_h <= 16'd0; cfg_w <= 16'd0;
            cfg_kh <= 4'd0; cfg_kw <= 4'd0; cfg_sh <= 4'd0;
            cfg_sw <= 4'd0; cfg_ph <= 4'd0; cfg_pw <= 4'd0;
            cfg_first <= 1'b0; cfg_law_fetch <= 1'b0; cfg_overlap <= 1'b0;
            cfg_oc <= 8'd0; cfg_s0_k <= 11'd0; cfg_s0_jc <= 8'd0;
            cfg_s0_g <= 2'd0; cfg_stride <= 32'd0; cfg_obuf <= 32'd0;
            cfg_slab <= 32'd0; cfg_rc_stride <= 32'd0; cfg_oc_stride <= 32'd0;
            cfg_chain_mask <= 16'd0;
            // cfg_chain_rel NOT here -- owned by the edge-table block
            // (single-driver law, see the 2e fix note above).
        end else begin
            start <= 1'b0;                       // doorbell = 1-cycle pulse
            frame_token <= 1'b0;                 // v2.3: same pulse law
            if (s_bvalid && s_bready) begin
                s_bvalid <= 1'b0;
                r_awready <= 1'b1; r_wready <= 1'b1;   // B done: reopen faces
            end
            if (s_awvalid && r_awready) begin
                aw_seen  <= 1'b1;
                aw_addr_q <= s_awaddr;
                r_awready <= 1'b0;
            end
            if (s_wvalid  && r_wready) begin
                w_seen   <= 1'b1;
                w_data_q <= s_wdata;
                r_wready <= 1'b0;
            end
            if (wr_go) begin
                aw_seen <= 1'b0; w_seen <= 1'b0;
                s_bresp <= 2'd0;                 // OKAY everywhere
                s_bvalid <= 1'b1;
                case (aw_addr_q)
                8'h04: plan_base    <= w_data_q;
                8'h08: arena_base   <= w_data_q;
                8'h0C: w_base       <= w_data_q;
                8'h10: begin
                    cfg_nb   <= w_data_q[9:0];
                    cfg_rc   <= w_data_q[15:10];
                    cfg_ns   <= w_data_q[19:16];
                    cfg_nseg <= w_data_q[21:20];
                    cfg_nconv<= w_data_q[28:24];
                end
                8'h14: begin
                    cfg_ic <= w_data_q[15:0];
                    cfg_h  <= w_data_q[31:16];
                end
                8'h18: begin
                    cfg_w  <= w_data_q[15:0];
                    cfg_kh <= w_data_q[19:16];
                    cfg_kw <= w_data_q[23:20];
                    cfg_sh <= w_data_q[27:24];
                    cfg_sw <= w_data_q[31:28];
                end
                8'h1C: begin
                    cfg_ph        <= w_data_q[3:0];
                    cfg_pw        <= w_data_q[7:4];
                    cfg_first     <= w_data_q[8];
                    cfg_law_fetch <= w_data_q[9];
                    cfg_overlap   <= w_data_q[10];
                    cfg_oc        <= w_data_q[23:16];
                end
                8'h20: begin
                    cfg_s0_k  <= w_data_q[10:0];
                    cfg_s0_jc <= w_data_q[18:11];
                    cfg_s0_g  <= w_data_q[20:19];
                end
                8'h24: cfg_stride    <= w_data_q;
                8'h28: cfg_obuf      <= w_data_q;
                8'h2C: cfg_slab      <= w_data_q;
                8'h30: cfg_rc_stride <= w_data_q;
                8'h34: cfg_oc_stride <= w_data_q;
                8'h58: cfg_chain_mask <= w_data_q[15:0];  // M10.1 v2.1
                // DOORBELL: v2.3 freezes wdata[7:0] = frame generation --
                // latched here (frame_gen level for the issuer island)
                // and pulsed (frame_token) for the walker island latch.
                // Old v2.2 drivers are already CAP0-gated (0x4D39_0230
                // mismatch -> refuse writes), no dual-write risk.
                8'h38: begin
                    start       <= 1'b1;
                    frame_gen   <= w_data_q[7:0];
                    frame_token <= 1'b1;
                end
                default: ;                       // RO/undefined: OKAY, no effect
                endcase
            end
        end
    end

    // ---------------- P2 clock probe (r5 tick patch) ----------------
    // 0x54 CNT4/TICK RO tick_cnt[31:0] -- free-running counter on the PL
    // aclk (= clk here).  Not part of any control or gate criterion; NOT
    // cleared by rst_n (soft reset law) -- only power-on/bitstream
    // download clears it (FF INIT=0).  0x00-0x50 semantics untouched.
    // ---------------- G3 OVF AW-capture (RUNBOOK_5d §11 补盲) ----------
    // Suspended-item deal: the 960B silicon-only OVF-sidecar writes have
    // only a post-hoc footprint (poison overwrite + fp_md5 9f064c35...);
    // the blind spot is the write-master ADDRESS STREAM.  This ring taps
    // the m2 AW channel (the only DDR write master, y_scatter path) and
    // latches the write pointer at the E_CHAIN_OVF (err=0x11) rising
    // edge.  The ring KEEPS ROLLING after the trigger (ovf_trig is only a
    // sticky marker), so software can reconstruct both the around-event
    // window (entries relative to the latched pointer) and, by polling
    // 0xEE at software pace, the whole post-OVF stream.  Addresses sit in
    // the CSR-owned free slots 0xE2/0xE6/0xEE (trace-aperture orphans
    // today: reads there accidentally return ring-payload garbage via the
    // >=0x60 default -- these explicit cases close that leak too).
    //   0xE2 OVF_STAT  RO {15'd0, ovf_trig, ovf_tot[15:0]}  WO=re-arm
    //   0xE6 OVF_CUR   RW  ring read cursor [3:0] (direct set, PPP law)
    //   0xEE OVF_DATA  RO  ovf_ring[ovf_cur] (no auto-inc, JOIN/PPP law)
    // Single always block owns every ovf_* reg (multi-drive law).
    reg        ovf_trig;
    reg [15:0] ovf_tot;
    reg [3:0]  ovf_wp, ovf_cur_q;
    reg [31:0] ovf_ring [0:15];
    reg [7:0]  err_d;
    wire       ovf_evt = (err == 8'h11) && (err_d != 8'h11);
    wire       ovf_push = mon_awvalid && mon_awready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ovf_trig  <= 1'b0;
            ovf_tot   <= 16'd0;
            ovf_wp    <= 4'd0;
            ovf_cur_q <= 4'd0;
            err_d     <= 8'd0;
        end else begin
            err_d <= err;
            if (ovf_evt)
                ovf_trig <= 1'b1;
            if (wr_go && (aw_addr_q == 8'hE2)) begin
                // re-arm: clear trigger + volume counter (ring/cursor
                // intentionally left intact for post-mortem reads)
                ovf_trig <= 1'b0;
                ovf_tot  <= 16'd0;
            end else if (ovf_push) begin
                ovf_ring[ovf_wp] <= mon_awaddr;
                ovf_wp           <= ovf_wp + 4'd1;
                if (ovf_tot != 16'hFFFF)
                    ovf_tot <= ovf_tot + 16'd1;
            end
            if (wr_go && (aw_addr_q == 8'hE6))
                ovf_cur_q <= w_data_q[3:0];
        end
    end

    reg [31:0] tick_cnt = 32'd0;
    always @(posedge clk) tick_cnt <= tick_cnt + 32'd1;

    // ---------------- read path ----------------
    // AR accepted only while no R pending; R holds until accepted.
    assign s_arready = ~s_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rvalid <= 1'b0; s_rdata <= 32'd0; s_rresp <= 2'd0;
        end else begin
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
            if (s_arvalid && s_arready) begin
                s_rresp   <= 2'd0;
                case (s_araddr)
                8'h00: s_rdata <= 32'h4D39_0230;  // v2.3 (M10.2 m8: PPP/LAYOUT)
                8'h04: s_rdata <= plan_base;
                8'h08: s_rdata <= arena_base;
                8'h0C: s_rdata <= w_base;
                8'h10: s_rdata <= {3'd0, cfg_nconv, 2'd0, cfg_nseg, cfg_ns,
                                   cfg_rc, cfg_nb};
                8'h14: s_rdata <= {cfg_h, cfg_ic};
                8'h18: s_rdata <= {cfg_sw, cfg_sh, cfg_kw, cfg_kh, cfg_w};
                8'h1C: s_rdata <= {3'd0, cfg_oc, 5'd0, cfg_overlap,
                                    cfg_law_fetch, cfg_first, cfg_pw, cfg_ph};
                8'h20: s_rdata <= {11'd0, cfg_s0_g, cfg_s0_jc, cfg_s0_k};
                8'h24: s_rdata <= cfg_stride;
                8'h28: s_rdata <= cfg_obuf;
                8'h2C: s_rdata <= cfg_slab;
                8'h30: s_rdata <= cfg_rc_stride;
                8'h34: s_rdata <= cfg_oc_stride;
                8'h38: s_rdata <= 32'd0;        // doorbell reads 0
                // STATUS pack: err MUST sit at [15:8] per ABI (busy@0
                // done@1 err[7:0]@8).  {20'd0, err, done, busy} is a
                // 30-bit expression -> err landed at [9:2] and every
                // (val>>8)&0xFF reader (TB + driver) saw only err[7:6]
                // = always 0 for codes 1..63 (latent since V1.0, found
                // by the M10.1 T4 probe 2026-10-14).  勘误.
                8'h3C: s_rdata <= {16'd0, err, 6'd0, done, busy};
                8'h40: s_rdata <= {20'd0, progress_blk};
                8'h44: s_rdata <= cnt_beats;
                8'h48: s_rdata <= {6'd0, cnt_y_blocks, cnt_csr_w};
                8'h4C: s_rdata <= {12'd0, cnt_y_bytes};
                8'h50: s_rdata <= cnt_stall;
                8'h54: s_rdata <= tick_cnt;    // P2 clock probe (r5)
                8'h58: s_rdata <= {16'd0, cfg_chain_mask}; // M10.1 RW face
                8'h5C: s_rdata <= cnt_chain_bytes;         // M10.1 RO ledger
                // ---- 2b edge table window (explicit: keep out of the
                // >=0x60 trace-aperture default below) ----
                8'hCC: s_rdata <= 32'h4D39_1008; // CAP1 | NSLOT=8 (unchanged)
                // 5b join-extension capability at 0xEC (explicit case
                // overrides the trace-ring default read, same law as
                // 0xE0-0xE8 above): 0x4D39_5J00, J = max join regions = 4
                8'hEC: s_rdata <= 32'h4D39_5400;
                // 5b join table readback (driver sets cursor via 0xF0 first;
                // reads do NOT auto-increment)
                8'hF4: s_rdata <= join_tab[join_cur];
                8'hD0: s_rdata <= {28'd0, cfg_nedge};
                8'hD4: s_rdata <= {28'd0, edge_idx};
                8'hD8: s_rdata <= {16'd0,
                                   cfg_edge_prod[edge_idx*8 +: 8],
                                   cfg_edge_node[edge_idx*8 +: 8]};
                8'hDC: s_rdata <= {16'd0,
                                   cfg_edge_win[edge_idx*16 +: 16]};
                // ---- 2e credit-gated release (SPEC §7; 盘态实读:
                // 0xE0-0xE8 在 trace ring 读窗口 0xA4-0x4A4 内，必须
                // CSR 显式 case 优先，否则 PS 读会拿到 ring 数据) ----
                8'hE0: s_rdata <= {31'd0, cfg_chain_rel};
                8'hDE: s_rdata <= {16'd0, cfg_up2x};   // 5b CHAIN_UP2X
                8'hE4: s_rdata <= s2l_cnt;
                8'hE8: s_rdata <= skew_max;
                // ---- v2.3 PPP/LAYOUT window (DESIGN §1.2; explicit case
                // beats the trace-ring default read, 0xE0-0xE8 law) ----
                8'hE9: s_rdata <= {29'd0, ppp_cur};
                8'hEA: s_rdata <= ppp_tab[ppp_cur];    // no auto-inc
                8'hEB: s_rdata <= {2'd0, layout_id};
                8'hED: s_rdata <= 32'h4D39_0A08;       // CAP3 (§1.2)
                // ---- G3 OVF AW-capture window (RUNBOOK_5d §11; explicit
                // case beats the trace-ring default read, 0xE0-0xE8 law) --
                8'hE2: s_rdata <= {15'd0, ovf_trig, ovf_tot};
                8'hE6: s_rdata <= {28'd0, ovf_cur_q};
                8'hEE: s_rdata <= ovf_ring[ovf_cur_q];
                // ---- r7 debug aperture (explicit case beats the trace
                // ring default read, same law as 0xE0-0xE8 above) ----
                8'hF8: s_rdata <= {28'd0, dbg_cur};
                8'hFC: s_rdata <= hb_dbg[{dbg_cur, 5'b00000} +: 32];
                default: s_rdata <= (s_araddr >= 8'h60) ? tr_rdata : 32'd0;
                endcase
                s_rvalid <= 1'b1;
            end
        end
    end

endmodule
