module arbiter (
    input  wire           clk         ,
    input  wire           rst_n       ,
    // Config
    input  wire           sch_mode    , // 0 SP, 1 WRR
    input  wire [7:0]     Weight[0:7] ,
    // crossbar相关已删除
    input  wire [3:0]     cb_rdy      ,
    
    // With queue_mgr
    input  wire [31:0]    queue_empty ,


    // With bus_tx
    input  wire           sch_done    ,
    output reg  [4:0]     sch_id      ,
    output reg            sch_en       

);
parameter IDLE    = 4'b0001;
parameter POLLING = 4'b0010;
parameter ARB_KEEP = 4'b0100;

reg  [3:0]   nstate, cstate;

wire [31:0]  qstatus        ;
reg  [7:0]   rmd[0:31]      ;
reg  [31:0]  top_pri        ;

reg  [31:0]  grant          ;
reg  [63:0]  grant_ext      ;

reg  [1:0]   sch_port_id    ;

reg          fin            ;

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
                if(~|qstatus)
                    nstate <= IDLE;
                else
                    nstate <= POLLING;
            end
            POLLING: begin
                nstate <= ARB_KEEP;
            end
            ARB_KEEP: begin
                if(sch_done && ~|qstatus)
                    nstate <= IDLE;
                else if(sch_done)
                    nstate <= IDLE;
                else
                    nstate <= ARB_KEEP;
            end
            default: begin
                nstate <= IDLE;
            end
        endcase
    end
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        fin  <= 1'b0;
    else if(sch_en)
        fin  <= 1'b1;
    else 
        fin  <= fin;
end

