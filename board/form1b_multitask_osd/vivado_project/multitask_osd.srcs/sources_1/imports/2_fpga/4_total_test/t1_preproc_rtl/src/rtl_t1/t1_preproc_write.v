`timescale 1ns/1ps
// t1_preproc_write.v
// T1 AXI4 write master + output row aggregation buffer.
// For one output row the top pushes 320 x 96 bit entries ({fp32 R? no:
// {fr, fg, fb}} per pixel); this module then writes three 320-beat bursts
// (one per channel plane) to dst + c*409600 + y*1280 -- CHW layout of the
// 1x3x320x320 fp32 blob. Bursts are INCR, <= 256 beats, 4 KB-safe splits.
module t1_preproc_write (
  input  wire        clk,
  input  wire        rstn,
  input  wire [31:0] dst_base,
  // row aggregation buffer write port (from top, one entry per output pixel)
  input  wire        rb_we,
  input  wire [8:0]  rb_addr,
  input  wire [95:0] rb_wdata,
  // command: write output row cmd_y
  input  wire        cmd_valid,
  input  wire [8:0]  cmd_y,
  output wire        cmd_ready,
  output reg         cmd_done,
  // AXI4 write master
  output reg  [31:0] m_axi_awaddr,
  output reg  [7:0]  m_axi_awlen,
  output wire [2:0]  m_axi_awsize,
  output wire [1:0]  m_axi_awburst,
  output reg         m_axi_awvalid,
  input  wire        m_axi_awready,
  output wire [31:0] m_axi_wdata,
  output wire [3:0]  m_axi_wstrb,
  output reg         m_axi_wvalid,
  input  wire        m_axi_wready,
  output wire        m_axi_wlast,
  input  wire [1:0]  m_axi_bresp,
  input  wire        m_axi_bvalid,
  output wire        m_axi_bready
);

  localparam [9:0] ROW_BEATS  = 320;          // beats per channel burst
  localparam       PLANE_BYTES = 409600;      // 320*320*4
  localparam       ROW_BYTES   = 1280;        // 320*4

  localparam ST_IDLE = 3'd0,
             ST_AW   = 3'd1,
             ST_W    = 3'd2,
             ST_B    = 3'd3,
             ST_DONE = 3'd4;

  reg [95:0] rb [0:319];

  reg [2:0]  state;
  reg [1:0]  ch;                 // channel plane 0..2
  reg [8:0]  rem_beats;          // beats left for this plane row
  reg [31:0] cur_addr;
  reg [8:0]  burst_beats;
  reg [8:0]  wcnt;               // beats sent in current burst
  reg [8:0]  rd_idx;             // rowbuf read index for current burst
  // combinational read of the aggregation buffer (a clocked blocking
  // assignment here would load one beat late and shift the whole burst)
  wire [95:0] rb_rd = rb[rd_idx];

  assign m_axi_awsize  = 3'b010;
  assign m_axi_awburst = 2'b01;
  assign m_axi_wstrb   = 4'b1111;
  assign m_axi_bready  = (state == ST_B);
  assign cmd_ready     = (state == ST_IDLE);
  assign m_axi_wlast   = m_axi_wvalid && (wcnt == burst_beats - 9'd1);
  assign m_axi_wdata   = (ch == 2'd0) ? rb_rd[31:0] :
                         (ch == 2'd1) ? rb_rd[63:32] : rb_rd[95:64];

  // dst + ch*409600 + y*1280
  wire [31:0] plane_addr = dst_base + ch * PLANE_BYTES + cmd_y * ROW_BYTES;
  wire [31:0] next_plane_addr = dst_base + (ch + 2'd1) * PLANE_BYTES
                                + cmd_y * ROW_BYTES;

  wire [10:0] b4k = 11'd1024 - {1'b0, cur_addr[11:2]};

  // burst length = min(rem_beats, 256, b4k); see fetch for the truncation
  // pitfall (b4k==1024 at 4 KB-aligned addresses)
  wire [10:0] wlim = (rem_beats > 9'd256) ? 11'd256 : {2'b00, rem_beats};
  wire [8:0] burst_len = (wlim > b4k) ? b4k[8:0] : wlim[8:0];

  always @(posedge clk) begin
    if (rb_we)
      rb[rb_addr] <= rb_wdata;
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state         <= ST_IDLE;
      cmd_done      <= 1'b0;
      ch            <= 2'd0;
      rem_beats     <= 9'd0;
      cur_addr      <= 32'd0;
      burst_beats   <= 9'd0;
      wcnt          <= 9'd0;
      rd_idx        <= 9'd0;
      m_axi_awvalid <= 1'b0;
      m_axi_awaddr  <= 32'd0;
      m_axi_awlen   <= 8'd0;
      m_axi_wvalid  <= 1'b0;
    end else begin
      cmd_done <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (cmd_valid) begin
            ch        <= 2'd0;
            rem_beats <= ROW_BEATS[8:0];
            cur_addr  <= dst_base + cmd_y * ROW_BYTES;  // ch==0 plane
            state     <= ST_AW;
          end
        end

        ST_AW: begin
          m_axi_awvalid <= 1'b1;
          m_axi_awaddr  <= cur_addr;
          m_axi_awlen   <= burst_len[7:0] - 8'd1;
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            burst_beats   <= burst_len;
            wcnt          <= 9'd0;
            rd_idx        <= ROW_BEATS[8:0] - rem_beats;  // start index
            rem_beats     <= rem_beats - burst_len;
            cur_addr      <= cur_addr + {burst_len, 2'b00};
            m_axi_wvalid  <= 1'b1;
            state         <= ST_W;
          end
        end

        ST_W: begin
          if (m_axi_wvalid && m_axi_wready) begin
            wcnt   <= wcnt + 9'd1;
            rd_idx <= rd_idx + 9'd1;
            if (wcnt == burst_beats - 9'd1) begin
              m_axi_wvalid <= 1'b0;
              state        <= ST_B;
            end
          end
        end

        ST_B: begin
          if (m_axi_bvalid) begin
            if (rem_beats == 9'd0) begin
              if (ch == 2'd2) begin
                state <= ST_DONE;
              end else begin
                ch        <= ch + 2'd1;
                rem_beats <= ROW_BEATS[8:0];
                cur_addr  <= next_plane_addr;
                state     <= ST_AW;
              end
            end else begin
              state <= ST_AW;
            end
          end
        end

        ST_DONE: begin
          cmd_done <= 1'b1;
          state    <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
