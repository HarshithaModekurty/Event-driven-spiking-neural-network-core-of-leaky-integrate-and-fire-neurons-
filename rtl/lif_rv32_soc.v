// PicoRV32 AXI4-Lite master, 64 KiB synchronous BRAM and full 256-state SNN.
// Boot image contains firmware, learned weights and input intensities.
module lif_rv32_soc #(
    parameter BOOT_FILE="build/rv32_network/firmware.hex"
) (
    input wire clk, input wire resetn,
    output wire cpu_trap, output reg bus_fault,
    output wire [31:0] software_result,
    output wire busy, tick_done, frame_done
);
    wire [31:0] awaddr,wdata,araddr,rdata;
    wire [3:0] wstrb;
    wire awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
    wire [1:0] bresp,rresp;
    wire we,re;
    wire [31:0] wa,wd,ra,rd;
    wire [3:0] ws;
    wire [1:0] wr,rr;
    wire ready;
    wire [31:0] csr_rd;
    wire [1:0] csr_wr,csr_rr;
    wire ram_write=(wa[31:16]==0), ram_read=(ra[31:16]==0);
    reg [31:0] ram_data;
    reg ram_pending;
    (* ram_style="block" *) reg [31:0] memory [0:16383];
    initial if(BOOT_FILE!="") $readmemh(BOOT_FILE,memory);
    wire ram_read_good=ram_read && ra[1:0]==0;
    assign ready=ram_read_good ? ram_pending : 1'b1;
    assign rd=ram_read_good ? ram_data : (ram_read ? 32'd0 : csr_rd);
    assign rr=ram_read ? (ra[1:0]!=0 ? 2'b10 : 2'b00) : csr_rr;
    assign wr=ram_write ? (wa[1:0]!=0 ? 2'b10 : 2'b00) : csr_wr;
    integer lane;
    always @(posedge clk) begin
        if(!resetn) begin ram_pending<=0; ram_data<=0; bus_fault<=0; end
        else begin
            if(re && ram_read_good && !ram_pending) begin
                ram_data<=memory[ra[15:2]]; ram_pending<=1;
            end else if(re && ready) ram_pending<=0;
            if((bvalid && bready && bresp!=0) || (rvalid && rready && rresp!=0)) bus_fault<=1;
        end
        // Do not reset the RAM: preserve BRAM inference and loaded firmware.
        if(resetn && we && ram_write && wa[1:0]==0)
            for(lane=0;lane<4;lane=lane+1) if(ws[lane]) memory[wa[15:2]][lane*8+:8]<=wd[lane*8+:8];
    end
    picorv32_axi #(.ENABLE_COUNTERS(0),.ENABLE_COUNTERS64(0),.ENABLE_IRQ(0),
        .ENABLE_MUL(0),.ENABLE_DIV(0),.PROGADDR_RESET(0),.STACKADDR(32'h00010000)) cpu (
        .clk(clk),.resetn(resetn && !bus_fault),.trap(cpu_trap),
        .mem_axi_awvalid(awvalid),.mem_axi_awready(awready),.mem_axi_awaddr(awaddr),.mem_axi_awprot(),
        .mem_axi_wvalid(wvalid),.mem_axi_wready(wready),.mem_axi_wdata(wdata),.mem_axi_wstrb(wstrb),
        .mem_axi_bvalid(bvalid),.mem_axi_bready(bready),
        .mem_axi_arvalid(arvalid),.mem_axi_arready(arready),.mem_axi_araddr(araddr),.mem_axi_arprot(),
        .mem_axi_rvalid(rvalid),.mem_axi_rready(rready),.mem_axi_rdata(rdata),
        .pcpi_wr(1'b0),.pcpi_rd(32'd0),.pcpi_wait(1'b0),.pcpi_ready(1'b0),
        .irq(32'd0),.pcpi_valid(),.pcpi_insn(),.pcpi_rs1(),.pcpi_rs2(),.eoi(),.trace_valid(),.trace_data()
    );
    axi_lite_endpoint endpoint (
        .clk(clk),.resetn(resetn),.s_awaddr(awaddr),.s_awvalid(awvalid),.s_awready(awready),
        .s_wdata(wdata),.s_wstrb(wstrb),.s_wvalid(wvalid),.s_wready(wready),
        .s_bresp(bresp),.s_bvalid(bvalid),.s_bready(bready),
        .s_araddr(araddr),.s_arvalid(arvalid),.s_arready(arready),
        .s_rdata(rdata),.s_rresp(rresp),.s_rvalid(rvalid),.s_rready(rready),
        .wr_enable(we),.wr_addr(wa),.wr_data(wd),.wr_strb(ws),.wr_ready(1'b1),.wr_resp(wr),
        .rd_enable(re),.rd_addr(ra),.rd_ready(ready),.rd_data(rd),.rd_resp(rr)
    );
    lif_host_registers registers (
        .clk(clk),.resetn(resetn),.wr_enable(we && !ram_write),.wr_addr(wa),.wr_data(wd),.wr_strb(ws),.wr_resp(csr_wr),
        .rd_enable(re && !ram_read),.rd_addr(ra),.rd_data(csr_rd),.rd_resp(csr_rr),
        .software_result(software_result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done)
    );
endmodule
