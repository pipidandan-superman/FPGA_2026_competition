`timescale 1ns/1ps
// t1_preproc_scale.v
// T1 scale core, bit-exact match of the reference cv2.resize(INTER_LINEAR)
// (IPP 2026 fixed-point path, verified zero-diff on the full reachable
// domain: all 511x511 col-pair-sum combos x both y phases, plus random and
// real frames -- see tools/cv2_probe and run REPORT).
//
// Geometry: 640x480 -> 320x320 direct (keep_ratio=False). x phase is a
// constant 0.5 (taps cols 2x, 2x+1 with equal weight); y taps rows
// r0 = (3*y)>>1 / r0+1 with weights {3,1}/{1,3} by y parity.
//
// Empirically extracted exact integer function (cv2 oracle, this build):
//   s0 = p00+p01 (row r0 adjacent-col sum), s1 = p10+p11 (row r1 sum)
//   y even: out = (3*s0 + (s1 & ~1) + 4) >> 3
//   y odd : out = ((s0 & ~1) + 3*s1 + 4) >> 3
// Max value (3*510+510+4)>>3 = 255: naturally bounded, no clamp required.
// NOTE: both rows are ALWAYS consumed (no wy==0 bypass); the scheduler
// therefore fetches r0 and r0+1 for every output row.
module t1_preproc_scale (
  input  wire [8:0]  x,          // output col index (kept for debug observability)
  input  wire        ypar,       // y[0]: 0 = even output row, 1 = odd
  input  wire [47:0] row0_word,  // cols 2x,2x+1 of row r0
  input  wire [47:0] row1_word,  // cols 2x,2x+1 of row r1
  output wire [7:0]  pix_b,
  output wire [7:0]  pix_g,
  output wire [7:0]  pix_r
);

  // word layout: [7:0]=col0 B, [15:8]=col0 G, [23:16]=col0 R,
  //              [31:24]=col1 B, [39:32]=col1 G, [47:40]=col1 R
  function [7:0] blend;
    input [7:0] p00;   // row r0, col 2x
    input [7:0] p01;   // row r0, col 2x+1
    input [7:0] p10;   // row r1, col 2x
    input [7:0] p11;   // row r1, col 2x+1
    input       yodd;  // y parity
    reg   [10:0] s0;   // p00+p01 (0..510)
    reg   [10:0] s1;   // p10+p11 (0..510)
    reg   [12:0] v;    // max 3*510+510+4 = 2044
    begin
      s0 = {3'b000, p00} + {3'b000, p01};
      s1 = {3'b000, p10} + {3'b000, p11};
      if (yodd)
        v = {s0[10:1], 1'b0} + {1'b0, s1, 1'b0} + {1'b0, s1} + 13'd4; // (s0&~1)+3*s1+4
      else
        v = {s0, 1'b0} + {1'b0, s0} + {s1[10:1], 1'b0} + 13'd4;      // 3*s0+(s1&~1)+4
      blend = v[12:3];
    end
  endfunction

  assign pix_b = blend(row0_word[7:0],   row0_word[31:24],
                       row1_word[7:0],   row1_word[31:24], ypar);
  assign pix_g = blend(row0_word[15:8],  row0_word[39:32],
                       row1_word[15:8],  row1_word[39:32], ypar);
  assign pix_r = blend(row0_word[23:16], row0_word[47:40],
                       row1_word[23:16], row1_word[47:40], ypar);

endmodule
