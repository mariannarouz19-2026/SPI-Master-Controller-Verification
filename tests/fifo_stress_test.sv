`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

`include "ref_model.sv"
`include "coverage.sv"
`include "stim_lib.sv"

`ifndef FIFO_APB_ADDRS
`define FIFO_APB_ADDRS
localparam [7:0] APB_CTRL     = 8'h00;
localparam [7:0] APB_STATUS   = 8'h04;
localparam [7:0] APB_TX_DATA  = 8'h08;
localparam [7:0] APB_RX_DATA  = 8'h0C;
localparam [7:0] APB_CLK_DIV  = 8'h10;
localparam [7:0] APB_SS_CTRL  = 8'h14;
localparam [7:0] APB_INT_EN   = 8'h18;
localparam [7:0] APB_INT_STAT = 8'h1C;
localparam [7:0] APB_DELAY    = 8'h20;
`endif

class fifo_stress_test;

    static function bit [3:0] to4(input int unsigned v);
        return v[3:0];
    endfunction


    static task apb_write_rm(ref spi_ref_model ref_model,
                             input bit [7:0]     addr,
                             input bit [31:0]    data);
        tb_top.u_apb_bfm.apb_write(addr, data);
        ref_model.predict_apb_write(addr, data);
    endtask


    static task apb_read_dut(input  bit [7:0]  addr,
                             output bit [31:0] data);
        tb_top.u_apb_bfm.apb_read(addr, data);
    endtask


    static task check_rx_front(ref spi_ref_model ref_model,
                               input bit [31:0]    observed,
                               input string        tag);
        bit [31:0] expected;

        expected = ref_model.predict_apb_read(APB_RX_DATA);

        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: %s RX mismatch: expected=0x%08h observed=0x%08h",
                     tag, expected, observed);
            ref_model.error_count++;
        end

        ref_model.predict_rx_pop();
    endtask


    static task model_one_transfer(ref spi_ref_model ref_model,
                                   input bit [31:0]    miso_word,
                                   input bit           loopback);
        ref_model.predict_tx_pop();

        ref_model.predict_transfer(
            .tx_data      (ref_model.pred_tx_word),
            .miso_pattern(miso_word),
            .loopback    (loopback)
        );

        ref_model.predict_transfer_complete(ref_model.pred_rx_word);
    endtask


    static task wait_done(input  int unsigned max_polls,
                          output bit          timeout,
                          output bit [31:0]   status);

        timeout = 1'b1;

        repeat (max_polls) begin
            tb_top.u_apb_bfm.apb_read(APB_STATUS, status);

            // STATUS[0] = BUSY
            // STATUS[2] = TX_EMPTY
            if ((status[0] == 1'b0) && (status[2] == 1'b1)) begin
                timeout = 1'b0;
                break;
            end
        end

    endtask


    // run: called by tb_top
    static task run(ref spi_ref_model    ref_model,
                    ref spi_coverage_col coverage);

        fifo_stress_txn t;
        bit [31:0]      rd;
        bit [31:0]      ctrl_word;
        int             seed;
        bit             timeout;

        $display("[INFO] fifo_stress_test: starting");

        t = new();
        ref_model.reset();

        if ($value$plusargs("SEED=%d", seed)) begin
            t.srandom(seed);
            $display("[INFO] fifo_stress_test: using SEED=%0d", seed);
        end


        tb_top.bfm_mode      = 2'b00;          // Mode 0
        tb_top.bfm_pattern   = 32'hA5A5A5A5;  // MISO pattern; ignored in loopback
        tb_top.bfm_width     = 2'b00;          // 8-bit
        tb_top.bfm_lsb_first = 1'b0;           // MSB-first

  
        ctrl_word      = 32'h0;
        ctrl_word[0]   = 1'b1;   // EN
        ctrl_word[1]   = 1'b1;   // MSTR
        ctrl_word[3:2] = 2'b00;  // Mode 0
        ctrl_word[4]   = 1'b0;   // MSB-first
        ctrl_word[5]   = 1'b1;   // Loopback ON
        ctrl_word[7:6] = 2'b00;  // 8-bit

        apb_write_rm(ref_model, APB_CTRL,     ctrl_word);
        apb_write_rm(ref_model, APB_CLK_DIV,  32'h0000_0004);
        apb_write_rm(ref_model, APB_DELAY,    32'h0000_0000);
        apb_write_rm(ref_model, APB_INT_EN,   32'h0000_001F);
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);
        apb_write_rm(ref_model, APB_SS_CTRL,  32'h0000_0000);

        coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));
        coverage.sample_clk_div(16'h0004);


        // SCENARIO A — Randomized legal bursts
        $display("[INFO] fifo_stress_test: Scenario A - randomized legal bursts");

        repeat (30) begin

            if (!t.randomize() with {
                    mode        == 2'b00;
                    width       == 2'b00;
                    lsb_first   == 1'b0;
                    loopback    == 1'b1;
                    delay_cfg   == 0;
                    burst_count inside {[1:8]};
                    clk_div inside {[1:8]};
                }) begin

                $display("[SCOREBOARD_ERROR] fifo_stress_test: randomize failed (Scenario A)");
                ref_model.error_count++;
                continue;
            end

            $display("[INFO] fifo_stress_test burst: %s burst_count=%0d",
                     t.sprint(), t.burst_count);


            ctrl_word[0] = 1'b0;
            apb_write_rm(ref_model, APB_CTRL, ctrl_word);

            ctrl_word[0] = 1'b1;
            apb_write_rm(ref_model, APB_CTRL, ctrl_word);

            apb_write_rm(ref_model, APB_CLK_DIV, {16'h0, t.clk_div});
            apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);

            coverage.sample_clk_div(t.clk_div[15:0]);

            apb_write_rm(ref_model, APB_SS_CTRL, 32'h0000_0001); //Assert SS[0]: SS_EN[0]=1, SS_VAL[0]=0

            for (int i = 0; i < t.burst_count; i++) begin
                apb_write_rm(ref_model, APB_TX_DATA, {24'h0, t.tx_data[7:0]});
                coverage.sample_tx_count(to4(i + 1));
            end

            wait_done(.max_polls(20_000), .timeout(timeout), .status(rd));

            if (timeout) begin
                $display("[SCOREBOARD_ERROR] fifo_stress_test: timeout in Scenario A, STATUS=0x%08h", rd);
                ref_model.error_count++;
            end

            for (int i = 0; i < t.burst_count; i++) begin
                model_one_transfer(ref_model, 32'h0, 1'b1);
            end

            coverage.sample_rx_count(to4(t.burst_count));
            coverage.sample_busy(1'b0);
            coverage.sample_tx_count(4'd0);

            if (t.burst_count == 8) begin
                apb_read_dut(APB_STATUS, rd);

                if (rd[3] !== 1'b1) begin //RX_FULL should assert after 8 received entries
                    $display("[SCOREBOARD_ERROR] fifo_stress_test: RX_FULL not set after 8 received entries (R12)");
                    ref_model.error_count++;
                end

                apb_read_dut(APB_RX_DATA, rd); //Pop one entry
                check_rx_front(ref_model, rd, "Scenario A first pop after RX_FULL");

                apb_read_dut(APB_STATUS, rd);

                if (rd[3] !== 1'b0) begin //confirm RX_FULL deasserts
                    $display("[SCOREBOARD_ERROR] fifo_stress_test: RX_FULL still set after one RX pop — should be 7 entries (R12)");
                    ref_model.error_count++;
                end

                for (int i = 1; i < 8; i++) begin //Pop remaining 7 entries
                    apb_read_dut(APB_RX_DATA, rd);
                    check_rx_front(ref_model, rd, "Scenario A remaining RX pop");
                end
            end
            else begin
                for (int i = 0; i < t.burst_count; i++) begin
                    apb_read_dut(APB_RX_DATA, rd);
                    check_rx_front(ref_model, rd, "Scenario A RX pop");
                end
            end

            coverage.sample_rx_count(4'd0);

            apb_write_rm(ref_model, APB_SS_CTRL, 32'h0000_0000);

            coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));
        end


        // SCENARIO B — TX FIFO depth check
        $display("[INFO] fifo_stress_test: Scenario B - TX FIFO depth=8 check (R11)");

        ctrl_word[0] = 1'b0;
        apb_write_rm(ref_model, APB_CTRL, ctrl_word);

        ctrl_word[0] = 1'b1;
        apb_write_rm(ref_model, APB_CTRL, ctrl_word);

        //Keep SS deasserted so the core does not consume TX FIFO
        apb_write_rm(ref_model, APB_SS_CTRL,  32'h0000_0000);
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);

        coverage.sample_tx_count(4'd0);

        for (int i = 0; i < 8; i++) begin
            apb_write_rm(ref_model, APB_TX_DATA, {24'h0, i[7:0]});
        end

        apb_read_dut(APB_STATUS, rd);
        coverage.sample_tx_count(4'd8);

        if (rd[1] !== 1'b1) begin //STATUS[1] = TX_FULL
            $display("[SCOREBOARD_ERROR] fifo_stress_test: TX_FULL not set after 8 writes, STATUS=0x%08h", rd);
            ref_model.error_count++;
        end

        if (rd[2] !== 1'b0) begin //STATUS[2] = TX_EMPTY
            $display("[SCOREBOARD_ERROR] fifo_stress_test: TX_EMPTY wrongly set while FIFO has 8 entries, STATUS=0x%08h", rd);
            ref_model.error_count++;
        end


        // SCENARIO C — TX FIFO overflow
        $display("[INFO] fifo_stress_test: Scenario C - TX overflow on 9th push (R13)");

        apb_write_rm(ref_model, APB_TX_DATA, 32'h0000_DEAD);

        apb_read_dut(APB_STATUS, rd);

        //STATUS[5] = TX_OVF
        if (rd[5] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: STATUS.TX_OVF not set after overflow, STATUS=0x%08h", rd);
            ref_model.error_count++;
        end

        apb_read_dut(APB_INT_STAT, rd);
        coverage.sample_interrupt_sources(rd[4:0], 5'b1_1111);

        //INT_STAT[2] = TX_OVF
        if (rd[2] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: INT_STAT[2] TX_OVF not set after overflow, INT_STAT=0x%08h", rd);
            ref_model.error_count++;
        end


        // SCENARIO D — W1C correctness
        $display("[INFO] fifo_stress_test: Scenario D - W1C correctness (R17)");

        //write zeros — TX_OVF must remain set
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_0000);
        apb_read_dut(APB_INT_STAT, rd);
        coverage.sample_irq_w1c(rd[4:0], 5'b1_1111);

        if (rd[2] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: INT_STAT[TX_OVF] cleared by write-0 — R17 violated");
            ref_model.error_count++;
        end

        //write 1 to bit 2 only — TX_OVF must clear
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_0004);
        apb_read_dut(APB_INT_STAT, rd);
        coverage.sample_irq_w1c(rd[4:0], 5'b1_1111);

        if (rd[2] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: INT_STAT[TX_OVF] not cleared by W1C — R17 violated");
            ref_model.error_count++;
        end

        //clear all bits
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);
        apb_read_dut(APB_INT_STAT, rd);

        if (rd[4:0] !== 5'b0_0000) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: INT_STAT not fully cleared after W1C, INT_STAT=0x%08h", rd);
            ref_model.error_count++;
        end


        // Drain TX FIFO before Scenario E
        $display("[INFO] fifo_stress_test: draining TX FIFO before Scenario E");

        apb_write_rm(ref_model, APB_SS_CTRL, 32'h0000_0001);

        wait_done(.max_polls(100_000), .timeout(timeout), .status(rd));

        if (timeout) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: timeout draining TX before Scenario E");
            ref_model.error_count++;
        end


        for (int i = 0; i < 8; i++) begin
            model_one_transfer(ref_model, 32'h0, 1'b1);
        end

        //Read and verify the 8 loopback RX entries
        for (int i = 0; i < 8; i++) begin
            apb_read_dut(APB_RX_DATA, rd);
            check_rx_front(ref_model, rd, "Drain before Scenario E");
        end

        apb_write_rm(ref_model, APB_SS_CTRL, 32'h0000_0000);


        // SCENARIO E — RX empty read, R15
        $display("[INFO] fifo_stress_test: Scenario E - RX empty read (R15)");

        ctrl_word[0] = 1'b0;
        apb_write_rm(ref_model, APB_CTRL, ctrl_word);

        ctrl_word[0] = 1'b1;
        apb_write_rm(ref_model, APB_CTRL, ctrl_word);

        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);

        apb_read_dut(APB_STATUS, rd);

        if (rd[4] !== 1'b1) begin //Verify RX_EMPTY=1 before proceeding
            $display("[SCOREBOARD_ERROR] fifo_stress_test: RX_EMPTY not set before Scenario E — flush did not work");
            ref_model.error_count++;
        end

        //Read from empty RX FIFO
        apb_read_dut(APB_RX_DATA, rd);

        //Empty RX read must return 0
        if (rd !== 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: empty RX read returned 0x%08h, expected 0x00000000 (R15)", rd);
            ref_model.error_count++;
        end

        //Empty RX read must not set STATUS.RX_OVF
        apb_read_dut(APB_STATUS, rd);

        if (rd[6] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: STATUS.RX_OVF set by empty RX read — R15 violated");
            ref_model.error_count++;
        end

        //Empty RX read must not set INT_STAT.RX_OVF
        apb_read_dut(APB_INT_STAT, rd);

        if (rd[3] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: INT_STAT[RX_OVF] set by empty RX read — R15 violated");
            ref_model.error_count++;
        end

        //Final cleanup
        apb_write_rm(ref_model, APB_SS_CTRL,  32'h0000_0000);
        apb_write_rm(ref_model, APB_INT_STAT, 32'h0000_001F);

        $display("[INFO] fifo_stress_test: finished, errors=%0d",
                 ref_model.error_count);

    endtask

endclass

`endif // FIFO_STRESS_TEST_SV