/************************************************************************
 * File Name       : m9_repack_glue.v
 * Developer       : M11 r11 build line (scatter->CHW repack merge)
 * Date            : 2026-10-18
 * Project Name    : YOLO object accel (replan M11, r11 build run01)
 * Module Name     : m9_repack_glue
 * Description     :
 *   M11 repack top glue -- SPEC_m11_repack.md section 7 contact list
 *   implementation for the r11 build.  This module is the single new
 *   glue file of the merge (contact #5 action column: "新增胶合文件，
 *   既有读核不动"); the frozen cores (m9_y_scatter, m9_cmd_issuer,
 *   m9_axi_wr, m9_axi_rd_v3, the whole PPU island) stay BYTE-IDENTICAL
 *   and are never instantiated here -- this file only ADDS logic.
 *
 *   Contact #4 (start line): pure top FF -- producer last-slot-complete
 *     detect (the repack-seal condition sc_done_lvl && nb!=0 &&
 *     sc_blocks >= nb, the robust >= form of the spec's b_cnt==nb-1
 *     detect, identical event) -> one-cycle rp_start pulse, held off
 *     after firing until the next accepted arm.  Never enters
 *     m9_cmd_issuer (contact #4 zero-change law).
 *
 *   Contact #5 (read path): lightweight AXI read master in the
 *     m9_axi_rd_v3 pattern (single ID, in-order R, single outstanding
 *     burst, rresp ignored per the frozen INJ-5D contract gap law) plus
 *     a 16 KiB span-resident window that fronts the repack's fixed
 *     1-cycle-latency / no-backpressure read contract (SPEC §4.2):
 *     the glue prefetches the whole slot-law source span while arming
 *     (warm gate), so once rp_start fires, every repack rreq sees its
 *     byte exactly one cycle later, structurally, with no rready.
 *
 *     STORAGE = OFFICIAL IP (user iron law 10-14/10-18, PG058): the
 *     window is a Block Memory Generator core "m9_bm_rpwin" (Simple
 *     Dual Port RAM, 2048 x 64b, READ_FIRST, ENA/ENB pins, NO output
 *     registers -> port B latency exactly 1), instantiated strictly
 *     from the generated .veo template (byte-for-byte port face).
 *     The hand-written inferred array of v1.0-v1.2 is deleted -- no
 *     hand-rolled memories remain in this file.  Port A = prefetch
 *     writer (one 64b word per AXI R beat; gapless back-to-back beats
 *     are structurally safe, no drain shifter).  Port B = repack
 *     consumer (random address gather: the CHW walk jumps vc/ypitch
 *     between rows -- this is why the window is an addressed RAM, not
 *     a queue; PG057 FIFO Generator cannot serve this port).
 *
 *   Contact #6 (write path): 2:1 byte-write arbitration between the
 *     y_scatter byte port and the repack write port into the SHARED
 *     m9_axi_wr (m9_axi_wr untouched).  Priority = y_scatter (conv
 *     writes must never stall); a 4-deep skid captures repack bytes on
 *     collision.  Mutual exclusion is structurally guaranteed by the
 *     seal timing (repack runs only after the producer closed every
 *     expected slot), so the skid is a belt-and-suspenders guard; a
 *     skid overflow sets the sticky dbg_col observability flag -- it
 *     can never fire under the seal law.
 *
 *   r11 carrier state (SPEC §8 OPEN-1/2, contact #2 "r11 裁"): the
 *     rp_* config face enters this module as PORTS; in the r11 build
 *     the axi_top ties rp_arm = 1'b0 (inert carrier, kept in the
 *     netlist by keep_hierarchy on u_repack).  The M11 config line
 *     replaces those tie-offs with the CSR/ROM source without touching
 *     this file's structure.  With rp_arm tied low: no arm latch, no
 *     prefetch, rp_start never pulses, no repack byte ever reaches the
 *     arbiter -- the r10 datapath is bit-identical.
 *
 * Dependencies    : m9_bm_rpwin (BMG v8.4 IP, project sources_1/ip),
 *                   m9_scatter_chw_repack.v (instantiated at axi_top,
 *                   not here), m9_axi_wr (shared write master, untouched)
 * Revision History:
 *   - V1.0 (2026-10-18) : first release, hand-written inferred FIFO
 *                         array (killed by Synth 8-3391 -- async-reset
 *                         memory statements; see V1.2 note).
 *   - V1.1 (2026-10-18) : read-data register moved out of the
 *                         async-reset process (first 8-3391 fix;
 *                         incomplete -- write statements stayed).
 *   - V1.2 (2026-10-18) : full SDP template restructure of the
 *                         hand-written array (write statements
 *                         reset-free, 64b-wide, true 1-cycle read).
 *   - V1.3 (2026-10-18) : STORAGE SWAPPED TO OFFICIAL IP per user
 *                         ruling (存储一律官方 IP): m9_bm_rpwin BMG
 *                         instance replaces the hand-written array
 *                         entirely (.veo-verified face; config pinned
 *                         and gate-checked in build_m10r11.tcl).  All
 *                         V1.2 functional fixes carry over (one word
 *                         per beat, true 1-cycle read port).  Single
 *                         always block per register (multi-driven =
 *                         sim/synth divergence law; 8-6859 object).
 *                         Pure Verilog-2001 RTL around one official IP.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_repack_glue (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- contact #2 config face (r11: tied inert at the axi_top) ----
    input  wire        rp_arm        ,
    input  wire [31:0] rp_src_base   ,
    input  wire [31:0] rp_dst_base   ,   // unused here (repack-internal)
    input  wire [15:0] rp_c          ,
    input  wire [15:0] rp_h          ,
    input  wire [15:0] rp_w          ,
    input  wire [15:0] rp_vc         ,
    input  wire [31:0] rp_ypitch     ,
    input  wire [15:0] rp_nb         ,
    // ---- contact #3 producer seal (direct u_ys net taps at axi_top) --
    input  wire        sc_done_lvl   ,
    input  wire [9:0]  sc_blocks     ,
    input  wire        rp_busy_i     ,   // repack busy level (arm mirror)
    output reg         rp_start      ,   // contact #4 -> repack.rp_start
    // ---- repack read port (fixed 1-cycle latency contract) ----
    input  wire [31:0] rp_raddr      ,
    input  wire        rp_rreq       ,
    output wire [7:0]  rp_rdata      ,
    // ---- contact #6 write arbitration (byte ports) ----
    input  wire [31:0] sc_yaddr      ,   // y_scatter side (scatter-only)
    input  wire        sc_yreq       ,
    input  wire [7:0]  sc_ywdata     ,
    input  wire [31:0] rp_waddr      ,   // repack side
    input  wire        rp_wreq       ,
    input  wire [7:0]  rp_wdata      ,
    output wire [31:0] mrg_yaddr     ,   // merged -> m9_axi_wr (u_ywr)
    output wire        mrg_yreq      ,
    output wire [7:0]  mrg_ywdata    ,
    // ---- contact #5a glue AXI read master face ----
    // r11: tied off at the axi_top (inert carrier); the M11 line punches
    // this face through the shim/BD following the r9b s2_axi/m03_axi
    // boundary-surgery precedent (SPEC §8 OPEN-1 ruling).
    output reg  [31:0] m_araddr      ,
    output reg  [3:0]  m_arlen       ,
    output reg         m_arvalid     ,
    input  wire        m_arready     ,
    input  wire [63:0] m_rdata       ,
    input  wire [1:0]  m_rresp       ,   // ignored (frozen INJ-5D law)
    input  wire        m_rvalid      ,
    input  wire        m_rlast       ,
    output wire        m_rready      ,
    // ---- observability (debug taps, no datapath effect) ----
    output reg         dbg_col       ,   // skid overflow sticky (never)
    output wire        dbg_warm          // prefetch complete level
);

    // ------------------------------------------------------------------
    // contact #4: arm shadow + last-slot-complete start detect
    // ------------------------------------------------------------------
    // Arm acceptance mirrors the repack contract (only when not busy);
    // the latched nb drives both the start detect and (redundantly, the
    // repack re-checks its own seal) the fire condition.
    reg        armed_shadow;             // set on accepted arm, cleared
    reg [15:0] nb_q;                     //   by the start pulse
    reg        warm_r;                   // prefetch complete (declared
                                         // here; driven by the PF engine)
    // arm acceptance mirrors the repack's own arm gate (SPEC §5: zero
    // geometry -> 0x04, W>vc -> 0x03 are repack-side rejects; the glue
    // must not treat a rejected arm as accepted)
    wire arm_accept = rp_arm && !rp_busy_i &&
                      (rp_c != 16'd0) && (rp_h != 16'd0) &&
                      (rp_w != 16'd0) && (rp_vc != 16'd0) &&
                      (rp_w <= rp_vc);
    wire start_cond = sc_done_lvl && (nb_q != 16'd0) &&
                      (sc_blocks >= (nb_q - 16'd1)) &&
                      warm_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            armed_shadow <= 1'b0;
            nb_q         <= 16'd0;
            rp_start     <= 1'b0;
        end else begin
            rp_start <= 1'b0;                      // default: 1-cycle pulse
            if (arm_accept) begin
                armed_shadow <= 1'b1;
                nb_q         <= rp_nb;
            end else if (armed_shadow && start_cond) begin
                armed_shadow <= 1'b0;              // one shot per arm
                rp_start     <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // contact #5: source-span prefetch engine + IP-backed window
    // ------------------------------------------------------------------
    // Slot-law source span walked by the repack (SPEC §1):
    //   max addr offset = vc*(C-1) + ypitch*(H-1) + (W-1)  ->  span bytes
    // computed at arm rate (config-rate multiply, M9.1 style).  The
    // prefetch covers [floor8(src_base), src_base+span) so every repack
    // raddr has a resident byte before rp_start can fire (warm gate).
    //
    // Window capacity law: fetch_tot <= 16384 bytes (fifo_of reject)
    // -> beats_tot <= 2048 = exactly the m9_bm_rpwin write depth.
    localparam FIFO_AW = 11;                    // 2048 x 64b words
    localparam [3:0] BEATS_MAX = 4'd8;          // 8 x 64b per burst
    reg [FIFO_AW-1:0] pf_ww;                    // write word cursor
    reg [31:0] fetch_q;                         // beats still to fetch
    reg [31:0] base_al_q;                       // latched floor8(src_base)
    assign dbg_warm = warm_r;

    localparam PF_IDLE = 2'd0, PF_AR = 2'd1, PF_R = 2'd2, PF_DONE = 2'd3;
    reg [1:0]  pf_st;
    reg [3:0]  beat_left;                       // beats left in burst
    reg [31:0] ar_addr;                         // next AR address
    wire [31:0] span_calc = {16'd0, rp_vc} * {16'd0, rp_c - 16'd1} +
                            rp_ypitch * {16'd0, rp_h - 16'd1} +
                            {16'd0, rp_w};
    wire [31:0] lead      = {29'd0, rp_src_base[2:0]};
    wire [31:0] fetch_tot = span_calc + lead;   // bytes from floor8 base
    wire [31:0] beats_tot = (fetch_tot + 32'd7) >> 3;

    wire fifo_of = (fetch_tot > (32'd1 << 14));

    // ---- window write strobe: one 64b word per accepted R beat -------
    wire pf_we = (pf_st == PF_R) && m_rvalid;

    // ---- prefetch control (async reset allowed: no memory ops here) --
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_st     <= PF_IDLE;
            base_al_q <= 32'd0;
            fetch_q   <= 32'd0;
            pf_ww     <= {FIFO_AW{1'b0}};
            warm_r    <= 1'b0;
            beat_left <= 4'd0;
            ar_addr   <= 32'd0;
            m_araddr  <= 32'd0;
            m_arlen   <= 4'd0;
            m_arvalid <= 1'b0;
        end else begin
            // warm level: prefetch delivered the whole span
            if (pf_st == PF_DONE)
                warm_r <= 1'b1;
            else if (arm_accept)
                warm_r <= 1'b0;
            if (pf_we)
                pf_ww <= pf_ww + {{(FIFO_AW-1){1'b0}}, 1'b1};
            case (pf_st)
            PF_IDLE: begin
                if (arm_accept && !fifo_of) begin
                    base_al_q <= {rp_src_base[31:3], 3'b000};
                    fetch_q   <= beats_tot;
                    pf_ww     <= {FIFO_AW{1'b0}};
                    ar_addr   <= {rp_src_base[31:3], 3'b000};
                    if (beats_tot != 32'd0) pf_st <= PF_AR;
                    else                    pf_st <= PF_DONE;
                end
            end
            PF_AR: begin
                // one burst in flight (m9_axi_rd_v3 single-outstanding
                // pattern); arlen = min(8, beats remaining) - 1
                m_araddr  <= ar_addr;
                m_arlen   <= (fetch_q >= 32'd8) ? (BEATS_MAX - 4'd1)
                             : (fetch_q[3:0] - 4'd1);
                m_arvalid <= 1'b1;
                beat_left <= (fetch_q >= 32'd8) ? BEATS_MAX
                             : fetch_q[3:0];
                pf_st     <= PF_R;
            end
            PF_R: begin
                if (m_arvalid && m_arready) m_arvalid <= 1'b0;
                if (m_rvalid) begin
                    // whole beat lands this cycle in u_rpwin (word write)
                    beat_left <= beat_left - 4'd1;
                    fetch_q   <= fetch_q - 32'd1;
                    if (fetch_q <= 32'd1) begin
                        pf_st <= PF_DONE;         // last beat landed
                    end else if (beat_left <= 4'd1) begin
                        ar_addr <= ar_addr + 32'd64;
                        pf_st   <= PF_AR;         // next burst
                    end
                end
            end
            default: pf_st <= PF_DONE;            // PF_DONE (and guard)
            endcase
        end
    end

    // ------------------------------------------------------------------
    // window RAM: official BMG IP m9_bm_rpwin (.veo-verified face)
    // ------------------------------------------------------------------
    // Port A = prefetch writer: ena/wea strobed by pf_we, one word per
    // R beat.  Port B = repack consumer: TRUE 1-cycle contract -- enb
    // samples rp_rreq/rp_raddr combinationally (repack register outputs,
    // setup-clean), the IP's port B synchronous read (NO output
    // registers) returns the word exactly one cycle later.  base_al_q
    // is 8-aligned, so word index = (raddr - base)[13:3] (11b subtract,
    // exact under the warm law) and byte select = raddr[2:0], muxed in
    // fabric off the registered byte pointer.  Reads can only start
    // after warm (rp_start gates the repack) -- no port A/B overlap;
    // READ_FIRST advisory satisfied regardless.
    wire [63:0]   win_word;
    reg  [2:0]    rby_d;                         // byte select pointer,
                                                // sampled with the word
    always @(posedge clk) begin
        if (rp_rreq)
            rby_d <= rp_raddr[2:0];
    end
    assign rp_rdata = win_word >> (8 * rby_d);

    m9_bm_rpwin u_rpwin (
      .clka(clk),                                // input  wire clka
      .ena(pf_we),                               // input  wire ena
      .wea(1'b1),                                // input  wire [0:0] wea
      .addra(pf_ww),                             // input  wire [10:0] addra
      .dina(m_rdata),                            // input  wire [63:0] dina
      .clkb(clk),                                // input  wire clkb
      .enb(rp_rreq),                             // input  wire enb
      .addrb(rp_raddr[FIFO_AW+2:3] - base_al_q[FIFO_AW+2:3]), // [10:0]
      .doutb(win_word)                           // output wire [63:0] doutb
    );

    // ------------------------------------------------------------------
    // contact #6: byte-write arbitration into the shared m9_axi_wr
    // ------------------------------------------------------------------
    // y_scatter has absolute priority; the repack side lands in a 4-deep
    // skid on collision.  Under the seal law the two writers are
    // mutually exclusive, so the skid only ever sees back-to-back
    // handoff cycles; dbg_col flags the impossible overflow.
    reg [31:0] skid_a [0:3];
    reg [7:0]  skid_d [0:3];
    reg [2:0]  skid_n;                          // 0..4 occupied
    wire skid_full  = (skid_n == 3'd4);
    wire skid_empty = (skid_n == 3'd0);
    wire collision  = rp_wreq && (sc_yreq || !skid_empty);

    assign mrg_yreq   = sc_yreq || !skid_empty || rp_wreq;
    assign mrg_yaddr  = sc_yreq  ? sc_yaddr  :
                        (!skid_empty ? skid_a[0] : rp_waddr);
    assign mrg_ywdata = sc_yreq  ? sc_ywdata :
                        (!skid_empty ? skid_d[0] : rp_wdata);
    assign m_rready   = 1'b1;                   // no R backpressure

    integer si;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_n  <= 3'd0;
            dbg_col <= 1'b0;
            for (si = 0; si < 4; si = si + 1) begin
                skid_a[si] <= 32'd0;
                skid_d[si] <= 8'd0;
            end
        end else begin
            if (collision) begin
                if (skid_full) begin
                    dbg_col <= 1'b1;            // impossible under seal law
                end else begin
                    skid_a[skid_n[1:0]] <= rp_waddr;
                    skid_d[skid_n[1:0]] <= rp_wdata;
                    skid_n <= skid_n + 3'd1;
                end
            end
            // skid drains only when the scatter side is idle; the byte
            // at slot 0 is consumed by the merge mux this cycle
            if (!skid_empty && !sc_yreq) begin
                skid_a[0] <= skid_a[1];
                skid_a[1] <= skid_a[2];
                skid_a[2] <= skid_a[3];
                skid_d[0] <= skid_d[1];
                skid_d[1] <= skid_d[2];
                skid_d[2] <= skid_d[3];
                skid_n    <= collision ? skid_n : (skid_n - 3'd1);
            end
        end
    end

endmodule
