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
    localparam READ_STATE = 2'd0, CALCULATE = 2'd1, WRITE_STATE = 2'd2;
    reg [1:0] update_phase;
    reg [15:0] selected_membrane;
    reg [15:0] selected_refractory;
    reg signed [31:0] selected_current;
    reg [15:0] selected_threshold;
    reg [15:0] selected_reset;
    reg selected_leak_enable;
    reg [4:0] selected_leak_shift;
    reg [15:0] selected_refractory_period;
    reg [15:0] result_membrane;
    reg [15:0] result_refractory;
    reg result_spike;
    integer reset_index;

    wire [15:0] next_membrane;
    wire [15:0] next_refractory;
    wire next_spike;
    // Visible to verification: exactly one commit per neuron, not per busy clock.
    wire update_commit = busy && (update_phase == WRITE_STATE) && !rst;

    assign state_read_membrane = membrane_state[state_read_addr];
    assign state_read_refractory = refractory_state[state_read_addr];

    lif_transition transition_unit (
        .membrane_in(selected_membrane),
        .refractory_in(selected_refractory),
        .input_current(selected_current),
        .threshold(selected_threshold),
        .reset_value(selected_reset),
        .leak_enable(selected_leak_enable),
        .leak_shift(selected_leak_shift),
        .refractory_period(selected_refractory_period),
        .membrane_next(next_membrane),
        .spike_next(next_spike),
        .refractory_next(next_refractory)
    );

    always @(posedge clk) begin
        if (rst) begin
            neuron_index <= {ADDR_WIDTH{1'b0}};
            update_phase <= READ_STATE;
            selected_membrane <= 0;
            selected_refractory <= 0;
            selected_current <= 0;
            selected_threshold <= 0;
            selected_reset <= 0;
            selected_leak_enable <= 0;
            selected_leak_shift <= 0;
            selected_refractory_period <= 0;
            result_membrane <= 0;
            result_refractory <= 0;
            result_spike <= 0;
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
                update_phase <= READ_STATE;
                spike_vector <= {NUM_NEURONS{1'b0}};
                busy <= 1'b1;
            end else if (busy && update_phase == READ_STATE) begin
                // Break the large state-select mux away from LIF arithmetic.
                selected_membrane <= membrane_state[neuron_index];
                selected_refractory <= refractory_state[neuron_index];
                selected_current <= current_state[neuron_index];
                selected_threshold <= threshold;
                selected_reset <= reset_value;
                selected_leak_enable <= leak_enable;
                selected_leak_shift <= leak_shift;
                selected_refractory_period <= refractory_period;
                update_phase <= CALCULATE;
            end else if (busy && update_phase == CALCULATE) begin
                // Register the result before broadcasting it to state storage.
                result_membrane <= next_membrane;
                result_refractory <= next_refractory;
                result_spike <= next_spike;
                update_phase <= WRITE_STATE;
            end else if (update_commit) begin
                membrane_state[neuron_index] <= result_membrane;
                refractory_state[neuron_index] <= result_refractory;
                spike_vector[neuron_index] <= result_spike;
                update_phase <= READ_STATE;

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
