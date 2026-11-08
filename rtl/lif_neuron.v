module lif_neuron (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire signed [31:0] input_current,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    output reg [15:0] membrane,
    output reg spike,
    output reg [15:0] refractory_remaining
);

    wire [15:0] membrane_next;
    wire spike_next;
    wire [15:0] refractory_next;

    lif_transition transition_unit (
        .membrane_in(membrane),
        .refractory_in(refractory_remaining),
        .input_current(input_current),
        .threshold(threshold),
        .reset_value(reset_value),
        .leak_enable(leak_enable),
        .leak_shift(leak_shift),
        .refractory_period(refractory_period),
        .membrane_next(membrane_next),
        .spike_next(spike_next),
        .refractory_next(refractory_next)
    );

    always @(posedge clk) begin
        if (rst) begin
            membrane <= reset_value;
            spike <= 1'b0;
            refractory_remaining <= 16'd0;
        end else if (enable) begin
            membrane <= membrane_next;
            spike <= spike_next;
            refractory_remaining <= refractory_next;
        end else begin
            spike <= 1'b0;
        end
    end

endmodule