always @(*) begin
    case(grant)
        32'h0000_0001:
            sch_id <= 5'h0;
        32'h0000_0002:
            sch_id <= 5'h1;
        32'h0000_0004:
            sch_id <= 5'h2;
        32'h0000_0008:
            sch_id <= 5'h3;
        32'h0000_0010:
            sch_id <= 5'h4;
        32'h0000_0020:
            sch_id <= 5'h5;
        32'h0000_0040:
            sch_id <= 5'h6;
        32'h0000_0080:
            sch_id <= 5'h7;
        32'h0000_0100:
            sch_id <= 5'h8;
        32'h0000_0200:
            sch_id <= 5'h9;
        32'h0000_0400:
            sch_id <= 5'ha;
        32'h0000_0800:
            sch_id <= 5'hb;
        32'h0000_1000:
            sch_id <= 5'hc;
        32'h0000_2000:
            sch_id <= 5'hd;
        32'h0000_4000:
            sch_id <= 5'he;
        32'h0000_8000:
            sch_id <= 5'hf;
        32'h0001_0000:
            sch_id <= 5'h10;
        32'h0002_0000:
            sch_id <= 5'h11;
        32'h0004_0000:
            sch_id <= 5'h12;
        32'h0008_0000:
            sch_id <= 5'h13;
        32'h0010_0000:
            sch_id <= 5'h14;
        32'h0020_0000:
            sch_id <= 5'h15;
        32'h0040_0000:
            sch_id <= 5'h16;
        32'h0080_0000:
            sch_id <= 5'h17;
        32'h0100_0000:
            sch_id <= 5'h18;
        32'h0200_0000:
            sch_id <= 5'h19;
        32'h0400_0000:
            sch_id <= 5'h1a;
        32'h0800_0000:
            sch_id <= 5'h1b;
        32'h1000_0000:
            sch_id <= 5'h1c;
        32'h2000_0000:
            sch_id <= 5'h1d;
        32'h4000_0000:
            sch_id <= 5'h1e;
        32'h8000_0000:
            sch_id <= 5'h1f;
        default:
            sch_id <= 5'b0 ;
    endcase
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        sch_port_id <= 2'b11;
    else if(|qstatus) begin
        case(sch_port_id)
            2'b00: begin
                if(|qstatus[15:8])
                    sch_port_id <= 2'b01;
                else if(|qstatus[23:16])
                    sch_port_id <= 2'b10;
                else if(|qstatus[31:24])
                    sch_port_id <= 2'b11;
                else 
                    sch_port_id <= 2'b00;
            end
            2'b01: begin
                if(|qstatus[23:16])
                    sch_port_id <= 2'b10;
                else if(|qstatus[31:24])
                    sch_port_id <= 2'b11;
                else if(|qstatus[7:0])
                    sch_port_id <= 2'b00;
                else 
                    sch_port_id <= 2'b01;
            end
            2'b10: begin
                if(|qstatus[31:24])
                    sch_port_id <= 2'b11;
                else if(|qstatus[7:0])
                    sch_port_id <= 2'b00;
                else if(|qstatus[15:8])
                    sch_port_id <= 2'b01;
                else 
                    sch_port_id <= 2'b10;
            end
            2'b11: begin
                if(|qstatus[7:0])
                    sch_port_id <= 2'b00;
                else if(|qstatus[15:8])
                    sch_port_id <= 2'b01;
                else if(|qstatus[23:16])
                    sch_port_id <= 2'b10;
                else
                    sch_port_id <= 2'b11;
            end
            default:
                sch_port_id <= sch_port_id;
        endcase
    end
    else
        sch_port_id <= sch_port_id;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        grant <= 32'b1;
    else if(cstate == POLLING) begin
        case(sch_port_id)
            2'b00:
                grant <= {24'b0, grant_ext[15:8] | grant_ext[7:0]};
            2'b01:
                grant <= {16'b0, grant_ext[31:24] | grant_ext[23:16], 8'b0};
            2'b10:
                grant <= {8'b0,  grant_ext[47:40] | grant_ext[39:32], 16'b0};
            2'b11:
                grant <= {grant_ext[63:56] | grant_ext[55:48], 24'b0};
            default:
                grant <= {24'b0, grant_ext[15:8] | grant_ext[7:0]};
        endcase
    end
    else
        grant <= grant;
end

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        sch_en <= 1'b0;
    else if(cstate == POLLING)
        sch_en <= 1'b1;
    else
        sch_en <= 1'b0;
end
generate
    genvar i;
    for(i = 0; i < 32; i+=1) begin: queue_schedule_update
        assign qstatus[i] = (sch_mode ? (|rmd[i]) : 1'b1) & ~queue_empty[i] & cb_rdy[i/8];
        always@(posedge clk or negedge rst_n) begin
            if(~rst_n)
                rmd[i] <= 8'b0;
            else if(sch_mode == 0)
                rmd[i] <= 8'b0;
            else if(nstate == IDLE && ~&queue_empty[i/8*8+7-:8] && cb_rdy[i/8])
                rmd[i] <= rmd[i] + Weight[i % 8];
            else if(sch_en && grant[i])
                rmd[i] <= rmd[i] - 8'b1;
            else
                rmd[i] <= rmd[i];
        end
    end

    for(i = 1; i <= 4; i+=1) begin: polling_update
        always@(posedge clk or negedge rst_n) begin
            if(~rst_n) 
                grant_ext[16*i-1-:16]  <= 16'b0;
            else if(nstate == POLLING)
                grant_ext[16*i-1-:16]  <= {qstatus[8*i-1-:8], qstatus[8*i-1-:8]} 
                & ~({qstatus[8*i-1-:8], qstatus[8*i-1-:8]} - {8'b0, top_pri[8*i-1-:8]});
            else
                grant_ext[16*i-1-:16]  <= grant_ext[16*i-1-:16];
        end
    end
endgenerate

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        top_pri <= {4{8'b1}};
    else if(~sch_mode)
        top_pri <= {4{8'b1}};
    else if(sch_en && fin) begin
        case(sch_id[3:2])
            2'b00:
                top_pri <= {top_pri[31:8], grant[6:0], grant[7]};
            2'b01:
                top_pri <= {top_pri[31:16], grant[14:8], grant[15], top_pri[7:0]};
            2'b10:
                top_pri <= {top_pri[31:24], grant[22:16], grant[23], top_pri[15:0]};
            2'b11:
                top_pri <= {grant[30:24], grant[31], top_pri[23:0]};
            default:
                top_pri <= top_pri;
        endcase
    end
    else
        top_pri <= top_pri;
end

endmodule