`timescale 1ns/1ps
// t1_preproc_top_m.v -- T1 PL preprocess, M-contract letterbox edition.
// (2026-10-22_t1_letterbox_bit_run02)
//
// Pin-compatible replacement for t1_preproc_top: same CSR map, same
// go/irq frame protocol, same AXI master pinout. BD unchanged.
//   CSR 0x00 CTRL go | 0x04 STATUS busy/irq | 0x08 SRC_ADDR | 0x0C DST_ADDR
//   0x10 VERSION ro 32'h0100_0002
//
// Datapath: fetch (UNCHANGED, board-proven AXI read) -> 48b two-pixel
// linebuf slots (old t1_preproc_linebuf, board-proven BMG) -> capture with
// byte rotation to {B,G,R} taps -> letterbox_scale (integer exact bilinear,
// run01 gate-proven) -> u8 {R,G,B} pixel stream -> t1_preproc_write_m
// (packs 4B words, writes 320x320x3 u8 RGB HWC blob = 307200 B).
//
// Geometry is the fixed T1 camera contract 640x480 -> letterbox r=0.5
// (320x240 content + 40/40 gray114 pad). At r=0.5 the half-pixel phase is
// CONSTANT: sx = ((2d+1)*640-320)/640 = d + 0.5, so ix = 2d and the x
// phase numerator wx = 320 (== QX/2) for every output pixel; likewise
// iy = 2e, wy = 240 (== QY/2). Both bilinear tap rows/cols are REAL
// weights, so rows iy AND iy+1 are fetched (480 source rows/frame) and
// letterbox_scale computes the full gate-proven guarded bilinear.
// The phase registers are kept as accumulators (init = half-pixel
// numerator, increment 0) so the general structure survives a geometry
// change.
//
// Timing contract (EMPIRICALLY pinned by the run02 gate debug trace): the
// t1_lb_bmg model delivers port-B data TWO cycles after the read address
// appears (the linebuf header's 1-cycle note was masked by the old top's
// own issue pipeline; this scheduler has no such pipeline). doutb holds
// while addrb holds. Capture: present pair addr, count LB_LAT, register
// taps+phase into cap_* and raise cap_v for one cycle (writer consumes
// on that cycle). ~4 cycles/pixel, ~1.3k cycles/row.
module t1_preproc_top (
  input  wire        clk,
  input  wire        rstn,
  input  wire [11:0] s_axil_awaddr,
  input  wire        s_axil_awvalid,
  output wire        s_axil_awready,
  input  wire [31:0] s_axil_wdata,
  input  wire [3:0]  s_axil_wstrb,
  input  wire        s_axil_wvalid,
  output wire        s_axil_wready,
  output wire [1:0]  s_axil_bresp,
  output wire        s_axil_bvalid,
  input  wire        s_axil_bready,
  input  wire [11:0] s_axil_araddr,
  input  wire        s_axil_arvalid,
  output wire        s_axil_arready,
  output wire [31:0] s_axil_rdata,
  output wire [1:0]  s_axil_rresp,
  output wire        s_axil_rvalid,
  input  wire        s_axil_rready,
  output wire [31:0] m_axi_araddr,
  output wire [7:0]  m_axi_arlen,
  output wire [2:0]  m_axi_arsize,
  output wire [1:0]  m_axi_arburst,
  output wire        m_axi_arvalid,
  input  wire        m_axi_arready,
  input  wire [31:0] m_axi_rdata,
  input  wire [1:0]  m_axi_rresp,
  input  wire        m_axi_rvalid,
  input  wire        m_axi_rlast,
  output wire        m_axi_rready,
  output wire [31:0] m_axi_awaddr,
  output wire [7:0]  m_axi_awlen,
  output wire [2:0]  m_axi_awsize,
  output wire [1:0]  m_axi_awburst,
  output wire        m_axi_awvalid,
  input  wire        m_axi_awready,
  output wire [31:0] m_axi_wdata,
  output wire [3:0]  m_axi_wstrb,
  output wire        m_axi_wvalid,
  input  wire        m_axi_wready,
  output wire        m_axi_wlast,
  input  wire [1:0]  m_axi_bresp,
  input  wire        m_axi_bvalid,
  output wire        m_axi_bready,
  output wire        irq
);

  localparam integer W2 = 320, H2 = 240, PAD_T = 40;
  localparam integer OUT_H = 320;
  localparam integer LB_LAT = 2;   // gate-pinned: BMG read latency = 2

  localparam ST_IDLE = 3'd0, ST_REQ = 3'd1, ST_FETCH_WAIT = 3'd2,
             ST_ROW_START = 3'd3, ST_CAPTURE = 3'd4,
             ST_WRITE_WAIT = 3'd5, ST_DONE = 3'd6;

  reg [2:0] state;
  wire busy_r = (state != ST_IDLE);
  reg [8:0]  y_out;          // 0..319 output row
  reg        wr_valid;       // level command to the writer

  // ---------------- CSR (identical protocol to t1_preproc_top) ----------
  reg [31:0] src_addr_r, dst_addr_r;
  reg        irq_r, go_pulse, done_pulse;
  reg [1:0]  slv_state;
  reg        bvalid_r, rvalid_r;
  reg [31:0] rdata_r;
  localparam SLV_IDLE = 2'd0, SLV_B = 2'd1, SLV_R = 2'd2;

  assign s_axil_awready = (slv_state == SLV_IDLE);
  assign s_axil_wready  = (slv_state == SLV_IDLE);
  assign s_axil_arready = (slv_state == SLV_IDLE);
  assign s_axil_bresp   = 2'b00;
  assign s_axil_bvalid  = bvalid_r;
  assign s_axil_rresp   = 2'b00;
  assign s_axil_rvalid  = rvalid_r;
  assign s_axil_rdata   = rdata_r;
  assign irq            = irq_r;

  wire w_fire = s_axil_awvalid && s_axil_wvalid && (slv_state == SLV_IDLE);
  wire r_fire = s_axil_arvalid && (slv_state == SLV_IDLE) && !w_fire;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      slv_state <= SLV_IDLE;
      bvalid_r <= 1'b0; rvalid_r <= 1'b0; rdata_r <= 32'd0;
      src_addr_r <= 32'd0; dst_addr_r <= 32'd0;
      irq_r <= 1'b0; go_pulse <= 1'b0;
    end else begin
      go_pulse <= 1'b0;
      case (slv_state)
        SLV_IDLE: begin
          if (w_fire) begin
            case (s_axil_awaddr)
              12'h000: if (s_axil_wdata[0] && !busy_r) go_pulse <= 1'b1;
              12'h004: if (s_axil_wdata[1]) irq_r <= 1'b0;
              12'h008: if (!busy_r) src_addr_r <= s_axil_wdata;
              12'h00C: if (!busy_r) dst_addr_r <= s_axil_wdata;
              default: ;
            endcase
            slv_state <= SLV_B;
          end else if (r_fire) begin
            case (s_axil_araddr)
              12'h000, 12'h004: rdata_r <= {30'd0, irq_r, busy_r};
              12'h008:          rdata_r <= src_addr_r;
              12'h00C:          rdata_r <= dst_addr_r;
              12'h010:          rdata_r <= 32'h0100_0002;
              default:          rdata_r <= 32'd0;
            endcase
            rvalid_r <= 1'b1; slv_state <= SLV_R;
          end
        end
        SLV_B: begin
          bvalid_r <= 1'b1;
          if (bvalid_r && s_axil_bready) begin
            bvalid_r <= 1'b0; slv_state <= SLV_IDLE;
          end
        end
        SLV_R: begin
          if (rvalid_r && s_axil_rready) begin
            rvalid_r <= 1'b0; slv_state <= SLV_IDLE;
          end
        end
        default: slv_state <= SLV_IDLE;
      endcase
      if (done_pulse) irq_r <= 1'b1;
    end
  end

  // ---------------- scheduler -------------------------------------------
  reg [8:0]  iy;                   // source row for current scaled row (2*sy)
  reg [11:0] ry;                   // y phase numerator (==0 at r=0.5)
  reg [8:0]  p_sx;                 // presented word/pair addr (= sx, 0..319)
  reg [11:0] p_rx;                 // x phase numerator (==0 at r=0.5)
  reg [1:0]  ph_cnt;
  reg        cap_v;
  reg [11:0] cap_rx;
  reg [23:0] cap_a0, cap_a1, cap_b0, cap_b1;
  reg [8:0]  px_cnt;
  reg        slot_v0, slot_v1, slot_v2;
  reg [8:0]  slot_row0, slot_row1, slot_row2;
  reg        fc_valid;
  reg [8:0]  fc_row;
  reg [1:0]  fc_slot;

  wire scaled_row = (y_out >= PAD_T) && (y_out < PAD_T + H2);

  // y phase next-state (Bresenham; r=0.5 -> STEPY_I=2, STEPY_R=0)
  wire [8:0] iy_nxt = iy + 9'd2;   // carry never fires at r=0.5

  wire [1:0] slot_a_i = iy % 3;
  wire [1:0] slot_b_i = (iy + 9'd1) % 3;

  wire hit0 = (slot_a_i == 2'd0) ? (slot_v0 && slot_row0 == iy) :
              (slot_a_i == 2'd1) ? (slot_v1 && slot_row1 == iy) :
                                   (slot_v2 && slot_row2 == iy);
  wire hit1 = (slot_b_i == 2'd0) ? (slot_v0 && slot_row0 == iy + 9'd1) :
              (slot_b_i == 2'd1) ? (slot_v1 && slot_row1 == iy + 9'd1) :
                                   (slot_v2 && slot_row2 == iy + 9'd1);

  wire fc_ready, fc_done, wr_ready, wr_done;

  // pixel stream into writer. letterbox_scale is now a 5-stage PIPELINE
  // (run02 timing fix: the combinational version failed impl timing,
  // WNS -13.353ns, cap regs -> packer flops; 2-stage was still -5.50ns). Writer consumes 1 px/cycle
  // with no backpressure; px_fire is the pipeline's out_valid, which lags
  // cap_v by 2 cycles -- the writer is still in ST_FILL then (it only
  // leaves ST_FILL after seeing all 320 px), so the trailing pixels of
  // each row drain while the scheduler sits in ST_WRITE_WAIT. Safe.
  wire        sc_valid;
  wire        px_fire = sc_valid;

  // rotate raw DDR 48b word (2 px, per-px bytes {B,G,R} with B at [7:0],
  // R at [23:16]) into letterbox_scale {B,G,R} tap order ([23:16]=B):
  // tap = {B, G, R}. r=0.5: both bilinear taps of output pixel sx live in
  // word sx (cols 2sx, 2sx+1); a1/b0/b1 are zero-weight-guarded in scale.
  // (Declared before the scheduler block: capture registers sample these.)
  wire [47:0] lb_rd_a, lb_rd_b;
  wire [23:0] tap_a0 = {lb_rd_a[7:0],   lb_rd_a[15:8],  lb_rd_a[23:16]};
  wire [23:0] tap_a1 = {lb_rd_a[31:24], lb_rd_a[39:32], lb_rd_a[47:40]};
  wire [23:0] tap_b0 = {lb_rd_b[7:0],   lb_rd_b[15:8],  lb_rd_b[23:16]};
  wire [23:0] tap_b1 = {lb_rd_b[31:24], lb_rd_b[39:32], lb_rd_b[47:40]};

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state <= ST_IDLE; y_out <= 9'd0; iy <= 9'd0; ry <= 12'd0;
      p_sx <= 9'd0; p_rx <= 12'd0; ph_cnt <= 2'd0; cap_v <= 1'b0;
      cap_rx <= 12'd0; cap_a0 <= 24'd0; cap_a1 <= 24'd0;
      cap_b0 <= 24'd0; cap_b1 <= 24'd0;
      px_cnt <= 9'd0;
      slot_v0 <= 1'b0; slot_v1 <= 1'b0; slot_v2 <= 1'b0;
      slot_row0 <= 9'd0; slot_row1 <= 9'd0; slot_row2 <= 9'd0;
      fc_valid <= 1'b0; wr_valid <= 1'b0; fc_row <= 9'd0; fc_slot <= 2'd0;
      done_pulse <= 1'b0;
    end else begin
      done_pulse <= 1'b0;
      // global accept-clear: the writer may take the row command while the
      // scheduler is in ANY state (it is issued at ROW_START, before the
      // px stream). Clearing must happen at accept, not at wr_done -- the
      // writer returns to IDLE while wr_done is still high and would
      // re-accept a level command held until ST_WRITE_WAIT.
      if (wr_valid && wr_ready) wr_valid <= 1'b0;
      case (state)
        ST_IDLE: begin
          if (go_pulse) begin
            y_out <= 9'd0; iy <= 9'd0; ry <= 12'd240;  // wy init = QY/2
            slot_v0 <= 1'b0; slot_v1 <= 1'b0; slot_v2 <= 1'b0;
            state <= ST_REQ;
          end
        end

        ST_REQ: begin
          if (!scaled_row) begin
            wr_valid <= 1'b1;              // pad row; writer fills gray114
            state <= ST_WRITE_WAIT;
          end else if (!hit0) begin
            fc_valid <= 1'b1; fc_row <= iy; fc_slot <= slot_a_i;
            state <= ST_FETCH_WAIT;
          end else if (!hit1) begin        // row iy+1: real weight (wy!=0)
            fc_valid <= 1'b1; fc_row <= iy + 9'd1; fc_slot <= slot_b_i;
            state <= ST_FETCH_WAIT;
          end else begin
            state <= ST_ROW_START;
          end
        end

        ST_FETCH_WAIT: begin
          if (fc_valid && fc_ready) fc_valid <= 1'b0;
          if (fc_done) begin
            case (fc_slot)
              2'd0: begin slot_v0 <= 1'b1; slot_row0 <= fc_row; end
              2'd1: begin slot_v1 <= 1'b1; slot_row1 <= fc_row; end
              default: begin slot_v2 <= 1'b1; slot_row2 <= fc_row; end
            endcase
            state <= ST_REQ;
          end
        end

        ST_ROW_START: begin
          p_sx <= 9'd0; p_rx <= 12'd320; ph_cnt <= LB_LAT[1:0]; // wx init
          cap_v <= 1'b0; px_cnt <= 9'd0;
          wr_valid <= 1'b1;   // row command BEFORE the px stream: the
          state <= ST_CAPTURE; // writer must be in ST_FILL when px arrives
        end

        ST_CAPTURE: begin
          if (cap_v) begin
            // consume: writer samples px_data this cycle
            cap_v <= 1'b0;
            if (px_cnt == W2[8:0] - 9'd1) begin
              iy <= iy_nxt;                 // ry stays 0 (STEPY_R=0)
              state <= ST_WRITE_WAIT;
            end else begin
              px_cnt <= px_cnt + 9'd1;
              p_sx <= p_sx + 9'd1;          // next word/pair
              ph_cnt <= LB_LAT[1:0];
            end
          end else if (ph_cnt != 2'd0) begin
            ph_cnt <= ph_cnt - 2'd1;        // linebuf read latency
          end else begin
            // taps valid now (doutb holds while addrb holds): capture
            cap_a0 <= tap_a0; cap_a1 <= tap_a1;
            cap_b0 <= tap_b0; cap_b1 <= tap_b1;
            cap_rx <= p_rx;                 // ==0 at r=0.5
            cap_v  <= 1'b1;
          end
        end

        ST_WRITE_WAIT: begin
          // clear on wr_done (pulsed exactly once): clearing on wr_ready
          // would race -- the writer is back in IDLE one cycle after done
          // with cmd_valid still high and would re-accept the same row.
          if (wr_done) begin
            wr_valid <= 1'b0;
            if (y_out == OUT_H[8:0] - 9'd1) state <= ST_DONE;
            else begin
              y_out <= y_out + 9'd1;
              state <= ST_REQ;
            end
          end
        end

        ST_DONE: begin
          done_pulse <= 1'b1;
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // ---------------- datapath --------------------------------------------
  wire        lb_wr_en;
  wire [1:0]  lb_wr_slot;
  wire [8:0]  lb_wr_pair;
  wire [47:0] lb_wr_data;

  t1_preproc_fetch u_fetch (
    .clk(clk), .rstn(rstn), .src_base(src_addr_r),
    .cmd_valid(fc_valid), .cmd_row(fc_row), .cmd_slot(fc_slot),
    .cmd_ready(fc_ready), .cmd_done(fc_done),
    .lb_wr_en(lb_wr_en), .lb_wr_slot(lb_wr_slot),
    .lb_wr_pair(lb_wr_pair), .lb_wr_data(lb_wr_data),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
    .m_axi_rvalid(m_axi_rvalid), .m_axi_rlast(m_axi_rlast),
    .m_axi_rready(m_axi_rready)
  );

  wire [47:0] lb_rd_a_w, lb_rd_b_w;
  t1_preproc_linebuf u_linebuf (
    .clk(clk),
    .wr_en(lb_wr_en), .wr_slot(lb_wr_slot), .wr_pair(lb_wr_pair),
    .wr_data(lb_wr_data),
    .rd_slot_a(slot_a_i), .rd_pair_a(p_sx), .rd_data_a(lb_rd_a_w),
    .rd_slot_b(slot_b_i), .rd_pair_b(p_sx), .rd_data_b(lb_rd_b_w)
  );
  assign lb_rd_a = lb_rd_a_w;
  assign lb_rd_b = lb_rd_b_w;

  wire [23:0] px_data;   // from letterbox_scale (registered stage-B output)
  letterbox_scale #(
    .QX(640), .QY(480)
  ) u_scale (
    .clk(clk), .rstn(rstn),
    .in_valid(cap_v),
    .a0(cap_a0), .a1(cap_a1), .b0(cap_b0), .b1(cap_b1),
    .wx(cap_rx), .wy(ry),
    .out_valid(sc_valid), .pix_rgb(px_data)
  );

  t1_preproc_write_m u_write (
    .clk(clk), .rstn(rstn), .dst_base(dst_addr_r),
    .px_we(px_fire), .px_data(px_data),
    .cmd_valid(wr_valid), .cmd_y(y_out), .cmd_pad(!scaled_row),
    .cmd_ready(wr_ready), .cmd_done(wr_done),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
  );

endmodule
