// One registered weight read and one shared accumulator; infer BRAM.
module lif_synapse_router #(
    parameter NUM_NEURONS = 256,
    parameter ADDR_WIDTH = 8,
    parameter NUM_SOURCES = NUM_NEURONS,
    parameter SOURCE_ADDR_WIDTH = ADDR_WIDTH
) (
    input wire clk,
    input wire rst,
    input wire weight_write,
    input wire [SOURCE_ADDR_WIDTH-1:0] weight_source_addr,
    input wire [ADDR_WIDTH-1:0] weight_destination_addr,
    input wire signed [3:0] weight_data,
    input wire route_start,
    input wire [NUM_SOURCES-1:0] source_spikes,
    output reg current_valid,
    output reg [ADDR_WIDTH-1:0] current_destination,
    output reg signed [31:0] current_value,
    output reg busy,
    output reg done
);
    localparam IDLE = 2'd0, SCAN = 2'd1, ACCUMULATE = 2'd2;
    (* ram_style = "block" *) reg signed [3:0] synapse_weight [0:NUM_SOURCES*NUM_NEURONS-1];
    reg signed [3:0] read_weight;
    reg [1:0] state;
    reg [NUM_SOURCES-1:0] active_sources;
    reg [SOURCE_ADDR_WIDTH-1:0] source_index;
    reg [ADDR_WIDTH-1:0] destination_index;
    reg signed [31:0] accumulated_current;
    wire signed [31:0] extended_weight = {{28{read_weight[3]}}, read_weight};

    // No memory reset loop: program every entry before inference.
    always @(posedge clk) begin
        if (!rst && !busy && weight_write &&
            weight_source_addr < NUM_SOURCES && weight_destination_addr < NUM_NEURONS)
            synapse_weight[weight_source_addr*NUM_NEURONS + weight_destination_addr] <= weight_data;
        if (!rst && state == SCAN && active_sources[source_index])
            read_weight <= synapse_weight[source_index*NUM_NEURONS + destination_index];
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            active_sources <= 0;
            source_index <= 0;
            destination_index <= 0;
            accumulated_current <= 0;
            current_valid <= 0;
            current_destination <= 0;
            current_value <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            current_valid <= 0;
            done <= 0;
            case (state)
                IDLE: if (route_start) begin
                    active_sources <= source_spikes;
                    source_index <= 0;
                    destination_index <= 0;
                    accumulated_current <= 0;
                    busy <= 1;
                    state <= SCAN;
                end
                SCAN: begin
                    if (active_sources[source_index]) state <= ACCUMULATE;
                    else if (source_index == NUM_SOURCES-1) begin
                        current_valid <= 1;
                        current_destination <= destination_index;
                        current_value <= accumulated_current;
                        source_index <= 0;
                        accumulated_current <= 0;
                        if (destination_index == NUM_NEURONS-1) begin
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end else destination_index <= destination_index + 1'b1;
                    end else source_index <= source_index + 1'b1;
                end
                ACCUMULATE: begin
                    if (source_index == NUM_SOURCES-1) begin
                        current_valid <= 1;
                        current_destination <= destination_index;
                        current_value <= accumulated_current + extended_weight;
                        source_index <= 0;
                        accumulated_current <= 0;
                        if (destination_index == NUM_NEURONS-1) begin
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end else begin
                            destination_index <= destination_index + 1'b1;
                            state <= SCAN;
                        end
                    end else begin
                        accumulated_current <= accumulated_current + extended_weight;
                        source_index <= source_index + 1'b1;
                        state <= SCAN;
                    end
                end
                default: begin state <= IDLE; busy <= 0; end
            endcase
        end
    end
endmodule
