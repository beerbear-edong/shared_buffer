module rx_data_fifo(
    input  wire          clk            ,
    input  wire          rst_n          ,
    pkt_if.pkt_in        wr             ,
    output wire [65:0]   rx_data_o      ,
    input  wire          rx_rd_en       ,
    output wire          full           ,
    output wire          empty
);

reg         sop_ff1, sop_ff2;
reg  [63:0] wr_data_sample  ;
reg         rx_wr_en        ;
wire [65:0] rx_data_i       ;
reg  [4:0]  pkt_cnt         ;
wire        wr_eop_flag     ;
wire        rd_eop_flag     ;
always @(posedge clk or negedge rst_n) begin//时序对齐
    if(~rst_n) begin
        sop_ff1         <= 1'b0;
        sop_ff2         <= 1'b0;
        wr_data_sample  <= 64'b0;
        rx_wr_en        <= 1'b0;
    end
    else begin
        sop_ff1         <= wr.sop;
        sop_ff2         <= sop_ff1;
        wr_data_sample  <= wr.data;
        rx_wr_en        <= wr.vld;
    end
end

assign rx_data_i = {sop_ff2, wr.eop, wr_data_sample};
assign wr_eop_flag = rx_wr_en     & rx_data_i[64];
assign rd_eop_flag = rx_rd_en     & rx_data_o[64];
pkt_fifo_w66_d1024 pkt_fifo_inst (
  .clk   (clk)                                   ,    // input wire clk
  .rst   (~rst_n)                                ,    // input wire rst
  .din   (rx_data_i)                             ,    // input wire [65 : 0] din
  .wr_en (rx_wr_en)                              ,    // input wire wr_en
  .rd_en (rx_rd_en)                              ,    // input wire rd_en
  .dout  (rx_data_o)                             ,    // output wire [65 : 0] dout
  .full  (full)                                  ,    // output wire full
  .empty (empty)                                 // output wire empty
);

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        pkt_cnt <= 5'b0;
    else if(wr_eop_flag & !rd_eop_flag)
        pkt_cnt <= pkt_cnt + 5'b1;
    else if(!wr_eop_flag & rd_eop_flag)
        pkt_cnt <= pkt_cnt - 5'b1;
    else
        pkt_cnt <= pkt_cnt;
end

//assign empty = pkt_cnt == 5'b0 ? 1'b1 : 1'b0;

endmodule