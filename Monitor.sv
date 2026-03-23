module Monitor#(
  parameter id = 0
)(
  input   wire    clk   ,
  input   wire    rst_n ,
  pkt_if.pkt_out  rd    ,
  input   wire    fin    
);
integer file;
bit [31:0] pkt_cnt;
initial begin
  if(id < 4)
    file = $fopen($sformatf("../tc/port_%0d_in.txt", id), "w");
  else
    file = $fopen($sformatf("../tc/port_%0d_out.txt", id-4), "w");

  wait(fin == 1'b1);
  $fclose(file);
end

always@(posedge clk or negedge rst_n) begin
  if(~rst_n)
    pkt_cnt <= 32'b0;
  else if(rd.vld)
    pkt_cnt <= pkt_cnt + 32'b1;
  else
    pkt_cnt <= pkt_cnt;
end

always@(posedge clk) begin
  if(rd.vld)
    $fdisplay(file, "%016h", rd.data);
  else if(rd.eop)
    $fdisplay(file, "");
end

endmodule
