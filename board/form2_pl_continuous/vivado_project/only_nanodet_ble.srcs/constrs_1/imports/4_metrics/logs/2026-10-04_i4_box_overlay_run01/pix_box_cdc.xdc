# pix_frame_display V2.0 box-coordinate CDC constraint.
# Crossing: aclk (FCLK0, 50 MHz) register bank -> vio_clk (25 MHz pixel)
# 2-FF sync stage (box_*_s0_reg). Coordinates are quasi-static, written by
# the PS under the box_en protocol (clear en -> write coords -> set en);
# the pixel-domain consumer latches them at the first active pixel of each
# frame, so a torn multi-bit sample can never reach the drawn rectangle.
# False-path the single crossing point; the 2-FF stage protects it.
# NOTE: module_ref cells gain an IP-wrapper "inst" hierarchy level in the
# netlist (pix_frame_display_0/inst/box_l_s0_reg), so the pattern must not
# pin the register directly under pix_frame_display_0 (run4 evidence:
# Vivado 12-4739 no-match when the slash form was used).
set_false_path -to [get_cells -hierarchical -filter {NAME =~ "*pix_frame_display_0*box_*_s0_reg*"}]
