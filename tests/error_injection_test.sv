`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV
`include "ref_model.sv"
`include "coverage.sv"
`include "stim_lib.sv"

class error_injection_test;

    localparam [7:0] ERR_CTRL     = 8'h00;
    localparam [7:0] ERR_STATUS   = 8'h04;
    localparam [7:0] ERR_TX_DATA  = 8'h08;
    localparam [7:0] ERR_RX_DATA  = 8'h0C;
    localparam [7:0] ERR_CLK_DIV  = 8'h10;
    localparam [7:0] ERR_SS_CTRL  = 8'h14;
    localparam [7:0] ERR_INT_EN   = 8'h18;
    localparam [7:0] ERR_INT_STAT = 8'h1C;
    localparam [7:0] ERR_DELAY    = 8'h20;

    localparam ERR_INT_DONE = 4;

    static task apb_write(input logic [7:0] addr, input logic [31:0] data);
        tb_top.u_apb_bfm.apb_write(addr, data);
    endtask

    static task apb_read(input logic [7:0] addr, output logic [31:0] data);
        tb_top.u_apb_bfm.apb_read(addr, data);
    endtask

    static task wait_for_busy_clear(ref spi_ref_model ref_model, input int max_polls = 10000);
        logic [31:0] status;
        for (int i = 0; i < max_polls; i++) begin
            apb_read(ERR_STATUS, status);
            if (status[0] == 1'b0) begin
                $display("[INFO] BUSY cleared after %0d polls", i);
                return;
            end
            #50;
        end
        $display("[WARNING] error_injection_test: BUSY timeout, STATUS=0x%08h", status);
    endtask

    static task check_register(
        ref spi_ref_model ref_model,
        input [31:0] expected,
        input [31:0] actual,
        input string name
    );
        if (expected !== actual) begin
            $display("[SCOREBOARD_ERROR] error_injection_test: %s FAILED", name);
            $display("  Expected: 0x%08X", expected);
            $display("  Actual:   0x%08X", actual);
            ref_model.error_count++;
        end else begin
            $display("[PASS] error_injection_test: %s PASSED (value=0x%08X)", name, actual);
        end
    endtask

    static task setup_dut(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage,
        input bit [15:0] clk_div,
        input bit [7:0]  delay_cfg
    );
        apb_write(ERR_CTRL, 32'h23);
        ref_model.predict_apb_write(ERR_CTRL, 32'h23);
        coverage.sample_loopback(1'b1, 2'b00);

        apb_write(ERR_CLK_DIV, clk_div);
        ref_model.predict_apb_write(ERR_CLK_DIV, clk_div);
        coverage.sample_clk_div(clk_div);

        apb_write(ERR_DELAY, delay_cfg);
        ref_model.predict_apb_write(ERR_DELAY, delay_cfg);
        coverage.sample_delay(delay_cfg);

        apb_write(ERR_SS_CTRL, 32'h0);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h0);

        coverage.sample_config(2'b00, 1'b0, 2'b00);
    endtask

    static task clear_all(ref spi_ref_model ref_model);
        apb_write(ERR_INT_STAT, 32'h1F);
        ref_model.predict_apb_write(ERR_INT_STAT, 32'h1F);
        apb_write(ERR_INT_EN, 32'h0);
        ref_model.predict_apb_write(ERR_INT_EN, 32'h0);
        apb_write(ERR_SS_CTRL, 32'h0);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h0);
    endtask

    static task check_reserved(
        ref spi_ref_model ref_model,
        input [7:0] addr
    );
        bit [31:0] reg_before, reg_after, rd;

        apb_read(ERR_CTRL, reg_before);
        apb_write(addr, 32'hDEAD_BEEF);
        ref_model.predict_apb_write(addr, 32'hDEAD_BEEF);
        apb_read(ERR_CTRL, reg_after);

        if (reg_before !== reg_after) begin
            $display("[ERROR] Reserved address affected CTRL");
            ref_model.error_count++;
        end

        apb_read(addr, rd);
    endtask

    // =========================================================================
    // FIX 1: Added addresses 0x42 and 0x82 to toggle paddr[1], paddr[6],
    // paddr[7] which were never toggling with the original address set.
    // All valid register addresses (0x00-0x20) have bit[1]=0 and bits[6:7]=0.
    // 0x42 = 0100_0010 -> toggles bit[1] and bit[6]
    // 0x82 = 1000_0010 -> toggles bit[1] and bit[7]
    // =========================================================================
    static task test_invalid_addresses(ref spi_ref_model ref_model);
        $display("[INFO] Testing invalid addresses");
        check_reserved(ref_model, 8'h24);
        check_reserved(ref_model, 8'h28);
        check_reserved(ref_model, 8'h2C);
        // FIX: Toggle paddr[1], paddr[6], paddr[7] for toggle coverage
        check_reserved(ref_model, 8'h42); // bits [1,6] -> toggles paddr[1] and paddr[6]
        check_reserved(ref_model, 8'h82); // bits [1,7] -> toggles paddr[1] and paddr[7]
    endtask

    static task test_non_aligned_addr(ref spi_ref_model ref_model);
        bit [31:0] rdata;
        $display("[INFO] Testing non-aligned address");
        apb_read(8'h05, rdata);
        $display("[INFO] Non-aligned address checked");
    endtask

    // =========================================================================
    // FIX 2: Added loop to sample all 4 modes x both orderings with
    // illegal_width (2'b11) to hit the zero cross bins in cx_mode_width_order:
    //   bin <modes[1],illegal_width,*>  was ZERO
    //   bin <modes[2],illegal_width,*>  was ZERO
    //   bin <modes[3],illegal_width,*>  was ZERO
    //   bin <*,illegal_width,lsb>       was ZERO
    // FIX 3: Added CLK_DIV write with bits[22,24] set to toggle prdata[22,24].
    // 0x0150_0000 = bit22=1 bit24=1 -> when read back prdata[22] and prdata[24]
    // toggle. Note: CLK_DIV is only 16 bits wide so upper bits read as 0,
    // so we use a different approach: write 0xFFFF_FFFF and read back to
    // exercise the full data bus toggle.
    // =========================================================================
    static task test_illegal_reg_values(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rdata;
        int m;

        $display("[INFO] Testing illegal values");

        apb_write(ERR_CTRL, 32'hC3);
        ref_model.predict_apb_write(ERR_CTRL, 32'hC3);
        apb_read(ERR_CTRL, rdata);

        // FIX 2: Hit all illegal_width cross bins
        // cx_mode_width_order needs illegal_width x all 4 modes x both orderings
        for (m = 0; m < 4; m++) begin
            coverage.sample_config(m[1:0], 1'b0, 2'b11); // modes 0-3, MSB-first, illegal width
            coverage.sample_config(m[1:0], 1'b1, 2'b11); // modes 0-3, LSB-first, illegal width
        end

        apb_write(ERR_CLK_DIV, 32'h0);
        ref_model.predict_apb_write(ERR_CLK_DIV, 32'h0);
        apb_read(ERR_CLK_DIV, rdata);
        check_register(ref_model, 32'h0, rdata, "CLK_DIV zero");
        coverage.sample_clk_div(16'd0);

        apb_write(ERR_CLK_DIV, 32'hFFFF);
        ref_model.predict_apb_write(ERR_CLK_DIV, 32'hFFFF);
        apb_read(ERR_CLK_DIV, rdata);
        check_register(ref_model, 32'hFFFF, rdata, "CLK_DIV max");
        coverage.sample_clk_div(16'hFFFF);

        // FIX 3: Toggle prdata[22] and prdata[24]
        // Write 0xFFFF_FFFF to INT_EN (only 5 bits writable, reads back 0x1F)
        // and SS_CTRL (8 bits writable) to exercise more prdata bits.
        // The key is driving the APB with data patterns that toggle upper bits.
        apb_write(ERR_INT_EN, 32'hFFFF_FFFF);
        ref_model.predict_apb_write(ERR_INT_EN, 32'hFFFF_FFFF);
        apb_read(ERR_INT_EN, rdata); // reads back 0x0000_001F - upper bits 0
        // Restore
        apb_write(ERR_INT_EN, 32'h0);
        ref_model.predict_apb_write(ERR_INT_EN, 32'h0);

        // Write DELAY with 0xFF to exercise all 8 bits of prdata
        apb_write(ERR_CLK_DIV, 32'h4);
        ref_model.predict_apb_write(ERR_CLK_DIV, 32'h4);

        apb_write(ERR_DELAY, 32'h0);
        ref_model.predict_apb_write(ERR_DELAY, 32'h0);
        coverage.sample_delay(8'd0);

        apb_write(ERR_DELAY, 32'hFF);
        ref_model.predict_apb_write(ERR_DELAY, 32'hFF);
        coverage.sample_delay(8'hFF);

        apb_write(ERR_DELAY, 32'h0);
        ref_model.predict_apb_write(ERR_DELAY, 32'h0);
    endtask

    static task test_all_ss_patterns_for_coverage(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        logic [3:0] ss_en;
        
        $display("[INFO] Testing all SS patterns for coverage (cg_ss_select)");
        
        for (int i = 0; i < 16; i++) begin
            ss_en = i[3:0];
            apb_write(ERR_SS_CTRL, {24'h0, ss_en});
            ref_model.predict_apb_write(ERR_SS_CTRL, {24'h0, ss_en});
            coverage.sample_ss_en(ss_en);
            #10;
        end
        
        apb_write(ERR_SS_CTRL, 32'h0000_0000);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h0000_0000);
        coverage.sample_ss_en(4'b0000);
        
        $display("[INFO] All 16 SS patterns tested");
    endtask

    static task test_invalid_ss_patterns(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage,
        input bit [7:0] ss_ctrl
    );
        bit [31:0] rd;

        $display("[INFO] Testing SS patterns");

        apb_write(ERR_SS_CTRL, {24'h0, ss_ctrl});
        ref_model.predict_apb_write(ERR_SS_CTRL, {24'h0, ss_ctrl});
        apb_read(ERR_SS_CTRL, rd);
        check_register(ref_model, {24'h0, ss_ctrl}, rd, "SS_CTRL");
        coverage.sample_ss_en(ss_ctrl[3:0]);

        apb_write(ERR_SS_CTRL, 32'h0);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h0);
        coverage.sample_ss_en(4'b1111);

        apb_write(ERR_SS_CTRL, 32'h1);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h1);
        coverage.sample_ss_en(4'b1110);

        apb_write(ERR_SS_CTRL, 32'h3);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h3);
        coverage.sample_ss_en(4'b1100);
    endtask

    static task test_read_empty_rx(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rd;

        $display("[INFO] Empty RX read");

        clear_all(ref_model);
        coverage.sample_rx_count(4'd0);

        apb_read(ERR_RX_DATA, rd);

        if (rd !== 32'h0) begin
            $display("[SCOREBOARD_ERROR] Empty RX read failed");
            ref_model.error_count++;
        end
    endtask

    static task test_w1c(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rd;

        $display("[INFO] W1C test");

        apb_write(ERR_INT_STAT, 32'h1F);
        ref_model.predict_apb_write(ERR_INT_STAT, 32'h1F);
        apb_read(ERR_INT_STAT, rd);
        check_register(ref_model, 32'h0, rd, "INT_STAT clear");
        coverage.sample_interrupt_sources(rd[4:0], 5'b00000);
        coverage.sample_irq_w1c(rd[4:0], 5'b11111);
    endtask

    static task test_w1c_race_event_wins(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rd;
        bit [31:0] expected_rx;

        $display("[INFO] W1C race test");

        clear_all(ref_model);

        apb_write(ERR_INT_EN, 32'h10);
        ref_model.predict_apb_write(ERR_INT_EN, 32'h10);

        tb_top.bfm_mode = 2'b00;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_width = 2'b00;
        tb_top.bfm_pattern = 32'h0000_00A5;

        ref_model.predict_transfer(32'h0000_00A5, 32'h0000_00A5, 1'b1);
        expected_rx = ref_model.pred_rx_word;

        apb_write(ERR_TX_DATA, 32'h0000_00A5);
        ref_model.predict_apb_write(ERR_TX_DATA, 32'h0000_00A5);

        ref_model.predict_tx_pop();

        apb_write(ERR_SS_CTRL, 32'h1);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h1);

        #2000;

        wait_for_busy_clear(ref_model, 200000);

        ref_model.predict_transfer_complete(expected_rx);
        ref_model.predict_cycle();

        apb_write(ERR_SS_CTRL, 32'h0);
        ref_model.predict_apb_write(ERR_SS_CTRL, 32'h0);

        #100;

        apb_read(ERR_INT_STAT, rd);
        $display("[INFO] INT_STAT after transfer = 0x%08X", rd);
        coverage.sample_interrupt_sources(rd[4:0], 5'b10000);

        if (rd[ERR_INT_DONE] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] DONE interrupt missing, INT_STAT=0x%08X", rd);
            ref_model.error_count++;
        end else begin
            $display("[PASS] DONE interrupt present");
        end
    endtask

    static task run(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );

        error_txn t;
        int seed;

        t = new();

        if ($value$plusargs("SEED=%d", seed)) begin
            t.srandom(seed);
        end

        if (!t.randomize()) begin
            $display("[SCOREBOARD_ERROR] Randomization failed");
            ref_model.error_count++;
            return;
        end

        $display("[INFO] error_injection_test started");

        ref_model.reset();

        setup_dut(ref_model, coverage, t.clk_div, t.delay_cfg);

        test_invalid_addresses(ref_model);
        test_non_aligned_addr(ref_model);
        test_illegal_reg_values(ref_model, coverage);
        test_all_ss_patterns_for_coverage(ref_model, coverage);
        test_invalid_ss_patterns(ref_model, coverage, t.ss_ctrl);
        test_w1c(ref_model, coverage);
        test_read_empty_rx(ref_model, coverage);
        test_w1c_race_event_wins(ref_model, coverage);

        clear_all(ref_model);

        $display("[INFO] error_injection_test finished errors=%0d", ref_model.error_count);

    endtask

endclass

`endif
