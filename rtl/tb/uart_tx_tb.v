`timescale 1ns/1ps
module uart_tx_tb;
    reg clk=0,resetn=0,valid=0;
    reg [7:0] data=0;
    wire ready,tx;
    integer bit_number,cycle;
    reg [9:0] expected;
    always #5 clk=~clk;
    uart_tx #(.CLKS_PER_BIT(868)) dut (.clk(clk),.resetn(resetn),.valid(valid),.data(data),.ready(ready),.tx(tx));
    task send_and_check;
        input [7:0] value;
        begin
            @(negedge clk); data=value; valid=1; expected={1'b1,value,1'b0};
            @(posedge clk); #1;
            if(ready || tx) $fatal(1,"FAIL: UART acceptance");
            for(bit_number=0;bit_number<10;bit_number=bit_number+1)
                for(cycle=0;cycle<868;cycle=cycle+1) begin
                    @(negedge clk); valid=0; data=~value;
                    if(tx!==expected[bit_number] || ready) $fatal(1,"FAIL: production UART bit=%d clock=%d",bit_number,cycle);
                end
            @(posedge clk); #1;
            if(!ready || !tx) $fatal(1,"FAIL: UART stop/idle");
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        send_and_check(8'ha5); send_and_check(8'h00); send_and_check(8'hff);
        @(negedge clk); valid=1; @(negedge clk); valid=0; resetn=0;
        @(negedge clk); if(!ready || !tx) $fatal(1,"FAIL: reset to idle");
        $display("PASS: UART production divisor 868, all 868 clocks of every bit, held data and reset");
        $finish;
    end
endmodule
