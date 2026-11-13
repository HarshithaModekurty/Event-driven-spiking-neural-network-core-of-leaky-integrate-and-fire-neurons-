// Zybo Z7-10 PL-only demonstration. The on-board ARM processor is not used.
module zybo_z710_top #(
    parameter BOOT_FILE="build/rv32_mnist/firmware.hex",
    parameter SAMPLES=20,
    parameter ENABLE_ILA=0,
    parameter UART_CLKS_PER_BIT=868,
    parameter DEBOUNCE_CYCLES=1000000
) (
    input wire sysclk,
    input wire [1:0] btn,
    output wire [3:0] led,
    output wire led6_r,led6_g,led6_b,
    output wire eth_rst_b,
    output wire pmod_uart_tx
);
    wire clk,locked,reset_button,next_pulse;
    (* ASYNC_REG="TRUE" *) reg lock_meta=0,lock_sync=0;
    reg [4:0] reset_count=0;
    (* MAX_FANOUT=128 *) reg resetn=0;
    assign eth_rst_b=1'b1; // The PHY supplies K17's 125 MHz reference clock.
    zybo_z710_clock clocking (.sysclk(sysclk),.clk100(clk),.locked(locked));
    always @(posedge clk) begin
        lock_meta<=locked; lock_sync<=lock_meta;
        if(!lock_sync || reset_button) begin reset_count<=0; resetn<=0; end
        else begin
            if(!(&reset_count)) reset_count<=reset_count+1'b1;
            resetn<=&reset_count;
        end
    end
    demo_buttons #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) buttons (
        .clk(clk),.resetn(resetn),.buttons(btn),.reset_button(reset_button),.next_pulse(next_pulse));
    wire run,cpu_trap,bus_fault,busy,tick_done,frame_done;
    wire [31:0] software_result,write_addr,write_data,read_addr,read_data;
    wire write_valid,read_valid,input_valid,output_valid;
    wire [7:0] state_address;
    wire [8:0] input_packet,output_packet;
    (* mark_debug="true" *) wire snapshot_pulse,snapshot_valid;
    (* mark_debug="true" *) wire [7:0] sample_index;
    (* mark_debug="true" *) wire [3:0] predicted_digit;
    (* mark_debug="true" *) wire [159:0] scores;
    (* mark_debug="true" *) wire error,waiting,transmitting,complete;
    wire [13:0] capture_count;
    lif_rv32_soc #(.BOOT_FILE(BOOT_FILE),.ENABLE_DEMO(1)) soc (
        .clk(clk),.resetn(resetn),.cpu_trap(cpu_trap),.bus_fault(bus_fault),
        .software_result(software_result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done),
        .demo_run(run),.trace_write_valid(write_valid),.trace_write_addr(write_addr),.trace_write_data(write_data),
        .trace_read_valid(read_valid),.trace_read_addr(read_addr),.trace_read_data(read_data),
        .trace_state_address(state_address),.input_event_valid(input_valid),.input_event_packet(input_packet),
        .output_event_valid(output_valid),.output_event_packet(output_packet));
    snn_demo_reporter #(.SAMPLES(SAMPLES),.UART_CLKS_PER_BIT(UART_CLKS_PER_BIT)) reporter (
        .clk(clk),.resetn(resetn),.next_pulse(next_pulse),
        .trace_write_valid(write_valid),.trace_write_addr(write_addr),.trace_write_data(write_data),
        .trace_read_valid(read_valid),.trace_read_addr(read_addr),.trace_read_data(read_data),
        .trace_state_address(state_address),.input_event_valid(input_valid),.input_event_packet(input_packet),
        .output_event_valid(output_valid),.output_event_packet(output_packet),
        .cpu_trap(cpu_trap),.bus_fault(bus_fault),.software_result(software_result),
        .demo_run(run),.uart_tx(pmod_uart_tx),.snapshot_pulse(snapshot_pulse),.snapshot_valid(snapshot_valid),
        .sample_index(sample_index),.predicted_digit(predicted_digit),.scores(scores),.error(error),
        .waiting(waiting),.transmitting(transmitting),.complete(complete),.capture_count(capture_count));
    assign led=snapshot_valid ? predicted_digit : 4'd0;
    assign led6_r=error;
    assign led6_g=!error && (complete || (waiting && snapshot_valid));
    assign led6_b=!error && !complete && !(waiting && snapshot_valid);
    // The build creates this vendor IP only for ENABLE_ILA=1. Simulation
    // leaves it disabled; all probes have the same one-clock input pipeline.
    generate if(ENABLE_ILA) begin: instrumentation
        snn_demo_ila demo_ila (.clk(clk),.probe0(snapshot_pulse),.probe1(snapshot_valid),
            .probe2(sample_index),.probe3(predicted_digit),.probe4(scores),.probe5(error),
            .probe6(waiting),.probe7(transmitting),.probe8(complete));
    end endgenerate
endmodule
