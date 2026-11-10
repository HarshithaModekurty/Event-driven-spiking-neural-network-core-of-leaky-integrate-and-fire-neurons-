`timescale 1ns / 1ps

module lif_mnist_tb;
    parameter NUM_SAMPLES = 20;
    parameter DATA_DIR = "D:/RTL_PROJECT/build/mnist256";
    localparam NUM_NEURONS = 256;
    localparam NUM_SOURCES = 256;
    localparam INPUT_WORDS = 8;
    localparam TICKS = 8;
    localparam VECTOR_FIELDS = 533;
    localparam MEMBRANE_FIELD = 20;
    localparam REFRACTORY_FIELD = 276;

    reg clk = 0;
    reg rst;
    reg step_start;
    reg [255:0] input_spikes;
    reg weight_write;
    reg [7:0] weight_source_addr;
    reg [7:0] weight_destination_addr;
    reg signed [3:0] weight_data;
    reg [7:0] debug_addr;
    wire [7:0] state_read_addr;
    wire [15:0] state_read_membrane;
    wire [15:0] state_read_refractory;
    wire [255:0] spike_vector;
    wire busy;
    wire done;
    reg readout_start;
    wire readout_busy;
    wire readout_done;
    wire [7:0] readout_addr;
    wire [7:0] rtl_prediction;
    wire [15:0] winning_score;
    reg [3:0] weight_memory [0:65535];
    reg [32*VECTOR_FIELDS-1:0] vector_memory [0:NUM_SAMPLES*TICKS-1];
    integer fields [0:VECTOR_FIELDS-1];
    integer actual_scores [0:9];
    integer sample_number;
    integer image_test_index;
    integer true_digit;
    integer python_prediction;
    integer vector_index;
    integer field_index;
    integer weight_index;
    integer source_index;
    integer neuron;
    integer wait_cycles;
    integer failed;
    integer correct;
    integer checked;
    integer updates_in_step = 0;
    reg [255:0] expected_spikes;
    integer result_file;
    integer check_file;

    always #5 clk = ~clk;
    // Check that the shared datapath visits every actual state once per tick.
    always @(posedge clk) begin
        if (dut.population_stepper.update_commit) begin
            if (dut.population_stepper.neuron_index !== updates_in_step[7:0]) begin
                $display("FAIL: population scan order got=%0d expected=%0d", dut.population_stepper.neuron_index, updates_in_step);
                failed = 1;
            end
            updates_in_step = updates_in_step + 1;
        end
    end
    assign state_read_addr = readout_busy ? readout_addr : debug_addr;

    lif_snn_core #(
        .NUM_NEURONS(256), .ADDR_WIDTH(8)
    ) dut (
        .clk(clk), .rst(rst), .step_start(step_start), .input_spikes(input_spikes),
        .weight_write(weight_write), .weight_source_addr(weight_source_addr),
        .weight_destination_addr(weight_destination_addr), .weight_data(weight_data),
        .threshold(16'd65535), .reset_value(16'd0), .leak_enable(1'b0),
        .leak_shift(5'd0), .refractory_period(16'd0),
        .state_read_addr(state_read_addr), .state_read_membrane(state_read_membrane),
        .state_read_refractory(state_read_refractory), .spike_vector(spike_vector),
        .busy(busy), .done(done)
    );

    lif_class_readout #(.NUM_CLASSES(10), .ADDR_WIDTH(8), .OUTPUT_BASE(246)) class_readout (
        .clk(clk), .rst(rst), .start(readout_start), .state_read_addr(readout_addr),
        .state_read_membrane(state_read_membrane), .predicted_class(rtl_prediction),
        .winning_score(winning_score), .busy(readout_busy), .done(readout_done)
    );

    initial begin
        rst = 1;
        step_start = 0;
        input_spikes = 0;
        weight_write = 0;
        weight_source_addr = 0;
        weight_destination_addr = 0;
        weight_data = 0;
        debug_addr = 0;
        readout_start = 0;
        failed = 0;
        correct = 0;
        checked = 0;
`ifdef IVERILOG
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("D:/RTL_PROJECT/build/mnist256/lif_mnist.vcd");
            $dumpvars(1, lif_mnist_tb);
            $dumpvars(1, dut);
            $dumpvars(1, class_readout);
        end
