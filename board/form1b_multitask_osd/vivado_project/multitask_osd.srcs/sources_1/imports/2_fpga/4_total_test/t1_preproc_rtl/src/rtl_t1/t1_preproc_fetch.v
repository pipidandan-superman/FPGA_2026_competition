`timescale 1ns/1ps
// t1_preproc_fetch.v
// T1 AXI4 read master: fetches one 640x3B source row (480 x 32-bit beats)
// into a line-buffer slot. Bursts respect AXI4 rules: INCR burst, max 256
// beats (ARLEN is 8-bit), and no 4 KB boundary crossing (split).
// Beat-to-linebuf assembly: 3 beats (12 B) -> 2 linebuf words (2 col pairs),
// word layout per t1_preproc_linebuf.
module t1_preproc_fetch (
  input  wire        clk,
  input  wire        rstn,
  input  wire [31:0] src_base,
  // command: fetch row cmd_row into linebuf slot cmd_slot
  input  wire        cmd_valid,
  input  wire [8:0]  cmd_row,
  input  wire [1:0]  cmd_slot,
  output wire        cmd_ready,
  output reg         cmd_done,
  // linebuf write port
  output reg         lb_wr_en,
  output wire [1:0]  lb_wr_slot,
  output reg  [8:0]  lb_wr_pair,
  output reg  [47:0] lb_wr_data,
  // AXI4 read master
  output reg  [31:0] m_axi_araddr,
  output reg  [7:0]  m_axi_arlen,
  output wire [2:0]  m_axi_arsize,
  output wire [1:0]  m_axi_arburst,
  output reg         m_axi_arvalid,
  input  wire        m_axi_arready,
  input  wire [31:0] m_axi_rdata,
  input  wire [1:0]  m_axi_rresp,
  input  wire        m_axi_rvalid,
  input  wire        m_axi_rlast,
  output wire        m_axi_rready
);

  localparam [9:0] ROW_BEATS = 480;    // 640*3/4
  localparam       ROW_BYTES = 1920;

  localparam ST_IDLE = 3'd0,
             ST_AR   = 3'd1,
             ST_RCV  = 3'd2,
             ST_DONE = 3'd3;

  reg [2:0]  state;
  reg [8:0]  rem_beats;                // beats left for this row (<=480)
  reg [31:0] cur_addr;
  reg [8:0]  burst_beats;              // beats in current burst
  reg [8:0]  rcv_cnt;                  // beats received in current burst
  reg [1:0]  asm_cnt;                  // 0/1/2 assembly phase (continuous per row)
  reg [8:0]  pair_cnt;                 // 0..319 col pair counter
  reg [31:0] beat_hold;                // previous beat data
  reg [15:0] hold_hi;                  // upper half of middle beat
  reg [1:0]  slot_r;

  assign m_axi_arsize  = 3'b010;       // 4 bytes
  assign m_axi_arburst = 2'b01;        // INCR
  assign m_axi_rready  = (state == ST_RCV);
  assign cmd_ready     = (state == ST_IDLE);
  assign lb_wr_slot    = slot_r;

  // beats allowed before hitting a 4 KB boundary from cur_addr (1..1024)
  wire [10:0] b4k = 11'd1024 - {1'b0, cur_addr[11:2]};

  // burst length = min(rem_beats, 256, b4k). Never truncate b4k to 8/9
  // bits: a 4 KB-aligned address yields b4k==1024 whose truncation would
  // zero the burst length (hang). lim <= 256, so when b4k < lim then
  // b4k < 256 and b4k[8:0] is exact.
  wire [10:0] lim = (rem_beats > 9'd256) ? 11'd256 : {2'b00, rem_beats};
  wire [8:0] burst_len = (lim > b4k) ? b4k[8:0] : lim[8:0];

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state        <= ST_IDLE;
      cmd_done     <= 1'b0;
      lb_wr_en     <= 1'b0;
      lb_wr_pair   <= 9'd0;
      lb_wr_data   <= 48'd0;
      m_axi_arvalid <= 1'b0;
      m_axi_araddr <= 32'd0;
      m_axi_arlen  <= 8'd0;
      rem_beats    <= 9'd0;
      cur_addr     <= 32'd0;
      burst_beats  <= 9'd0;
      rcv_cnt      <= 9'd0;
      asm_cnt      <= 2'd0;
      pair_cnt     <= 9'd0;
      beat_hold    <= 32'd0;
      hold_hi      <= 16'd0;
      slot_r       <= 2'd0;
    end else begin
      cmd_done   <= 1'b0;
      lb_wr_en   <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (cmd_valid) begin
            rem_beats <= ROW_BEATS[8:0];
            cur_addr  <= src_base + cmd_row * ROW_BYTES;
            slot_r    <= cmd_slot;
            asm_cnt   <= 2'd0;
            pair_cnt  <= 9'd0;
            state     <= ST_AR;
          end
        end

        ST_AR: begin
          m_axi_arvalid <= 1'b1;
          m_axi_araddr  <= cur_addr;
          m_axi_arlen   <= burst_len[7:0] - 8'd1;
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            burst_beats   <= burst_len;
            rcv_cnt       <= 9'd0;
            rem_beats     <= rem_beats - burst_len;
            cur_addr      <= cur_addr + {burst_len, 2'b00};
            state         <= ST_RCV;
          end
        end

        ST_RCV: begin
          if (m_axi_rvalid) begin
            rcv_cnt <= rcv_cnt + 9'd1;
            case (asm_cnt)
              2'd0: beat_hold <= m_axi_rdata;
              2'd1: begin
                // word0 bytes = {b4,b5,b0,b1,b2,b3} LSB..MSB
                //             = {beat1[15:0], beat0}
                lb_wr_en   <= 1'b1;
                lb_wr_pair <= {pair_cnt[7:0], 1'b0};
                lb_wr_data <= {m_axi_rdata[15:0], beat_hold};
                hold_hi    <= m_axi_rdata[31:16];
              end
              default: begin
                // word1 bytes = {b6,b7,b8,b9,b10,b11}
                //             = {beat1[31:16], beat2} -> {beat2, hold_hi}
                lb_wr_en   <= 1'b1;
                lb_wr_pair <= {pair_cnt[7:0], 1'b0} + 9'd1;
                lb_wr_data <= {m_axi_rdata, hold_hi};
                pair_cnt   <= pair_cnt + 9'd1;
              end
            endcase
            asm_cnt <= (asm_cnt == 2'd2) ? 2'd0 : asm_cnt + 2'd1;
            if (m_axi_rlast) begin
              if (rem_beats == 9'd0)
                state <= ST_DONE;
              else
                state <= ST_AR;
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
