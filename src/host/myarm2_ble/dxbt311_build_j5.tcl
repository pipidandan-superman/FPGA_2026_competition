# DX-BT311-10C02S prep: rebuild the J5 bench bridge bitstream and archive it.
# NON-PROJECT mode on purpose: reads RTL + the j5at09 XDC directly, never opens
# the shared .xpr (an uncommitted Codex session owns rebuild_20261005/ and the
# project state; we must not disturb it). The 10-04 19:31 J5 bit was never
# archived and impl_1 has since been overwritten by the Y15 builds, so this
# rebuild restores the asset ahead of module arrival.
# Usage: vivado -mode batch -source dxbt311_build_j5.tcl
set rtl "E:/competition/2_fpga/1_ble_test/rtl"
set out_bit "E:/competition/2_fpga/1_ble_test/bit/ble_uart_debug_top_j5_20261005.bit"
set evd "E:/competition/4_metrics/logs/2026-10-05_dxbt311_prep_run01"

read_verilog [list \
    "$rtl/uart_rx.v" \
    "$rtl/uart_tx.v" \
    "$rtl/ble_uart_debug_top.v" \
]
read_xdc "$rtl/ees331_ble_uart_debug_j5at09.xdc"

synth_design -top ble_uart_debug_top -part xc7z020clg484-1
opt_design
place_design
route_design

report_timing_summary -delay_type min_max -max_paths 10 \
    -file "$evd/j5_timing_summary_routed.rpt"
report_drc -file "$evd/j5_drc.rpt"

set setup_paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_paths  [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set fh [open "$evd/j5_build_summary.txt" w]
puts $fh "TOP=ble_uart_debug_top"
puts $fh "XDC=ees331_ble_uart_debug_j5at09.xdc (J5-31/T21 in, J5-32/U21 out)"
if {[llength $setup_paths] > 0} { puts $fh "WNS=[get_property SLACK $setup_paths]" }
if {[llength $hold_paths]  > 0} { puts $fh "WHS=[get_property SLACK $hold_paths]" }
close $fh

write_bitstream -file $out_bit
puts "DXBT311_J5_BUILD_PASS bit=$out_bit"
exit
