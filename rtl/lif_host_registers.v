// Native register backend used behind an AXI4-Lite endpoint.
// Full address decoding: 0x40000000..0x400fffff, no aliases outside it.
module lif_host_registers (
    input wire clk, input wire resetn,
    input wire wr_enable, input wire [31:0] wr_addr, wr_data,
    input wire [3:0] wr_strb, output reg [1:0] wr_resp,
    input wire rd_enable, input wire [31:0] rd_addr,
    output reg [31:0] rd_data, output reg [1:0] rd_resp,
    output reg [31:0] software_result,
    output wire busy, output wire tick_done, frame_done,
    output wire input_event_valid, output wire [8:0] input_event_packet,
    output wire output_event_valid, output wire [8:0] output_event_packet,
    output wire [7:0] debug_state_address
);
    localparam OKAY=2'b00, SLVERR=2'b10, DECERR=2'b11;
    reg [15:0] threshold, reset_value, refractory_period;
    reg [8:0] leak_config;
    reg [7:0] state_address;
    reg tick_pending, frame_pending;
    reg host_active;
    reg clear;
    reg [31:0] ticks, frames, weight_writes, intensity_writes, output_spikes;
    wire [19:0] wa=wr_addr[19:0], ra=rd_addr[19:0];
    wire wregion=(wr_addr[31:20]==12'h400), rregion=(rd_addr[31:20]==12'h400);
    wire [19:0] weight_offset=wa-20'h01000;
    wire weight_window=(wa>=20'h01000 && wa<20'h41000);
    wire intensity_window=(wa>=20'h80000 && wa<20'h80400);
    wire clear_ready, tick_ready, weight_ready, intensity_ready;
    wire out_req, out_end;
    wire [7:0] out_addr;
    wire [15:0] membrane, refractory;
    wire [255:0] spikes;
    wire core_busy;
    assign busy=host_active || clear;
    wire accepted_write=wr_enable && (wr_resp==OKAY);
    // Admission uses the registered core's busy state. Do not feed the
    // response decoder back through ready/reset into its own command enables.
    wire writable=wr_enable && wregion && wr_addr[1:0]==0 && !busy;
    wire command=writable && wa==20'h00004 && wr_strb[0];
    wire start=command && wr_data[7:0]==8'd1;
    wire request_clear=command && wr_data[7:0]==8'd2;
    wire write_weight=writable && weight_window && wr_strb[0];
    wire write_intensity=writable && intensity_window && wr_strb[0];
    wire pop=rd_enable && (rd_resp==OKAY) && ra==20'h00028 && out_req;
    assign output_event_valid=pop;
    assign output_event_packet={out_end,out_addr};
    assign debug_state_address=state_address;
    wire [31:0] output_word=out_req ? {1'b1,22'd0,out_end,out_addr} : 32'd0;
    function [31:0] merge_bytes;
        input [31:0] old_value, value; input [3:0] strobe;
        integer b;
        begin
            merge_bytes=old_value;
            for(b=0;b<4;b=b+1) if(strobe[b]) merge_bytes[b*8+:8]=value[b*8+:8];
        end
    endfunction
    wire [31:0] threshold_merge=merge_bytes({16'd0,threshold},wr_data,wr_strb);
    wire [31:0] reset_merge=merge_bytes({16'd0,reset_value},wr_data,wr_strb);
    wire [31:0] leak_merge=merge_bytes({23'd0,leak_config},wr_data,wr_strb);
    wire [31:0] refractory_merge=merge_bytes({16'd0,refractory_period},wr_data,wr_strb);
    wire [31:0] address_merge=merge_bytes({24'd0,state_address},wr_data,wr_strb);
    always @* begin
        wr_resp=OKAY;
        if(!wregion) wr_resp=DECERR;
        else if(wr_addr[1:0]!=0) wr_resp=SLVERR;
        else if(weight_window) begin
            if(wr_strb[0] && busy) wr_resp=SLVERR;
        end else if(intensity_window) begin
            if(wr_strb[0] && busy) wr_resp=SLVERR;
        end else case(wa)
            20'h00004: if(wr_strb[0]) begin
                if(wr_data[7:2]!=0 || wr_data[1:0]==2'b11) wr_resp=SLVERR;
                else if((|wr_data[1:0]) && busy) wr_resp=SLVERR;
            end
            20'h0000c,20'h00044: begin end
            20'h00010,20'h00014,20'h00018,20'h0001c,20'h00020:
                if((|wr_strb) && busy) wr_resp=SLVERR;
            default: wr_resp=DECERR;
        endcase
    end
    always @* begin
        rd_data=0; rd_resp=OKAY;
        if(!rregion) rd_resp=DECERR;
        else if(rd_addr[1:0]!=0) rd_resp=SLVERR;
        else case(ra)
            20'h00000: rd_data=32'h534e4e32;
            20'h00004: rd_data=0;
            20'h00008: rd_data={26'd0,frame_pending,tick_pending,out_req,clear_ready,tick_ready,busy};
            20'h0000c: rd_data={30'd0,frame_pending,tick_pending};
            20'h00010: rd_data={16'd0,threshold};
            20'h00014: rd_data={16'd0,reset_value};
            20'h00018: rd_data={23'd0,leak_config};
            20'h0001c: rd_data={16'd0,refractory_period};
            20'h00020: rd_data={24'd0,state_address};
            20'h00024: if(busy) rd_resp=SLVERR; else rd_data={refractory,membrane};
            20'h00028,20'h0002c: rd_data=output_word;
            20'h00030: rd_data=ticks;
            20'h00034: rd_data=frames;
            20'h00038: rd_data=weight_writes;
            20'h0003c: rd_data=intensity_writes;
            20'h00040: rd_data=output_spikes;
            20'h00044: rd_data=software_result;
            default: rd_resp=DECERR;
        endcase
    end
    lif_rate_aer_snn_core core (
        .clk(clk),.rst(!resetn),.sample_clear(clear),.clear_ready(clear_ready),
        .intensity_write(write_intensity),.intensity_ready(intensity_ready),
        .intensity_addr(wa[9:2]),.intensity_data(wr_data[7:0]),
        .tick_start(start),.tick_ready(tick_ready),
        .out_req(out_req),.out_ack(pop),.out_addr(out_addr),.out_end(out_end),
        .weight_write(write_weight),.weight_ready(weight_ready),
        .weight_source_addr(weight_offset[17:10]),.weight_destination_addr(weight_offset[9:2]),.weight_data(wr_data[3:0]),
        .threshold(threshold),.reset_value(reset_value),.leak_enable(leak_config[8]),
        .leak_shift(leak_config[4:0]),.refractory_period(refractory_period),
        .state_read_addr(state_address),.state_read_membrane(membrane),.state_read_refractory(refractory),
        .spike_vector(spikes),.busy(core_busy),.tick_done(tick_done),.frame_done(frame_done),
        .input_event_valid(input_event_valid),.input_event_packet(input_event_packet)
    );
    always @(posedge clk) begin
        if(!resetn) begin
            threshold<=8; reset_value<=0; leak_config<=0; refractory_period<=0; state_address<=0;
            tick_pending<=0; frame_pending<=0; ticks<=0; frames<=0;
            weight_writes<=0; intensity_writes<=0; output_spikes<=0; software_result<=0;
            host_active<=0; clear<=0;
        end else begin
            // Decode AXI once, then drive the wide sample-reset/readiness
            // network from a flip-flop. Keep admission busy for this cycle.
            clear<=request_clear;
            if(start) host_active<=1;
            else if(frame_done) host_active<=0;
            if(accepted_write) case(wa)
                20'h0000c: if(wr_strb[0]) begin
                    if(wr_data[0]) tick_pending<=0;
                    if(wr_data[1]) frame_pending<=0;
                end
                20'h00010: threshold<=threshold_merge[15:0];
                20'h00014: reset_value<=reset_merge[15:0];
                20'h00018: leak_config<=leak_merge[8:0] & 9'h11f;
                20'h0001c: refractory_period<=refractory_merge[15:0];
                20'h00020: state_address<=address_merge[7:0];
                20'h00044: software_result<=merge_bytes(software_result,wr_data,wr_strb);
            endcase
            // An arriving event wins over a simultaneous write-one-to-clear.
            if(tick_done) begin tick_pending<=1; ticks<=ticks+1; end
            if(frame_done) begin frame_pending<=1; frames<=frames+1; end
            if(write_weight) weight_writes<=weight_writes+1;
            if(write_intensity) intensity_writes<=intensity_writes+1;
            if(pop && !out_end) output_spikes<=output_spikes+1;
        end
    end
endmodule