`endif
        check_file = $fopen({DATA_DIR, "/synapse_weights.hex"}, "r");
        if (!check_file) begin
            $display("FAIL: missing trained weight file; run tools.run_mnist_rtl_check first");
            $finish;
        end
        $fclose(check_file);
        check_file = $fopen({DATA_DIR, "/mnist_vectors.hex"}, "r");
        if (!check_file) begin
            $display("FAIL: missing MNIST vectors");
            $finish;
        end
        $fclose(check_file);
        $readmemh({DATA_DIR, "/synapse_weights.hex"}, weight_memory);
        $readmemh({DATA_DIR, "/mnist_vectors.hex"}, vector_memory);
        result_file = $fopen({DATA_DIR, "/rtl_predictions.csv"}, "w");
        if (!result_file) begin
            $display("FAIL: could not open RTL prediction report");
            $finish;
        end
        $fwrite(result_file, "sample,test_index,true_digit,python_prediction,rtl_prediction");
        for (neuron = 0; neuron < 10; neuron = neuron + 1)
            $fwrite(result_file, ",score_%0d", neuron);
        $fwrite(result_file, "\n");

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;
        // Program actual DUT memory through the same write port as the ring.
        for (weight_index = 0; weight_index < 65536; weight_index = weight_index + 1) begin
            if (^weight_memory[weight_index] === 1'bx) begin
                $display("FAIL: missing/unknown weight %0d", weight_index);
                $finish;
            end
            weight_write = 1;
            weight_source_addr = weight_index / 256;
            weight_destination_addr = weight_index % 256;
            weight_data = weight_memory[weight_index];
            @(negedge clk);
        end
        weight_write = 0;

        for (vector_index = 0; vector_index < NUM_SAMPLES*TICKS; vector_index = vector_index + 1) begin
            if (^vector_memory[vector_index] === 1'bx) begin
                $display("FAIL: missing/unknown vector %0d", vector_index);
                $finish;
            end
            for (field_index = 0; field_index < VECTOR_FIELDS; field_index = field_index + 1)
                fields[field_index] = vector_memory[vector_index] >> (32*field_index);
            sample_number = fields[0];
            image_test_index = fields[1];
            true_digit = fields[2];
            python_prediction = fields[532];
            if (sample_number != vector_index / TICKS + 1 || fields[3] != vector_index % TICKS + 1) begin
                $display("FAIL: invalid sample/tick metadata at vector %0d", vector_index);
                $finish;
            end
            // Clear membrane/feedback between images; weights survive reset.
            if (vector_index % TICKS == 0) begin
                rst = 1;
                repeat (2) @(negedge clk);
                rst = 0;
            end
            input_spikes = 0;
            for (source_index = 0; source_index < NUM_SOURCES; source_index = source_index + 1)
                input_spikes[source_index] = (fields[4+source_index/32] >> (source_index%32)) & 1;
            updates_in_step = 0;
            step_start = 1;
            @(negedge clk);
            step_start = 0;
            wait_cycles = 0;
            while (!done && wait_cycles < 197632) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
            end
            if (!done) begin
                $display("FAIL: core timeout sample=%0d tick=%0d", sample_number, fields[3]);
                $finish;
            end
            if (updates_in_step != 256) begin
                $display("FAIL: expected 256 state updates, got %0d", updates_in_step);
                failed = 1;
            end
            for (source_index = 0; source_index < 256; source_index = source_index + 1)
                expected_spikes[source_index] = (fields[12+source_index/32] >> (source_index%32)) & 1;
            if (spike_vector !== expected_spikes) begin
                $display("FAIL: spike mismatch sample=%0d tick=%0d got=%h expected=%h", sample_number, fields[3], spike_vector, expected_spikes);
                failed = 1;
            end
            for (neuron = 0; neuron < 256; neuron = neuron + 1) begin
                debug_addr = neuron;
                #1;
                if (neuron >= 246) actual_scores[neuron-246] = state_read_membrane;
                if (state_read_membrane !== fields[MEMBRANE_FIELD+neuron][15:0] ||
                    state_read_refractory !== fields[REFRACTORY_FIELD+neuron][15:0]) begin
                    $display("FAIL: state sample=%0d tick=%0d digit=%0d membrane=%0d/%0d refractory=%0d/%0d",
                        sample_number, fields[3], neuron, state_read_membrane, fields[MEMBRANE_FIELD+neuron],
                        state_read_refractory, fields[REFRACTORY_FIELD+neuron]);
                    failed = 1;
                end
            end
            checked = checked + 1;
            @(negedge clk);
            if (vector_index % TICKS == TICKS-1) begin
                // The winner is calculated by synthesizable RTL, not by the
                // testbench and not copied from the Python expected value.
                readout_start = 1;
                @(negedge clk);
                readout_start = 0;
                wait_cycles = 0;
                while (!readout_done && wait_cycles < 16) begin
                    @(posedge clk);
                    #1;
                    wait_cycles = wait_cycles + 1;
                end
                if (!readout_done || rtl_prediction !== python_prediction[7:0]) begin
                    $display("FAIL: class sample=%0d RTL=%0d Python=%0d done=%0d", sample_number, rtl_prediction, python_prediction, readout_done);
                    failed = 1;
                end
                if (rtl_prediction == true_digit) correct = correct + 1;
                $display("IMAGE %0d test_index=%0d true=%0d Python=%0d RTL=%0d", sample_number, image_test_index, true_digit, python_prediction, rtl_prediction);
                $write("RTL membrane scores:");
                $fwrite(result_file, "%0d,%0d,%0d,%0d,%0d", sample_number, image_test_index, true_digit, python_prediction, rtl_prediction);
                for (neuron = 0; neuron < 10; neuron = neuron + 1) begin
                    $write(" %0d", actual_scores[neuron]);
                    $fwrite(result_file, ",%0d", actual_scores[neuron]);
                end
                $write("\n");
                $fwrite(result_file, "\n");
                @(negedge clk);
            end
        end
        $fclose(result_file);
        if (failed) $display("FAIL: MNIST RTL/Python comparison");
        else $display("PASS: MNIST %0d images, %0d ticks, all 256 states and RTL predictions match Python; correct=%0d/%0d", NUM_SAMPLES, checked, correct, NUM_SAMPLES);
        $finish;
    end
endmodule
