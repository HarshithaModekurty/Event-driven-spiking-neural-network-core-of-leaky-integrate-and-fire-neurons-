// Timing-only registered context for the AER wrapper; not functional stimulus.
module lif_aer_timing_harness (input wire clk, output reg [305:0] observed = 0);
    wire core_clk;
    BUFG core_clock_buffer (.I(clk), .O(core_clk));
    (* DONT_TOUCH = "true" *) reg [124:0] launch_data = 1;
    wire [3:0] in_ack;
    wire [0:0] out_req;
    wire [7:0] out_addr;
    wire [0:0] out_end;
    wire [0:0] weight_ready;
    wire [0:0] busy;
    wire [0:0] tick_done;
    wire [0:0] frame_done;
    wire [255:0] spike_vector;
    wire [15:0] state_read_membrane;
    wire [15:0] state_read_refractory;
    always @(posedge core_clk) begin
        launch_data <= {launch_data[123:0], launch_data[124] ^ launch_data[122] ^ launch_data[119] ^ launch_data[116]};
        observed <= {in_ack, out_req, out_addr, out_end, weight_ready, busy, tick_done, frame_done, spike_vector, state_read_membrane, state_read_refractory};
    end
    (* KEEP_HIERARCHY = "yes" *) lif_aer_snn_core core (
        .clk(core_clk),
        .rst(launch_data[0]),
        .in_req(launch_data[4:1]),
        .in_addr(launch_data[36:5]),
        .in_end(launch_data[40:37]),
        .out_ack(launch_data[41]),
        .weight_write(launch_data[42]),
        .weight_source_addr(launch_data[50:43]),
        .weight_destination_addr(launch_data[58:51]),
        .weight_data(launch_data[62:59]),
        .threshold(launch_data[78:63]),
        .reset_value(launch_data[94:79]),
        .leak_enable(launch_data[95]),
        .leak_shift(launch_data[100:96]),
        .refractory_period(launch_data[116:101]),
        .state_read_addr(launch_data[124:117]),
        .in_ack(in_ack),
        .out_req(out_req),
        .out_addr(out_addr),
        .out_end(out_end),
        .weight_ready(weight_ready),
        .busy(busy),
        .tick_done(tick_done),
        .frame_done(frame_done),
        .spike_vector(spike_vector),
        .state_read_membrane(state_read_membrane),
        .state_read_refractory(state_read_refractory)
    );
endmodule
