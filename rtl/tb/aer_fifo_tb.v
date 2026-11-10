`timescale 1ns/1ps
module aer_fifo_tb;
    parameter DEPTH = 3;
    reg clk = 0, rst = 1, push_valid = 0, pop_ready = 0;
    reg [8:0] push_data = 0;
    wire push_ready, pop_valid;
    wire [8:0] pop_data;
    wire [$clog2(DEPTH+1)-1:0] level;
    integer file, fields, line = 0;
    integer r, pv, data, pr, expected_ready, expected_valid, expected_data, expected_level;
    reg [4095:0] path;
    always #5 clk = ~clk;
    aer_event_fifo #(.DEPTH(DEPTH)) dut (
        .clk(clk), .rst(rst), .push_valid(push_valid), .push_ready(push_ready), .push_data(push_data),
        .pop_valid(pop_valid), .pop_ready(pop_ready), .pop_data(pop_data), .level(level)
    );
    initial begin
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "Missing FIFO vectors");
        file = $fopen(path, "r");
        if (!file) $fatal(1, "Cannot open FIFO vectors");
        @(posedge clk); #1;
        fields = 8;
        while (fields == 8) begin
            fields = $fscanf(file, "%d %d %d %d %d %d %d %d\n", r, pv, data, pr,
                expected_ready, expected_valid, expected_data, expected_level);
            if (fields == 8) begin
                @(negedge clk); rst = r; push_valid = pv; push_data = data; pop_ready = pr;
                #1;
                if (push_ready !== expected_ready[0] || pop_valid !== expected_valid[0] ||
                    (pop_valid && pop_data !== expected_data[8:0]) || level !== expected_level)
                    $fatal(1, "FIFO line %0d ready=%b valid=%b data=%0d level=%0d expected=%0d/%0d/%0d/%0d",
                        line, push_ready, pop_valid, pop_data, level, expected_ready, expected_valid, expected_data, expected_level);
                @(posedge clk); #1; line = line + 1;
            end
        end
        $fclose(file);
        $display("PASS: FIFO depth=%0d, %0d queue operations", DEPTH, line);
        $finish;
    end
endmodule
