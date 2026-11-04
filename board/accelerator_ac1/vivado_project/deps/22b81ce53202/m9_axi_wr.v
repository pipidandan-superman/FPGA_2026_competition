/************************************************************************
 * File Name       : m9_axi_wr.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_axi_wr
 * Description     :
 *   M9.5b AXI32 HP write adapter for the proven m9_y_scatter byte face
 *   (02_m9_issuer_spec.md section 7: y scatter HP0 write).
 *
 *   Client face: yaddr/yreq/ywdata -- yreq is a 1-cycle PULSE per byte
 *   (y scatter has no write-side stall; see its default-pulse law).
 *   A 512-deep byte FIFO absorbs pulse bursts while a line is flushing;
 *   contiguous bytes combine into 8-byte AXI beats (single ARLEN=0 AW
 *   at the ALIGNED base with WSTRB lanes -- the AXI start address must
 *   be beat-aligned, and the lane already encodes paddr[2:0]); a skip
 *   (non-contiguous byte) flushes the pending line.
 *
 *   Depth law (5b M10.5): 128 -> 512.  The 5b up2x scatter emits 4x
 *   the byte volume per source word; even with the scatter's
 *   contiguous-run emission order (32B runs = classic 8B-line flush
 *   density), the worst analyzed run is ~4x longer than the classic
 *   ~268B run, so the classic 128 depth no longer bounds the deficit
 *   (290B > 128).  512 leaves ~1.8x margin.  Cost 1 RAMB36
 *   (20,480 bit < 36Kb); the fill gauge guards the probe face as before.
 *
 *   Tail law: the last arm of a frame may leave a partial line -- the
 *   wrapper pulses `flush` at frame end (top busy falling edge) so the
 *   arena is complete before PS observes done.
 *
 *   Proven-core discipline: m9_y_scatter stays byte-face identical;
 *   this module is a sibling, not a change.
 *
 *   CUT1 (2026-10-23, gemm_cut1_wrfifo_bram_run01): the 512x40 FF array
 *   (~20.5k FF, LUT/FF scout Top1) becomes a simple-dual-port block RAM
 *   (ram_style="block").  The combinational read fifo[rp] is replaced by
 *   a registered read with a LOOKAHEAD read address rd_addr = rp +
 *   consume, so the +1 cycle of BRAM read latency is spent on the address
 *   port, not on the data path: rd_addr(k) = rp(k+1), hence fhead_r(k+1)
 *   tracks fifo[rp(k+1)] and fhead is cycle-identical to the FF comb-read
 *   V1.0 at EVERY cycle.  The two reachable read/write same-address
 *   collisions (empty-FIFO write wp==rp; fill==1 consume+write wp==rp+1)
 *   are forwarded through a REGISTERED bypass mux after the RAM output
 *   register (V2.2 -- see revision history), so the RAM read port itself
 *   stays an unconditional synchronous read and infers one RAMB36E1.
 *   No prefetch valid flag, no episode skew, no output skid: external
 *   AXI handshake timing and busy/full_wait cycle semantics are
 *   unchanged by construction.  Bit-exact evidence:
 *   4_metrics/logs/2026-10-23_gemm_cut1_wrfifo_bram_run01/ (TB compares
 *   every output and internal state cycle-by-cycle vs the V1.0 golden).
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 *   - V2.1 (2026-10-23) : CUT1 FF FIFO -> WRITE_FIRST BRAM, lookahead
 *                         read address, cycle-identical interface.
 *   - V2.2 (2026-10-23) : CUT1 rev2 -- collision forwarding moved from a
 *                         write-bus mux in the read path (made
 *                         ram_style="block" infeasible, silent LUTRAM
 *                         fallback, Vivado Synth 8-6849) to a registered
 *                         bypass after the RAM output register; the RAM
 *                         read port is now an unconditional synchronous
 *                         read -> RAMB36E1 inference, still cycle-
 *                         identical (bit-exact TB rerun, see run dir).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_axi_wr (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- client byte-write face (pulse per byte) ----
    input  wire [31:0] yaddr         ,
    input  wire        yreq          ,
    input  wire [7:0]  ywdata        ,
    input  wire        flush         ,   // frame end: drain + flush line
    output wire        busy          ,
    // ---- AXI32 write master (single-beat 64b, WSTRB) ----
    output reg  [31:0] m_awaddr      ,
    output wire [3:0]  m_awlen       ,
    output reg         m_awvalid     ,
    input  wire        m_awready     ,
    output reg  [63:0] m_wdata       ,
    output reg  [7:0]  m_wstrb       ,
    output reg         m_wvalid      ,
    input  wire        m_wready      ,
    input  wire [1:0]  m_bresp       ,
    input  wire        m_bvalid      ,
    output reg         m_bready,
    output wire        fifo_full_wait
);

    // ---------------- FSM ----------------
    localparam ST_FILL  = 2'd0,  // pull FIFO bytes, build the line
               ST_AW    = 2'd1,  // AW handshake
               ST_W     = 2'd2,  // W handshake
               ST_B     = 2'd3;  // B handshake (single outstanding)
    reg [1:0] st;

    // byte FIFO pointers (512 deep; {addr[31:0], data[7:0]}).
    // Field law unchanged: the address is fhead[39:8] and the data is
    // fhead[7:0] -- slicing the address at [31:0] silently appends the
    // data byte to the address (M9.5b arena map forensics).
    reg [8:0]  wp, rp;
    wire       fnempty = (wp != rp);

    // ---------------- BRAM FIFO storage (CUT1) ----------------
    // WRITE_FIRST simple-dual-port block RAM.  The lookahead address
    // rd_addr = rp + consume makes the registered output equal to the
    // V1.0 combinational fifo[rp] at every cycle:
    //   rp(k+1) = rp(k) + consume(k)          (rp update law, unchanged)
    //   rd_addr(k) = rp(k) + consume(k) = rp(k+1)
    //   fhead_r(k+1) = fifo-after-write(k)[rd_addr(k)] = fifo[rp(k+1)]
    // The WRITE_FIRST override (yreq && wp==rd_addr) is the only escape
    // from the array-read branch and covers exactly the two reachable
    // same-address collisions, where the value being written IS the
    // value the slot (and therefore the next fhead) takes:
    //   (a) !consume && yreq && wp==rp          (write into empty FIFO)
    //   (b) consume  && yreq && wp==rp+9'd1     (fill==1: the byte being
    //                                            written this cycle is
    //                                            the next head)
    // Both are exercised and coverage-counted in the CUT1 bit-exact TB.
    // fhead_r needs no reset: fnempty gates every consumer, and both
    // sides agree on X (compared with case-equality in the TB).
    (* ram_style = "block" *) reg [39:0] fifo [0:511];
    reg  [39:0] fhead_r;

    // Registered collision bypass (CUT1 rev2): the two reachable
    // same-address write/read collisions both need the in-flight write
    // word as the next head.  Staging it in a register and muxing AFTER
    // the RAM output register (instead of muxing the write bus into the
    // read data path, which made ram_style="block" infeasible and
    // silently fell back to LUTRAM) keeps the read port a pure
    // unconditional synchronous read -> RAMB36 inference (exp_v3-proven).
    // Cycle identity is preserved exactly: at any cycle k+1 with
    // coll_r(k+1)=1, golden fhead = fifo[rp(k+1)] = fifo[wp(k)] = the
    // word written at k = wreg_r(k+1); with coll_r=0 the read slot was
    // not written at k, so fhead_r is already correct.  BRAM write mode
    // is therefore don't-care (collision cycles never consume fhead_r).
    reg        coll_r;
    reg [39:0] wreg_r;

    wire [39:0] fhead = coll_r ? wreg_r : fhead_r;
    wire [31:0] paddr = fhead[39:8];
    wire [7:0]  pdata = fhead[7:0];

    // pending line (first byte address + up to 8 bytes)
    reg [31:0] ln_base;
    reg [2:0]  ln_cnt;                 // bytes 0..7
    reg [63:0] ln_data;
    reg [7:0]  ln_strb;

    // append law: SAME 8-byte aligned line AND exactly the next address
    // of the run.  The same-line pin is load-bearing for an unaligned
    // line start (e.g. base 0x1005 fills lanes 5-7): the byte at 0x1008
    // belongs to the NEXT line -- AXI maps lane n of a beat to
    // aligned_base+n, so absorbing it at lane 0 would land it at 0x1000.
    wire contig = (ln_cnt != 3'd0) &&
                  (paddr[31:3] == ln_base[31:3]) &&
                  (paddr[31:0] == ln_base + {29'd0, ln_cnt});

    // consume law (one head byte per cycle at most, in ST_FILL only)
    wire consume = (st == ST_FILL) && fnempty &&
                   (ln_cnt == 3'd0 || contig);

    // lookahead read address (see storage law above)
    wire [8:0] rd_addr = rp + (consume ? 9'd1 : 9'd0);

    // BRAM write port (wp, yreq) + unconditional synchronous read port.
    // The read is UNCONDITIONAL (no write-data mux in the read path) --
    // this is what makes block-RAM inference feasible (exp_v3).
    always @(posedge clk) begin
        if (yreq)
            fifo[wp] <= {yaddr, ywdata};
    end
    always @(posedge clk) begin
        fhead_r <= fifo[rd_addr];
    end
    always @(posedge clk) begin
        coll_r <= yreq && (wp == rd_addr);
        if (yreq)
            wreg_r <= {yaddr, ywdata};
    end

    // fill gauge: probe/overflow face (a capture that makes fill touch
    // 512 overwrites unconsumed bytes -- the gate TB fails on margin)
    reg  [9:0] fill;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                    fill <= 10'd0;
        else if (yreq && !consume)                     fill <= fill + 10'd1;
        else if (!yreq && consume)                     fill <= fill - 10'd1;
    end

    assign m_awlen = 4'd0;
    assign busy = (st != ST_FILL) || fnempty || (ln_cnt != 3'd0);
    assign fifo_full_wait = yreq && (fill == 10'd512);

    // ---------------- sequencer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_FILL;
            wp <= 7'd0; rp <= 7'd0;
            ln_base <= 32'd0; ln_cnt <= 3'd0;
            ln_data <= 64'd0; ln_strb <= 8'd0;
            m_awvalid <= 1'b0; m_awaddr <= 32'd0;
            m_wvalid <= 1'b0; m_wdata <= 64'd0; m_wstrb <= 8'd0;
            m_bready <= 1'b0;
        end else begin
            // ---- FIFO capture (client pulses, never back-pressured;
            // sustained contiguous fill 1B/cyc vs ~0.73B/cyc drain --
            // the 512-deep FIFO absorbs the worst analyzed run (5b up2x:
            // ~290B deficit over a ~1072B quad run) and the fill gauge
            // guards it) ----
            if (yreq) begin
                wp <= wp + 9'd1;
            end
            case (st)
            ST_FILL: begin
                if (fnempty) begin
                    if (ln_cnt == 3'd0) begin
                        // start a line at this byte (may be unaligned)
                        rp <= rp + 9'd1;               // consume head
                        ln_base <= paddr;
                        ln_cnt  <= 3'd1;
                        ln_data <= {56'd0, pdata} << (8 * paddr[2:0]);
                        ln_strb <= 8'd1 << paddr[2:0];
                    end else if (contig) begin
                        rp <= rp + 9'd1;               // consume head
                        ln_data <= ln_data | ({56'd0, pdata} << (8 * paddr[2:0]));
                        ln_strb <= ln_strb | (8'd1 << paddr[2:0]);
                        if (ln_cnt == 3'd7) begin
                            // line full (8th byte lands this edge; the
                            // ln_cnt 3b field cannot hold 8 -- do NOT
                            // increment): flush, ln_cnt cleared in ST_B.
                            // AW carries the ALIGNED base (AXI law:
                            // start address aligned to the beat); lanes
                            // already encode paddr[2:0].
                            m_awaddr  <= {ln_base[31:3], 3'b000};
                            m_awvalid <= 1'b1;
                            st <= ST_AW;
                        end else
                            ln_cnt <= ln_cnt + 3'd1;
                    end else begin
                        // skip: flush the pending line; do NOT advance
                        // rp -- the head byte re-pulls after ST_B and
                        // starts the next line (dropping it would lose
                        // a y byte)
                        m_awaddr  <= {ln_base[31:3], 3'b000};
                        m_awvalid <= 1'b1;
                        st <= ST_AW;
                    end
                end else if (flush && ln_cnt != 3'd0) begin
                    m_awaddr  <= {ln_base[31:3], 3'b000};
                    m_awvalid <= 1'b1;
                    st <= ST_AW;
                end
                // flush with empty line/FIFO: nothing to do (busy drops)
            end
            ST_AW: if (m_awready) begin
                m_awvalid <= 1'b0;
                m_wdata   <= ln_data;
                m_wstrb   <= ln_strb;
                m_wvalid  <= 1'b1;
                st <= ST_W;
            end
            ST_W: if (m_wready) begin
                m_wvalid <= 1'b0;
                m_bready <= 1'b1;
                st <= ST_B;
            end
            ST_B: if (m_bvalid) begin
                m_bready <= 1'b0;
                ln_cnt   <= 3'd0;
                ln_strb  <= 8'd0;
                st <= ST_FILL;
            end
            default: st <= ST_FILL;
            endcase
        end
    end

endmodule
