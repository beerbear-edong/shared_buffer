`include "Stimulator.sv"
// `include "Monitor.sv"  // Monitor is already in the Vivado sim fileset
program automatic test();
    virtual pkt_if wr[4];
    Stimulator sti[4];
    initial begin
        integer i;
        wr[0] = top_tb.wr[0];
        wr[1] = top_tb.wr[1];
        wr[2] = top_tb.wr[2];
        wr[3] = top_tb.wr[3];
        for(i = 0; i < 4; i++) begin
            sti[i] = new($sformatf("sti%d", i) , i, wr[i]);
        end
        repeat(500) @(posedge top_tb.clk);
        // Send packets from port 1 until buffer almost full
        repeat(50) @(posedge top_tb.clk);
        while (top_tb.afull == 1'b0) begin
          repeat(10) @(posedge top_tb.clk);
          sti[1].gen_pkt();
          sti[1].send_pkt();
        end
        // Wait for scheduler to drain some packets
        repeat(250) @(posedge top_tb.clk);
        // Send more packets until almost full again
        repeat(100) @(posedge top_tb.clk);
        while (top_tb.afull == 1'b0) begin
          repeat(10) @(posedge top_tb.clk);
          sti[1].gen_pkt();
          sti[1].send_pkt();
        end
        repeat(1000) @(posedge top_tb.clk);
    end

endprogram
