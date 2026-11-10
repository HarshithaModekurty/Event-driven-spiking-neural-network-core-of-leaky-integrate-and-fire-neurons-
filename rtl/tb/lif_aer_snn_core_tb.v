`timescale 1ns/1ps
module lif_aer_snn_core_tb;
    parameter FRAMES = 8, PORT_WORDS = 100, OUTPUT_WORDS = 410;
    parameter THRESHOLD = 8, RESET_VALUE = 3, LEAK_ENABLE = 1, REFRACTORY_PERIOD = 2;
    parameter RESET_EVERY = 0, REQUIRE_FULL_OUTPUT = 1;
    reg clk = 0, rst = 1, drive = 0;
    reg [3:0] driver_req = 0, driver_end = 0, manual_req = 0, manual_end = 0;
    reg [31:0] driver_addr = 0, manual_addr = 0;
    wire [3:0] in_req = drive ? driver_req : manual_req;
    wire [3:0] in_end = drive ? driver_end : manual_end;
    wire [31:0] in_addr = drive ? driver_addr : manual_addr;
    wire [3:0] in_ack;
    wire out_req, out_end, weight_ready, busy, tick_done, frame_done;
    wire [7:0] out_addr;
    reg out_ack = 0, weight_write = 0;
    reg [7:0] weight_source_addr = 0, weight_destination_addr = 0, debug_addr = 0;
    reg signed [3:0] weight_data = 0;
    wire [15:0] membrane, refractory;
    wire [255:0] spikes;
    reg [3:0] weights [0:65535];
    reg [8:0] input_packets [0:4*PORT_WORDS-1];
    reg [31:0] input_counts [0:3];
    reg [8:0] output_packets [0:OUTPUT_WORDS-1];
    reg [8447:0] expected_states [0:FRAMES-1];
    reg [4095:0] data_dir;
    reg [15:0] random_bits = 16'hcafe;
    reg [3:0] accepted = 0;
    reg previous_stall = 0;
    reg [8:0] stalled_packet;
    integer input_index [0:3];
    integer input_frames [0:3];
    integer frame_limit = RESET_EVERY ? RESET_EVERY : FRAMES;
    integer i, p, frame, neuron, packet_index = 0, total_commits = 0, commits = 0;
    integer tick_count = 0, cycles = 0, first_output_stalls = 80;
    integer input_stalls = 0, output_stalls = 0, full_output_stalls = 0;
    reg [8:0] received;
    always #5 clk = ~clk;
    lif_aer_snn_core #(.INPUT_DEPTH(3), .OUTPUT_DEPTH(4)) dut (
        .clk(clk), .rst(rst), .in_req(in_req), .in_ack(in_ack), .in_addr(in_addr), .in_end(in_end),
        .out_req(out_req), .out_ack(out_ack), .out_addr(out_addr), .out_end(out_end),
        .weight_write(weight_write), .weight_ready(weight_ready),
        .weight_source_addr(weight_source_addr), .weight_destination_addr(weight_destination_addr),
        .weight_data(weight_data), .threshold(THRESHOLD[15:0]), .reset_value(RESET_VALUE[15:0]),
        .leak_enable(LEAK_ENABLE[0]), .leak_shift(5'd2), .refractory_period(REFRACTORY_PERIOD[15:0]),
        .state_read_addr(debug_addr), .state_read_membrane(membrane), .state_read_refractory(refractory),
        .spike_vector(spikes), .busy(busy), .tick_done(tick_done), .frame_done(frame_done)
    );
    always @(posedge clk) begin
        if (!rst && drive) begin
            cycles = cycles + 1;
            accepted = driver_req & in_ack;
            for (p = 0; p < 4; p = p + 1) begin
                if (accepted[p]) begin
                    input_index[p] = input_index[p] + 1;
                    if (driver_end[p]) input_frames[p] = input_frames[p] + 1;
                end
                if (driver_req[p] && !in_ack[p]) input_stalls = input_stalls + 1;
            end
            if (previous_stall && (!out_req || {out_end, out_addr} !== stalled_packet))
                $fatal(1, "FAIL: AER packet changed before acknowledgment");
            previous_stall = out_req && !out_ack;
            stalled_packet = {out_end, out_addr};
            if (previous_stall) output_stalls = output_stalls + 1;
            if (dut.output_put && !dut.output_ready) full_output_stalls = full_output_stalls + 1;
            if (dut.core_start) commits = 0;
            if (dut.core.population_stepper.update_commit) begin
                if (dut.core.population_stepper.neuron_index !== commits[7:0])
                    $fatal(1, "FAIL: neuron commit order");
                commits = commits + 1;
                total_commits = total_commits + 1;
            end
            if (tick_done) begin
                if (commits != 256) $fatal(1, "FAIL: expected 256 commits, got %0d", commits);
                tick_count = tick_count + 1;
            end
        end else begin
            accepted = 0;
            previous_stall = 0;
        end
    end
    always @(negedge clk) begin
        if (drive && !rst) begin
            random_bits = {random_bits[14:0], random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
            for (i = 0; i < 4; i = i + 1) begin
                if (!driver_req[i] || accepted[i]) begin
                    driver_req[i] = 0;
                    if (input_index[i] < input_counts[i] && input_frames[i] < frame_limit && random_bits[i]) begin
                        driver_req[i] = 1;
                        driver_end[i] = input_packets[i*PORT_WORDS+input_index[i]][8];
                        driver_addr[8*i +: 8] = input_packets[i*PORT_WORDS+input_index[i]][7:0];
                    end
                end
            end
            if (out_req && first_output_stalls > 0) begin
                out_ack = 0;
                first_output_stalls = first_output_stalls - 1;
            end else out_ack = (cycles % 211 >= 67) && (random_bits[8] || random_bits[12]);
        end
    end
    initial begin
        for (p = 0; p < 4; p = p + 1) begin input_index[p] = 0; input_frames[p] = 0; end
        if (!$value$plusargs("DATA_DIR=%s", data_dir)) data_dir = "D:/RTL_PROJECT/build/aer_network";
        $readmemh({data_dir, "/weights.hex"}, weights);
        $readmemh({data_dir, "/input_counts.hex"}, input_counts);
        $readmemh({data_dir, "/input_packets.hex"}, input_packets);
        $readmemh({data_dir, "/output_packets.hex"}, output_packets);
        $readmemh({data_dir, "/states.hex"}, expected_states);
        repeat (3) @(negedge clk); rst = 0; #1;
        for (neuron = 0; neuron < 65536; neuron = neuron + 1) begin
            if (!weight_ready || ^weights[neuron] === 1'bx) $fatal(1, "FAIL: weight programming");
            weight_write = 1;
            weight_source_addr = neuron / 256;
            weight_destination_addr = neuron % 256;
            weight_data = weights[neuron];
            @(negedge clk);
        end
        weight_write = 0;
        // Reset a partially collected frame. Programmed synapses must survive.
        manual_req = 1; manual_addr = 42; manual_end = 0;
        @(posedge clk); while (!in_ack[0]) @(posedge clk);
        @(negedge clk); manual_req = 0;
        repeat (8) @(negedge clk);
        manual_req = 1; manual_end = 1;
        @(posedge clk); while (!in_ack[0]) @(posedge clk);
        @(negedge clk); manual_req = 0;
        repeat (8) @(negedge clk);
        if (dut.closed_ports != 1 || dut.input_bitmap[42] !== 1'b1)
            $fatal(1, "FAIL: partial-frame reset precondition");
        rst = 1;
        repeat (3) @(negedge clk); rst = 0;
        #1;
        if (busy || out_req || dut.closed_ports || dut.input_bitmap)
            $fatal(1, "FAIL: reset did not cancel partial frame");
        @(negedge clk); drive = 1;
        for (frame = 0; frame < FRAMES; frame = frame + 1) begin
            received = 0;
            while (received != 256) begin
                @(posedge clk);
                if (out_req && out_ack) begin
                    received = {out_end, out_addr};
                    if (packet_index >= OUTPUT_WORDS || received !== output_packets[packet_index])
                        $fatal(1, "FAIL: output packet %0d got=%0d expected=%0d", packet_index, received, output_packets[packet_index]);
                    packet_index = packet_index + 1;
                end
            end
            #1;
            if (!frame_done || spikes !== expected_states[frame][255:0])
                $fatal(1, "FAIL: frame completion/spike bitmap frame=%0d", frame);
            for (neuron = 0; neuron < 256; neuron = neuron + 1) begin
                @(negedge clk); debug_addr = neuron; #1;
                if (membrane !== ((expected_states[frame] >> (256+16*neuron)) & 16'hffff) ||
                    refractory !== ((expected_states[frame] >> (4352+16*neuron)) & 16'hffff))
                    $fatal(1, "FAIL: state mismatch frame=%0d neuron=%0d membrane=%0d refractory=%0d", frame, neuron, membrane, refractory);
            end
            if (RESET_EVERY && ((frame+1) % RESET_EVERY == 0) && frame+1 < FRAMES) begin
                // No next-image tokens may enter before this reset boundary.
                if (busy || |driver_req) $fatal(1, "FAIL: image boundary not drained");
                @(negedge clk); rst = 1;
                repeat (3) @(negedge clk); rst = 0;
                frame_limit = frame_limit + RESET_EVERY;
            end
        end
        repeat (20) @(negedge clk);
        for (p = 0; p < 4; p = p + 1)
            if (input_index[p] != input_counts[p]) $fatal(1, "FAIL: missing input packets");
        if (packet_index != OUTPUT_WORDS || total_commits != FRAMES*256 || tick_count != FRAMES || busy || out_req)
            $fatal(1, "FAIL: final counts/state packets=%0d commits=%0d ticks=%0d busy=%b", packet_index, total_commits, tick_count, busy);
        if (!input_stalls || !output_stalls || (REQUIRE_FULL_OUTPUT && !full_output_stalls))
            $fatal(1, "FAIL: test did not exercise queue backpressure");
        $display("PASS: AER network %0d frames, %0d packets, %0d state updates; input stalls=%0d output stalls=%0d full-output stalls=%0d",
            FRAMES, packet_index, total_commits, input_stalls, output_stalls, full_output_stalls);
        $finish;
    end
    initial begin
        #(FRAMES*2000000 + 1000000);
        $fatal(1, "FAIL: AER network timeout");
    end
endmodule
