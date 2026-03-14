`timescale 1ns / 1ps



module rx_polling(
    input  wire         clk               ,
    input  wire         rst_n             ,
    input  wire [65:0]  rx_data_o   [0:3] ,
    output reg          rx_rd_en    [0:3] ,//读使能信号
    input  wire         rx_empty    [0:3] ,
    output reg  [65:0]  bus_data_o        ,
    output reg          bus_data_en        //输出数据有效,轮询模块从 4 路 FIFO 中读取到有效数据并输出到bus_data_o时，
    //                      通过此语句置位bus_data_en，告诉后续的info_collector
);
reg        c_state, n_state;

wire [3:0] rx_state;
wire       rx_valid;
wire [7:0] grant_ext;
reg  [3:0] grant;
reg  [3:0] top_pri;
reg        fin;
reg        rx_valid_r;

always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        c_state <= 1'b0;
    else
        c_state <= n_state;
end
always@(*) begin
    if(~rst_n) 
        n_state <= 1'b0;
    else begin
        case (c_state)
            1'b0:
                if(~rx_valid_r | fin)
                    n_state <= 1'b0;
                else
                    n_state <= 1'b1;
            1'b1:
                if(bus_data_o[64])
                    n_state <= 1'b0;
                else
                    n_state <= 1'b1;
            default:
                n_state <= 1'b0;
        endcase
    end
end

assign rx_state = {~rx_empty[3], ~rx_empty[2], ~rx_empty[1], ~rx_empty[0]};//有数据包待处理标志
assign rx_valid = |rx_state;

always@(posedge clk or negedge rst_n) begin//打拍同步
    if(~rst_n)
        rx_valid_r <= 1'b0;
    else
        rx_valid_r <= rx_valid;
end



always@(posedge clk or negedge rst_n) begin//数据包读取完成标志,c_state状态下，读取到eop则fin置1
    if(~rst_n)
        fin <= 1'b0;
    else if(c_state & bus_data_o[64])
        fin <= 1'b1;
    else 
        fin <= 1'b0;
end


always@(posedge clk or negedge rst_n) begin//轮询仲裁
    if(~rst_n)
        top_pri <= 4'b0001;
    else if(c_state && !n_state)//从c_state为1，n_state为0，更新优先级  
        top_pri <= {grant[2:0], grant[3]};
    else
        top_pri <= top_pri;
end
assign grant_ext = rx_valid ? ({rx_state, rx_state} & ~({rx_state, rx_state} - top_pri)) : 8'b0;
// assign grant     = n_state ? grant : (grant_ext[3:0] | grant_ext[7:4])  ;
always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        grant <= 4'b0;
    else if(!n_state)//只在空闲态更新grant
        grant <= (grant_ext[3:0] | grant_ext[7:4]);
    else
        grant <= grant;
end
always@(*) begin
    if(n_state) begin
        case(grant)
        4'b0001: begin
            rx_rd_en[0] <= 1'b1;
            rx_rd_en[1] <= 1'b0;
            rx_rd_en[2] <= 1'b0;
            rx_rd_en[3] <= 1'b0;
        end
        4'b0010: begin
            rx_rd_en[0] <= 1'b0;
            rx_rd_en[1] <= 1'b1;
            rx_rd_en[2] <= 1'b0;
            rx_rd_en[3] <= 1'b0;
        end
        4'b0100: begin
            rx_rd_en[0] <= 1'b0;
            rx_rd_en[1] <= 1'b0;
            rx_rd_en[2] <= 1'b1;
            rx_rd_en[3] <= 1'b0;
        end
        4'b1000: begin
            rx_rd_en[0] <= 1'b0;
            rx_rd_en[1] <= 1'b0;
            rx_rd_en[2] <= 1'b0;
            rx_rd_en[3] <= 1'b1;
        end
        default: begin
            rx_rd_en[0] <= 1'b0;
            rx_rd_en[1] <= 1'b0;
            rx_rd_en[2] <= 1'b0;
            rx_rd_en[3] <= 1'b0;
        end
        endcase
    end
    else begin
        rx_rd_en[0] <= 1'b0;
        rx_rd_en[1] <= 1'b0;
        rx_rd_en[2] <= 1'b0;
        rx_rd_en[3] <= 1'b0;
    end
end
always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        bus_data_en <= 1'b0;
    else if(n_state)
        bus_data_en <= 1'b1;
    else
        bus_data_en <= 1'b0;
end
always@(posedge clk or negedge rst_n) begin
    if(~rst_n)
        bus_data_o     <= 66'b0;
    else if(n_state) begin
        case(grant)
        4'b0001: begin
            bus_data_o <= rx_data_o[0];
        end
        4'b0010: begin
            bus_data_o <= rx_data_o[1];
        end
        4'b0100: begin
            bus_data_o <= rx_data_o[2];
        end
        4'b1000: begin
            bus_data_o <= rx_data_o[3];
        end
        default: begin
            bus_data_o <= 66'b0;
        end
        endcase
    end
    else begin
        bus_data_o     <= 66'b0;
    end
end

endmodule
