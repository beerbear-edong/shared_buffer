`timescale 1ns / 1ps
module Monitor#(
  parameter id = 0
)(
  input   wire    clk   ,
  input   wire    rst_n ,
  pkt_if.pkt_in   rd    ,
  input   wire    fin
);
  integer file;
  string  file_name;
  string  file_leaf;
  bit     log_disabled;

  task automatic open_log_file;
  begin
    if(file != 0 || log_disabled)
      return;

    file_name = {"../tc/", file_leaf};
    file = $fopen(file_name, "w");
    if(file == 0) begin
      log_disabled = 1'b1;
      $display("[MON_WARN] %t open file failed(id=%0d, name=%s), disable file logging",
               $time, id, file_name);
    end
  end
  endtask

  initial begin
    file         = 0;
    file_name    = "";
    log_disabled = 1'b0;

    if(id < 4)
      file_leaf = $sformatf("port_%0d_in.txt", id);
    else
      file_leaf = $sformatf("port_%0d_out.txt", id-4);

    // XSim runs from the xsim directory, so logs should live in ../tc.
    void'($system("cmd /c if not exist ..\\tc mkdir ..\\tc >nul 2>nul"));

    wait(fin == 1'b1);
    if(file != 0)
      $fclose(file);
  end

  always@(posedge clk) begin
    if(rst_n && (rd.vld || rd.eop) && file == 0 && !log_disabled)
      open_log_file();

    if(file != 0 && rd.vld)
      $fdisplay(file, "%016h", rd.data);
    else if(file != 0 && rd.eop)
      $fdisplay(file, "");
  end

endmodule
