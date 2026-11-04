`timescale 1ns/1ps
//====================================================================
// File name   : t1_label_osd.v
// Author      : Claude Code
// Create date : 2026-10-21
// Description : Fixed-bitmap label + score OSD for the T1 HDMI chain
//               (user-directed architecture, replaces the general text
//               engine t1_text_gen + t1_osd_mux).  Same interaction
//               pattern as pix_frame_display (GBOX): the PS writes
//               parameter registers over AXI-Lite, the PL re-rasters
//               the bitmap EVERY FRAME -> absolutely stable, zero
//               writes into the display ring (genlock-freeze-proof).
//
//               One single ROM (4096 x 32b, 4x RAMB36 EXACTLY -- BRAM-min
//               per user directive) holds:
//                 entries 1..24  160 words  "NET:Gesture" bitmaps
//                            (3 nets x 8 states: 7 gestures + None)
//                 entries 25..34  16 words  digits '0'..'9', TWO glyph
//                            rows packed per 32-bit word (16px glyph in
//                            each half; row-pair packing keeps the whole
//                            ROM inside one 4K-deep BRAM column)
//               Register map (32-bit words, AXI-Lite):
//                 0x00 ID     RO 0x544C424C "TLBL"
//                 0x08 CODE   RW [4:0]=label code 0..24 (0=hide strip)
//                                 [8:5]=score digit 0..9 (0=hide digit)
//                 0x0C X      RW [9:0] strip left column (default 440)
//                 0x10 Y      RW [9:0] strip top row    (default 16)
//                 0x14 FG     RW [23:0] foreground (glyph) color
//                 0x18 BG     RW [23:0] background (plate)  color
//               (No ROMIDX readback port: the diagnostic second read
//               port made 2025.2 DUPLICATE the ROM -- 2x8192x32 = 16
//               RAMB36 instead of 4.  Silicon ROM content is verified
//               through the xsim G1b mirror + the visible strip instead.)
//               Strip geometry (one contiguous 184x32 box, top-right):
//                 [  label 160px  | 8px gap | digit 16px ]
//                 bit=1 -> FG, bit=0 -> BG (opaque plate); outside ->
//                 video passthrough.
//               Per-pixel raster lookup (NOT a burst fetch): the ROM
//               address is combinational from (h_cnt,v_cnt) each pixel,
//               BRAM read is 1 cycle, the whole pixel path is padded to
//               2 register stages so ROM bit / video / DE-HS-VS stay in
//               lockstep (label field and digit field are adjacent
//               address segments read on the same scan lines, us apart).
//               Sync polarity: consumes GBOX's REGISTERED outputs whose
//               hsync/vsync are INVERTED (idle high, one-cycle LOW pulse
//               at line/frame start) -> counters reset on the LOW pulse
//               (2026-10-20 silicon lesson; TB stimulus models this).
//               Params shadow-latch at pixel (0,0) of each frame (no
//               tearing); CDC = 2-FF per field, pix_frame_display V2.0
//               proven pattern.
// Target      : Xilinx Zynq-7020
//====================================================================
module t1_label_osd #(
    parameter H_SIZE      = 640,
    parameter V_SIZE      = 480,
    parameter LABEL_W     = 160,    // 10 chars x 16 px
    parameter GAP         = 8,      // px between label and digit
    parameter DIGIT_W     = 16,     // px
    parameter ROW_WORDS   = 5,      // LABEL_W / 32
    parameter LABEL_WORDS = 160,    // 32 rows x ROW_WORDS
    parameter DIGIT_WORDS = 16,     // 32 rows packed 2-per-word
    parameter DIGIT_BASE  = 3840,   // word offset of digit entries
    parameter ROM_WORDS   = 4096
)(
    input  wire        vio_clk    ,
    input  wire        sys_rst_n  ,
    input  wire        vio_active ,
    input  wire        vio_hsync  ,
    input  wire        vio_vsync  ,
    input  wire [23:0] vio_data   ,
    output reg  [23:0] hdmi_data  ,
    output reg         hdmi_de    ,
    output reg         hdmi_hsync ,
    output reg         hdmi_vsync ,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET resetn, FREQ_HZ 50000000" *)
    input  wire        aclk       ,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        aresetn    ,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 50000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, HAS_QOS 0, HAS_PROT 1, HAS_WSTRB 1, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [11:0] s_axi_awaddr  ,
    input  wire [2:0]  s_axi_awprot  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire [3:0]  s_axi_wstrb   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [11:0] s_axi_araddr  ,
    input  wire [2:0]  s_axi_arprot  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready
);

    localparam [1:0] RESP_OKAY   = 2'd0,
                     RESP_SLVERR = 2'd2;

    // AXI-Lite internal channel (protocol shell instance)
    wire        wr_valid;
    wire [11:0] wr_addr;
    wire [31:0] wr_data;
    wire [3:0]  wr_strb;
    wire        wr_rsp_ready;
    wire        rd_valid;
    wire [11:0] rd_addr;
    wire        rd_rsp_ready;
    reg         wr_ready;
    reg         wr_rsp_valid;
    reg  [1:0]  wr_rsp;
    reg         rd_ready;
    reg         rd_rsp_valid;
    reg  [31:0] rd_data;
    reg  [1:0]  rd_rsp;

    axi_lite_slave u_shell (
        .clk            (aclk          ),
        .resetn         (aresetn       ),
        .s_axi_awaddr   (s_axi_awaddr  ),
        .s_axi_awvalid  (s_axi_awvalid ),
        .s_axi_awready  (s_axi_awready ),
        .s_axi_wdata    (s_axi_wdata   ),
        .s_axi_wstrb    (s_axi_wstrb   ),
        .s_axi_wvalid   (s_axi_wvalid  ),
        .s_axi_wready   (s_axi_wready  ),
        .s_axi_bresp    (s_axi_bresp   ),
        .s_axi_bvalid   (s_axi_bvalid  ),
        .s_axi_bready   (s_axi_bready  ),
        .s_axi_araddr   (s_axi_araddr  ),
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  ),
        .wr_valid       (wr_valid      ),
        .wr_ready       (wr_ready      ),
        .wr_addr        (wr_addr       ),
        .wr_data        (wr_data       ),
        .wr_strb        (wr_strb       ),
        .wr_rsp_valid   (wr_rsp_valid  ),
        .wr_rsp_ready   (wr_rsp_ready  ),
        .wr_rsp         (wr_rsp        ),
        .rd_valid       (rd_valid      ),
        .rd_ready       (rd_ready      ),
        .rd_addr        (rd_addr       ),
        .rd_rsp_valid   (rd_rsp_valid  ),
        .rd_rsp_ready   (rd_rsp_ready  ),
        .rd_data        (rd_data       ),
        .rd_rsp         (rd_rsp        )
    );

    // ---------------------------------------------------------------
    // Register bank (aclk domain)
    // ---------------------------------------------------------------
    reg  [4:0] label_reg;       // 0..24 (0 = hide whole strip)
    reg  [3:0] digit_reg;       // 0..9  (0 = hide digit)
    reg  [9:0] x_reg, y_reg;
    reg [23:0] fg_reg, bg_reg;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ready     <= 1'b0;
            wr_rsp_valid <= 1'b0;
            wr_rsp       <= RESP_OKAY;
            label_reg    <= 5'd0;
            digit_reg    <= 4'd0;
            x_reg        <= 10'd440;
            y_reg        <= 10'd16;
            fg_reg       <= 24'h00FF00;
            bg_reg       <= 24'h000000;
        end else begin
            if (!wr_rsp_valid)
                wr_ready <= 1'b1;
            if (wr_rsp_valid && wr_rsp_ready) begin
                wr_rsp_valid <= 1'b0;
                wr_ready     <= 1'b1;
            end
            if (wr_valid && wr_ready) begin
                wr_ready     <= 1'b0;
                wr_rsp_valid <= 1'b1;
                wr_rsp       <= RESP_OKAY;
                if (wr_addr[11:8] == 4'h0) begin
                    case (wr_addr[7:0])
                        8'h08: if (wr_strb[0]) begin
                                   label_reg <= wr_data[4:0];
                                   digit_reg <= wr_data[8:5];
                               end
                        8'h0c: if (wr_strb[0]) x_reg     <= wr_data[9:0];
                        8'h10: if (wr_strb[0]) y_reg     <= wr_data[9:0];
                        8'h14: begin
                                   if (wr_strb[0]) fg_reg[ 7: 0] <= wr_data[ 7: 0];
                                   if (wr_strb[1]) fg_reg[15: 8] <= wr_data[15: 8];
                                   if (wr_strb[2]) fg_reg[23:16] <= wr_data[23:16];
                               end
                        8'h18: begin
                                   if (wr_strb[0]) bg_reg[ 7: 0] <= wr_data[ 7: 0];
                                   if (wr_strb[1]) bg_reg[15: 8] <= wr_data[15: 8];
                                   if (wr_strb[2]) bg_reg[23:16] <= wr_data[23:16];
                               end
                        default: wr_rsp <= RESP_SLVERR;
                    endcase
                end else begin
                    wr_rsp <= RESP_SLVERR;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // AXI-Lite read process
    // ---------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rd_ready     <= 1'b0;
            rd_rsp_valid <= 1'b0;
            rd_data      <= 32'd0;
            rd_rsp       <= RESP_OKAY;
        end else begin
            if (!rd_rsp_valid)
                rd_ready <= 1'b1;
            if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 1'b0;
                rd_ready     <= 1'b1;
            end
            if (rd_valid && rd_ready) begin
                rd_ready     <= 1'b0;
                rd_rsp_valid <= 1'b1;
                rd_rsp       <= RESP_OKAY;
                if (rd_addr[11:8] == 4'h0) begin
                    case (rd_addr[7:0])
                        8'h00: rd_data <= 32'h544C424C;              // "TLBL"
                        8'h08: rd_data <= {18'd0, digit_reg, label_reg};
                        8'h0c: rd_data <= {22'd0, x_reg};
                        8'h10: rd_data <= {22'd0, y_reg};
                        8'h14: rd_data <= {8'd0, fg_reg};
                        8'h18: rd_data <= {8'd0, bg_reg};
                        default: begin
                            rd_data <= 32'd0;
                            rd_rsp  <= RESP_SLVERR;
                        end
                    endcase
                end else begin
                    rd_data      <= 32'd0;
                    rd_rsp       <= RESP_SLVERR;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // CDC aclk -> vio_clk: 2-FF per field
    // ---------------------------------------------------------------
    reg  [4:0] label_s0, label_s1;
    reg  [3:0] digit_s0, digit_s1;
    reg  [9:0] x_s0, x_s1, y_s0, y_s1;
    reg [23:0] fg_s0, fg_s1, bg_s0, bg_s1;

    always @(posedge vio_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            {label_s0, label_s1} <= 10'd0;
            {digit_s0, digit_s1} <= 8'd0;
            {x_s0, x_s1} <= 20'd0;
            {y_s0, y_s1} <= 20'd0;
            {fg_s0, fg_s1} <= 48'd0;
            {bg_s0, bg_s1} <= 48'd0;
        end else begin
            label_s0 <= label_reg;  label_s1 <= label_s0;
            digit_s0 <= digit_reg;  digit_s1 <= digit_s0;
            x_s0 <= x_reg;  x_s1 <= x_s0;
            y_s0 <= y_reg;  y_s1 <= y_s0;
            fg_s0 <= fg_reg;  fg_s1 <= fg_s0;
            bg_s0 <= bg_reg;  bg_s1 <= bg_s0;
        end
    end

    // ---------------------------------------------------------------
    // Pixel domain: reset sync
    // ---------------------------------------------------------------
    reg rst_n0, rst_sync;

    always @(posedge vio_clk or negedge sys_rst_n)
        if (!sys_rst_n) begin
            rst_n0   <= 0;
            rst_sync <= 0;
        end else begin
            rst_n0   <= 1;
            rst_sync <= rst_n0;
        end

    // NOTE on sync polarity: this module consumes pix_frame_display's
    // REGISTERED outputs, and GBOX drives hdmi_hsync/vsync INVERTED
    // (<= ~vio_hsync, mostly-high with a one-cycle LOW pulse at line/
    // frame start).  Counters therefore reset on the LOW pulse --
    // resetting on vio_hsync==1 would freeze h_cnt at 0 forever
    // (2026-10-20 silicon bug: sim TB modeled active-HIGH pulses so the
    // bug passed xsim and killed all text on the board).
    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge vio_clk or negedge rst_sync)
        if (!rst_sync)
            h_cnt <= 0;
        else if (!vio_hsync)
            h_cnt <= 0;
        else if (vio_active) begin
            if (h_cnt >= H_SIZE-1)
                h_cnt <= 0;
            else
                h_cnt <= h_cnt + 1;
        end else
            h_cnt <= 0;

    always @(posedge vio_clk or negedge rst_sync)
        if (!rst_sync)
            v_cnt <= 0;
        else if (!vio_vsync)
            v_cnt <= 0;
        else if (h_cnt == H_SIZE-1 && vio_active == 1'b1) begin
            if (v_cnt >= V_SIZE-1)
                v_cnt <= 0;
            else
                v_cnt <= v_cnt + 1;
        end

    // ---------------------------------------------------------------
    // Frame-boundary shadow latch: whole drawing state at pixel (0,0)
    // ---------------------------------------------------------------
    reg  [4:0] draw_label;
    reg  [3:0] draw_digit;
    reg  [9:0] draw_x, draw_y;
    reg [23:0] draw_fg, draw_bg;

    always @(posedge vio_clk or negedge rst_sync)
        if (!rst_sync) begin
            draw_label <= 5'd0;
            draw_digit <= 4'd0;
            draw_x     <= 10'd440;
            draw_y     <= 10'd16;
            draw_fg    <= 24'h00FF00;
            draw_bg    <= 24'h000000;
        end else if (vio_active && (h_cnt == 10'd0) && (v_cnt == 10'd0)) begin
            draw_label <= label_s1;
            draw_digit <= digit_s1;
            draw_x     <= x_s1;
            draw_y     <= y_s1;
            draw_fg    <= fg_s1;
            draw_bg    <= bg_s1;
        end

    // ---------------------------------------------------------------
    // Per-pixel geometry + ROM address (combinational, pixel N)
    // ---------------------------------------------------------------
    localparam [9:0] STRIP_W = LABEL_W + GAP + DIGIT_W;   // 184

    wire        label_valid = (draw_label != 5'd0);
    wire        digit_valid = label_valid && (draw_digit != 4'd0);
    wire [9:0]  dx0 = h_cnt - draw_x;                     // label rel x
    wire [9:0]  dy0 = v_cnt - draw_y;                     // strip  rel y
    wire [9:0]  dx1 = h_cnt - (draw_x + LABEL_W + GAP);   // digit rel x

    wire in_label = label_valid
                 && (h_cnt >= draw_x) && (h_cnt < draw_x + LABEL_W)
                 && (v_cnt >= draw_y) && (v_cnt < draw_y + 10'd32);
    wire in_digit = digit_valid
                 && (h_cnt >= draw_x + LABEL_W + GAP)
                 && (h_cnt <  draw_x + STRIP_W)
                 && (v_cnt >= draw_y) && (v_cnt < draw_y + 10'd32);
    wire in_any   = in_label | in_digit;

    // entry k (1..24) base word = (k-1)*160 = ((k-1)<<7)+((k-1)<<5);
    // (no blank entry: label_valid=0 gates the whole strip)
    wire [4:0]  lbl_m1   = draw_label - 5'd1;
    wire [11:0] lbl_base = ({7'd0, lbl_m1} << 7) + ({7'd0, lbl_m1} << 5);
    wire [11:0] row_off  = ({7'd0, dy0[4:0]} << 2) + {7'd0, dy0[4:0]};  // dy*5
    wire [11:0] lbl_addr = lbl_base + row_off + {7'd0, dx0[7:5]};
    // digit entry d: DIGIT_WORDS words, TWO glyph rows per word
    // (even row -> upper half, odd row -> lower half)
    localparam [11:0] DGT_BASE = DIGIT_BASE;
    wire [11:0] dgt_addr = DGT_BASE + ({7'd0, draw_digit} << 4)
                         + {7'd0, dy0[4:1]};
    wire [11:0] rom_addr = in_label ? lbl_addr
                         : in_digit ? dgt_addr
                         : 12'd0;

    // bit position pipeline: {row_half, x[4:0]}; bit31 = leftmost pixel,
    // upper half = even row, lower half = odd row
    wire [5:0] bit_sel = {dy0[0], (in_label ? dx0[4:0] : dx1[4:0])};

    // ---------------------------------------------------------------
    // Single-port ROM: 4096 x 32b (4x RAMB36, exactly one BRAM column)
    // ---------------------------------------------------------------
    (* rom_style = "block" *)
    reg [31:0] rom [0:ROM_WORDS-1];
    initial $readmemh("label24.hex", rom);

    reg [31:0] rom_q;       // port A data, valid one cycle after address

    always @(posedge vio_clk)
        rom_q <= rom[rom_addr];

    // ---------------------------------------------------------------
    // Pipeline stage 1: align video/qualifiers with the BRAM read
    // ---------------------------------------------------------------
    reg [23:0] vio_d;
    reg        act_d, hs_d, vs_d;
    reg        in_d;
    reg        lbl_d;       // 1 = label field (full 32b word), 0 = digit (16b half)
    reg  [5:0] bsel_d;
    reg [23:0] fg_d, bg_d;

    always @(posedge vio_clk or negedge rst_sync)
        if (!rst_sync) begin
            vio_d  <= 24'd0;
            act_d  <= 1'b0;
            hs_d   <= 1'b1;
            vs_d   <= 1'b1;
            in_d   <= 1'b0;
            lbl_d  <= 1'b0;
            bsel_d <= 6'd0;
            fg_d   <= 24'd0;
            bg_d   <= 24'd0;
        end else begin
            vio_d  <= vio_data;
            act_d  <= vio_active;
            hs_d   <= vio_hsync;
            vs_d   <= vio_vsync;
            in_d   <= in_any;
            lbl_d  <= in_label;
            bsel_d <= bit_sel;
            fg_d   <= draw_fg;
            bg_d   <= draw_bg;
        end

    // ---------------------------------------------------------------
    // Pipeline stage 2: overlay mux (all paths 2 registers deep)
    // Label words are one 32-px row per word (full-word select, ignore
    // row-parity half); digit words pack TWO 16-px glyph rows (row
    // parity selects the half).
    // ---------------------------------------------------------------
    wire rom_bit = lbl_d ? rom_q[5'd31 - bsel_d[4:0]]
                         : bsel_d[5] ? rom_q[5'd15 - bsel_d[4:0]]
                                     : rom_q[5'd31 - bsel_d[4:0]];

    always @(posedge vio_clk or negedge rst_sync)
        if (!rst_sync) begin
            hdmi_data  <= 24'd0;
            hdmi_de    <= 1'b0;
            hdmi_hsync <= 1'b1;
            hdmi_vsync <= 1'b1;
        end else begin
            hdmi_de    <= act_d;
            hdmi_hsync <= ~hs_d;
            hdmi_vsync <= ~vs_d;
            if (act_d && in_d)
                hdmi_data <= rom_bit ? fg_d : bg_d;
            else if (act_d)
                hdmi_data <= vio_d;
            else
                hdmi_data <= 24'd0;
        end

endmodule
