/************************************************************************
 * File Name       : m9_y_scatter.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_y_scatter
 * Description     :
 *   Y recovery consumer and native byte emitter.  Each block accepts
 *   exactly vc 64-bit input words (8*vc engine-input bytes), preserves
 *   the legacy ordinary and up2x native byte order, and emits only the
 *   selected prefix [0,selected_q).  Raw and selected cursors are
 *   independent: dead-row poison is consumed but never asserted on yreq.
 *   sc_done is a sticky verified-close level; sc_err is independent and
 *   prevents close on input, TLAST, cursor, configuration, address, or
 *   bounded-wait errors.
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 *   - V1.1 (2026-10-09) : sc_done pulse -> sticky level (vc4 race).
 *   - V1.2 (2026-10-09) : removed the leftover pulse assign (dual
 *     continuous drivers on sc_done resolved X -- S_W4 hang, block 0).
 *   - V2.0 (2026-10-28) : selected-prefix emission, complete input drain,
 *     independent raw/selected cursors, bounded wait and verified close.
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_y_scatter (
    input  wire        clk           ,
    input  wire        rst_n         ,
    input  wire        sc_arm        ,
    input  wire [31:0] sc_base       ,
    input  wire [4:0]  sc_vc         ,
    input  wire        sc_up2x       ,
    input  wire        sc_chw        ,
    input  wire [31:0] sc_ch_stride  ,
    input  wire [15:0] selected_write_bytes,
    input  wire [31:0] sc_timeout_limit,
    output wire        sc_done       ,
    output wire        sc_err        ,
    output reg  [7:0]  sc_err_code   ,
    input  wire [63:0] y_tdata       ,
    input  wire        y_tvalid      ,
    output wire        y_tready      ,
    input  wire        y_tlast       ,
    output reg  [31:0] yaddr         ,
    output reg         yreq          ,
    output reg  [7:0]  ywdata        ,
    output reg  [19:0] y_bytes       ,
    output reg  [9:0]  y_blocks
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_RDY   = 2'd1;
    localparam [1:0] ST_DRN   = 2'd2;
    localparam [1:0] ST_CLOSE = 2'd3;

    localparam [7:0] SC_ERR_NONE      = 8'h00;
    localparam [7:0] SC_ERR_CONFIG    = 8'h01;
    localparam [7:0] SC_ERR_ADDRESS   = 8'h02;
    localparam [7:0] SC_ERR_TIMEOUT   = 8'h03;
    localparam [7:0] SC_ERR_CLOSE     = 8'h04;

    reg [1:0] state;
    reg [1:0] next_state;

    reg [31:0] base_r;
    reg [4:0]  vc_r;
    reg        up2x_r;
    reg        chw_r;
    reg [31:0] chw_stride_r;
    reg [31:0] chw_addr_r;
    reg [4:0]  chw_lane_r;
    reg [15:0] selected_q;
    reg [15:0] raw_expected_q;
    reg [31:0] timeout_limit_q;

    reg [5:0]  input_word_count;
    reg [31:0] input_accept_bytes;
    reg [1:0]  tlast_count;
    reg [5:0]  tlast_word_index;
    reg [31:0] raw_native_cursor;
    reg [31:0] selected_cursor;
    reg [31:0] wait_cycles;

    reg [63:0] word_r;
    reg [2:0]  dr_i;

    reg [7:0]  rbyte [0:23];
    reg [4:0]  rcount;
    reg [6:0]  ox_e;
    reg [31:0] ux_rowoff;
    integer    bi;

    reg err_r;
    reg done_r;

    wire [15:0] arm_raw_bytes = sc_up2x
                              ? {6'd0, sc_vc, 5'b00000}
                              : {8'd0, sc_vc, 3'b000};
    wire [32:0] arm_end_ext = {1'b0, sc_base}
                            + {17'd0, selected_write_bytes};
    wire arm_config_ok = (sc_vc != 5'd0) &&
                         (sc_vc <= 5'd16) &&
                         (sc_timeout_limit != 32'd0) &&
                         (selected_write_bytes <= arm_raw_bytes) &&
                         (!sc_up2x ||
                          (selected_write_bytes == arm_raw_bytes));
    wire arm_ok = arm_config_ok && !arm_end_ext[32];

    wire y_fire = y_tvalid && y_tready;
    wire up2x_row_ready = (rcount + 5'd8 >= {1'b0, vc_r});
    wire ordinary_word_done = (dr_i == 3'd7);
    wire up2x_row_done = (ox_e + 7'd1 == {vc_r, 2'b00});
    wire [4:0] up2x_remainder = rcount - vc_r;
    wire timeout_event = (state == ST_RDY) && !y_fire &&
                         (wait_cycles >= timeout_limit_q - 32'd1);

    wire input_ok = (input_word_count == {1'b0, vc_r}) &&
                    (input_accept_bytes == {24'd0, vc_r, 3'b000}) &&
                    (tlast_count == 2'd1) &&
                    (tlast_word_index == {1'b0, vc_r} - 6'd1);
    wire raw_ok = (raw_native_cursor == {16'd0, raw_expected_q});
    wire selected_ok = (selected_cursor == {16'd0, selected_q});
    wire scatter_verified_close = (state == ST_CLOSE) &&
                                  input_ok && raw_ok && selected_ok &&
                                  !err_r;

    wire [6:0] ox_hl = ox_e - {1'b0, vc_r, 1'b0};

    assign y_tready = (state == ST_RDY) &&
                      (input_word_count < {1'b0, vc_r}) && !err_r;
    assign sc_err = err_r;
    assign sc_done = done_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (sc_arm && arm_ok) begin
                    next_state = ST_RDY;
                end
            end
            ST_RDY: begin
                if (timeout_event) begin
                    next_state = ST_IDLE;
                end else if (y_fire) begin
                    if (!up2x_r || up2x_row_ready) begin
                        next_state = ST_DRN;
                    end
                end
            end
            ST_DRN: begin
                if (!up2x_r && ordinary_word_done) begin
                    if (input_word_count == {1'b0, vc_r}) begin
                        next_state = ST_CLOSE;
                    end else begin
                        next_state = ST_RDY;
                    end
                end else if (up2x_r && up2x_row_done) begin
                    if ((input_word_count == {1'b0, vc_r}) &&
                        (rcount == {1'b0, vc_r})) begin
                        next_state = ST_CLOSE;
                    end else if (up2x_remainder >= vc_r) begin
                        next_state = ST_DRN;
                    end else begin
                        next_state = ST_RDY;
                    end
                end
            end
            ST_CLOSE: begin
                next_state = ST_IDLE;
            end
            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yreq <= 1'b0;
            yaddr <= 32'd0;
            ywdata <= 8'd0;
            base_r <= 32'd0;
            vc_r <= 5'd0;
            up2x_r <= 1'b0;
            chw_r <= 1'b0;
            chw_stride_r <= 32'd0;
            chw_addr_r <= 32'd0;
            chw_lane_r <= 5'd0;
            selected_q <= 16'd0;
            raw_expected_q <= 16'd0;
            timeout_limit_q <= 32'd1;
            input_word_count <= 6'd0;
            input_accept_bytes <= 32'd0;
            tlast_count <= 2'd0;
            tlast_word_index <= 6'd0;
            raw_native_cursor <= 32'd0;
            selected_cursor <= 32'd0;
            wait_cycles <= 32'd0;
            word_r <= 64'd0;
            dr_i <= 3'd0;
            rcount <= 5'd0;
            ox_e <= 7'd0;
            ux_rowoff <= 32'd0;
            y_bytes <= 20'd0;
            y_blocks <= 10'd0;
            err_r <= 1'b0;
            done_r <= 1'b0;
            sc_err_code <= SC_ERR_NONE;
            for (bi = 0; bi < 24; bi = bi + 1) begin
                rbyte[bi] <= 8'd0;
            end
        end else begin
            yreq <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (sc_arm) begin
                        base_r <= sc_base;
                        vc_r <= sc_vc;
                        up2x_r <= sc_up2x;
                        chw_r <= sc_chw;
                        chw_stride_r <= sc_ch_stride;
                        chw_addr_r <= sc_base;
                        chw_lane_r <= 5'd0;
                        selected_q <= selected_write_bytes;
                        raw_expected_q <= arm_raw_bytes;
                        timeout_limit_q <= sc_timeout_limit;
                        input_word_count <= 6'd0;
                        input_accept_bytes <= 32'd0;
                        tlast_count <= 2'd0;
                        tlast_word_index <= 6'd0;
                        raw_native_cursor <= 32'd0;
                        selected_cursor <= 32'd0;
                        wait_cycles <= 32'd0;
                        dr_i <= 3'd0;
                        rcount <= 5'd0;
                        ox_e <= 7'd0;
                        ux_rowoff <= 32'd0;
                        err_r <= 1'b0;
                        done_r <= 1'b0;
                        sc_err_code <= SC_ERR_NONE;
                        for (bi = 0; bi < 24; bi = bi + 1) begin
                            rbyte[bi] <= 8'd0;
                        end
                        if (!arm_config_ok) begin
                            err_r <= 1'b1;
                            sc_err_code <= SC_ERR_CONFIG;
                        end else if (arm_end_ext[32]) begin
                            err_r <= 1'b1;
                            sc_err_code <= SC_ERR_ADDRESS;
                        end
                    end
                end
                ST_RDY: begin
                    if (y_fire) begin
                        input_word_count <= input_word_count + 6'd1;
                        input_accept_bytes <= input_accept_bytes + 32'd8;
                        wait_cycles <= 32'd0;
                        if (y_tlast) begin
                            if (tlast_count != 2'd3) begin
                                tlast_count <= tlast_count + 2'd1;
                            end
                            tlast_word_index <= input_word_count;
                        end
                        if (up2x_r) begin
                            for (bi = 0; bi < 8; bi = bi + 1) begin
                                rbyte[rcount + bi] <= y_tdata[8*bi +: 8];
                            end
                            rcount <= rcount + 5'd8;
                        end else begin
                            word_r <= y_tdata;
                            dr_i <= 3'd0;
                        end
                    end else if (timeout_event) begin
                        err_r <= 1'b1;
                        done_r <= 1'b0;
                        sc_err_code <= SC_ERR_TIMEOUT;
                    end else if (wait_cycles != 32'hFFFF_FFFF) begin
                        wait_cycles <= wait_cycles + 32'd1;
                    end
                end
                ST_DRN: begin
                    raw_native_cursor <= raw_native_cursor + 32'd1;
                    if (raw_native_cursor < {16'd0, selected_q}) begin
                        yreq <= 1'b1;
                        if (chw_r) begin
                            yaddr <= chw_addr_r;
                            if (chw_lane_r + 5'd1 >= vc_r) begin
                                chw_lane_r <= 5'd0;
                                chw_addr_r <= chw_addr_r + chw_stride_r - vc_r + 32'd1;
                            end else begin
                                chw_lane_r <= chw_lane_r + 5'd1;
                                chw_addr_r <= chw_addr_r + 32'd1;
                            end
                        end else begin
                            yaddr <= base_r + raw_native_cursor;
                        end
                        selected_cursor <= selected_cursor + 32'd1;
                    end
                    if (up2x_r) begin
                        if (ox_e < {1'b0, vc_r, 1'b0}) begin
                            ywdata <= rbyte[ox_e[4:1]];
                        end else begin
                            ywdata <= rbyte[ox_hl[4:1]];
                        end
                        if (up2x_row_done) begin
                            for (bi = 0; bi < 24; bi = bi + 1) begin
                                if (bi + vc_r < 24) begin
                                    rbyte[bi] <= rbyte[bi + vc_r];
                                end else begin
                                    rbyte[bi] <= 8'd0;
                                end
                            end
                            rcount <= rcount - vc_r;
                            ux_rowoff <= ux_rowoff + {24'd0, vc_r, 2'b00};
                            ox_e <= 7'd0;
                        end else begin
                            ox_e <= ox_e + 7'd1;
                        end
                    end else begin
                        ywdata <= word_r[8*dr_i +: 8];
                        if (!ordinary_word_done) begin
                            dr_i <= dr_i + 3'd1;
                        end
                    end
                end
                ST_CLOSE: begin
                    if (y_tvalid) begin
                        err_r <= 1'b1;
                        done_r <= 1'b0;
                        sc_err_code <= SC_ERR_CLOSE;
                    end else if (scatter_verified_close) begin
                        done_r <= 1'b1;
                        y_bytes <= y_bytes + {9'd0, vc_r, 3'b000};
                        y_blocks <= y_blocks + 10'd1;
                    end else begin
                        err_r <= 1'b1;
                        done_r <= 1'b0;
                        sc_err_code <= SC_ERR_CLOSE;
                    end
                end
                default: begin
                    err_r <= 1'b1;
                    done_r <= 1'b0;
                    sc_err_code <= SC_ERR_CLOSE;
                end
            endcase
        end
    end

endmodule
