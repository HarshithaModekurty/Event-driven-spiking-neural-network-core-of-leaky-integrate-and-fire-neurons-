# The integrating design supplies a global clock buffer at this assumed site.
# Used only for out-of-context placement/routing; not a board pin assignment.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
