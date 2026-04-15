`include "Stimulator.sv"
// `include "Monitor.sv"  // Monitor is already in the Vivado sim fileset
`timescale 1ns / 1ps

program automatic test();
    virtual pkt_if wr[4];
    Stimulator sti[4];

    localparam integer FILL_GAP_CYCLES = 5;
    localparam integer FILL_MAX_ROUNDS = 20000;
    localparam integer DRAIN_MAX_CYCLES = 500000;
    localparam [31:0] ALL_QUEUE_EMPTY = 32'hffff_ffff;
    localparam [12:0] DRAIN_BUF_THRESH = 13'd4090;

    task automatic send_random_round();
        integer i;
        begin
            for (i = 0; i < 4; i++) begin
                sti[i].gen_pkt();
                sti[i].send_pkt();
            end
        end
    endtask

    task automatic fill_until_afull(input integer max_rounds);
        integer round_cnt;
        begin
            round_cnt = 0;
            while (top_tb.afull == 1'b0 && round_cnt < max_rounds) begin
                repeat(FILL_GAP_CYCLES) @(posedge top_tb.clk);
                send_random_round();
                round_cnt++;
            end
        end
    endtask

    task automatic drain_until_idle(input integer max_cycles);
        integer cycle_cnt;
        begin
            cycle_cnt = 0;
            while (((top_tb.rcv_top_inst.queue_empty != ALL_QUEUE_EMPTY) ||
                    (top_tb.rcv_top_inst.buf_blk_cnt < DRAIN_BUF_THRESH)) &&
                   cycle_cnt < max_cycles) begin
                @(posedge top_tb.clk);
                cycle_cnt++;
            end
        end
    endtask

    task automatic run_one_mode(input string mode_name);
        begin
            $display("[TEST] %t  %s test begin", $time, mode_name);
            fill_until_afull(FILL_MAX_ROUNDS);
            drain_until_idle(DRAIN_MAX_CYCLES);
            $display("[TEST] %t  %s test end", $time, mode_name);
        end
    endtask

    initial begin
        integer i;
        wr[0] = top_tb.wr[0];
        wr[1] = top_tb.wr[1];
        wr[2] = top_tb.wr[2];
        wr[3] = top_tb.wr[3];

        for (i = 0; i < 4; i++) begin
            sti[i] = new($sformatf("sti%0d", i), i, wr[i]);
            sti[i].init_port;
        end

        // Wait for buffer initialization and steady state.
        repeat(5000) @(posedge top_tb.clk);

        top_tb.sch_mode <= 1'b0;
        repeat(10) @(posedge top_tb.clk);
        run_one_mode("SP");

        top_tb.Weight[0] <= 8'd1;
        top_tb.Weight[1] <= 8'd2;
        top_tb.Weight[2] <= 8'd4;
        top_tb.Weight[3] <= 8'd8;
        top_tb.Weight[4] <= 8'd1;
        top_tb.Weight[5] <= 8'd2;
        top_tb.Weight[6] <= 8'd4;
        top_tb.Weight[7] <= 8'd8;
        top_tb.sch_mode  <= 1'b1;
        repeat(10) @(posedge top_tb.clk);
        run_one_mode("WRR");

        top_tb.fin <= 1'b1;
        repeat(10) @(posedge top_tb.clk);
        $finish;
    end

endprogram
