# Y15 hardware-master variant load. PROGRAM.FILE points at the ARCHIVED bit
# under 2_fpga/1_ble_test/bit/ (impl_1 gets clobbered by future builds).
# This bitstream holds BT_MASTER_EN (Y15 -> BT socket B1-28 P0_6) HIGH:
# the U14 power cycle at reconfiguration boots the module straight into
# hardware-master transparent mode with AT+BAND autoconnect.
# Usage: vivado -mode batch -source y15_jtag_load_master.tcl
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
set_property PROGRAM.FILE {E:/competition/2_fpga/1_ble_test/bit/ble_uart_debug_master_top_y15_20261005.bit} [current_hw_device]
program_hw_devices [current_hw_device]
puts "JTAG_LOAD_DONE"
exit
