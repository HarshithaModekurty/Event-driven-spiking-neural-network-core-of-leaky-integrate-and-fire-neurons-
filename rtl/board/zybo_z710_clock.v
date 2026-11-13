// Zybo Z7 external PHY clock: 125 MHz at K17 -> 100 MHz PL system clock.
module zybo_z710_clock(input wire sysclk,output wire clk100,output wire locked);
    wire input_clk,feedback,feedback_buffered,output_clk;
    IBUF input_buffer(.I(sysclk),.O(input_clk));
    MMCME2_BASE #(.CLKIN1_PERIOD(8.0),.DIVCLK_DIVIDE(1),.CLKFBOUT_MULT_F(8.0),
        .CLKOUT0_DIVIDE_F(10.0),.STARTUP_WAIT("FALSE")) mmcm (
        .CLKIN1(input_clk),.CLKFBIN(feedback_buffered),.CLKFBOUT(feedback),
        .CLKOUT0(output_clk),.LOCKED(locked),.RST(1'b0),.PWRDWN(1'b0),
        .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
        .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
    BUFG feedback_buffer(.I(feedback),.O(feedback_buffered));
    BUFG output_buffer(.I(output_clk),.O(clk100));
endmodule
