`timescale 1ns / 1ps

module lif_neuron_tb;

    reg clk;
    reg rst;
    reg enable;
    reg signed [31:0] input_current;
    reg [15:0] threshold;
    reg [15:0] reset_value;
    reg leak_enable;
    reg [4:0] leak_shift;
    reg [15:0] refractory_period;
    wire [15:0] membrane;
    wire spike;
    wire [15:0] refractory_remaining;

    integer vector_file;
    integer scan_result;
    integer line_number;
    integer expected_spike;
    integer expected_membrane;
    integer expected_refractory;
    integer vectors_checked;
    integer failed;
    integer vector_values[0:10];

    always #5 clk = ~clk;

    lif_neuron dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .input_current(input_current),
        .threshold(threshold),
        .reset_value(reset_value),
        .leak_enable(leak_enable),
        .leak_shift(leak_shift),
        .refractory_period(refractory_period),
        .membrane(membrane),
        .spike(spike),
        .refractory_remaining(refractory_remaining)
    );

    initial begin
        clk = 1'b0;
`ifdef IVERILOG
        $dumpfile("build/lif_rtl/lif_neuron.vcd");
        $dumpvars(0, lif_neuron_tb);
`endif
        line_number = 0;
        vectors_checked = 0;
        failed = 0;
        rst = 1'b0;
        enable = 1'b0;
        input_current = 32'sd0;
        threshold = 16'd0;
        reset_value = 16'd0;
        leak_enable = 1'b0;
        leak_shift = 5'd0;
        refractory_period = 16'd0;

        vector_file = $fopen("D:/RTL_PROJECT/build/lif_rtl/lif_vectors.txt", "r");
        if (vector_file == 0) begin
            $display("FAIL: could not open D:/RTL_PROJECT/build/lif_rtl/lif_vectors.txt");
            $finish;
        end
        $display("INFO: reading Python reference vectors from D:/RTL_PROJECT/build/lif_rtl/lif_vectors.txt");

        scan_result = 11;
        while (scan_result == 11) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d",
                vector_values[0], vector_values[1], vector_values[2],
                vector_values[3], vector_values[4], vector_values[5],
                vector_values[6], vector_values[7], vector_values[8],
                vector_values[9], vector_values[10]
            );
            if (scan_result == 11) begin
                line_number = line_number + 1;
                rst = vector_values[0];
                enable = vector_values[1];
                input_current = vector_values[2];
                threshold = vector_values[3];
                reset_value = vector_values[4];
                leak_enable = vector_values[5];
                leak_shift = vector_values[6];
                refractory_period = vector_values[7];
                expected_spike = vector_values[8];
                expected_membrane = vector_values[9];
                expected_refractory = vector_values[10];

                @(posedge clk);
                #1;
                if (spike !== expected_spike[0] ||
                    membrane !== expected_membrane[15:0] ||
                    refractory_remaining !== expected_refractory[15:0]) begin
                    $display(
                        "FAIL: vector %0d got spike=%0d membrane=%0d refractory=%0d; expected spike=%0d membrane=%0d refractory=%0d",
                        line_number, spike, membrane, refractory_remaining,
                        expected_spike, expected_membrane, expected_refractory
                    );
                    failed = 1;
                end
                vectors_checked = vectors_checked + 1;
                @(negedge clk);
            end
        end

        if (scan_result != -1 && !$feof(vector_file)) begin
            $display("FAIL: malformed vector line %0d (read %0d fields)", line_number + 1, scan_result);
            failed = 1;
        end
        $fclose(vector_file);
        if (failed) begin
            $display("FAIL: Python golden-model comparison failed after %0d cycles", vectors_checked);
        end else begin
            $display("PASS: matched Python golden model for %0d LIF cycles", vectors_checked);
        end
        $finish;
    end

endmodule