`timescale 1ns/1ps
module lif_axi_lite_tb;
    reg clk=0,resetn=0;
    reg [31:0] awaddr=0,wdata=0,araddr=0;
    reg [3:0] wstrb=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid,busy,tick_done,frame_done;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata,result;
    reg [31:0] value,held;
    integer n,tries,pops=0;
    localparam BASE=32'h40000000;
    always #5 clk=~clk;
    lif_axi_lite dut (.clk(clk),.resetn(resetn),.s_awaddr(awaddr),.s_awprot(3'd0),
        .s_awvalid(awvalid),.s_awready(awready),.s_wdata(wdata),.s_wstrb(wstrb),
        .s_wvalid(wvalid),.s_wready(wready),.s_bresp(bresp),.s_bvalid(bvalid),.s_bready(bready),
        .s_araddr(araddr),.s_arprot(3'd0),.s_arvalid(arvalid),.s_arready(arready),
        .s_rdata(rdata),.s_rresp(rresp),.s_rvalid(rvalid),.s_rready(rready),
        .software_result(result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done));
    always @(posedge clk) if(resetn && dut.registers.pop) pops=pops+1;
    task reset_bus;
        begin
            @(negedge clk); resetn=0; awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0;
            repeat(3) @(negedge clk); resetn=1;
        end
    endtask
    task address;
        input [31:0] a; input integer delay;
        begin
            repeat(delay+1) @(negedge clk); awaddr=a; awvalid=1;
            @(posedge clk); while(!awready) @(posedge clk);
            @(negedge clk); awvalid=0;
        end
    endtask
    task data;
        input [31:0] d; input [3:0] st; input integer delay;
        begin
            repeat(delay+1) @(negedge clk); wdata=d; wstrb=st; wvalid=1;
            @(posedge clk); while(!wready) @(posedge clk);
            @(negedge clk); wvalid=0;
        end
    endtask
    task write;
        input [31:0] a,d; input [3:0] st;
        input integer order,stall; input [1:0] response;
        integer t;
        begin
            fork address(a,order==0?3:0); data(d,st,order==1?3:0); join
            wait(bvalid); #1;
            if(bresp!==response) $fatal(1,"FAIL: AXI B response address=%h got=%d expected=%d",a,bresp,response);
            for(t=0;t<stall;t=t+1) begin
                @(negedge clk); if(!bvalid || bresp!==response) $fatal(1,"FAIL: B response not held");
                if(awready || wready) $fatal(1,"FAIL: second write admitted while response blocked");
            end
            @(negedge clk); bready=1;
            @(posedge clk); if(!bvalid) $fatal(1,"FAIL: B handshake");
            @(negedge clk); bready=0;
        end
    endtask
    task read;
        input [31:0] a; input integer stall; input [1:0] response;
        output [31:0] d;
        integer t; reg [31:0] snapshot;
        begin
            @(negedge clk); araddr=a; arvalid=1;
            @(posedge clk); while(!arready) @(posedge clk);
            @(negedge clk); arvalid=0;
            wait(rvalid); #1; snapshot=rdata;
            if(rresp!==response) $fatal(1,"FAIL: AXI R response address=%h got=%d expected=%d",a,rresp,response);
            for(t=0;t<stall;t=t+1) begin
                @(negedge clk);
                if(!rvalid || rresp!==response || rdata!==snapshot || arready) $fatal(1,"FAIL: R response not held");
            end
            @(negedge clk); rready=1;
            @(posedge clk); if(!rvalid) $fatal(1,"FAIL: R handshake");
            d=rdata;
            @(negedge clk); rready=0;
        end
    endtask
    task idle;
        reg [31:0] s;
        begin
            s=1;
            while(s[0]) read(BASE+8,0,0,s);
        end
    endtask
    initial begin
        reset_bus;
        read(BASE,7,0,value); if(value!==32'h534e4e32) $fatal(1,"FAIL: device ID");
        // Reset must discard either half of a split write, and held responses.
        address(BASE+16,0); reset_bus; data(32'hdead,15,0);
        repeat(8) @(negedge clk); if(bvalid) $fatal(1,"FAIL: stale AW paired after reset");
        reset_bus; data(32'hdead,15,0); reset_bus; address(BASE+16,0);
        repeat(8) @(negedge clk); if(bvalid) $fatal(1,"FAIL: stale W paired after reset");
        reset_bus;
        fork address(BASE+16,0); data(32'hdead,15,0); join
        wait(bvalid); reset_bus;
        read(BASE+16,0,0,value); if(value!=8) $fatal(1,"FAIL: reset defaults");
        @(negedge clk); arvalid=1; araddr=BASE;
        @(posedge clk); while(!arready) @(posedge clk);
        @(negedge clk); arvalid=0; wait(rvalid); reset_bus;
        if(rvalid || bvalid) $fatal(1,"FAIL: reset response cancellation");
        write(BASE+16,32'habcd,15,0,5,0);
        write(BASE+16,32'hffff0012,1,1,4,0);
        write(BASE+16,32'h00003400,2,2,2,0);
        write(BASE+16,32'hffff,0,0,3,0);
        read(BASE+16,5,0,value); if(value!==32'h3412) $fatal(1,"FAIL: WSTRB merge");
        fork
            write(BASE+20,32'h55,15,1,8,0);
            begin read(BASE,8,0,value); if(value!==32'h534e4e32) $fatal(1,"FAIL: simultaneous read/write"); end
        join
        write(BASE+17,0,15,0,0,2); read(BASE+17,0,2,value);
        write(32'h50000010,1,15,1,0,3); read(32'h50000000,0,3,value);
        write(BASE+32'hffffc,1,15,2,0,3); read(BASE+32'h1000,0,3,value);
        write(BASE+4,3,1,2,0,2); write(BASE+4,1,0,2,0,0);
        if(busy) $fatal(1,"FAIL: zero-strobe command executed");
        reset_bus;
        // Only source 255 is active. Initialize its complete weight row;
        // other rows are never read in these two ticks (no recurrent spike yet).
        for(n=0;n<256;n=n+1) begin
            write(BASE+32'h1000+(65280+n)*4,7,1,n%3,0,0);
            write(BASE+32'h80000+n*4,n==255?255:0,1,n%3,0,0);
        end
        write(BASE+4,2,1,2,0,0);
        write(BASE+4,1,1,0,0,0);
        write(BASE+16,99,15,2,0,2);
        write(BASE+32'h40ffc,0,1,1,0,2);
        write(BASE+32'h80000,255,1,0,0,2);
        write(BASE+4,2,1,2,0,2); write(BASE+4,1,1,2,0,2);
        read(BASE+36,2,2,value);
        value=0;
        while(!value[31]) read(BASE+40,3,0,value);
        if(value!==32'h80000100) $fatal(1,"FAIL: first empty spike frame");
        idle;
        write(BASE+32,255,1,2,0,0); read(BASE+36,1,0,value);
        if(value!==7) $fatal(1,"FAIL: last weight/source mapping");
        write(BASE+4,1,1,1,0,0);
        wait(dut.registers.out_req); repeat(100) @(negedge clk);
        if(dut.registers.core.network.output_queue.level!=16) $fatal(1,"FAIL: full output FIFO not exercised");
        read(BASE+44,5,0,value); if(value!==32'h80000000) $fatal(1,"FAIL: output peek");
        if(pops!=1) $fatal(1,"FAIL: peek popped a packet");
        for(n=0;n<257;n=n+1) begin
            value=0;
            while(!value[31]) read(BASE+40,5,0,value);
            if(value!==(32'h80000000 | n)) $fatal(1,"FAIL: exactly-once output packet %d got=%h",n,value);
        end
        idle;
        read(BASE+40,5,0,value); if(value!=0 || pops!=258) $fatal(1,"FAIL: empty pop side effect");
        read(BASE+32'h38,0,0,value); if(value!=256) $fatal(1,"FAIL: weight writes duplicated");
        read(BASE+32'h3c,0,0,value); if(value!=256) $fatal(1,"FAIL: intensity writes duplicated");
        read(BASE+32'h40,0,0,value); if(value!=256) $fatal(1,"FAIL: spike counter");
        read(BASE+12,0,0,value); if(value!=3) $fatal(1,"FAIL: sticky completion flags");
        write(BASE+12,3,1,2,3,0); read(BASE+12,0,0,value);
        if(value!=0) $fatal(1,"FAIL: W1C flags");
        $display("PASS: independent AXI AW/W, simultaneous read/write, WSTRB, B/R stalls, reset cancellation, errors, busy rejection and 258 exactly-once packet pops");
        $finish;
    end
    initial begin #30000000; $fatal(1,"FAIL: AXI watchdog"); end
endmodule
