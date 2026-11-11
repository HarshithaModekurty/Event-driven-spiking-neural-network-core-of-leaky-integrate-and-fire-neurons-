// Exact arithmetic used by golden_model.encoding.RateEncoder (maximum=255).
module rate_encoder_transition (
    input wire [7:0] phase,
    input wire [7:0] intensity,
    output wire fire,
    output wire [7:0] phase_next
);
    wire [8:0] sum = {1'b0, phase} + {1'b0, intensity};
    wire [8:0] remainder = sum - 9'd255;
    assign fire = (sum >= 9'd255);
    assign phase_next = fire ? remainder[7:0] : sum[7:0];
endmodule
