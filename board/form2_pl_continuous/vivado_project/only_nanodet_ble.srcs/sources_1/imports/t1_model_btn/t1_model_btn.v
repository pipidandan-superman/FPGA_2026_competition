`timescale 1ns/1ps
//====================================================================
// File name   : t1_model_btn.v
// Author      : Codex
// Create date : 2026-10-21
// Description : PL pushbutton -> model switch register (T1 gesture chain)
//               btn_n -> 2-FF sync -> 20ms debounce (press+release confirm)
//               -> rising-edge press event -> mod-3 model counter
//               -> AXI-Lite RO registers polled by PS gesture chain.
// Target      : Zynq-7020 (EES-331 PYNQ), FCLK_CLK0 = 50 MHz
// Revision    : V1.0
//
// Register map (byte addresses, 12-bit local):
//   0x00 ID      RO  0x5442544E ("TBTN")
//   0x04 MODEL   RO  [1:0] current model number 0/1/2
//   0x08 PRESSES RO  [15:0] cumulative press count (reset = 0)
// Design-reserved segment: 0x43C60000 / 64K (integration: BD-assigned).
// All registers are read-only; writes are accepted and return OKAY with
// no effect.
//====================================================================
module t1_model_btn #(
    parameter DEBOUNCE_MS  = 20,                     // >= 20 ms confirm window
    parameter CLK_FREQ_HZ  = 50_000_000,             // FCLK_CLK0
    // debounce confirm threshold in cycles
    parameter DEB_CYCLES   = (CLK_FREQ_HZ/1000)*DEBOUNCE_MS - 1,
    parameter integer DEB_W = 24                      // ceil(log2(1e6)) safe
)(
    input  wire        clk      ,   // 50 MHz, FCLK_CLK0 domain
    input  wire        aresetn  ,   // active-low reset, same name as t1_text_osd
    input  wire        btn_n    ,   // PL pushbutton, active-low (S1/S2/S3 per XDC)
    output wire        led_out  ,   // pressed indicator (optional LED)
    // ---------------- AXI-Lite slave ----------------
    input  wire [11:0] s_axi_awaddr ,
    input  wire [2:0]  s_axi_awprot ,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata  ,
    input  wire [3:0]  s_axi_wstrb  ,
    input  wire        s_axi_wvalid ,
    output wire        s_axi_wready ,
    output wire [1:0]  s_axi_bresp  ,
    output wire        s_axi_bvalid ,
    input  wire        s_axi_bready ,
    input  wire [11:0] s_axi_araddr ,
    input  wire [2:0]  s_axi_arprot ,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata  ,
    output wire [1:0]  s_axi_rresp  ,
    output wire        s_axi_rvalid ,
    input  wire        s_axi_rready
);

    // width-matched compare constant (avoids parameter part-select quirks)
    localparam [DEB_W-1:0] DEB_TOP = DEB_CYCLES;

    //------------------------------------------------------------------
    // 1. 2-FF synchronizer on the asynchronous button input
    //------------------------------------------------------------------
    reg btn_meta, btn_sync;
    always @(posedge clk) begin
        if (!aresetn) begin
            btn_meta <= 1'b1;        // button idle = released = high
            btn_sync <= 1'b1;
        end else begin
            btn_meta <= btn_n;
            btn_sync <= btn_meta;
        end
    end
    wire pressed_raw = ~btn_sync;    // active-high "raw pressed"

    //------------------------------------------------------------------
    // 2. Debounce: count while raw disagrees with debounced output;
    //    flip only after DEB_CYCLES of stable disagreement.
    //    This confirms BOTH the press edge and the release edge
    //    (>= 20 ms window each way), so a long hold fires exactly once.
    //------------------------------------------------------------------
    reg                 btn_db;                 // debounced, active-high pressed
    reg  [DEB_W-1:0]    db_cnt;
    always @(posedge clk) begin
        if (!aresetn) begin
            btn_db  <= 1'b0;
            db_cnt  <= {DEB_W{1'b0}};
        end else if (pressed_raw == btn_db) begin
            db_cnt  <= {DEB_W{1'b0}};           // stable agreement: hold
        end else if (db_cnt >= DEB_TOP) begin
            btn_db  <= pressed_raw;             // confirmed flip (press or release)
            db_cnt  <= {DEB_W{1'b0}};
        end else begin
            db_cnt  <= db_cnt + 1'b1;
        end
    end

    //------------------------------------------------------------------
    // 3. Rising-edge press capture -> mod-3 model counter + press tally
    //------------------------------------------------------------------
    reg        btn_db_d;
    wire       press_pulse = btn_db & ~btn_db_d;
    reg  [1:0] model_reg;                // 0/1/2
    reg [15:0] presses_reg;

    always @(posedge clk) begin
        if (!aresetn) begin
            btn_db_d    <= 1'b0;
            model_reg   <= 2'd0;
            presses_reg <= 16'd0;
        end else begin
            btn_db_d <= btn_db;
            if (press_pulse) begin
                model_reg   <= (model_reg == 2'd2) ? 2'd0 : model_reg + 2'd1;
                presses_reg <= presses_reg + 16'd1;
            end
        end
    end

    assign led_out = btn_db;             // LED on while button confirmed-pressed

    //------------------------------------------------------------------
    // 4. Register readback core behind the shared AXI-Lite slave
    //------------------------------------------------------------------
    wire        wr_valid, wr_ready;
    wire [11:0] wr_addr;
    wire [31:0] wr_data;
    wire [3:0]  wr_strb;
    wire        wr_rsp_valid, wr_rsp_ready;
    wire [1:0]  wr_rsp;
    wire        rd_valid, rd_ready;
    wire [11:0] rd_addr;
    wire        rd_rsp_valid, rd_rsp_ready;
    wire [31:0] rd_data;
    wire [1:0]  rd_rsp;

    localparam [31:0] REG_ID = 32'h5442544E;   // "TBTN"

    // No writable registers: accept any write, always answer OKAY.
    assign wr_ready = 1'b1;
    reg        wr_rsp_valid_r;
    reg [1:0]  wr_rsp_r;
    always @(posedge clk) begin
        if (!aresetn) begin
            wr_rsp_valid_r <= 1'b0;
            wr_rsp_r       <= 2'b00;
        end else if (wr_valid && !wr_rsp_valid_r) begin
            wr_rsp_valid_r <= 1'b1;            // OKAY, ignored
        end else if (wr_rsp_valid_r && wr_rsp_ready) begin
            wr_rsp_valid_r <= 1'b0;
        end
    end
    assign wr_rsp_valid = wr_rsp_valid_r;
    assign wr_rsp       = wr_rsp_r;

    // Read mux: register values snapshotted at accept time (1-cycle latency
    // before rd_rsp_valid, so model/presses are stable when rdata is taken).
    assign rd_ready = 1'b1;
    reg        rd_rsp_valid_r;
    reg [31:0] rd_data_r;
    reg [1:0]  rd_rsp_r2;
    always @(posedge clk) begin
        if (!aresetn) begin
            rd_rsp_valid_r <= 1'b0;
            rd_data_r      <= 32'd0;
            rd_rsp_r2      <= 2'b00;
        end else if (rd_valid && !rd_rsp_valid_r) begin
            rd_rsp_valid_r <= 1'b1;
            rd_rsp_r2      <= 2'b00;           // OKAY everywhere
            case (rd_addr)
                12'h000: rd_data_r <= REG_ID;
                12'h004: rd_data_r <= {30'd0, model_reg};
                12'h008: rd_data_r <= {16'd0, presses_reg};
                default: rd_data_r <= 32'h00000000;
            endcase
        end else if (rd_rsp_valid_r && rd_rsp_ready) begin
            rd_rsp_valid_r <= 1'b0;
        end
    end
    assign rd_rsp_valid = rd_rsp_valid_r;
    assign rd_data      = rd_data_r;
    assign rd_rsp       = rd_rsp_r2;

    //------------------------------------------------------------------
    // 5. Shared AXI-Lite slave front end (board-proven module)
    //------------------------------------------------------------------
    axi_lite_slave u_axi_slave (
        .clk          (clk),
        .resetn       (aresetn),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .wr_valid     (wr_valid),
        .wr_ready     (wr_ready),
        .wr_addr      (wr_addr),
        .wr_data      (wr_data),
        .wr_strb      (wr_strb),
        .wr_rsp_valid (wr_rsp_valid),
        .wr_rsp_ready (wr_rsp_ready),
        .wr_rsp       (wr_rsp),
        .rd_valid     (rd_valid),
        .rd_ready     (rd_ready),
        .rd_addr      (rd_addr),
        .rd_rsp_valid (rd_rsp_valid),
        .rd_rsp_ready (rd_rsp_ready),
        .rd_data      (rd_data),
        .rd_rsp       (rd_rsp)
    );

endmodule
