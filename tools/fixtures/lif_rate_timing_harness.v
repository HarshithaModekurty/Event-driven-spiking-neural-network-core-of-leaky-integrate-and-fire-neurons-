// Timing-only registered host context for the rate/AER/SNN top.
module lif_rate_timing_harness (input wire clk, output reg [304:0] observed=0);
    wire core_clk;
    BUFG core_clock_buffer (.I(clk),.O(core_clk));
    (* DONT_TOUCH="true" *) reg [103:0] launch_data=1;
    wire [0:0] clear_ready;
    wire [0:0] intensity_ready;
    wire [0:0] tick_ready;
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
        launch_data <= {launch_data[102:0],launch_data[103]^launch_data[101]^launch_data[98]^launch_data[95]};
        observed <= {clear_ready, intensity_ready, tick_ready, out_req, out_addr, out_end, weight_ready, busy, tick_done, frame_done, spike_vector, state_read_membrane, state_read_refractory};
    end
    (* KEEP_HIERARCHY="yes" *) lif_rate_aer_snn_core core (
        .clk(core_clk),
        .rst(launch_data[0]),
        .sample_clear(launch_data[1]),
        .intensity_write(launch_data[2]),
        .intensity_addr(launch_data[10:3]),
        .intensity_data(launch_data[18:11]),
        .tick_start(launch_data[19]),
        .out_ack(launch_data[20]),
        .weight_write(launch_data[21]),
        .weight_source_addr(launch_data[29:22]),
        .weight_destination_addr(launch_data[37:30]),
        .weight_data(launch_data[41:38]),
        .threshold(launch_data[57:42]),
        .reset_value(launch_data[73:58]),
        .leak_enable(launch_data[74]),
        .leak_shift(launch_data[79:75]),
        .refractory_period(launch_data[95:80]),
        .state_read_addr(launch_data[103:96]),
        .clear_ready(clear_ready),
        .intensity_ready(intensity_ready),
        .tick_ready(tick_ready),
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
