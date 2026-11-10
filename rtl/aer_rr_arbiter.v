// Select a queued input port and retain its address/grant until acknowledged.
// Exactly four ports; address zero is valid, and grant=0 means no request.
module aer_rr_arbiter #(
    parameter WIDTH = 9
) (
    input wire clk,
    input wire rst,
    input wire [3:0] requests,
    input wire [4*WIDTH-1:0] addresses,
    output reg out_req,
    input wire out_ack,
    output reg [WIDTH-1:0] out_data,
    output reg [3:0] held_grant,
    output reg [1:0] held_port
);
    reg [1:0] next_port;
    wire [3:0] selected_grant;
    aer_rr_select select_port (.requests(requests), .next_port(next_port), .grant(selected_grant));
    always @(posedge clk) begin
        if (rst) begin
            next_port <= 0;
            out_req <= 0;
            out_data <= 0;
            held_grant <= 0;
            held_port <= 0;
        end else if (out_req) begin
            if (out_ack) begin
                next_port <= held_port + 1'b1;
                out_req <= 0;
                held_grant <= 0;
            end
        end else if (|selected_grant) begin
            out_req <= 1;
            held_grant <= selected_grant;
            case (selected_grant)
                4'b0001: begin held_port <= 0; out_data <= addresses[WIDTH-1:0]; end
                4'b0010: begin held_port <= 1; out_data <= addresses[2*WIDTH-1:WIDTH]; end
                4'b0100: begin held_port <= 2; out_data <= addresses[3*WIDTH-1:2*WIDTH]; end
                4'b1000: begin held_port <= 3; out_data <= addresses[4*WIDTH-1:3*WIDTH]; end
            endcase
        end
    end
endmodule
