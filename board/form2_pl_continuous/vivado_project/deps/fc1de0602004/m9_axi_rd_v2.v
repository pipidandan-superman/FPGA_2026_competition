//-----------------------------------------------------------------------------
// File Name    : m9_axi_rd_v2.v
// Developer    : LSL
// Date         : 2026-10-13
// Project      : yolo7020 competition -- M9 INTRA line
// Module       : m9_axi_rd_v2
// Description  : DDR read adapter V2.1 (M9.3 issuer closure, approved plan).
//                Drop-in client-contract replacement for m9_axi_rd (byte-read
//                face: raddr/rreq held by client until one rvalid pulse),
//                with a 64-line x 8B direct-mapped line buffer, up to 32
//                outstanding single-beat (ARLEN=0) AR transactions, and
//                demand-seeded +1-line speculative top-up so the sequential
//                x/w read streams stay latency-hidden instead of paying one
//                full DDR round trip per 8 bytes.
//
//                Latency hiding budget: 32 lines in flight x 8B = 256B of
//                lookahead, ~4x the measured board requirement
//                (RT_eff ~124 aclk x ~0.5B/cyc consumption ~ 62B).
//                Multi-outstanding replaces the V1 "ARLEN burst + wider
//                beat" idea at equal bandwidth-per-latency with single-beat
//                R handling identical to the proven V1 channel logic.
//
//                Safety: speculation is demand-seeded and bounded by the
//                outstanding budget (spec_base never runs more than 32 lines
//                past the last demand address), so speculative reads stay
//                inside the plane's reserved DDR window. Wild past-end
//                reads of the INJ-5C class cannot be generated.
//                m_rresp_i is intentionally not acted on (frozen INJ-5D
//                contract gap; V1 zero-diff semantics preserved).
// Dependencies : none (leaf module; instantiated as u_xrd/u_wrd in
//                m9_intra_axi_top.v)
// Revision History:
//   - V2.1 (2026-10-13) : Initial. M9.3 issuer closure item 1+2 (multi-
//                         outstanding AR queue + multi-line cache).
//                         Client byte-serve contract byte-identical to V1.
//                         Two bring-up fixes in the same session (unit TB
//                         tb_m9_axi_rd_v2.sv): (a) AR pop must gate on the
//                         registered m_arvalid_o on the bus -- popping on
//                         arready alone loses the entry and wedges the
//                         return queue; (b) m_arvalid masked with !ar_pop
//                         so a just-accepted burst is never re-asserted
//                         (real AXI interconnects would double-accept);
//                         (c) the outstanding budget is ar_cnt+rt_cnt
//                         (single shared pool) -- independent per-FIFO
//                         checks overflowed the 32-deep return queue;
//                         (d) one-cycle rready gap after each consumed
//                         beat: the tb_m9_v25 family slave holds rvalid
//                         one cycle past the handshake, so raw-rvalid
//                         consuming double-counts beats (the gap is legal
//                         AXI and also paces real pipelined DDR slaves);
//                         (e) queue pointers are 5-bit wrapping at the
//                         32-deep ar_mem/rt_mem -- the original 6-bit
//                         pointers indexed [32,63] of the 32-entry arrays,
//                         so every push past the first 32 fell into the
//                         void (entry lost: pend stuck set, queues drained,
//                         demand starves at the 33rd line).
//   - V2.2 (2026-10-13) : Timing-fix round 3 (BUILD0D WNS -1.985ns / BUILD1
//                         Performance_Explore WNS -2.556ns, both route-
//                         dominated congestion from the 2 x 5568 cache FFs
//                         per instance).  line_buf/tag_buf move FF ->
//                         distributed RAM (* ram_style = "distributed" *);
//                         async reset dropped from both arrays (line_valid
//                         still resets, so a stale-data hit is impossible).
//                         Client byte-serve contract UNCHANGED: hit serve
//                         stays combinational (async RAM read port), zero
//                         added latency, no port change.
//   - V2.3 (2026-10-13) : BUILD2 post-mortem: the V2.2 ram_style attribute
//                         was IGNORED -- OOC synth (Synth 8-4767) refused
//                         RAM inference because the WRITE PROCESS carries
//                         an async reset sensitivity, even with no reset
//                         assignment on the arrays themselves.  Fix: the
//                         four arrays (line_buf/tag_buf/ar_mem/rt_mem)
//                         move to a dedicated posedge-only write process;
//                         all control state keeps its async reset in the
//                         original process.  Same conditions, same
//                         clocked assignments, one driver per reg --
//                         functionally zero-diff vs V2.2 (itself proven
//                         zero-diff vs V2.1 by the four doors).
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module m9_axi_rd_v2 (
    input  wire        clk_i            ,
    input  wire        rst_n_i          ,
    // client byte-read face (contract identical to m9_axi_rd V1.0)
    input  wire [31:0] raddr_i          ,   // byte address
    input  wire        rreq_i           ,   // held high until rvalid_o pulse
    output reg  [7:0]  rdata_o          ,   // byte data, valid with rvalid_o
    output reg         rvalid_o         ,   // one-cycle pulse per request
    // AXI4 read master (single ID, single-beat bursts, in-order R)
    output reg  [31:0] m_araddr_o       ,
    output reg  [3:0]  m_arlen_o        ,   // tied 4'd0 (one 64b beat per AR)
    output reg         m_arvalid_o      ,
    input  wire        m_arready_i      ,
    input  wire [63:0] m_rdata_i        ,
    input  wire [1:0]  m_rresp_i        ,   // ignored (INJ-5D contract gap)
    input  wire        m_rvalid_i       ,
    input  wire        m_rlast_i        ,
    output wire        m_rready_o       ,   // tied 1'b1
    // trace probe: client waiting on a not-yet-resident line
    output wire        ddr_gap_wait_o
);

    //--------------------------------------------------------------------------
    // Parameters / localparams
    //--------------------------------------------------------------------------
    localparam [5:0] FIFO_DEPTH   = 6'd32;   // max outstanding ARs
    localparam       ST_IDLE      = 1'b0;    // AR channel idle, scan FIFO
    localparam       ST_SEND      = 1'b1;    // AR on the bus, wait accept

    //--------------------------------------------------------------------------
    // Line buffer state (64 lines x 8B, direct-mapped)
    //   line index = addr[8:3], tag = addr[31:9]
    //--------------------------------------------------------------------------
    // ram_style = distributed (V2.2, 2026-10-13): the FF implementation of
    // the 64-line cache (4096 data + 1472 tag FFs per instance) caused
    // route-dominated timing congestion (BUILD0D/BUILD1 gates).  Distributed
    // RAM keeps the combinational hit-serve latency identical (async read
    // port), so the client contract is untouched.  No async reset on either
    // array (RAM cells cannot be reset); line_valid/line_pend still reset,
    // so a hit can never return stale data.
    (* ram_style = "distributed" *) reg  [63:0] line_buf  [0:63];
    (* ram_style = "distributed" *) reg  [22:0] tag_buf   [0:63];
    reg  [63:0] line_valid;
    reg  [63:0] line_pend;

    //--------------------------------------------------------------------------
    // Outstanding queues
    //   ar_fifo : enqueue -> AR accept        (line addr [31:3])
    //   rt_fifo : AR accept -> R last beat    (in-flight, return order)
    //--------------------------------------------------------------------------
    reg  [28:0] ar_mem [0:31];
    reg  [4:0]  ar_wptr;   // 5-bit: wraps at the 32-deep memory
    reg  [4:0]  ar_rptr;
    reg  [5:0]  ar_cnt;    // 6-bit: full range 0..32
    reg  [28:0] rt_mem [0:31];
    reg  [4:0]  rt_wptr;
    reg  [4:0]  rt_rptr;
    reg  [5:0]  rt_cnt;

    //--------------------------------------------------------------------------
    // Speculative frontier (line-address granularity, [31:3])
    //--------------------------------------------------------------------------
    reg  [28:0] spec_base;

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

    // total in-flight budget: ar_cnt + rt_cnt must stay < FIFO_DEPTH.
    // Checking the two counters independently allows ar=20/rt=20 (40
    // total) and overflows the 32-deep rt_fifo -- one budget for both.
    wire [6:0] occ_total  = {1'b0, ar_cnt} + {1'b0, rt_cnt};
    wire       fifo_space = (occ_total < {1'b0, FIFO_DEPTH});

    // demand enqueue: client waiting on a line that is neither resident
    // nor already being fetched (line_pend covers the wait-for-fill case,
    // so a held rreq never enqueues a duplicate)
    wire        enq_dem  = rreq_i && !hit && !line_pend[dem_idx] && fifo_space;

    // speculative top-up: +1 line past the frontier, demand has priority;
    // self-limited by fifo_space so the frontier never runs more than
    // FIFO_DEPTH lines ahead of the last demand address
    wire [5:0]  spec_idx = spec_base[5:0];
    wire        enq_spec = (!enq_dem) && fifo_space &&
                           (!line_valid[spec_idx]) && (!line_pend[spec_idx]);
    wire        enq_fire = enq_dem || enq_spec;
    wire [28:0] enq_addr = enq_dem ? raddr_i[31:3] : spec_base;
    wire [5:0]  enq_idx  = enq_addr[5:0];

    wire        serve_pulse = rreq_i && hit && !served;

    //--------------------------------------------------------------------------
    // Byte-lane mux (combinational read of the resident line)
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
    // Next-state combinational logic (defaults first, then case)
    //--------------------------------------------------------------------------
    // accept = slave took the burst ON THE BUS: gate on the registered
    // m_arvalid_o, never on the comb next-value (a pop without a bus
    // accept loses the FIFO entry and wedges the return queue)
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
    // Registered outputs (AXI AR channel + client serve channel)
    //--------------------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            m_arvalid_o <= 1'b0;
            m_araddr_o  <= 32'd0;
            m_arlen_o   <= 4'd0;
            rvalid_o    <= 1'b0;
            rdata_o     <= 8'd0;
            served      <= 1'b0;
        end else begin
            m_arvalid_o <= ar_valid_n && !ar_pop;   // pop ends this burst;
                                                    // no phantom re-assert
            m_araddr_o  <= ar_addr_n;
            m_arlen_o   <= 4'd0;
            rvalid_o    <= serve_pulse;
            rdata_o     <= lane;
            if (!rreq_i) begin
                served <= 1'b0;
            end else if (serve_pulse) begin
                served <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // R-channel pacing: one-cycle gap after each consumed beat.
    // The tb_m9_v25 family slave holds rvalid one extra cycle after the
    // handshake ("hold until taken" idiom, V1-era law); consuming on raw
    // rvalid would count the held beat twice.  A single rready bubble
    // after each consume is legal AXI (slave holds the next beat), works
    // for both the TB slave and real pipelined DDR controllers, and
    // sustains 1 beat / 2 cycles = 4 B/cyc per port (>> the ~0.5 B/cyc
    // load-stream demand).
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
    // Vivado refuses RAM inference for arrays written in a process with an
    // async-reset sensitivity (Synth 8-4767, found by BUILD2 post-mortem
    // 2026-10-13), even when the arrays carry no reset assignment of their
    // own.  The arrays need no reset: every read is gated by line_valid /
    // queue occupancy, which DO reset in the control process below.
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
    // Datapath control: pointers, occupancy counters, pending/valid bits,
    // speculative frontier (async reset preserved)
    //--------------------------------------------------------------------------
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ar_wptr     <= 5'd0;
            ar_rptr     <= 5'd0;
            ar_cnt      <= 6'd0;
            rt_wptr     <= 5'd0;
            rt_rptr     <= 5'd0;
            rt_cnt      <= 6'd0;
            spec_base   <= 29'd0;
            line_valid  <= 64'd0;
            line_pend   <= 64'd0;
        end else begin
            // enqueue side (demand has priority over speculation)
            if (enq_fire) begin
                ar_wptr         <= ar_wptr + 5'd1;
                line_pend[enq_idx] <= 1'b1;
                if (enq_dem) begin
                    spec_base <= raddr_i[31:3] + 29'd1;
                end else begin
                    spec_base <= spec_base + 29'd1;
                end
            end
            // AR accept: pop request queue, push return-order queue
            if (ar_pop) begin
                ar_rptr      <= ar_rptr + 5'd1;
                rt_wptr      <= rt_wptr + 5'd1;
            end
            // R last beat: mark line resident
            if (rt_pop) begin
                rt_rptr          <= rt_rptr + 5'd1;
                line_valid[rt_idx] <= 1'b1;
                line_pend[rt_idx]  <= 1'b0;
            end
            // occupancy counters (ar: enq vs accept; rt: accept vs return)
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
        end
    end


    //--------------------------------------------------------------------------
    // Output probes
    //--------------------------------------------------------------------------
    assign m_rready_o     = !rready_gap;
    assign ddr_gap_wait_o = rreq_i && !hit;

endmodule
