// Buttons are asynchronous. Only the first synchronizer stages are CDC endpoints.
module demo_buttons #(parameter DEBOUNCE_CYCLES=1000000) (
    input wire clk, input wire resetn, input wire [1:0] buttons,
    output wire reset_button, output reg next_pulse
);
    (* ASYNC_REG="TRUE" *) reg [1:0] button_meta=0,button_sync=0;
    localparam WIDTH=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
    reg [WIDTH-1:0] count;
    reg next_level;
    assign reset_button=button_sync[0];
    always @(posedge clk) begin button_meta<=buttons; button_sync<=button_meta; end
    always @(posedge clk) begin
        if(!resetn) begin count<=0; next_level<=0; next_pulse<=0; end
        else begin
            next_pulse<=0;
            if(button_sync[1]==next_level) count<=0;
            else if(count==DEBOUNCE_CYCLES-1) begin
                count<=0; next_level<=button_sync[1]; next_pulse<=button_sync[1];
            end else count<=count+1'b1;
        end
    end
endmodule
