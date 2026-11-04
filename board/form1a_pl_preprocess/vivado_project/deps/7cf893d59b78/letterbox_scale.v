`timescale 1ns/1ps
// letterbox_scale.v
// PL letterbox bilinear core, PIPELINED 5 stages (1 pixel/cycle throughput).
// (2026-10-22_t1_letterbox_bit_run02, timing fix: run01 build FAILED timing
//  WNS -13.353ns -- the combinational version put two chained multipliers +
//  constant reciprocal divide between the capture registers and the writer
//  packer flops. This 2-stage version is BIT-IDENTICAL.)
//
// Implements the M-contract resize as EXACT INTEGER rational arithmetic:
//   phase per axis: sx = ((2*d+1)*N - D) / (2D)   (exact rational, N=src, D=dst)
//   ix = floor(sx), wx = numerator of the fractional part, in [0, 2D) = [0,QX)
//   Qx = 2*W2, Qy = 2*H2 (both even):
//   S = p00*(Qx-wx)*(Qy-wy) + p01*wx*(Qy-wy)
//     + p10*(Qx-wx)*wy     + p11*wx*wy
//   v = (S + Qx*Qy/2) / (Qx*Qy)          -- round-half-up, one single rounding
// This is exactly the README real-number formula (half-pixel INTER_LINEAR)
// evaluated with zero representation error; the golden generator
// (tools/gen_gate_vectors.py) computes the identical function.
// Ties round UP -- verified equal to cv2 8U resize behavior on all r=0.5
// and identity frames, including the 100%-tie checkerboard frame.
//
// Pipeline (bit-exact by integer associativity):
//   stage A (registered): guards applied, then the four column products
//     qa0=p00*(Qx-wx) qa1=p01*wx qb0=p10*(Qx-wx) qb1=p11*wx  (each <= 18 bits)
//     wy registered alongside.
//   stage B (registered): the four row-weighted products qa*(QY-wy) etc.
//     (each <= 255*QX*QY_col < 2^27).
//   stage C (registered): s = q00+q01+q10+q11 (any integer grouping exact),
//     v = (s + QXQY/2) / QXQY (constant divisor).
// Latency: 5 clk from in_valid to out_valid. in_valid may gap arbitrarily.
//
// Width analysis: Qx,Qy <= 640; stage-A products <= 255*640 = 163200 < 2^18;
// s <= 255*640*640 < 2^27; +half keeps < 2^27. All fits 32 bits; the convex
// weights sum to 1 so the result needs no saturation.
module letterbox_scale #(
  parameter integer QX = 640,          // 2*W2
  parameter integer QY = 480           // 2*H2
) (
  input  wire        clk,
  input  wire        rstn,
  input  wire        in_valid,         // a0..b1, wx, wy valid this cycle
  input  wire [23:0] a0,               // row iy  , col ix    , {B,G,R}
  input  wire [23:0] a1,               // row iy  , col ix+1
  input  wire [23:0] b0,               // row iy+1, col ix
  input  wire [23:0] b1,               // row iy+1, col ix+1
  input  wire [11:0] wx,               // x fraction numerator [0, QX)
  input  wire [11:0] wy,               // y fraction numerator [0, QY)
  output reg         out_valid,        // pix_rgb valid this cycle (2-clk lag)
  output reg  [23:0] pix_rgb           // {R,G,B} -- BGR->RGB swap here
);

  localparam integer QXQY   = QX * QY;
  localparam integer QXQY_H = QXQY / 2;   // exact: QX,QY both even

  // ---------------- stage A: guards + column products (registered) --------
  // X-propagation guards (t1 pitfall #5): a zero-weight operand is replaced
  // by a KNOWN sibling value, never X (row iy+1 may be unwritten when wy==0;
  // col ix+1 unwritten never). Applied BEFORE the pipeline regs so the
  // guarded values themselves are what gets pipelined.
  wire [23:0] a1g = (wx == 12'd0) ? a0 : a1;
  wire [23:0] b0g = (wy == 12'd0) ? a0 : b0;
  wire [23:0] b1g = (wy == 12'd0) ? a0 : ((wx == 12'd0) ? b0 : b1);

  wire [11:0] qxmwx = QX[11:0] - wx;      // QX-wx in [1, QX]

  // stage-A products per channel: p*(weight) <= 255*640 = 163200 < 2^18
  reg [17:0] qa0_B, qa1_B, qb0_B, qb1_B;  // B channel ([23:16] of taps)
  reg [17:0] qa0_G, qa1_G, qb0_G, qb1_G;  // G channel ([15:8])
  reg [17:0] qa0_R, qa1_R, qb0_R, qb1_R;  // R channel ([7:0])
  reg [11:0] wy_A;                        // y phase piped alongside
  reg        vA;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      qa0_B <= 18'd0; qa1_B <= 18'd0; qb0_B <= 18'd0; qb1_B <= 18'd0;
      qa0_G <= 18'd0; qa1_G <= 18'd0; qb0_G <= 18'd0; qb1_G <= 18'd0;
      qa0_R <= 18'd0; qa1_R <= 18'd0; qb0_R <= 18'd0; qb1_R <= 18'd0;
      wy_A  <= 12'd0; vA <= 1'b0;
    end else begin
      vA <= in_valid;
      if (in_valid) begin
        qa0_B <= a0 [23:16] * qxmwx;  qa1_B <= a1g[23:16] * wx;
        qb0_B <= b0g[23:16] * qxmwx;  qb1_B <= b1g[23:16] * wx;
        qa0_G <= a0 [15:8]  * qxmwx;  qa1_G <= a1g[15:8]  * wx;
        qb0_G <= b0g[15:8]  * qxmwx;  qb1_G <= b1g[15:8]  * wx;
        qa0_R <= a0 [7:0]   * qxmwx;  qa1_R <= a1g[7:0]   * wx;
        qb0_R <= b0g[7:0]   * qxmwx;  qb1_R <= b1g[7:0]   * wx;
        wy_A  <= wy;
      end
    end
  end

  // ---------------- stage B: row-weighted products (registered) ---------
  // 18b column product x 9b row weight <= 163200*480 = 78336000 < 2^27.
  wire [11:0] qymwy = QY[11:0] - wy_A;    // QY-wy in [1, QY]
  reg [26:0] q00_B, q01_B, q10_B, q11_B;  // B channel ([23:16] of taps)
  reg [26:0] q00_G, q01_G, q10_G, q11_G;  // G channel ([15:8])
  reg [26:0] q00_R, q01_R, q10_R, q11_R;  // R channel ([7:0])
  reg        vB;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      q00_B <= 27'd0; q01_B <= 27'd0; q10_B <= 27'd0; q11_B <= 27'd0;
      q00_G <= 27'd0; q01_G <= 27'd0; q10_G <= 27'd0; q11_G <= 27'd0;
      q00_R <= 27'd0; q01_R <= 27'd0; q10_R <= 27'd0; q11_R <= 27'd0;
      vB <= 1'b0;
    end else begin
      vB <= vA;
      if (vA) begin
        q00_B <= qa0_B * qymwy;  q01_B <= qa1_B * qymwy;
        q10_B <= qb0_B * wy_A;   q11_B <= qb1_B * wy_A;
        q00_G <= qa0_G * qymwy;  q01_G <= qa1_G * qymwy;
        q10_G <= qb0_G * wy_A;   q11_G <= qb1_G * wy_A;
        q00_R <= qa0_R * qymwy;  q01_R <= qa1_R * qymwy;
        q10_R <= qb0_R * wy_A;   q11_R <= qb1_R * wy_A;
      end
    end
  end

  // ---------------- stage C: sum + round/divide, 3 sub-stages --------------
  // v = (s + QXQY/2) / QXQY, EXACT integer round-half-up. Verified
  // exhaustively offline over every reachable t=s+half in [0, 2^27):
  //   t/D == (t * R44) >> 44   with R44 = ceil(2^44/D) = 57266231 (26 bits),
  //   max product 255*QX*QY*R44 < 2^53. Three sub-stages so no single
  //   cycle carries the whole divide: 10-22 v2 build had the full
  //   reciprocal multiply as ONE stage-C path (23 LUT/CARRY levels,
  //   WNS +0.348ns) -- split for real margin.
  localparam [31:0] R44 = 32'd57266231;   // ceil(2^44 / 307200), D=QX*QY

  reg [27:0] tC_B, tC_G, tC_R;            // s + QXQY_H (s < 2^27)
  reg [53:0] pC_B, pC_G, pC_R;            // t * R44 (full product, < 2^53)
  reg        vC1, vC2;

  // Continuous-assign slices: xelab 2025.2 MIS-SIMULATES a part-select of a
  // wide reg inside a clocked-block concat ({pC_*[53:44]} read wrong bits
  // while the regs held the right values -- verified 10-22 with per-cycle
  // traces). A wire slice elaborates correctly (and equals tb_mul proof).
  wire [9:0] v_sl_B = pC_B[53:44];        // == t/D, exact (<= 255)
  wire [9:0] v_sl_G = pC_G[53:44];
  wire [9:0] v_sl_R = pC_R[53:44];

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      tC_B <= 28'd0; tC_G <= 28'd0; tC_R <= 28'd0; vC1 <= 1'b0;
      pC_B <= 54'd0; pC_G <= 54'd0; pC_R <= 54'd0; vC2 <= 1'b0;
      out_valid <= 1'b0;
      pix_rgb   <= 24'd0;
    end else begin
      // C1: exact 4-term sum + half (any integer grouping is exact)
      vC1 <= vB;
      if (vB) begin
        tC_B <= q00_B + q01_B + q10_B + q11_B + QXQY_H[27:0];
        tC_G <= q00_G + q01_G + q10_G + q11_G + QXQY_H[27:0];
        tC_R <= q00_R + q01_R + q10_R + q11_R + QXQY_H[27:0];
      end
      // C2: reciprocal multiply (one DSP48 chain)
      vC2 <= vC1;
      if (vC1) begin
        pC_B <= tC_B * R44;
        pC_G <= tC_G * R44;
        pC_R <= tC_R * R44;
      end
      // C3: BGR->RGB output flip (channel-wise linear)
      out_valid <= vC2;
      if (vC2) begin
        pix_rgb <= {v_sl_R[7:0], v_sl_G[7:0], v_sl_B[7:0]};
      end
    end
  end

endmodule
