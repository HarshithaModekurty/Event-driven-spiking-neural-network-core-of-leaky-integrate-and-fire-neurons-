`timescale 1ns/1ps
module demo_reporter_tb;
    reg clk=0,resetn=0,next_pulse=0;
    reg we=0,re=0,iv=0,ov=0;
    reg [31:0] wa=0,wd=0,ra=0,rd=0;
    reg [7:0] addr=0;
    reg [8:0] ip=0,op=0;
    wire run,tx,pulse,valid,error,waiting,transmitting,complete;
    wire [7:0] sample;
    wire [3:0] digit;
    wire [159:0] scores;
    wire [13:0] count;
    integer f,bitno,n;
    reg [7:0] byte_data;
    reg [4095:0] path;
    always #5 clk=~clk;
    snn_demo_reporter #(.SAMPLES(2),.UART_CLKS_PER_BIT(2)) dut (
        .clk(clk),.resetn(resetn),.next_pulse(next_pulse),
        .trace_write_valid(we),.trace_write_addr(wa),.trace_write_data(wd),
        .trace_read_valid(re),.trace_read_addr(ra),.trace_read_data(rd),.trace_state_address(addr),
        .input_event_valid(iv),.input_event_packet(ip),.output_event_valid(ov),.output_event_packet(op),
        .cpu_trap(1'b0),.bus_fault(1'b0),.software_result(32'd0),.demo_run(run),.uart_tx(tx),
        .snapshot_pulse(pulse),.snapshot_valid(valid),.sample_index(sample),.predicted_digit(digit),
        .scores(scores),.error(error),.waiting(waiting),.transmitting(transmitting),.complete(complete),.capture_count(count));
    initial forever begin
        @(negedge tx);
        if(resetn) begin
            #10; if(tx!==0) $fatal(1,"FAIL: start");
            for(bitno=0;bitno<8;bitno=bitno+1) begin #20; byte_data[bitno]=tx; end
            #20; if(tx!==1) $fatal(1,"FAIL: stop");
            $fwrite(f,"%c",byte_data);
        end
    end
    initial begin
        if(!$value$plusargs("OUTPUT=%s",path)) $fatal(1,"FAIL: output path");
        f=$fopen(path,"wb");
        repeat(3) @(negedge clk); resetn=1;
        @(negedge clk); next_pulse=1;
        @(negedge clk); next_pulse=0;
        for(n=0;n<10;n=n+1) begin
            re=1; ra=32'h40000024; addr=246+n; rd=16'h1230+n; @(negedge clk);
        end
        re=0;
        // Both RAM ports must preserve simultaneous handshakes and tick tags.
        iv=1; ov=1; ip=9'h005; op=9'h0fa; @(negedge clk);
        ip=9'h100; op=9'h100; @(negedge clk);
        ip=9'h006; op=9'h0fb; @(negedge clk);
        iv=0; ov=0; we=1; wa=32'hc000; wd=9; @(negedge clk); we=0;
        if(!valid || !pulse || digit!=9 || count!=6 || run) $fatal(1,"FAIL: snapshot");
        wait(waiting); @(negedge clk);
        if(error || sample!=0) $fatal(1,"FAIL: reporter first sample");
        next_pulse=1; @(negedge clk); next_pulse=0;
        if(count!=0 || !run || valid || sample!=1) $fatal(1,"FAIL: next sample clear");
        // Capacity violation is explicit rather than silent raster loss.
        force dut.capture_count=14'd8192;
        iv=1; @(negedge clk); iv=0; release dut.capture_count;
        if(!error) $fatal(1,"FAIL: missing overflow indication");
        resetn=0; @(negedge clk); resetn=1; @(negedge clk);
        if(error || count!=0 || valid || sample!=0 || !waiting) $fatal(1,"FAIL: reporter restart");
        $fclose(f);
        $display("PASS: simultaneous AER capture, UART formatting, pause/next/reset and overflow");
        $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL: reporter watchdog"); end
endmodule
