// Registered implementation context; not a board clock/reset/pin wrapper.
module lif_rv32_timing_harness (input wire clk,output reg [36:0] observed=0);
    wire core_clk;
    BUFG core_clock_buffer (.I(clk),.O(core_clk));
    (* DONT_TOUCH="true" *) reg [7:0] reset_pattern=8'h5a;
    wire trap,fault,busy,tick_done,frame_done;
    wire [31:0] result;
    always @(posedge core_clk) begin
        reset_pattern<={reset_pattern[6:0],reset_pattern[7]^reset_pattern[5]^reset_pattern[4]^reset_pattern[3]};
        observed<={result,trap,fault,busy,tick_done,frame_done};
    end
    (* KEEP_HIERARCHY="yes" *) lif_rv32_soc #(.BOOT_FILE("build/rv32_mnist/firmware.hex")) soc (
        .clk(core_clk),.resetn(reset_pattern[0]),.cpu_trap(trap),.bus_fault(fault),
        .software_result(result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done));
endmodule
