`include "Stimulator.sv"
// `include "Monitor.sv"  // Monitor is already in the Vivado sim fileset
`timescale 1ns / 1ps
program automatic test();
    virtual pkt_if wr[4];
    Stimulator sti[4];
    integer timeout_cnt;  // 超时计数器，防止 while 死循环

    initial begin
        integer i;
        wr[0] = top_tb.wr[0];
        wr[1] = top_tb.wr[1];
        wr[2] = top_tb.wr[2];
        wr[3] = top_tb.wr[3];
        for(i = 0; i < 4; i++) begin
            sti[i] = new($sformatf("sti%d", i) , i, wr[i]);
        end
        // 立即初始化所有端口，防止 x 传播到 DUT
        for(i = 0; i < 4; i++) begin
            sti[i].init_port_blocking();
        end
        // 等待 buf_mgr 空闲块 FIFO 初始化完成 (需要 4096+ 周期)
        repeat(5000) @(posedge top_tb.clk);

        // ============================================================
        //  SP (Strict Priority) 测试  —— sch_mode = 0
        // ============================================================
        $display("============================================");
        $display("[TEST] %t  SP test begin", $time);
        $display("============================================");
        // 多端口同时灌包直到 buffer almost full
        repeat(50) @(posedge top_tb.clk);
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < 500) begin
          repeat(5) @(posedge top_tb.clk);
          for(i = 0; i < 4; i++) begin
            sti[i].gen_pkt();
            sti[i].send_pkt();
          end
          timeout_cnt++;
        end
        if (timeout_cnt >= 500)
            $display("[WARN] %t  SP fill loop 1 timed out, afull=%b", $time, top_tb.afull);
        // Wait for scheduler to drain some packets
        repeat(500) @(posedge top_tb.clk);
        // Send more packets until almost full again
        repeat(100) @(posedge top_tb.clk);
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < 500) begin
          repeat(5) @(posedge top_tb.clk);
          for(i = 0; i < 4; i++) begin
            sti[i].gen_pkt();
            sti[i].send_pkt();
          end
          timeout_cnt++;
        end
        if (timeout_cnt >= 500)
            $display("[WARN] %t  SP fill loop 2 timed out, afull=%b", $time, top_tb.afull);
        repeat(1000) @(posedge top_tb.clk);
        $display("============================================");
        $display("[TEST] %t  SP test end", $time);
        $display("============================================");

        // ============================================================
        //  WRR (Weighted Round Robin) 测试  —— sch_mode = 1
        // ============================================================

        // 等全部队列排空，再切换到 WRR 模式
        repeat(2000) @(posedge top_tb.clk);

        // 配置 WRR 权重：pri 0‑7 分别配置不同权重
        top_tb.Weight[0] <= 8'd1;
        top_tb.Weight[1] <= 8'd2;
        top_tb.Weight[2] <= 8'd4;
        top_tb.Weight[3] <= 8'd8;
        top_tb.Weight[4] <= 8'd1;
        top_tb.Weight[5] <= 8'd2;
        top_tb.Weight[6] <= 8'd4;
        top_tb.Weight[7] <= 8'd8;
        // 切换调度模式
        top_tb.sch_mode  <= 1'b1;
        repeat(10) @(posedge top_tb.clk);

        $display("============================================");
        $display("[TEST] %t  WRR test begin  (Weight = 1,2,4,8,1,2,4,8)", $time);
        $display("============================================");

        // —— WRR 场景 1：多端口同时注入，观察 WRR 调度公平性
        //    port 0‑3 各发若干包，让调度器按权重轮转输出
        for(i = 0; i < 4; i++) begin
            sti[i].gen_pkt();
            sti[i].send_pkt();
        end
        repeat(200) @(posedge top_tb.clk);

        // —— WRR 场景 2：持续从多端口灌包直到 afull
        repeat(50) @(posedge top_tb.clk);
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < 500) begin
            repeat(5) @(posedge top_tb.clk);
            for(i = 0; i < 4; i++) begin
                sti[i].gen_pkt();
                sti[i].send_pkt();
            end
            timeout_cnt++;
        end
        if (timeout_cnt >= 500)
            $display("[WARN] %t  WRR fill loop 2 timed out, afull=%b", $time, top_tb.afull);

        // 等待调度器排空部分报文
        repeat(500) @(posedge top_tb.clk);

        // —— WRR 场景 3：再次灌包验证权重累加与轮转
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < 500) begin
            repeat(5) @(posedge top_tb.clk);
            for(i = 0; i < 4; i++) begin
                sti[i].gen_pkt();
                sti[i].send_pkt();
            end
            timeout_cnt++;
        end
        if (timeout_cnt >= 500)
            $display("[WARN] %t  WRR fill loop 3 timed out, afull=%b", $time, top_tb.afull);

        repeat(2000) @(posedge top_tb.clk);
        $display("============================================");
        $display("[TEST] %t  WRR test end", $time);
        $display("============================================");

        top_tb.fin <= 1'b1;
        repeat(10) @(posedge top_tb.clk);
        $finish;
    end

endprogram
