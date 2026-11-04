/************************************************************************
 * File Name       : m9_scatter_chw_repack.v
 * Developer       : M11-prep repack line (scatter->CHW geometry wall)
 * Date            : 2026-10-18
 * Project Name    : YOLO object accel (replan M11, M11-prep RTL item)
 * Module Name     : m9_scatter_chw_repack
 * Description     :
 *   M11-prep: slot-tiled scatter plane -> CHW linear plane repacker.
 *   The conv island y_scatter writes its y tensor in the 5b slot law
 *   (m9_y_scatter.v header): byte = r*vc + cv inside a slot, slot base
 *   obuf + stride*b, b = rc + RC*(s + NS*oy).  For the SPPF cv1 shape
 *   [C=128,H=10,W=10] with vc=10/RC=16/NS=1 this resolves to the
 *   layout-ruling law (golden/SPPF/exp_meta.json layout_ruling,
 *   SPEC_m10p4_sppf.md addendum 7.0):
 *
 *       src_addr(c,y,x) = src_base + vc*c + ypitch*y + x
 *
 *   (c pitch = vc <= 16, y pitch = 8*vc*RC, x pitch = 1) while the
 *   PPU island mp5 engine consumes ONE linear (in0_base, CHW) read
 *   (ppu_mp5_engine.v V1.1 header: rd_req(in0_base, CHW)).  vc<=16
 *   can never equal H*W=100 -- the scatter cannot emit CHW and no
 *   descriptor trick repairs the 5x5 window semantics.  This module
 *   is the sanctioned bridge: it walks the DST plane in linear order
 *   (n = c*H*W + y*W + x), computes the slot-law source address per
 *   element, and rewrites the tensor into the CHW plane mp5/xfer
 *   already contract for.
 *
 *   Dataflow (one tensor per arm):
 *     arm (config latch) -> start pulse, accepted only when the
 *     producer-seal level is true (sc_done_lvl && sc_blocks >= nb)
 *     -> one arena byte read per cycle, fixed 1-cycle read latency,
 *     no read backpressure (in-order return contract, see README) ->
 *     write channel trails the read pipe by one cycle -> done sticky
 *     level.  Byte order on both ports is pure linear, so an AXI
 *     glue sees fully coalescible streams on both sides.
 *
 *   Correctness-first byte-per-cycle engine (M9.1 style): 12,800 B
 *   SPPF plane = ~12.8 us @50 MHz, ~0.3% of the SPPF frame budget --
 *   not worth a wider datapath at M11-prep.  All address math is
 *   incremental (ch_base/yoff accumulators), no runtime multiplies
 *   in the beat path, 32-bit adds only -- trivial 50 MHz closure.
 *
 *   Poison/negative contract (M11-prep gate 3):
 *     err 0x01 RP_ERR_UNSEALED : start while producer seal false
 *                                (slot writes incomplete) -> refused,
 *                                zero bytes moved, sticky err.
 *     err 0x02 RP_ERR_NOT_ARMED: start with no valid arm.
 *     err 0x03 RP_ERR_GEOM_LANE: arm with W > vc (x would spill the
 *                                slot lane width) -> arm rejected.
 *     err 0x04 RP_ERR_GEOM_ZERO: arm with C/H/W/vc == 0.
 *     err 0x05 RP_ERR_BUSY     : arm or start while a run is active.
 *   err/done are STICKY LEVELS held to the next successful arm --
 *   the exact sc_done/sc_err contract of m9_y_scatter (V1.1 lesson:
 *   a 1-cycle pulse fires and vanishes before a polling waiter
 *   looks; the issuer polls STATUS over ~20 cycles).
 *
 *   Single always block, single driver per register (multi-driven
 *   register = sim/synth divergence law; build double gate 8-6859).
 *   No continuous-assign memory reads (xsim legacy pattern law).
 *
 * Dependencies    : none (pure RTL, no IP, no .sv)
 * Revision History:
 *   - V1.0 (2026-10-18) : first release, M11-prep xsim 3-gate ladder
 *     (addr transform / back-to-back frames / poison), run01.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_scatter_chw_repack (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-tensor arm: config latch (mirrors the sc_arm contract;
    //      accepted only when idle; re-arm clears done/err levels) ----
    input  wire        rp_arm        ,
    input  wire [31:0] rp_src_base   ,   // slot-tiled src arena byte base
    input  wire [31:0] rp_dst_base   ,   // CHW linear dst arena byte base
    input  wire [15:0] rp_c          ,   // tensor channels C
    input  wire [15:0] rp_h          ,   // tensor H
    input  wire [15:0] rp_w          ,   // tensor W  (lane law: W <= vc)
    input  wire [15:0] rp_vc         ,   // slot channel pitch (= lane count)
    input  wire [31:0] rp_ypitch     ,   // slot y pitch = 8*vc*RC
    input  wire [15:0] rp_nb         ,   // producer blocks expected at seal
    // ---- producer seal + trigger ----
    input  wire        sc_done_lvl   ,   // y_scatter sticky slot-closed level
    input  wire [9:0]  sc_blocks     ,   // y_scatter y_blocks ledger
    input  wire        rp_start      ,   // 1-cycle trigger pulse
    output wire        rp_busy       ,
    output wire        rp_done       ,   // sticky level, held to next arm
    output wire        rp_err        ,   // sticky level, held to next arm
    output reg  [7:0]  rp_err_code   ,
    // ---- arena byte read port (fixed 1-cycle latency, in-order, no
    //      backpressure -- see README integration contract) ----
    output reg  [31:0] raddr         ,
    output reg         rreq          ,
    input  wire [7:0]  rdata         ,
    // ---- arena byte write port (always-ready contract, y_scatter law) ----
    output reg  [31:0] waddr         ,
    output reg         wreq          ,
    output reg  [7:0]  wdata         ,
    // ---- D4 ledger ----
    output reg  [23:0] rp_bytes          // bytes written this tensor
);

    localparam ST_IDLE  = 3'd0,   // not armed / waiting
               ST_RUN   = 3'd1,   // beat pipeline active
               ST_DRAIN = 3'd2,   // last read captured -> final write
               ST_DONE  = 3'd3;   // close: ledgers + done level
    reg [2:0] st;

    // err codes (poison contract, spec section 4)
    localparam RP_ERR_NONE     = 8'h00,
               RP_ERR_UNSEALED = 8'h01,
               RP_ERR_NOT_ARMED= 8'h02,
               RP_ERR_GEOM_LANE= 8'h03,
               RP_ERR_GEOM_ZERO= 8'h04,
               RP_ERR_BUSY     = 8'h05;

    // latched config
    reg [31:0] src_base_r, dst_base_r, ypitch_r;
    reg [15:0] c_r, h_r, w_r, vc_r, nb_r;
    reg [31:0] total_r;          // C*H*W (arm-time multiply, config rate)
    reg        armed_r;

    // linear walk coordinates (dst order) + incremental src accumulators
    reg [15:0] x_r, y_r;         // lane cursors (c itself is implicit in
                                 // ch_base_r: one channel == one pass)
    reg [31:0] n_r;              // linear dst index
    reg [31:0] ch_base_r;        // src_base + vc*current_channel
    reg [31:0] yoff_r;           // ypitch*current_y (within channel)

    // read->write pipeline shadow (1-cycle latency contract)
    reg        p_valid_r;
    reg [31:0] p_waddr_r;

    reg        err_r, done_r;
    assign rp_busy = (st == ST_RUN) || (st == ST_DRAIN);
    assign rp_err  = err_r;
    assign rp_done = done_r;

    // producer seal: sticky slot-closed level AND the block ledger says
    // every expected slot closed (blocks short = slot writes incomplete
    // = the gate-3 poison surface)
    wire sealed = sc_done_lvl && (nb_r != 16'd0) && (sc_blocks >= nb_r);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            armed_r <= 1'b0;
            err_r <= 1'b0; done_r <= 1'b0;
            rp_err_code <= RP_ERR_NONE;
            src_base_r <= 32'd0; dst_base_r <= 32'd0; ypitch_r <= 32'd0;
            c_r <= 16'd0; h_r <= 16'd0; w_r <= 16'd0; vc_r <= 16'd0;
            nb_r <= 16'd0; total_r <= 32'd0;
            x_r <= 16'd0; y_r <= 16'd0; n_r <= 32'd0;
            ch_base_r <= 32'd0; yoff_r <= 32'd0;
            p_valid_r <= 1'b0; p_waddr_r <= 32'd0;
            rreq <= 1'b0; raddr <= 32'd0;
            wreq <= 1'b0; waddr <= 32'd0; wdata <= 8'd0;
            rp_bytes <= 24'd0;
        end else begin
            // default strobes; levels are set explicitly below
            rreq <= 1'b0;
            wreq <= 1'b0;

            // ---- read-pipe capture: the read issued last cycle returns
            // this cycle (fixed 1-cycle latency).  Guarded by the shadow
            // valid so no phantom write ever leaves the pipe. ----
            if (p_valid_r) begin
                wreq     <= 1'b1;
                waddr    <= p_waddr_r;
                wdata    <= rdata;
                rp_bytes <= rp_bytes + 24'd1;
                p_valid_r <= 1'b0;
            end

            // command refusal at the top level so a pulse landing
            // mid-run is JUDGED (err 0x05), not silently dropped
            if (rp_busy && (rp_arm || rp_start)) begin
                err_r <= 1'b1;
                rp_err_code <= RP_ERR_BUSY;
            end

            case (st)
            ST_IDLE: begin
                if (!rp_busy && rp_arm) begin
                    if ((rp_c == 16'd0) || (rp_h == 16'd0) ||
                                 (rp_w == 16'd0) || (rp_vc == 16'd0)) begin
                        // degenerate geometry: arm rejected
                        err_r <= 1'b1;
                        rp_err_code <= RP_ERR_GEOM_ZERO;
                        armed_r <= 1'b0;
                    end else if (rp_w > rp_vc) begin
                        // x would spill the slot lane width -- the
                        // slot law has no byte for it (layout wall)
                        err_r <= 1'b1;
                        rp_err_code <= RP_ERR_GEOM_LANE;
                        armed_r <= 1'b0;
                    end else begin
                        // clean arm: latch config, clear sticky levels
                        src_base_r <= rp_src_base;
                        dst_base_r <= rp_dst_base;
                        ypitch_r   <= rp_ypitch;
                        c_r <= rp_c; h_r <= rp_h; w_r <= rp_w;
                        vc_r <= rp_vc; nb_r <= rp_nb;
                        total_r <= {16'd0, rp_c} * {16'd0, rp_h} *
                                   {16'd0, rp_w};      // config-rate mul
                        armed_r <= 1'b1;
                        err_r <= 1'b0;
                        rp_err_code <= RP_ERR_NONE;
                        done_r <= 1'b0;
                        rp_bytes <= 24'd0;
                    end
                end else if (rp_start) begin
                    if (!armed_r) begin
                        err_r <= 1'b1;
                        rp_err_code <= RP_ERR_NOT_ARMED;
                    end else if (!sealed) begin
                        // POISON GATE: slot writes incomplete -- refuse,
                        // move zero bytes, drop the arm (re-arm required)
                        err_r <= 1'b1;
                        rp_err_code <= RP_ERR_UNSEALED;
                        armed_r <= 1'b0;
                    end else begin
                        // launch: walk dst linear, src by slot law
                        x_r <= 16'd0; y_r <= 16'd0; n_r <= 32'd0;
                        ch_base_r <= src_base_r;
                        yoff_r <= 32'd0;
                        st <= ST_RUN;
                    end
                end
            end

            ST_RUN: begin
                // issue this beat's read; the capture above drains the
                // previous beat's return onto the write port
                rreq      <= 1'b1;
                raddr     <= ch_base_r + yoff_r + {16'd0, x_r};
                p_valid_r <= 1'b1;              // overrides capture clear
                p_waddr_r <= dst_base_r + n_r;

                // advance (x fastest == dst linear order); src address
                // stays incremental -- no multiplies in the beat path
                if (x_r + 16'd1 == w_r) begin
                    x_r <= 16'd0;
                    if (y_r + 16'd1 == h_r) begin
                        y_r       <= 16'd0;
                        yoff_r    <= 32'd0;
                        ch_base_r <= ch_base_r + {16'd0, vc_r};
                    end else begin
                        y_r    <= y_r + 16'd1;
                        yoff_r <= yoff_r + ypitch_r;
                    end
                end else begin
                    x_r <= x_r + 16'd1;
                end
                n_r <= n_r + 32'd1;
                if (n_r + 32'd1 == total_r)
                    st <= ST_DRAIN;
            end

            ST_DRAIN: begin
                // final read returns this cycle; the common capture
                // writes it.  Nothing left to issue.
                st <= ST_DONE;
            end

            ST_DONE: begin
                done_r  <= 1'b1;                // level: held to next arm
                armed_r <= 1'b0;
                st <= ST_IDLE;
            end

            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
