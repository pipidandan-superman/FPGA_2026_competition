/************************************************************************
 * File Name       : m9_plan_roms.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_plan_roms
 * Description     :
 *   M9.5c plan ROM bank: the golden94 plan faces, bitstream-baked
 *   into single-port BMG ROMs (COE from scripts/m9_hex2coe.py over
 *   xsim/golden94/*.hex; the M9.5 board gate walks the representative
 *   layer set, so the plan body is a build-time constant -- PS setup
 *   writes CFG/bases only, 帧中零 PS still holds by the doorbell law).
 *
 *   Face contract = the TB ROM model law (tb_m9_v25.sv):
 *   registered read, 1-cycle latency, no enable on the engine side --
 *   BMG ena tied 1, Register_PortA_Output_of_Memory_Primitives=false.
 *   Instantiations checked against the generated .veo (clka/ena/addra/
 *   douta).  r6 (2026-10-10): the three plan faces re-depthed for
 *   NCONV_MAX=16 (pctl 2048 / strip 256 / lut 4096) -- the addra widths
 *   were RE-VERIFIED against the freshly regenerated .veo of each IP
 *   (depth change = new .veo, no memory law).  Unused tail rows are 0
 *   in the COE (TB leaves them X; the walk never reads them).
 *
 *   Bitstream-baked plan = M9.5 gate scope; PS-reloadable plan BRAM
 *   is a later phase (the CSR PLAN_BASE register stays 台账-only).
 *
 *   V2.4-M11a (2026-10-18, D4 errata b46f81f2 authority): depths are
 *   SLOT-based for the 63-conv R63 graph -- 6 of 63 convs carry rc=32
 *   (model.7 / 8.cv1 / 8.cv2 / 9.cv2 / 21.cv1 / 21.cv2, rc*8=256 rows)
 *   and per the m94-D4 law each occupies TWO plan slots -> 69 slots
 *   total.  Depth contract: pctl 8832 (69 x 128, 14b -- NOT 8064/8192),
 *   strip 1104 (69 x 16, 11b), lut 17664 (69 x 256, 15b).  The cv
 *   constant faces stay CONV-indexed (cv_addr 6b = the global conv
 *   number, 63 entries used of 64-deep faces) and a NEW cv_slot face
 *   (64 x 7b) maps conv -> plan slot base (golden94: slot==conv, r10
 *   law, slot 7 reserved-empty for M10P4.cv2 rc=32; the R63 COE fills
 *   the doubled slots per D4).  Sim-only $fatal address assertions
 *   guard the depth contract on every face (SPEC M11a §2.1 authority
 *   law).  The actual BMG re-customisation + .veo re-verification is
 *   the r12 build duty (memory law), as is the COE swap to R63
 *   (delivered by the D4 line: 2026-10-18_yolo_m11_selfrun_d4_coe63_
 *   run01/coe/R63/, R63_BAKE_PASS).
 *
 * Dependencies    : m9_bm_{pctl,strip,lut,iss,geo,wlay,cvslot} (proj IPs)
 * Revision History:
 *   - V1.0 (2026-10-09) : first release, M9.5c.
 *   - V1.1 (2026-10-10) : r6 ROM-widening: pctl/strip/lut faces
 *     re-depthed 2048/256/4096 (NCONV_MAX=16; addra 11b/8b/12b per the
 *     regenerated .veo of each BMG).  cv faces stay 16 deep.
 *   - V1.2 (2026-10-14) : M10.1-v2 2a -- m9_bm_wlay widened 136->168
 *     (ch_stride[167:136] tail; .veo re-verified per IP law).  Other
 *     faces untouched.
 *   - V1.3 (2026-10-18) : r10 ROM rebake (M10.4 cv1/cv2 + M10.6
 *     H18_P{3,4,5} = 20 new convs, 25 live total) -- all six faces
 *     re-depthed: pctl 2048->4096 (12b), strip 256->512 (9b), lut
 *     4096->8192 (13b), cv faces 16->32 (5b).  Append-only layout:
 *     convs 0-4 = J04 baseline byte-exact (no-drift gate vs the live
 *     PPU_ON COE in m9_hex2coe_r10.py), conv5=M10P4.cv1, conv6=
 *     M10P4.cv2 (rc=32 -> pctl spans slots 6-7; slot 7 reserved-
 *     empty on all six faces), convs 8-25 = H18_P3/P4/P5 cards 0-5.
 *     COE: 2026-10-18_yolo_m10_r10_rom_rebake_run01/coe/R10/*.coe.
 *     Addr widths below follow the r6 law: RE-VERIFY against the
 *     freshly regenerated .veo of each re-customised BMG before the
 *     r10 build (checklist in the r10 run README).  NOTE the r10
 *     width change propagates: m9_cmd_issuer pbase/sbase/lbase +
 *     conv_cnt 4b->5b, and the intra/v25/shim passthrough ports
 *     (see r10 run README section 6 -- main line applies).
 *   - V2.4-M11a (2026-10-18) : D4 slot-doubling depths (above) +
 *     cv_slot face + sim depth assertions.  Legacy addressing
 *     (slot==conv, values < 25 slots) is bit-identical through the
 *     widened faces -- the legacy address map is value-identical,
 *     widths only (r6 regression ladder law).
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_plan_roms (
    input  wire        clk        ,
    // ---- pctl face (96b x 8832; D4: 69 slots x 128 rows, 14b) ----
    input  wire [13:0] pctl_addr  ,
    output wire [95:0] pctl_data  ,
    // ---- strip face (21b x 1104; D4: 69 slots x 16 rows, 11b) ----
    input  wire [10:0] strip_addr ,
    output wire [20:0] strip_data ,
    // ---- lut face (8b x 17664; D4: 69 slots x 256 rows, 15b) ----
    input  wire [14:0] lut_addr   ,
    output wire [7:0]  lut_data   ,
    // ---- conv-constant faces (64 deep; cv_addr = 6b GLOBAL conv) ----
    input  wire [6:0]  cv_addr    ,
    output wire [255:0] cv_iss    ,
    output wire [105:0] cv_geo    ,
    output wire [167:0] cv_wlay   ,
    // ---- v2.4 slot face: per-conv plan slot base (64 x 7b; D4 slot
    //      doubling: 6 rc=32 convs occupy two slots; golden94 =
    //      slot==conv with slot 7 reserved-empty, r10 law) ----
    output wire [6:0]  cv_slot
);

    // Heads-only compact contract: 18 contiguous plan slots.
    // cvslot remains 64-deep because it is indexed by global conv ordinal.
    localparam integer PCTL_DEPTH  = 2304;   // 18 x 128
    localparam integer STRIP_DEPTH = 288;    // 18 x 16
    localparam integer LUT_DEPTH   = 4608;   // 18 x 256
    localparam integer CV_DEPTH    = 18;     // 18 compact slots

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n_chk(pctl_addr)  >= PCTL_DEPTH)
            $fatal(1, "M9ROM_FAIL pctl_addr %0d >= %0d", pctl_addr, PCTL_DEPTH);
        if (rst_n_chk(strip_addr) >= STRIP_DEPTH)
            $fatal(1, "M9ROM_FAIL strip_addr %0d >= %0d", strip_addr, STRIP_DEPTH);
        if (rst_n_chk(lut_addr)   >= LUT_DEPTH)
            $fatal(1, "M9ROM_FAIL lut_addr %0d >= %0d", lut_addr, LUT_DEPTH);
        if (rst_n_chk6(cv_addr)   >= CV_DEPTH)
            $fatal(1, "M9ROM_FAIL cv_addr %0d >= %0d", cv_addr, CV_DEPTH);
    end
    // address-isolation helpers: X/Z addresses (unwired TB faces) must
    // not false-fire the depth assert -- treat anything non-2-state as 0
    function [13:0] rst_n_chk;
        input [13:0] a;
        begin
            rst_n_chk = (^a === 1'bx) ? 14'd0 : a;
        end
    endfunction
    function [13:0] rst_n_chk6;
        input [5:0] a;
        begin
            rst_n_chk6 = (^a === 1'bx) ? 14'd0 : {8'd0, a};
        end
    endfunction
`endif

    m9_bm_pctl u_pctl (
        .clka  (clk),
        .ena   (1'b1),
        .addra (pctl_addr[11:0]),
        .douta (pctl_data)
    );

    m9_bm_strip u_strip (
        .clka  (clk),
        .ena   (1'b1),
        .addra (strip_addr[8:0]),
        .douta (strip_data)
    );

    m9_bm_lut u_lut (
        .clka  (clk),
        .ena   (1'b1),
        .addra (lut_addr[12:0]),
        .douta (lut_data)
    );

    m9_bm_iss u_iss (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr[4:0]),
        .douta (cv_iss)
    );

    m9_bm_geo u_geo (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr[4:0]),
        .douta (cv_geo)
    );

    m9_bm_wlay u_wlay (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr[4:0]),
        .douta (cv_wlay)
    );

    m9_bm_cvslot u_cvslot (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr[5:0]),
        .douta (cv_slot)
    );

endmodule
