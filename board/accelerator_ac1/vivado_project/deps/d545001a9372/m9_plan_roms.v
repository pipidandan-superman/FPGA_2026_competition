/************************************************************************
 * File Name       : m9_plan_roms.v
 * Developer       : M9 intra-layer pipeline line
 * Date            : 2026-10-09
 * Project Name    : YOLO object accel (replan 2026-10-05 section 13, M9)
 * Module Name     : m9_plan_roms
 * Description     :
 *   M9.5c plan ROM bank: the six golden94 plan faces, bitstream-baked
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
 * Dependencies    : m9_bm_{pctl,strip,lut,iss,geo,wlay} (proj IPs)
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
 ***********************************************************************/
`timescale 1ns / 1ps

module m9_plan_roms (
    input  wire        clk        ,
    // ---- pctl face (96b x 4096; r10: 25 convs, 128 rows/slot) ----
    input  wire [11:0] pctl_addr  ,
    output wire [95:0] pctl_data  ,
    // ---- strip face (21b x 512; r10: 16 rows/slot) ----
    input  wire [8:0]  strip_addr ,
    output wire [20:0] strip_data ,
    // ---- lut face (8b x 8192; r10: 256 rows/slot) ----
    input  wire [12:0] lut_addr   ,
    output wire [7:0]  lut_data   ,
    // ---- conv-constant faces (32 deep) ----
    input  wire [4:0]  cv_addr    ,
    output wire [255:0] cv_iss    ,
    output wire [105:0] cv_geo    ,
    output wire [167:0] cv_wlay
);

    m9_bm_pctl u_pctl (
        .clka  (clk),
        .ena   (1'b1),
        .addra (pctl_addr),
        .douta (pctl_data)
    );

    m9_bm_strip u_strip (
        .clka  (clk),
        .ena   (1'b1),
        .addra (strip_addr),
        .douta (strip_data)
    );

    m9_bm_lut u_lut (
        .clka  (clk),
        .ena   (1'b1),
        .addra (lut_addr),
        .douta (lut_data)
    );

    m9_bm_iss u_iss (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr),
        .douta (cv_iss)
    );

    m9_bm_geo u_geo (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr),
        .douta (cv_geo)
    );

    m9_bm_wlay u_wlay (
        .clka  (clk),
        .ena   (1'b1),
        .addra (cv_addr),
        .douta (cv_wlay)
    );

endmodule
