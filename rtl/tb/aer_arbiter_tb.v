`timescale 1ns/1ps
module aer_arbiter_tb;
    reg clk = 0, rst = 1, ack = 0;
    reg [3:0] requests = 0;
    reg [35:0] addresses = 0;
    wire req;
    wire [8:0] data;
    wire [3:0] held_grant;
    wire [1:0] held_port;
    reg [1:0] start;
    reg [3:0] mask;
    wire [3:0] selected;
    integer file, fields, line = 0, i, j, k, expected;
    integer r, a, request_bits, a0, a1, a2, a3, ev, ep, ed;
    reg [4095:0] path;
    always #5 clk = ~clk;
    aer_rr_select selector (.requests(mask), .next_port(start), .grant(selected));
    aer_rr_arbiter dut (.clk(clk), .rst(rst), .requests(requests), .addresses(addresses),
        .out_req(req), .out_ack(ack), .out_data(data), .held_grant(held_grant), .held_port(held_port));
    initial begin
        // Independent cyclic priority loop: all 64 combinational cases.
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                start = i; mask = j; expected = 0;
                for (k = 3; k >= 0; k = k - 1)
                    if (j & (1 << ((i+k)%4))) expected = 1 << ((i+k)%4);
                #1;
                if (selected !== expected[3:0]) $fatal(1, "BDD mismatch start=%0d mask=%0h", i, j);
            end
        end
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "Missing arbiter vectors");
        file = $fopen(path, "r");
        if (!file) $fatal(1, "Cannot open arbiter vectors");
        fields = 10;
        while (fields == 10) begin
            fields = $fscanf(file, "%d %d %d %d %d %d %d %d %d %d\n", r, request_bits, a,
                a0, a1, a2, a3, ev, ep, ed);
            if (fields == 10) begin
                @(negedge clk); rst = r; requests = request_bits; ack = a;
                addresses = {a3[8:0], a2[8:0], a1[8:0], a0[8:0]};
                @(posedge clk); #1;
                if (req !== ev[0] || (req && (held_port !== ep[1:0] || data !== ed[8:0] || held_grant !== (4'b1 << ep))))
                    $fatal(1, "Arbiter line %0d req/port/data=%0d/%0d/%0d expected=%0d/%0d/%0d", line, req, held_port, data, ev, ep, ed);
                line = line + 1;
            end
        end
        $fclose(file);
        $display("PASS: 64 BDD cases and %0d Python arbiter cycles", line);
        $finish;
    end
endmodule
