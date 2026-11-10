// Framed, synchronous AER interface around the unchanged 256-state LIF core.
// Each port sends a separate end token per tick; end tokens carry no spike.
module lif_aer_snn_core #(
    parameter INPUT_DEPTH = 16,
    parameter OUTPUT_DEPTH = 16
) (
    input wire clk,
    input wire rst,
    input wire [3:0] in_req,
    output wire [3:0] in_ack,
    input wire [31:0] in_addr,
    input wire [3:0] in_end,
    output wire out_req,
    input wire out_ack,
    output wire [7:0] out_addr,
    output wire out_end,
    input wire weight_write,
    output wire weight_ready,
    input wire [7:0] weight_source_addr,
    input wire [7:0] weight_destination_addr,
    input wire signed [3:0] weight_data,
    input wire [15:0] threshold,
    input wire [15:0] reset_value,
    input wire leak_enable,
    input wire [4:0] leak_shift,
    input wire [15:0] refractory_period,
    input wire [7:0] state_read_addr,
    output wire [15:0] state_read_membrane,
    output wire [15:0] state_read_refractory,
    output wire [255:0] spike_vector,
    output wire busy,
    output reg tick_done,
    output reg frame_done
);
    localparam COLLECT = 0, LAUNCH = 1, COMPUTE = 2,
               EMIT = 3, END_TOKEN = 4, DRAIN = 5;
    reg [2:0] state;
    reg [3:0] closed_ports;
    reg [255:0] input_bitmap, emit_bitmap;
    reg [7:0] emit_index;
    reg [15:0] step_threshold, step_reset, step_refractory;
    reg step_leak_enable;
    reg [4:0] step_leak_shift;
    wire [3:0] fifo_valid, fifo_take, held_grant;
    wire [35:0] fifo_heads;
    wire arb_req;
    wire [8:0] arb_data;
    wire arb_ack = (state == COLLECT) && arb_req && !rst;
    wire [3:0] eligible = (state == COLLECT) ? (fifo_valid & ~closed_ports) : 4'b0;
    wire output_ready, output_valid;
    wire [8:0] output_data;
    wire core_busy, core_done;
    wire core_start = (state == LAUNCH);
    wire send_spike = (state == EMIT) && emit_bitmap[emit_index];
    wire output_put = send_spike || (state == END_TOKEN);
    wire [8:0] output_put_data = (state == END_TOKEN) ? 9'h100 : {1'b0, emit_index};

    assign fifo_take = held_grant & {4{arb_ack}};
    assign out_req = output_valid;
    assign out_end = output_data[8];
    assign out_addr = output_data[7:0];
    assign busy = (state != COLLECT) || (|closed_ports) || (|fifo_valid) || arb_req || (|input_bitmap);
    // Input traffic has priority over a simultaneous configuration write.
    assign weight_ready = !rst && !busy && !(|in_req) && !core_busy;

    genvar port;
    generate for (port = 0; port < 4; port = port + 1) begin: inputs
        aer_event_fifo #(.WIDTH(9), .DEPTH(INPUT_DEPTH)) queue (
            .clk(clk), .rst(rst), .push_valid(in_req[port]), .push_ready(in_ack[port]),
            .push_data({in_end[port], in_addr[8*port +: 8]}),
            .pop_valid(fifo_valid[port]), .pop_ready(fifo_take[port]),
            .pop_data(fifo_heads[9*port +: 9]), .level()
        );
    end endgenerate
    aer_rr_arbiter #(.WIDTH(9)) arbiter (
        .clk(clk), .rst(rst), .requests(eligible), .addresses(fifo_heads),
        .out_req(arb_req), .out_ack(arb_ack), .out_data(arb_data),
        .held_grant(held_grant), .held_port()
    );
    aer_event_fifo #(.WIDTH(9), .DEPTH(OUTPUT_DEPTH)) output_queue (
        .clk(clk), .rst(rst), .push_valid(output_put), .push_ready(output_ready),
        .push_data(output_put_data), .pop_valid(output_valid), .pop_ready(out_ack),
        .pop_data(output_data), .level()
    );
    lif_snn_core core (
        .clk(clk), .rst(rst), .step_start(core_start), .input_spikes(input_bitmap),
        .weight_write(weight_write && weight_ready),
        .weight_source_addr(weight_source_addr), .weight_destination_addr(weight_destination_addr),
        .weight_data(weight_data), .threshold(step_threshold),
        .reset_value(rst ? reset_value : step_reset),
        .leak_enable(step_leak_enable), .leak_shift(step_leak_shift),
        .refractory_period(step_refractory), .state_read_addr(state_read_addr),
        .state_read_membrane(state_read_membrane), .state_read_refractory(state_read_refractory),
        .spike_vector(spike_vector), .busy(core_busy), .done(core_done)
    );
    always @(posedge clk) begin
        if (rst) begin
            state <= COLLECT;
            closed_ports <= 0;
            input_bitmap <= 0;
            emit_bitmap <= 0;
            emit_index <= 0;
            step_threshold <= 0;
            step_reset <= 0;
            step_refractory <= 0;
            step_leak_enable <= 0;
            step_leak_shift <= 0;
            tick_done <= 0;
            frame_done <= 0;
        end else begin
            tick_done <= 0;
            frame_done <= 0;
            case (state)
                COLLECT: begin
                    if (arb_ack) begin
                        if (arb_data[8]) closed_ports <= closed_ports | held_grant;
                        else input_bitmap[arb_data[7:0]] <= 1'b1;
                    end
                    if (&closed_ports) state <= LAUNCH;
                end
                LAUNCH: begin
                    step_threshold <= threshold;
                    step_reset <= reset_value;
                    step_refractory <= refractory_period;
                    step_leak_enable <= leak_enable;
                    step_leak_shift <= leak_shift;
                    state <= COMPUTE;
                end
                COMPUTE: if (core_done) begin
                    emit_bitmap <= spike_vector;
                    emit_index <= 0;
                    tick_done <= 1;
                    state <= EMIT;
                end
                EMIT: if (!emit_bitmap[emit_index] || output_ready) begin
                    if (emit_index == 255) state <= END_TOKEN;
                    else emit_index <= emit_index + 1'b1;
                end
                END_TOKEN: if (output_ready) state <= DRAIN;
                DRAIN: if (out_req && out_ack && out_end) begin
                    input_bitmap <= 0;
                    closed_ports <= 0;
                    frame_done <= 1;
                    state <= COLLECT;
                end
                default: state <= COLLECT;
            endcase
        end
    end
endmodule
