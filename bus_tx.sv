module bus_tx(
    input  wire         clk                  ,
    input  wire         rst_n                ,

    // With buf_mgr
    input  wire [63:0]  buf_rd_data          ,
    output wire [14:0]  buf_rd_addr          ,
    output reg  [11:0]  rls_buf_blk_addr     ,
    output reg          rls_buf_blk_en       ,

    output wire [11:0]  buf_list_info_raddr  ,
    input  wire [31:0]  buf_list_info_rdata  ,

    // With queue_mgr
    output reg  [23:0]  deqhead_wdata        ,
    output wire [4:0]   deqhead_addr         ,
    output reg          deqhead_wen          ,
    input  wire [23:0]  deqhead_rdata        ,

    output wire [15:0]  deqtail_wdata        ,
    output wire [4:0]   deqtail_addr         ,
    output wire         deqtail_wen          ,
    input  wire [15:0]  deqtail_rdata        ,

    output reg          deq_en               ,
    output wire [4:0]   deq_addr             ,
    input  wire [15:0]  deq_cnt              ,

    // With arbiter
    input  wire [4:0]   sch_id               ,
    input  wire         sch_en               ,
    output reg          sch_done             ,

    // crossbar相关已删除
    output reg  [63:0]  tx_data              ,
    output reg          tx_data_en           ,
    output reg  [10:0]  tx_data_len          ,
    output reg  [3:0]   tx_dst_bus              
);

parameter IDLE   = 4'b0001;
parameter PAUSE1 = 4'b0010;
parameter PAUSE2 = 4'b0100;
parameter TRANS  = 4'b1000;


reg [3:0]  nstate, cstate;

reg [2:0]  buf_slice_cnt;
reg [11:0] buf_deq_addr;

reg        pkt_rd_en, pkt_rd_en_ff1;

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        cstate <= IDLE;
    else 
        cstate <= nstate;
end

always@(*) begin
    if(~rst_n)
        nstate <= IDLE;
    else begin
        case(cstate)
            IDLE: begin
                if(sch_en)
                    nstate <= PAUSE1;
                else 
                    nstate <= IDLE;
            end
            PAUSE1:
                nstate <= PAUSE2;
            PAUSE2:
                nstate <= TRANS;
            TRANS: begin
                if(sch_done)
                    nstate <= IDLE;
                else
                    nstate <= TRANS;
            end
            default:
                nstate <= IDLE;
        endcase
    end
end

assign deqhead_addr = sch_id;
assign deqtail_addr = sch_id;
assign deq_addr     = sch_id;
assign buf_list_info_raddr = buf_deq_addr;
assign buf_rd_addr = {buf_deq_addr, buf_slice_cnt};
// assign rls_buf_blk_addr = buf_deq_addr;
assign deqtail_wen = 1'b0;
assign deqtail_wdata = 16'b0;
always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        buf_slice_cnt <= 3'b0;
    end
    else if(nstate == TRANS)
        buf_slice_cnt <= buf_slice_cnt + 3'b1;
    else
        buf_slice_cnt <= 3'b0;
end

// always@(posedge clk or negedge rst_n) begin
//     if(~rst_n)
//         buf_rd_addr <= 15'b0;
//     else if(nstate == TRANS)
//         buf_rd_addr = {buf_deq_addr, buf_slice_cnt};
//     else
//         buf_rd_addr <= buf_rd_addr;
// end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        buf_deq_addr <= 12'b0;
        rls_buf_blk_en <= 1'b0;
        rls_buf_blk_addr <= 12'b0;
    end
    else if(nstate == PAUSE2) begin
        buf_deq_addr <= deqhead_rdata[22:11];
        rls_buf_blk_en <= 1'b0;
        rls_buf_blk_addr <= 12'b0;
    end
    else if(nstate == TRANS && buf_slice_cnt + 3'b1 == buf_list_info_rdata[25:23]) begin
        buf_deq_addr <= buf_list_info_rdata[22:11];
        rls_buf_blk_en <= 1'b1;
        rls_buf_blk_addr <= buf_deq_addr;
    end
    else begin
        buf_deq_addr <= buf_deq_addr;
        rls_buf_blk_en <= 1'b0;
        rls_buf_blk_addr <= 12'b0;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        deq_en  <= 1'b0;
    else if(sch_en)
        deq_en  <= 1'b1;
    else
        deq_en  <= 1'b0;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        deqhead_wen <= 1'b0;
        deqhead_wdata <= 24'b0;
    end
    else if(cstate == TRANS && nstate == IDLE && deq_cnt) begin
        deqhead_wen <= 1'b1;
        deqhead_wdata <= {1'b0, buf_deq_addr, buf_list_info_rdata[10:0]};
    end
    else begin
        deqhead_wen <= 1'b0;
        deqhead_wdata <= 24'b0;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        sch_done <= 1'b0;
    else if(nstate == TRANS && buf_list_info_rdata[26] 
        && buf_slice_cnt + 3'b1 == buf_list_info_rdata[25:23])
        sch_done <= 1'b1;
    else
        sch_done <= 1'b0;
end


always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        tx_dst_bus <= 4'b0;
    else if(pkt_rd_en_ff1) begin
        case(sch_id[4:3])
            2'b00:
                tx_dst_bus <= 4'b0001;
            2'b01:
                tx_dst_bus <= 4'b0010;
            2'b10:
                tx_dst_bus <= 4'b0100;
            2'b11:
                tx_dst_bus <= 4'b1000;
            default:
                tx_dst_bus <= 4'b0;
        endcase
    end
    else
        tx_dst_bus <= 4'b0;

end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        pkt_rd_en <= 1'b0;
    else if(nstate == TRANS)
        pkt_rd_en <= 1'b1;
    else
        pkt_rd_en <= 1'b0;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        pkt_rd_en_ff1 <= 1'b0;
    end
    else begin
        pkt_rd_en_ff1 <= pkt_rd_en;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        tx_data      <= 64'b0;
        tx_data_en   <= 1'b0 ;
        tx_data_len  <= 11'b0;
    end
    else if(pkt_rd_en_ff1) begin
        tx_data      <= buf_rd_data;
        tx_data_en   <= 1'b1;
        tx_data_len  <= deqhead_rdata[10:0];
    end
    else begin
        tx_data      <= 64'b0;
        tx_data_en   <= 1'b0 ;
        tx_data_len  <= 11'b0;
    end
end

endmodule