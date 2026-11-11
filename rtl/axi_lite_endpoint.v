// One outstanding transaction in each direction. AW and W are independent.
// Backend enables remain asserted until their ready; side effects occur once
// at enable && ready. B/R payloads stay registered through backpressure.
module axi_lite_endpoint (
    input wire clk, input wire resetn,
    input wire [31:0] s_awaddr, input wire s_awvalid, output wire s_awready,
    input wire [31:0] s_wdata, input wire [3:0] s_wstrb,
    input wire s_wvalid, output wire s_wready,
    output reg [1:0] s_bresp, output reg s_bvalid, input wire s_bready,
    input wire [31:0] s_araddr, input wire s_arvalid, output wire s_arready,
    output reg [31:0] s_rdata, output reg [1:0] s_rresp,
    output reg s_rvalid, input wire s_rready,
    output wire wr_enable, output reg [31:0] wr_addr, output reg [31:0] wr_data,
    output reg [3:0] wr_strb, input wire wr_ready, input wire [1:0] wr_resp,
    output wire rd_enable, output reg [31:0] rd_addr,
    input wire rd_ready, input wire [31:0] rd_data, input wire [1:0] rd_resp
);
    reg aw_pending, w_pending, ar_pending;
    assign s_awready = resetn && !aw_pending && !s_bvalid;
    assign s_wready = resetn && !w_pending && !s_bvalid;
    assign s_arready = resetn && !ar_pending && !s_rvalid;
    assign wr_enable = resetn && aw_pending && w_pending && !s_bvalid;
    assign rd_enable = resetn && ar_pending && !s_rvalid;
    always @(posedge clk) begin
        if (!resetn) begin
            aw_pending<=0; w_pending<=0; ar_pending<=0;
            s_bvalid<=0; s_bresp<=0; s_rvalid<=0; s_rresp<=0; s_rdata<=0;
            wr_addr<=0; wr_data<=0; wr_strb<=0; rd_addr<=0;
        end else begin
            if (s_awvalid && s_awready) begin aw_pending<=1; wr_addr<=s_awaddr; end
            if (s_wvalid && s_wready) begin w_pending<=1; wr_data<=s_wdata; wr_strb<=s_wstrb; end
            if (s_arvalid && s_arready) begin ar_pending<=1; rd_addr<=s_araddr; end
            if (s_bvalid && s_bready) s_bvalid<=0;
            if (s_rvalid && s_rready) s_rvalid<=0;
            if (wr_enable && wr_ready) begin
                aw_pending<=0; w_pending<=0; s_bvalid<=1; s_bresp<=wr_resp;
            end
            if (rd_enable && rd_ready) begin
                ar_pending<=0; s_rvalid<=1; s_rresp<=rd_resp; s_rdata<=rd_data;
            end
        end
    end
endmodule
