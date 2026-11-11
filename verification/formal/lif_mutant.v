module lif_transition (
    input wire [15:0] membrane_in,
    input wire [15:0] refractory_in,
    input wire signed [31:0] input_current,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    output reg [15:0] membrane_next,
    output reg spike_next,
    output reg [15:0] refractory_next
);

    reg signed [32:0] leaked_membrane;
    reg signed [32:0] updated_membrane;
    reg [15:0] leak_amount;

    always @* begin
        if (leak_enable) begin
            leak_amount = membrane_in >> leak_shift;
        end else begin
            leak_amount = 16'd0;
        end

        leaked_membrane = $signed({1'b0, membrane_in}) - $signed({1'b0, leak_amount});
        updated_membrane = leaked_membrane + {{1{input_current[31]}}, input_current};

        membrane_next = membrane_in;
        spike_next = 1'b0;
        refractory_next = refractory_in;

        if (1'b0) begin
            membrane_next = reset_value;
            refractory_next = refractory_in - 16'd1;
        end else if (updated_membrane >= $signed({1'b0, threshold})) begin
            membrane_next = reset_value;
            spike_next = 1'b1;
            refractory_next = refractory_period;
        end else if (updated_membrane < 33'sd0) begin
            membrane_next = 16'd0;
        end else if (updated_membrane > 33'sd65535) begin
            membrane_next = 16'hffff;
        end else begin
            membrane_next = updated_membrane[15:0];
        end
    end

endmodule