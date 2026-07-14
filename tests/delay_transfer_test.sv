`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

`include "ref_model.sv"
`include "coverage.sv"
`include "stim_lib.sv"

class delay_transfer_test;

    localparam [7:0] DEL_CTRL     = 8'h00;
    localparam [7:0] DEL_STATUS   = 8'h04;
    localparam [7:0] DEL_TX_DATA  = 8'h08;
    localparam [7:0] DEL_RX_DATA  = 8'h0C;
    localparam [7:0] DEL_CLK_DIV  = 8'h10;
    localparam [7:0] DEL_SS_CTRL  = 8'h14;
    localparam [7:0] DEL_INT_EN   = 8'h18;
    localparam [7:0] DEL_INT_STAT = 8'h1C;
    localparam [7:0] DEL_DELAY    = 8'h20;


    static task apb_write_rm(
        ref spi_ref_model ref_model,
        input logic [7:0]  addr,
        input logic [31:0] data
    );
        tb_top.u_apb_bfm.apb_write(addr, data);
        ref_model.predict_apb_write(addr, data);
    endtask


    static task apb_read_dut(
        input  logic [7:0]  addr,
        output logic [31:0] data
    );
        tb_top.u_apb_bfm.apb_read(addr, data);
    endtask


    static task model_one_transfer( //this updates the reference model's expected TX pop, RX word, RX FIFO, TX_EMPTY interrupt, TRANSFER_DONE interrupt, etc
        ref spi_ref_model ref_model,
        input logic [31:0] miso_word,
        input logic        loopback
    );
        ref_model.predict_tx_pop();

        ref_model.predict_transfer(
            .tx_data      (ref_model.pred_tx_word),
            .miso_pattern(miso_word),
            .loopback    (loopback)
        );

        ref_model.predict_transfer_complete(ref_model.pred_rx_word);
    endtask


    static task check_rx_front(
        ref spi_ref_model ref_model,
        input logic [31:0] observed,
        input string       tag
    );
        logic [31:0] expected;

        expected = ref_model.predict_apb_read(DEL_RX_DATA);

        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] delay_transfer_test: %s RX mismatch expected=0x%08h observed=0x%08h",
                     tag, expected, observed);
            ref_model.error_count++;
        end

        ref_model.predict_rx_pop(); //pop reference rx fifo
    endtask


    static function int unsigned calc_timeout_polls(
        input int unsigned width_bits,
        input int unsigned burst_count,
        input int unsigned clk_div,
        input int unsigned delay_val
    );
        int unsigned half_period;
        int unsigned transfer_cycles;
        int unsigned delay_cycles;
        int unsigned margin;

        half_period = clk_div + 1; //SCLK half-period = CLK_DIV + 1 PCLK cycle

        transfer_cycles = burst_count * width_bits * 2 * half_period; //One SPI bit = 2 half-periods

        if (burst_count > 1)
            delay_cycles = (burst_count - 1) * delay_val * half_period; //Delay is counted in SCLK half-cycles
        else
            delay_cycles = 0;

        margin = 200 + (20 * (clk_div + 1));

        return transfer_cycles + delay_cycles + margin;
    endfunction

    //Wait until whole burst is done
    static task wait_done(
        input  int unsigned max_polls,
        output bit          timeout,
        output logic [31:0] status
    );
        timeout = 1'b1;

        repeat (max_polls) begin
            tb_top.u_apb_bfm.apb_read(DEL_STATUS, status);

            if ((status[0] == 1'b0) && (status[2] == 1'b1)) begin //STATUS[0] BUSY = 0 and STATUS[2] TX_EMPTY = 1
                timeout = 1'b0;
                break;
            end
        end
    endtask


    //run called by tb_top
    static task run(
        ref spi_ref_model    ref_model,
        ref spi_coverage_col coverage
    );

        delay_txn  t;
        logic [31:0] rd;
        logic [31:0] ctrl_word;
        int          seed;
        bit          timeout;
        int unsigned timeout_polls;

        int directed_delays[] = '{0, 1, 10, 31, 128, 255};
        int directed_divs[]   = '{1, 4, 1024};

        $display("[INFO] delay_transfer_test: starting");

        t = new();
        ref_model.reset();

        if ($value$plusargs("SEED=%d", seed)) begin
            t.srandom(seed);
            $display("[INFO] delay_transfer_test: using SEED=%0d", seed);
        end

        //Configure slave BFM
        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_width     = 2'b00;
        tb_top.bfm_pattern   = 32'h0000_0000;

    
        ctrl_word      = 32'h0;
        ctrl_word[0]   = 1'b1;   // EN
        ctrl_word[1]   = 1'b1;   // MSTR
        ctrl_word[3:2] = 2'b00;  // Mode 0
        ctrl_word[4]   = 1'b0;   // MSB-first
        ctrl_word[5]   = 1'b1;   // Loopback ON
        ctrl_word[7:6] = 2'b00;  // 8-bit

        apb_write_rm(ref_model, DEL_CTRL,     ctrl_word);
        apb_write_rm(ref_model, DEL_INT_EN,   32'h0000_001F);
        apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);
        apb_write_rm(ref_model, DEL_SS_CTRL,  32'h0000_0000);

        coverage.sample_config(2'b00, 1'b0, 2'b00);
        coverage.sample_loopback(1'b1, 2'b00);


        // SCENARIO A — Directed delay x divider sweep
        $display("[INFO] delay_transfer_test: Scenario A - directed delay sweep");

        foreach (directed_divs[d]) begin
            foreach (directed_delays[i]) begin

                $display("[INFO] delay_transfer_test: CLK_DIV=%0d DELAY=%0d",
                         directed_divs[d], directed_delays[i]);

                ctrl_word[0] = 1'b0;
                apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

                ctrl_word[0] = 1'b1;
                apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

                apb_write_rm(ref_model, DEL_CLK_DIV,  directed_divs[d]);
                apb_write_rm(ref_model, DEL_DELAY,    directed_delays[i]);
                apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);

                coverage.sample_clk_div(directed_divs[d][15:0]);
                coverage.sample_delay(directed_delays[i][7:0]);

                //Assert SS[0]
                apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0001);

                repeat (3) begin
                    apb_write_rm(ref_model, DEL_TX_DATA, 32'h0000_00A5);
                end

                apb_read_dut(DEL_STATUS, rd); //Check BUSY after push

                if (rd[0] !== 1'b1) begin
                    $display("[SCOREBOARD_ERROR] delay_transfer_test: BUSY not set after TX push CLK_DIV=%0d DELAY=%0d",
                             directed_divs[d], directed_delays[i]);
                    ref_model.error_count++;
                end

                coverage.sample_busy(1'b1);

                timeout_polls = calc_timeout_polls(
                    .width_bits (8),
                    .burst_count(3),
                    .clk_div    (directed_divs[d]),
                    .delay_val  (directed_delays[i])
                );

                wait_done(.max_polls(timeout_polls),
                          .timeout(timeout),
                          .status(rd));

                if (timeout) begin
                    $display("[SCOREBOARD_ERROR] delay_transfer_test: timeout CLK_DIV=%0d DELAY=%0d polls=%0d STATUS=0x%08h",
                             directed_divs[d], directed_delays[i], timeout_polls, rd);
                    ref_model.error_count++;
                end

                repeat (3) begin
                    model_one_transfer(ref_model, 32'h0000_0000, 1'b1); //Advance reference model for the 3 completed transfers
                end

                coverage.sample_busy(1'b0);

                //Read and check RX
                repeat (3) begin
                    apb_read_dut(DEL_RX_DATA, rd);
                    check_rx_front(ref_model, rd, "Scenario A");
                end

                apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0000);

                coverage.sample_config(2'b00, 1'b0, 2'b00);
            end
        end


        // SCENARIO B — BUSY stays asserted during delay gap
        $display("[INFO] delay_transfer_test: Scenario B - BUSY stays 1 during delay gap");

        ctrl_word[0] = 1'b0;
        apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

        ctrl_word[0] = 1'b1;
        apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

        apb_write_rm(ref_model, DEL_CLK_DIV,  32'h0000_0001);
        apb_write_rm(ref_model, DEL_DELAY,    32'h0000_00FF); //Delay = 255
        apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);
        apb_write_rm(ref_model, DEL_SS_CTRL,  32'h0000_0001);

        coverage.sample_clk_div(16'h0001);
        coverage.sample_delay(8'hFF);

        apb_write_rm(ref_model, DEL_TX_DATA, 32'h0000_00C3);
        apb_write_rm(ref_model, DEL_TX_DATA, 32'h0000_00C3);

        begin
            bit gap_busy_ok;
            gap_busy_ok = 1'b1;

            repeat (600) begin
                apb_read_dut(DEL_STATUS, rd);

                if (rd[0] == 1'b0 && rd[2] == 1'b0) begin // BUSY=0 and TX_EMPTY=0 
                    $display("[SCOREBOARD_ERROR] delay_transfer_test: BUSY deasserted during delay gap");
                    ref_model.error_count++;
                    gap_busy_ok = 1'b0;
                    break;
                end

                if (rd[0] == 1'b0 && rd[2] == 1'b1)
                    break;
            end

            if (gap_busy_ok)
                $display("[INFO] delay_transfer_test: BUSY correctly held during gap");
        end

        timeout_polls = calc_timeout_polls(8, 2, 1, 255);

        wait_done(.max_polls(timeout_polls),
                  .timeout(timeout),
                  .status(rd));

        if (timeout) begin
            $display("[SCOREBOARD_ERROR] delay_transfer_test: timeout in Scenario B STATUS=0x%08h", rd);
            ref_model.error_count++;
        end

        repeat (2) begin
            model_one_transfer(ref_model, 32'h0000_0000, 1'b1);
        end

        repeat (2) begin
            apb_read_dut(DEL_RX_DATA, rd);
            check_rx_front(ref_model, rd, "Scenario B");
        end

        apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0000);


        // SCENARIO C — Mid-transfer CLK_DIV write
        $display("[INFO] delay_transfer_test: Scenario C - mid-transfer CLK_DIV write");

        ctrl_word[0] = 1'b0;
        apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

        ctrl_word[0] = 1'b1;
        apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

        apb_write_rm(ref_model, DEL_CLK_DIV,  32'h0000_0010);
        apb_write_rm(ref_model, DEL_DELAY,    32'h0000_0000);
        apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);
        apb_write_rm(ref_model, DEL_SS_CTRL,  32'h0000_0001);

        apb_write_rm(ref_model, DEL_TX_DATA, 32'h0000_005A);

        apb_write_rm(ref_model, DEL_CLK_DIV, 32'h0000_0004); //Change CLK_DIV during active transfer

        coverage.sample_clk_div(16'h0010);
        coverage.sample_delay(8'h00);

        timeout_polls = calc_timeout_polls(8, 1, 16, 0);

        wait_done(.max_polls(timeout_polls),
                  .timeout(timeout),
                  .status(rd));

        if (timeout) begin
            $display("[SCOREBOARD_ERROR] delay_transfer_test: timeout after mid-transfer CLK_DIV write");
            ref_model.error_count++;
        end

        model_one_transfer(ref_model, 32'h0000_0000, 1'b1);

        apb_read_dut(DEL_RX_DATA, rd);
        check_rx_front(ref_model, rd, "Scenario C");

        apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0000);


        // SCENARIO D — Randomized sweep
        $display("[INFO] delay_transfer_test: Scenario D - randomized sweep");

        repeat (100) begin

            if (!t.randomize() with {
                    loopback  == 1'b1;
                    width     == 2'b00;
                    mode      == 2'b00;
                    lsb_first == 1'b0;
                    clk_div dist {
                        [1:8]      := 40,
                        [9:64]     := 35,
                        [65:256]   := 20,
                        [257:1024] := 5
                    };
                }) begin
                $display("[SCOREBOARD_ERROR] delay_transfer_test: randomize failed");
                ref_model.error_count++;
                continue;
            end

            $display("[INFO] delay_transfer_test randomized: %s", t.sprint());

            ctrl_word[0] = 1'b0;
            apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

            ctrl_word[0] = 1'b1;
            apb_write_rm(ref_model, DEL_CTRL, ctrl_word);

            apb_write_rm(ref_model, DEL_CLK_DIV,  {16'h0, t.clk_div});
            apb_write_rm(ref_model, DEL_DELAY,    {24'h0, t.delay_cfg});
            apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);

            coverage.sample_clk_div(t.clk_div[15:0]);
            coverage.sample_delay(t.delay_cfg);

            apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0001);

            repeat (3) begin
                apb_write_rm(ref_model, DEL_TX_DATA, {24'h0, t.tx_data[7:0]});
            end

            apb_read_dut(DEL_STATUS, rd);

            if (rd[0] !== 1'b1) begin
                $display("[SCOREBOARD_ERROR] delay_transfer_test: BUSY not set after TX push randomized");
                ref_model.error_count++;
            end

            coverage.sample_busy(1'b1);

            timeout_polls = calc_timeout_polls(
                .width_bits (8),
                .burst_count(3),
                .clk_div    (t.clk_div),
                .delay_val  (t.delay_cfg)
            );

            wait_done(.max_polls(timeout_polls),
                      .timeout(timeout),
                      .status(rd));

            if (timeout) begin
                $display("[SCOREBOARD_ERROR] delay_transfer_test: timeout randomized polls=%0d STATUS=0x%08h",
                         timeout_polls, rd);
                ref_model.error_count++;
            end

            repeat (3) begin
                model_one_transfer(ref_model, 32'h0000_0000, 1'b1);
            end

            coverage.sample_busy(1'b0);

            repeat (3) begin
                apb_read_dut(DEL_RX_DATA, rd);
                check_rx_front(ref_model, rd, "Scenario D");
            end

            apb_write_rm(ref_model, DEL_SS_CTRL, 32'h0000_0000);

            coverage.sample_config(2'b00, 1'b0, 2'b00);
        end

        //Final cleanup
        apb_write_rm(ref_model, DEL_SS_CTRL,  32'h0000_0000);
        apb_write_rm(ref_model, DEL_INT_STAT, 32'h0000_001F);

        $display("[INFO] delay_transfer_test: finished, errors=%0d",
                 ref_model.error_count);

    endtask

endclass

`endif // DELAY_TRANSFER_TEST_SV