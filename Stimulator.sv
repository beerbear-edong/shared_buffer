`ifndef STIMULATOR_SV
`define STIMULATOR_SV
class Stimulator;
    string name;
    int id;
    virtual pkt_if.pkt_out wr;
    // 用于产生随机帧
    bit[63:0] pkt_data[];
    rand bit[10:0] pkt_len;
    rand bit[7:0]  content;
    rand bit[23:0] mark;
    rand bit[2:0]  pri;
    rand bit[3:0]  dst_port;
    constraint pkt_c{
        pkt_len >= 11'd64;
        pkt_len <= 11'd1024;
        pkt_len % 8 == 0;
        pkt_len % 64 != 8;
        pkt_len % 64 != 16;
        //pkt_len % 64 == 24;
    };
    function new(string _name, int _id, virtual pkt_if.pkt_out _wr);
        this.name = _name;
        this.id   = _id;
        this.wr   = _wr;
    endfunction
    virtual task automatic init_port();
        wr.data <= 64'h0000_0000_0000_0000;
        wr.sop  <= 1'b0;
        wr.eop  <= 1'b0;
        wr.vld  <= 1'b0;
    endtask
    virtual task automatic pkt_show();
        for(int i = 0; i < pkt_len / 8; i+=1) begin
            $display("%h", pkt_data[i]);
        end
    endtask
    virtual task automatic gen_pkt();// 生成随机帧，内容为递增的计数器
        bit[7:0]  cnt = 8'b0;
        assert(this.randomize());
        this.pkt_data = new[pkt_len / 8];
        this.pkt_data[0] = {46'b0, pkt_len, pri, dst_port};
        for(int i = 1; i < pkt_len / 8; i+=1) begin
            this.pkt_data[i] = {{4{content}}, mark, cnt};
            cnt += 8'b1;
        end
        $display("[TRACE]%t Generated packet:",$time);
        pkt_show();
    endtask
    task automatic send_pkt();
        init_port();
        @(posedge top_tb.clk);
        wr.sop <= 1'b1;
        for(int i = 0; i < pkt_len / 8; i+=1) begin
            @(posedge top_tb.clk);
            wr.sop  <= 1'b0;
            wr.eop  <= 1'b0;
            wr.vld  <= 1'b1;
            wr.data <= pkt_data[i];
        end
        @(posedge top_tb.clk);
        wr.vld  <= 1'b0;
        wr.data <= 64'b0;
        wr.sop  <= 1'b0;
        wr.eop  <= 1'b1;
        @(posedge top_tb.clk);
        init_port();
    endtask
endclass
`endif
