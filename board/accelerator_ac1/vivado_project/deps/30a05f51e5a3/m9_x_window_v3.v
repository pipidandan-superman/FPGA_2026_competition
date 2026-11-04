/************************************************************************
 * File Name       : m9_x_window_v3.v
 * Developer       : M9.3 V3 issuer redesign line
 * Date            : 2026-10-13
 * Project Name    : YOLO object accel (M9.3 V3, 2026-10-13_yolo_m93_issuer_v3_run01)
 * Module Name     : m9_x_window_v3
 * Description     :
 *   X-window beat generator V3 -- LINE-ORIENTED rewrite of m9_x_window.v
 *   (V1.1).  Drops into the same socket: per-port contract with the
 *   issuer (cfg_* / rt_* / start / busy / done) and the ld_mux (x_beat_*) is
 *   UNCHANGED; only the DDR read face changes from the M9.1 byte-read
 *   port to a pipelined LINE-read port, on the documented contract that
 *   the downstream loader (m9_axi_rd_v3, 64-line cache + speculation)
 *   guarantees every requested line is resident -- the window never
 *   sees a miss (TB models must honor this; a hang means a coverage
 *   hole in the loader, which is a V3 bring-up finding, not a window
 *   bug).
 *
 *   Frozen beat-law semantics carried over BYTE-EXACT from V1.1
 *   (golden94 walk zero-diff is the hard gate of Phase B):
 *     iy[k]     = sh*oy + kKH[k] - ph            (all 16 lanes share)
 *     ix[k][n]  = sw*(16*s + n) + kKW[k] - pw
 *     inb       = 0<=iy<H & 0<=ix<W
 *     const n   = ~iy_inb | ~ix_inb(n) | (~law_fetch & vc<=n)
 *     xb[n]     = const ? (fill ? 8'hA5 : pad_val) : X[byte]
 *     pad_val   = cfg_first ? 8'h80 : 8'h00
 *     x_beat    : lo = lanes 0..7, hi = lanes 8..15, last = (k==K-1) on hi
 *
 *   V3 performance changes (PHASE_A_SPEC.md 2.1):
 *     (1) LINE fetch: the 16 lane bytes of a tap live in a consecutive
 *         span A_lo..A_hi (A = xbase + base + ix_base + sw*n).  Only
 *         NON-CONST lanes bound the span (const/oob lanes never touch
 *         the bus -- V1.0 safety law preserved, no wild reads of the
 *         INJ-5C class).  sw=1 -> <=3 lines, sw=2 -> <=5 lines.  The
 *         16-beat serial lane walk collapses to <=5 pipelined line
 *         requests, issued 1/cycle, responses in order.
 *     (2) CROSS-K PIPELINE: the tap address pipe (ADDR1-3) computes the
 *         NEXT tap while the current tap's lines are fetched / beats
 *         presented.  One-tap lookahead: a single pending slot between
 *         the address pipe and the line stage.
 *     (3) Steady-state target: one tap per max(3, n_lines) cycles
 *         (sw=1: 3) vs V1.1's ~21+.
 *
 *   Line-read port protocol (v3):
 *     rreq_line is a PULSE with raddr_line valid the same cycle
 *     (8B-aligned).  Multiple outstanding requests allowed; responses
 *     rvalid_line/rdata_line return IN REQUEST ORDER (m9_axi_rd_v3
 *     returns in order by construction).  Variable in-order latency
 *     tolerated via rsp counting.
 *
 * Dependencies    : none (pure RTL; no on-chip data storage)
 * Revision History:
 *   - V3.0 (2026-10-13) : initial release (Phase B, M9.3 V3 redesign).
 *                         Equivalence class = x_beat stream CONTENT
 *                         (data/hi/last in emission order); cycle-level
 *                         alignment with V1.1 is impossible BY DESIGN
 *                         (V3 is faster) and is NOT part of the
 *                         contract.
 *   - V3.1 (2026-10-14) : M10.1-v2 2a -- cfg_ch_stride input; the
 *                         channel byte stride hw_prod_r is decoupled from
 *                         cfg_h*cfg_w (0 = legacy).  View-conv vehicle:
 *                         SPEC_layer_chain_v2.md §6.  Chain-off behavior
 *                         is BYTE-EXACT (default path unchanged).
 ************************************************************************/
