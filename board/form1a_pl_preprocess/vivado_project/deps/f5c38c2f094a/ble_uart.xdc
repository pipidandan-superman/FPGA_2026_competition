#--------------------------------------------------------------------
# ble_uart.xdc - BLE (MLT-BT05 family) bridge pins, cam_hdmi_pc_ble
# Pinout per board-proven 09-12 bridge canon:
#   bt_uart_rxd  Y13  in  MLT BT_TX -> FPGA
#   bt_uart_txd  AA13 out FPGA -> MLT BT_RX
#   bt_power_en  U14  out active high
#   bt_reset_n   H15  out active low
# Outputs: DRIVE 8 / SLEW SLOW; slow UART lines, no timing budget.
#--------------------------------------------------------------------

# UART RX from module (sampled by 2-flop ASYNC_REG synchronizer)
set_property PACKAGE_PIN Y13 [get_ports bt_uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports bt_uart_rxd]

# UART TX to module
set_property PACKAGE_PIN AA13 [get_ports bt_uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports bt_uart_txd]
set_property DRIVE 8 [get_ports bt_uart_txd]
set_property SLEW SLOW [get_ports bt_uart_txd]

# module power enable, active high
set_property PACKAGE_PIN U14 [get_ports bt_power_en]
set_property IOSTANDARD LVCMOS33 [get_ports bt_power_en]
set_property DRIVE 8 [get_ports bt_power_en]
set_property SLEW SLOW [get_ports bt_power_en]

# module reset, active low
set_property PACKAGE_PIN H15 [get_ports bt_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports bt_reset_n]
set_property DRIVE 8 [get_ports bt_reset_n]
set_property SLEW SLOW [get_ports bt_reset_n]

# no timing budget on the BLE side (canon from 09-12 bridge)
set_false_path -from [get_ports bt_uart_rxd]
set_false_path -to [get_ports {bt_uart_txd bt_power_en bt_reset_n}]
