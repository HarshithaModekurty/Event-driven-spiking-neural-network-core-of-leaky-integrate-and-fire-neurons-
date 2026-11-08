module lif_population_stepper #(
    parameter NUM_NEURONS = 256,
    parameter ADDR_WIDTH = 8
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire current_write,
    input wire [ADDR_WIDTH-1:0] current_addr,
    input wire signed [31:0] current_data,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    input wire [ADDR_WIDTH-1:0] state_read_addr,
    output wire [15:0] state_read_membrane,
    output wire [15:0] state_read_refractory,
    output reg [NUM_NEURONS-1:0] spike_vector,
    output reg busy,
    output reg done
);

    reg [15:0] membrane_state [0:NUM_NEURONS-1];
    reg [15:0] refractory_state [0:NUM_NEURONS-1];
    reg signed [31:0] current_state [0:NUM_NEURONS-1];
    reg [ADDR_WIDTH-1:0] neuron_index;
    integer reset_index;

    wire [15:0] next_membrane;
    wire [15:0] next_refractory;
    wire next_spike;

    assign state_read_membrane = membrane_state[state_read_addr];
    assign state_read_refractory = refractory_state[state_read_addr];

    lif_transition transition_unit (
        .membrane_in(membrane_state[neuron_index]),
        .refractory_in(refractory_state[neuron_index]),
        .input_current(current_state[neuron_index]),
        .threshold(threshold),
        .reset_value(reset_value),
        .leak_enable(leak_enable),
        .leak_shift(leak_shift),
        .refractory_period(refractory_period),
        .membrane_next(next_membrane),
        .spike_next(next_spike),
        .refractory_next(next_refractory)
    );

    always @(posedge clk) begin
        if (rst) begin
            neuron_index <= {ADDR_WIDTH{1'b0}};
            spike_vector <= {NUM_NEURONS{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            for (reset_index = 0; reset_index < NUM_NEURONS; reset_index = reset_index + 1) begin
                membrane_state[reset_index] <= reset_value;
                refractory_state[reset_index] <= 16'd0;
                current_state[reset_index] <= 32'sd0;
            end
        end else begin
            done <= 1'b0;

            if (!busy && current_write && current_addr < NUM_NEURONS) begin
                current_state[current_addr] <= current_data;
            end

            if (!busy && start) begin
                neuron_index <= {ADDR_WIDTH{1'b0}};
                spike_vector <= {NUM_NEURONS{1'b0}};
                busy <= 1'b1;
            end else if (busy) begin
                membrane_state[neuron_index] <= next_membrane;
                refractory_state[neuron_index] <= next_refractory;
                spike_vector[neuron_index] <= next_spike;

                if (neuron_index == NUM_NEURONS - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    neuron_index <= neuron_index + 1'b1;
                end
            end
        end
    end

endmodule