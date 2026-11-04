# DX-BT311-10C02S prep: load the J5 bench bridge bitstream.
# FPGA bridges CP2103 (J8 upper = COM4) <-> J5-31/T21 (module TX in) /
# J5-32/U21 (module RX out). PROGRAM.FILE points at the ARCHIVED bit under
# 2_fpga/1_ble_test/bit/ so a later impl_1 overwrite can never lose it.
# Board must be in JTAG boot mode (no Linux; ping/SSH dead = expected).
# Power iron rule: power switch first, J8 USB last; J8 out first on shutdown.
# Usage: vivado -mode batch -source dxbt311_jtag_load_j5.tcl
open_hw_manager
connect_hw_server
set ts [get_hw_targets]
puts "TARGETS: $ts"
if {[llength $ts] == 0} { puts "NO_HW_TARGET"; exit 1 }
current_hw_target [lindex $ts 0]
open_hw_target
set ds [get_hw_devices]
puts "DEVICES: $ds"
if {[llength $ds] == 0} { puts "NO_HW_DEVICE"; exit 1 }
# select the FPGA (xc7z...), not the ARM DAP (chain order varies)
set fpga_dev ""
foreach d $ds { if {[string match "xc7z*" $d]} { set fpga_dev $d } }
if { $fpga_dev == "" } { puts "NO_XC7Z_DEVICE"; exit 1 }
current_hw_device $fpga_dev
puts "SELECTED: $fpga_dev"
# this design carries no ILA: clear stale probe files per 09-12 canon
catch { set_property PROBES.FILE {} [current_hw_device] }
catch { set_property FULL_PROBES.FILE {} [current_hw_device] }
set_property PROGRAM.FILE {E:/competition/2_fpga/1_ble_test/bit/ble_uart_debug_top_j5_20261005.bit} [current_hw_device]
program_hw_devices [current_hw_device]
puts "JTAG_LOAD_DONE"
exit
