/*
 * M9.2 v2b trace reference block.  V1.1 (2026-10-12, M9.3 run01):
 *   + FRAME_NODE_CASE CSR 0xC4 (frame[7:0]/node[15:8]/case[23:16]) and a
 *     per-ring-entry 32-bit context word (same-index sideband read at
 *     0xC8) so every dumped entry is self-describing (13.4.2 token
 *     identity: frame/node/case/tile/OC/K/buffer/generation).
 *   + ring_ovr output (was an undriven float at the m9_intra_top port).
 *   + push_token zero padding corrected to the exact 14 free bits.
 *   Zero data-path change: counters, ring payload, and event semantics
 *   are byte-identical to V1.0.
 *   V3.10 (2026-10-14, M9.3 V3 line): one-deep write staging register
 *   between the push_* bundle and the ring arrays.  Entry content,
 *   order, and wp/count/total values are byte-identical; the write
 *   lands one cycle later (see the ring write block).  Motivated by
 *   post-route forensics: all worst failing paths were cross-module
 *   (u_xrd lsq_rptr -> ring D/CE), route-dominated.
 *
 * This file is deliberately staged outside the frozen production tree until
 * the v2b RTL/bit/hwh chain has passed the required PC, timing, and board
 * gates.  Counters are cycle-space counters in the single aclk domain.  The
 * phase inputs must already be handshake-qualified by the integration layer:
 * load_active = valid && ready, compute_useful = valid && ready && !padding,
 * and store_active = write_valid && write_ready.
 */
`timescale 1ns / 1ps

module m9_trace_v2b #(
    // V1.2 (2026-10-12 m93 bit): 256 -> 64.  The three ring arrays
    // (payload/token/ctx) cannot infer block RAM (frame-start clear
    // loops + async CSR read muxes), so depth 256 cost ~37k LUT and
    // overflowed the xc7z020 placer by ~912 slices.  Depth 64 quarters
    // the read muxes and fits.  Ring is a rolling debug window, not a
    // log; 13.4.3 has no metric on ring depth.  Wrap logic below is
    // explicit (pointers stayed 8-bit for ABI 0xA0 compatibility).
    parameter integer RING_DEPTH = 64
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_start,
    input  wire         frame_done,
    input  wire         steady_end,
    input  wire         load_active,
    input  wire         compute_useful,
    input  wire         store_active,
    input  wire         ddr_gap,
    input  wire         fifo_full,
    input  wire [15:0] fifo_level,
    input  wire [7:0]   fifo_id,
    input  wire [15:0]  token_tile_x,
    input  wire [15:0]  token_tile_y,
    input  wire [15:0]  token_oc0,
    input  wire [15:0]  token_oc1,
    input  wire [15:0]  token_k0,
    input  wire [15:0]  token_k1,
    input  wire [3:0]   token_buffer_id,
    input  wire [7:0]   token_generation,
    input  wire         token_valid,
    input  wire         token_ready,
    input  wire         token_first,
    input  wire         token_last,
    input  wire         token_tail,
    input  wire         token_error,
    input  wire         event_valid,
    input  wire [3:0]   event_type,
    input  wire [11:0]  event_data,
    input  wire [15:0]  event_fifo_level,
    // ---- v2.4 (M11a): page-advance anchor (SPEC §2.4) -- direct input
    //      (the frozen wrappers cannot compose it into the event port;
    //      float-guarded, r12 build wires the real face) ----
    input  wire         pg_anchor,
    input  wire [2:0]   pg_anchor_page,
    input  wire         csr_we,
    input  wire [11:0]  csr_waddr,
    input  wire [31:0]  csr_wdata,
    input  wire [11:0]  csr_raddr,
    output reg  [31:0]  csr_rdata,
    output wire         ring_ovr
`ifdef M9_TRACE_TEST
    ,input wire         test_seed_valid
    ,input wire [3:0]   test_seed_sel
    ,input wire [31:0]  test_seed_value
