// Timing-only registered context, not a functional stimulus or SoC top.
// Preserve every core input/output; no classifier weights or mapping changes.
module lif_core_timing_harness (input wire clk, output reg [289:0] observed = 0);
    wire core_clk;
    BUFG core_clock_buffer (.I(clk), .O(core_clk));
    (* DONT_TOUCH = "true" *) reg [340:0] launch_data = 341'h1;
    wire [15:0] membrane, refractory;
    wire [255:0] spikes;
    wire busy, done;
    always @(posedge core_clk) begin
        launch_data <= {launch_data[339:0], launch_data[340] ^ launch_data[338] ^ launch_data[335] ^ launch_data[332]};
        observed <= {membrane, refractory, spikes, busy, done};
    end
    (* KEEP_HIERARCHY = "yes" *) lif_snn_core core (
        .clk(core_clk),
        .rst(launch_data[0]),
        .step_start(launch_data[1]),
        .input_spikes(launch_data[257:2]),
        .weight_write(launch_data[258]),
        .weight_source_addr(launch_data[266:259]),
        .weight_destination_addr(launch_data[274:267]),
        .weight_data(launch_data[278:275]),
        .threshold(launch_data[294:279]),
        .reset_value(launch_data[310:295]),
        .leak_enable(launch_data[311]),
        .leak_shift(launch_data[316:312]),
        .refractory_period(launch_data[332:317]),
        .state_read_addr(launch_data[340:333]),
        .state_read_membrane(membrane), .state_read_refractory(refractory),
        .spike_vector(spikes), .busy(busy), .done(done)
    );
endmodule
