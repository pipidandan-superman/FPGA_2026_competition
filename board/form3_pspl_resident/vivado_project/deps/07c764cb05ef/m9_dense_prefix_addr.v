/************************************************************************
 * File Name       : m9_dense_prefix_addr.v
 * Developer       : LSL
 * Date            : 2026-10-28
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : m9_dense_prefix_addr
 * Description     : Paged dense-prefix cursor and absolute block-base
 *                   generator.  Relative and absolute objects stay
 *                   separate; all address commits use 33-bit checks.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-10-28) by LSL : Initial release
 *   - V1.1 (2026-10-28) by LSL : Reject same-cycle init/arm and pre-arm
 *         face-extent overflow before any selected byte can emit.
 ************************************************************************/
`timescale 1ns / 1ps

module m9_dense_prefix_addr (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        paged_mode_i,
    input  wire        epoch_ybase_valid_i,
    input  wire [31:0] epoch_ybase_i,
    input  wire        epoch_ybase_fault_i,
    input  wire        conv_start_i,
    input  wire [31:0] face_off_i,
    input  wire [31:0] face_expected_bytes_i,
    input  wire        sc_arm_i,
    input  wire [15:0] selected_write_bytes_i,
    input  wire        scatter_verified_close_i,
    input  wire        face_close_i,
    output wire [31:0] sc_base_o,
    output reg  [31:0] face_abs_base_q_o,
    output reg  [31:0] block_base_q_o,
    output reg  [31:0] block_off_q_o,
    output reg  [15:0] selected_q_o,
    output reg  [31:0] dense_off_committed_o,
    output reg         block_open_q_o,
    output reg         face_valid_q_o,
    output reg         addr_err_o
);

    reg [31:0] face_off_q;
    reg [31:0] face_expected_bytes_q;

    wire [32:0] face_sum_ext = {1'b0, epoch_ybase_i}
                             + {1'b0, face_off_q};
    wire [32:0] block_sum_ext = {1'b0, face_sum_ext[31:0]}
                              + {1'b0, dense_off_committed_o};
    wire [32:0] arm_end_ext = {1'b0, block_sum_ext[31:0]}
                            + {17'd0, selected_write_bytes_i};
    wire [32:0] close_sum_ext = {1'b0, block_off_q_o}
                              + {17'd0, selected_q_o};
    wire [32:0] arm_relative_end_ext = {1'b0, dense_off_committed_o}
                                     + {17'd0, selected_write_bytes_i};

    wire arm_legal = face_valid_q_o && !block_open_q_o && !addr_err_o &&
                     !conv_start_i &&
                     !epoch_ybase_fault_i &&
                     (!paged_mode_i || epoch_ybase_valid_i) &&
                     (face_off_i == face_off_q) &&
                     (face_expected_bytes_i == face_expected_bytes_q) &&
                     !face_sum_ext[32] && !block_sum_ext[32] &&
                     !arm_end_ext[32];

    assign sc_base_o = sc_arm_i ? block_sum_ext[31:0] : block_base_q_o;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            face_abs_base_q_o <= 32'd0;
            block_base_q_o <= 32'd0;
            block_off_q_o <= 32'd0;
            selected_q_o <= 16'd0;
            dense_off_committed_o <= 32'd0;
            block_open_q_o <= 1'b0;
            face_valid_q_o <= 1'b0;
            addr_err_o <= 1'b0;
            face_off_q <= 32'd0;
            face_expected_bytes_q <= 32'd0;
        end else begin
            if (epoch_ybase_fault_i) begin
                addr_err_o <= 1'b1;
            end

            if (conv_start_i) begin
                if (block_open_q_o || addr_err_o || epoch_ybase_fault_i) begin
                    addr_err_o <= 1'b1;
                end else begin
                    dense_off_committed_o <= 32'd0;
                    block_open_q_o <= 1'b0;
                    face_valid_q_o <= 1'b1;
                    face_off_q <= face_off_i;
                    face_expected_bytes_q <= face_expected_bytes_i;
                end
            end

            if (sc_arm_i) begin
                if (arm_legal) begin
                    face_abs_base_q_o <= face_sum_ext[31:0];
                    block_base_q_o <= block_sum_ext[31:0];
                    block_off_q_o <= dense_off_committed_o;
                    selected_q_o <= selected_write_bytes_i;
                    block_open_q_o <= 1'b1;
                end else begin
                    addr_err_o <= 1'b1;
                end
            end

            if (scatter_verified_close_i) begin
                if (!block_open_q_o || close_sum_ext[32] || addr_err_o) begin
                    addr_err_o <= 1'b1;
                end else begin
                    dense_off_committed_o <= close_sum_ext[31:0];
                    block_open_q_o <= 1'b0;
                end
            end

            if (face_close_i) begin
                // A face is a sequence of compact blocks, not a full dense
                // byte span.  Close after the last verified block; comparing
                // against face_expected_bytes_q rejects every compact face.
                if (!face_valid_q_o || addr_err_o) begin
                    addr_err_o <= 1'b1;
                end else if (scatter_verified_close_i) begin
                    if (block_open_q_o && !close_sum_ext[32]) begin
                        face_valid_q_o <= 1'b0;
                    end else begin
                        addr_err_o <= 1'b1;
                    end
                end else if (!block_open_q_o) begin
                    face_valid_q_o <= 1'b0;
                end else begin
                    addr_err_o <= 1'b1;
                end
            end
        end
    end

endmodule
