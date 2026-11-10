module lif_snn_core #(
    parameter NUM_NEURONS = 256,
    parameter ADDR_WIDTH = 8,
    parameter NUM_SOURCES = NUM_NEURONS,
    parameter SOURCE_ADDR_WIDTH = ADDR_WIDTH,
    parameter RECURRENT_SOURCE_BASE = 0
) (
    input wire clk,
    input wire rst,
    input wire step_start,
    input wire [NUM_SOURCES-1:0] input_spikes,
    input wire weight_write,
    input wire [SOURCE_ADDR_WIDTH-1:0] weight_source_addr,
    input wire [ADDR_WIDTH-1:0] weight_destination_addr,
    input wire signed [3:0] weight_data,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    input wire [ADDR_WIDTH-1:0] state_read_addr,
    output wire [15:0] state_read_membrane,
    output wire [15:0] state_read_refractory,
    output wire [NUM_NEURONS-1:0] spike_vector,
    output wire busy,
    output wire done
);

    localparam CORE_IDLE = 2'd0;
    localparam CORE_ROUTE = 2'd1;
    localparam CORE_LAUNCH_NEURONS = 2'd2;
    localparam CORE_UPDATE_NEURONS = 2'd3;

    reg [1:0] core_state;
    reg [NUM_NEURONS-1:0] previous_spikes;

    wire [NUM_SOURCES-1:0] routed_sources;
    wire route_start;
    wire route_current_valid;
    wire [ADDR_WIDTH-1:0] route_destination;
    wire signed [31:0] route_current;
    wire route_busy;
    wire route_done;
    wire population_start;
    wire population_busy;
    wire population_done;

    // Map stored neurons back into the source namespace. Defaults preserve
    // the square recurrent network; the PS classifier uses states 246..255.
    assign routed_sources = input_spikes |
        ({{(NUM_SOURCES-NUM_NEURONS){1'b0}}, previous_spikes} << RECURRENT_SOURCE_BASE);
    assign route_start = (core_state == CORE_IDLE) && step_start;
    assign population_start = (core_state == CORE_LAUNCH_NEURONS);
    assign busy = (core_state != CORE_IDLE);
    assign done = population_done;

    lif_synapse_router #(
        .NUM_NEURONS(NUM_NEURONS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_SOURCES(NUM_SOURCES),
        .SOURCE_ADDR_WIDTH(SOURCE_ADDR_WIDTH)
    ) synapse_router (
        .clk(clk),
        .rst(rst),
        .weight_write(weight_write),
        .weight_source_addr(weight_source_addr),
        .weight_destination_addr(weight_destination_addr),
        .weight_data(weight_data),
        .route_start(route_start),
        .source_spikes(routed_sources),
        .current_valid(route_current_valid),
        .current_destination(route_destination),
        .current_value(route_current),
        .busy(route_busy),
        .done(route_done)
    );

    lif_population_stepper #(
        .NUM_NEURONS(NUM_NEURONS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) population_stepper (
        .clk(clk),
        .rst(rst),
        .start(population_start),
        .current_write(route_current_valid),
        .current_addr(route_destination),
        .current_data(route_current),
        .threshold(threshold),
        .reset_value(reset_value),
        .leak_enable(leak_enable),
        .leak_shift(leak_shift),
        .refractory_period(refractory_period),
        .state_read_addr(state_read_addr),
        .state_read_membrane(state_read_membrane),
        .state_read_refractory(state_read_refractory),
        .spike_vector(spike_vector),
        .busy(population_busy),
        .done(population_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            core_state <= CORE_IDLE;
            previous_spikes <= {NUM_NEURONS{1'b0}};
        end else begin
            case (core_state)
                CORE_IDLE: begin
                    if (step_start) begin
                        core_state <= CORE_ROUTE;
                    end
                end
                CORE_ROUTE: begin
                    if (route_done) begin
                        core_state <= CORE_LAUNCH_NEURONS;
                    end
                end
                CORE_LAUNCH_NEURONS: begin
                    core_state <= CORE_UPDATE_NEURONS;
                end
                CORE_UPDATE_NEURONS: begin
                    if (population_done) begin
                        previous_spikes <= spike_vector;
                        core_state <= CORE_IDLE;
                    end
                end
                default: core_state <= CORE_IDLE;
            endcase
        end
    end

endmodule