`endif
);

    localparam [11:0] A_CTRL          = 12'h060;
    localparam [11:0] A_STATUS        = 12'h064;
    localparam [11:0] A_CNT_L         = 12'h068;
    localparam [11:0] A_CNT_C         = 12'h06C;
    localparam [11:0] A_CNT_S         = 12'h070;
    localparam [11:0] A_CNT_LC        = 12'h074;
    localparam [11:0] A_CNT_CS        = 12'h078;
    localparam [11:0] A_CNT_LS        = 12'h07C;
    localparam [11:0] A_CNT_LCS       = 12'h080;
    localparam [11:0] A_GMAX          = 12'h084;
    localparam [11:0] A_FMAX          = 12'h088;
    localparam [11:0] A_FILL          = 12'h08C;
    localparam [11:0] A_DRAIN         = 12'h090;
    localparam [11:0] A_STEADY        = 12'h094;
    localparam [11:0] A_RING_CTRL     = 12'h098;
    localparam [11:0] A_RING_STATUS   = 12'h09C;
    localparam [11:0] A_RING_RD_PTR   = 12'h0A0;
    localparam [11:0] A_RING_BASE     = 12'h0A4;
    localparam [11:0] A_RING_TOKEN_BASE = 12'h0B4;
    localparam [11:0] A_FRAME_NODE_CASE = 12'h0C4;
    localparam [11:0] A_RING_CTX_BASE   = 12'h0C8;

    localparam [3:0] EVT_PHASE        = 4'd0;
    localparam [3:0] EVT_GAP_START    = 4'd1;
    localparam [3:0] EVT_GAP_END      = 4'd2;
    localparam [3:0] EVT_FIFO_SAMPLE  = 4'd3;
    localparam [3:0] EVT_PPP_START    = 4'd4;
    localparam [3:0] EVT_PPP_DONE     = 4'd5;
    localparam [3:0] EVT_TOKEN_LATCH  = 4'd6;
    // v2.4 (M11a SPEC §2.4): page-advance anchor; data = {9'd0, page}
    localparam [3:0] EVT_PG_ADV       = 4'd7;
    localparam [3:0] EVT_OVERFLOW     = 4'd15;

    // ---- G2 (M10.2 m8): PPP explicit event anchors ---------------------
    // v2.3 removed the (0xE8,0xF0) tr_we observation band (DESIGN §7.3-6),
    // so PPP CSR writes no longer mirror into ring data; PPP protocol
    // anchors are explicit ring-class events instead (DESIGN §6 G2).
    // The main ring is a rolling 64-deep debug window that compute_useful
    // saturates within one busy frame, so the anchors get a dedicated
    // side FIFO here.  Observe-only: zero data-path influence; the main
    // ring arrays, pointers, and all L/C/S counters are untouched.
    // Clear follows clear_on_frame (per-frame isolation, same law as the
    // main ring).  Entry = {cycle[31:0], type[3:0], data[11:0]}.
    localparam integer PPP_DEPTH      = 16;
    // A_PPP_* stays at 0x4C0-0x4CC (v2.3 canon ABI; the frozen m8-upgrade
    // TB dumps the FIFO through the DIRECT 12-bit tr_raddr/tr_rdata face
    // -- CSR 0x60-0xFF carve passthrough is 8-bit and CANNOT reach here.
    // G2's leaf harness therefore also reads this family through a TB-side
    // direct-drive mux on the trace csr face, not through the CSR carve
    // (the 10-18 attempt to relocate these regs to 0x0C0-0x0C3 broke the
    // frozen TB's anchor cross-asserts -- reverted same day).
    localparam [11:0] A_PPP_STATUS    = 12'h4C0;
    localparam [11:0] A_PPP_RD_PTR    = 12'h4C4;
    localparam [11:0] A_PPP_DATA0     = 12'h4C8;
    localparam [11:0] A_PPP_DATA1     = 12'h4CC;

    reg        trace_enable_q;
    reg        clear_on_frame_q;
    reg        freeze_q;
    reg        snapshot_done_q;
    reg        overflow_q;
    reg  [6:0] overflow_detail_q;
    reg  [7:0] ring_overflow_count_q;
    reg [31:0] cycle_q;
    reg        steady_q;
    reg        gap_q;
    reg [31:0] current_gap_q;
    reg [31:0] fill_cycle_q;
    reg [31:0] drain_cycle_q;
    reg [31:0] steady_cycles_q;
    reg  [7:0] ring_wp_q;
    reg  [8:0] ring_count_q;
    reg [14:0] ring_total_q;
    reg  [7:0] ring_rd_ptr_q;
    reg [127:0] ring_mem [0:RING_DEPTH-1];
    reg [127:0] ring_token_mem [0:RING_DEPTH-1];
    // V1.1: per-entry frame/node/case context word (13.4.2 token identity).
    reg [31:0]  ring_ctx_mem [0:RING_DEPTH-1];
    reg [7:0]   frame_id_q, node_id_q, case_id_q;

    // G2 PPP anchor FIFO state (single-driver block below; see header
    // comment at the event-type localparams).
    reg [47:0]  ppp_mem [0:PPP_DEPTH-1];
    reg [4:0]   ppp_wp_q, ppp_rd_ptr_q;
    reg [5:0]   ppp_count_q;
    reg [15:0]  ppp_total_q;
    reg         ppp_ovr_q;
    // v2.4: page-advance anchor joins the PPP anchor FIFO (same observe-
    // only law).  Float-guarded: frozen wrappers leave pg_anchor
    // unconnected -> never fires (legacy rings byte-identical).  On the
    // impossible pg_anchor+event_valid coincidence the page anchor
    // outranks (page boundaries are the stronger frame landmark).
    wire        pg_anchor_g = (pg_anchor === 1'b1);
    wire [3:0]  ppp_push_type = pg_anchor_g ? EVT_PG_ADV : event_type;
    wire [11:0] ppp_push_data = pg_anchor_g ? {9'd0, pg_anchor_page}
                                            : event_data;
    wire        is_ppp_ev = (event_valid &&
                            ((event_type == EVT_PPP_START)   ||
                             (event_type == EVT_PPP_DONE)    ||
                             (event_type == EVT_TOKEN_LATCH))) ||
                            pg_anchor_g;
    wire        ppp_push  = is_ppp_ev && trace_enable_q && !freeze_q;
    wire        ppp_rd_ptr_write = csr_we && (csr_waddr == A_PPP_RD_PTR);

    reg [31:0] cnt_l_q, cnt_c_q, cnt_s_q;
    reg [31:0] cnt_lc_q, cnt_cs_q, cnt_ls_q, cnt_lcs_q;
    reg [31:0] gmax_q;
    reg [15:0] fmax_level_q;
    reg  [7:0] fmax_id_q;

    wire ctrl_write = csr_we && (csr_waddr == A_CTRL);
    wire rd_ptr_write = csr_we && (csr_waddr == A_RING_RD_PTR);
    wire fnc_write = csr_we && (csr_waddr == A_FRAME_NODE_CASE);
    wire snapshot_cmd = ctrl_write && csr_wdata[1];
    wire freeze_cmd = ctrl_write && csr_wdata[2];
    wire backpressure = ddr_gap | fifo_full;
    wire steady_now = steady_q | compute_useful;

    function [31:0] sat_add1;
        input [31:0] value;
        begin
            sat_add1 = (value == 32'hFFFF_FFFF) ? value : value + 32'd1;
        end
    endfunction

    function [15:0] sat_add1_16;
        input [15:0] value;
        begin
            sat_add1_16 = (value == 16'hFFFF) ? value : value + 16'd1;
        end
    endfunction

    wire gap_start = backpressure && !gap_q;
    wire gap_end = !backpressure && gap_q;
    wire auto_event = frame_start | frame_done | steady_end | compute_useful |
                      gap_start | gap_end;
    wire push_event = trace_enable_q && (event_valid | auto_event);
    wire [3:0] push_type = frame_start ? EVT_PHASE :
                           frame_done  ? EVT_PHASE :
                           steady_end  ? EVT_PHASE :
                           gap_start   ? EVT_GAP_START :
                           gap_end     ? EVT_GAP_END :
                           (event_valid ? event_type : EVT_PHASE);
    wire [11:0] push_data = frame_start ? 12'd1 :
                            frame_done  ? 12'd3 :
                            steady_end  ? 12'd4 :
                            compute_useful ? 12'd2 :
                            (event_valid ? event_data : 12'd0);
    wire [15:0] push_fifo = event_valid ? event_fifo_level : fifo_level;
    wire [11:0] ring_byte_off = csr_raddr - A_RING_BASE;
    wire [11:0] token_byte_off = csr_raddr - A_RING_TOKEN_BASE;
    wire [127:0] push_token = {14'd0, token_error, token_tail, token_last,
                               token_first, token_ready, token_valid,
                               token_generation, token_buffer_id, token_k1,
                               token_k0, token_oc1, token_oc0,
                               token_tile_y, token_tile_x};
    wire [31:0] push_ctx = {8'd0, case_id_q, node_id_q, frame_id_q};

    // V3.10 write-stage registers (see the ring write block below)
    reg         st_valid;
    reg         st_first;
    reg [127:0] st_mem;
    reg [127:0] st_token;
    reg [31:0]  st_ctx;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trace_enable_q <= 1'b0;
            clear_on_frame_q <= 1'b1;
            freeze_q <= 1'b0;
            snapshot_done_q <= 1'b0;
            overflow_q <= 1'b0;
            overflow_detail_q <= 7'd0;
            ring_overflow_count_q <= 8'd0;
            cycle_q <= 32'd0;
            steady_q <= 1'b0;
            gap_q <= 1'b0;
            current_gap_q <= 32'd0;
            fill_cycle_q <= 32'd0;
            drain_cycle_q <= 32'd0;
            steady_cycles_q <= 32'd0;
            ring_wp_q <= 8'd0;
            ring_count_q <= 9'd0;
            ring_total_q <= 15'd0;
            ring_rd_ptr_q <= 8'd0;
            frame_id_q <= 8'd0;
            node_id_q <= 8'd0;
            case_id_q <= 8'd0;
            ppp_wp_q <= 5'd0;
            ppp_rd_ptr_q <= 5'd0;
            ppp_count_q <= 6'd0;
            ppp_total_q <= 16'd0;
            ppp_ovr_q <= 1'b0;
            cnt_l_q <= 32'd0; cnt_c_q <= 32'd0; cnt_s_q <= 32'd0;
            cnt_lc_q <= 32'd0; cnt_cs_q <= 32'd0;
            cnt_ls_q <= 32'd0; cnt_lcs_q <= 32'd0;
            gmax_q <= 32'd0;
            fmax_level_q <= 16'd0; fmax_id_q <= 8'd0;
            // V3.9 (2026-10-14): the three ring data arrays carry NO
            // reset (was: async clear of all 64 entries here and on
            // clear_on_frame below).  Post-route forensics on the V3.8
            // build: the 13,808-load s_axi_aresetn net routed 8.658ns
            // to these CLRs, failing recovery on 1,059 endpoints, and
            // the CLR web pressurized routing across the whole die.
            // Protocol safety: the host only ever reads entries
            // [0, ring_count_q) written AFTER the last clear (the count
            // is reset, the data is not), so unwritten/stale entries
            // are never observed -- identical ABI, zero behavioral
            // change for count-bounded dumps.  Control registers keep
            // their async reset.
            st_valid <= 1'b0;
        end else begin
            cycle_q <= cycle_q + 32'd1;

            if (ctrl_write) begin
                trace_enable_q <= csr_wdata[0];
                clear_on_frame_q <= csr_wdata[3];
                if (snapshot_cmd) begin
                    freeze_q <= 1'b1;
                    snapshot_done_q <= 1'b1;
                end else begin
                    freeze_q <= freeze_cmd;
                    if (!freeze_cmd) snapshot_done_q <= 1'b0;
                end
                if (csr_wdata[0] == 1'b0) begin
                    overflow_q <= 1'b0;
                    overflow_detail_q <= 7'd0;
                end
            end
            if (rd_ptr_write)
                ring_rd_ptr_q <= csr_wdata[7:0];
            if (ppp_rd_ptr_write)
                ppp_rd_ptr_q <= csr_wdata[4:0];
            if (fnc_write) begin
                frame_id_q <= csr_wdata[7:0];
                node_id_q  <= csr_wdata[15:8];
                case_id_q  <= csr_wdata[23:16];
            end

`ifdef M9_TRACE_TEST
            // Test-only saturation seed. The production build omits these
            // ports and this branch, so no software-visible ABI is changed.
            if (test_seed_valid) begin
                case (test_seed_sel)
                    4'd0: cnt_l_q   <= test_seed_value;
                    4'd1: cnt_c_q   <= test_seed_value;
                    4'd2: cnt_s_q   <= test_seed_value;
                    4'd3: cnt_lc_q  <= test_seed_value;
                    4'd4: cnt_cs_q  <= test_seed_value;
                    4'd5: cnt_ls_q  <= test_seed_value;
                    4'd6: cnt_lcs_q <= test_seed_value;
                    4'd7: gmax_q    <= test_seed_value;
                    default: begin end
                endcase
            end
