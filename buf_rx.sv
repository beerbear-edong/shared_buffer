module bus_rx(
    input  wire         clk                  ,
    input  wire         rst_n                ,
    // With info_collector
    input  wire [17:0]  pkt_info_i           ,
    input  wire         pkt_info_en          ,
    input  wire         pkt_info_ed          , 
    // raw packet data (no ECC)
    input  wire [63:0]  data_i               ,
    input  wire         data_en             ,
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
    // input  wire [23:0]  enqhead_rdata        , // 未用端口，已注释
    output reg  [15:0]  enqtail_wdata        ,
    output wire [4:0]   enqtail_addr         ,
    output reg          enqtail_wen          ,
    // input  wire [15:0]  enqtail_rdata        , // 未用端口，已注释
    output reg          enq_en               ,
    output wire [4:0]   enq_addr             ,
    // input  wire [15:0]  enq_cnt               // 未用端口，已注释

);

parameter IDLE    = 4'b0001;
parameter DISCARD = 4'b0010;
parameter BUFFER  = 4'b0100;

reg  [3:0]    nstate, cstate;

reg  [63:0]   data_sample;
reg  [63:0]   data_sample_ff1;
reg           data_en_sample;
reg           data_en_sample_ff1;
reg           pkt_info_ed_ff1;



wire [10:0]   pkt_len;
wire [2:0]    pkt_pri;
wire [3:0]    pkt_dst;
reg  [10:0]   r_pkt_len;
reg  [2:0]    r_pkt_pri;
reg  [3:0]    r_pkt_dst;

reg           discard_flag;
reg           enqueue_flag;
wire [10:0]   pkt_len_dec;
wire          buf_req;

reg  [11:0]   buf_use_addr, buf_use_addr_ff1;
reg  [2:0]    buf_slice_cnt;
reg           first_buf_flag, first_buf_flag_ff1;

reg  [4:0]    qid;

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
        data_en_sample     <= 1'b0;
    end
    else begin
        data_sample        <= data_i;
        data_sample_ff1    <= data_sample;
        data_en_sample     <= data_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        discard_flag <= 1'b0;
    end
    else if(nstate == DISCARD)
        discard_flag <= 1'b1;
    else
        discard_flag <= 1'b0;
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
assign pkt_len_dec = pkt_len - 11'b1; 
assign buf_req     = (pkt_len_dec[10:3] + 8'b1 <= {buf_blk_cnt, 3'b0}) ? 1'b1 : 1'b0;


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
        buf_use_addr  <= 12'b0;
    else if(!enqueue_flag)
        buf_use_addr  <= buf_blk_addr;
    else if(enqueue_flag && buf_slice_cnt == 3'h7)
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
    else if((enqueue_flag && buf_slice_cnt == 3'h7) || (cstate == BUFFER && nstate == IDLE))
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
        // enqhead_addr   <= 5'b0;
        enqhead_wen    <= 1'b0;
    end
    else if(enq_cnt == 16'b0 && first_buf_flag && 
      ((buf_slice_cnt == 3'h7 && enqueue_flag) || 
      (cstate == BUFFER && nstate == IDLE))) begin
        enqhead_wdata  <= {1'b1, buf_use_addr, r_pkt_len};
        // enqhead_addr   <= qid;
        enqhead_wen    <= 1'b1;
    end
    else begin
        enqhead_wdata  <= 24'b0;
        // enqhead_addr   <= 5'b0;
        enqhead_wen    <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        enqtail_wdata  <= 16'b0;
        // enqtail_addr   <= 5'b0;
        enqtail_wen    <= 1'b0;
    end
    else if((cstate == BUFFER && nstate == IDLE) ||
            (buf_slice_cnt == 3'h7 && enqueue_flag)) begin
        enqtail_wdata  <= {4'b0, buf_use_addr};
        // enqtail_addr   <= qid;
        enqtail_wen    <= 1'b1;
    end
    else begin
        enqtail_wdata  <= 16'b0;
        // enqtail_addr   <= 5'b0;
        enqtail_wen    <= 1'b0;
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        buf_list_info_wen    <= 1'b0;
        buf_list_info_waddr  <= 12'b0;
        buf_list_info_wdata  <= 32'b0;
    end
    else if(cstate == BUFFER && nstate == IDLE && ~(enq_cnt == 16'b0 && first_buf_flag)) begin
        buf_list_info_wen    <= 1'b1;
        buf_list_info_waddr  <= enqtail_rdata;
        // buf_list_info_wdata  <= {first_buf_flag, 1'b1, buf_slice_cnt, buf_use_addr, r_pkt_len};
        buf_list_info_wdata  <= {buf_list_info_wdata[31:23], buf_use_addr, buf_list_info_wdata[10:0]};
    end
    else if(pkt_ed) begin
        buf_list_info_wen    <= 1'b1;
        buf_list_info_waddr  <= buf_use_addr_ff1;
        buf_list_info_wdata  <= {first_buf_flag_ff1, 1'b1, buf_slice_cnt, buf_use_addr_ff1, r_pkt_len};
    end
    else if(buf_slice_cnt == 3'h7 && enqueue_flag && ~(enq_cnt == 16'b0 && first_buf_flag)) begin
        buf_list_info_wen    <= 1'b1;
        buf_list_info_waddr  <= enqtail_rdata;
        // buf_list_info_wdata  <= {first_buf_flag, 1'b0, buf_slice_cnt, buf_use_addr, r_pkt_len}; 
        buf_list_info_wdata  <= {buf_list_info_wdata[31:23], buf_use_addr, buf_list_info_wdata[10:0]};
    end
    else if(blk_ed)begin
        buf_list_info_wen    <= 1'b1;
        buf_list_info_waddr  <= buf_use_addr_ff1;
        buf_list_info_wdata  <= {first_buf_flag_ff1, 1'b0, buf_slice_cnt, buf_use_addr_ff1, r_pkt_len};
    end
    else begin
        buf_list_info_wen    <= 1'b0;
        buf_list_info_waddr  <= 12'b0;
        buf_list_info_wdata  <= 32'b0;    
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        blk_ed  <= 1'b0;
    end
    else if(cstate == BUFFER && nstate == IDLE)
        blk_ed  <= 1'b1;
    else if(buf_slice_cnt == 3'h7 && enqueue_flag)
        blk_ed  <= 1'b1;
    else
        blk_ed  <= 1'b0;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        pkt_ed  <= 1'b0;
    end
    else if(cstate == BUFFER && nstate == IDLE)
        pkt_ed  <= 1'b1;
    else
        pkt_ed  <= 1'b0;
end



always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        enq_en <= 1'b0;
    else if(cstate == BUFFER && nstate == IDLE)
        enq_en <= 1'b1;
    else
        enq_en <= 1'b0;
end

endmodule