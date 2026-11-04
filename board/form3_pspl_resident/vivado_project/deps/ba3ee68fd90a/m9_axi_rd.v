/************************************************************************
 * File Name       : m9_axi_rd.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_axi_rd
 * Description     :
 *   M9.5b AXI32 HP read adapter for the proven M9.1 byte-read faces
 *   (02_m9_issuer_spec.md section 7: x window HP0 / w feeder HP3).
 *   One instance per client port -- no arbitration inside.
 *
 *   Client face (contract = m9_x_window/m9_w_feeder, unchanged):
 *     raddr/rreq held until a 1-cycle rvalid pulse; any latency legal.
 *   AXI face: single-beat 64b line reads (ARLEN=0) at 8-byte-aligned
 *   addresses; an 8-byte line register absorbs the per-lane sequential
 *   walk (ix strides 1/2, W streams are long-sequential).  Correctness
 *   first: line hit serves in one cycle; miss costs one AR+R round trip
 *   (burst efficiency is M10 work, spec section 7 note).
 *
 *   The proven cores stay byte-face identical (wrapper composition --
 *   same discipline as the engine zero-diff law); this module is a
 *   sibling, not a change, to m9_x_window/m9_w_feeder.
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5b.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_axi_rd (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- client byte-read face (req 在途保持律) ----
    input  wire [31:0] raddr         ,
    input  wire        rreq          ,
    output reg  [7:0]  rdata         ,
    output reg         rvalid        ,
    // ---- AXI32 read master (single-beat 64b lines) ----
    output reg  [31:0] m_araddr      ,
    output wire [3:0]  m_arlen       ,
    output reg         m_arvalid     ,
    input  wire        m_arready     ,
    input  wire [63:0] m_rdata       ,
    input  wire [1:0]  m_rresp       ,
    input  wire        m_rvalid      ,
    input  wire        m_rlast       ,
    output reg         m_rready,
    output wire        ddr_gap_wait
);

    // ---------------- FSM ----------------
    localparam ST_IDLE = 2'd0,   // wait rreq
               ST_AR   = 2'd1,   // AR handshake (line miss)
               ST_R    = 2'd2;   // R beat capture
    reg [1:0] st;

    // 8-byte line buffer
    reg [31:0] line_base;            // aligned base of the loaded line
    reg        line_ok;              // line holds valid data
    reg [63:0] line_data;
    reg        served;               // rvalid issued for current rreq

    wire [31:0] line_aln = {raddr[31:3], 3'b000};
    wire        hit      = line_ok && (line_aln == line_base);

    assign m_arlen = 4'd0;           // 1 beat of 64b per AR
    assign ddr_gap_wait = (st == ST_R) && !m_rvalid;

    // ---------------- sequencer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            rvalid <= 1'b0;
            m_arvalid <= 1'b0;
            m_araddr <= 32'd0;
            m_rready <= 1'b0;
            line_ok <= 1'b0;
            line_base <= 32'd0;
            line_data <= 64'd0;
            served <= 1'b0;
            rdata <= 8'd0;
        end else begin
            rvalid <= 1'b0;               // default pulse
            if (!rreq) served <= 1'b0;    // client accepted, re-arm
            case (st)
            ST_IDLE: if (rreq && !served) begin
                if (hit) begin
                    // serve from the line (lane of the HELD raddr)
                    case (raddr[2:0])
                    3'd0: rdata <= line_data[7:0];
                    3'd1: rdata <= line_data[15:8];
                    3'd2: rdata <= line_data[23:16];
                    3'd3: rdata <= line_data[31:24];
                    3'd4: rdata <= line_data[39:32];
                    3'd5: rdata <= line_data[47:40];
                    3'd6: rdata <= line_data[55:48];
                    default: rdata <= line_data[63:56];
                    endcase
                    rvalid  <= 1'b1;
                    served  <= 1'b1;
                end else begin
                    m_araddr  <= line_aln;
                    m_arvalid <= 1'b1;
                    st <= ST_AR;
                end
            end
            ST_AR: if (m_arready) begin
                m_arvalid <= 1'b0;
                m_rready  <= 1'b1;
                st <= ST_R;
            end
            ST_R: if (m_rvalid && m_rlast) begin
                m_rready  <= 1'b0;
                line_base <= m_araddr;
                line_data <= m_rdata;
                line_ok   <= 1'b1;
                // serve the missed request this cycle+1 register path:
                // fall through to IDLE; IDLE re-tests hit (now true)
                st <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
