//====================================================================
// File name   : pix_frame_dispaly.v
// Author      : Claude Code
// Create date : 2026-10-04
// Description : HDMI video overlay stage (module_ref cell in the
//               display_test BD). Sits between v_axi4s_vid_out and the
//               adv7511 HDMI encoder on the native video path.
//               V2.0 replaces the legacy handwritten-digit UI (fixed
//               center capture box + top-right ROM digit bitmap, both
//               deleted per user directive) with a PS-driven dynamic
//               bounding box for gesture detection:
//                 - AXI-Lite register bank (proven axi_lite_slave
//                   shell + ble_csr reg-file timing) on the 50 MHz
//                   AXI clock, base 0x43C30000 (assigned in BD)
//                 - 2-FF CDC into the pixel domain, frame-boundary
//                   shadow latch (first active pixel) so a box never
//                   tears mid-frame
//                 - white 2-pixel rectangle drawn over camera video
//               Register map (32-bit words):
//                 0x00 ID      RO 0x47424F58 "GBOX"
//                 0x04 VERSION RO 0x00010000
//                 0x08 BOX_L   RW [9:0] left   column, inclusive
//                 0x0C BOX_R   RW [9:0] right  column, inclusive
//                 0x10 BOX_T   RW [9:0] top    row,    inclusive
//                 0x14 BOX_B   RW [9:0] bottom row,    inclusive
//                 0x18 CTRL    RW bit0 box_en (PS: clear en, write
//                              coords, set en - latch also guards)
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V2.0 (V1.x legacy: static 112x112 frame + ROM digit)
//====================================================================
module pix_frame_display #(
	parameter H_SIZE  = 640 ,
	parameter V_SIZE  = 480
)(
	input  wire 			vio_clk		,
	input  wire 			sys_rst_n	,
	input  wire 			vio_active	,
	input  wire 			vio_hsync	,
	input  wire 			vio_vsync	,
	input  wire  [23:0]     vio_data	,

	output reg   [23:0]     hdmi_data	,
	output reg 				hdmi_de		,
	output reg 				hdmi_hsync	,
	output reg 				hdmi_vsync	,

	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK",
	   X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET resetn, FREQ_HZ 50000000" *)
	input  wire         aclk          ,
	(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST",
	   X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
	input  wire         aresetn       ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
	   X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 50000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, HAS_QOS 0, HAS_PROT 1, HAS_WSTRB 1, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
	input  wire [11:0]  s_axi_awaddr  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
	input  wire [2:0]   s_axi_awprot  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
	input  wire         s_axi_awvalid ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
	output wire         s_axi_awready ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
	input  wire [31:0]  s_axi_wdata   ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
	input  wire [3:0]   s_axi_wstrb   ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
	input  wire         s_axi_wvalid  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
	output wire         s_axi_wready  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
	output wire [1:0]   s_axi_bresp   ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
	output wire         s_axi_bvalid  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
	input  wire         s_axi_bready  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
	input  wire [11:0]  s_axi_araddr  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
	input  wire [2:0]   s_axi_arprot  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
	input  wire         s_axi_arvalid ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
	output wire         s_axi_arready ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
	output wire [31:0]  s_axi_rdata   ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
	output wire [1:0]   s_axi_rresp   ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
	output wire         s_axi_rvalid  ,
	(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
	input  wire         s_axi_rready
);

	localparam [1:0] RESP_OKAY   = 2'd0,
	                 RESP_SLVERR = 2'd2;

	// AXI-Lite internal channel (protocol shell instance)
	// shell-driven (wires)
	wire        wr_valid;
	wire [11:0] wr_addr;
	wire [31:0] wr_data;
	wire [3:0]  wr_strb;
	wire        wr_rsp_ready;
	wire        rd_valid;
	wire [11:0] rd_addr;
	wire        rd_rsp_ready;
	// register-bank driven (assigned in always blocks below)
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
	// Register bank (aclk domain), ble_csr accept/response timing
	// ---------------------------------------------------------------
	reg [9:0] box_l_reg, box_r_reg, box_t_reg, box_b_reg;
	reg       box_en_reg;

	always @(posedge aclk or negedge aresetn) begin
		if (!aresetn) begin
			wr_ready     <= 1'b0;
			wr_rsp_valid <= 1'b0;
			wr_rsp       <= RESP_OKAY;
			box_l_reg    <= 10'd0;
			box_r_reg    <= 10'd0;
			box_t_reg    <= 10'd0;
			box_b_reg    <= 10'd0;
			box_en_reg   <= 1'b0;
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
						8'h08: if (wr_strb[0]) box_l_reg <= wr_data[9:0];
						8'h0c: if (wr_strb[0]) box_r_reg <= wr_data[9:0];
						8'h10: if (wr_strb[0]) box_t_reg <= wr_data[9:0];
						8'h14: if (wr_strb[0]) box_b_reg <= wr_data[9:0];
						8'h18: if (wr_strb[0]) box_en_reg <= wr_data[0];
						default: wr_rsp <= RESP_SLVERR;
					endcase
				end else begin
					wr_rsp <= RESP_SLVERR;
				end
			end
		end
	end

	always @(posedge aclk or negedge aresetn) begin
		if (!aresetn) begin
			rd_ready      <= 1'b0;
			rd_rsp_valid  <= 1'b0;
			rd_data       <= 32'd0;
			rd_rsp        <= RESP_OKAY;
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
						8'h00: rd_data <= 32'h47424F58;              // "GBOX"
						8'h04: rd_data <= 32'h00010000;
						8'h08: rd_data <= {22'd0, box_l_reg};
						8'h0c: rd_data <= {22'd0, box_r_reg};
						8'h10: rd_data <= {22'd0, box_t_reg};
						8'h14: rd_data <= {22'd0, box_b_reg};
						8'h18: rd_data <= {31'd0, box_en_reg};
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
	// CDC aclk -> vio_clk: 2-FF per bit, then a shadow latch at the
	// first active pixel of each frame so drawing sees one stable
	// coordinate set for the whole frame (no tearing).
	// ---------------------------------------------------------------
	reg [9:0] box_l_s0, box_l_s1, box_r_s0, box_r_s1;
	reg [9:0] box_t_s0, box_t_s1, box_b_s0, box_b_s1;
	reg       box_en_s0, box_en_s1;

	always @(posedge vio_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			{box_l_s0, box_l_s1} <= 20'd0;
			{box_r_s0, box_r_s1} <= 20'd0;
			{box_t_s0, box_t_s1} <= 20'd0;
			{box_b_s0, box_b_s1} <= 20'd0;
			box_en_s0 <= 1'b0;
			box_en_s1 <= 1'b0;
		end else begin
			box_l_s0 <= box_l_reg;  box_l_s1 <= box_l_s0;
			box_r_s0 <= box_r_reg;  box_r_s1 <= box_r_s0;
			box_t_s0 <= box_t_reg;  box_t_s1 <= box_t_s0;
			box_b_s0 <= box_b_reg;  box_b_s1 <= box_b_s0;
			box_en_s0 <= box_en_reg; box_en_s1 <= box_en_s0;
		end
	end

	// ---------------------------------------------------------------
	// Pixel domain: counters + HDMI sync (V1.x behavior preserved)
	// ---------------------------------------------------------------
	reg [9:0] h_cnt;
	reg [9:0] v_cnt;
	reg rst_n0, rst_sync;

	always @(posedge vio_clk or negedge rst_sync)
		if (!rst_sync) begin
			hdmi_de	   <= 0;
			hdmi_hsync <= 0;
			hdmi_vsync <= 0;
		end
		else begin
			hdmi_de	   <= vio_active;
			hdmi_hsync <= ~vio_hsync;
			hdmi_vsync <= ~vio_vsync;
		end

	//异步复位 同步释放
	always @(posedge vio_clk or negedge sys_rst_n)
		if (!sys_rst_n)begin
			rst_n0 <= 0;
			rst_sync <= 0;
		end
		else begin
			rst_n0 <= 1;
			rst_sync <= rst_n0;
		end

	//行计数器 0-639
	always @(posedge vio_clk or negedge rst_sync)
		if (!rst_sync)
			h_cnt <= 0;
		else if(vio_hsync)
			h_cnt <= 0;
		else if(vio_active)begin
			if(h_cnt >= H_SIZE-1)
				h_cnt <= 0;
			else
				h_cnt <= h_cnt+1;
		end
		else
			h_cnt <= 0;

	//场计数器 0-479
	always @(posedge vio_clk or negedge rst_sync)
		if (!rst_sync)
			v_cnt <= 0;
		else if(vio_vsync)
			v_cnt <= 0;
		else if(h_cnt == H_SIZE-1 && vio_active == 1)begin
			if(v_cnt >= V_SIZE-1)
				v_cnt <= 0;
			else
				v_cnt <= v_cnt+1;
		end

	// ---------------------------------------------------------------
	// Frame-boundary shadow latch: capture coordinates at the first
	// active pixel of the frame (h_cnt==0 && v_cnt==0)
	// ---------------------------------------------------------------
	reg [9:0] draw_l, draw_r, draw_t, draw_b;
	reg       draw_en;

	always @(posedge vio_clk or negedge rst_sync)
		if (!rst_sync) begin
			draw_l  <= 10'd0;
			draw_r  <= 10'd0;
			draw_t  <= 10'd0;
			draw_b  <= 10'd0;
			draw_en <= 1'b0;
		end
		else if (vio_active && (h_cnt == 10'd0) && (v_cnt == 10'd0)) begin
			draw_l  <= box_l_s1;
			draw_r  <= box_r_s1;
			draw_t  <= box_t_s1;
			draw_b  <= box_b_s1;
			draw_en <= box_en_s1;
		end

	// ---------------------------------------------------------------
	// Dynamic bounding box: white 2-pixel rectangle over camera video
	// draw_l/r/t/b inclusive; edges 2 px wide/tall
	// ---------------------------------------------------------------
	wire box_in_rows = (v_cnt >= draw_t) && (v_cnt <= draw_b);
	wire box_in_cols = (h_cnt >= draw_l) && (h_cnt <= draw_r);
	wire box_left_2  = (h_cnt >= draw_l) && (h_cnt <  draw_l + 2'd2);
	wire box_right_2 = (h_cnt + 2'd2 > draw_r) && (h_cnt <= draw_r);
	wire box_top_2   = (v_cnt >= draw_t) && (v_cnt <  draw_t + 2'd2);
	wire box_bot_2   = (v_cnt + 2'd2 > draw_b) && (v_cnt <= draw_b);
	wire box_draw = draw_en && (
			// 左右边线（2 像素宽，纵向贯穿）
			(box_in_rows && (box_left_2 || box_right_2)) ||
			// 上下边线（2 像素高，横向贯穿）
			(box_in_cols && (box_top_2  || box_bot_2 ))
		);

	always @(posedge vio_clk or negedge rst_sync)
		if(!rst_sync)
			hdmi_data <= 0;
		else if(vio_active && box_draw)
			hdmi_data <= 24'hffffff;  // 白色边框
		else if(vio_active)
			hdmi_data <= vio_data;
		else
			hdmi_data <= 0;

endmodule
