`timescale 1ns / 1ps

module queue_mgr (
    input  wire             clk            ,
    input  wire             rst_n          ,
    
    input  wire[23:0]       enqhead_wdata  ,
    input  wire[4:0]        enqhead_addr   ,
    input  wire             enqhead_wen    ,
    output wire[23:0]       enqhead_rdata  ,

    input  wire[23:0]       deqhead_wdata  ,
    input  wire[4:0]        deqhead_addr   ,
    input  wire             deqhead_wen    ,
    output wire[22:0]       deqhead_rdata  ,


    input  wire[15:0]       enqtail_wdata  ,
    input  wire[4:0]        enqtail_addr   ,
    input  wire             enqtail_wen    ,
    output wire[11:0]       enqtail_rdata  ,

    input  wire[15:0]       deqtail_wdata  ,
    input  wire[4:0]        deqtail_addr   ,
    input  wire             deqtail_wen    ,
    output wire[15:0]       deqtail_rdata  ,


    // input  wire[15:0]       enqlen_wdata   ,
    // input  wire[4:0]        enqlen_addr    ,
    // input  wire             enqlen_wen     ,
    // output wire[15:0]       enqlen_rdata   ,

    // input  wire[15:0]       deqlen_wdata   ,
    // input  wire[4:0]        deqlen_addr    ,
    // input  wire             deqlen_wen     ,
    // output wire[15:0]       deqlen_rdata   ,


    // input  wire[15:0]       enqcnt_wdata   ,
    // input  wire[4:0]        enqcnt_addr    ,
    // input  wire             enqcnt_wen     ,
    // output wire[15:0]       enqcnt_rdata   ,

    // input  wire[15:0]       deqcnt_wdata   ,
    // input  wire[4:0]        deqcnt_addr    ,
    // input  wire             deqcnt_wen     ,
    // output wire[15:0]       deqcnt_rdata   ,

    input  wire             enq_en         ,
    input  wire             deq_en         ,
    input  wire[4:0]        enq_addr       ,
    input  wire[4:0]        deq_addr       ,
    output wire[15:0]       enq_cnt        ,
    output wire[15:0]       deq_cnt        ,
    output reg [31:0]       queue_empty    ,
    output reg              init_done      
);

reg [15:0]       inq_cnt_reg[0:31];

reg [4:0]        init_addr;

reg [23:0]       r_enqhead_wdata  ;
reg [4:0]        r_enqhead_addr   ;
reg              r_enqhead_wen    ;

reg [15:0]       r_enqtail_wdata  ;
reg [4:0]        r_enqtail_addr   ;
reg              r_enqtail_wen    ;

// reg [15:0]       r_enqlen_wdata   ;
// reg [4:0]        r_enqlen_addr    ;
// reg              r_enqlen_wen     ;

// reg [15:0]       r_enqcnt_wdata   ;
// reg [4:0]        r_enqcnt_addr    ;
// reg              r_enqcnt_wen     ;




always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        init_addr   <= 5'b0;
    else if(!init_done)
        init_addr   <= init_addr + 1'b1;
    else
        init_addr   <= init_addr;
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n)
        init_done   <= 1'b0;
    else if(init_addr == 5'd31)
        init_done   <= 1'b1;
    else
        init_done   <= init_done;
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        r_enqhead_wen   <= 1'b0 ;
        r_enqhead_addr  <= 5'b0 ;
        r_enqhead_wdata <= 24'b0;
    end
    else if(!init_done) begin
        r_enqhead_wen   <= 1'b1;
        r_enqhead_addr  <= init_addr;
        r_enqhead_wdata <= 24'b0;
    end
    else begin
        r_enqhead_wen   <= enqhead_wen  ;
        r_enqhead_addr  <= enqhead_addr ;
        r_enqhead_wdata <= enqhead_wdata;        
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        r_enqtail_wen   <= 1'b0 ;
        r_enqtail_addr  <= 5'b0 ;
        r_enqtail_wdata <= 16'b0;
    end
    else if(!init_done) begin
        r_enqtail_wen   <= 1'b1;
        r_enqtail_addr  <= init_addr;
        r_enqtail_wdata <= 16'b0;
    end
    else begin
        r_enqtail_wen   <= enqtail_wen  ;
        r_enqtail_addr  <= enqtail_addr ;
        r_enqtail_wdata <= enqtail_wdata;        
    end
end

integer i;

// generate
//     genvar i;
//     for(i = 0; i < 32; i=i+1) begin
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        for(i = 0; i < 32; i=i+1) begin
            inq_cnt_reg[i]         <= 16'b0;
        end
    end
    else if(enq_addr != deq_addr) begin
        if(enq_en && !deq_en) begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr] + 1'b1;
            inq_cnt_reg[deq_addr]  <= inq_cnt_reg[deq_addr];
        end
        else if(!enq_en && deq_en) begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr];
            inq_cnt_reg[deq_addr]  <= inq_cnt_reg[deq_addr] - 1'b1;
        end
        else if(enq_en && deq_en && enq_addr != deq_addr) begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr] + 1'b1;
            inq_cnt_reg[deq_addr]  <= inq_cnt_reg[deq_addr] - 1'b1;
        end
        else begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr];
            inq_cnt_reg[deq_addr]  <= inq_cnt_reg[deq_addr];
        end
    end
    else begin
        if(enq_en && !deq_en) begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr] + 1'b1;
        end
        else if(!enq_en && deq_en) begin
            inq_cnt_reg[deq_addr]  <= inq_cnt_reg[deq_addr] - 1'b1;
        end
        else begin
            inq_cnt_reg[enq_addr]  <= inq_cnt_reg[enq_addr];
        end
    end
end
//     end
// endgenerate

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        for(i = 0; i < 32; i=i+1) begin
            queue_empty[i]         <= 1'b1;
        end
    end
    else if(enq_addr != deq_addr) begin
        if(enq_en && !deq_en) begin
            queue_empty[enq_addr]  <= 1'b0;
            queue_empty[deq_addr]  <= queue_empty[deq_addr];
        end
        else if(!enq_en && deq_en) begin
            queue_empty[enq_addr]  <= queue_empty[enq_addr];
            queue_empty[deq_addr]  <= (inq_cnt_reg[deq_addr] == 1'b1) ? 1'b1 : 1'b0;
        end
        else if(enq_en && deq_en && enq_addr != deq_addr) begin
            queue_empty[enq_addr]  <= 1'b0;
            queue_empty[deq_addr]  <= (inq_cnt_reg[deq_addr] == 1'b1) ? 1'b1 : 1'b0;
        end
        else begin
            queue_empty[enq_addr]  <= queue_empty[enq_addr];
            queue_empty[deq_addr]  <= queue_empty[deq_addr];
        end
    end
    else begin
        if(enq_en && !deq_en) begin
            queue_empty[enq_addr]  <= 1'b0;
        end
        else if(!enq_en && deq_en) begin
            queue_empty[deq_addr]  <= (inq_cnt_reg[deq_addr] == 1'b1) ? 1'b1 : 1'b0;
        end
        else begin
            queue_empty[enq_addr]  <= queue_empty[enq_addr];
        end
    end
end


assign enq_cnt = inq_cnt_reg[enq_addr];
assign deq_cnt = inq_cnt_reg[deq_addr];


// `ifdef FPGA
wire [23:0] deqhead_rdata_full;

