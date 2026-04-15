`timescale 1ns / 1ps



module info_collector(
    input    wire        clk           ,
    input    wire        rst_n         ,
    input    wire        bus_data_sof  ,
    input    wire        bus_data_eof  ,
    input    wire[17:0]  bus_data_info ,
    input    wire        bus_data_en   ,
    output   reg[17:0]   pkt_info_o    ,
    output   reg         pkt_info_en   ,
    output   reg         pkt_info_ed
);

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        pkt_info_o   <= 18'b0;
        pkt_info_en  <= 1'b0;
        pkt_info_ed  <= 1'b0;
    end
    else if(bus_data_en & bus_data_sof) begin
        pkt_info_o   <= bus_data_info;
        pkt_info_en  <= 1'b1;
        pkt_info_ed  <= 1'b0;
    end
    else if(bus_data_en & bus_data_eof) begin
        pkt_info_o   <= 18'b0;
        pkt_info_en  <= 1'b0;
        pkt_info_ed  <= 1'b1;
    end
    else begin
        pkt_info_o   <= pkt_info_o;
        pkt_info_en  <= 1'b0;
        pkt_info_ed  <= 1'b0;
    end
end

endmodule