# Pin source: Digilent/digilent-xdc Zybo-Z7-Master.xdc (Z7-10 pins only).
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -name sysclk125 -period 8.000 [get_ports sysclk]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports led6_r]
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33} [get_ports led6_g]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports led6_b]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports eth_rst_b]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports pmod_uart_tx]
set_property SLEW SLOW [get_ports {led[*] led6_r led6_g led6_b eth_rst_b pmod_uart_tx}]
# Applied after synthesis so each exception can require its exact endpoint.
# No exception here changes an internal SNN/CPU setup or hold requirement.
