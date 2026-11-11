// Full-width combinational invariant, valid for every LIF state/config/current.
module lif_refractory (
    input wire [15:0] membrane,
    input wire [15:0] refractory,
    input wire signed [31:0] current,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    output wire safe,
    output wire countdown_safe
);
    wire [15:0] next_membrane, next_refractory;
    wire spike;
    lif_transition dut (.membrane_in(membrane),.refractory_in(refractory),.input_current(current),
        .threshold(threshold),.reset_value(reset_value),.leak_enable(leak_enable),.leak_shift(leak_shift),
        .refractory_period(refractory_period),.membrane_next(next_membrane),.spike_next(spike),
        .refractory_next(next_refractory));
    assign safe = (refractory==0) || !spike;
    assign countdown_safe = (refractory==0) || ((next_membrane==reset_value) && (next_refractory==refractory-16'd1));
endmodule
