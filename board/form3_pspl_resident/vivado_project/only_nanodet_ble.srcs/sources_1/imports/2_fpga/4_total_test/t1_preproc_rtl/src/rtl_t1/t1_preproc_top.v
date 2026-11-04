`timescale 1ns/1ps
// t1_preproc_top.v
// T1 PL preprocess top: AXI4-Lite CSR + scheduler FSM + fetch/linebuf/scale/
// norm/write pipeline stages.
//
// Pipeline notes (integration round):
//  * linebuf = 3x BMG 48b x 512 (synchronous read, 1-cycle latency); the
//    COMPUTE issue path waits 2 cycles (BMG read latency, see pipe_fill).
//  * scale = cv2-INTER_LINEAR bit-exact integer core; needs BOTH rows for
//    every output row (no wy==0 bypass), so need1 is constant 1.
//  * norm = FP32 i2f + mul official IPs (16-cycle latency), channels of a
//    pixel serialized into one shared stream (3 cycles/pixel issue
//    throughput); results return in order and are written into the write
//    module's rowbuf as they arrive.
//
// CSR map (byte addresses):
//   0x00 CTRL    [0] go (write 1; ignored while busy)
//   0x04 STATUS  [0] busy (ro), [1] irq (write-1-to-clear)
//   0x08 SRC_ADDR  source frame base in DDR (640x480x3 BGR uint8)
//   0x0C DST_ADDR  output blob base (1x3x320x320 fp32 CHW, 1,228,800 B)
//   0x10 VERSION   ro, 32'h0100_0001
//
// Frame protocol: PS writes SRC/DST, pulses go; DUT raises busy, processes
// one frame, raises irq and drops busy. Re-arm after irq (G3).
module t1_preproc_top (
  input  wire        clk,
  input  wire        rstn,
  // AXI4-Lite CSR slave
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
  // AXI4 read master
  output wire [31:0] m_axi_araddr,
  output wire [7:0]  m_axi_arlen,
  output wire [2:0]  m_axi_arsize,
  output wire [1:0]  m_axi_arburst,
  output wire        m_axi_arvalid,
  input  wire        m_axi_arready,
  input  wire [31:0] m_axi_rdata,
  input  wire [1:0]  m_axi_rresp,
  input wire         m_axi_rvalid,
  input  wire        m_axi_rlast,
  output wire        m_axi_rready,
  // AXI4 write master
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

  localparam ST_IDLE       = 3'd0,
             ST_REQ        = 3'd1,
             ST_FETCH_WAIT = 3'd2,
             ST_COMPUTE    = 3'd3,
             ST_WRITE_WAIT = 3'd5,
             ST_DONE       = 3'd6;

  // scheduler state (declared early: busy_r feeds the CSR block)
  reg [2:0] state;
  wire busy_r = (state != ST_IDLE);

  // ---------------- CSR ----------------
  reg [31:0] src_addr_r, dst_addr_r;
  reg        irq_r;
  reg        go_pulse, done_pulse;

  reg [1:0]  slv_state;
  reg [11:0] slv_waddr, slv_raddr;
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

  // single owner of irq_r / address regs / go pulse (multi-drive law)
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      slv_state  <= SLV_IDLE;
      slv_waddr  <= 12'd0;
      slv_raddr  <= 12'd0;
      bvalid_r   <= 1'b0;
      rvalid_r   <= 1'b0;
      rdata_r    <= 32'd0;
      src_addr_r <= 32'd0;
      dst_addr_r <= 32'd0;
      irq_r      <= 1'b0;
      go_pulse   <= 1'b0;
    end else begin
      go_pulse <= 1'b0;
      case (slv_state)
        SLV_IDLE: begin
          if (w_fire) begin
            slv_waddr <= s_axil_awaddr;
            case (s_axil_awaddr)
              12'h000: begin
                if (s_axil_wdata[0] && !busy_r)
                  go_pulse <= 1'b1;
              end
              12'h004: begin
                if (s_axil_wdata[1])
                  irq_r <= 1'b0;
              end
              12'h008: if (!busy_r) src_addr_r <= s_axil_wdata;
              12'h00C: if (!busy_r) dst_addr_r <= s_axil_wdata;
              default: ;
            endcase
            slv_state <= SLV_B;
          end else if (r_fire) begin
            slv_raddr <= s_axil_araddr;
            case (s_axil_araddr)
              12'h000, 12'h004: rdata_r <= {30'd0, irq_r, busy_r};
              12'h008:          rdata_r <= src_addr_r;
              12'h00C:          rdata_r <= dst_addr_r;
              12'h010:          rdata_r <= 32'h0100_0001;
              default:          rdata_r <= 32'd0;
            endcase
            rvalid_r  <= 1'b1;
            slv_state <= SLV_R;
          end
        end
        SLV_B: begin
          bvalid_r <= 1'b1;
          if (bvalid_r && s_axil_bready) begin
            bvalid_r  <= 1'b0;
            slv_state <= SLV_IDLE;
          end
        end
        SLV_R: begin
          if (rvalid_r && s_axil_rready) begin
            rvalid_r  <= 1'b0;
            slv_state <= SLV_IDLE;
          end
        end
        default: slv_state <= SLV_IDLE;
      endcase

      if (done_pulse)
        irq_r <= 1'b1;
    end
  end

  // ---------------- scheduler ----------------
  reg [8:0] y, x, r0;
  reg       ypar_r;
  reg [8:0] fc_row;
  reg [1:0] fc_slot;
  reg       slot_v0, slot_v1, slot_v2;
  reg [8:0] slot_row0, slot_row1, slot_row2;
  reg       wr_valid;
  reg [8:0] wr_y;

  wire [8:0] r0_c   = y + {1'b0, y[8:1]};          // (3*y)>>1
  // cv2-exact scale consumes BOTH window rows for every output row
  wire [8:0] r1_c   = r0_c + 9'd1;
  wire [3:0] r0m    = r0_c % 3;
  wire [3:0] r1m    = r1_c % 3;

  wire slot0_hit0 = slot_v0 && (slot_row0 == r0_c);
  wire slot1_hit0 = slot_v1 && (slot_row1 == r0_c);
  wire slot2_hit0 = slot_v2 && (slot_row2 == r0_c);
  wire hit0 = r0m == 4'd0 ? slot0_hit0 : r0m == 4'd1 ? slot1_hit0 : slot2_hit0;

  wire slot0_hit1 = slot_v0 && (slot_row0 == r1_c);
  wire slot1_hit1 = slot_v1 && (slot_row1 == r1_c);
  wire slot2_hit1 = slot_v2 && (slot_row2 == r1_c);
  wire hit1 = r1m == 4'd0 ? slot0_hit1 : r1m == 4'd1 ? slot1_hit1 : slot2_hit1;

  wire miss0 = !hit0;
  wire miss1 = !hit1;              // row1 always needed (cv2-exact scale)

  // linebuf read ports (address presented 1 cycle ahead, BMG sync read)
  wire [1:0]  cur_slot_a = r0 % 3;
  wire [1:0]  cur_slot_b = (r0 + 9'd1) % 3;
  wire [47:0] lb_rd_a, lb_rd_b;

  // scale
  wire [7:0] pix_b, pix_g, pix_r;

  // norm handshake
  wire        norm_in_ready;
  wire        norm_out_valid;
  wire [95:0] norm_out_data;

  // COMPUTE issue control: the BMG read pipeline latency is TWO cycles
  // (verified against the official sim model: addrb registered internally,
  // doutb valid 2 clocks after the address cycle), so the issue path waits
  // two cycles after entering COMPUTE before the first issue; mid-row the
  // address is stable 2+ cycles before every issue, so only the first
  // issue of a row needs the fill.
  reg [1:0]  pipe_fill;     // 0 -> 1 -> 2 saturated
  wire       pipe_filled = (pipe_fill == 2'd2);
  reg        issued_all;    // pixel 319 accepted by norm
  reg [8:0]  rx;            // result pixel counter (rowbuf fill)
  wire       cmp_issue = (state == ST_COMPUTE) && pipe_filled && !issued_all
                         && norm_in_ready;

  // rowbuf write (into write module)
  reg        rb_we;
  reg [8:0]  rb_addr;
  reg [95:0] rb_data;

  reg         fc_valid;
  wire        fc_ready, fc_done, wr_ready, wr_done;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state      <= ST_IDLE;
      y          <= 9'd0;
      x          <= 9'd0;
      r0         <= 9'd0;
      ypar_r     <= 1'b0;
      fc_valid   <= 1'b0;
      fc_row     <= 9'd0;
      fc_slot    <= 2'd0;
      slot_v0    <= 1'b0;
      slot_v1    <= 1'b0;
      slot_v2    <= 1'b0;
      slot_row0  <= 9'd0;
      slot_row1  <= 9'd0;
      slot_row2  <= 9'd0;
      wr_valid   <= 1'b0;
      wr_y       <= 9'd0;
      rb_we      <= 1'b0;
      rb_addr    <= 9'd0;
      rb_data    <= 96'd0;
      pipe_fill  <= 2'd0;
      issued_all <= 1'b0;
      rx         <= 9'd0;
      done_pulse <= 1'b0;
    end else begin
      rb_we      <= 1'b0;
      done_pulse <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (go_pulse) begin
            y         <= 9'd0;
            slot_v0   <= 1'b0;
            slot_v1   <= 1'b0;
            slot_v2   <= 1'b0;
            state     <= ST_REQ;
          end
        end

        ST_REQ: begin
          if (miss0) begin
            fc_valid <= 1'b1;
            fc_row   <= r0_c;
            fc_slot  <= r0m[1:0];
            state    <= ST_FETCH_WAIT;
          end else if (miss1) begin
            fc_valid <= 1'b1;
            fc_row   <= r1_c;
            fc_slot  <= r1m[1:0];
            state    <= ST_FETCH_WAIT;
          end else begin
            r0         <= r0_c;
            ypar_r     <= y[0];
            x          <= 9'd0;
            rx         <= 9'd0;
            pipe_fill  <= 2'd0;
            issued_all <= 1'b0;
            state      <= ST_COMPUTE;
          end
        end

        ST_FETCH_WAIT: begin
          if (fc_valid && fc_ready)
            fc_valid <= 1'b0;
          if (fc_done) begin
            case (fc_slot)
              2'd0: begin slot_v0 <= 1'b1; slot_row0 <= fc_row; end
              2'd1: begin slot_v1 <= 1'b1; slot_row1 <= fc_row; end
              default: begin slot_v2 <= 1'b1; slot_row2 <= fc_row; end
            endcase
            state <= ST_REQ;
          end
        end

        ST_COMPUTE: begin
          // 2-cycle BMG read pipeline fill
          if (pipe_fill != 2'd2)
            pipe_fill <= pipe_fill + 2'd1;

          // issue one pixel into the norm stream
          if (cmp_issue) begin
            if (x == 9'd319)
              issued_all <= 1'b1;
            else
              x <= x + 9'd1;
          end

          // collect norm results into the write rowbuf (in order)
          if (norm_out_valid) begin
            rb_we   <= 1'b1;
            rb_addr <= rx;
            rb_data <= norm_out_data;
            if (rx == 9'd319) begin
              wr_valid <= 1'b1;
              wr_y     <= y;
              state    <= ST_WRITE_WAIT;
            end else begin
              rx <= rx + 9'd1;
            end
          end
        end

        ST_WRITE_WAIT: begin
          if (wr_valid && wr_ready)
            wr_valid <= 1'b0;
          if (wr_done) begin
            if (y == 9'd319) begin
              state <= ST_DONE;
            end else begin
              y     <= y + 9'd1;
              state <= ST_REQ;
            end
          end
        end

        ST_DONE: begin
          done_pulse <= 1'b1;   // busy drops this edge; irq rises
          state      <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // fetch -> linebuf write wires (declared before use)
  wire        lb_wr_en;
  wire [1:0]  lb_wr_slot;
  wire [8:0]  lb_wr_pair;
  wire [47:0] lb_wr_data;

  // ---------------- submodules ----------------
  t1_preproc_fetch u_fetch (
    .clk           (clk),
    .rstn          (rstn),
    .src_base      (src_addr_r),
    .cmd_valid     (fc_valid),
    .cmd_row       (fc_row),
    .cmd_slot      (fc_slot),
    .cmd_ready     (fc_ready),
    .cmd_done      (fc_done),
    .lb_wr_en      (lb_wr_en),
    .lb_wr_slot    (lb_wr_slot),
    .lb_wr_pair    (lb_wr_pair),
    .lb_wr_data    (lb_wr_data),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rready  (m_axi_rready)
  );

  t1_preproc_linebuf u_linebuf (
    .clk         (clk),
    .wr_en       (lb_wr_en),
    .wr_slot     (lb_wr_slot),
    .wr_pair     (lb_wr_pair),
    .wr_data     (lb_wr_data),
    .rd_slot_a   (cur_slot_a),
    .rd_pair_a   (x),
    .rd_data_a   (lb_rd_a),
    .rd_slot_b   (cur_slot_b),
    .rd_pair_b   (x),
    .rd_data_b   (lb_rd_b)
  );

  t1_preproc_scale u_scale (
    .x          (x),
    .ypar       (ypar_r),
    .row0_word  (lb_rd_a),
    .row1_word  (lb_rd_b),
    .pix_b      (pix_b),
    .pix_g      (pix_g),
    .pix_r      (pix_r)
  );

  wire norm_in_valid = cmp_issue;
  t1_preproc_norm u_norm (
    .clk        (clk),
    .rstn       (rstn),
    .in_valid   (norm_in_valid),
    .in_ready   (norm_in_ready),
    .in_b       (pix_b),
    .in_g       (pix_g),
    .in_r       (pix_r),
    .out_valid  (norm_out_valid),
    .out_data   (norm_out_data)
  );

  t1_preproc_write u_write (
    .clk           (clk),
    .rstn          (rstn),
    .dst_base      (dst_addr_r),
    .rb_we         (rb_we),
    .rb_addr       (rb_addr),
    .rb_wdata      (rb_data),
    .cmd_valid     (wr_valid),
    .cmd_y         (wr_y),
    .cmd_ready     (wr_ready),
    .cmd_done      (wr_done),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

endmodule
