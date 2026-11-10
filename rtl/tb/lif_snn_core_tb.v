`timescale 1ns / 1ps

module lif_snn_core_tb;

    parameter NUM_NEURONS = 4;
    parameter ADDR_WIDTH = 2;
    parameter NUM_TRANSACTIONS = 24;
    parameter SPIKE_WORDS = (NUM_NEURONS + 31) / 32;
    parameter VECTOR_FIELDS = 5 + 2*SPIKE_WORDS + 2*NUM_NEURONS;

    reg clk;
    reg rst;
    reg step_start;
    reg [NUM_NEURONS-1:0] input_spikes;
    reg weight_write;
    reg [ADDR_WIDTH-1:0] weight_source_addr;
    reg [ADDR_WIDTH-1:0] weight_destination_addr;
    reg signed [3:0] weight_data;
    reg [15:0] threshold;
    reg [15:0] reset_value;
    reg leak_enable;
    reg [4:0] leak_shift;
    reg [15:0] refractory_period;
    reg [ADDR_WIDTH-1:0] state_read_addr;
    wire [15:0] state_read_membrane;
    wire [15:0] state_read_refractory;
    wire [NUM_NEURONS-1:0] spike_vector;
    wire busy;
    wire done;

    reg [31:0] weight_memory [0:NUM_NEURONS*NUM_NEURONS-1];
    reg [32*VECTOR_FIELDS-1:0] vector_memory [0:NUM_TRANSACTIONS-1];
    integer vector_values [0:VECTOR_FIELDS-1];
    integer expected_membrane [0:NUM_NEURONS-1];
    integer expected_refractory [0:NUM_NEURONS-1];
    integer weight_index;
    integer field_index;
    integer transaction;
    integer neuron;
    integer spike_word;
    integer failed;
    integer vectors_checked;
    reg [NUM_NEURONS-1:0] expected_spikes;

    always #5 clk = ~clk;

    lif_snn_core #(
        .NUM_NEURONS(NUM_NEURONS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .step_start(step_start),
        .input_spikes(input_spikes),
        .weight_write(weight_write),
        .weight_source_addr(weight_source_addr),
        .weight_destination_addr(weight_destination_addr),
        .weight_data(weight_data),
        .threshold(threshold),
        .reset_value(reset_value),
        .leak_enable(leak_enable),
        .leak_shift(leak_shift),
        .refractory_period(refractory_period),
        .state_read_addr(state_read_addr),
        .state_read_membrane(state_read_membrane),
        .state_read_refractory(state_read_refractory),
        .spike_vector(spike_vector),
        .busy(busy),
        .done(done)
    );

    initial begin
        clk = 1'b0;
`ifdef IVERILOG
        if (NUM_NEURONS <= 4) begin
            $dumpfile("build/lif_snn_core/lif_snn_core.vcd");
            $dumpvars(0, lif_snn_core_tb);
        end
`endif
        rst = 1'b1;
        step_start = 1'b0;
        input_spikes = {NUM_NEURONS{1'b0}};
        weight_write = 1'b0;
        weight_source_addr = {ADDR_WIDTH{1'b0}};
        weight_destination_addr = {ADDR_WIDTH{1'b0}};
        weight_data = 4'sd0;
        threshold = 16'd0;
        reset_value = 16'd0;
        leak_enable = 1'b0;
        leak_shift = 5'd0;
        refractory_period = 16'd0;
        state_read_addr = {ADDR_WIDTH{1'b0}};
        failed = 0;
        vectors_checked = 0;

        $display("INFO: loading Python weights/vectors from D:/RTL_PROJECT/build/lif_snn_core");
        $readmemh("D:/RTL_PROJECT/build/lif_snn_core/synapse_weights.hex", weight_memory);
        $readmemh("D:/RTL_PROJECT/build/lif_snn_core/lif_snn_vectors.hex", vector_memory);
        threshold = vector_memory[0] >> 0;
        reset_value = vector_memory[0] >> 32;
        leak_enable = vector_memory[0] >> 64;
        leak_shift = vector_memory[0] >> 96;
        refractory_period = vector_memory[0] >> 128;

        @(posedge clk);
        #1;
        rst = 1'b0;

        for (weight_index = 0; weight_index < NUM_NEURONS*NUM_NEURONS; weight_index = weight_index + 1) begin
            @(negedge clk);
            weight_write = 1'b1;
            weight_source_addr = weight_index / NUM_NEURONS;
            weight_destination_addr = weight_index % NUM_NEURONS;
            weight_data = weight_memory[weight_index][3:0];
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        weight_write = 1'b0;

        for (transaction = 0; transaction < NUM_TRANSACTIONS; transaction = transaction + 1) begin
            for (field_index = 0; field_index < VECTOR_FIELDS; field_index = field_index + 1) begin
                vector_values[field_index] = vector_memory[transaction] >> (32*field_index);
            end

            for (field_index = 0; field_index < 5; field_index = field_index + 1) begin
                case (field_index)
                    0: threshold = vector_values[field_index];
                    1: reset_value = vector_values[field_index];
                    2: leak_enable = vector_values[field_index];
                    3: leak_shift = vector_values[field_index];
                    4: refractory_period = vector_values[field_index];
                endcase
            end

            input_spikes = {NUM_NEURONS{1'b0}};
            expected_spikes = {NUM_NEURONS{1'b0}};
            for (neuron = 0; neuron < NUM_NEURONS; neuron = neuron + 1) begin
                spike_word = vector_values[5 + neuron/32];
                input_spikes[neuron] = (spike_word >> (neuron%32)) & 1;
                spike_word = vector_values[5 + SPIKE_WORDS + neuron/32];
                expected_spikes[neuron] = (spike_word >> (neuron%32)) & 1;
                expected_membrane[neuron] = vector_values[5 + 2*SPIKE_WORDS + neuron];
                expected_refractory[neuron] = vector_values[5 + 2*SPIKE_WORDS + NUM_NEURONS + neuron];
            end

            @(negedge clk);
            step_start = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            step_start = 1'b0;

            begin : wait_for_core_done
                reg complete;
                complete = 1'b0;
                while (!complete) begin
                    @(posedge clk);
                    #1;
                    complete = done;
                end
            end

            if (spike_vector !== expected_spikes) begin
                $display("FAIL: transaction %0d spikes got %h expected %h", transaction + 1, spike_vector, expected_spikes);
                failed = 1;
            end
            for (neuron = 0; neuron < NUM_NEURONS; neuron = neuron + 1) begin
                state_read_addr = neuron;
                #1;
                if (state_read_membrane !== expected_membrane[neuron][15:0] ||
                    state_read_refractory !== expected_refractory[neuron][15:0]) begin
                    $display("FAIL: transaction %0d neuron %0d state membrane=%0d/%0d refractory=%0d/%0d",
                        transaction + 1, neuron, state_read_membrane, expected_membrane[neuron],
                        state_read_refractory, expected_refractory[neuron]);
                    failed = 1;
                end
            end
            vectors_checked = vectors_checked + 1;
            @(negedge clk);
        end

        if (failed) begin
            $display("FAIL: integrated SNN comparison failed after %0d transactions", vectors_checked);
        end else begin
            $display("PASS: matched Python SNN model for %0d transactions (%0d neurons)", vectors_checked, NUM_NEURONS);
        end
        $finish;
    end

endmodule
