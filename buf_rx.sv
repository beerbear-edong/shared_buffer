module bus_rx(
    input  wire         clk                  ,
    input  wire         rst_n                ,
    // With info_collector
    input  wire [17:0]  pkt_info_i           ,
    input  wire         pkt_info_en          ,
    input  wire         pkt_info_ed          , 
    // raw packet data (no ECC)
    input  wire [63:0]  data_i               ,
    // With buffer_mgr
    input  wire [12:0]  buf_blk_cnt          ,
    input  wire [11:0]  buf_blk_addr         ,
    output reg          buf_blk_rd_en        ,
    output reg  [63:0]  buf_wr_data          ,
    output reg  [14:0]  buf_wr_addr          ,
    output reg          buf_wr_en            ,

    output reg          buf_list_info_wen    ,
    output reg  [11:0]  buf_list_info_waddr  ,
    output reg  [31:0]  buf_list_info_wdata  ,

    // With queue_mgr
    output reg  [23:0]  enqhead_wdata        ,
    output wire [4:0]   enqhead_addr         ,
    output reg          enqhead_wen          ,
    output reg  [15:0]  enqtail_wdata        ,
    output wire [4:0]   enqtail_addr         ,
    output reg          enqtail_wen          ,
    input  wire [11:0]  enqtail_rdata        , 
    output reg          enq_en               ,
    output wire [4:0]   enq_addr             ,
    input  wire [15:0]  enq_cnt              

);

parameter IDLE    = 4'b0001;
parameter DISCARD = 4'b0010;
parameter BUFFER  = 4'b0100;

reg  [3:0]    nstate, cstate;

reg  [63:0]   data_sample;
reg  [63:0]   data_sample_ff1;
//reg           data_en_sample;未使用
//reg           data_en_sample_ff1;未使用
reg           pkt_info_ed_ff1;



wire [10:0]   pkt_len;
wire [2:0]    pkt_pri;
wire [3:0]    pkt_dst;
reg  [10:0]   r_pkt_len;
reg  [2:0]    r_pkt_pri;
reg  [3:0]    r_pkt_dst;

reg           enqueue_flag;
wire          buf_req;

reg  [11:0]   buf_use_addr, buf_use_addr_ff1;
reg  [2:0]    buf_slice_cnt, buf_slice_cnt_ff1;
reg           first_buf_flag, first_buf_flag_ff1;// 用于标记包的第一块，单块包的第一块也是最后一块

reg  [4:0]    qid;

// 每个队列保存最近一次写入的块元信息，用于 update_prev 时正确回填
reg  [14:0]   tail_meta[0:31]; // {pkt_ed, slice_cnt[2:0], pkt_len[10:0]}，不再缓存 first_buf_flag
integer       k;

reg           blk_ed, pkt_ed;

always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        cstate <= IDLE;
    else
        cstate <= nstate;
end

always @(*) begin
    if(~rst_n)
        nstate <= IDLE;
    else 
        case (cstate)
            IDLE: 
                if(pkt_info_en & buf_req)
                    nstate <= BUFFER;
                else if(pkt_info_en & ~buf_req)
                    nstate <= DISCARD;
                else 
                    nstate <= IDLE;
            DISCARD:
                if(pkt_info_ed_ff1)
                    nstate <= IDLE;
                else
                    nstate <= DISCARD;
            BUFFER:
                    if(pkt_info_ed_ff1)
                        nstate <= IDLE;
                    else
                        nstate <= BUFFER;            
            default:
                nstate  <= IDLE;
        endcase
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        data_sample        <= 64'b0;
        data_sample_ff1    <= 64'b0;
    end
    else begin
        data_sample        <= data_i;
        data_sample_ff1    <= data_sample;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        pkt_info_ed_ff1 <= 1'b0;
    end
    else begin
        pkt_info_ed_ff1 <= pkt_info_ed;
    end
end