`timescale 1ns / 1ps

module m9_x_window_v3 (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv geometry config (issuer writes while idle) ----
    input  wire [15:0] cfg_ic        ,   // input channels (socket parity)
    input  wire [15:0] cfg_h         ,   // input plane H
    input  wire [15:0] cfg_w         ,   // input plane W
    input  wire [3:0]  cfg_kh        ,
    input  wire [3:0]  cfg_kw        ,
    input  wire [3:0]  cfg_sh        ,
    input  wire [3:0]  cfg_sw        ,
    input  wire [3:0]  cfg_ph        ,
    input  wire [3:0]  cfg_pw        ,
    input  wire        cfg_first     ,   // pad = -128 only for stem
    input  wire        cfg_law_fetch ,   // 0='fill'(default) 1='fetch'
    input  wire [31:0] cfg_xbase     ,   // in_buf base (arena byte addr)
    // M10.1-v2 2a: channel byte stride decoupling.  0 = legacy default
    // (cfg_h*cfg_w, CHW plane-coupled); nonzero = explicit per-channel
    // stride -- the view-conv vehicle reads the producer's Y tile layout
    // (stride 16 for the vc=16 tile, SPEC_layer_chain_v2.md §6).
    input  wire [31:0] cfg_ch_stride ,
    // ---- v2.3 (M10.2 m8): per-conv layout declaration (DESIGN §4) ----
    // 3b per conv: 001=CHW plane / 010=tile slot / 100=up2x materialized;
    // 000 = default (v2.2 legacy, cfg-driven law, byte-exact).
    input  wire [29:0] cfg_layout_id,
    input  wire [3:0]  conv_idx      ,   // active conv (issuer snoop face)
    // ---- per-block runtime (latched on start) ----
    input  wire [9:0]  rt_oy         ,
    input  wire [3:0]  rt_s          ,
    input  wire [10:0] rt_k          ,   // segment k count (<=1024)
    input  wire [4:0]  rt_vc         ,   // strip vc (16 or less)
    input  wire [15:0] rt_koff_ic    ,   // segment k-seed kIC
    input  wire [3:0]  rt_koff_kh    ,   // segment k-seed kKH
    input  wire [3:0]  rt_koff_kw    ,   // segment k-seed kKW
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    // ---- X LINE read port (V3: pipelined, in-order, guaranteed hit) ----
    output reg  [31:0] raddr_line    ,
    output reg         rreq_line     ,
    input  wire [63:0] rdata_line    ,
    input  wire        rvalid_line   ,
    // ---- X beat outlet (to m9_ld_mux) -- contract unchanged ----
    output reg  [63:0] x_beat_data   ,
    output reg         x_beat_hi     ,   // 0=lo lanes 0..7, 1=hi 8..15
    output reg         x_beat_last   ,   // (k==K-1) on the hi beat
    output reg         x_beat_valid  ,
    input  wire        x_beat_ready
);

    // ---------------- FSM ----------------
    localparam ST_IDLE  = 3'd0,
               ST_ADDR1 = 3'd1,    // tap-prefetch address pipe stage 1
               ST_ADDR2 = 3'd2,
               ST_ADDR3 = 3'd3,
               ST_LINE  = 3'd4,    // current tap: line fetch + present
               ST_PRE_LO= 3'd5,
               ST_PRE_HI= 3'd6,
               ST_DONE  = 3'd7;
    reg [2:0]  st;

    // per-conv derived
    reg  [31:0] hw_prod_r;                          // channel byte stride
    wire [7:0]  pad_val = cfg_first ? 8'h80 : 8'h00;

    // ---------------- v2.3 layout selection point (DESIGN §4.2) ---------
    // The ONE selection point of the layout vector: the tap address
    // generator's channel-stride law.  All three declared layouts ride
    // the EXISTING cfg-driven law in v2.3 (formalization only -- §4.3
    // scopes differentiation to the post-repack v2.4); the latch makes
    // the active selection wave/ledger-visible and TB-assertable.
    //   000 default : ch_stride==0 ? h*w : ch_stride   (legacy, byte-exact)
    //   001 CHW     : plane law  (compiler emits stride 0 / 2W-pitch)
    //   010 tile    : slot law   (compiler emits the slot stride)
    //   100 up2x    : materialized-plane law (existing up2x_view cfg)
    reg [2:0] layout_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     layout_sel <= 3'b000;
        else if (start) layout_sel <= cfg_layout_id[conv_idx*3 +: 3];
    end

    // tap-prefetch decomposition cursor (advances at ADDR1; kw->kh->ic law
    // identical to V1.1's advance at PRE_HI accept)
    reg [15:0] pf_ic;
    reg [3:0]  pf_kh;
    reg [3:0]  pf_kw;

    // address-pipe regs (tap being prefetched)
    reg  [31:0]        ch_off_r;
    reg  signed [31:0] iy_v_r;
    reg  [31:0]        iy_clip_r;
    reg                iy_inb_r;
    reg  signed [15:0] ix_base_r;

    // pending tap slot (between address pipe and line stage)
    reg                 pend_valid;
    reg  [31:0]         pend_b0;        // byte base of lane n=0 (wrapped ok)
    reg  [15:0]         pend_const;     // const_mask per lane
    reg  [15:0]         pend_fill;      // fill_mask per lane
    reg  [10:0]         pend_k;

    // current tap slot
    reg                 cur_valid;
    reg  [31:0]         cur_b0;
    reg  [15:0]         cur_const;
    reg  [15:0]         cur_fill;
    reg  [10:0]         cur_k;

    // line fetch / assembly
    reg  [28:0]         line_lo;        // first 8B-line index ([31:3])
    reg  [3:0]          n_lines;        // 0..5
    reg  [3:0]          fcnt;           // requests issued
    reg  [3:0]          rcnt;           // responses received
    reg  [63:0]         line_word [0:4];

    // counters / latched runtime
    reg [10:0] k_pf;        // tap index in the address pipe
    reg [10:0] k_cur;       // tap index being served
    reg [10:0] k_r;
    reg [9:0]  oy_r;
    reg [3:0]  s_r;
    reg [4:0]  vc_r;

    assign busy = (st != ST_IDLE);
    assign done = (st == ST_DONE);

    // ---------------- per-lane decision functions (V1.1 expressions,
    // copied verbatim) ------------------------------------------------
    function ix_inb_l;
        input [3:0] n;
        reg signed [15:0] v;
        begin
            v = ix_base_r + cfg_sw * {12'd0, n};
            ix_inb_l = (v >= 0) && (v < cfg_w);
        end
    endfunction

    function [3:0] first_live;          // lowest non-const lane
        input [15:0] m;
        integer i;
        begin
            first_live = 4'd0;
            for (i = 15; i >= 0; i = i - 1)
                if (!m[i]) first_live = i[3:0];
        end
    endfunction
    function [3:0] last_live;           // highest non-const lane
        input [15:0] m;
        integer i;
        begin
            last_live = 4'd0;
            for (i = 0; i <= 15; i = i + 1)
                if (!m[i]) last_live = i[3:0];
        end
    endfunction

    // ---------------- combinational lane assembly (V1.1 data selection)
    function [7:0] lane_byte;
        input [3:0] n;
        reg  [31:0] a;
        reg  [3:0]  j;
        begin
            if (cur_const[n]) begin
                lane_byte = cur_fill[n] ? 8'hA5 : pad_val;
            end else begin
                a = cur_b0 + cfg_sw * {12'd0, n};
                j = a[31:3] - line_lo;
                case (a[2:0])
                    3'd0    : lane_byte = line_word[j][ 7: 0];
                    3'd1    : lane_byte = line_word[j][15: 8];
                    3'd2    : lane_byte = line_word[j][23:16];
                    3'd3    : lane_byte = line_word[j][31:24];
                    3'd4    : lane_byte = line_word[j][39:32];
                    3'd5    : lane_byte = line_word[j][47:40];
                    3'd6    : lane_byte = line_word[j][55:48];
                    default : lane_byte = line_word[j][63:56];
                endcase
            end
        end
    endfunction

    // NOTE: asm_lo/asm_hi are NOT wired as continuous assigns -- a function
    // that reads the line_word MEMORY inside a continuous assignment never
    // re-evaluates on memory writes in xsim (values stuck at time-0 X).
    // The lane assembly is instead sampled procedurally inside the clocked
    // ST_PRE_LO/ST_PRE_HI states (the legacy m9_x_window.v pattern:
    // x_beat_data <= {lane_lo[7],...} reads memory in a clocked block).

    // pending-tap span (evaluated at the swap cycle; pend_* are regs)
    wire [3:0]  pend_first = first_live(pend_const);
    wire [3:0]  pend_last  = last_live(pend_const);
    wire [31:0] span_lo    = pend_b0 + cfg_sw * {12'd0, pend_first};
    wire [31:0] span_hi    = pend_b0 + cfg_sw * {12'd0, pend_last};
    wire        any_live   = ~(&pend_const);
    wire [3:0]  span_lines = any_live ?
                             (span_hi[31:3] - span_lo[31:3] + 29'd1) : 4'd0;

    integer wi;

    // ---------------- sequencer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            rreq_line <= 1'b0;
            x_beat_valid <= 1'b0;
            x_beat_hi    <= 1'b0;
            x_beat_last  <= 1'b0;
            pend_valid <= 1'b0;
            cur_valid <= 1'b0;
            k_pf <= 11'd0; k_cur <= 11'd0;
        end else begin
            rreq_line    <= 1'b0;                 // default pulse
            x_beat_valid <= 1'b0;                 // default pulse
            case (st)
            ST_IDLE: if (start) begin
                oy_r <= rt_oy; s_r <= rt_s; k_r <= rt_k; vc_r <= rt_vc;
                // v2.3: layout_sel (latched above) formalizes the branch;
                // every branch resolves to the existing cfg law in v2.3
                // -- the case is structural documentation + wave anchor,
                // and the differentiation point for the v2.4 repack law.
                case (layout_sel)
                3'b001: hw_prod_r <= (cfg_ch_stride == 32'd0)
                                     ? (cfg_h * cfg_w) : cfg_ch_stride;
                3'b010: hw_prod_r <= (cfg_ch_stride == 32'd0)
                                     ? (cfg_h * cfg_w) : cfg_ch_stride;
                3'b100: hw_prod_r <= (cfg_ch_stride == 32'd0)
                                     ? (cfg_h * cfg_w) : cfg_ch_stride;
                default: hw_prod_r <= (cfg_ch_stride == 32'd0)
                                      ? (cfg_h * cfg_w) : cfg_ch_stride;
                endcase
                pf_ic <= rt_koff_ic; pf_kh <= rt_koff_kh; pf_kw <= rt_koff_kw;
                k_pf <= 11'd0; k_cur <= 11'd0;
                pend_valid <= 1'b0; cur_valid <= 1'b0;
                st <= ST_ADDR1;
            end
            // ---- tap-prefetch address pipe (runs one tap ahead) ----
            ST_ADDR1: begin
                ch_off_r <= pf_ic * hw_prod_r;
                iy_v_r   <= cfg_sh * oy_r + pf_kh - cfg_ph;
                st <= ST_ADDR2;
            end
            ST_ADDR2: begin
                iy_clip_r <= (iy_v_r < 0) ? 32'd0 :
                             (iy_v_r >= cfg_h) ? (cfg_h - 1) : iy_v_r;
                iy_inb_r  <= (iy_v_r >= 0) && (iy_v_r < cfg_h);
                ix_base_r <= cfg_sw * {s_r, 4'd0} + pf_kw - cfg_pw;
                // V1.1 law: the k-decomposition advances only AFTER the tap
                // has consumed kw (legacy advances at PRE_HI accept).  The
                // prefetch pipe runs one tap ahead, so the advance lands
                // here -- after ADDR2 has captured this tap's kw.
                if (pf_kw == cfg_kw - 1) begin
                    pf_kw <= 4'd0;
                    if (pf_kh == cfg_kh - 1) begin
                        pf_kh <= 4'd0;
                        pf_ic <= pf_ic + 16'd1;
                    end else
                        pf_kh <= pf_kh + 4'd1;
                end else
                    pf_kw <= pf_kw + 4'd1;
                st <= ST_ADDR3;
            end
            ST_ADDR3: begin
                for (wi = 0; wi < 16; wi = wi + 1) begin
                    pend_const[wi] <= ~iy_inb_r | ~ix_inb_l(wi[3:0])
                                      | (~cfg_law_fetch & (vc_r <= wi[4:0]));
                    pend_fill[wi]  <= ~cfg_law_fetch & (vc_r <= wi[4:0]);
                end
                pend_b0    <= cfg_xbase + ch_off_r + iy_clip_r * cfg_w
                              + {{16{ix_base_r[15]}}, ix_base_r};
                pend_k     <= k_pf;
                k_pf       <= k_pf + 11'd1;
                pend_valid <= 1'b1;
                st <= ST_LINE;
            end
            // ---- current tap: swap-in, line fetch, then present ----
            ST_LINE: begin
                if (!cur_valid && pend_valid) begin
                    // swap pending -> current; span wires see pend regs now
                    cur_valid  <= 1'b1;
                    cur_b0     <= pend_b0;
                    cur_const  <= pend_const;
                    cur_fill   <= pend_fill;
                    cur_k      <= pend_k;
                    pend_valid <= 1'b0;
                    line_lo    <= span_lo[31:3];
                    n_lines    <= span_lines;
                    fcnt       <= 4'd0;
                    rcnt       <= 4'd0;
                end else if (cur_valid) begin
                    if (fcnt < n_lines) begin
                        raddr_line <= {line_lo + fcnt, 3'b000};
                        rreq_line  <= 1'b1;
                        fcnt       <= fcnt + 4'd1;
                    end
                    if (rvalid_line) begin
                        line_word[rcnt] <= rdata_line;
                        rcnt <= rcnt + 4'd1;
                    end
                    if ((rcnt + (rvalid_line ? 4'd1 : 4'd0)) == n_lines)
                        st <= ST_PRE_LO;
                end else begin
                    // current done, pending empty: refill the pipe if
                    // taps remain (k_pf counts taps already ENTERED)
                    if (k_pf < k_r) st <= ST_ADDR1;
                    // else: all taps served; PRE_HI routed us to DONE
                end
            end
            ST_PRE_LO: begin
                // registered-handshake presentation: assert valid with the
                // beat data; only a REAL accept (valid already high + ready)
                // advances the FSM, and valid drops the cycle after the
                // accept so the same beat is never presented twice.  The
                // entry cycle (!valid) always presents -- a consumer ready
                // that follows the ld_mux law (ready only in response to
                // valid, low during the entry cycle) can never skip the LO
                // beat.  Lane assembly is sampled HERE (clocked, procedural
                // memory read), not via a continuous-assign wire.
                if (!x_beat_valid) begin
                    x_beat_data  <= {lane_byte(7),lane_byte(6),lane_byte(5),
                                     lane_byte(4),lane_byte(3),lane_byte(2),
                                     lane_byte(1),lane_byte(0)};
                    x_beat_hi    <= 1'b0;
                    x_beat_last  <= 1'b0;
                    x_beat_valid <= 1'b1;
                end else if (x_beat_ready) begin
                    x_beat_valid <= 1'b0;
                    st <= ST_PRE_HI;
                end else
                    x_beat_valid <= 1'b1;   // hold beat until accepted
            end
            ST_PRE_HI: begin
                if (!x_beat_valid) begin
                    x_beat_data  <= {lane_byte(15),lane_byte(14),lane_byte(13),
                                     lane_byte(12),lane_byte(11),lane_byte(10),
                                     lane_byte(9),lane_byte(8)};
                    x_beat_hi    <= 1'b1;
                    x_beat_last  <= (cur_k == k_r - 1);
                    x_beat_valid <= 1'b1;
                end else if (x_beat_ready) begin
                    x_beat_valid <= 1'b0;
                    k_cur     <= k_cur + 11'd1;
                    cur_valid <= 1'b0;
                    if (cur_k == k_r - 1) st <= ST_DONE;
                    else                  st <= ST_LINE;
                end else
                    x_beat_valid <= 1'b1;   // hold beat until accepted
            end
            ST_DONE: st <= ST_IDLE;               // done is a 1-cycle pulse
            default: st <= ST_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    // coverage / contract assertions (sim only)
    always @(posedge clk) begin
        if (rst_n && rreq_line && (raddr_line[2:0] != 3'b000))
            $fatal(1, "M9XW3_FAIL line request unaligned addr=%h", raddr_line);
        if (rst_n && (n_lines > 4'd5))
            $fatal(1, "M9XW3_FAIL span exceeds 5 lines (sw=%0d)", cfg_sw);
        // v2.3 layout contract (DESIGN §4.3): the declared layout must
        // match the consumer's cfg law.  Tile-declared convs MUST carry
        // an explicit slot stride (the RTL refusal lives in the issuer
        // S_CVLH walk check); CHW-declared convs may carry stride 0 (h*w
        // law) or a plane-pitch stride (2W rows from an ups producer) --
        // anything else is a compiler-contract violation.
        if (rst_n && busy && (layout_sel == 3'b010) &&
            (cfg_ch_stride == 32'd0))
            $fatal(1, "M9XW3_FAIL tile layout without slot stride conv=%0d",
                   conv_idx);
        if (rst_n && busy && (layout_sel == 3'b001) &&
            (cfg_ch_stride != 32'd0) &&
            (cfg_ch_stride != (cfg_h * cfg_w)) &&
            (cfg_ch_stride != (2 * cfg_h * cfg_w)))
            $fatal(1, "M9XW3_FAIL CHW layout with non-plane stride %0d conv=%0d",
                   cfg_ch_stride, conv_idx);
    end
`endif

endmodule
