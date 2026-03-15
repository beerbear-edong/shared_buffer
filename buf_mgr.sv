`timescale 1ns / 1ps


module buf_mgr(
    input  wire         clk                  ,
    input  wire         rst_n                ,
    // With bus_rx
    output wire [12:0]  buf_blk_cnt          ,//缓存块空闲数量
    output wire [11:0]  buf_blk_addr         ,
    input  wire         buf_blk_rd_en        ,
    input  wire [63:0]  buf_wr_data          ,
    input  wire [14:0]  buf_wr_addr          ,
    input  wire         buf_wr_en            ,

    // With bus_tx
    output wire [63:0]  buf_rd_data          ,
    input  wire [14:0]  buf_rd_addr          ,
    
    input  wire [11:0]  rls_buf_blk_addr     ,//bus_tx释放的buffer块地址
    input  wire         rls_buf_blk_en       ,

    input  wire         buf_list_info_wen    ,//链表信息写使能
    input  wire [11:0]  buf_list_info_waddr  ,
    input  wire [31:0]  buf_list_info_wdata  ,
    input  wire [11:0]  buf_list_info_raddr  ,
    output wire [31:0]  buf_list_info_rdata   
);
// 空闲buffer块初始化以及释放逻辑
reg  [12:0] init_cnt                 ;
reg         free_blk_fifo_init_done  ;

reg  [11:0] free_blk_fifo_wdata      ;//大区块地址
reg         free_blk_fifo_wren       ;
wire        free_blk_fifo_req        ;
wire [11:0] free_blk_fifo_addr       ;
wire        free_blk_fifo_full       ;
wire [12:0] free_blk_count           ;

always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        init_cnt <= 13'b0;
    else if(free_blk_fifo_init_done == 1'b0)
        init_cnt <= init_cnt + 13'b1;
    else
        init_cnt <= init_cnt;
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        free_blk_fifo_init_done <= 1'b0;
    else if(init_cnt == 13'b0_1111_1111_1111)
        free_blk_fifo_init_done <= 1'b1;
    else
        free_blk_fifo_init_done <= free_blk_fifo_init_done;
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        free_blk_fifo_wren  <= 1'b0;
        free_blk_fifo_wdata <= 12'b0;
    end
    else if(free_blk_fifo_init_done == 1'b0 && free_blk_fifo_full == 1'b0) begin
        free_blk_fifo_wren  <= 1'b1;
        free_blk_fifo_wdata <= init_cnt[11:0];
    end
    else begin
        free_blk_fifo_wren  <= rls_buf_blk_en;
        free_blk_fifo_wdata <= rls_buf_blk_addr;
    end
end

// `ifdef FPGA
Free_Buffer_Block_FIFO free_buffer_block_fifo_inst (
  .clk        (clk                  ),     // input wire clk
  .rst        (~rst_n               ),     // input wire rst
  .din        (free_blk_fifo_wdata  ),     // input wire [11 : 0] din
  .wr_en      (free_blk_fifo_wren   ),     // input wire wr_en
  .rd_en      (free_blk_fifo_req    ),     // input wire rd_en
  .dout       (free_blk_fifo_addr   ),     // output wire [11 : 0] dout
  .full       (free_blk_fifo_full   ),     // output wire full
  .empty      (                     ),     // output wire empty
  .data_count (free_blk_count       )      // output wire [12 : 0] data_count
);


Linked_List_RAM linked_list_ram_inst(
    .clka     (clk                  ),      // input wire clka
    .wea      (buf_list_info_wen    ),      // input wire [0 : 0] wea
    .addra    (buf_list_info_waddr  ),      // input wire [11 : 0] addra
    .dina     (buf_list_info_wdata  ),      // input wire [31 : 0] dina
    .clkb     (clk                  ),      // input wire clkb
    .addrb    (buf_list_info_raddr  ),      // input wire [11 : 0] addrb
    .doutb    (buf_list_info_rdata  )       // output wire [31 : 0] doutb
);


// memory still 72‑bit wide; pad/strip at interface
//wire [71:0] mem_dout;

// SDP_RAM_W72_D32768 shared_buffer_inst (
//   .clka(clk),    // input wire clka
//   .ena(1'b1),      // input wire ena
//   .wea(buf_wr_en),      // input wire [0 : 0] wea
//   .addra(buf_wr_addr),  // input wire [14 : 0] addra
//   .dina({8'b0, buf_wr_data}),    // input wire [71 : 0] dina (pad high bits)
//   .clkb(clk),    // input wire clkb
//   .addrb(buf_rd_addr),  // input wire [14 : 0] addrb
//   .doutb(mem_dout)  // output wire [71 : 0] doutb
// );

// assign buf_rd_data = mem_dout[63:0];

SDP_RAM_W64_D32768 shared_buffer_inst (
  .clka(clk),    // input wire clka
  .ena(1'b1),      // input wire ena
  .wea(buf_wr_en),      // input wire [0 : 0] wea
  .addra(buf_wr_addr),  // input wire [14 : 0] addra
  .dina({buf_wr_data}),    // input wire [71 : 0] dina (pad high bits)
  .clkb(clk),    // input wire clkb
  .addrb(buf_rd_addr),  // input wire [14 : 0] addrb
  .doutb(buf_rd_data)  // output wire [71 : 0] doutb
);

// `endif
assign buf_blk_addr = free_blk_fifo_addr;//分配出去的大区块地址
assign buf_blk_cnt  = free_blk_count;
assign free_blk_fifo_req = buf_blk_rd_en;
endmodule
