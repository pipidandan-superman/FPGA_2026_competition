# JTAG fallback load of the BLE bridge bitstream (runs entirely from the PC
# through the FT2232 adapter; no board kernel / fpga_manager involvement).
# Usage: vivado -mode batch -source b1_jtag_load.tcl
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
set_property PROGRAM.FILE {E:/competition/2_fpga/1_ble_test/proj/ble_uart_debug_vivado_2025_2/ble_uart_debug_vivado_2025_2.runs/impl_1/ble_uart_debug_top.bit} [current_hw_device]
program_hw_devices [current_hw_device]
puts "JTAG_LOAD_DONE"
exit
