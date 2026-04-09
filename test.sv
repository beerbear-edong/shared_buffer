`include "Stimulator.sv"
`timescale 1ns / 1ps

program automatic test();
    virtual pkt_if wr[4];
    Stimulator sti[4];

    localparam integer CASE_ID = 2;
    localparam integer CASE_QUEUE_OPS        = 1;
    localparam integer CASE_BUFFER_MGR       = 2;
    localparam integer CASE_SCHED_SP_WRR_RR  = 3;
    localparam integer CASE_THROUGHPUT       = 4;
    localparam integer CASE_DELAY_JITTER     = 5;
    localparam integer CASE_OVERLOAD_RECOVER = 6;
    localparam integer CASE_WRR_LAT_GUARD    = 7;

    localparam integer STARTUP_CYCLES   = 5000;
    localparam integer FILL_GAP_CYCLES  = 5;
    localparam integer FILL_MAX_ROUNDS  = 20000;
    localparam integer DRAIN_MAX_CYCLES = 500000;
    localparam integer STALL_CYCLES     = 4096;
    localparam [31:0] ALL_EMPTY         = 32'hffff_ffff;
    localparam [12:0] DRAIN_BUF_THRESH  = 13'd4090;
    localparam bit [2:0] HIGH_PRI_V    = 3'd7;
    localparam bit [2:0] LOW_PRI_V     = 3'd0;
    localparam integer LAT_DEPTH        = 4096;
    localparam integer LAT_BINS         = 256;
    localparam real    CLK_NS           = 3.2;
    localparam real    TH_GBPS          = 20.0;

    bit stats_en;
    bit lat_en;
    string case_name;
    longint unsigned sim_cycle;

    longint unsigned sample_cycles, tx_words, tx_pkts, enq_evt, deq_evt, drop_evt, alloc_evt, rls_evt;
    integer q_toggle[0:31];
    reg [31:0] q_prev;
    longint unsigned q_mismatch, deq_empty, head_col, tail_col;
    integer buf_init, buf_min, buf_max, buf_final;
    longint unsigned no_prog_run, no_prog_max, no_prog_win;
    longint unsigned rr_grant[0:3], sch_pri_cnt[0:7];
    longint unsigned sp_hi_miss, discard_enter;
    reg [3:0] bus_rx_cstate_prev;
    reg tx_en_prev;

    integer hi_ts[0:LAT_DEPTH-1], lo_ts[0:LAT_DEPTH-1];
    integer hi_h, hi_t, hi_n, lo_h, lo_t, lo_n;
    longint unsigned hi_cnt, hi_sum, lo_cnt, lo_sum, afull_cycles;
    integer hi_min, hi_max, lo_min, lo_max;
    integer hi_hist[0:LAT_BINS-1], lo_hist[0:LAT_BINS-1];

    function automatic [3:0] dst_of(input integer p);
        case (p)
            0: dst_of = 4'b0001;
            1: dst_of = 4'b0010;
            2: dst_of = 4'b0100;
            default: dst_of = 4'b1000;
        endcase
    endfunction

    function automatic real calc_gbps(input longint unsigned words, input longint unsigned cycles);
        real bits, tns;
        begin
            bits = words * 64.0;
            tns = cycles * CLK_NS;
            calc_gbps = (tns > 0.0) ? (bits / tns) : 0.0;
        end
    endfunction

    function automatic bit hi_pending();
        hi_pending = (~top_tb.rcv_top_inst.queue_empty[7]) |
                     (~top_tb.rcv_top_inst.queue_empty[15]) |
                     (~top_tb.rcv_top_inst.queue_empty[23]) |
                     (~top_tb.rcv_top_inst.queue_empty[31]);
    endfunction

    task automatic reset_stats();
        integer i;
        begin
            sample_cycles = 0; tx_words = 0; tx_pkts = 0; enq_evt = 0; deq_evt = 0; drop_evt = 0; alloc_evt = 0; rls_evt = 0;
            q_prev = top_tb.rcv_top_inst.queue_empty; q_mismatch = 0; deq_empty = 0; head_col = 0; tail_col = 0;
            for (i = 0; i < 32; i++) q_toggle[i] = 0;
            buf_init = top_tb.rcv_top_inst.buf_blk_cnt; buf_min = buf_init; buf_max = buf_init; buf_final = buf_init;
            no_prog_run = 0; no_prog_max = 0; no_prog_win = 0;
            for (i = 0; i < 4; i++) rr_grant[i] = 0;
            for (i = 0; i < 8; i++) sch_pri_cnt[i] = 0;
            sp_hi_miss = 0; discard_enter = 0; bus_rx_cstate_prev = top_tb.rcv_top_inst.bus_rx_inst.cstate;
            tx_en_prev = top_tb.tx_data_en; afull_cycles = 0;

            hi_h = 0; hi_t = 0; hi_n = 0; lo_h = 0; lo_t = 0; lo_n = 0;
            hi_cnt = 0; hi_sum = 0; lo_cnt = 0; lo_sum = 0;
            hi_min = 32'h7fff_ffff; hi_max = 0; lo_min = 32'h7fff_ffff; lo_max = 0;
            for (i = 0; i < LAT_BINS; i++) begin hi_hist[i] = 0; lo_hist[i] = 0; end
        end
    endtask

    task automatic start_case(input string n);
        begin
            case_name = n;
            reset_stats();
            stats_en = 1'b1;
            $display("[TEST] %t  %s begin", $time, case_name);
        end
    endtask

    task automatic end_case();
        begin
            stats_en = 1'b0;
            buf_final = top_tb.rcv_top_inst.buf_blk_cnt;
            $display("[OBS][%s] cycles=%0d enq=%0d deq=%0d tx_words=%0d tx_pkts=%0d drop=%0d", case_name, sample_cycles, enq_evt, deq_evt, tx_words, tx_pkts, drop_evt);
            $display("[TEST] %t  %s end", $time, case_name);
        end
    endtask

    task automatic setup_env();
        integer i;
        begin
            wr[0] = top_tb.wr[0]; wr[1] = top_tb.wr[1]; wr[2] = top_tb.wr[2]; wr[3] = top_tb.wr[3];
            for (i = 0; i < 4; i++) begin
                sti[i] = new($sformatf("sti%0d", i), i, wr[i]);
                sti[i].init_port();
            end
        end
    endtask

    task automatic set_wrr_default();
        begin
            top_tb.Weight[0] <= 8'd1; top_tb.Weight[1] <= 8'd2; top_tb.Weight[2] <= 8'd4; top_tb.Weight[3] <= 8'd8;
            top_tb.Weight[4] <= 8'd1; top_tb.Weight[5] <= 8'd2; top_tb.Weight[6] <= 8'd4; top_tb.Weight[7] <= 8'd8;
        end
    endtask

    task automatic set_wrr_hi_bias();
        begin
            top_tb.Weight[0] <= 8'd1; top_tb.Weight[1] <= 8'd1; top_tb.Weight[2] <= 8'd2; top_tb.Weight[3] <= 8'd8;
            top_tb.Weight[4] <= 8'd1; top_tb.Weight[5] <= 8'd1; top_tb.Weight[6] <= 8'd2; top_tb.Weight[7] <= 8'd8;
        end
    endtask

    task automatic send_random_round();
        integer i;
        begin
            for (i = 0; i < 4; i++) begin sti[i].gen_pkt(); sti[i].send_pkt(); end
        end
    endtask

    task automatic send_fixed_round(input bit [10:0] len_i, input bit [2:0] pri_i);
        integer i;
        begin
            for (i = 0; i < 4; i++) begin
                sti[i].gen_pkt_fixed_pri(pri_i, len_i, dst_of(i));
                sti[i].send_pkt();
            end
        end
    endtask

    task automatic send_mixed_round(input integer base);
        integer i;
        bit [2:0] pri_v;
        bit [10:0] len_v;
        begin
            for (i = 0; i < 4; i++) begin
                pri_v = (base + i) % 8;
                len_v = ((i % 2) == 1) ? 11'd1518 : 11'd64;
                sti[i].gen_pkt_fixed_pri(pri_v, len_v, dst_of(i));
                sti[i].send_pkt();
            end
        end
    endtask

    task automatic fill_until_afull(input integer max_rounds);
        integer r;
        begin
            r = 0;
            while (top_tb.afull == 1'b0 && r < max_rounds) begin
                repeat (FILL_GAP_CYCLES) @(posedge top_tb.clk);
                send_random_round();
                r++;
            end
        end
    endtask

    task automatic drain_until_idle(input integer max_cycles, output integer waited);
        begin
            waited = 0;
            while (((top_tb.rcv_top_inst.queue_empty != ALL_EMPTY) || (top_tb.rcv_top_inst.buf_blk_cnt < DRAIN_BUF_THRESH)) && waited < max_cycles) begin
                @(posedge top_tb.clk);
                waited++;
            end
        end
    endtask

    task automatic measure_tp(input string tag, input bit [10:0] len_i, input integer rounds);
        integer i, dcy;
        longint unsigned w0, w1, c0, c1;
        real gbps, util;
        begin
            w0 = tx_words; c0 = sample_cycles;
            for (i = 0; i < rounds; i++) send_fixed_round(len_i, 3'd3);
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            w1 = tx_words; c1 = sample_cycles;
            gbps = calc_gbps(w1 - w0, c1 - c0);
            util = (TH_GBPS > 0.0) ? (gbps / TH_GBPS) * 100.0 : 0.0;
            $display("[OBS][%s] %s throughput_gbps=%0.3f utilization_pct=%0.2f", case_name, tag, gbps, util);
        end
    endtask

    task automatic run_case_queue_ops();
        integer i, dcy, toggles;
        begin
            start_case("CASE1_QUEUE_OPS");
            top_tb.sch_mode <= 1'b0; repeat (10) @(posedge top_tb.clk);
            fill_until_afull(FILL_MAX_ROUNDS);
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            toggles = 0; for (i = 0; i < 32; i++) toggles += q_toggle[i];
            $display("[OBS][%s] head_collision=%0d tail_collision=%0d", case_name, head_col, tail_col);
            $display("[OBS][%s] q_toggle=%0d q_mismatch=%0d deq_from_empty=%0d drain_cycles=%0d", case_name, toggles, q_mismatch, deq_empty, dcy);
            end_case();
        end
    endtask

    task automatic run_case_buffer_mgr();
        integer i, dcy;
        begin
            start_case("CASE2_BUFFER_MGR");
            top_tb.sch_mode <= 1'b0; repeat (10) @(posedge top_tb.clk);
            for (i = 0; i < 3; i++) begin fill_until_afull(FILL_MAX_ROUNDS / 2); drain_until_idle(DRAIN_MAX_CYCLES, dcy); end
            $display("[OBS][%s] alloc=%0d release=%0d net=%0d", case_name, alloc_evt, rls_evt, (alloc_evt >= rls_evt) ? (alloc_evt - rls_evt) : (rls_evt - alloc_evt));
            $display("[OBS][%s] buf_blk_cnt init=%0d min=%0d max=%0d final=%0d", case_name, buf_init, buf_min, buf_max, buf_final);
            $display("[OBS][%s] no_progress_windows=%0d max_no_progress=%0d", case_name, no_prog_win, no_prog_max);
            end_case();
        end
    endtask

    task automatic run_case_sched_sp_wrr_rr();
        integer i, dcy;
        begin
            start_case("CASE3_SCHED_SP_WRR_RR");
            top_tb.sch_mode <= 1'b0; repeat (10) @(posedge top_tb.clk);
            for (i = 0; i < 120; i++) send_random_round();
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            $display("[OBS][%s] RR grant p0=%0d p1=%0d p2=%0d p3=%0d", case_name, rr_grant[0], rr_grant[1], rr_grant[2], rr_grant[3]);

            top_tb.sch_mode <= 1'b0; repeat (10) @(posedge top_tb.clk);
            for (i = 0; i < 160; i++) send_mixed_round(i);
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            $display("[OBS][%s] SP service pri7=%0d pri0=%0d hi_pending_miss=%0d", case_name, sch_pri_cnt[7], sch_pri_cnt[0], sp_hi_miss);

            set_wrr_default(); top_tb.sch_mode <= 1'b1; repeat (10) @(posedge top_tb.clk);
            for (i = 0; i < 220; i++) send_mixed_round(i + 3);
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            for (i = 0; i < 8; i++) $display("[OBS][%s] WRR pri%0d service=%0d", case_name, i, sch_pri_cnt[i]);
            end_case();
        end
    endtask

    task automatic run_case_throughput();
        integer dcy;
        begin
            start_case("CASE4_THROUGHPUT");
            set_wrr_default(); top_tb.sch_mode <= 1'b1; repeat (10) @(posedge top_tb.clk);
            measure_tp("short_64B", 11'd64, 400);
            measure_tp("long_1518B", 11'd1518, 200);
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            end_case();
        end
    endtask

    task automatic run_case_delay_jitter();
        integer i, p, dcy;
        begin
            start_case("CASE5_DELAY_JITTER");
            top_tb.sch_mode <= 1'b0; repeat (10) @(posedge top_tb.clk);
            lat_en = 1'b1;
            for (i = 0; i < 220; i++) begin
                sti[0].gen_pkt_fixed_pri(3'd7, 11'd88, dst_of(0)); sti[0].send_pkt();
                for (p = 1; p < 4; p++) begin sti[p].gen_pkt_fixed_pri(3'd0, 11'd1518, dst_of(p)); sti[p].send_pkt(); end
            end
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            lat_en = 1'b0;
            $display("[OBS][%s] high_latency samples=%0d min=%0d max=%0d avg=%0.2f jitter=%0d", case_name, hi_cnt, (hi_cnt > 0) ? hi_min : 0, (hi_cnt > 0) ? hi_max : 0, (hi_cnt > 0) ? (1.0 * hi_sum / hi_cnt) : 0.0, (hi_cnt > 0) ? (hi_max - hi_min) : 0);
            $display("[OBS][%s] afull_cycles=%0d drain_cycles=%0d", case_name, afull_cycles, dcy);
            end_case();
        end
    endtask

    task automatic run_case_overload_recover();
        integer i, dcy;
        longint unsigned d0, d1, stable_anom;
        begin
            start_case("CASE6_OVERLOAD_RECOVER");
            set_wrr_default(); top_tb.sch_mode <= 1'b1; repeat (10) @(posedge top_tb.clk);
            d0 = drop_evt;
            for (i = 0; i < 800 && (drop_evt - d0) < 64; i++) send_fixed_round(11'd1518, 3'd0);
            d1 = drop_evt;
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            stable_anom = 0;
            for (i = 0; i < 20000; i++) begin @(posedge top_tb.clk); if (top_tb.afull || drop_evt > d1) stable_anom++; end
            $display("[OBS][%s] drop_cnt=%0d discard_enter=%0d recover_cycles=%0d stable_anomaly=%0d", case_name, d1 - d0, discard_enter, dcy, stable_anom);
            end_case();
        end
    endtask

    task automatic run_case_wrr_latency_guard();
        integer i, p, dcy;
        real hi_avg, lo_avg;
        bit [2:0] pri_v;
        begin
            start_case("CASE7_WRR_LAT_GUARD");
            set_wrr_hi_bias(); top_tb.sch_mode <= 1'b1; repeat (10) @(posedge top_tb.clk);
            lat_en = 1'b1;
            for (i = 0; i < 320; i++) begin
                for (p = 0; p < 4; p++) begin
                    pri_v = (i + p) % 8;
                    sti[p].gen_pkt_fixed_pri(pri_v, 11'd88, dst_of(p));
                    sti[p].send_pkt();
                end
            end
            drain_until_idle(DRAIN_MAX_CYCLES, dcy);
            lat_en = 1'b0;
            hi_avg = (hi_cnt > 0) ? (1.0 * hi_sum / hi_cnt) : 0.0;
            lo_avg = (lo_cnt > 0) ? (1.0 * lo_sum / lo_cnt) : 0.0;
            for (i = 0; i < 8; i++) $display("[OBS][%s] WRR pri%0d service=%0d", case_name, i, sch_pri_cnt[i]);
            $display("[OBS][%s] high_avg_latency=%0.2f low_avg_latency=%0.2f drain_cycles=%0d", case_name, hi_avg, lo_avg, dcy);
            end_case();
        end
    endtask

    initial begin : stats_thread
        integer q, lat, bin;
        bit alloc_p, rls_p, progress;
        forever begin
            @(posedge top_tb.clk or negedge top_tb.rst_n);
            if (~top_tb.rst_n) begin
                sim_cycle <= 0; tx_en_prev <= 1'b0; bus_rx_cstate_prev <= 0;
            end
            else begin
                sim_cycle <= sim_cycle + 1;
                if (stats_en) begin
                    sample_cycles <= sample_cycles + 1;
                    alloc_p = top_tb.rcv_top_inst.buf_mgr_inst.buf_blk_rd_en;
                    rls_p = top_tb.rcv_top_inst.bus_tx_inst.rls_buf_blk_en;
                    progress = alloc_p || rls_p;

                    if (top_tb.tx_data_en) tx_words <= tx_words + 1;
                    if (top_tb.tx_data_en && !tx_en_prev) tx_pkts <= tx_pkts + 1;
                    if (top_tb.rcv_top_inst.bus_rx_inst.enq_en) enq_evt <= enq_evt + 1;
                    if (top_tb.rcv_top_inst.bus_tx_inst.deq_en) deq_evt <= deq_evt + 1;
                    if (top_tb.rcv_top_inst.bus_rx_inst.pkt_info_en && !top_tb.rcv_top_inst.bus_rx_inst.buf_req) drop_evt <= drop_evt + 1;
                    if (alloc_p) alloc_evt <= alloc_evt + 1;
                    if (rls_p) rls_evt <= rls_evt + 1;
                    if (top_tb.afull) afull_cycles <= afull_cycles + 1;
                    if (top_tb.rcv_top_inst.bus_rx_inst.cstate == 4'b0010 && bus_rx_cstate_prev != 4'b0010) discard_enter <= discard_enter + 1;

                    if (top_tb.rcv_top_inst.queue_mgr_inst.r_enqhead_wen && top_tb.rcv_top_inst.bus_tx_inst.deqhead_wen && top_tb.rcv_top_inst.queue_mgr_inst.r_enqhead_addr == top_tb.rcv_top_inst.bus_tx_inst.deqhead_addr) head_col <= head_col + 1;
                    if (top_tb.rcv_top_inst.queue_mgr_inst.r_enqtail_wen && top_tb.rcv_top_inst.bus_tx_inst.deqtail_wen && top_tb.rcv_top_inst.queue_mgr_inst.r_enqtail_addr == top_tb.rcv_top_inst.bus_tx_inst.deqtail_addr) tail_col <= tail_col + 1;
                    if (top_tb.rcv_top_inst.bus_tx_inst.deq_en && top_tb.rcv_top_inst.queue_empty[top_tb.rcv_top_inst.bus_tx_inst.deq_addr]) deq_empty <= deq_empty + 1;

                    if (top_tb.rcv_top_inst.rx_polling_inst.n_state) begin
                        case (top_tb.rcv_top_inst.rx_polling_inst.grant)
                            4'b0001: rr_grant[0] <= rr_grant[0] + 1;
                            4'b0010: rr_grant[1] <= rr_grant[1] + 1;
                            4'b0100: rr_grant[2] <= rr_grant[2] + 1;
                            4'b1000: rr_grant[3] <= rr_grant[3] + 1;
                            default: begin end
                        endcase
                    end

                    if (top_tb.rcv_top_inst.arbiter_inst.sch_en) begin
                        sch_pri_cnt[top_tb.rcv_top_inst.arbiter_inst.sch_id[2:0]] <= sch_pri_cnt[top_tb.rcv_top_inst.arbiter_inst.sch_id[2:0]] + 1;
                        if (!top_tb.sch_mode && hi_pending() && top_tb.rcv_top_inst.arbiter_inst.sch_id[2:0] != HIGH_PRI_V) sp_hi_miss <= sp_hi_miss + 1;
                    end

                    for (q = 0; q < 32; q++) begin
                        if (top_tb.rcv_top_inst.queue_empty[q] != q_prev[q]) q_toggle[q] <= q_toggle[q] + 1;
                        if (top_tb.rcv_top_inst.queue_empty[q] != (top_tb.rcv_top_inst.queue_mgr_inst.inq_cnt_reg[q] == 0)) q_mismatch <= q_mismatch + 1;
                    end
                    q_prev <= top_tb.rcv_top_inst.queue_empty;

                    if (top_tb.rcv_top_inst.buf_blk_cnt < buf_min) buf_min <= top_tb.rcv_top_inst.buf_blk_cnt;
                    if (top_tb.rcv_top_inst.buf_blk_cnt > buf_max) buf_max <= top_tb.rcv_top_inst.buf_blk_cnt;
                    if (progress) begin if (no_prog_run > no_prog_max) no_prog_max <= no_prog_run; no_prog_run <= 0; end
                    else if (top_tb.rcv_top_inst.queue_empty != ALL_EMPTY) begin no_prog_run <= no_prog_run + 1; if (no_prog_run == STALL_CYCLES) no_prog_win <= no_prog_win + 1; end

                    if (lat_en) begin
                        if (top_tb.wr[0].vld && top_tb.wr[0].sop) begin
                            if (top_tb.wr[0].data[6:4] == HIGH_PRI_V && hi_n < LAT_DEPTH) begin hi_ts[hi_t] <= sim_cycle; hi_t <= (hi_t + 1) % LAT_DEPTH; hi_n <= hi_n + 1; end
                            if (top_tb.wr[0].data[6:4] == LOW_PRI_V  && lo_n < LAT_DEPTH) begin lo_ts[lo_t] <= sim_cycle; lo_t <= (lo_t + 1) % LAT_DEPTH; lo_n <= lo_n + 1; end
                        end
                        if (top_tb.wr[1].vld && top_tb.wr[1].sop) begin
                            if (top_tb.wr[1].data[6:4] == HIGH_PRI_V && hi_n < LAT_DEPTH) begin hi_ts[hi_t] <= sim_cycle; hi_t <= (hi_t + 1) % LAT_DEPTH; hi_n <= hi_n + 1; end
                            if (top_tb.wr[1].data[6:4] == LOW_PRI_V  && lo_n < LAT_DEPTH) begin lo_ts[lo_t] <= sim_cycle; lo_t <= (lo_t + 1) % LAT_DEPTH; lo_n <= lo_n + 1; end
                        end
                        if (top_tb.wr[2].vld && top_tb.wr[2].sop) begin
                            if (top_tb.wr[2].data[6:4] == HIGH_PRI_V && hi_n < LAT_DEPTH) begin hi_ts[hi_t] <= sim_cycle; hi_t <= (hi_t + 1) % LAT_DEPTH; hi_n <= hi_n + 1; end
                            if (top_tb.wr[2].data[6:4] == LOW_PRI_V  && lo_n < LAT_DEPTH) begin lo_ts[lo_t] <= sim_cycle; lo_t <= (lo_t + 1) % LAT_DEPTH; lo_n <= lo_n + 1; end
                        end
                        if (top_tb.wr[3].vld && top_tb.wr[3].sop) begin
                            if (top_tb.wr[3].data[6:4] == HIGH_PRI_V && hi_n < LAT_DEPTH) begin hi_ts[hi_t] <= sim_cycle; hi_t <= (hi_t + 1) % LAT_DEPTH; hi_n <= hi_n + 1; end
                            if (top_tb.wr[3].data[6:4] == LOW_PRI_V  && lo_n < LAT_DEPTH) begin lo_ts[lo_t] <= sim_cycle; lo_t <= (lo_t + 1) % LAT_DEPTH; lo_n <= lo_n + 1; end
                        end
                        if (top_tb.tx_data_en && !tx_en_prev) begin
                            if (top_tb.rcv_top_inst.bus_tx_inst.sch_id[2:0] == HIGH_PRI_V && hi_n > 0) begin
                                lat = sim_cycle - hi_ts[hi_h]; hi_h <= (hi_h + 1) % LAT_DEPTH; hi_n <= hi_n - 1; hi_cnt <= hi_cnt + 1; hi_sum <= hi_sum + lat; if (lat < hi_min) hi_min <= lat; if (lat > hi_max) hi_max <= lat; bin = (lat >= LAT_BINS) ? (LAT_BINS - 1) : lat; hi_hist[bin] <= hi_hist[bin] + 1;
                            end
                            if (top_tb.rcv_top_inst.bus_tx_inst.sch_id[2:0] == LOW_PRI_V && lo_n > 0) begin
                                lat = sim_cycle - lo_ts[lo_h]; lo_h <= (lo_h + 1) % LAT_DEPTH; lo_n <= lo_n - 1; lo_cnt <= lo_cnt + 1; lo_sum <= lo_sum + lat; if (lat < lo_min) lo_min <= lat; if (lat > lo_max) lo_max <= lat; bin = (lat >= LAT_BINS) ? (LAT_BINS - 1) : lat; lo_hist[bin] <= lo_hist[bin] + 1;
                            end
                        end
                    end
                end
                tx_en_prev <= top_tb.tx_data_en;
                bus_rx_cstate_prev <= top_tb.rcv_top_inst.bus_rx_inst.cstate;
            end
        end
    end

    initial begin
        integer dcy;
        stats_en = 1'b0; lat_en = 1'b0; sim_cycle = 0;
        setup_env();
        repeat (STARTUP_CYCLES) @(posedge top_tb.clk);
        drain_until_idle(DRAIN_MAX_CYCLES, dcy);

        case (CASE_ID)
            CASE_QUEUE_OPS:        run_case_queue_ops();
            CASE_BUFFER_MGR:       run_case_buffer_mgr();
            CASE_SCHED_SP_WRR_RR:  run_case_sched_sp_wrr_rr();
            CASE_THROUGHPUT:       run_case_throughput();
            CASE_DELAY_JITTER:     run_case_delay_jitter();
            CASE_OVERLOAD_RECOVER: run_case_overload_recover();
            CASE_WRR_LAT_GUARD:    run_case_wrr_latency_guard();
            default:               run_case_queue_ops();
        endcase

        top_tb.fin <= 1'b1;
        repeat (20) @(posedge top_tb.clk);
        $finish;
    end
endprogram
