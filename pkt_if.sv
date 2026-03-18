`timescale 1ns / 1ps

`ifndef PKT_IF
`define PKT_IF
interface pkt_if #(
    parameter DW = 64
)(
    // input logic clk
);
logic        sop  ; 
logic        eop  ;
logic        vld  ;
logic [63:0] data ;
modport pkt_in (
    input sop, eop, vld, data
);
modport pkt_out(
    output sop, eop, vld, data
);
endinterface //pkt_if
`endif