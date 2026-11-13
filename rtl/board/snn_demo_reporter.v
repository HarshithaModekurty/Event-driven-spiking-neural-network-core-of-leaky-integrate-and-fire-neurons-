// Observe actual accepted CPU/AER transactions. Pauses the CPU between images
// using AXI backpressure; the clock and the SNN datapath keep running.
module snn_demo_reporter #(
    parameter SAMPLES=20, parameter UART_CLKS_PER_BIT=868
) (
    input wire clk, resetn, next_pulse,
    input wire trace_write_valid, input wire [31:0] trace_write_addr,trace_write_data,
    input wire trace_read_valid, input wire [31:0] trace_read_addr,trace_read_data,
    input wire [7:0] trace_state_address,
    input wire input_event_valid, input wire [8:0] input_event_packet,
    input wire output_event_valid, input wire [8:0] output_event_packet,
    input wire cpu_trap,bus_fault, input wire [31:0] software_result,
    output wire demo_run, uart_tx,
    output reg snapshot_pulse, snapshot_valid,
    output reg [7:0] sample_index,
    output reg [3:0] predicted_digit,
    output reg [159:0] scores,
    output reg error,
    output wire waiting, transmitting, complete,
    output reg [13:0] capture_count
);
    localparam WAIT_START=0,RUN=1,HEADER=2,READ_EVENT=3,WAIT_EVENT=4,
        EVENT=5,DRAIN=6,WAIT_NEXT=7,FINISH=8;
    reg [3:0] state;
    reg [5:0] char_index;
    reg [12:0] read_index;
    reg [15:0] event_word;
    reg [2:0] input_tick,output_tick;
    (* ram_style="block" *) reg [15:0] raster [0:8191];
    wire capture_input=state==RUN && input_event_valid;
    wire capture_output=state==RUN && output_event_valid;
    wire [1:0] additions={1'b0,capture_input}+{1'b0,capture_output};
    wire room=capture_count+additions<=14'd8192;
    wire [13:0] output_index=capture_count+{13'd0,capture_input};
    wire [12:0] port_a_address=capture_input ? capture_count[12:0] : read_index;
    wire port_a_enable=(capture_input && room) || state==READ_EVENT;
    wire class_write=trace_write_valid && trace_write_addr[31:8]==24'h0000c0;
    wire uart_ready;
    reg [7:0] uart_data;
    wire uart_valid=state==HEADER || state==EVENT;
    assign demo_run=state==RUN || state==FINISH;
    assign waiting=state==WAIT_START || state==WAIT_NEXT;
    assign transmitting=state>=HEADER && state<=DRAIN;
    assign complete=software_result==32'h600d600d;
    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) serial (
        .clk(clk),.resetn(resetn),.valid(uart_valid),.data(uart_data),
        .ready(uart_ready),.tx(uart_tx));

    // True dual-port RAM: port A records input or reads while CPU is paused;
    // port B records output, including simultaneous input/output handshakes.
    always @(posedge clk) begin
        if(port_a_enable) begin
            if(capture_input) raster[port_a_address]<={3'b0,1'b0,input_tick,input_event_packet};
            event_word<=raster[port_a_address];
        end
    end
    always @(posedge clk) begin
        if(capture_output && room) raster[output_index[12:0]]<={3'b0,1'b1,output_tick,output_event_packet};
    end
    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar=value<10 ? 8'd48+value : 8'd65+value-10; end
    endfunction
    integer score_number,nibble_number;
    always @* begin
        uart_data=8'h2c; score_number=0; nibble_number=0;
        if(state==HEADER) begin
            case(char_index)
                0:uart_data="C";
                2:uart_data=hexchar(sample_index[7:4]);
                3:uart_data=hexchar(sample_index[3:0]);
                5:uart_data=hexchar(predicted_digit);
                56:uart_data=13;
                57:uart_data=10;
                default:if(char_index>=6 && char_index<=55 && (char_index-6)%5!=0) begin
                    score_number=(char_index-6)/5;
                    nibble_number=4-(char_index-6)%5;
                    uart_data=hexchar(scores[score_number*16+nibble_number*4+:4]);
                end
            endcase
        end else begin
            case(char_index)
                0:uart_data=event_word[12] ? "O" : "I";
                2:uart_data=hexchar(sample_index[7:4]);
                3:uart_data=hexchar(sample_index[3:0]);
                5:uart_data=hexchar({1'b0,event_word[11:9]});
                7:uart_data=hexchar({3'b0,event_word[8]});
                8:uart_data=hexchar(event_word[7:4]);
                9:uart_data=hexchar(event_word[3:0]);
                10:uart_data=13;
                11:uart_data=10;
                default:uart_data=",";
            endcase
        end
    end
    always @(posedge clk) begin
        if(!resetn) begin
            state<=WAIT_START; sample_index<=0; predicted_digit<=0; scores<=0;
            snapshot_pulse<=0; snapshot_valid<=0; error<=0;
            capture_count<=0; input_tick<=0; output_tick<=0;
            read_index<=0; char_index<=0;
        end else begin
            snapshot_pulse<=0;
            if(bus_fault || software_result==32'hdead0001 || (cpu_trap && !complete)) error<=1;
            if(state==RUN) begin
                if(!room) error<=1;
                else capture_count<=capture_count+additions;
                if(capture_input && input_event_packet[8]) input_tick<=input_tick+1'b1;
                if(capture_output && output_event_packet[8]) output_tick<=output_tick+1'b1;
                if(trace_read_valid && trace_read_addr==32'h40000024 && trace_state_address>=246)
                    scores[(trace_state_address-246)*16+:16]<=trace_read_data[15:0];
            end
            case(state)
                WAIT_START:if(next_pulse) state<=RUN;
                RUN:if(class_write) begin
                    if(trace_write_addr!=32'hc000+{22'd0,sample_index,2'b0} || trace_write_data>9) error<=1;
                    predicted_digit<=trace_write_data[3:0];
                    snapshot_pulse<=1; snapshot_valid<=1;
                    char_index<=0; state<=HEADER;
                end
                HEADER:if(uart_ready) begin
                    if(char_index==57) begin
                        char_index<=0; read_index<=0;
                        state<=capture_count==0 ? DRAIN : READ_EVENT;
                    end else char_index<=char_index+1'b1;
                end
                READ_EVENT:state<=WAIT_EVENT;
                WAIT_EVENT:begin char_index<=0; state<=EVENT; end
                EVENT:if(uart_ready) begin
                    if(char_index==11) begin
                        if({1'b0,read_index}+14'd1==capture_count) state<=DRAIN;
                        else begin read_index<=read_index+1'b1; state<=READ_EVENT; end
                    end else char_index<=char_index+1'b1;
                end
                DRAIN:if(uart_ready) state<=sample_index==SAMPLES-1 ? FINISH : WAIT_NEXT;
                WAIT_NEXT:if(next_pulse) begin
                    sample_index<=sample_index+1'b1; capture_count<=0;
                    input_tick<=0; output_tick<=0; snapshot_valid<=0; state<=RUN;
                end
                FINISH:state<=FINISH;
                default:begin state<=WAIT_START; error<=1; end
            endcase
        end
    end
endmodule
