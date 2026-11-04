#--------------------------------------------------------------------
# ble_uart.xdc - two-wire BLE UART on EES-331 expansion connector J5
#   bt_uart_rxd  V13  input   module TX -> FPGA RX
#   bt_uart_txd  W13  output  FPGA TX -> module RX
# UART: 9600 baud, 8N1, no flow control (ble_csr reset divisor = 5208).
# The module is externally powered and reset; no FPGA power/reset pins.
#--------------------------------------------------------------------

set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports bt_uart_rxd]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports bt_uart_txd]

# Asynchronous UART input is synchronized by two ASYNC_REG flops in RTL.
set_false_path -from [get_ports bt_uart_rxd]
set_false_path -to [get_ports bt_uart_txd]