qhead_info qhead_info_inst (
  .clka    (clk              ),  // input wire clka
  .wea     (r_enqhead_wen    ),  // input wire [0 : 0] wea
  .addra   (r_enqhead_addr   ),  // input wire [4 : 0] addra
  .dina    (r_enqhead_wdata  ),  // input wire [23 : 0] dina
  .douta   (enqhead_rdata    ),  // output wire [23 : 0] douta
  .clkb    (clk              ),  // input wire clkb
  .web     (deqhead_wen      ),  // input wire [0 : 0] web
  .addrb   (deqhead_addr     ),  // input wire [4 : 0] addrb
  .dinb    (deqhead_wdata    ),  // input wire [23 : 0] dinb
  .doutb   (deqhead_rdata_full)  // output wire [23 : 0] doutb
);

assign deqhead_rdata = deqhead_rdata_full[22:0];


wire [15:0] enqtail_rdata_full;
qtail_info qtail_info_inst (
  .clka    (clk              ),  // input wire clka
  .wea     (r_enqtail_wen    ),  // input wire [0 : 0] wea
  .addra   (r_enqtail_addr   ),  // input wire [4 : 0] addra
  .dina    (r_enqtail_wdata  ),  // input wire [15 : 0] dina
  .douta   (enqtail_rdata_full), // output wire [15 : 0] douta
  .clkb    (clk              ),  // input wire clkb
  .web     (deqtail_wen      ),  // input wire [0 : 0] web
  .addrb   (deqtail_addr     ),  // input wire [4 : 0] addrb
  .dinb    (deqtail_wdata    ),  // input wire [15 : 0] dinb
  .doutb   (deqtail_rdata    )   // output wire [15 : 0] doutb
);

assign enqtail_rdata = enqtail_rdata_full[11:0];

// qlen_info qlen_info_inst (
//   .clka    (clk              ),  // input wire clka
//   .wea     (r_enqlen_wen     ),  // input wire [0 : 0] wea
//   .addra   (r_enqlen_addr    ),  // input wire [4 : 0] addra
//   .dina    (r_enqlen_wdata   ),  // input wire [15 : 0] dina
//   .douta   (enqlen_rdata     ),  // output wire [15 : 0] douta
//   .clkb    (clk              ),  // input wire clkb
//   .web     (enqlen_wen       ),  // input wire [0 : 0] web
//   .addrb   (enqlen_addr      ),  // input wire [4 : 0] addrb
//   .dinb    (enqlen_wdata     ),  // input wire [15 : 0] dinb
//   .doutb   (enqlen_rdata     )   // output wire [15 : 0] doutb
// );

// qcnt_info qcnt_info_inst (
//   .clka    (clk              ),  // input wire clka
//   .wea     (r_enqcnt_wen     ),  // input wire [0 : 0] wea
//   .addra   (r_enqcnt_addr    ),  // input wire [4 : 0] addra
//   .dina    (r_enqcnt_wdata   ),  // input wire [15 : 0] dina
//   .douta   (enqcnt_rdata     ),  // output wire [15 : 0] douta
//   .clkb    (clk              ),  // input wire clkb
//   .web     (enqcnt_wen       ),  // input wire [0 : 0] web
//   .addrb   (enqcnt_addr      ),  // input wire [4 : 0] addrb
//   .dinb    (enqcnt_wdata     ),  // input wire [15 : 0] dinb
//   .doutb   (enqcnt_rdata     )   // output wire [15 : 0] doutb
// );
    
// `endif
endmodule
