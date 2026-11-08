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

    reg signed [32:0] leaked_membrane;
    reg signed [32:0] updated_membrane;
    reg [15:0] leak_amount;

    always @* begin
        if (leak_enable) begin
            leak_amount = membrane >> leak_shift;
        end else begin
            leak_amount = 16'd0;
        end

        leaked_membrane = $signed({1'b0, membrane}) - $signed({1'b0, leak_amount});
        updated_membrane = leaked_membrane + {{1{input_current[31]}}, input_current};
    end

    always @(posedge clk) begin
        if (rst) begin
            membrane <= reset_value;
            spike <= 1'b0;
            refractory_remaining <= 16'd0;
        end else if (enable) begin
            if (refractory_remaining != 16'd0) begin
                membrane <= reset_value;
                spike <= 1'b0;
                refractory_remaining <= refractory_remaining - 16'd1;
            end else if (updated_membrane >= $signed({1'b0, threshold})) begin
                membrane <= reset_value;
                spike <= 1'b1;
                refractory_remaining <= refractory_period;
            end else begin
                if (updated_membrane < 33'sd0) begin
                    membrane <= 16'd0;
                end else if (updated_membrane > 33'sd65535) begin
                    membrane <= 16'hffff;
                end else begin
                    membrane <= updated_membrane[15:0];
                end
                spike <= 1'b0;
            end
        end else begin
            spike <= 1'b0;
        end
    end

endmodule