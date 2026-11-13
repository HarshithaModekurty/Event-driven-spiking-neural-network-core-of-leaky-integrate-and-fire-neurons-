`timescale 1ns/1ps
module board_io_tb;
    reg sysclk=0;
    reg [1:0] btn=0;
    wire [3:0] led;
    wire r,g,b,phy,tx;
    integer pulses=0;
    realtime last_edge=0;
    always #4 sysclk=~sysclk;
    zybo_z710_top #(.BOOT_FILE(""),.DEBOUNCE_CYCLES(8)) dut (
        .sysclk(sysclk),.btn(btn),.led(led),.led6_r(r),.led6_g(g),.led6_b(b),
        .eth_rst_b(phy),.pmod_uart_tx(tx));
    always @(posedge dut.clk) begin
        if(dut.resetn && last_edge!=0 && ($realtime-last_edge<9.999 || $realtime-last_edge>10.001))
            $fatal(1,"FAIL: expected 100 MHz, period=%f",$realtime-last_edge);
        last_edge=$realtime;
        if(dut.resetn && dut.next_pulse) pulses=pulses+1;
    end
    initial begin
        wait(dut.resetn); repeat(5) @(negedge dut.clk);
        if(!phy || !tx || !b || r || g || led!=0 || dut.run) $fatal(1,"FAIL: initial board state");
        btn[1]=1; repeat(3) @(negedge dut.clk); btn[1]=0;
        repeat(15) @(negedge dut.clk);
        if(pulses!=0 || dut.run) $fatal(1,"FAIL: button bounce accepted");
        btn[1]=1; repeat(30) @(negedge dut.clk);
        if(pulses!=1 || !dut.run) $fatal(1,"FAIL: debounced start");
        btn=1; repeat(10) @(negedge dut.clk);
        if(dut.resetn || dut.run || tx!=1) $fatal(1,"FAIL: BTN0 reset");
        btn=0; repeat(40) @(negedge dut.clk);
        if(!dut.resetn || dut.run || led!=0 || !b) $fatal(1,"FAIL: restart wait");
        $display("PASS: actual MMCM 125->100 MHz, board startup, button bounce, start and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL: board IO watchdog"); end
endmodule
