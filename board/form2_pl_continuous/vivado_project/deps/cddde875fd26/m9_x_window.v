/************************************************************************
 * File Name       : m9_x_window.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-08
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_x_window
 * Description     :
 *   Per-block X-window beat generator -- the RTL embodiment of the
 *   frozen three-beat law (02_m9_issuer_spec.md section 3, proven
 *   byte-exact against pl_m3.pack_tile by M9_BEAT_REF_PASS, and the
 *   law itself is the V2.4 board-green packer):
 *
 *     iy[k]     = sh*oy + kKH[k] - ph            (all 16 lanes share)
 *     ix[k][n]  = sw*(16*s + n) + kKW[k] - pw    (n = 0..15)
 *     inb       = 0<=iy<H & 0<=ix<W & (fetch ? 1 : n<vc)
 *     xb[k][n]  = inb ? X[kIC, clip(iy), clip(ix)]
 *                     : (first ? 0x80 : 0x00)    (pad fill)
 *     fill law  : xb[k][n>=vc] = 0xA5 sentinel   (masked lanes)
 *
 *   Output: per k two 64b beats, data[8n+:8]=xb[n]:
 *     X lo beat : x_hi=0 lanes 0..7
 *     X hi beat : x_hi=1 lanes 8..15, last=(k==K-1)
 *
 *   M9.1 correctness-first byte-read port (one lane byte per request,
 *   constant lanes skip the read).  Row buffering / burst reshaping for
 *   HP efficiency is an M9.3 concern and must not change the beat law.
 *
 *   Config (per conv, held) vs runtime (per block, latched on start):
 *   deliberately split so the cmd_issuer may preload geometry once.
 *
 *   M9.4 k-seed law: a K-chain segment starts at global tap k_cum which
 *   is NOT channel-aligned for 3x3 convs (1024 = 113*9 + 7); the x
 *   window's k decomposition (kIC,kKH,kKW) must be SEEDED per segment
 *   (rt_koff_*) instead of restarted from zero.  cnt_k stays
 *   segment-local (the x_beat_last flag compares against segment k).
 *   Seeds are PC-precomputed in the conv table (no RTL division).
 *
 * Dependencies    : none (pure RTL)
 * Revision History:
 *   - V1.0 (2026-10-08) : first release, M9.1 gate run01.
 *   - V1.1 (2026-10-09) : M9.4 rt_koff_ic/kh/kw seed inputs (K-chain
 *     segments mid-channel start); beat law unchanged.
 *   - V1.2 (2026-10-09) : M9.5 timing closure at 100 MHz -- the tap
 *     address math (ch_off mult || iy mult->clip->row mult merged with
 *     ix mult into xaddr) was a 23-level / 20.7 ns cone.  Pipelined at
 *     the tap boundary: ST_ADDR1/2/3 stage ch_off/iy_v/clip and the
 *     row-base merge; ix narrowed to 16-bit with a per-tap registered
 *     base (sw*16s + kw - pw) so the per-lane cone is a 4x4 mult +
 *     compare.  Address VALUES identical; +3 cycles per tap (internal
 *     only -- byte stream, beats and CSR counts unchanged).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_x_window (
    input  wire        clk           ,
    input  wire        rst_n         ,
    // ---- per-conv geometry config (issuer writes while idle) ----
    input  wire [15:0] cfg_ic        ,   // input channels
    input  wire [15:0] cfg_h         ,   // input plane H
    input  wire [15:0] cfg_w         ,   // input plane W
    input  wire [3:0]  cfg_kh        ,
    input  wire [3:0]  cfg_kw        ,
    input  wire [3:0]  cfg_sh        ,
    input  wire [3:0]  cfg_sw        ,
    input  wire [3:0]  cfg_ph        ,
    input  wire [3:0]  cfg_pw        ,
    input  wire        cfg_first      ,   // pad = -128 only for stem
    input  wire        cfg_law_fetch  ,   // 0='fill'(default) 1='fetch'
    input  wire [31:0] cfg_xbase      ,   // in_buf base (arena byte addr)
    // ---- per-block runtime (latched on start) ----
    input  wire [9:0]  rt_oy         ,
    input  wire [3:0]  rt_s          ,
    input  wire [10:0] rt_k          ,   // segment k count (<=1024)
    input  wire [4:0]  rt_vc         ,   // strip vc (16 or less)
    input  wire [15:0] rt_koff_ic    ,   // M9.4: segment k-seed kIC
    input  wire [3:0]  rt_koff_kh    ,   // M9.4: segment k-seed kKH
    input  wire [3:0]  rt_koff_kw    ,   // M9.4: segment k-seed kKW
    input  wire        start         ,
    output wire        busy          ,
    output wire        done          ,
    // ---- X byte read port (M9.1: byte granularity, any latency) ----
    output reg  [31:0] xaddr         ,
    output reg         xreq          ,
    input  wire [7:0]  xdata         ,
    input  wire        xvalid        ,
    // ---- X beat outlet (to m9_ld_mux) ----
    output reg  [63:0] x_beat_data   ,
    output reg         x_beat_hi     ,   // 0=lo lanes 0..7, 1=hi 8..15
    output reg         x_beat_last   ,   // (k==K-1) on the hi beat
    output reg         x_beat_valid  ,
    input  wire        x_beat_ready
);

    // ---------------- FSM ----------------
    localparam ST_IDLE = 3'd0,
               ST_LANE = 3'd1,     // walk n=0..15, fetch/constant lanes
               ST_PRE_LO = 3'd2,   // present X lo beat
               ST_PRE_HI = 3'd3,   // present X hi beat
               ST_DONE  = 3'd4,
               ST_ADDR1 = 3'd5,    // tap address stage 1 (V1.2)
               ST_ADDR2 = 3'd6,    // tap address stage 2
               ST_ADDR3 = 3'd7;    // tap address stage 3
    reg [2:0]  st, st_nx;

    // per-conv derived
    reg  [31:0] hw_prod_r;                          // channel byte stride
    wire [7:0]  pad_val = cfg_first ? 8'h80 : 8'h00;

    // k decomposition counters (natural increment, zero division)
    reg [15:0] cnt_ic;      // kIC
    reg [3:0]  cnt_kh;      // kKH
    reg [3:0]  cnt_kw;      // kKW
    reg [10:0] cnt_k;

    // lane cursor + buffers
    reg [3:0]  n_cur;
    reg [7:0]  lane_lo [0:7];
    reg [7:0]  lane_hi [0:7];

    // latched runtime
    reg [9:0]  oy_r;
    reg [3:0]  s_r;
    reg [10:0] k_r;
    reg [4:0]  vc_r;

    // tap-address pipeline regs (V1.2: written in ST_ADDR1/2/3, valid for
    // the whole lane walk of one tap; iy fixed across lanes, ix per lane)
    reg  [31:0]        ch_off_r;   // kIC * H*W            (ADDR1)
    reg  signed [31:0] iy_v_r;     // sh*oy + kKH - ph     (ADDR1)
    reg  [31:0]        iy_clip_r;  // clamp(iy_v)          (ADDR2)
    reg                iy_inb_r;   // 0<=iy_v<H            (ADDR2)
    reg  signed [15:0] ix_base_r;  // sw*16s + kKW - pw    (ADDR2)
    reg  [31:0]        base_r;     // ch_off_r + clip*W    (ADDR3)
    // per-lane inb/fill decision, precomputed for all 16 lanes at ADDR3
    // (V1.2b: keeps the live lane cone at a 16:1 mask select; the
    // expressions mirror the V1.1 wires exactly)
    reg                const_mask_r [0:15];
    reg                fill_mask_r  [0:15];
    // per-lane remainder: ix = ix_base_r + sw*n  (4x4 mult + 16b add;
    // range sw*255 + kw - pw in [-15, 3840] fits signed 16)
    wire signed [15:0] ix_v = ix_base_r + cfg_sw * {12'd0, n_cur};
    wire        lane_const = const_mask_r[n_cur];
    wire [7:0]  lane_val = fill_mask_r[n_cur] ? 8'hA5 : pad_val;

    // lane-n inb test (V1.2b mask precompute; mirrors the V1.1 wire)
    function ix_inb_l;
        input [3:0] n;
        reg signed [15:0] v;
        begin
            v = ix_base_r + cfg_sw * {12'd0, n};
            ix_inb_l = (v >= 0) && (v < cfg_w);
        end
    endfunction

    assign busy = (st != ST_IDLE);
    assign done = (st == ST_DONE);

    // ---------------- sequencer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            xreq <= 1'b0;
            x_beat_valid <= 1'b0;
            n_cur <= 4'd0;
            cnt_ic <= 16'd0; cnt_kh <= 4'd0; cnt_kw <= 4'd0; cnt_k <= 11'd0;
        end else begin
            x_beat_valid <= 1'b0;                  // default pulse
            xreq <= 1'b0;
            case (st)
            ST_IDLE: if (start) begin
                oy_r <= rt_oy; s_r <= rt_s; k_r <= rt_k; vc_r <= rt_vc;
                hw_prod_r <= cfg_h * cfg_w;
                // M9.4: seed the decomposition at the segment's global
                // tap offset (single-seg run feeds all-zero = V1.0 law)
                cnt_ic <= rt_koff_ic;
                cnt_kh <= rt_koff_kh;
                cnt_kw <= rt_koff_kw;
                cnt_k <= 11'd0; n_cur <= 4'd0;
                st <= ST_ADDR1;
            end
            // ---- tap address pipeline (V1.2): one multiply per stage --
            ST_ADDR1: begin
                ch_off_r <= cnt_ic * hw_prod_r;
                iy_v_r   <= cfg_sh * oy_r + cnt_kh - cfg_ph;
                st <= ST_ADDR2;
            end
            ST_ADDR2: begin
                iy_clip_r <= (iy_v_r < 0) ? 32'd0 :
                             (iy_v_r >= cfg_h) ? (cfg_h - 1) : iy_v_r;
                iy_inb_r  <= (iy_v_r >= 0) && (iy_v_r < cfg_h);
                ix_base_r <= cfg_sw * {s_r, 4'd0} + cnt_kw - cfg_pw;
                st <= ST_ADDR3;
            end
            ST_ADDR3: begin
                base_r <= ch_off_r + iy_clip_r * cfg_w;
                // per-lane decision masks for this tap (V1.2b)
                const_mask_r[0]  <= ~iy_inb_r | ~ix_inb_l(4'd0)  | ~cfg_law_fetch & (vc_r <= 5'd0);
                const_mask_r[1]  <= ~iy_inb_r | ~ix_inb_l(4'd1)  | ~cfg_law_fetch & (vc_r <= 5'd1);
                const_mask_r[2]  <= ~iy_inb_r | ~ix_inb_l(4'd2)  | ~cfg_law_fetch & (vc_r <= 5'd2);
                const_mask_r[3]  <= ~iy_inb_r | ~ix_inb_l(4'd3)  | ~cfg_law_fetch & (vc_r <= 5'd3);
                const_mask_r[4]  <= ~iy_inb_r | ~ix_inb_l(4'd4)  | ~cfg_law_fetch & (vc_r <= 5'd4);
                const_mask_r[5]  <= ~iy_inb_r | ~ix_inb_l(4'd5)  | ~cfg_law_fetch & (vc_r <= 5'd5);
                const_mask_r[6]  <= ~iy_inb_r | ~ix_inb_l(4'd6)  | ~cfg_law_fetch & (vc_r <= 5'd6);
                const_mask_r[7]  <= ~iy_inb_r | ~ix_inb_l(4'd7)  | ~cfg_law_fetch & (vc_r <= 5'd7);
                const_mask_r[8]  <= ~iy_inb_r | ~ix_inb_l(4'd8)  | ~cfg_law_fetch & (vc_r <= 5'd8);
                const_mask_r[9]  <= ~iy_inb_r | ~ix_inb_l(4'd9)  | ~cfg_law_fetch & (vc_r <= 5'd9);
                const_mask_r[10] <= ~iy_inb_r | ~ix_inb_l(4'd10) | ~cfg_law_fetch & (vc_r <= 5'd10);
                const_mask_r[11] <= ~iy_inb_r | ~ix_inb_l(4'd11) | ~cfg_law_fetch & (vc_r <= 5'd11);
                const_mask_r[12] <= ~iy_inb_r | ~ix_inb_l(4'd12) | ~cfg_law_fetch & (vc_r <= 5'd12);
                const_mask_r[13] <= ~iy_inb_r | ~ix_inb_l(4'd13) | ~cfg_law_fetch & (vc_r <= 5'd13);
                const_mask_r[14] <= ~iy_inb_r | ~ix_inb_l(4'd14) | ~cfg_law_fetch & (vc_r <= 5'd14);
                const_mask_r[15] <= ~iy_inb_r | ~ix_inb_l(4'd15) | ~cfg_law_fetch & (vc_r <= 5'd15);
                fill_mask_r[0]  <= ~cfg_law_fetch & (vc_r <= 5'd0);
                fill_mask_r[1]  <= ~cfg_law_fetch & (vc_r <= 5'd1);
                fill_mask_r[2]  <= ~cfg_law_fetch & (vc_r <= 5'd2);
                fill_mask_r[3]  <= ~cfg_law_fetch & (vc_r <= 5'd3);
                fill_mask_r[4]  <= ~cfg_law_fetch & (vc_r <= 5'd4);
                fill_mask_r[5]  <= ~cfg_law_fetch & (vc_r <= 5'd5);
                fill_mask_r[6]  <= ~cfg_law_fetch & (vc_r <= 5'd6);
                fill_mask_r[7]  <= ~cfg_law_fetch & (vc_r <= 5'd7);
                fill_mask_r[8]  <= ~cfg_law_fetch & (vc_r <= 5'd8);
                fill_mask_r[9]  <= ~cfg_law_fetch & (vc_r <= 5'd9);
                fill_mask_r[10] <= ~cfg_law_fetch & (vc_r <= 5'd10);
                fill_mask_r[11] <= ~cfg_law_fetch & (vc_r <= 5'd11);
                fill_mask_r[12] <= ~cfg_law_fetch & (vc_r <= 5'd12);
                fill_mask_r[13] <= ~cfg_law_fetch & (vc_r <= 5'd13);
                fill_mask_r[14] <= ~cfg_law_fetch & (vc_r <= 5'd14);
                fill_mask_r[15] <= ~cfg_law_fetch & (vc_r <= 5'd15);
                st <= ST_LANE;
            end
            ST_LANE: begin
                if (lane_const) begin
                    if (n_cur < 8) lane_lo[n_cur] <= lane_val;
                    else           lane_hi[n_cur-8] <= lane_val;
                    n_cur <= n_cur + 4'd1;
                    if (n_cur == 4'd15) st <= ST_PRE_LO;
                end else if (!xreq) begin
                    xaddr <= cfg_xbase + base_r + {{16{ix_v[15]}}, ix_v};
                    xreq  <= 1'b1;
                end else begin
                    xreq <= 1'b1;            // req 在途保持（顶默认 0 勿吞）
                    if (xvalid) begin
                        if (n_cur < 8) lane_lo[n_cur] <= xdata;
                        else           lane_hi[n_cur-8] <= xdata;
                        xreq <= 1'b0;
                        n_cur <= n_cur + 4'd1;
                        if (n_cur == 4'd15) st <= ST_PRE_LO;
                    end
                end
            end
            ST_PRE_LO: begin
                x_beat_data <= {lane_lo[7],lane_lo[6],lane_lo[5],lane_lo[4],
                                lane_lo[3],lane_lo[2],lane_lo[1],lane_lo[0]};
                x_beat_hi   <= 1'b0;
                x_beat_last <= 1'b0;
                x_beat_valid<= 1'b1;
                if (x_beat_ready) st <= ST_PRE_HI;
            end
            ST_PRE_HI: begin
                x_beat_data <= {lane_hi[7],lane_hi[6],lane_hi[5],lane_hi[4],
                                lane_hi[3],lane_hi[2],lane_hi[1],lane_hi[0]};
                x_beat_hi   <= 1'b1;
                x_beat_last <= (cnt_k == k_r - 1);
                x_beat_valid<= 1'b1;
                if (x_beat_ready) begin
                    // advance k decomposition
                    if (cnt_kw == cfg_kw - 1) begin
                        cnt_kw <= 4'd0;
                        if (cnt_kh == cfg_kh - 1) begin
                            cnt_kh <= 4'd0;
                            cnt_ic <= cnt_ic + 16'd1;
                        end else
                            cnt_kh <= cnt_kh + 4'd1;
                    end else
                        cnt_kw <= cnt_kw + 4'd1;
                    cnt_k <= cnt_k + 11'd1;
                    n_cur <= 4'd0;
                    if (cnt_k == k_r - 1) st <= ST_DONE;
                    else                  st <= ST_ADDR1;
                end
            end
            ST_DONE: st <= ST_IDLE;               // done is a 1-cycle pulse
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
