`include "Stimulator.sv"
`include "Monitor.sv"
program automatic test();
    virtual pkt_if wr[16];
    Stimulator sti[16];
    initial begin
        integer i;
        wr[0] = top_tb.wr[0];
        wr[1] = top_tb.wr[1];
        wr[2] = top_tb.wr[2];
        wr[3] = top_tb.wr[3];
        wr[4] = top_tb.wr[4];
        wr[5] = top_tb.wr[5];
        wr[6] = top_tb.wr[6];
        wr[7] = top_tb.wr[7];
        wr[8] = top_tb.wr[8];
        wr[9] = top_tb.wr[9];
        wr[10] = top_tb.wr[10];
        wr[11] = top_tb.wr[11];
        wr[12] = top_tb.wr[12];
        wr[13] = top_tb.wr[13];
        wr[14] = top_tb.wr[14];
        wr[15] = top_tb.wr[15];
        for(i = 0; i < 16; i++) begin
        //    wr[i] = top_tb.wr[i];
            sti[i] = new($sformatf("sti%d", i) , i, wr[i]);
        end
        repeat(500) @(posedge top_tb.clk);
        for(int i = 0; i < 16; i+=1) top_tb.ready[i] <= 1'b0;
        repeat(50) @(posedge top_tb.clk);
        while (top_tb.almost_full[0] == 1'b0) begin
          repeat(10) @(posedge top_tb.clk);
          sti[1].gen_pkt();
          sti[1].send_pkt();
        end
        repeat(100) @(posedge top_tb.clk);
        for(int i = 0; i < 16; i+=1) top_tb.ready[i] <= 1'b1;
        repeat(150) @(posedge top_tb.clk);
        for(int i = 0; i < 16; i+=1) top_tb.ready[i] <= 1'b0;
        repeat(100) @(posedge top_tb.clk);
        while (top_tb.almost_full[0] == 1'b0) begin
          repeat(10) @(posedge top_tb.clk);
          sti[1].gen_pkt();
          sti[1].send_pkt();
        end
//        for(i = 15; i >= 0; i--) begin
//            automatic integer j = i;
//            fork
//                begin
//                sti[j].gen_pkt();
//                sti[j].send_pkt();
//                end
//            join_none
//        end
           repeat(1000) @(posedge top_tb.clk);
        end

endprogram
