`timescale 1ns/1ps
module aer_rate_encoder_tb;
    parameter TICKS=32, PACKETS=4046;
    reg clk=0, rst=1, clear=0, write=0, start=0, ack=0, run_ack=0;
    reg [7:0] addr=0, data=0;
    wire clear_ready, write_ready, start_ready, req, eot, busy, done;
    wire [7:0] spike_addr;
    reg [7:0] values[0:255];
    reg [8:0] expected_packets[0:PACKETS-1];
    reg [2047:0] expected_phases[0:TICKS-1];
    reg [4095:0] path;
    reg [8:0] received, held;
    reg was_stalled=0;
    reg [15:0] random_bits=16'h1234;
    integer n,t,index=0,cycles=0,stalls=0;
    always #5 clk=~clk;
    aer_rate_encoder dut (.clk(clk),.rst(rst),.sample_clear(clear),.clear_ready(clear_ready),
        .intensity_write(write),.intensity_ready(write_ready),.intensity_addr(addr),.intensity_data(data),
        .tick_start(start),.tick_ready(start_ready),.out_req(req),.out_ack(ack),.out_addr(spike_addr),
        .out_end(eot),.busy(busy),.tick_done(done));
    always @(negedge clk) if (run_ack) begin
        random_bits={random_bits[14:0],random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
        ack=(cycles%17>=7) && random_bits[0];
    end
    always @(posedge clk) if (!rst && run_ack) begin
        cycles=cycles+1;
        if (was_stalled && (!req || {eot,spike_addr}!==held)) $fatal(1,"Encoder packet changed under backpressure");
        was_stalled=req && !ack; held={eot,spike_addr};
        if (was_stalled) stalls=stalls+1;
    end else was_stalled=0;
    initial begin
        if (!$value$plusargs("DATA_DIR=%s",path)) $fatal(1,"Missing encoder vectors");
        $readmemh({path,"/intensities.hex"},values);
        $readmemh({path,"/packets.hex"},expected_packets);
        $readmemh({path,"/phases.hex"},expected_phases);
        repeat(3) @(negedge clk); rst=0; #1;
        for(n=0;n<256;n=n+1) begin
            if(!write_ready) $fatal(1,"Encoder intensity load not ready");
            write=1; addr=n; data=values[n]; @(negedge clk);
        end
        write=0; start=1; @(negedge clk); start=0;
        wait(req && !eot);
        @(negedge clk); held={eot,spike_addr};
        // Idle-only controls must not rewrite or clear a stalled tick.
        write=1; addr=0; data=255; clear=1; start=1;
        repeat(5) begin
            @(negedge clk);
            if(clear_ready || write_ready || start_ready || !req || {eot,spike_addr}!==held)
                $fatal(1,"Busy encoder accepted idle-only commands");
        end
        write=0; clear=0; start=0; rst=1;
        repeat(3) @(negedge clk); rst=0; #1;
        if(req || busy || done) $fatal(1,"Encoder reset did not cancel held packet");
        for(n=0;n<256;n=n+1) if(dut.phase[n]!==0) $fatal(1,"Encoder phase reset");
        run_ack=1;
        for(t=0;t<TICKS;t=t+1) begin
            if(t==16) begin
                @(negedge clk); clear=1;
                @(negedge clk); clear=0;
            end
            @(negedge clk); if(!start_ready) $fatal(1,"Tick not ready");
            start=1; @(negedge clk); start=0;
            received=0;
            while(received!=256) begin
                @(posedge clk);
                if(req && ack) begin
                    received={eot,spike_addr};
                    if(index>=PACKETS || received!==expected_packets[index])
                        $fatal(1,"Encoder packet %0d got=%0d expected=%0d",index,received,expected_packets[index]);
                    index=index+1;
                end
            end
            #1;
            if(!done || busy) $fatal(1,"Encoder completion timing");
            for(n=0;n<256;n=n+1)
                if(dut.phase[n]!==((expected_phases[t]>>(8*n))&8'hff) || dut.phase[n]>254)
                    $fatal(1,"Encoder phase mismatch tick=%0d source=%0d",t,n);
        end
        if(index!=PACKETS || !stalls) $fatal(1,"Encoder coverage/count failure");
        $display("PASS: 256-source rate encoder, %0d ticks, %0d packets, %0d stall clocks",TICKS,PACKETS,stalls);
        $finish;
    end
    initial begin #5000000; $fatal(1,"Encoder timeout"); end
endmodule
