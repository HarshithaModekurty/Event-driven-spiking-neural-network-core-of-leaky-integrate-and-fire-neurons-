// Select the largest output membrane. Equal scores choose the lowest class.
module lif_class_readout #(
    parameter NUM_CLASSES = 10,
    parameter ADDR_WIDTH = 4,
    parameter OUTPUT_BASE = 0
) (
    input wire clk,
    input wire rst,
    input wire start,
    output wire [ADDR_WIDTH-1:0] state_read_addr,
    input wire [15:0] state_read_membrane,
    output reg [ADDR_WIDTH-1:0] predicted_class,
    output reg [15:0] winning_score,
    output reg busy,
    output reg done
);
    reg [ADDR_WIDTH-1:0] class_index;
    assign state_read_addr = OUTPUT_BASE + class_index;

    always @(posedge clk) begin
        if (rst) begin
            class_index <= 0;
            predicted_class <= 0;
            winning_score <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            done <= 0;
            if (!busy && start) begin
                class_index <= 0;
                predicted_class <= 0;
                winning_score <= 0;
                busy <= 1;
            end else if (busy) begin
                if (state_read_membrane > winning_score) begin
                    predicted_class <= class_index;
                    winning_score <= state_read_membrane;
                end
                if (class_index == NUM_CLASSES - 1) begin
                    busy <= 0;
                    done <= 1;
                end else begin
                    class_index <= class_index + 1'b1;
                end
            end
        end
    end
endmodule
