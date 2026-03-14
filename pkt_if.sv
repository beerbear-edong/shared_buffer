`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/08 17:19:06
// Design Name: 
// Module Name: pkt_if
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


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