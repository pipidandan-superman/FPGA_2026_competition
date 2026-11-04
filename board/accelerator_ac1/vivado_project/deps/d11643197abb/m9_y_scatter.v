/************************************************************************
 * File Name       : m9_y_scatter.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_y_scatter
 * Description     :
 *   Y recovery consumer -- the S2MM replacement (02_m9_issuer_spec.md
 *   section 5).  The engine pushes per completed block exactly
 *   ycnt = 8*vc bytes as vc 64-bit words (first y byte in [7:0],
 *   tlast on the last word -- YSTAT.y_count counts BYTES, the pl_m3
 *   completion gate ycnt==8*vc).  Byte order in the slot is the
 *   board-green gather law: byte = r*vc + cv (compact row-major over
 *   valid lanes), so the scatter is a pure sequential byte writer:
 *
 *     arena[cfg base + stride_slot*b + i] = word[i%8]  (i = byte idx)
 *
 *   M9.1 correctness-first: one arena byte per cycle, tready gated
 *   low while the accepted word drains (8 cycles).  The engine-side
 *   32-word y FIFO absorbs the pacing jitter; overrun is structurally
 *   impossible (tready=0 backs the stream up, zero loss).
 *
 *   Per-block check: after tlast, byte count must equal 8*vc (the
 *   TKEEP CAP8 view: transferred bytes == valid bytes per tile);
 *   mismatch sets err_sticky (issuer halts on it).
 *
 *   sc_done is a STICKY LEVEL held from slot close until the next
 *   sc_arm -- NOT a pulse.  Lesson (block-16 deadlock, vc=4): the
 *   issuer polls STATUS/YSTAT/BRGSTAT (~20 cycles) before entering
 *   its scatter-wait state; a vc=4 slot drains in ~36 cycles, so a
 *   1-cycle done pulse fires and vanishes before the waiter looks
 *   (vc=16 slots drain ~150 cycles and never exposed the race).
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 *   - V1.1 (2026-10-09) : sc_done pulse -> sticky level (vc4 race).
 *   - V1.2 (2026-10-09) : removed the leftover pulse assign (dual
 *     continuous drivers on sc_done resolved X -- S_W4 hang, block 0).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_y_scatter (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-block arm (issuer, block entry; previous block must have
    //      completed -- sc_done handshake serializes) ----
    input  wire        sc_arm        ,
    input  wire [31:0] sc_base       ,   // arena byte addr of the slot
    input  wire [4:0]  sc_vc         ,   // strip vc (expected words = vc)
    input  wire        sc_up2x       ,   // 5b: materialize nearest-2x
    output wire        sc_done       ,   // level: slot closed (holds to next arm)
    output wire        sc_err        ,   // sticky: byte count != 8*vc
    // ---- engine y recovery port (m_axis_y) ----
    input  wire [63:0] y_tdata       ,
    input  wire        y_tvalid      ,
    output wire        y_tready      ,
    input  wire        y_tlast       ,
    // ---- arena byte write port ----
    output reg  [31:0] yaddr         ,
    output reg         yreq          ,
    output reg  [7:0]  ywdata        ,
    // ---- D4 ledger ----
    output reg  [19:0] y_bytes       ,   // total bytes written
    output reg  [9:0]  y_blocks         // completed slots
);

    localparam ST_IDLE = 2'd0,   // not armed
               ST_RDY  = 2'd1,   // armed: accept words as they come
               ST_DRN  = 2'd2,   // drain accepted word (8 byte writes)
               ST_DONE = 2'd3;   // close: ledgers + set done level
    reg [1:0] st;

    reg [31:0] base_r;
    reg [4:0]  vc_r;
    reg        up2x_r;           // 5b: materialize mode (latched at arm)
    reg [31:0] byte_cnt;         // bytes taken for this block
    reg [63:0] word_r;
    reg        last_r;           // accepted word carried tlast
    reg [2:0]  dr_i;             // drain byte cursor 0..7
    // 5e generic-vc up2x materialization (2026-10-15), CONTIGUOUS-RUN
    // order preserved.  A source row = vc bytes with vc in 1..16 (the
    // 5b vehicle law hard-coded vc==16 with a 2-word row frame; NECK's
    // real shapes need vc=10 and vc=4, where rows cut ACROSS 8B word
    // boundaries).  Accepted words shift into a 24-byte row FIFO; a row
    // frames as soon as >= vc bytes are buffered; its 4*vc quad bytes
    // drain as two 2*vc CONTIGUOUS runs (low cols at +0, high half at
    // +2vc -- identical destinations and byte order to the 5b law, so
    // m9_axi_wr's 8B line builder sees the same flush density and vc=16
    // streams stay byte-exact).  After the row the FIFO shifts down vc
    // bytes and rowoff += 4vc.  hbuf capture is address-driven
    // (order-insensitive), so the seal needs no change.
    reg [7:0]  rbyte [0:23];     // byte FIFO (leftover <= 16 + word 8)
    reg [4:0]  rcount;           // bytes buffered
    reg [6:0]  ox_e;             // emit cursor 0..4*vc-1
    reg [31:0] ux_rowoff;        // completed-rows offset (r * 4vc)
    integer    bi;

    assign y_tready = (st == ST_RDY);

    reg err_r;                                       // sticky byte-count err
    reg done_r;                                      // sticky slot-closed
    assign sc_err  = err_r;
    assign sc_done = done_r;
    wire [31:0] exp_bytes = {24'd0, vc_r, 3'b000};   // 8*vc
    // 5e: run-local high-half emit index (ox_e - 2*vc), valid when
    // ox_e >= 2*vc (kept as a wire: Verilog-2001 bars part-selects on
    // expressions)
    wire [6:0]  ox_hl  = ox_e - {1'b0, vc_r, 1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            yreq <= 1'b0;
            yaddr <= 32'd0; ywdata <= 8'd0;
            byte_cnt <= 32'd0; word_r <= 64'd0; last_r <= 1'b0;
            dr_i <= 3'd0;
            base_r <= 32'd0; vc_r <= 5'd0;
            up2x_r <= 1'b0;
            for (bi = 0; bi < 24; bi = bi + 1) rbyte[bi] <= 8'd0;
            rcount <= 5'd0; ox_e <= 7'd0;
            ux_rowoff <= 32'd0;
            y_bytes <= 20'd0; y_blocks <= 10'd0;
            err_r <= 1'b0;
            done_r <= 1'b0;
        end else begin
            yreq <= 1'b0;                          // default pulse
            case (st)
            ST_IDLE: if (sc_arm) begin
                base_r <= sc_base; vc_r <= sc_vc;
                up2x_r <= sc_up2x;
                byte_cnt <= 32'd0;
                for (bi = 0; bi < 24; bi = bi + 1) rbyte[bi] <= 8'd0;
                rcount <= 5'd0; ox_e <= 7'd0;
                ux_rowoff <= 32'd0;
                err_r <= 1'b0;
                done_r <= 1'b0;                    // re-arm clears the level
                st <= ST_RDY;
            end
            ST_RDY: begin
                if (y_tvalid && y_tready) begin    // accept one word
                    last_r <= y_tlast;
                    byte_cnt <= byte_cnt + 32'd8;
                    if (up2x_r) begin
                        // 5e generic-vc: append the 8 word bytes at
                        // rbyte[rcount..rcount+7] (no shift).  A row frames
                        // whenever rcount+8 >= vc; the row about to drain
                        // is ALWAYS rbyte[0..vc-1] because the row-complete
                        // shift-down-by-vc restores the queue front to 0.
                        for (bi = 0; bi < 8; bi = bi + 1)
                            rbyte[rcount + bi] <= y_tdata[8*bi +: 8];
                        rcount <= rcount + 5'd8;
                        if (rcount + 5'd8 >= {1'b0, vc_r})
                            st <= ST_DRN;
                    end else begin
                        word_r <= y_tdata;
                        st <= ST_DRN;
                        dr_i <= 3'd0;
                    end
                end
            end
            ST_DRN: begin
                if (up2x_r) begin
                    // 5e generic-vc drain: one quad byte per cycle, two
                    // 2*vc contiguous runs.  Both runs' destinations are
                    // base+rowoff+e (low run e<2vc at +0, high run at
                    // +2vc..+4vc-1 -- 2vc+e' == e), data = row byte (e
                    // run-local)>>1, read straight from rbyte[0..vc-1].
                    // (An ox_off=rcount-vc offset here was a 5e bug: it is
                    // 0 only for vc=16 and shifted the row start for every
                    // vc<16 -- 10-15 gate evidence got=0x06/0x04 at addr 0.)
                    // vc=16 is byte-exact vs the 5b law.
                    yaddr  <= base_r + ux_rowoff + {25'd0, ox_e};
                    if (ox_e < {1'b0, vc_r, 1'b0})
                        ywdata <= rbyte[ox_e[4:1]];
                    else
                        ywdata <= rbyte[ox_hl[4:1]];
                    yreq   <= 1'b1;
                    if (ox_e + 7'd1 == {vc_r, 2'b00}) begin
                        // row complete: shift FIFO down by vc, bump rowoff
                        for (bi = 0; bi < 24; bi = bi + 1)
                            rbyte[bi] <= (bi + vc_r < 24)
                                         ? rbyte[bi + vc_r] : 8'd0;
                        rcount    <= rcount - vc_r;
                        ux_rowoff <= ux_rowoff + {24'd0, vc_r, 2'b00};
                        ox_e      <= 7'd0;
                        // another full row already buffered (vc<8 multi-row
                        // words): drain it now; else arm for the next word
                        if (last_r && (rcount == {1'b0, vc_r}))
                            st <= ST_DONE;
                        else if (rcount - vc_r >= vc_r)
                            st <= ST_DRN;
                        else
                            st <= ST_RDY;
                    end else
                        ox_e <= ox_e + 7'd1;
                end else begin
                    // classic path (unchanged, cycle-exact)
                    yaddr  <= base_r + byte_cnt - 32'd8 + {29'd0, dr_i};
                    ywdata <= word_r[8*dr_i +: 8];
                    yreq   <= 1'b1;
                    if (dr_i == 3'd7) begin
                        if (last_r) st <= ST_DONE;  // slot closed
                        else        st <= ST_RDY;
                    end else
                        dr_i <= dr_i + 3'd1;
                end
            end
            ST_DONE: begin
                if (byte_cnt != exp_bytes)
                    err_r <= 1'b1;                   // tlast word count law
                y_bytes  <= y_bytes + exp_bytes[19:0];
                y_blocks <= y_blocks + 10'd1;
                done_r   <= 1'b1;                    // level: held to next arm
                st <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
