// Single-clock queue. A transfer occurs on each edge with valid && ready.
module aer_event_fifo #(
    parameter WIDTH = 9,
    parameter DEPTH = 16,
    parameter PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter COUNT_WIDTH = $clog2(DEPTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire push_valid,
    output wire push_ready,
    input wire [WIDTH-1:0] push_data,
    output wire pop_valid,
    input wire pop_ready,
    output wire [WIDTH-1:0] pop_data,
    output reg [COUNT_WIDTH-1:0] level
);
    (* ram_style = "distributed" *) reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] read_pointer, write_pointer;
    wire take = pop_valid && pop_ready;
    wire put = push_valid && push_ready;
    assign pop_valid = !rst && (level != 0);
    // Reuse the departing slot when a full queue is read and written together.
    assign push_ready = !rst && ((level < DEPTH) || take);
    assign pop_data = pop_valid ? memory[read_pointer] : {WIDTH{1'b0}};
    always @(posedge clk) begin
        if (rst) begin
            level <= 0;
            read_pointer <= 0;
            write_pointer <= 0;
        end else begin
            if (put) begin
                memory[write_pointer] <= push_data;
                write_pointer <= (write_pointer == DEPTH-1) ? 0 : write_pointer + 1'b1;
            end
            if (take)
                read_pointer <= (read_pointer == DEPTH-1) ? 0 : read_pointer + 1'b1;
            case ({put, take})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase
        end
    end
endmodule
