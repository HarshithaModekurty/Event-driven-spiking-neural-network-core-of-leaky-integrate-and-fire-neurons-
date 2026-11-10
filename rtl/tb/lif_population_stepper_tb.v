`timescale 1ns / 1ps

module lif_population_stepper_tb;

    parameter NUM_NEURONS = 4;
    parameter ADDR_WIDTH = 2;
    parameter NUM_TIME_STEPS = 64;
    parameter SPIKE_WORDS = (NUM_NEURONS + 31) / 32;
    parameter VECTOR_FIELDS = 5 + 3*NUM_NEURONS + SPIKE_WORDS;

    reg clk;
    reg rst;
    reg start;
    reg current_write;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg signed [31:0] current_data;
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

    integer vectors_checked;
    integer failed;
    integer vector_values[0:VECTOR_FIELDS-1];
    integer neuron;
    integer field_index;
    integer spike_word;
    integer transaction;
    reg [NUM_NEURONS-1:0] expected_spikes;
    integer expected_membrane[0:NUM_NEURONS-1];
    integer expected_refractory[0:NUM_NEURONS-1];
    reg [32*VECTOR_FIELDS-1:0] vector_memory[0:NUM_TIME_STEPS-1];

    always #5 clk = ~clk;

    lif_population_stepper #(
        .NUM_NEURONS(NUM_NEURONS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .current_write(current_write),
        .current_addr(current_addr),
        .current_data(current_data),
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
        $dumpfile("build/lif_population/lif_population_stepper.vcd");
        $dumpvars(0, lif_population_stepper_tb);
`endif
        rst = 1'b1;
        start = 1'b0;
        current_write = 1'b0;
        current_addr = {ADDR_WIDTH{1'b0}};
        current_data = 32'sd0;
        threshold = 16'd0;
        reset_value = 16'd0;
        leak_enable = 1'b0;
        leak_shift = 5'd0;
        refractory_period = 16'd0;
        state_read_addr = {ADDR_WIDTH{1'b0}};
        vectors_checked = 0;
        failed = 0;
        $display("INFO: loading Python population vectors from D:/RTL_PROJECT/build/lif_population/lif_population_vectors.hex");
        $readmemh("D:/RTL_PROJECT/build/lif_population/lif_population_vectors.hex", vector_memory);
        threshold = vector_memory[0] >> 0;
        reset_value = vector_memory[0] >> 32;
        leak_enable = vector_memory[0] >> 64;
        leak_shift = vector_memory[0] >> 96;
        refractory_period = vector_memory[0] >> 128;

        @(posedge clk);
        #1;
        rst = 1'b0;

        for (transaction = 0; transaction < NUM_TIME_STEPS; transaction = transaction + 1) begin
            for (field_index = 0; field_index < VECTOR_FIELDS; field_index = field_index + 1) begin
                vector_values[field_index] = vector_memory[transaction] >> (32*field_index);
            end
            threshold = vector_values[0];
            reset_value = vector_values[1];
            leak_enable = vector_values[2];
            leak_shift = vector_values[3];
            refractory_period = vector_values[4];
            expected_spikes = {NUM_NEURONS{1'b0}};
            for (neuron = 0; neuron < NUM_NEURONS; neuron = neuron + 1) begin
                spike_word = vector_values[5 + NUM_NEURONS + neuron/32];
                expected_spikes[neuron] = (spike_word >> (neuron % 32)) & 1;
            end
            for (neuron = 0; neuron < NUM_NEURONS; neuron = neuron + 1) begin
                expected_membrane[neuron] = vector_values[5 + NUM_NEURONS + SPIKE_WORDS + neuron];
                expected_refractory[neuron] = vector_values[5 + 2*NUM_NEURONS + SPIKE_WORDS + neuron];

                @(negedge clk);
                current_write = 1'b1;
                current_addr = neuron;
                current_data = vector_values[neuron + 5];
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            current_write = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            start = 1'b0;

            begin : wait_for_step_done
                reg complete;
                complete = 1'b0;
                while (!complete) begin
                    @(posedge clk);
                    #1;
                    complete = done;
                end
            end

            if (spike_vector !== expected_spikes[NUM_NEURONS-1:0]) begin
                $display("FAIL: transaction %0d spike vector got %h expected %h", transaction + 1, spike_vector, expected_spikes);
                failed = 1;
            end

            for (neuron = 0; neuron < NUM_NEURONS; neuron = neuron + 1) begin
                state_read_addr = neuron;
                #1;
                if (state_read_membrane !== expected_membrane[neuron][15:0] ||
                    state_read_refractory !== expected_refractory[neuron][15:0]) begin
                    $display(
                        "FAIL: transaction %0d neuron %0d membrane=%0d/%0d refractory=%0d/%0d",
                        transaction + 1, neuron, state_read_membrane, expected_membrane[neuron],
                        state_read_refractory, expected_refractory[neuron]
                    );
                    failed = 1;
                end
            end
            vectors_checked = vectors_checked + 1;
            @(negedge clk);
        end

        if (failed) begin
            $display("FAIL: population comparison failed after %0d time steps", vectors_checked);
        end else begin
            $display("PASS: matched Python model for %0d population time steps (%0d neurons)", vectors_checked, NUM_NEURONS);
        end
        $finish;
    end

endmodule