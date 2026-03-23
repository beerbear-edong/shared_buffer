`timescale 1ns / 1ps
`include "top_define.v"
`include "pkt_if.sv"
`include "test.sv"
module top_tb();
    logic           clk                 ;
    logic           rst_n               ;
    logic           full        [0:3]   ;
    logic           almost_full [0:3]   ;
    logic           ready       [0:15]  ;
    pkt_if          wr[16]()            ;
    pkt_if          rd[16]()            ;

    logic           sch_mode            ;
    logic[7:0]      Weight[0:7]         ;

    assign          sch_mode = 1'b0; //

    logic           fin;
    SRAM_Controller SRAM_Controller_inst(
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .sch_mode   (sch_mode   ),
        .Weight     (Weight     ),
        .wr         (wr         ),
        .rd         (rd         ),
        .full       (full       ),
        .almost_full(almost_full),
        .ready      (ready      )
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

    generate
        genvar i;
        for(i = 0; i < 32; i++) begin: monitor
            if(i < 16) begin
                Monitor#(.id(i)) Moniter_inst(
                  .clk(clk),
                  .rst_n(rst_n),
                  .rd(wr[i]),
                  .fin(fin)
                );
            end
            else begin
                Monitor#(.id(i)) Moniter_inst(
                  .clk(clk),
                  .rst_n(rst_n),
                  .rd(rd[i-16]),
                  .fin(fin)
                );
            end
        end
    endgenerate





endmodule
