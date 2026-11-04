/************************************************************************
 * File Name       : m9_trace.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-11
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13.4.3)
 * Module Name     : m9_trace
 * Description     :
 *   M9.2 trace bring-up block. Low-disturbance cycle counters and a
 *   bounded block-event ring for the intra-layer pipeline phases,
 *   per plan section 13.4.3 (trace schema):
 *
 *     L      = load_active_cycles     (feeder activity window)
 *     C      = compute_useful_cycles  (engine core busy, observe-only tap)
 *     S      = store_active_cycles    (scatter window sc_arm .. sc_done)
 *     LC/CS/LS/LCS = pairwise / triple per-cycle overlap cycle counts
 *     Gmax   = max consecutive (ld_tvalid && !ld_tready) run length
 *     Fmax   = max y FIFO occupancy level; Fov = FIFO overflow count
 *     Tfill  = start .. first C cycle of the last frame (latched)
 *     Tdrain = last C cycle .. done of the last frame (latched)
 *
 *   All counters are 32-bit, single clock domain (clk), naturally
 *   wrapping, cleared by reset or the `clr` pulse (read-side snapshot
 *   semantics are the reader's responsibility: counters are free-running
 *   accumulators, the ABI/TB reads them between frames; readout port is
 *   fully separate from the data path -- section 13.4.2 "trace block").
 *
 *   Event ring: 64 entries x {evt[3:0], blk[11:0], cyc[31:0]} capturing
 *   frame/block boundary order for the self-check gate (event order,
 *   zero-clear, wraparound, formula unit tests -- M9.2 gate).
 *
 * Revision History:
 *   - V1.0 (2026-10-11) : first release, M9.2 gate run01.
 *   - V1.1 (2026-10-11) : two bring-up fixes from run01 NB=4 evidence:
 *     (1) readout mux priority: the ring region (tr_raddr[9]=1, 0x200-0x3FF)
 *         was only reachable via the DEFAULT arm of case(tr_raddr[7:0]),
 *         so every ring address whose low byte collided with a counter
 *         offset (0x00-0x44) returned a counter instead of a ring entry
 *         (observed: ring reads returned cnt_L/C/ld_beats values).
 *         Fix: test tr_raddr[9] FIRST, then the counter case.
 *     (2) sc_done is a STICKY LEVEL (m9_y_scatter V1.1 contract: held
 *         from slot close until next sc_arm), NOT a pulse -- the ring
 *         pushed one entry per cycle sc_done stayed high (observed:
 *         ring_len=40 for NB=4 where 6 expected). Fix: rising-edge
 *         detect (sc_done_evt) feeds the ring push/event code/flags;
 *         the S window clear keeps using the level (arm..close window
 *         semantics unchanged).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_trace (
    input  wire        clk          ,
    input  wire        rst_n        ,
    input  wire        clr          ,   // software clear pulse (1 cycle)
    // ---- phase observation (all single clk domain) ----
    input  wire        ld_active    ,   // w_busy | x_busy  (load feeder)
    input  wire        ld_beat      ,   // ld_tvalid && ld_tready
    input  wire        ld_stall     ,   // ld_tvalid && !ld_tready
    input  wire        c_active     ,   // dbg tap: engine core busy
    input  wire        y_valid      ,   // dbg tap: engine y out valid
    input  wire        sc_arm       ,   // scatter window open strobe
    input  wire        sc_done      ,   // scatter window close pulse
    input  wire        frame_start  ,   // start pulse
    input  wire        frame_done   ,   // done pulse
    input  wire [11:0] progress_blk ,   // cumulative block count (snoop)
    input  wire [5:0]  yfifo_level  ,   // dbg tap: y FIFO occupancy
    input  wire        y_ovf_evt    ,   // dbg tap: FIFO overflow pulse
    input  wire        err_evt      ,   // any engine/trace error pulse
    // ---- readout face (separate from data path) ----
    input  wire [9:0]  tr_raddr     ,
    output reg  [31:0] tr_rdata     ,
    output reg         ring_ovr         // ring overwrite (sticky)
);

    // ---------------- counter bank -----------------------------------
    reg [31:0] cnt_L, cnt_C, cnt_S;
    reg [31:0] cnt_LC, cnt_CS, cnt_LS, cnt_LCS;
    reg [31:0] cnt_ld_beats, cnt_y_beats;
    reg [31:0] cnt_Gmax, cnt_Fmax, cnt_Fov;
    reg [31:0] cnt_frame;
    reg [31:0] free_cyc;                 // free-running cycle stamp

    // ---------------- S window (sticky sc_arm .. sc_done) ------------
    reg        sc_window;

    // ---------------- Gmax run-length tracker ------------------------
    reg [31:0] gap_run;

    // ---------------- Tfill / Tdrain (last frame, latched) -----------
    reg        frame_open;               // between frame_start/frame_done
    reg [1:0]  frame_age;                // suppress reset-settling error edge
    reg        c_seen;                   // a C cycle occurred this frame
    reg [31:0] win_cyc;                  // cycles since frame_start
    reg [31:0] last_gap;                 // cycles since last C cycle
    reg [31:0] tfill_r, tdrain_r;

    // ---------------- block-done edge detect -------------------------
    reg [11:0] prog_d;

    // ---------------- sc_done level -> event edge --------------------
    // sc_done is a STICKY LEVEL (scatter V1.1 contract: held from slot
    // close until next sc_arm), NOT a pulse. The S window below uses the
    // level directly (arm..close semantics); the ring push / event code /
    // flags must see only the rising edge = one entry per store close.
    // During clr, track the level (no false edge if sc_done still high).
    reg sc_done_d;
    wire sc_done_evt = sc_done & ~sc_done_d;   // rising edge = slot close
    reg sc_pending;                             // close seen before block edge

    // ---------------- event ring -------------------------------------
    // entry: {evt[3:0], flags[3:0], blk[11:0], cyc[31:0]}
    //   flags[0] = sc_done coincident this cycle (store close)
    //   flags[1] = y_ovf coincident; flags[2] = err coincident;
    //   flags[3] = frame_start coincident (never: start wins the slot)
    // One entry per cycle max: simultaneous events collapse with priority
    // frame_start > blk_done > sc_done > frame_done > y_ovf > err, the
    // losers recorded in flags (schema: event_ring.collapse_rule).
    localparam RING_N = 64;
    reg [63:0] ring [0:RING_N-1];
    reg [5:0]  ring_wp;
    reg [6:0]  ring_len;                 // 0..64 (saturates at 64)
    reg        trace_active;
    reg        done_pending;
    reg [1:0]  ring_holdoff;
    integer    ring_i;

    localparam EVT_FRAME_START = 4'd1,
               EVT_LD_START    = 4'd2,
               EVT_BLK_DONE    = 4'd3,
               EVT_SC_DONE     = 4'd4,
               EVT_FRAME_DONE  = 4'd5,
               EVT_Y_OVF       = 4'd6,
               EVT_ERR         = 4'd7;

    wire do_clr = clr | ~rst_n;          // registered reset below handles rst

    // ---------------- main counter process ---------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_L <= 32'd0;  cnt_C <= 32'd0;  cnt_S <= 32'd0;
            cnt_LC <= 32'd0; cnt_CS <= 32'd0;
            cnt_LS <= 32'd0; cnt_LCS <= 32'd0;
            cnt_ld_beats <= 32'd0; cnt_y_beats <= 32'd0;
            cnt_Gmax <= 32'd0; cnt_Fmax <= 32'd0; cnt_Fov <= 32'd0;
            cnt_frame <= 32'd0; free_cyc <= 32'd0;
            sc_window <= 1'b0;
            gap_run <= 32'd0;
            frame_open <= 1'b0; c_seen <= 1'b0;
            frame_age <= 2'd0;
            win_cyc <= 32'd0; last_gap <= 32'd0;
            tfill_r <= 32'd0; tdrain_r <= 32'd0;
            prog_d <= 12'd0;
            sc_done_d <= 1'b0;
            sc_pending <= 1'b0;
        end else begin
            free_cyc <= free_cyc + 32'd1;

            if (clr) begin
                cnt_L <= 32'd0;  cnt_C <= 32'd0;  cnt_S <= 32'd0;
                cnt_LC <= 32'd0; cnt_CS <= 32'd0;
                cnt_LS <= 32'd0; cnt_LCS <= 32'd0;
                cnt_ld_beats <= 32'd0; cnt_y_beats <= 32'd0;
                cnt_Gmax <= 32'd0; cnt_Fmax <= 32'd0; cnt_Fov <= 32'd0;
                cnt_frame <= 32'd0;
                sc_window <= 1'b0;
                gap_run <= 32'd0;
                frame_open <= 1'b0; c_seen <= 1'b0;
                frame_age <= 2'd0;
                win_cyc <= 32'd0; last_gap <= 32'd0;
                tfill_r <= 32'd0; tdrain_r <= 32'd0;
                prog_d <= progress_blk;
                sc_done_d <= sc_done;    // track level: no false edge post-clr
                sc_pending <= 1'b0;
            end else begin
                // ---- phase counters (per-cycle boolean sampling) ----
                if (ld_active)              cnt_L  <= cnt_L  + 32'd1;
                if (c_active)               cnt_C  <= cnt_C  + 32'd1;
                if (sc_window)              cnt_S  <= cnt_S  + 32'd1;
                if (ld_active && c_active)  cnt_LC <= cnt_LC + 32'd1;
                if (c_active && sc_window)  cnt_CS <= cnt_CS + 32'd1;
                if (ld_active && sc_window) cnt_LS <= cnt_LS + 32'd1;
                if (ld_active && c_active && sc_window)
                                            cnt_LCS <= cnt_LCS + 32'd1;
                if (ld_beat)  cnt_ld_beats <= cnt_ld_beats + 32'd1;
                if (y_valid)  cnt_y_beats  <= cnt_y_beats  + 32'd1;

                // ---- Gmax: max consecutive ld_stall run ----
                if (ld_stall) begin
                    gap_run <= gap_run + 32'd1;
                    if (gap_run + 32'd1 > cnt_Gmax)
                        cnt_Gmax <= gap_run + 32'd1;
                end else begin
                    gap_run <= 32'd0;
                end

                // ---- Fmax / Fov ----
                if ({26'd0, yfifo_level} > cnt_Fmax)
                    cnt_Fmax <= {26'd0, yfifo_level};
                if (y_ovf_evt) cnt_Fov <= cnt_Fov + 32'd1;

                // ---- S window sticky ----
                if (sc_done)      sc_window <= 1'b0;
                else if (sc_arm)  sc_window <= 1'b1;

                // ---- frame bookkeeping / Tfill / Tdrain ----
                if (frame_start) begin
                    frame_open <= 1'b1;
                    frame_age  <= 2'd0;
                    c_seen     <= 1'b0;
                    win_cyc    <= 32'd0;
                    last_gap   <= 32'd0;
                    cnt_frame  <= cnt_frame + 32'd1;
                end else if (frame_done) begin
                    frame_open <= 1'b0;
                    frame_age  <= 2'd0;
                    // Tdrain = cycles from last C cycle to done; if no C
                    // ever happened the frame drain is the whole window.
                    tdrain_r   <= c_seen ? last_gap : win_cyc;
                end

                if (frame_open && (frame_age != 2'd3))
                    frame_age <= frame_age + 2'd1;

                if (frame_open) begin
                    win_cyc  <= win_cyc + 32'd1;
                    last_gap <= last_gap + 32'd1;
                    if (c_active && !c_seen) begin
                        c_seen   <= 1'b1;
                        tfill_r  <= win_cyc;    // start .. first C cycle
                    end
                    if (c_active) last_gap <= 32'd0;
                end

                // ---- block-done edge ----
                prog_d      <= progress_blk;
                sc_done_d   <= sc_done;      // track sticky level
                // A sticky scatter close normally precedes the issuer's
                // progress edge by a few cycles.  Retain it and attach the
                // flag to that block event instead of emitting a second
                // ring entry.
                if (progress_blk != prog_d)
                    sc_pending <= 1'b0;
                else if (sc_done_evt)
                    sc_pending <= 1'b1;
            end
        end
    end

    // ---------------- event ring push --------------------------------
    wire blk_done_evt = (progress_blk != prog_d);
    // Ignore an error transition before the first frame window; reset-time
    // X-to-zero settling must not create a trace event.
    wire err_ring_evt = err_evt && (frame_open || frame_start)
                      && (frame_start || (frame_age != 2'd0))
                      && (frame_start || (progress_blk != 12'd0));
    wire done_now = frame_done && !blk_done_evt;
    wire ring_push = (frame_start | blk_done_evt | done_now
                   | done_pending | y_ovf_evt
                   | (err_ring_evt && (progress_blk != 12'd0)))
                   && (trace_active | frame_start);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ring_wp  <= 6'd0;
            ring_len <= 6'd0;
            ring_ovr <= 1'b0;
            trace_active <= 1'b0;
            done_pending <= 1'b0;
            ring_holdoff <= 2'd0;
            for (ring_i = 0; ring_i < RING_N; ring_i = ring_i + 1)
                ring[ring_i] <= 64'd0;
        end else if (clr) begin
            ring_wp  <= 6'd0;
            ring_len <= 6'd0;
            ring_ovr <= 1'b0;
            trace_active <= 1'b0;
            done_pending <= 1'b0;
            ring_holdoff <= 2'd0;
            for (ring_i = 0; ring_i < RING_N; ring_i = ring_i + 1)
                ring[ring_i] <= 64'd0;
        end else if (frame_start) begin
            // Make the first event deterministic.  The frame-start probe
            // is the anchor of the trace contract and must occupy ring[0],
            // even if an unrelated pre-frame signal is settling.
            ring[0] <= {
                12'd0, EVT_FRAME_START, 4'd0, progress_blk, free_cyc
            };
            ring_wp <= 6'd1;
            ring_len <= 7'd1;
            ring_ovr <= 1'b0;
            trace_active <= 1'b1;
            ring_holdoff <= 2'd2;
            if (frame_done && blk_done_evt) done_pending <= 1'b1;
        end else if (ring_holdoff != 2'd0) begin
            ring_holdoff <= ring_holdoff - 2'd1;
        end else if (ring_push) begin
            // entry = {12'd0, evt[3:0], flags[3:0], blk[11:0], cyc[31:0]}
            ring[ring_wp] <= {
                12'd0,
                (frame_start ? EVT_FRAME_START :
                 blk_done_evt ? EVT_BLK_DONE :
                 (done_pending | done_now) ? EVT_FRAME_DONE :
                 y_ovf_evt    ? EVT_Y_OVF : EVT_ERR),
                {(err_ring_evt && !frame_start && !blk_done_evt
                              && !done_now && !done_pending && !y_ovf_evt),
                 (y_ovf_evt && !frame_start && !blk_done_evt
                              && !done_now && !done_pending),
                 1'b0,
                 ((sc_done_evt | sc_pending) && blk_done_evt)},
                progress_blk,
                free_cyc
            };
            ring_wp <= ring_wp + 6'd1;
            if (ring_len != 7'd64) ring_len <= ring_len + 7'd1;
            else                   ring_ovr <= 1'b1;   // wrapped overwrite
            if (frame_start) trace_active <= 1'b1;
            if (frame_done && blk_done_evt) done_pending <= 1'b1;
            else if (done_pending || done_now) done_pending <= 1'b0;
        end else begin
            if (frame_start) trace_active <= 1'b1;
            if (frame_done && blk_done_evt) done_pending <= 1'b1;
        end
    end

    // ---- readout (combinational mux) ----
    // 0x000..0x0FF : counter bank (below)
    // 0x200 + 8*i  : ring entry i = {header @+0, cycle @+4}, i = 0..63
    // PRIORITY: tr_raddr[9]=1 selects the ring FIRST -- the ring base 0x200
    // has zero low byte, so a case(tr_raddr[7:0])-first mux returned counter
    // values for every ring address colliding with 0x00-0x44 (run01 bug).
    wire [5:0]  ring_ri = tr_raddr[8:3];

    always @(*) begin
        if (tr_raddr[9] == 1'b1) begin
            if (tr_raddr[2] == 1'b0)
                tr_rdata = ring[ring_ri][63:32];  // {12'd0,evt,flags,blk}
            else
                tr_rdata = ring[ring_ri][31:0];   // cycle stamp
        end else begin
            case (tr_raddr[7:0])
                8'h00:   tr_rdata = cnt_L;
                8'h04:   tr_rdata = cnt_C;
                8'h08:   tr_rdata = cnt_S;
                8'h0C:   tr_rdata = cnt_LC;
                8'h10:   tr_rdata = cnt_CS;
                8'h14:   tr_rdata = cnt_LS;
                8'h18:   tr_rdata = cnt_LCS;
                8'h1C:   tr_rdata = cnt_ld_beats;
                8'h20:   tr_rdata = cnt_y_beats;
                8'h24:   tr_rdata = cnt_Gmax;
                8'h28:   tr_rdata = cnt_Fmax;
                8'h2C:   tr_rdata = cnt_Fov;
                8'h30:   tr_rdata = tfill_r;
                8'h34:   tr_rdata = tdrain_r;
                8'h38:   tr_rdata = cnt_frame;
                8'h3C:   tr_rdata = {25'd0, ring_len};
                8'h40:   tr_rdata = free_cyc;
                8'h44:   tr_rdata = {31'd0, ring_ovr};
                default: tr_rdata = 32'd0;
            endcase
        end
    end

endmodule
