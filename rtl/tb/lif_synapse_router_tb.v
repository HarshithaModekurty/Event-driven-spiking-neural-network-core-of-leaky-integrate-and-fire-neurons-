`timescale 1ns / 1ps

module lif_synapse_router_tb;

    parameter NUM_NEURONS = 4;
    parameter ADDR_WIDTH = 2;
    parameter NUM_TRANSACTIONS = 32;
    parameter SPIKE_WORDS = (NUM_NEURONS + 31) / 32;
    parameter VECTOR_FIELDS = NUM_NEURONS + SPIKE_WORDS;

    reg clk;
    reg rst;
    reg weight_write;
    reg [ADDR_WIDTH-1:0] weight_source_addr;
    reg [ADDR_WIDTH-1:0] weight_destination_addr;
    reg signed [3:0] weight_data;
    reg route_start;
    reg [NUM_NEURONS-1:0] source_spikes;
    wire current_valid;
    wire [ADDR_WIDTH-1:0] current_destination;
    wire signed [31:0] current_value;
    wire busy;
    wire done;

    reg [31:0] weight_memory [0:NUM_NEURONS*NUM_NEURONS-1];
    reg [32*VECTOR_FIELDS-1:0] vector_memory [0:NUM_TRANSACTIONS-1];
    integer vector_values [0:VECTOR_FIELDS-1];
    integer expected_current [0:NUM_NEURONS-1];
    integer weight_index;
    integer field_index;
    integer transaction;
    integer destination;
    integer spike_word;
    integer wait_cycles;
    integer failed;
    integer vectors_checked;

    always #5 clk = ~clk;

    lif_synapse_router #(
        .NUM_NEURONS(NUM_NEURONS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .weight_write(weight_write),
        .weight_source_addr(weight_source_addr),
        .weight_destination_addr(weight_destination_addr),
        .weight_data(weight_data),
        .route_start(route_start),
        .source_spikes(source_spikes),
        .current_valid(current_valid),
        .current_destination(current_destination),
        .current_value(current_value),
        .busy(busy),
        .done(done)
    );

    initial begin
        clk = 1'b0;
`ifdef IVERILOG
        $dumpfile("build/lif_router/lif_synapse_router.vcd");
        $dumpvars(0, lif_synapse_router_tb);
`endif
        rst = 1'b1;
        weight_write = 1'b0;
        weight_source_addr = {ADDR_WIDTH{1'b0}};
        weight_destination_addr = {ADDR_WIDTH{1'b0}};
        weight_data = 4'sd0;
        route_start = 1'b0;
        source_spikes = {NUM_NEURONS{1'b0}};
        failed = 0;
        vectors_checked = 0;

        $display("INFO: loading Python synapse weights and route vectors from D:/RTL_PROJECT/build/lif_router");
        $readmemh("D:/RTL_PROJECT/build/lif_router/synapse_weights.hex", weight_memory);
        $readmemh("D:/RTL_PROJECT/build/lif_router/lif_router_vectors.hex", vector_memory);

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

            source_spikes = {NUM_NEURONS{1'b0}};
            for (destination = 0; destination < NUM_NEURONS; destination = destination + 1) begin
                source_spikes[destination] = (vector_values[destination/32] >> (destination%32)) & 1;
                expected_current[destination] = vector_values[SPIKE_WORDS + destination];
            end

            @(negedge clk);
            route_start = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            route_start = 1'b0;

            for (destination = 0; destination < NUM_NEURONS; destination = destination + 1) begin
                wait_cycles = 0;
                begin : wait_for_current
                    reg received;
                    received = 0;
                    while (!received && wait_cycles < 2*NUM_NEURONS+4) begin
                        @(posedge clk);
                        #1;
                        received = current_valid;
                        wait_cycles = wait_cycles + 1;
                    end
                end
                if (!current_valid || current_destination !== destination[ADDR_WIDTH-1:0] ||
                    current_value !== expected_current[destination]) begin
                    $display(
                        "FAIL: transaction %0d destination %0d valid=%0d addr=%0d current=%0d expected=%0d",
                        transaction + 1, destination, current_valid, current_destination,
                        current_value, expected_current[destination]
                    );
                    failed = 1;
                end
            end

            if (!done) begin
                $display("FAIL: router did not assert done on transaction %0d", transaction + 1);
                failed = 1;
            end
            vectors_checked = vectors_checked + 1;
            @(negedge clk);
        end

        if (failed) begin
            $display("FAIL: synapse routing comparison failed after %0d transactions", vectors_checked);
        end else begin
            $display("PASS: matched Python synapse routing for %0d transactions (%0d neurons)", vectors_checked, NUM_NEURONS);
        end
        $finish;
    end

endmodule
