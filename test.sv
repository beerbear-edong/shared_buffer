`include "Stimulator.sv"
// `include "Monitor.sv"  // Monitor is already in the Vivado sim fileset
`timescale 1ns / 1ps
program automatic test();
    virtual pkt_if wr[4];
    Stimulator sti[4];
    integer timeout_cnt;  // 超时计数器，防止 while 死循环
    parameter TIMEOUT = 1000;

    initial begin
        integer i;
        integer drain_wait_cnt;
        wr[0] = top_tb.wr[0];
        wr[1] = top_tb.wr[1];
        wr[2] = top_tb.wr[2];
        wr[3] = top_tb.wr[3];
        for(i = 0; i < 4; i++) begin
            sti[i] = new($sformatf("sti%d", i) , i, wr[i]);
        end
        
        for(i = 0; i < 4; i++) begin
            sti[i].init_port;
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
        while (top_tb.afull == 1'b0 && timeout_cnt < TIMEOUT) begin
          repeat(5) @(posedge top_tb.clk);
          for(i = 0; i < 4; i++) begin
            sti[i].gen_pkt();
            sti[i].send_pkt();
          end
          timeout_cnt++;
        end
        if (timeout_cnt >= TIMEOUT)
            $display("[WARN] %t  SP fill loop 1 timed out, afull=%b", $time, top_tb.afull);
        // Wait for scheduler to drain some packets
        repeat(500) @(posedge top_tb.clk);
        // Send more packets until almost full again
        repeat(100) @(posedge top_tb.clk);
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < TIMEOUT) begin
          repeat(5) @(posedge top_tb.clk);
          for(i = 0; i < 4; i++) begin
            sti[i].gen_pkt();
            sti[i].send_pkt();
          end
          timeout_cnt++;
        end
        if (timeout_cnt >= TIMEOUT)
            $display("[WARN] %t  SP fill loop 2 timed out, afull=%b", $time, top_tb.afull);
        repeat(1000) @(posedge top_tb.clk);
        $display("============================================");
        $display("[TEST] %t  SP test end", $time);
        $display("============================================");

        // ============================================================
        //  WRR (Weighted Round Robin) 测试  —— sch_mode = 1
        // ============================================================

        // 等队列尽量排空后再切 WRR；避免固定2000拍不够导致WRR阶段过短
        drain_wait_cnt = 0;
        while ((top_tb.rcv_top_inst.queue_empty != 32'hffff_ffff || top_tb.rcv_top_inst.buf_blk_cnt < 13'd4090)
               && drain_wait_cnt < (TIMEOUT * 20)) begin
            @(posedge top_tb.clk);
            drain_wait_cnt++;
        end
        if (drain_wait_cnt >= (TIMEOUT * 20))
            $display("[WARN] %t  pre-WRR drain timed out: queue_empty=%h, buf_blk_cnt=%0d, afull=%b",
                     $time, top_tb.rcv_top_inst.queue_empty, top_tb.rcv_top_inst.buf_blk_cnt, top_tb.afull);
        else
            $display("[INFO] %t  pre-WRR drain done in %0d cycles: queue_empty=%h, buf_blk_cnt=%0d, afull=%b",
                     $time, drain_wait_cnt, top_tb.rcv_top_inst.queue_empty, top_tb.rcv_top_inst.buf_blk_cnt, top_tb.afull);

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
        $display("[INFO] %t  WRR begin snapshot: afull=%b, buf_blk_cnt=%0d, queue_empty=%h",
             $time, top_tb.afull, top_tb.rcv_top_inst.buf_blk_cnt, top_tb.rcv_top_inst.queue_empty);
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
        while (top_tb.afull == 1'b0 && timeout_cnt < TIMEOUT) begin
            repeat(5) @(posedge top_tb.clk);
            for(i = 0; i < 4; i++) begin
                sti[i].gen_pkt();
                sti[i].send_pkt();
            end
            timeout_cnt++;
        end
        $display("[INFO] %t  WRR fill loop 2 finished: iter=%0d, afull=%b, buf_blk_cnt=%0d, queue_empty=%h",
                 $time, timeout_cnt, top_tb.afull, top_tb.rcv_top_inst.buf_blk_cnt, top_tb.rcv_top_inst.queue_empty);
        if (timeout_cnt >= TIMEOUT)
            $display("[WARN] %t  WRR fill loop 2 timed out, afull=%b", $time, top_tb.afull);

        // 等待调度器排空部分报文
        repeat(TIMEOUT) @(posedge top_tb.clk);

        // —— WRR 场景 3：再次灌包验证权重累加与轮转
        timeout_cnt = 0;
        while (top_tb.afull == 1'b0 && timeout_cnt < TIMEOUT) begin
            repeat(5) @(posedge top_tb.clk);
            for(i = 0; i < 4; i++) begin
                sti[i].gen_pkt();
                sti[i].send_pkt();
            end
            timeout_cnt++;
        end
        $display("[INFO] %t  WRR fill loop 3 finished: iter=%0d, afull=%b, buf_blk_cnt=%0d, queue_empty=%h",
                 $time, timeout_cnt, top_tb.afull, top_tb.rcv_top_inst.buf_blk_cnt, top_tb.rcv_top_inst.queue_empty);
        if (timeout_cnt >= TIMEOUT)
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
