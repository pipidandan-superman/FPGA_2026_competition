/************************************************************************
 * File Name       : m9_axi_wr.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_axi_wr
 * Description     :
 *   Single-outstanding AXI32 HP write adapter.  The absolute-lane,
 *   aligned-AW, contiguous-line and WDATA/WSTRB packing laws are retained.
 *   The 512x40 byte queue is official BMG m9_bm_axiwr_fifo with the CUT1
 *   lookahead and registered collision bypass.  The leaf owns exact
 *   pre-state FIFO overflow, m02 BRESP and post-W B-timeout sticky faults.
 * Dependencies    : m9_bm_axiwr_fifo (blk_mem_gen 8.4, veo-style instance)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 *   - V2.1 (2026-10-23) : CUT1 FF FIFO -> WRITE_FIRST BRAM, lookahead
 *                         read address, cycle-identical interface.
 *   - V2.2 (2026-10-23) : registered collision bypass after RAM output.
 *   - V3.0 (2026-10-28) : official BMG conversion, exact full+/-consume
 *                         overflow event, BRESP/B-timeout and empty status.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_axi_wr (
    input  wire        clk           ,
    input  wire        rst_n         ,
    input  wire [31:0] yaddr         ,
    input  wire        yreq          ,
    input  wire [7:0]  ywdata        ,
    input  wire        flush         ,
    input  wire [31:0] b_timeout_limit,
    output wire        busy          ,
    output wire        writer_empty  ,
    output reg  [31:0] m_awaddr      ,
    output wire [3:0]  m_awlen       ,
    output reg         m_awvalid     ,
    input  wire        m_awready     ,
    output reg  [63:0] m_wdata       ,
    output reg  [7:0]  m_wstrb       ,
    output reg         m_wvalid      ,
    input  wire        m_wready      ,
    input  wire [1:0]  m_bresp       ,
    input  wire        m_bvalid      ,
    output reg         m_bready      ,
    output wire        fifo_full_wait,
    output wire [9:0]  fifo_fill     ,
    output wire        axi_fifo_overflow_event,
    output reg         axi_fifo_overflow_sticky,
    output reg         axi_b_timeout_sticky,
    output reg         axi_bresp_error_sticky,
    output wire        b_waiting     ,
    output wire        err           ,
    output reg  [7:0]  err_code
);

    localparam [2:0] ST_FILL = 3'd0;
    localparam [2:0] ST_AW   = 3'd1;
    localparam [2:0] ST_W    = 3'd2;
    localparam [2:0] ST_B    = 3'd3;
    localparam [2:0] ST_ERR  = 3'd4;

    localparam [7:0] AXI_ERR_NONE     = 8'h00;
    localparam [7:0] AXI_ERR_CONFIG   = 8'h01;
    localparam [7:0] AXI_ERR_OVERFLOW = 8'h02;
    localparam [7:0] AXI_ERR_B_TIMEOUT= 8'h03;
    localparam [7:0] AXI_ERR_BRESP    = 8'h04;

    reg [2:0] state;
    reg [2:0] next_state;

    reg [8:0] wp;
    reg [8:0] rp;
    reg [9:0] fill;
    wire fnempty = (fill != 10'd0);

    reg        coll_r;
    reg [39:0] wreg_r;
    wire [39:0] fifo_dout;

    wire [39:0] fhead = coll_r ? wreg_r : fifo_dout;
    wire [31:0] paddr = fhead[39:8];
    wire [7:0]  pdata = fhead[7:0];

    reg [31:0] ln_base;
    reg [2:0]  ln_cnt;
    reg [63:0] ln_data;
    reg [7:0]  ln_strb;

    wire contig = (ln_cnt != 3'd0) &&
                  (paddr[31:3] == ln_base[31:3]) &&
                  (paddr[31:0] == ln_base + {29'd0, ln_cnt});

    wire consume = (state == ST_FILL) && fnempty &&
                   (ln_cnt == 3'd0 || contig);

    assign axi_fifo_overflow_event = yreq && (fill == 10'd512) && !consume;
    wire fifo_we = yreq && !axi_fifo_overflow_event && !err;
    wire [8:0] rd_addr = rp + (consume ? 9'd1 : 9'd0);

    m9_bm_axiwr_fifo u_fifo (
        .clka(clk),
        .ena(fifo_we),
        .wea(1'b1),
        .addra(wp),
        .dina({yaddr, ywdata}),
        .clkb(clk),
        .enb(1'b1),
        .addrb(rd_addr),
        .doutb(fifo_dout)
    );

    always @(posedge clk) begin
        coll_r <= fifo_we && (wp == rd_addr);
        if (fifo_we) begin
            wreg_r <= {yaddr, ywdata};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill <= 10'd0;
        end else if (fifo_we && !consume) begin
            fill <= fill + 10'd1;
        end else if (!fifo_we && consume) begin
            fill <= fill - 10'd1;
        end
    end

    reg [31:0] b_wait_cycles;
    wire b_fire = (state == ST_B) && m_bvalid && m_bready;
    wire b_timeout_event = (state == ST_B) && !b_fire &&
                           (b_timeout_limit != 32'd0) &&
                           (b_wait_cycles >= b_timeout_limit - 32'd1);

    assign m_awlen = 4'd0;
    assign busy = (state != ST_FILL) || fnempty || (ln_cnt != 3'd0);
    assign writer_empty = (state == ST_FILL) && !fnempty &&
                          (fill == 10'd0) && (ln_cnt == 3'd0) &&
                          !m_awvalid && !m_wvalid && !m_bready && !err;
    assign fifo_full_wait = yreq && (fill == 10'd512);
    assign fifo_fill = fill;
    assign b_waiting = (state == ST_B);
    assign err = axi_fifo_overflow_sticky || axi_b_timeout_sticky ||
                 axi_bresp_error_sticky || (b_timeout_limit == 32'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_FILL;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        if (axi_fifo_overflow_event || (b_timeout_limit == 32'd0)) begin
            next_state = ST_ERR;
        end else begin
            case (state)
                ST_FILL: begin
                    if (fnempty) begin
                        if (ln_cnt == 3'd0) begin
                            next_state = ST_FILL;
                        end else if (contig && (ln_cnt == 3'd7)) begin
                            next_state = ST_AW;
                        end else if (!contig) begin
                            next_state = ST_AW;
                        end
                    end else if (flush && (ln_cnt != 3'd0)) begin
                        next_state = ST_AW;
                    end
                end
                ST_AW: begin
                    if (m_awready) begin
                        next_state = ST_W;
                    end
                end
                ST_W: begin
                    if (m_wready) begin
                        next_state = ST_B;
                    end
                end
                ST_B: begin
                    if (b_fire) begin
                        if (m_bresp == 2'b00) begin
                            next_state = ST_FILL;
                        end else begin
                            next_state = ST_ERR;
                        end
                    end else if (b_timeout_event) begin
                        next_state = ST_ERR;
                    end
                end
                ST_ERR: begin
                    next_state = ST_ERR;
                end
                default: begin
                    next_state = ST_ERR;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= 9'd0;
            rp <= 9'd0;
            ln_base <= 32'd0;
            ln_cnt <= 3'd0;
            ln_data <= 64'd0;
            ln_strb <= 8'd0;
            m_awvalid <= 1'b0;
            m_awaddr <= 32'd0;
            m_wvalid <= 1'b0;
            m_wdata <= 64'd0;
            m_wstrb <= 8'd0;
            m_bready <= 1'b0;
            b_wait_cycles <= 32'd0;
        end else begin
            if (fifo_we) begin
                wp <= wp + 9'd1;
            end

            case (state)
                ST_FILL: begin
                    if (fnempty) begin
                        if (ln_cnt == 3'd0) begin
                            rp <= rp + 9'd1;
                            ln_base <= paddr;
                            ln_cnt <= 3'd1;
                            ln_data <= {56'd0, pdata} << (8 * paddr[2:0]);
                            ln_strb <= 8'd1 << paddr[2:0];
                        end else if (contig) begin
                            rp <= rp + 9'd1;
                            ln_data <= ln_data |
                                       ({56'd0, pdata} << (8 * paddr[2:0]));
                            ln_strb <= ln_strb | (8'd1 << paddr[2:0]);
                            if (ln_cnt == 3'd7) begin
                                m_awaddr <= {ln_base[31:3], 3'b000};
                                m_awvalid <= 1'b1;
                            end else begin
                                ln_cnt <= ln_cnt + 3'd1;
                            end
                        end else begin
                            m_awaddr <= {ln_base[31:3], 3'b000};
                            m_awvalid <= 1'b1;
                        end
                    end else if (flush && (ln_cnt != 3'd0)) begin
                        m_awaddr <= {ln_base[31:3], 3'b000};
                        m_awvalid <= 1'b1;
                    end
                end
                ST_AW: begin
                    if (m_awready) begin
                        m_awvalid <= 1'b0;
                        m_wdata <= ln_data;
                        m_wstrb <= ln_strb;
                        m_wvalid <= 1'b1;
                    end
                end
                ST_W: begin
                    if (m_wready) begin
                        m_wvalid <= 1'b0;
                        m_bready <= 1'b1;
                        b_wait_cycles <= 32'd0;
                    end
                end
                ST_B: begin
                    if (b_fire) begin
                        m_bready <= 1'b0;
                        ln_cnt <= 3'd0;
                        ln_strb <= 8'd0;
                        b_wait_cycles <= 32'd0;
                    end else if (b_timeout_event) begin
                        b_wait_cycles <= b_wait_cycles;
                    end else if (b_wait_cycles != 32'hFFFF_FFFF) begin
                        b_wait_cycles <= b_wait_cycles + 32'd1;
                    end
                end
                ST_ERR: begin
                    m_awvalid <= 1'b0;
                    m_wvalid <= 1'b0;
                    m_bready <= 1'b0;
                end
                default: begin
                    m_awvalid <= 1'b0;
                    m_wvalid <= 1'b0;
                    m_bready <= 1'b0;
                end
            endcase

            if (next_state == ST_ERR) begin
                m_awvalid <= 1'b0;
                m_wvalid <= 1'b0;
                m_bready <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_fifo_overflow_sticky <= 1'b0;
            axi_b_timeout_sticky <= 1'b0;
            axi_bresp_error_sticky <= 1'b0;
            err_code <= AXI_ERR_NONE;
        end else begin
            if (b_timeout_limit == 32'd0) begin
                if (err_code == AXI_ERR_NONE) begin
                    err_code <= AXI_ERR_CONFIG;
                end
            end
            if (axi_fifo_overflow_event) begin
                axi_fifo_overflow_sticky <= 1'b1;
                if (err_code == AXI_ERR_NONE) begin
                    err_code <= AXI_ERR_OVERFLOW;
                end
            end
            if (b_timeout_event) begin
                axi_b_timeout_sticky <= 1'b1;
                if (err_code == AXI_ERR_NONE) begin
                    err_code <= AXI_ERR_B_TIMEOUT;
                end
            end
            if (b_fire && (m_bresp != 2'b00)) begin
                axi_bresp_error_sticky <= 1'b1;
                if (err_code == AXI_ERR_NONE) begin
                    err_code <= AXI_ERR_BRESP;
                end
            end
        end
    end

endmodule