`endif

            if (frame_start && clear_on_frame_q) begin
                cnt_l_q <= 32'd0; cnt_c_q <= 32'd0; cnt_s_q <= 32'd0;
                cnt_lc_q <= 32'd0; cnt_cs_q <= 32'd0;
                cnt_ls_q <= 32'd0; cnt_lcs_q <= 32'd0;
                gmax_q <= 32'd0;
                fmax_level_q <= 16'd0; fmax_id_q <= 8'd0;
                fill_cycle_q <= 32'd0; drain_cycle_q <= 32'd0;
                steady_cycles_q <= 32'd0;
                steady_q <= 1'b0;
                gap_q <= 1'b0; current_gap_q <= 32'd0;
                ring_wp_q <= 8'd0; ring_count_q <= 9'd0;
                ring_total_q <= 15'd0;
                ring_rd_ptr_q <= 8'd0;
                ring_overflow_count_q <= 8'd0;
                overflow_q <= 1'b0; overflow_detail_q <= 7'd0;
                ppp_wp_q <= 5'd0;
                ppp_count_q <= 6'd0;
                ppp_total_q <= 16'd0;
                ppp_ovr_q <= 1'b0;
                // G2: TOKEN_LATCH fires on the doorbell cycle == frame_start
                // cycle, so the frame's first anchor must survive its own
                // clear.  Re-push after the reset (entry 0 of the new
                // frame); START/DONE can never land here (they follow the
                // doorbell by >= 1 cycle through the issuer).
                if (ppp_push) begin
                    ppp_mem[5'd0] <= {cycle_q, ppp_push_type, ppp_push_data};
                    ppp_wp_q    <= 5'd1;
                    ppp_count_q <= 6'd1;
                    ppp_total_q <= 16'd1;
                end
                // ring arrays intentionally NOT cleared -- see the reset
                // branch comment (V3.9); reads are count-bounded.
            end else if (trace_enable_q && !freeze_q) begin
                if (compute_useful && !steady_q)
                    fill_cycle_q <= cycle_q;
                if (steady_now && !steady_end) begin
                    if (load_active) cnt_l_q <= sat_add1(cnt_l_q);
                    if (compute_useful) cnt_c_q <= sat_add1(cnt_c_q);
                    if (store_active) cnt_s_q <= sat_add1(cnt_s_q);
                    if (load_active && compute_useful) cnt_lc_q <= sat_add1(cnt_lc_q);
                    if (compute_useful && store_active) cnt_cs_q <= sat_add1(cnt_cs_q);
                    if (load_active && store_active) cnt_ls_q <= sat_add1(cnt_ls_q);
                    if (load_active && compute_useful && store_active)
                        cnt_lcs_q <= sat_add1(cnt_lcs_q);
                    if (load_active && (cnt_l_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[0] <= 1'b1;
                    end
                    if (compute_useful && (cnt_c_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[1] <= 1'b1;
                    end
                    if (store_active && (cnt_s_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[2] <= 1'b1;
                    end
                    if (load_active && compute_useful &&
                        (cnt_lc_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[3] <= 1'b1;
                    end
                    if (compute_useful && store_active &&
                        (cnt_cs_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[4] <= 1'b1;
                    end
                    if (load_active && store_active &&
                        (cnt_ls_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[5] <= 1'b1;
                    end
                    if (load_active && compute_useful && store_active &&
                        (cnt_lcs_q == 32'hFFFF_FFFF)) begin
                        overflow_q <= 1'b1; overflow_detail_q[6] <= 1'b1;
                    end
                    if (fifo_level >= fmax_level_q) begin
                        fmax_level_q <= fifo_level;
                        fmax_id_q <= fifo_id;
                    end
                    steady_cycles_q <= sat_add1(steady_cycles_q);
                end
                if (compute_useful) steady_q <= 1'b1;
                if (steady_end) begin
                    drain_cycle_q <= cycle_q;
                    steady_q <= 1'b0;
                end
                if (frame_done)
                    steady_q <= 1'b0;
                if (backpressure) begin
                    current_gap_q <= sat_add1(current_gap_q);
                    if (current_gap_q != 32'hFFFF_FFFF &&
                        current_gap_q + 32'd1 > gmax_q)
                        gmax_q <= current_gap_q + 32'd1;
                end else begin
                    current_gap_q <= 32'd0;
                end
                gap_q <= backpressure;
            end

            // V3.10 (2026-10-14): one-deep WRITE STAGING.  Post-route
            // forensics on the V3.9 build: 100% of the 3000 worst failing
            // paths cross from u_xrd (lsq_rptr replica) into these ring
            // D/CE cones (~12.8ns, route-dominated).  Capturing the push
            // bundle into registers HERE moves every ring-path start
            // next to the ring and gives the cross-module cone a full
            // 10ns cycle.  Protocol: every staged field (incl. cycle_q
            // and the first-of-frame flag) is sampled at the capture
            // edge, so entry content, order, and wp/count/total values
            // are byte-identical -- only the write lands one cycle
            // later.  Capture keeps the old (push_event && !freeze_q)
            // gate; the write side drains the stage regardless of
            // freeze, so the last pre-freeze entry is never lost.
            // Back-to-back 1/cycle pushes sustain: the ring write
            // consumes the stage the same edge the next push captures.
            if (push_event && !freeze_q) begin
                st_valid <= 1'b1;
                st_mem   <= {64'd0, push_fifo, push_data, push_type, cycle_q};
                st_token <= push_token;
                st_ctx   <= push_ctx;
                st_first <= frame_start && clear_on_frame_q;
            end else
                st_valid <= 1'b0;
            if (st_valid) begin
                if (st_first) begin
                    ring_mem[0]       <= st_mem;
                    ring_token_mem[0] <= st_token;
                    ring_ctx_mem[0]   <= st_ctx;
                    ring_wp_q    <= 8'd1;
                    ring_count_q <= 9'd1;
                    ring_total_q <= 15'd1;
                end else begin
                    ring_mem[ring_wp_q]       <= st_mem;
                    ring_token_mem[ring_wp_q] <= st_token;
                    ring_ctx_mem[ring_wp_q]   <= st_ctx;
                    ring_wp_q <= (ring_wp_q == RING_DEPTH-1) ?
                                 8'd0 : ring_wp_q + 8'd1;
                    if (ring_count_q < RING_DEPTH)
                        ring_count_q <= ring_count_q + 9'd1;
                    if (ring_total_q != 15'h7FFF)
                        ring_total_q <= ring_total_q + 15'd1;
                    else begin
                        if (ring_overflow_count_q != 8'hFF)
                            ring_overflow_count_q <= ring_overflow_count_q + 8'd1;
                        overflow_q <= 1'b1;
                    end
                end
            end
            // G2 PPP anchor FIFO push.  Same capture discipline as the main
            // ring (single cycle_q sample at the push edge); no write
            // staging needed at 16x48b (LUT flops, no cross-module cone).
            if (ppp_push) begin
                ppp_mem[ppp_wp_q] <= {cycle_q, ppp_push_type, ppp_push_data};
                ppp_wp_q <= (ppp_wp_q == PPP_DEPTH[4:0]-5'd1) ?
                            5'd0 : ppp_wp_q + 5'd1;
                if (ppp_count_q < PPP_DEPTH[5:0])
                    ppp_count_q <= ppp_count_q + 6'd1;
                else
                    ppp_ovr_q <= 1'b1;   // entry overwrite = anchor loss
                if (ppp_total_q != 16'hFFFF)
                    ppp_total_q <= ppp_total_q + 16'd1;
            end
            if (snapshot_cmd)
                freeze_q <= 1'b1;
        end
    end

    always @(*) begin
        csr_rdata = 32'd0;
        case (csr_raddr)
            A_CTRL:        csr_rdata = {28'd0, clear_on_frame_q, freeze_q,
                                        snapshot_done_q, trace_enable_q};
            A_STATUS:      csr_rdata = {8'd0, ring_overflow_count_q,
                                        6'd0, overflow_detail_q,
                                        snapshot_done_q, freeze_q, overflow_q};
            A_CNT_L:       csr_rdata = cnt_l_q;
            A_CNT_C:       csr_rdata = cnt_c_q;
            A_CNT_S:       csr_rdata = cnt_s_q;
            A_CNT_LC:      csr_rdata = cnt_lc_q;
            A_CNT_CS:      csr_rdata = cnt_cs_q;
            A_CNT_LS:      csr_rdata = cnt_ls_q;
            A_CNT_LCS:     csr_rdata = cnt_lcs_q;
            A_GMAX:        csr_rdata = {current_gap_q[15:0], gmax_q[15:0]};
            A_FMAX:        csr_rdata = {8'd0, fmax_id_q, fmax_level_q};
            A_FILL:        csr_rdata = fill_cycle_q;
            A_DRAIN:       csr_rdata = drain_cycle_q;
            A_STEADY:      csr_rdata = steady_cycles_q;
            A_RING_CTRL:   csr_rdata = {8'd0, 8'd16, 16'd256};
            A_RING_STATUS: csr_rdata = {ring_total_q,
                                        (|ring_overflow_count_q),
                                        8'd0, ring_wp_q};
            A_RING_RD_PTR: csr_rdata = {24'd0, ring_rd_ptr_q};
            A_FRAME_NODE_CASE: csr_rdata = {8'd0, case_id_q, node_id_q,
                                            frame_id_q};
            A_RING_CTX_BASE: csr_rdata = ring_ctx_mem[ring_rd_ptr_q];
            A_PPP_STATUS: csr_rdata = {9'd0, ppp_count_q[5:0], ppp_ovr_q,
                                       ppp_total_q[15:0]};
            A_PPP_RD_PTR: csr_rdata = {27'd0, ppp_rd_ptr_q};
            A_PPP_DATA0:  csr_rdata = ppp_mem[ppp_rd_ptr_q][47:16];
            A_PPP_DATA1:  csr_rdata = {16'd0, ppp_mem[ppp_rd_ptr_q][15:0]};
            default: begin
                if ((csr_raddr >= A_RING_TOKEN_BASE) &&
                    (csr_raddr < A_RING_TOKEN_BASE + 16)) begin
                    csr_rdata = ring_token_mem[ring_rd_ptr_q][(token_byte_off[3:2] * 32) +: 32];
                end else if ((csr_raddr >= A_RING_BASE) &&
                             (csr_raddr < A_RING_BASE + RING_DEPTH * 16)) begin
                    csr_rdata = ring_mem[ring_rd_ptr_q][(ring_byte_off[3:2] * 32) +: 32];
                end
            end
        endcase
    end
    // Sticky-any ring loss flag for the top-level tr_ring_ovr port (V1.1).
    assign ring_ovr = (ring_overflow_count_q != 8'd0);

endmodule
