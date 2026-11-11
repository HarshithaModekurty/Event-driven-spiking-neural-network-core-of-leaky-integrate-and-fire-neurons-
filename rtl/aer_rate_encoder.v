// One shared 8-bit rate encoder visits all 256 sources in address order.
// A phase update that emits a spike commits only when that packet transfers.
module aer_rate_encoder (
    input wire clk,
    input wire rst,
    input wire sample_clear,
    output wire clear_ready,
    input wire intensity_write,
    output wire intensity_ready,
    input wire [7:0] intensity_addr,
    input wire [7:0] intensity_data,
    input wire tick_start,
    output wire tick_ready,
    output wire out_req,
    input wire out_ack,
    output wire [7:0] out_addr,
    output wire out_end,
    output wire busy,
    output reg tick_done
);
    localparam IDLE=0, READ=1, CALCULATE=2, COMMIT=3, END_TOKEN=4;
    reg [2:0] state;
    (* ram_style = "distributed" *) reg [7:0] intensity [0:255];
    reg [7:0] phase [0:255];
    reg [7:0] index, selected_phase, selected_intensity, result_phase;
    reg result_fire;
    integer neuron;
    wire arithmetic_fire;
    wire [7:0] arithmetic_phase;
    assign busy = (state != IDLE);
    assign clear_ready = !rst && !busy;
    assign intensity_ready = clear_ready && !sample_clear;
    assign tick_ready = intensity_ready && !intensity_write;
    assign out_req = !rst && ((state == END_TOKEN) || ((state == COMMIT) && result_fire));
    assign out_addr = (state == END_TOKEN) ? 8'd0 : index;
    assign out_end = (state == END_TOKEN);
    rate_encoder_transition transition (
        .phase(selected_phase), .intensity(selected_intensity),
        .fire(arithmetic_fire), .phase_next(arithmetic_phase)
    );
    // Sample reset preserves programmed intensities, just as SNN reset preserves weights.
    always @(posedge clk)
        if (intensity_write && intensity_ready) intensity[intensity_addr] <= intensity_data;
    always @(posedge clk) begin
        if (rst || (sample_clear && clear_ready)) begin
            state <= IDLE;
            index <= 0;
            selected_phase <= 0;
            selected_intensity <= 0;
            result_phase <= 0;
            result_fire <= 0;
            tick_done <= 0;
            for (neuron=0; neuron<256; neuron=neuron+1) phase[neuron] <= 0;
        end else begin
            tick_done <= 0;
            case (state)
                IDLE: if (tick_start && tick_ready) begin index <= 0; state <= READ; end
                READ: begin
                    selected_phase <= phase[index];
                    selected_intensity <= intensity[index];
                    state <= CALCULATE;
                end
                CALCULATE: begin
                    result_phase <= arithmetic_phase;
                    result_fire <= arithmetic_fire;
                    state <= COMMIT;
                end
                COMMIT: if (!result_fire || out_ack) begin
                    phase[index] <= result_phase;
                    if (index == 255) state <= END_TOKEN;
                    else begin index <= index + 1'b1; state <= READ; end
                end
                END_TOKEN: if (out_ack) begin tick_done <= 1; state <= IDLE; end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
