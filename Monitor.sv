`timescale 1ns / 1ps
module Monitor#(
  parameter id = 0
)(
  input   wire    clk   ,
  input   wire    rst_n ,
  pkt_if.pkt_in   rd    ,
  input   wire    fin    
);
  integer     file;
  string      file_name;
  bit [31:0]  pkt_cnt;
initial begin
    if(id < 4)
      file_name = $sformatf("../tc/port_%0d_in.txt", id);
    else
      file_name = $sformatf("../tc/port_%0d_out.txt", id-4);

    file = $fopen(file_name, "w");
    // 若相对路径不存在，回退到当前仿真目录，避免无效句柄告警
    if(file <= 0) begin
      if(id < 4)
        file_name = $sformatf("port_%0d_in.txt", id);
      else
        file_name = $sformatf("port_%0d_out.txt", id-4);
      file = $fopen(file_name, "w");
    end

  if(file <= 0)
    $display("[MON_WARN] %t open file failed(id=%0d, name=%s), disable file logging", $time, id, file_name);

  wait(fin == 1'b1);
  if(file > 0)
    $fclose(file);
end

// always@(posedge clk or negedge rst_n) begin
//   if(~rst_n)
//     pkt_cnt <= 32'b0;
//   else if(rd.vld)
//     pkt_cnt <= pkt_cnt + 32'b1;
//   else
//     pkt_cnt <= pkt_cnt;
// end

always@(posedge clk) begin
  if(file > 0 && rd.vld)
    $fdisplay(file, "%016h", rd.data);
  else if(file > 0 && rd.eop)
    $fdisplay(file, "");
end

endmodule
