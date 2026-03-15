`timescale 1ns / 1ps

`include "top_define.v"
module rcv_top(
    input                clk            ,
    input                rst_n          ,
    input                sch_mode       ,
    input  wire [7:0]    Weight[0:7]    ,
    pkt_if.pkt_in        wr    [0:3]    ,
    output               full           ,
    output               afull          ,
    input  wire [3:0]    cb_rdy         ,
    output reg  [63:0]   tx_data        ,
    output reg           tx_data_en     ,
    output reg  [10:0]   tx_data_len    ,
    output reg  [3:0]    tx_dst_bus       
);

reg  [65:0]  rx_data_o   [0:3];
reg          rx_rd_en    [0:3];   
wire         fifo_full   [0:3];
wire         fifo_empty  [0:3];

wire [65:0]  bus_data_o       ;
wire [63:0]  bus_data_i       ;
wire         bus_data_en      ;

// no ECC data output

wire [17:0]  pkt_info_o       ;
wire         pkt_info_en      ;
wire         pkt_info_ed      ;


wire [12:0]  buf_blk_cnt      ;
wire [11:0]  buf_blk_addr     ;
wire         buf_blk_rd_en    ;
wire [63:0]  buf_wr_data      ;
wire [14:0]  buf_wr_addr      ;
wire         buf_wr_en        ;
wire [63:0]  buf_rd_data      ;
wire [14:0]  buf_rd_addr      ;

wire [11:0]  rls_buf_blk_addr ;
wire         rls_buf_blk_en   ;

wire         buf_list_info_wen    ;
wire [11:0]  buf_list_info_waddr  ;
wire [31:0]  buf_list_info_wdata  ;
wire [11:0]  buf_list_info_raddr  ;
wire [31:0]  buf_list_info_rdata  ;

wire[23:0]       enqhead_wdata  ;
wire[4:0]        enqhead_addr   ;
wire             enqhead_wen    ;
wire[23:0]       deqhead_wdata  ;
wire[4:0]        deqhead_addr   ;
wire             deqhead_wen    ;
wire[23:0]       deqhead_rdata  ;

wire[15:0]       enqtail_wdata  ;
wire[4:0]        enqtail_addr   ;
wire             enqtail_wen    ;
wire[15:0]       enqtail_rdata  ;
wire[15:0]       deqtail_wdata  ;
wire[4:0]        deqtail_addr   ;
wire             deqtail_wen    ;

wire             enq_en         ;
wire             deq_en         ;
wire[15:0]       enq_cnt        ;
wire[15:0]       deq_cnt        ;
wire[4:0]        enq_addr       ;
wire[4:0]        deq_addr       ;

wire[31:0]       queue_empty    ;
wire             sch_done       ;
wire[4:0]        sch_id         ;
wire             sch_en         ;



// rx_data_fifo rx_data_fifo_inst[4](
//     .clk        (clk           ),
//     .rst_n      (rst_n         ),
//     .wr         (wr            ),
//     .rx_data_o  (rx_data_o     ),
//     .rx_rd_en   (rx_rd_en      ),
//     .full       (fifo_full     ),
//     .empty      (fifo_empty    )
// );

rx_data_fifo rx_data_fifo_inst_0(
    .clk        (clk           ),
    .rst_n      (rst_n         ),
    .wr         (wr[0]         ),
    .rx_data_o  (rx_data_o[0]  ),
    .rx_rd_en   (rx_rd_en[0]   ),
    .full       (fifo_full[0]  ),
    .empty      (fifo_empty[0] )
);

rx_data_fifo rx_data_fifo_inst_1(
    .clk        (clk           ),
    .rst_n      (rst_n         ),
    .wr         (wr[1]         ),
    .rx_data_o  (rx_data_o[1]  ),
    .rx_rd_en   (rx_rd_en[1]   ),
    .full       (fifo_full[1]  ),
    .empty      (fifo_empty[1] )
);


