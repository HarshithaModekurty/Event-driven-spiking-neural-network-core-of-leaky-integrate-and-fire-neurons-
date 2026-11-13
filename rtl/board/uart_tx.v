// 8 data bits, no parity, one stop bit. Byte handshake occurs at valid&&ready.
module uart_tx #(parameter CLKS_PER_BIT=868) (
    input wire clk, input wire resetn, input wire valid, input wire [7:0] data,
    output wire ready, output wire tx
);
    localparam COUNT_WIDTH=(CLKS_PER_BIT<2)?1:$clog2(CLKS_PER_BIT);
    reg [COUNT_WIDTH-1:0] count;
    reg [3:0] remaining;
    reg [9:0] bits;
    assign ready=(remaining==0);
    assign tx=ready ? 1'b1 : bits[0];
    always @(posedge clk) begin
        if(!resetn) begin count<=0; remaining<=0; bits<=10'h3ff; end
        else if(ready) begin
            if(valid) begin bits<={1'b1,data,1'b0}; remaining<=10; count<=CLKS_PER_BIT-1; end
        end else if(count==0) begin
            bits<={1'b1,bits[9:1]}; remaining<=remaining-1'b1; count<=CLKS_PER_BIT-1;
        end else count<=count-1'b1;
    end
endmodule
