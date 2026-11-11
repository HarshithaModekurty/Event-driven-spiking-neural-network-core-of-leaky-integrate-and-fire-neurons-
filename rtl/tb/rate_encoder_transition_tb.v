`timescale 1ns/1ps
module rate_encoder_transition_tb;
    reg [7:0] phase, intensity;
    wire fire;
    wire [7:0] next_phase;
    integer file, fields, p, v, f, n, checked=0;
    reg [4095:0] path;
    rate_encoder_transition dut (.phase(phase), .intensity(intensity), .fire(fire), .phase_next(next_phase));
    initial begin
        if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing encoder transition vectors");
        file=$fopen(path,"r");
        if (!file) $fatal(1,"Cannot open encoder transition vectors");
        fields=4;
        while (fields==4) begin
            fields=$fscanf(file,"%d %d %d %d\n",p,v,f,n);
            if (fields==4) begin
                phase=p; intensity=v; #1;
                if (fire!==f[0] || next_phase!==n[7:0])
                    $fatal(1,"Encoder arithmetic p=%0d v=%0d got=%0d/%0d expected=%0d/%0d",p,v,fire,next_phase,f,n);
                checked=checked+1;
            end
        end
        if (checked!=65280) $fatal(1,"Missing phase/intensity combinations");
        $display("PASS: all 65,280 legal phase/intensity combinations match Python");
        $finish;
    end
endmodule