rx_data_fifo rx_data_fifo_inst_2(
    .clk        (clk           ),
    .rst_n      (rst_n         ),
    .wr         (wr[2]         ),
    .rx_data_o  (rx_data_o[2]  ),
    .rx_rd_en   (rx_rd_en[2]   ),
    .full       (fifo_full[2]  ),
    .empty      (fifo_empty[2] )
);

rx_data_fifo rx_data_fifo_inst_3(
    .clk        (clk           ),
    .rst_n      (rst_n         ),
    .wr         (wr[3]         ),
    .rx_data_o  (rx_data_o[3]  ),
    .rx_rd_en   (rx_rd_en[3]   ),
    .full       (fifo_full[3]  ),
    .empty      (fifo_empty[3] )
);



assign full = fifo_full[0] | fifo_full[1] | fifo_full[2] | fifo_full[3];
assign afull = buf_blk_cnt <= 12'd20 ? 1'b1 : 1'b0;

rx_polling rx_polling_inst(
    .clk         (clk        ),
    .rst_n       (rst_n      ),
    .rx_data_o   (rx_data_o  ),
    .rx_rd_en    (rx_rd_en   ),
    .rx_empty    (fifo_empty ),
    .bus_data_o  (bus_data_o ),
    .bus_data_en (bus_data_en)
);

info_collector info_collector_inst(
    .clk           (clk              ),  
    .rst_n         (rst_n            ),  
    .bus_data_sof  (bus_data_o[65]   ),
    .bus_data_eof  (bus_data_o[64]   ),
    .bus_data_info (bus_data_o[17:0] ),
    .bus_data_en   (bus_data_en      ),  
    .pkt_info_o  (pkt_info_o    ),  
    .pkt_info_en (pkt_info_en   ),
    .pkt_info_ed (pkt_info_ed   ) 
);

// ECC_gen removed – pass through raw 64‑bit data
assign bus_data_i = bus_data_o[63:0];

bus_rx bus_rx_inst(
    .clk                  (clk                      ),
    .rst_n                (rst_n                    ),
    .pkt_info_i           (pkt_info_o               ),
    .pkt_info_en          (pkt_info_en              ),
    .pkt_info_ed          (pkt_info_ed              ), 
    .data_i               (bus_data_i               ),
    .data_en              (bus_data_en              ),
    .buf_blk_cnt          (buf_blk_cnt              ),
    .buf_blk_addr         (buf_blk_addr             ),
    .buf_blk_rd_en        (buf_blk_rd_en            ),
    .buf_wr_data          (buf_wr_data              ),
    .buf_wr_addr          (buf_wr_addr              ),
    .buf_wr_en            (buf_wr_en                ),
    .buf_list_info_wen    (buf_list_info_wen        ),
    .buf_list_info_waddr  (buf_list_info_waddr      ),
    .buf_list_info_wdata  (buf_list_info_wdata      ),
    .enqhead_wdata        (enqhead_wdata            ),
    .enqhead_addr         (enqhead_addr             ),
    .enqhead_wen          (enqhead_wen              ),
    .enqtail_wdata        (enqtail_wdata            ),
    .enqtail_addr         (enqtail_addr             ),
    .enqtail_wen          (enqtail_wen              ),
    .enqtail_rdata        (enqtail_rdata[11:0]      ),
    .enq_en               (enq_en                   ),
    .enq_addr             (enq_addr                 ),
    .enq_cnt              (enq_cnt                  )
);

