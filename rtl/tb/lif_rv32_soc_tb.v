`timescale 1ns/1ps
module lif_rv32_soc_tb;
    parameter IMAGES=3, FRAMES=24, INPUT_WORDS=3906, OUTPUT_WORDS=1908;
    reg clk=0,resetn=0;
    wire trap,fault,busy,tick_done,frame_done;
    wire [31:0] result;
    reg [4095:0] path;
    reg [3:0] weights[0:65535];
    reg [7:0] intensities[0:IMAGES*256-1];
    reg [8:0] input_packets[0:INPUT_WORDS-1], output_packets[0:OUTPUT_WORDS-1];
    reg [8447:0] states[0:FRAMES-1];
    reg [31:0] predictions[0:IMAGES-1];
    integer wi=0,ii=0,inputs=0,outputs=0,reads=0,ticks=0,frames=0,n,frame,index,cycles=0;
    reg [31:0] expected;
    always #5 clk=~clk;
    lif_rv32_soc #(.BOOT_FILE("")) dut (.clk(clk),.resetn(resetn),.cpu_trap(trap),
        .bus_fault(fault),.software_result(result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done));
    initial begin
        if(!$value$plusargs("DATA_DIR=%s",path)) $fatal(1,"FAIL: missing RV32 vectors");
        // Only boot RAM is initialized by the testbench. Every SNN weight,
        // intensity, configuration and start command is written by the CPU.
        $readmemh({path,"/firmware.hex"},dut.memory);
        $readmemh({path,"/weights.hex"},weights);
        $readmemh({path,"/intensities.hex"},intensities);
        $readmemh({path,"/encoder_packets.hex"},input_packets);
        $readmemh({path,"/output_packets.hex"},output_packets);
        $readmemh({path,"/states.hex"},states);
        $readmemh({path,"/predictions.hex"},predictions);
        repeat(5) @(negedge clk); resetn=1;
        wait(trap); #1;
        if(result!==32'h600d600d || fault || busy) $fatal(1,"FAIL: CPU stopped result=%h fault=%b busy=%b",result,fault,busy);
        if(wi!=65536 || ii!=IMAGES*256 || inputs!=INPUT_WORDS || outputs!=OUTPUT_WORDS ||
           reads!=FRAMES*256 || ticks!=FRAMES || frames!=FRAMES)
            $fatal(1,"FAIL: CPU counts weights=%d intensities=%d encoded=%d emitted=%d states=%d ticks=%d frames=%d",wi,ii,inputs,outputs,reads,ticks,frames);
        for(n=0;n<IMAGES;n=n+1)
            if(dut.memory[16'hc000/4+n]!==predictions[n]) $fatal(1,"FAIL: CPU class %d",n);
        $display("PASS: real RV32/AXI boot, 65536 learned/stress weights, %0d images, %0d ticks, %0d state reads, %0d cycles",IMAGES,FRAMES,reads,cycles);
        $finish;
    end
    always @(posedge clk) if(resetn) begin
        cycles=cycles+1;
        if(fault) $fatal(1,"FAIL: AXI bus fault");
        if(dut.registers.write_weight) begin
            if(wi>=65536 || dut.registers.weight_offset[17:2]!==wi[15:0] || dut.wd[3:0]!==weights[wi])
                $fatal(1,"FAIL: CPU weight write %0d",wi);
            wi=wi+1;
        end
        if(dut.registers.write_intensity) begin
            if(ii>=IMAGES*256 || dut.wa[9:2]!==ii[7:0] || dut.wd[7:0]!==intensities[ii])
                $fatal(1,"FAIL: CPU intensity %0d",ii);
            ii=ii+1;
        end
        if(dut.registers.core.encoder.out_req && dut.registers.core.input_ack[0]) begin
            if(inputs>=INPUT_WORDS || {dut.registers.core.encoder.out_end,dut.registers.core.encoder.out_addr}!==input_packets[inputs])
                $fatal(1,"FAIL: CPU encoded packet %0d",inputs);
            inputs=inputs+1;
        end
        if(dut.registers.pop) begin
            if(outputs>=OUTPUT_WORDS || {dut.registers.out_end,dut.registers.out_addr}!==output_packets[outputs])
                $fatal(1,"FAIL: CPU output packet %0d",outputs);
            outputs=outputs+1;
        end
        if(dut.re && dut.ready && dut.ra==32'h40000024) begin
            frame=reads/256; index=reads%256;
            expected=((states[frame]>>(256+16*index))&32'hffff) |
                     (((states[frame]>>(4352+16*index))&32'hffff)<<16);
            if(reads>=FRAMES*256 || dut.registers.state_address!==index[7:0] || dut.rd!==expected || dut.rr!=0)
                $fatal(1,"FAIL: CPU state frame=%0d neuron=%0d got=%h expected=%h",frame,index,dut.rd,expected);
            reads=reads+1;
        end
        if(tick_done) ticks=ticks+1;
        if(frame_done) frames=frames+1;
    end
    initial begin #(200000000+FRAMES*5000000); $fatal(1,"FAIL: RV32 watchdog"); end
endmodule
