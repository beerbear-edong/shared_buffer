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

    assign          sch_mode = 1'b0;

    // TX output (no crossbar, direct output)
    logic [63:0]    tx_data             ;
    logic           tx_data_en          ;
    logic [10:0]    tx_data_len         ;
    logic [3:0]     tx_dst_bus          ;

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
        fin <= 1'b0;
        clk <= 1'b0;
        rst_n <= 1'b0;
        repeat(200) @(posedge clk);
        rst_n <= 1'b1;
    end
    always #1.6 clk <= ~clk;
    
    test t();

    // Monitor input ports (4 ports, no crossbar output)
    generate
        genvar i;
        for(i = 0; i < 4; i++) begin: monitor
            Monitor#(.id(i)) Monitor_inst(
              .clk(clk),
              .rst_n(rst_n),
              .rd(wr[i]),
              .fin(fin)
            );
        end
    endgenerate

    // Log TX output (replacing crossbar output monitors)
    always @(posedge clk) begin
        if(tx_data_en)
            $display("[TX_OUT] %t dst_bus=%b len=%0d data=%016h", $time, tx_dst_bus, tx_data_len, tx_data);
    end

endmodule
