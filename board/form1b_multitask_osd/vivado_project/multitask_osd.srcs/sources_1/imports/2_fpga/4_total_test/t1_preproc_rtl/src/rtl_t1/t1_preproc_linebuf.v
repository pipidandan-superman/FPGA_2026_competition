`timescale 1ns/1ps
// t1_preproc_linebuf.v
// T1 line buffer: 3 row slots x 320 words x 48 bit (2 adjacent cols x
// 3ch x 8b), built from THREE official blk_mem_gen IP instances
// (t1_lb_bmg, Simple_Dual_Port 48b x 512, READ_FIRST, Always_Enabled, no
// RSTB, no output register -- one BMG per row slot). Instantiation ports
// verified against the generated .veo template (IP instantiation law).
//
// Timing contract vs the old behavioral model: BMG port B is a SYNCHRONOUS
// read (data appears 1 cycle after addrb). The scheduler compensates with
// a 1-cycle issue pipeline (see t1_preproc_top ST_COMPUTE pipe_filled).
//
// Read port sharing: the bilinear window always reads two DIFFERENT slots
// (r0%3 and (r0+1)%3), so each instance's single port B serves window row A
// when rd_slot_a == slot, else window row B. Write port A comes from fetch.
module t1_preproc_linebuf (
  input  wire        clk,
  // write port (from fetch)
  input  wire        wr_en,
  input  wire [1:0]  wr_slot,
  input  wire [8:0]  wr_pair,     // 0..319, col pair index (cols 2*pair, 2*pair+1)
  input  wire [47:0] wr_data,
  // read port A / B (rows r0 / r1 of the bilinear window)
  input  wire [1:0]  rd_slot_a,
  input  wire [8:0]  rd_pair_a,
  output wire [47:0] rd_data_a,
  input  wire [1:0]  rd_slot_b,
  input  wire [8:0]  rd_pair_b,
  output wire [47:0] rd_data_b
);

  // word layout: [7:0]=col0 B, [15:8]=col0 G, [23:16]=col0 R,
  //              [31:24]=col1 B, [39:32]=col1 G, [47:40]=col1 R

  wire [47:0] dout0, dout1, dout2;

  wire we0 = wr_en && (wr_slot == 2'd0);
  wire we1 = wr_en && (wr_slot == 2'd1);
  wire we2 = wr_en && (wr_slot == 2'd2);

  // each instance's read address serves window row A or row B
  wire [8:0] addr0 = (rd_slot_a == 2'd0) ? rd_pair_a : rd_pair_b;
  wire [8:0] addr1 = (rd_slot_a == 2'd1) ? rd_pair_a : rd_pair_b;
  wire [8:0] addr2 = (rd_slot_a == 2'd2) ? rd_pair_a : rd_pair_b;

  t1_lb_bmg u_row0 (
    .clka  (clk),      .wea (we0),  .addra (wr_pair), .dina (wr_data),
    .clkb  (clk),      .addrb (addr0), .doutb (dout0)
  );
  t1_lb_bmg u_row1 (
    .clka  (clk),      .wea (we1),  .addra (wr_pair), .dina (wr_data),
    .clkb  (clk),      .addrb (addr1), .doutb (dout1)
  );
  t1_lb_bmg u_row2 (
    .clka  (clk),      .wea (we2),  .addra (wr_pair), .dina (wr_data),
    .clkb  (clk),      .addrb (addr2), .doutb (dout2)
  );

  assign rd_data_a = (rd_slot_a == 2'd0) ? dout0 :
                     (rd_slot_a == 2'd1) ? dout1 : dout2;
  assign rd_data_b = (rd_slot_b == 2'd0) ? dout0 :
                     (rd_slot_b == 2'd1) ? dout1 : dout2;

endmodule
