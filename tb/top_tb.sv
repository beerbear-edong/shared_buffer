`timescale 1ns / 1ps
// `include "top_define.v"
// `include "pkt_if.sv"
// `include "test.sv"
module top_tb();
    logic           clk                 ;
    logic           rst_n               ;
    logic           full                ;
    logic           afull               ;
    pkt_if          wr[4]()             ;

    logic           sch_mode            ;
    logic[7:0]      Weight[0:7]         ;

    // TX output (no crossbar, direct output)
    logic [63:0]    tx_data             ;
    logic           tx_data_en          ;
    logic [10:0]    tx_data_len         ;
    logic [3:0]     tx_dst_bus          ;

    // Output pkt_if driven from TX bus (for Monitor)
    pkt_if          rd[4]()             ;

    logic           fin;

    rcv_top rcv_top_inst(
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .sch_mode   (sch_mode   ),
        .Weight     (Weight     ),
        .wr         (wr         ),
        .full       (full       ),
        .afull      (afull      ),
        .tx_data    (tx_data    ),
        .tx_data_en (tx_data_en ),
        .tx_data_len(tx_data_len),
        .tx_dst_bus (tx_dst_bus )
    );

    initial begin
        integer i;
        fin      <= 1'b0;
        clk      <= 1'b0;
        rst_n    <= 1'b0;
        sch_mode <= 1'b0;
        for (i = 0; i < 8; i++) begin
            Weight[i] <= 8'd1;
        end
        repeat(200) @(posedge clk);
        rst_n <= 1'b1;
    end
    always #1.6 clk <= ~clk;
    
    test t();

    // Drive output pkt_if from TX bus
    reg [3:0] tx_dst_bus_d;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            tx_dst_bus_d <= 4'b0;
        else
            tx_dst_bus_d <= tx_dst_bus;
    end

    generate
        genvar j;
        for(j = 0; j < 4; j++) begin: tx_to_pktif
            assign rd[j].vld  = tx_data_en & tx_dst_bus[j];
            assign rd[j].data = tx_data;
            assign rd[j].sop  = tx_data_en & tx_dst_bus[j] & ~tx_dst_bus_d[j];
            assign rd[j].eop  = ~tx_dst_bus[j] & tx_dst_bus_d[j];
        end
    endgenerate

    generate
        genvar i;
        for(i = 0; i < 8; i++) begin: monitor
            if(i < 4) begin
                Monitor#(.id(i)) Monitor_inst(
                  .clk(clk),
                  .rst_n(rst_n),
                  .rd(wr[i]),
                  .fin(fin)
                );
            end
            else begin
                Monitor#(.id(i)) Monitor_inst(
                  .clk(clk),
                  .rst_n(rst_n),
                  .rd(rd[i-4]),
                  .fin(fin)
                );
            end
        end
    endgenerate

endmodule
