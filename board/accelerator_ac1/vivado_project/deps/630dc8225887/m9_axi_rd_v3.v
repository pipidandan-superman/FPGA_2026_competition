//-----------------------------------------------------------------------------
// File Name    : m9_axi_rd_v3.v
// Developer    : M9.3 V3 issuer redesign line
// Date         : 2026-10-13
// Project      : yolo7020 competition -- M9.3 V3 issuer redesign
// Module       : m9_axi_rd_v3
// Description  : DDR read adapter V3 -- m9_axi_rd_v2 (V2.1/V2.2/V2.3)
//                plus:
//                (1) LINE-READ CLIENT PORT (new): pulsed 8B-aligned line
//                    requests lreq_line/laddr_line, pipelined (1/cycle),
//                    responses rvalid_line/rdata_line IN REQUEST ORDER
//                    via a 16-deep line-status queue (LSQ).  Hit ->
//                    respond as soon as the entry reaches the queue
//                    head; miss -> demand-enqueue the line, respond on
//                    fill.  The head-of-LSQ check is the whole response
//                    sequencer: `head valid => pop+respond`, which is
//                    in-order and self-synchronizing.  This is the port
//                    m9_x_window_v3 and m9_w_feeder_v3 (preload) attach
//                    to.  Requests must not overflow the LSQ (window
//                    emits <=5/tap at >=3 cyc/tap; feeder preload is
//                    sequential -- 16 is deep 3x over; sim fatal on
//                    overflow, synth sets lsq_ovf sticky).
//                (2) EXPLICIT SPECULATION WINDOW localparam SPEC_N=8:
//                    the speculative frontier may run at most SPEC_N
//                    lines past the LAST DEMAND line (V2.1 let the
//                    budget alone bound it at 32 -- functionally fine
//                    but unbounded-past-demand; the explicit window
//                    documents the guarantee the window's line span
//                    relies on and bounds wild-read exposure of the
//                    INJ-5C class even harder).  Deeper outstanding
//                    capacity (32 AR) is unchanged -- SPEC_N only caps
//                    how far AHEAD of demand speculation may run.
//                (3) Line-port demand has priority over the legacy
//                    byte port (byte port kept byte-contract-identical
//                    for legacy TBs / the V1 socket; no V3 client uses
//                    it in production wiring).
//
//                UNCHANGED from V2.1/V2.2/V2.3 (the five bring-up fixes
//                and the two inference laws, verbatim):
//                  (a) AR pop gates on the REGISTERED m_arvalid_o on the
//                      bus; (b) m_arvalid masked with !ar_pop; (c) one
//                      shared outstanding budget ar_cnt+rt_cnt < 32;
//                  (d) one-cycle rready_gap after each consumed beat;
//                  (e) 5-bit pointers wrapping at the 32-deep queues;
//                  (f) arrays in a posedge-only write process (V2.3
//                      Synth 8-4767 law: no async reset sensitivity).
//
//                Safety: demand addresses come only from client
//                requests; speculation is demand-seeded and SPEC_N-
//                bounded, so reads stay inside the plane's reserved
//                DDR window.  m_rresp_i intentionally not acted on
//                (frozen INJ-5D contract gap; V1 zero-diff semantics
//                preserved).
// Dependencies : none (leaf module; u_xrd/u_wrd in m9_intra_axi_top)
// Revision History:
//   - V3.0 (2026-10-13) : initial release (Phase B, M9.3 V3 redesign).
//                         SPEC_N explicit window + line client port.
//   - V3.1 (2026-10-13) : two unit-TB proven fixes:
//                         (i) LSQ pointers 4-bit (wrap AT the 16-deep
//                         queue); 5-bit walked past lsq_mem[15] into
//                         out-of-bounds X after 16 lifetime pushes and
//                         deadlocked the head check;
//                         (ii) dem_seen gate on enq_spec -- at reset
//                         spec_base==dem_last==0 made the window true
//                         and the DUT wild-fetched lines 0..7 below any
//                         demand, violating the demand-seeded law.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module m9_axi_rd_v3 (
    input  wire        clk_i            ,
    input  wire        rst_n_i          ,
    // ---- legacy client byte-read face (V1 contract, kept) ----
    input  wire [31:0] raddr_i          ,   // byte address
    input  wire        rreq_i           ,   // held high until rvalid_o pulse
    output reg  [7:0]  rdata_o          ,   // byte data, valid with rvalid_o
    output reg         rvalid_o         ,   // one-cycle pulse per request
    // ---- V3 client LINE-read face (pipelined, in-order) ----
    input  wire [31:0] laddr_line_i     ,   // 8B-aligned byte address
    input  wire        lreq_line_i      ,   // one-cycle pulse per request
    output reg  [63:0] rdata_line_o     ,   // line data, valid with rvalid
    output reg         rvalid_line_o    ,   // one-cycle pulse, request order
    output reg         lsq_ovf_o        ,   // LSQ overflow (sticky, synth)
    // ---- AXI4 read master (single ID, single-beat bursts, in-order R) ----
    output reg  [31:0] m_araddr_o       ,
    output reg  [3:0]  m_arlen_o        ,   // tied 4'd0 (one 64b beat per AR)
    output reg         m_arvalid_o      ,
    input  wire        m_arready_i      ,
    input  wire [63:0] m_rdata_i        ,
    input  wire [1:0]  m_rresp_i        ,   // ignored (INJ-5D contract gap)
    input  wire        m_rvalid_i       ,
    input  wire        m_rlast_i        ,
    output wire        m_rready_o       ,   // !rready_gap (see below)
    // trace probe: client waiting on a not-yet-resident line
    output wire        ddr_gap_wait_o
);

    //--------------------------------------------------------------------------
    // Parameters / localparams
    //--------------------------------------------------------------------------
    localparam [5:0] FIFO_DEPTH   = 6'd32;   // max outstanding ARs
    localparam [4:0] LSQ_DEPTH    = 5'd16;   // line-status queue
    localparam [3:0] SPEC_N       = 4'd8;    // spec window past last demand
    localparam       ST_IDLE      = 1'b0;
    localparam       ST_SEND      = 1'b1;

    //--------------------------------------------------------------------------
    // Line buffer state (64 lines x 8B, direct-mapped)
    //--------------------------------------------------------------------------
    (* ram_style = "distributed" *) reg  [63:0] line_buf  [0:63];
    (* ram_style = "distributed" *) reg  [22:0] tag_buf   [0:63];
    reg  [63:0] line_valid;
    reg  [63:0] line_pend;

    //--------------------------------------------------------------------------
    // Outstanding queues (AR issue order / R return order)
    //--------------------------------------------------------------------------
    reg  [28:0] ar_mem [0:31];
    reg  [4:0]  ar_wptr;
    reg  [4:0]  ar_rptr;
    reg  [5:0]  ar_cnt;
    reg  [28:0] rt_mem [0:31];
    reg  [4:0]  rt_wptr;
    reg  [4:0]  rt_rptr;
    reg  [5:0]  rt_cnt;

    //--------------------------------------------------------------------------
    // Speculative frontier + last demand line (SPEC_N window, V3)
    //--------------------------------------------------------------------------
    reg  [28:0] spec_base;
    reg  [28:0] dem_last;
    reg         dem_seen;   // first demand has seeded the frontier; without
                            // this gate spec_base==dem_last==0 at reset and
                            // the DUT wild-fetches lines 0..7 below any
                            // real demand (violates the demand-seeded law)

    //--------------------------------------------------------------------------
    // Line-status queue (V3): every line-port request pushes its full
    // addr[31:3] line address; the head responds (and pops) as soon as
    // that EXACT line (index + tag) is resident.  In-order by
    // construction.  Tag-exactness matters: a same-index different-tag
    // fill (byte-port demand or speculation aliasing) must NOT satisfy
    // the head -- the head then demand-enqueues its own address and
    // self-heals.
    //--------------------------------------------------------------------------
    reg  [28:0] lsq_mem [0:15];
    reg  [3:0]  lsq_wptr;   // 4-bit: wraps AT the 16-deep LSQ (5-bit would
    reg  [3:0]  lsq_rptr;   // walk past lsq_mem[15] -> OOB X and deadlock)
    reg  [5:0]  lsq_cnt;

    //--------------------------------------------------------------------------
    // Serve bookkeeping
    //--------------------------------------------------------------------------
    reg         served;

    //--------------------------------------------------------------------------
    // FSM state register
    //--------------------------------------------------------------------------
    reg         state;
    reg         next_state;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    //--------------------------------------------------------------------------
    // Combinational request-side decode
    //--------------------------------------------------------------------------
    wire [5:0]  dem_idx  = raddr_i[8:3];
    wire [22:0] dem_tag  = raddr_i[31:9];
    wire        hit      = line_valid[dem_idx] && (tag_buf[dem_idx] == dem_tag);

    wire [6:0] occ_total  = {1'b0, ar_cnt} + {1'b0, rt_cnt};
    wire       fifo_space = (occ_total < {1'b0, FIFO_DEPTH});

    // V3 demand sources (line port has priority):
    //  (1) head-of-LSQ miss: the oldest un-served line request is not
    //      resident (tag-exact) -> demand-fetch it (line_pend covers
    //      the case where the fill is already in flight for THIS tag:
    //      the head check turns true when that fill lands)
    //  (2) legacy byte port demand (V1 semantics)
    wire [28:0] lsq_head_addr = lsq_mem[lsq_rptr];
    wire [5:0]  lsq_head_ix   = lsq_head_addr[5:0];
    wire        lsq_head_hit  = (lsq_cnt != 6'd0) &&
                                line_valid[lsq_head_ix] &&
                                (tag_buf[lsq_head_ix] == lsq_head_addr[28:6]);
    wire        lsq_head_miss = (lsq_cnt != 6'd0) && !lsq_head_hit;
    wire        enq_ldem = lsq_head_miss &&
                           !line_pend[lsq_head_ix] && fifo_space;
    wire        enq_bdem = (!enq_ldem) && rreq_i && !hit &&
                           !line_pend[dem_idx] && fifo_space;
    wire        enq_dem  = enq_ldem || enq_bdem;
    wire [28:0] dem_addr = enq_ldem ? lsq_head_addr : raddr_i[31:3];

    // SPEC_N-bounded speculation past the last demand line
    wire [28:0] spec_idx  = spec_base[5:0];
    wire        spec_in_win = (spec_base - dem_last) < {25'd0, SPEC_N};
    wire        enq_spec = (!enq_dem) && dem_seen && fifo_space &&
                           spec_in_win &&
                           (!line_valid[spec_idx]) && (!line_pend[spec_idx]);
    wire        enq_fire = enq_dem || enq_spec;
    wire [28:0] enq_addr = enq_dem ? dem_addr : spec_base;
    wire [5:0]  enq_idx  = enq_addr[5:0];

    wire        serve_pulse = rreq_i && hit && !served;

    //--------------------------------------------------------------------------
    // Byte-lane mux (legacy port, unchanged)
    //--------------------------------------------------------------------------
    reg [7:0] lane;
    always @(*) begin
        case (raddr_i[2:0])
            3'd0    : lane = line_buf[dem_idx][7:0];
            3'd1    : lane = line_buf[dem_idx][15:8];
            3'd2    : lane = line_buf[dem_idx][23:16];
            3'd3    : lane = line_buf[dem_idx][31:24];
            3'd4    : lane = line_buf[dem_idx][39:32];
            3'd5    : lane = line_buf[dem_idx][47:40];
            3'd6    : lane = line_buf[dem_idx][55:48];
            3'd7    : lane = line_buf[dem_idx][63:56];
            default : lane = line_buf[dem_idx][7:0];
        endcase
    end

    //--------------------------------------------------------------------------
    // AR channel FSM (V2.1 fix (a)/(b) preserved)
    //--------------------------------------------------------------------------
    wire       ar_accept = (state == ST_SEND) && m_arvalid_o &&
                           m_arready_i;
    reg        ar_pop;
    reg        rt_push;
    reg        ar_valid_n;
    reg [31:0] ar_addr_n;

    always @(*) begin
        next_state = state;
        ar_pop     = 1'b0;
        rt_push    = 1'b0;
        ar_valid_n = 1'b0;
        ar_addr_n  = {ar_mem[ar_rptr], 3'b000};
        case (state)
            ST_IDLE: begin
                if (ar_cnt != 6'd0) begin
                    next_state = ST_SEND;
                end
            end
            ST_SEND: begin
                ar_valid_n = 1'b1;
                if (ar_accept) begin
                    ar_pop     = 1'b1;
                    rt_push    = 1'b1;
                    next_state = ST_IDLE;
                end
            end
            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Registered outputs (AXI AR + legacy byte serve + V3 line serve)
    //--------------------------------------------------------------------------
    wire        lsq_head_ok  = lsq_head_hit;
    wire [5:0]  lsq_head_idx = lsq_head_ix;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            m_arvalid_o    <= 1'b0;
            m_araddr_o     <= 32'd0;
            m_arlen_o      <= 4'd0;
            rvalid_o       <= 1'b0;
            rdata_o        <= 8'd0;
            rvalid_line_o  <= 1'b0;
            rdata_line_o   <= 64'd0;
            lsq_ovf_o      <= 1'b0;
            served         <= 1'b0;
        end else begin
            m_arvalid_o   <= ar_valid_n && !ar_pop;
            m_araddr_o    <= ar_addr_n;
            m_arlen_o     <= 4'd0;
            rvalid_o      <= serve_pulse;
            rdata_o       <= lane;
            // V3 line-port response sequencer: head resident -> respond
            rvalid_line_o <= lsq_head_ok;
            rdata_line_o  <= line_buf[lsq_head_idx];
            if (lreq_line_i) begin
                if (lsq_cnt == {1'b0, LSQ_DEPTH})
                    lsq_ovf_o <= 1'b1;
            end
            if (!rreq_i) begin
                served <= 1'b0;
            end else if (serve_pulse) begin
                served <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // R-channel pacing (V2.1 fix (d) preserved)
    //--------------------------------------------------------------------------
    reg        rready_gap;

    wire       beat_consume = m_rvalid_i && m_rlast_i && m_rready_o &&
                              (rt_cnt != 6'd0);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rready_gap <= 1'b0;
        end else if (beat_consume) begin
            rready_gap <= 1'b1;
        end else begin
            rready_gap <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // Array writes -- V2.3 inference law: NO async reset in this process.
    //--------------------------------------------------------------------------
    wire        rt_pop     = beat_consume;
    wire [5:0]  rt_idx     = rt_mem[rt_rptr][5:0];
    wire [22:0] rt_tag     = rt_mem[rt_rptr][28:6];

    always @(posedge clk_i) begin
        if (enq_fire) begin
            ar_mem[ar_wptr] <= enq_addr;
        end
        if (ar_pop) begin
            rt_mem[rt_wptr] <= ar_mem[ar_rptr];
        end
        if (rt_pop) begin
            line_buf[rt_idx] <= m_rdata_i;
            tag_buf[rt_idx]  <= rt_tag;
        end
    end

    //--------------------------------------------------------------------------
    // Datapath control: pointers, occupancy, pending/valid, frontier,
    // LSQ (async reset preserved)
    //--------------------------------------------------------------------------
    wire        lsq_push = lreq_line_i && (lsq_cnt < {1'b0, LSQ_DEPTH});
    wire        lsq_pop  = lsq_head_ok;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ar_wptr     <= 5'd0;
            ar_rptr     <= 5'd0;
            ar_cnt      <= 6'd0;
            rt_wptr     <= 5'd0;
            rt_rptr     <= 5'd0;
            rt_cnt      <= 6'd0;
            spec_base   <= 29'd0;
            dem_last    <= 29'd0;
            dem_seen    <= 1'b0;
            lsq_wptr    <= 4'd0;
            lsq_rptr    <= 4'd0;
            lsq_cnt     <= 6'd0;
            line_valid  <= 64'd0;
            line_pend   <= 64'd0;
        end else begin
            // enqueue side (demand over speculation; line demand over
            // byte demand -- see enq_ldem/enq_bdem)
            if (enq_fire) begin
                ar_wptr            <= ar_wptr + 5'd1;
                line_pend[enq_idx] <= 1'b1;
                if (enq_dem) begin
                    dem_last  <= enq_addr;
                    spec_base <= enq_addr + 29'd1;
                    dem_seen  <= 1'b1;
                end else begin
                    spec_base <= spec_base + 29'd1;
                end
            end
            if (ar_pop) begin
                ar_rptr      <= ar_rptr + 5'd1;
                rt_wptr      <= rt_wptr + 5'd1;
            end
            if (rt_pop) begin
                rt_rptr            <= rt_rptr + 5'd1;
                line_valid[rt_idx] <= 1'b1;
                line_pend[rt_idx]  <= 1'b0;
            end
            case ({enq_fire, ar_pop})
                2'b10   : ar_cnt <= ar_cnt + 6'd1;
                2'b01   : ar_cnt <= ar_cnt - 6'd1;
                default : ar_cnt <= ar_cnt;
            endcase
            case ({ar_pop, rt_pop})
                2'b10   : rt_cnt <= rt_cnt + 6'd1;
                2'b01   : rt_cnt <= rt_cnt - 6'd1;
                default : rt_cnt <= rt_cnt;
            endcase
            // V3 LSQ
            if (lsq_push) begin
                lsq_mem[lsq_wptr] <= laddr_line_i[31:3];
                lsq_wptr          <= lsq_wptr + 4'd1;
            end
            if (lsq_pop) begin
                lsq_rptr <= lsq_rptr + 4'd1;
            end
            case ({lsq_push, lsq_pop})
                2'b10   : lsq_cnt <= lsq_cnt + 6'd1;
                2'b01   : lsq_cnt <= lsq_cnt - 6'd1;
                default : lsq_cnt <= lsq_cnt;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Output probes
    //--------------------------------------------------------------------------
    assign m_rready_o     = !rready_gap;
    assign ddr_gap_wait_o = (rreq_i && !hit) ||
                            (lsq_head_miss && !line_pend[lsq_head_ix]);

`ifndef SYNTHESIS
    always @(posedge clk_i) begin
        if (rst_n_i && lreq_line_i && (laddr_line_i[2:0] != 3'b000))
            $fatal(1, "M9AXIRD3_FAIL unaligned line request addr=%h",
                   laddr_line_i);
        if (rst_n_i && lreq_line_i && (lsq_cnt == {1'b0, LSQ_DEPTH}))
            $fatal(1, "M9AXIRD3_FAIL LSQ overflow (window faster than 16?)");
    end
`endif

endmodule