buf_mgr buf_mgr_inst(
    .clk                (clk                 ),
    .rst_n              (rst_n               ),
    .buf_blk_cnt        (buf_blk_cnt         ),
    .buf_blk_addr       (buf_blk_addr        ),
    .buf_blk_rd_en      (buf_blk_rd_en       ),
    .buf_wr_data        (buf_wr_data         ),
    .buf_wr_addr        (buf_wr_addr         ),
    .buf_wr_en          (buf_wr_en           ),
    .buf_rd_data        (buf_rd_data         ),  
    .buf_rd_addr        (buf_rd_addr         ),  
    .rls_buf_blk_addr   (rls_buf_blk_addr    ),
    .rls_buf_blk_en     (rls_buf_blk_en      ),
    .buf_list_info_wen  (buf_list_info_wen   ), 
    .buf_list_info_waddr(buf_list_info_waddr ), 
    .buf_list_info_wdata(buf_list_info_wdata ), 
    .buf_list_info_raddr(buf_list_info_raddr ), 
    .buf_list_info_rdata(buf_list_info_rdata )
);

queue_mgr queue_mgr_inst(
    .clk                (clk                 ),
    .rst_n              (rst_n               ),
    .enqhead_wdata      (enqhead_wdata       ),
    .enqhead_addr       (enqhead_addr        ),
    .enqhead_wen        (enqhead_wen         ),
    .enqhead_rdata      (                    ),
    .deqhead_wdata      (deqhead_wdata       ),
    .deqhead_addr       (deqhead_addr        ),
    .deqhead_wen        (deqhead_wen         ),
    .deqhead_rdata      (deqhead_rdata       ),
    .enqtail_wdata      (enqtail_wdata       ),
    .enqtail_addr       (enqtail_addr        ),
    .enqtail_wen        (enqtail_wen         ),
    .enqtail_rdata      (enqtail_rdata       ),
    .deqtail_wdata      (deqtail_wdata       ),
    .deqtail_addr       (deqtail_addr        ),
    .deqtail_wen        (deqtail_wen         ),
    .deqtail_rdata      (                    ),
    .enq_en             (enq_en              ),
    .deq_en             (deq_en              ),
    .enq_addr           (enq_addr            ),
    .deq_addr           (deq_addr            ),
    .enq_cnt            (enq_cnt             ),
    .deq_cnt            (deq_cnt             ),
    .queue_empty        (queue_empty         ),
    .init_done          (                    )
);

arbiter arbiter_inst(
    .clk                (clk                 ),
    .rst_n              (rst_n               ),
    .sch_mode           (sch_mode            ),
    .Weight             (Weight              ),
    .cb_rdy             (cb_rdy              ),
    .queue_empty        (queue_empty         ),
    .sch_done           (sch_done            ),
    .sch_id             (sch_id              ),
    .sch_en             (sch_en              )
);

bus_tx bus_tx_inst(
    .clk                  (clk                  ),
    .rst_n                (rst_n                ),
    .buf_rd_data          (buf_rd_data          ),
    .buf_rd_addr          (buf_rd_addr          ),
    .rls_buf_blk_addr     (rls_buf_blk_addr     ),
    .rls_buf_blk_en       (rls_buf_blk_en       ),
    .buf_list_info_raddr  (buf_list_info_raddr  ),
    .buf_list_info_rdata  (buf_list_info_rdata[26:0]),
    .deqhead_wdata        (deqhead_wdata        ),
    .deqhead_addr         (deqhead_addr         ),
    .deqhead_wen          (deqhead_wen          ),
    .deqhead_rdata        (deqhead_rdata[22:0]  ),
    .deqtail_wdata        (deqtail_wdata        ),
    .deqtail_addr         (deqtail_addr         ),
    .deqtail_wen          (deqtail_wen          ),
    .deq_en               (deq_en               ),
    .deq_addr             (deq_addr             ),
    .deq_cnt              (deq_cnt              ),
    .sch_id               (sch_id               ),
    .sch_en               (sch_en               ),
    .sch_done             (sch_done             ),
    .tx_data              (tx_data              ),
    .tx_data_en           (tx_data_en           ),
    .tx_data_len          (tx_data_len          ),
    .tx_dst_bus           (tx_dst_bus           )
);
endmodule
