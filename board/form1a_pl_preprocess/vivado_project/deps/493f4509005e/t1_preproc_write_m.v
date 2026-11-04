`timescale 1ns/1ps
// t1_preproc_write_m.v -- M-contract u8 HWC blob writer.
// (2026-10-22_t1_letterbox_bit_run02)
//
// Consumes the letterbox_scale pixel stream ({R,G,B}, [23:16]=R), packs
// 3 bytes/px into 32-bit AXI words, and writes one 960-byte output row
// (320 px x 3 B) per command. Full blob = 320 rows x 960 B = 307200 B
// RGB HWC u8, little-endian (byte0=R). Pad rows take no pixel stream: the
// writer emits constant 32'h72727272 (gray114 per channel).
//
// Row storage: one 32b x 256 register file with ASYNC read (sim and synth
// identical: distributed RAM, ~1 KB -- deliberately not a sync-read BRAM,
// which would need a second pipeline stage in ST_W). The px stream fills
// it (a row needs exactly 240 words from 320 px; write port is free by
// ST_AW time). Bulletproof because the scheduler only issues the next row
// command after cmd_done.
//
// Burst engine: skeleton inherited from board-proven t1_preproc_write
// (AW/W/B sequential per burst, awsize=2 INCR, 4 KB-boundary split).
module t1_preproc_write_m (
  input  wire        clk,
  input  wire        rstn,
  input  wire [31:0] dst_base,
  // pixel stream (1 px/cycle, no backpressure; consumed only in ST_FILL)
  input  wire        px_we,
  input  wire [23:0] px_data,      // {R,G,B}
  // row command
  input  wire        cmd_valid,
  input  wire [8:0]  cmd_y,        // output row 0..319
  input  wire        cmd_pad,      // 1 = gray114 pad row (ignore px stream)
  output wire        cmd_ready,
  output reg         cmd_done,
  // AXI4 write master
  output reg  [31:0] m_axi_awaddr,
  output reg  [7:0]  m_axi_awlen,
  output wire [2:0]  m_axi_awsize,
  output wire [1:0]  m_axi_awburst,
  output reg         m_axi_awvalid,
  input  wire        m_axi_awready,
  output wire [31:0] m_axi_wdata,   // comb from row_ram (async read):
  output wire [3:0]  m_axi_wstrb,   // registering it would lag ram_raddr
  output reg         m_axi_wvalid,  // by one cycle and duplicate/skip beats
  input  wire        m_axi_wready,
  output wire        m_axi_wlast,
  input  wire [1:0]  m_axi_bresp,
  input  wire        m_axi_bvalid,
  output wire        m_axi_bready
);

  localparam integer ROW_WORDS = 240;            // 960 B / 4
  localparam [31:0]  GRAY_WORD = 32'h72727272;   // gray114 per byte

  localparam ST_IDLE = 3'd0, ST_FILL = 3'd1, ST_AW = 3'd2,
             ST_W = 3'd3, ST_B = 3'd4;

  reg [2:0]  state;
  reg [8:0]  px_cnt;               // 0..319
  reg        pad_r;
  reg [31:0] row_addr;             // byte address of next burst segment
  reg [8:0]  rem_beats;            // beats left in this row (<=240)
  reg [8:0]  burst_len;            // beats in current burst
  reg [8:0]  beat_cnt;             // beats sent in current burst

  // ---------------- row storage (async read: sim == synth) --------------
  reg [31:0] row_ram [0:255];
  reg [7:0]  ram_waddr;
  reg [7:0]  ram_raddr;
  wire [31:0] ram_dout = row_ram[ram_raddr];

  assign cmd_ready     = (state == ST_IDLE);
  assign m_axi_awsize  = 3'b010;   // 4 bytes
  assign m_axi_awburst = 2'b01;    // INCR
  assign m_axi_wstrb   = 4'hF;
  assign m_axi_bready  = (state == ST_B);
  assign m_axi_wdata   = pad_r ? GRAY_WORD : ram_dout;
  // board wedge root-cause experiment (10-22): the OLD board-proven writer
  // asserts WVALID in the SAME cycle as the AW accept and drives WLAST
  // combinationally. The converter (TRANSLATION_MODE=2) appears sensitive
  // to the 1-cycle-later registered style (first write burst deadlocked:
  // B held high, W never accepted, address-independent). Replicate the
  // proven handshake exactly.
  assign m_axi_wlast   = m_axi_wvalid && (beat_cnt == burst_len - 9'd1);

  // cmd_y*960 = y*(512+256+128+64)
  wire [31:0] y_off = {14'd0, cmd_y, 9'd0} + {23'd0, cmd_y, 8'd0}
                    + {24'd0, cmd_y, 7'd0} + {25'd0, cmd_y, 6'd0};
  wire cmd_acc = (state == ST_IDLE) && cmd_valid;

  // beats allowed before hitting a 4 KB boundary from row_addr (1..1024)
  wire [10:0] b4k = 11'd1024 - {1'b0, row_addr[11:2]};
  wire [8:0]  blen_raw = (rem_beats > b4k) ? b4k[8:0] : rem_beats;
  // AXI3 burst cap: the preproc AXI4 master sits behind the interconnect's
  // axi4->axi3 auto_pc, whose WRITE side has NO burst splitter (only the
  // read side does, USE_SPLIT_R). AXI3 AWLEN must be <= 15 (16 beats);
  // the 240-beat row burst deadlocked the converter on the board (first
  // pad row, busy stuck, 10-22). Split every burst to <= 16 beats.
  wire [8:0]  blen = (blen_raw > 9'd16) ? 9'd16 : blen_raw;

  // ---------------- pixel packer: 3 B/px -> 4 B words --------------------
  // DDR byte stream per px: R,G,B; word n covers bytes[4n+3..4n],
  // wdata[7:0] = byte[4n] (lowest address). byte_pos = bytes held in cur
  // (low bytes). Position cycle per px: 0->3->2->1->0, one word emitted
  // at positions 3/2/1 (240 words per 320 px). 960 % 4 == 0: byte_pos
  // returns to 0 exactly at row end.
  reg [31:0] cur;
  reg [1:0]  byte_pos;
  reg        wr_word;              // pulse: row_ram[ram_waddr] <= wr_data
  reg [31:0] wr_data;

  wire [7:0] pxR = px_data[23:16];
  wire [7:0] pxG = px_data[15:8];
  wire [7:0] pxB = px_data[7:0];

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      cur <= 32'd0; byte_pos <= 2'd0; wr_word <= 1'b0; wr_data <= 32'd0;
    end else begin
      wr_word <= 1'b0;
      if (cmd_acc) begin
        byte_pos <= 2'd0;          // new row: packer starts aligned
      end else if (px_we && state == ST_FILL && !pad_r) begin
        case (byte_pos)
          2'd0: begin
            cur[7:0]   <= pxR; cur[15:8] <= pxG; cur[23:16] <= pxB;
            byte_pos   <= 2'd3;
          end
          2'd3: begin
            // word = {px.R @3, B@2, G@1, R@0}; leftover G,B -> next word
            wr_data  <= {pxR, cur[23:0]};
            wr_word  <= 1'b1;
            cur[7:0] <= pxG; cur[15:8] <= pxB; cur[23:16] <= 8'd0;
            byte_pos <= 2'd2;
          end
          2'd2: begin
            // word = {px.G @3, px.R @2, B@1, R@0}; leftover B -> next word
            wr_data  <= {pxG, pxR, cur[15:0]};
            wr_word  <= 1'b1;
            cur[7:0] <= pxB; cur[23:16] <= 8'd0;
            byte_pos <= 2'd1;
          end
          default: begin
            // word = {px.B @3, G@2, R@1, cur[7:0] @0}; nothing left over
            wr_data  <= {pxB, pxG, pxR, cur[7:0]};
            wr_word  <= 1'b1;
            cur      <= 32'd0;
            byte_pos <= 2'd0;
          end
        endcase
      end
    end
  end

  always @(posedge clk) begin
    if (wr_word) row_ram[ram_waddr] <= wr_data;
  end

  // ---------------- main FSM --------------------------------------------
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state <= ST_IDLE; px_cnt <= 9'd0; pad_r <= 1'b0;
      row_addr <= 32'd0; rem_beats <= 9'd0; burst_len <= 9'd0;
      beat_cnt <= 9'd0;
      ram_waddr <= 8'd0; ram_raddr <= 8'd0;
      cmd_done <= 1'b0;
      m_axi_awaddr <= 32'd0; m_axi_awlen <= 8'd0; m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
    end else begin
      cmd_done <= 1'b0;
      case (state)
        ST_IDLE: begin
          if (cmd_valid) begin
            pad_r     <= cmd_pad;
            row_addr  <= dst_base + y_off;
            rem_beats <= ROW_WORDS[8:0];
            ram_waddr <= 8'd0;
            ram_raddr <= 8'd0;
            px_cnt    <= 9'd0;
            state     <= cmd_pad ? ST_AW : ST_FILL;
          end
        end

        ST_FILL: begin
          if (px_we) begin
            px_cnt <= px_cnt + 1;
            if (px_cnt == 9'd319) state <= ST_AW;
          end
          // bump the write pointer on every emitted word -- wr_word is a
          // registered packer output (one cycle after its px), so gating
          // on px_we here would never fire and every word would land at
          // address 0. The final word is emitted during ST_AW; the extra
          // bump is harmless (pointer resets at the next command accept).
          if (wr_word) ram_waddr <= ram_waddr + 8'd1;
        end

        ST_AW: begin
          m_axi_awvalid <= 1'b1;
          m_axi_awaddr  <= row_addr;
          m_axi_awlen   <= blen[7:0] - 8'd1;
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b1;         // board-proven style: WVALID with
            burst_len     <= blen;         // the AW accept, first beat next
            beat_cnt      <= 9'd0;         // cycle (converter W-pacing quirk)
            rem_beats     <= rem_beats - blen;
            row_addr      <= row_addr + {blen, 2'b00};
            state         <= ST_W;
          end
        end

        ST_W: begin
          if (m_axi_wvalid && m_axi_wready) begin
            beat_cnt  <= beat_cnt + 9'd1;
            ram_raddr <= ram_raddr + 8'd1;
            if (m_axi_wlast) begin
              m_axi_wvalid <= 1'b0;
              state        <= ST_B;
            end
          end
        end

        ST_B: begin
          if (m_axi_bvalid) begin
            if (rem_beats != 9'd0) state <= ST_AW;  // ram_raddr continues
            else begin
              cmd_done <= 1'b1;
              state    <= ST_IDLE;
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
