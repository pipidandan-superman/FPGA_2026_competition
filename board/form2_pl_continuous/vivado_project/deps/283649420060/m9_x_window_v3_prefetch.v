`timescale 1ns / 1ps

// X-window with an eight-descriptor pipeline and a 64-line BRAM FIFO.
// Address generation, DDR requests/responses and output consumption are
// decoupled, while response and tap ordering remain strictly in order.
module m9_x_window_v3 (
    input wire clk, input wire rst_n,
    input wire [15:0] cfg_ic, input wire [15:0] cfg_h, input wire [15:0] cfg_w,
    input wire [3:0] cfg_kh, input wire [3:0] cfg_kw,
    input wire [3:0] cfg_sh, input wire [3:0] cfg_sw,
    input wire [3:0] cfg_ph, input wire [3:0] cfg_pw,
    input wire cfg_first, input wire cfg_law_fetch,
    input wire [31:0] cfg_xbase, input wire [31:0] cfg_ch_stride,
    input wire [47:0] cfg_layout_id, input wire [3:0] conv_idx,
    input wire [9:0] rt_oy, input wire [3:0] rt_s, input wire [10:0] rt_k,
    input wire [4:0] rt_vc, input wire [15:0] rt_koff_ic,
    input wire [3:0] rt_koff_kh, input wire [3:0] rt_koff_kw,
    input wire start, output wire busy, output wire done,
    output reg [31:0] raddr_line, output reg rreq_line,
    input wire [63:0] rdata_line, input wire rvalid_line,
    output reg [63:0] x_beat_data, output reg x_beat_hi,
    output reg x_beat_last, output reg x_beat_valid,
    input wire x_beat_ready
);
    localparam A_IDLE=3'd0, A_ADDR1=3'd1, A_ADDR2=3'd2, A_ADDR3=3'd3;
    localparam O_IDLE=3'd0, O_WAIT=3'd1, O_READ=3'd2, O_LO=3'd3,
               O_HI=3'd4, O_DONE=3'd5;
    reg [2:0] addr_st, out_st;
    reg [31:0] hw_prod_r;
    reg [2:0] layout_sel;
    wire [7:0] pad_val = 8'h00;

    reg [15:0] pf_ic;
    reg [3:0] pf_kh, pf_kw;
    reg [31:0] ch_off_r;
    reg signed [31:0] iy_v_r;
    reg [31:0] iy_clip_r;
    reg iy_inb_r;
    reg signed [15:0] ix_base_r;
    reg [10:0] k_pf, k_r;
    reg [9:0] oy_r;
    reg [3:0] s_r;
    reg [4:0] vc_r;

    function ix_inb_l;
        input [3:0] n;
        reg signed [15:0] v;
        begin
            v = ix_base_r + cfg_sw * {12'd0,n};
            ix_inb_l = (v >= 0) && (v < cfg_w);
        end
    endfunction
    function [3:0] first_live;
        input [15:0] m;
        integer i;
        begin
            first_live = 4'd0;
            for (i=15;i>=0;i=i-1) if (!m[i]) first_live=i[3:0];
        end
    endfunction
    function [3:0] last_live;
        input [15:0] m;
        integer i;
        begin
            last_live = 4'd0;
            for (i=0;i<=15;i=i+1) if (!m[i]) last_live=i[3:0];
        end
    endfunction

    // New descriptor presented by A_ADDR3.
    wire [15:0] new_const;
    wire [15:0] new_fill;
    genvar gm;
    generate for (gm=0; gm<16; gm=gm+1) begin : g_mask
        // Independent lane arithmetic avoids sharing the function's static
        // temporary across sixteen concurrent continuous calls.
        wire signed [15:0] lane_ix = ix_base_r + cfg_sw * gm;
        assign new_const[gm] = ~iy_inb_r | (lane_ix < 0) |
                               (lane_ix >= $signed({1'b0,cfg_w})) |
                               (~cfg_law_fetch & (vc_r<=gm[4:0]));
        assign new_fill[gm] = ~cfg_law_fetch & (vc_r<=gm[4:0]);
    end endgenerate
    wire [31:0] new_b0 = cfg_xbase+ch_off_r+iy_clip_r*cfg_w+
                         {{16{ix_base_r[15]}},ix_base_r};
    wire [3:0] new_first = first_live(new_const);
    wire [3:0] new_last = last_live(new_const);
    wire [31:0] new_span_lo = new_b0 + cfg_sw * {12'd0,new_first};
    wire [31:0] new_span_hi = new_b0 + cfg_sw * {12'd0,new_last};
    wire new_any_live = ~(&new_const);
    wire [3:0] new_nlines = new_any_live ?
                            (new_span_hi[31:3]-new_span_lo[31:3]+29'd1) : 4'd0;

    // Descriptor FIFO.  Entries remain until the output consumes them;
    // a separate issue pointer lets DDR run ahead without reordering.
    reg [31:0] desc_b0 [0:7];
    reg [15:0] desc_const [0:7];
    reg [15:0] desc_fill [0:7];
    reg [3:0] desc_nlines [0:7];
    reg [10:0] desc_k [0:7];
    reg [2:0] desc_head, desc_tail, issue_head;
    reg [3:0] desc_count, issue_count;

    // BRAM line FIFO and DDR in-flight accounting.
    reg [5:0] fifo_wptr, fifo_rptr;
    reg [6:0] fifo_count;
    reg [4:0] inflight;
    wire [7:0] line_credit = 8'd64 - {1'b0,fifo_count} - {3'd0,inflight};
    wire desc_push = (addr_st == A_ADDR3) && (desc_count < 4'd8) &&
                     (line_credit >= {4'd0,new_nlines});

    // DDR issue side.
    reg issue_active;
    reg [28:0] issue_line_lo;
    reg [3:0] issue_nlines, issue_fcnt;
    wire issue_start = !issue_active && (issue_count != 0);
    wire issue_fire = issue_active && (issue_fcnt < issue_nlines) &&
                      (inflight < 5'd12);

    // Output side.
    reg [31:0] cur_b0;
    reg [15:0] cur_const, cur_fill;
    reg [10:0] cur_k;
    reg [28:0] line_lo;
    reg [3:0] cur_nlines, out_issued, out_received;
    reg bram_rd_pending;
    reg [3:0] bram_rd_idx;
    wire [63:0] fifo_dout;
    wire out_start = (out_st == O_WAIT) && (desc_count != 0) &&
                     (fifo_count >= {3'd0,desc_nlines[desc_head]});
    wire out_pop = out_start;
    wire bram_read = (out_st == O_READ) && (out_issued < cur_nlines);

    m9_bm_xprefetch u_xprefetch (
        .clka(clk), .ena(rvalid_line), .wea(rvalid_line),
        .addra(fifo_wptr), .dina(rdata_line),
        .clkb(clk), .enb(bram_read), .addrb(fifo_rptr), .doutb(fifo_dout)
    );

    reg [63:0] line_word [0:4];
    function [7:0] lane_byte;
        input [3:0] n;
        reg [31:0] a;
        reg [3:0] j;
        begin
            if (cur_const[n]) lane_byte = cur_fill[n] ? 8'hA5 : pad_val;
            else begin
                a = cur_b0 + cfg_sw * {12'd0,n};
                j = a[31:3] - line_lo;
                case (a[2:0])
                    3'd0: lane_byte=line_word[j][7:0];
                    3'd1: lane_byte=line_word[j][15:8];
                    3'd2: lane_byte=line_word[j][23:16];
                    3'd3: lane_byte=line_word[j][31:24];
                    3'd4: lane_byte=line_word[j][39:32];
                    3'd5: lane_byte=line_word[j][47:40];
                    3'd6: lane_byte=line_word[j][55:48];
                    default: lane_byte=line_word[j][63:56];
                endcase
            end
        end
    endfunction

    // Preserve the original unit-TB visibility names.
    wire [2:0] st = out_st;
    wire [3:0] fcnt = issue_fcnt;
    wire [3:0] rcnt = out_issued;
    wire [3:0] n_lines = cur_nlines;
    wire [7:0] pend_valid = {8{desc_count != 0}};
    wire cur_valid = (out_st == O_READ) || (out_st == O_LO) || (out_st == O_HI);
    reg [10:0] k_cur;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) k_cur <= 11'd0;
        else if (start) k_cur <= 11'd0;
        else if ((out_st == O_HI) && x_beat_valid && x_beat_ready)
            k_cur <= k_cur + 11'd1;
    end

    assign busy = (addr_st != A_IDLE) || (out_st != O_IDLE) ||
                  (desc_count != 0) || issue_active || (inflight != 0) ||
                  (fifo_count != 0);
    assign done = (out_st == O_DONE);

    // Address generator stalls only on descriptor/data-FIFO credit.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_st <= A_IDLE;
            layout_sel <= 3'b000;
        end else begin
            case (addr_st)
            A_IDLE: if (start) begin
                oy_r <= rt_oy; s_r <= rt_s; k_r <= rt_k; vc_r <= rt_vc;
                layout_sel <= cfg_layout_id[conv_idx*3 +: 3];
                case (cfg_layout_id[conv_idx*3 +: 3])
                3'b001,3'b010,3'b100: hw_prod_r <= (cfg_ch_stride==0) ? (cfg_h*cfg_w) : cfg_ch_stride;
                default: hw_prod_r <= (cfg_ch_stride==0) ? (cfg_h*cfg_w) : cfg_ch_stride;
                endcase
                pf_ic <= rt_koff_ic; pf_kh <= rt_koff_kh; pf_kw <= rt_koff_kw;
                k_pf <= 0;
                addr_st <= A_ADDR1;
            end
            A_ADDR1: begin
                ch_off_r <= pf_ic * hw_prod_r;
                iy_v_r <= cfg_sh * oy_r + pf_kh - cfg_ph;
                addr_st <= A_ADDR2;
            end
            A_ADDR2: begin
                iy_clip_r <= (iy_v_r<0) ? 0 : (iy_v_r>=cfg_h) ? (cfg_h-1) : iy_v_r;
                iy_inb_r <= (iy_v_r>=0) && (iy_v_r<cfg_h);
                ix_base_r <= cfg_sw * {s_r,4'd0} + pf_kw - cfg_pw;
                if (pf_kw == cfg_kw-1) begin
                    pf_kw <= 0;
                    if (pf_kh == cfg_kh-1) begin pf_kh<=0; pf_ic<=pf_ic+1; end
                    else pf_kh <= pf_kh+1;
                end else pf_kw <= pf_kw+1;
                addr_st <= A_ADDR3;
            end
            A_ADDR3: begin
                if (desc_push) begin
                    k_pf <= k_pf+1;
                    if (k_pf+1 >= k_r) addr_st <= A_IDLE;
                    else addr_st <= A_ADDR1;
                end
            end
            default: addr_st <= A_IDLE;
            endcase
        end
    end

    // Descriptor FIFO pointers and occupancy.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            desc_head <= 0; desc_tail <= 0; issue_head <= 0;
            desc_count <= 0; issue_count <= 0;
        end else if (start) begin
            desc_head <= 0; desc_tail <= 0; issue_head <= 0;
            desc_count <= 0; issue_count <= 0;
        end else begin
            if (desc_push) begin
                desc_b0[desc_tail] <= new_b0;
                desc_const[desc_tail] <= new_const;
                desc_fill[desc_tail] <= new_fill;
                desc_nlines[desc_tail] <= new_nlines;
                desc_k[desc_tail] <= k_pf;
                desc_tail <= desc_tail + 1'b1;
            end
            if (out_pop) desc_head <= desc_head + 1'b1;
            if (issue_start) issue_head <= issue_head + 1'b1;
            case ({desc_push,out_pop})
                2'b10: desc_count <= desc_count + 1'b1;
                2'b01: desc_count <= desc_count - 1'b1;
                default: desc_count <= desc_count;
            endcase
            case ({desc_push,issue_start})
                2'b10: issue_count <= issue_count + 1'b1;
                2'b01: issue_count <= issue_count - 1'b1;
                default: issue_count <= issue_count;
            endcase
        end
    end

    // DDR issue pipeline.  Responses are written in exactly request order.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_active <= 1'b0;
            issue_fcnt <= 0;
            rreq_line <= 1'b0;
            inflight <= 0;
            fifo_wptr <= 0;
        end else if (start) begin
            issue_active <= 1'b0;
            issue_fcnt <= 0;
            rreq_line <= 1'b0;
            inflight <= 0;
            fifo_wptr <= 0;
        end else begin
            rreq_line <= 1'b0;
            if (issue_start) begin
                issue_line_lo <= (desc_b0[issue_head] +
                    cfg_sw*{12'd0,first_live(desc_const[issue_head])}) >> 3;
                issue_nlines <= desc_nlines[issue_head];
                issue_fcnt <= 0;
                issue_active <= (desc_nlines[issue_head] != 0);
            end
            if (issue_fire) begin
                raddr_line <= {issue_line_lo+issue_fcnt,3'b000};
                rreq_line <= 1'b1;
                issue_fcnt <= issue_fcnt + 1'b1;
                if (issue_fcnt+1 >= issue_nlines) issue_active <= 1'b0;
            end
            case ({issue_fire,rvalid_line})
                2'b10: inflight <= inflight + 1'b1;
                2'b01: inflight <= inflight - 1'b1;
                default: inflight <= inflight;
            endcase
            if (rvalid_line) fifo_wptr <= fifo_wptr + 1'b1;
        end
    end

    // Output FIFO reads and original two-beat presentation.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_st <= O_IDLE;
            fifo_rptr <= 0; fifo_count <= 0;
            out_issued <= 0; out_received <= 0;
            bram_rd_pending <= 1'b0;
            x_beat_valid <= 1'b0;
            x_beat_hi <= 1'b0;
            x_beat_last <= 1'b0;
        end else if (start) begin
            out_st <= O_WAIT;
            fifo_rptr <= 0; fifo_count <= 0;
            out_issued <= 0; out_received <= 0;
            bram_rd_pending <= 1'b0;
            x_beat_valid <= 1'b0;
            x_beat_hi <= 1'b0;
            x_beat_last <= 1'b0;
        end else begin
            x_beat_valid <= 1'b0;
            bram_rd_pending <= bram_read;
            if (bram_read) begin
                bram_rd_idx <= out_issued;
                fifo_rptr <= fifo_rptr + 1'b1;
                out_issued <= out_issued + 1'b1;
            end
            case ({rvalid_line,bram_read})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
            case (out_st)
            O_WAIT: if (out_start) begin
                cur_b0 <= desc_b0[desc_head];
                cur_const <= desc_const[desc_head];
                cur_fill <= desc_fill[desc_head];
                cur_k <= desc_k[desc_head];
                cur_nlines <= desc_nlines[desc_head];
                line_lo <= (desc_b0[desc_head] +
                    cfg_sw*{12'd0,first_live(desc_const[desc_head])}) >> 3;
                out_issued <= 0; out_received <= 0;
                out_st <= O_READ;
            end
            O_READ: begin
                if (bram_rd_pending) begin
                    line_word[bram_rd_idx] <= fifo_dout;
                    out_received <= out_received + 1'b1;
                    if (out_received+1 >= cur_nlines) out_st <= O_LO;
                end
                if (cur_nlines == 0) out_st <= O_LO;
            end
            O_LO: begin
                if (!x_beat_valid) begin
                    x_beat_data <= {lane_byte(7),lane_byte(6),lane_byte(5),lane_byte(4),
                                    lane_byte(3),lane_byte(2),lane_byte(1),lane_byte(0)};
                    x_beat_hi <= 1'b0; x_beat_last <= 1'b0; x_beat_valid <= 1'b1;
                end else if (x_beat_ready) begin
                    x_beat_valid <= 1'b0; out_st <= O_HI;
                end else x_beat_valid <= 1'b1;
            end
            O_HI: begin
                if (!x_beat_valid) begin
                    x_beat_data <= {lane_byte(15),lane_byte(14),lane_byte(13),lane_byte(12),
                                    lane_byte(11),lane_byte(10),lane_byte(9),lane_byte(8)};
                    x_beat_hi <= 1'b1; x_beat_last <= (cur_k==k_r-1); x_beat_valid <= 1'b1;
                end else if (x_beat_ready) begin
                    x_beat_valid <= 1'b0;
                    if (cur_k == k_r-1) out_st <= O_DONE;
                    else out_st <= O_WAIT;
                end else x_beat_valid <= 1'b1;
            end
            O_DONE: out_st <= O_IDLE;
            default: out_st <= O_WAIT;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && out_start)
            $display("XPREF_OUT_START k=%0d nlines=%0d fifo_count=%0d line_lo=%0d const=%h fill=%h b0=%h",desc_k[desc_head],desc_nlines[desc_head],fifo_count,line_lo,desc_const[desc_head],desc_fill[desc_head],desc_b0[desc_head]);
        if (rst_n && desc_push)
            $display("XPREF_DESC k=%0d const=%h fill=%h b0=%h ix=%0d nlines=%0d",k_pf,new_const,new_fill,new_b0,ix_base_r,new_nlines);
        if (rst_n && rvalid_line)
            $display("XPREF_WRITE wptr=%0d data=%h",fifo_wptr,rdata_line);
        if (rst_n && bram_rd_pending)
            $display("XPREF_READ idx=%0d rptr_prev=%0d data=%h nlines=%0d",bram_rd_idx,fifo_rptr,fifo_dout,cur_nlines);
        if (rst_n && rreq_line && (raddr_line[2:0] != 0))
            $fatal(1,"M9XW3_FAIL unaligned line address %h",raddr_line);
        if (rst_n && cur_nlines > 5)
            $fatal(1,"M9XW3_FAIL span exceeds five lines");
        if (rst_n && inflight > 12)
            $fatal(1,"M9XW3_FAIL DDR outstanding exceeds twelve");
    end
`endif
endmodule
