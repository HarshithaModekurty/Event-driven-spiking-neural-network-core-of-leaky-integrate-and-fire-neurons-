`timescale 1ns/1ps
module lif_rate_snn_tb;
    parameter FRAMES=24, IMAGES=3, INPUT_WORDS=3906, OUTPUT_WORDS=1908;
    parameter THRESHOLD=8, RESET_VALUE=3, LEAK_ENABLE=1, REFRACTORY_PERIOD=2, REQUIRE_FULL_OUTPUT=1;
    reg clk=0,rst=1,clear=0,write_intensity=0,start=0,ack=0,weight_write=0,run_ack=0;
    wire clear_ready,intensity_ready,tick_ready,req,eot,weight_ready,busy,tick_done,frame_done;
    wire [7:0] out_addr;
    reg [7:0] intensity_addr=0,intensity_data=0,weight_source=0,weight_dest=0,debug_addr=0;
    reg signed [3:0] weight_data=0;
    reg [15:0] cfg_threshold=THRESHOLD,cfg_reset=RESET_VALUE,cfg_refractory=REFRACTORY_PERIOD;
    reg cfg_leak=LEAK_ENABLE;
    wire [15:0] membrane,refractory;
    wire [255:0] spikes;
    reg [3:0] weights[0:65535];
    reg [7:0] intensities[0:IMAGES*256-1];
    reg [8:0] input_packets[0:INPUT_WORDS-1],output_packets[0:OUTPUT_WORDS-1];
    reg [8447:0] states[0:FRAMES-1];
    reg [4095:0] path;
    reg [15:0] random_bits=16'h5678;
    reg [8:0] previous_packet,received;
    reg stalled=0;
    integer n,frame,inputs=0,outputs=0,commits=0,total_commits=0,ticks=0,cycles=0,stalls=0,full_stalls=0,first_stalls=80;
    always #5 clk=~clk;
    lif_rate_aer_snn_core #(.INPUT_DEPTH(3),.OUTPUT_DEPTH(4)) dut (
        .clk(clk),.rst(rst),.sample_clear(clear),.clear_ready(clear_ready),
        .intensity_write(write_intensity),.intensity_ready(intensity_ready),.intensity_addr(intensity_addr),.intensity_data(intensity_data),
        .tick_start(start),.tick_ready(tick_ready),.out_req(req),.out_ack(ack),.out_addr(out_addr),.out_end(eot),
        .weight_write(weight_write),.weight_ready(weight_ready),.weight_source_addr(weight_source),
        .weight_destination_addr(weight_dest),.weight_data(weight_data),
        .threshold(cfg_threshold),.reset_value(cfg_reset),.leak_enable(cfg_leak),.leak_shift(5'd2),
        .refractory_period(cfg_refractory),.state_read_addr(debug_addr),.state_read_membrane(membrane),
        .state_read_refractory(refractory),.spike_vector(spikes),.busy(busy),.tick_done(tick_done),.frame_done(frame_done)
    );
    always @(negedge clk) if(run_ack) begin
        random_bits={random_bits[14:0],random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
        if(req && first_stalls>0) begin ack=0; first_stalls=first_stalls-1; end
        else ack=(cycles%211>=67) && (random_bits[0] || random_bits[8]);
    end
    always @(posedge clk) if(!rst && run_ack) begin
        cycles=cycles+1;
        if(stalled && (!req || {eot,out_addr}!==previous_packet)) $fatal(1,"FAIL: output changed during stall");
        stalled=req && !ack; previous_packet={eot,out_addr};
        if(stalled) stalls=stalls+1;
        if(dut.network.output_put && !dut.network.output_ready) full_stalls=full_stalls+1;
        if(dut.encoder.out_req && dut.input_ack[0]) begin
            if(inputs>=INPUT_WORDS || {dut.encoder.out_end,dut.encoder.out_addr}!==input_packets[inputs])
                $fatal(1,"FAIL: encoded packet %0d got=%0d expected=%0d",inputs,{dut.encoder.out_end,dut.encoder.out_addr},input_packets[inputs]);
            inputs=inputs+1;
        end
        if(dut.network.core_start) commits=0;
        if(dut.network.core.population_stepper.update_commit) begin
            if(dut.network.core.population_stepper.neuron_index!==commits[7:0]) $fatal(1,"FAIL: neuron visit order");
            commits=commits+1; total_commits=total_commits+1;
        end
        if(tick_done) begin
            if(commits!=256) $fatal(1,"FAIL: incomplete population step");
            ticks=ticks+1;
        end
    end
    initial begin
        if(!$value$plusargs("DATA_DIR=%s",path)) path="D:/RTL_PROJECT/build/rate_network";
        $readmemh({path,"/weights.hex"},weights);
        $readmemh({path,"/intensities.hex"},intensities);
        $readmemh({path,"/encoder_packets.hex"},input_packets);
        $readmemh({path,"/output_packets.hex"},output_packets);
        $readmemh({path,"/states.hex"},states);
        repeat(3) @(negedge clk); rst=0; #1;
        for(n=0;n<65536;n=n+1) begin
            if(!weight_ready || ^weights[n]===1'bx) $fatal(1,"FAIL: weight load");
            weight_write=1; weight_source=n/256; weight_dest=n%256; weight_data=weights[n];
            @(negedge clk);
        end
        weight_write=0; run_ack=1;
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            wait(clear_ready);
            if(frame%8==0) begin
                @(negedge clk); clear=1;
                @(negedge clk); clear=0; #1;
                for(n=0;n<256;n=n+1) begin
                    if(!intensity_ready) $fatal(1,"FAIL: intensity load");
                    write_intensity=1; intensity_addr=n; intensity_data=intensities[(frame/8)*256+n];
                    @(negedge clk);
                end
                write_intensity=0;
            end
            @(negedge clk); if(!tick_ready) $fatal(1,"FAIL: tick admission");
            start=1; @(negedge clk); start=0;
            // Commands while busy must be rejected; live configuration cannot
            // alter the settings already captured on the tick-start handshake.
            @(negedge clk); write_intensity=1; intensity_addr=0; intensity_data=0;
            weight_write=1; weight_source=0; weight_dest=1; weight_data=-8;
            start=1; clear=1; cfg_threshold=1; cfg_reset=0; cfg_leak=!LEAK_ENABLE;
            #1;
            if(clear_ready || intensity_ready || tick_ready || weight_ready) $fatal(1,"FAIL: busy command accepted");
            @(negedge clk); write_intensity=0; weight_write=0; start=0; clear=0;
            cfg_threshold=THRESHOLD; cfg_reset=RESET_VALUE; cfg_leak=LEAK_ENABLE;
            received=0;
            while(received!=256) begin
                @(posedge clk);
                if(req && ack) begin
                    received={eot,out_addr};
                    if(outputs>=OUTPUT_WORDS || received!==output_packets[outputs])
                        $fatal(1,"FAIL: network packet %0d got=%0d expected=%0d",outputs,received,output_packets[outputs]);
                    outputs=outputs+1;
                end
            end
            #1;
            if(!frame_done || spikes!==states[frame][255:0]) $fatal(1,"FAIL: frame result");
            for(n=0;n<256;n=n+1) begin
                @(negedge clk); debug_addr=n; #1;
                if(membrane!==((states[frame]>>(256+16*n))&16'hffff) ||
                    refractory!==((states[frame]>>(4352+16*n))&16'hffff))
                    $fatal(1,"FAIL: state frame=%0d neuron=%0d",frame,n);
            end
        end
        repeat(20) @(negedge clk);
        if(inputs!=INPUT_WORDS || outputs!=OUTPUT_WORDS || total_commits!=FRAMES*256 || ticks!=FRAMES || busy || req)
            $fatal(1,"FAIL: final counts inputs=%0d outputs=%0d commits=%0d ticks=%0d",inputs,outputs,total_commits,ticks);
        if(!stalls || (REQUIRE_FULL_OUTPUT && !full_stalls)) $fatal(1,"FAIL: output backpressure not exercised");
        $display("PASS: rate/AER/SNN %0d images, %0d ticks, %0d encoder tokens, %0d output tokens, %0d state updates",IMAGES,FRAMES,inputs,outputs,total_commits);
        $finish;
    end
    initial begin #(FRAMES*2500000+1000000); $fatal(1,"FAIL: rate/SNN timeout"); end
endmodule
