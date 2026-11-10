`timescale 1ns / 1ps
// Directed regression: source IDs exceed state IDs; recurrence uses an offset.
module lif_source_mapping_tb;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg [5:0] inputs = 0;
    reg write_weight = 0;
    reg [2:0] source = 0;
    reg [1:0] destination = 0;
    reg signed [3:0] weight = 0;
    wire [2:0] spikes;
    wire done;
    integer index;
    integer tick;
    integer cycles;
    integer failed = 0;
    reg [2:0] expected;
    reg readout_start = 0;
    reg [15:0] scores [0:2];
    wire [1:0] read_addr;
    wire [1:0] prediction;
    wire [15:0] winning_score;
    wire readout_done;
    always #5 clk = ~clk;

    lif_snn_core #(.NUM_NEURONS(3), .ADDR_WIDTH(2), .NUM_SOURCES(6),
        .SOURCE_ADDR_WIDTH(3), .RECURRENT_SOURCE_BASE(3)) dut (
        .clk(clk), .rst(rst), .step_start(start), .input_spikes(inputs),
        .weight_write(write_weight), .weight_source_addr(source),
        .weight_destination_addr(destination), .weight_data(weight),
        .threshold(16'd5), .reset_value(16'd0), .leak_enable(1'b0),
        .leak_shift(5'd0), .refractory_period(16'd0), .state_read_addr(2'd0),
        .spike_vector(spikes), .done(done)
    );
    lif_class_readout #(.NUM_CLASSES(3), .ADDR_WIDTH(2)) readout (
        .clk(clk), .rst(rst), .start(readout_start), .state_read_addr(read_addr),
        .state_read_membrane(scores[read_addr]), .predicted_class(prediction),
        .winning_score(winning_score), .done(readout_done)
    );

    task check_readout;
        input [1:0] expected_class;
        input [15:0] expected_score;
        begin
            @(negedge clk); readout_start = 1;
            @(negedge clk); readout_start = 0;
            cycles = 0;
            while (!readout_done && cycles < 8) begin
                @(posedge clk); #1; cycles = cycles + 1;
            end
            if (!readout_done || prediction !== expected_class || winning_score !== expected_score) begin
                $display("FAIL: readout class=%0d/%0d score=%0d/%0d", prediction, expected_class, winning_score, expected_score);
                failed = 1;
            end
        end
    endtask

    initial begin
        scores[0] = 5; scores[1] = 17; scores[2] = 17;
        repeat (2) @(negedge clk);
        rst = 0;
        for (index = 0; index < 18; index = index + 1) begin
            write_weight = 1; source = index / 3; destination = index % 3;
            if (index == 0 || index == 10 || index == 14 || index == 15) weight = 7;
            else weight = 0;
            @(negedge clk);
        end
        write_weight = 0;
        for (tick = 0; tick < 4; tick = tick + 1) begin
            inputs = (tick == 0) ? 6'b000001 : 0;
            start = 1;
            @(negedge clk); start = 0;
            cycles = 0;
            while (!done && cycles < 128) begin
                @(posedge clk); #1; cycles = cycles + 1;
            end
            expected = 3'b001 << (tick % 3);
            if (!done || spikes !== expected) begin
                $display("FAIL: mapped recurrence tick=%0d got=%b expected=%b", tick, spikes, expected);
                failed = 1;
            end
            repeat (2) @(negedge clk);
        end
        check_readout(1, 17); // Tie must choose the lower class.
        scores[0] = 0; scores[1] = 0; scores[2] = 0;
        check_readout(0, 0);
        scores[2] = 65535;
        check_readout(2, 65535);
        if (failed) $display("FAIL: source mapping / readout regression");
        else $display("PASS: offset recurrent source mapping and class readout boundaries");
        $finish;
    end
endmodule
