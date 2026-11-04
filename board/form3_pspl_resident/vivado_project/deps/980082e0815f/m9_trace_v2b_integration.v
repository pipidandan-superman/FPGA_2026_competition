//====================================================================
// File name   : m9_trace_v2b_integration.sv
// Author      : M9 verification
// Create date : 2026-10-11
// Description : Handshake-qualified v2b trace integration wrapper
// Target      : FPGA/ASIC
// Revision    : V1.0
//====================================================================
`timescale 1ns / 1ps

// This wrapper is staged verification RTL. It makes the required v2b
// observe-only bindings explicit before they are wired into the production
// m9_intra_top data path.
module m9_trace_v2b_integration (
    input wire         clk,
    input wire         rst_n,
    input wire         steady_end,
    input wire         ld_tvalid,
    input wire         ld_tready,
    input wire         y_tvalid,
    input wire         y_tready,
    input wire         padding_tile_active,
    input wire         s2mm_tvalid,
    input wire         s2mm_tready,
    input wire         ddr_gap,
    input wire         fifo_full,
    input wire [15:0]  fifo_level,
    input wire [7:0]   fifo_id,
    input wire         frame_start,
    input wire         frame_done,
    input wire         event_valid,
    input wire [3:0]   event_type,
    input wire [11:0]  event_data,
    input wire [15:0]  event_fifo_level,
    input wire         csr_we,
    input wire [11:0]  csr_waddr,
    input wire [31:0]  csr_wdata,
    input wire [11:0]  csr_raddr,
    output wire [31:0] csr_rdata
`ifdef M9_TRACE_TEST
    ,input wire        test_seed_valid
    ,input wire [3:0]  test_seed_sel
    ,input wire [31:0] test_seed_value
`endif
);

    // Contract bindings: acceptance handshakes, not busy or request levels.
    wire load_active   = ld_tvalid   && ld_tready;
    wire compute_useful = y_tvalid  && y_tready && !padding_tile_active;
    wire store_active  = s2mm_tvalid && s2mm_tready;

    m9_trace_v2b u_trace (
        .clk               (clk),
        .rst_n             (rst_n),
        .steady_end        (steady_end),
        .frame_start       (frame_start),
        .frame_done        (frame_done),
        .load_active       (load_active),
        .compute_useful    (compute_useful),
        .store_active      (store_active),
        .ddr_gap           (ddr_gap),
        .fifo_full         (fifo_full),
        .fifo_level        (fifo_level),
        .fifo_id           (fifo_id),
        .event_valid       (event_valid),
        .event_type        (event_type),
        .event_data        (event_data),
        .event_fifo_level  (event_fifo_level),
        .csr_we            (csr_we),
        .csr_waddr         (csr_waddr),
        .csr_wdata         (csr_wdata),
        .csr_raddr         (csr_raddr),
        .csr_rdata         (csr_rdata)
`ifdef M9_TRACE_TEST
        ,.test_seed_valid  (test_seed_valid)
        ,.test_seed_sel    (test_seed_sel)
        ,.test_seed_value  (test_seed_value)
`endif
    );
endmodule
