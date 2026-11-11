// Standalone AXI4-Lite SNN peripheral; clocked active-low synchronous reset.
// AWPROT/ARPROT are accepted but unused (no protection domains).
module lif_axi_lite (
    input wire clk, input wire resetn,
    input wire [31:0] s_awaddr, input wire [2:0] s_awprot,
    input wire s_awvalid, output wire s_awready,
    input wire [31:0] s_wdata, input wire [3:0] s_wstrb,
    input wire s_wvalid, output wire s_wready,
    output wire [1:0] s_bresp, output wire s_bvalid, input wire s_bready,
    input wire [31:0] s_araddr, input wire [2:0] s_arprot,
    input wire s_arvalid, output wire s_arready,
    output wire [31:0] s_rdata, output wire [1:0] s_rresp,
    output wire s_rvalid, input wire s_rready,
    output wire [31:0] software_result,
    output wire busy, tick_done, frame_done
);
    wire we,re;
    wire [31:0] wa,wd,ra,rd;
    wire [3:0] ws;
    wire [1:0] wr,rr;
    axi_lite_endpoint endpoint (
        .clk(clk),.resetn(resetn),.s_awaddr(s_awaddr),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_araddr(s_araddr),.s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rdata(s_rdata),.s_rresp(s_rresp),.s_rvalid(s_rvalid),.s_rready(s_rready),
        .wr_enable(we),.wr_addr(wa),.wr_data(wd),.wr_strb(ws),.wr_ready(1'b1),.wr_resp(wr),
        .rd_enable(re),.rd_addr(ra),.rd_ready(1'b1),.rd_data(rd),.rd_resp(rr)
    );
    lif_host_registers registers (
        .clk(clk),.resetn(resetn),.wr_enable(we),.wr_addr(wa),.wr_data(wd),.wr_strb(ws),.wr_resp(wr),
        .rd_enable(re),.rd_addr(ra),.rd_data(rd),.rd_resp(rr),
        .software_result(software_result),.busy(busy),.tick_done(tick_done),.frame_done(frame_done)
    );
endmodule
