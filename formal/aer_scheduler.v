// Queue-head abstraction: a pending port cannot withdraw before service.
// Data payload is irrelevant to selection; the production arbiter is instantiated.
module aer_scheduler (
    input wire clk,
    input wire [3:0] arrivals,
    input wire acknowledge,
    output wire [3:0] pending,
    output wire [3:0] served,
    output wire active
);
    reg reset=1;
    reg [3:0] queued=0;
    wire [3:0] grant;
    assign pending=queued;
    assign served=grant & {4{active && acknowledge && !reset}};
    always @(posedge clk) begin
        reset<=0;
        if (reset) queued<=0;
        else queued <= (queued & ~served) | arrivals;
    end
    aer_rr_arbiter #(.WIDTH(1)) dut (
        .clk(clk),.rst(reset),.requests(queued),.addresses(4'b0),
        .out_req(active),.out_ack(acknowledge),.out_data(),
        .held_grant(grant),.held_port()
    );
endmodule