assign pkt_dst     = pkt_info_i[3:0] ;
assign pkt_pri     = pkt_info_i[6:4] ;
assign pkt_len     = pkt_info_i[17:7];
assign buf_req     = (((pkt_len - 11'd1) >> 6) + 8'd1  <= buf_blk_cnt) ? 1'b1 : 1'b0;


always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        r_pkt_dst    <=  4'b0;
        r_pkt_pri    <=  3'b0;
        r_pkt_len    <=  11'b0;
    end
    else if(pkt_info_en) begin
        r_pkt_dst    <=  pkt_dst;
        r_pkt_pri    <=  pkt_pri;
        r_pkt_len    <=  pkt_len;
    end
    else begin
        r_pkt_dst    <=  r_pkt_dst;
        r_pkt_pri    <=  r_pkt_pri;
        r_pkt_len    <=  r_pkt_len;
    end
end

assign qid          = {r_pkt_dst[3:2], r_pkt_pri};

assign enqhead_addr = qid;
assign enqtail_addr = qid;
assign enq_addr     = qid;

// 公共条件信号
wire pkt_boundary  = (cstate == BUFFER && nstate == IDLE);      // 包结束边界：当前状态是BUFFER，下一状态是IDLE
wire blk_boundary  = (buf_slice_cnt == 3'h7 && enqueue_flag);   // 块结束边界：当前正在入队且buf_slice_cnt达到7（即已入队8片数据，满一个块）
wire any_boundary  = pkt_boundary || blk_boundary;              // 任一边界：包结束或块结束
wire is_1st_of_q   = (enq_cnt == 16'b0 && first_buf_flag);      // 是否为队列的第一块：当前队列入队计数器为0且first_buf_flag为1（标记了包的第一块）
wire has_prev_blk  = ~is_1st_of_q;                              // 是否有前块：不是队列的第一块则说明有前块
wire update_prev   = any_boundary && has_prev_blk;              // 是否需要更新前块的链表信息：当出现任一边界且有前块时，需要更新前块的链表信息以指向当前块  

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        enqueue_flag   <= 1'b0;
    else if(nstate == BUFFER)
        enqueue_flag   <= 1'b1;
    else
        enqueue_flag   <= 1'b0;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        buf_slice_cnt <= 3'b0;
    else if(enqueue_flag)
        buf_slice_cnt <= buf_slice_cnt + 3'b1;
    else
        buf_slice_cnt <= 3'b0;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        buf_slice_cnt_ff1 <= 3'b0;
    else
        buf_slice_cnt_ff1 <= buf_slice_cnt;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        buf_use_addr  <= 12'b0;
    else if(!enqueue_flag || blk_boundary)
        buf_use_addr  <= buf_blk_addr;
    else
        buf_use_addr  <= buf_use_addr;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        buf_use_addr_ff1  <= 12'b0;
    else
        buf_use_addr_ff1  <= buf_use_addr;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        first_buf_flag <= 1'b0;
    else if(cstate == IDLE && nstate == BUFFER)
        first_buf_flag <= 1'b1;
    else if(any_boundary)
        first_buf_flag <= 1'b0;
    else 
        first_buf_flag <= first_buf_flag;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        first_buf_flag_ff1  <= 1'b0;
    else
        first_buf_flag_ff1  <= first_buf_flag;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        buf_wr_data   <= 64'b0;
        buf_wr_addr   <= 15'b0;
        buf_wr_en     <= 1'b0;
    end
    else if(enqueue_flag) begin
        buf_wr_data   <= data_sample_ff1;
        buf_wr_addr   <= {buf_use_addr, buf_slice_cnt};
        buf_wr_en     <= 1'b1;
    end
    else begin
        buf_wr_data   <= 64'b0;
        buf_wr_addr   <= 15'b0;
        buf_wr_en     <= 1'b0;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        buf_blk_rd_en <= 1'b0;
    else if(buf_slice_cnt == 3'b0 && enqueue_flag)
        buf_blk_rd_en <= 1'b1;
    else
        buf_blk_rd_en <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        enqhead_wdata  <= 24'b0;
        enqhead_wen    <= 1'b0;
    end
    else begin
        enqhead_wen   <= is_1st_of_q && any_boundary;
        enqhead_wdata <= (is_1st_of_q && any_boundary)
                         ? {1'b1, buf_use_addr, r_pkt_len} : 24'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        enqtail_wdata  <= 16'b0;
        enqtail_wen    <= 1'b0;
    end
    else begin
        enqtail_wen   <= any_boundary;
        enqtail_wdata <= any_boundary ? {4'b0, buf_use_addr} : 16'b0;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        buf_list_info_wen    <= 1'b0;
        buf_list_info_waddr  <= 12'b0;
        buf_list_info_wdata  <= 32'b0;
        for (k = 0; k < 32; k = k + 1)
            tail_meta[k] <= 15'b0;
    end
    else begin
        buf_list_info_wen    <= 1'b0;
        buf_list_info_waddr  <= 12'b0;
        buf_list_info_wdata  <= 32'b0;

        if (update_prev) begin
            // 当拍：改写前块的 next_addr，使之指向当前块；tail_meta 仅保留必要字段，避免误带 first 标志
            buf_list_info_wen    <= 1'b1;
            buf_list_info_waddr  <= enqtail_rdata;
            buf_list_info_wdata  <= {4'b0,
                                     1'b0,
                                     tail_meta[qid][14],
                                     tail_meta[qid][13:11],
                                     buf_use_addr,
                                     tail_meta[qid][10:0]};
        end
        else if (pkt_ed || blk_ed) begin
            // 后一拍：写当前块的完整链表条目，同时保存元数据到 tail_meta
            buf_list_info_wen    <= 1'b1;
            buf_list_info_waddr  <= buf_use_addr_ff1;
            buf_list_info_wdata  <= {4'b0,
                                     first_buf_flag_ff1,
                                     pkt_ed,
                                     buf_slice_cnt_ff1,
                                     buf_use_addr_ff1,
                                     r_pkt_len};
            tail_meta[qid]       <= {pkt_ed, buf_slice_cnt_ff1, r_pkt_len};
        end
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        blk_ed  <= 1'b0;
    else
        blk_ed  <= any_boundary;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        pkt_ed  <= 1'b0;
    else
        pkt_ed  <= pkt_boundary;
end



always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        enq_en <= 1'b0;
    else
        enq_en <= pkt_boundary;
end

endmodule