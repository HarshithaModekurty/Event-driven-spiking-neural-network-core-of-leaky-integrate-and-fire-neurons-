`timescale 1ns / 1ps
module lif_population_pipeline_tb;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg current_write = 0;
    reg [1:0] current_addr = 0;
    reg signed [31:0] current_data = 0;
    wire [15:0] membrane;
    wire [15:0] refractory;
    wire [3:0] spikes;
    wire busy;
    wire done;
    integer failed = 0;
    integer commits = 0;
    integer cycles;
    always #5 clk = ~clk;
    always @(posedge clk) if (dut.update_commit) commits = commits + 1;
    lif_population_stepper #(.NUM_NEURONS(4), .ADDR_WIDTH(2)) dut (
        .clk(clk), .rst(rst), .start(start), .current_write(current_write),
        .current_addr(current_addr), .current_data(current_data),
        .threshold(16'd10), .reset_value(16'd0), .leak_enable(1'b0),
        .leak_shift(5'd0), .refractory_period(16'd2), .state_read_addr(2'd0),
        .state_read_membrane(membrane), .state_read_refractory(refractory),
        .spike_vector(spikes), .busy(busy), .done(done)
    );
    task load_current;
        input signed [31:0] value;
        begin
            @(negedge clk); current_write = 1; current_data = value;
            @(negedge clk); current_write = 0;
        end
    endtask
    task launch;
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        load_current(7);
        launch;
        @(posedge clk); #1; // Read phase must not modify stored state.
        if (membrane !== 0 || dut.selected_current !== 7 || commits != 0) failed = 1;
        @(posedge clk); #1; // Calculation is registered, without a state write.
        if (membrane !== 0 || dut.result_membrane !== 7 || commits != 0) failed = 1;
        @(posedge clk); #1; // Exactly one write follows the registered result.
        if (membrane !== 7 || commits != 1) failed = 1;
        cycles = 0;
        while (!done && cycles < 24) begin @(posedge clk); #1; cycles = cycles + 1; end
        if (!done || commits != 4 || spikes !== 0) failed = 1;
        // Abort a newly captured read. Reset must cancel its pending write.
        launch;
        @(posedge clk); #1;
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        if (busy !== 0 || done !== 0 || membrane !== 0 || spikes !== 0) failed = 1;
        @(negedge clk); rst = 0; commits = 0;
        load_current(12);
        launch;
        repeat (2) begin @(posedge clk); #1; end
        // Cancel after calculation, immediately before the write phase.
        if (dut.result_spike !== 1 || commits != 0) failed = 1;
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        if (busy !== 0 || membrane !== 0 || refractory !== 0 || spikes !== 0) failed = 1;
        @(negedge clk); rst = 0; commits = 0;
        load_current(12);
        launch;
        cycles = 0;
        while (!done && cycles < 24) begin @(posedge clk); #1; cycles = cycles + 1; end
        if (!done || commits != 4 || spikes !== 4'b0001 || membrane !== 0 || refractory !== 2) failed = 1;
        if (failed) $display("FAIL: registered population read / commit / reset");
        else $display("PASS: registered population read, one commit per state, and reset cancels pending write");
        $finish;
    end
endmodule
