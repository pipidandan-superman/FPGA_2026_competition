# t1_model_btn pins (EES-331): SW0 DIP = model-switch input.
# led_out NOT connected: U7 is occupied by ACTION_LED[6] (action_v1_pins.xdc),
# other LEDs taken (ACTION_LED[0..5], LED0/V4 = camera cfg_done) -- spec says
# the LED is optional ("找不到就不用，不硬凑"), so the port stays internal.
# Source: 4_metrics/logs/2026-10-21_t1_model_btn_run01/pin_constraints.md
# (MinerU EES-331 User Guide parse + board-proven XDC cross-check).
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33} [get_ports btn_n]
set_false_path -from [get_ports btn_n]   ;# async mechanical input, RTL 2-FF sync
