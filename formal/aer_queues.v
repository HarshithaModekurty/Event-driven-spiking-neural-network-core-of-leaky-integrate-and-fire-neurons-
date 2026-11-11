// Actual depth-16 FIFO control and production arbiter, with opaque payload.
// Pending external requests persist until their FIFO accepts them.
module aer_queues (
    input wire clk,
    input wire [3:0] arrivals,
    input wire acknowledge,
    output wire [3:0] pending,
    output wire [3:0] accepted,
    output wire [3:0] nonempty,
    output wire [3:0] served
);
    reg reset=1;
    reg [3:0] incoming=0;
    wire [3:0] ready, grant;
    wire active;
    wire [3:0] heads;
    assign pending=incoming;
    assign accepted=incoming & ready & {4{!reset}};
    assign served=grant & {4{active && acknowledge && !reset}};
    always @(posedge clk) begin
        reset<=0;
        if(reset) incoming<=0;
        else incoming<=(incoming & ~accepted) | arrivals;
    end
    genvar p;
    generate for(p=0;p<4;p=p+1) begin: queues
        aer_event_fifo #(.WIDTH(1),.DEPTH(16)) queue (
            .clk(clk),.rst(reset),.push_valid(incoming[p]),.push_ready(ready[p]),.push_data(1'b0),
            .pop_valid(nonempty[p]),.pop_ready(served[p]),.pop_data(heads[p]),.level()
        );
    end endgenerate
    aer_rr_arbiter #(.WIDTH(1)) dut (
        .clk(clk),.rst(reset),.requests(nonempty),.addresses(heads),
        .out_req(active),.out_ack(acknowledge),.out_data(),.held_grant(grant),.held_port()
    );
endmodule
