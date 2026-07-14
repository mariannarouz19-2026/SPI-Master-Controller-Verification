`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV
`include "ref_model.sv"
`include "coverage.sv"
`include "stim_lib.sv"

class reg_access_test;

    localparam [7:0] REG_CTRL     = 8'h00;
    localparam [7:0] REG_STATUS   = 8'h04;
    localparam [7:0] REG_TX_DATA  = 8'h08;
    localparam [7:0] REG_RX_DATA  = 8'h0C;
    localparam [7:0] REG_CLK_DIV  = 8'h10;
    localparam [7:0] REG_SS_CTRL  = 8'h14;
    localparam [7:0] REG_INT_EN   = 8'h18;
    localparam [7:0] REG_INT_STAT = 8'h1C;
    localparam [7:0] REG_DELAY    = 8'h20;

    static task check_register(
        ref spi_ref_model ref_model,
        input [31:0] expected,
        input [31:0] actual,
        input string test_name
    );
        if (expected !== actual) begin
            $display("[SCOREBOARD_ERROR] reg_access_test: %s FAILED", test_name);
            $display("  Expected: 0x%08X", expected);
            $display("  Actual:   0x%08X", actual);
            ref_model.error_count++;
        end else begin
            $display("[PASS] reg_access_test: %s PASSED (value=0x%08X)",
                     test_name, actual);
        end
    endtask

    static task check_wr(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage,
        input [7:0] addr,
        input [31:0] data,
        input string name
    );
        bit [31:0] rd;
        tb_top.u_apb_bfm.apb_write(addr, data);
        ref_model.predict_apb_write(addr, data);
        coverage.sample_reg_write(addr);

        tb_top.u_apb_bfm.apb_read(addr, rd);
        coverage.sample_reg_read(addr);
        check_register(ref_model, data, rd, name);
    endtask

    static task check_rd(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage,
        input [7:0] addr,
        input [31:0] expected,
        input string name
    );
        bit [31:0] rd;
        tb_top.u_apb_bfm.apb_read(addr, rd);
        coverage.sample_reg_read(addr);
        check_register(ref_model, expected, rd, name);
    endtask

    static task test_reset_values(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rd;
        
        $display("[INFO] Testing reset values");
        
        tb_top.u_apb_bfm.apb_read(REG_CTRL, rd);
        coverage.sample_reg_read(REG_CTRL);
        $display("[INFO] Actual CTRL after reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_CTRL, 32'h0000_0000, "CTRL reset");

        tb_top.u_apb_bfm.apb_read(REG_CLK_DIV, rd);
        coverage.sample_reg_read(REG_CLK_DIV);
        $display("[INFO] Actual CLK_DIV after reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_CLK_DIV, 32'h0000_0000, "CLK_DIV reset");
        
        tb_top.u_apb_bfm.apb_read(REG_INT_EN, rd);
        coverage.sample_reg_read(REG_INT_EN);
        $display("[INFO] Actual INT_EN after reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_INT_EN, 32'h0000_0000, "INT_EN reset");
        
        tb_top.u_apb_bfm.apb_read(REG_STATUS, rd);
        coverage.sample_reg_read(REG_STATUS);
        $display("[INFO] STATUS reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_STATUS, 32'h0000_0014, "STATUS reset");
        coverage.sample_tx_count(rd[4:2]);
        coverage.sample_rx_count(rd[4:2]);
        
        tb_top.u_apb_bfm.apb_read(REG_TX_DATA, rd);
        coverage.sample_reg_read(REG_TX_DATA);
        $display("[INFO] TX_DATA reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_TX_DATA, 32'h0000_0000, "TX_DATA reset");
        
        tb_top.u_apb_bfm.apb_read(REG_RX_DATA, rd);
        coverage.sample_reg_read(REG_RX_DATA);
        $display("[INFO] RX_DATA reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_RX_DATA, 32'h0000_0000, "RX_DATA reset");
        
        tb_top.u_apb_bfm.apb_read(REG_SS_CTRL, rd);
        coverage.sample_reg_read(REG_SS_CTRL);
        $display("[INFO] SS_CTRL reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_SS_CTRL, 32'h0000_0000, "SS_CTRL reset");
        
        tb_top.u_apb_bfm.apb_read(REG_INT_STAT, rd);
        coverage.sample_reg_read(REG_INT_STAT);
        $display("[INFO] INT_STAT reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_INT_STAT, 32'h0000_0000, "INT_STAT reset");
        
        tb_top.u_apb_bfm.apb_read(REG_DELAY, rd);
        coverage.sample_reg_read(REG_DELAY);
        $display("[INFO] DELAY reset = 0x%08X", rd);
        check_rd(ref_model, coverage, REG_DELAY, 32'h0000_0000, "DELAY reset");
    endtask

    static task test_read_write_registers(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage,
        input bit [7:0]  ctrl_val,
        input bit [15:0] clk_div_val,
        input bit [7:0]  ss_ctrl_val,
        input bit [4:0]  int_en_val,
        input bit [7:0]  delay_val,
        input bit [31:0] tx_data_val
    );
        $display("[INFO] Testing read/write registers");
        
        check_wr(ref_model, coverage, REG_CTRL,    {24'h0, ctrl_val},      "CTRL write/read");
        coverage.sample_config(ctrl_val[3:2], ctrl_val[4], ctrl_val[7:6]);
        
        tb_top.u_apb_bfm.apb_write(REG_TX_DATA, tx_data_val);
        ref_model.predict_apb_write(REG_TX_DATA, tx_data_val);
        coverage.sample_reg_write(REG_TX_DATA);
        coverage.sample_tx_count(4'd1);
        
        check_wr(ref_model, coverage, REG_CLK_DIV, {16'h0, clk_div_val},   "CLK_DIV write/read");
        coverage.sample_clk_div(clk_div_val);
        
        check_wr(ref_model, coverage, REG_SS_CTRL, {24'h0, ss_ctrl_val},   "SS_CTRL write/read");
        coverage.sample_ss_en(ss_ctrl_val[3:0]);
        
        check_wr(ref_model, coverage, REG_INT_EN,  {27'h0, int_en_val},    "INT_EN write/read");
        coverage.sample_interrupt_sources(int_en_val, int_en_val);
        
        check_wr(ref_model, coverage, REG_DELAY,   {24'h0, delay_val},     "DELAY write/read");
        coverage.sample_delay(delay_val);
    endtask

    static task test_RO_registers(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rdata;
        bit [31:0] original_value;
        
        $display("[INFO] Testing read-only registers");
        
        tb_top.u_apb_bfm.apb_read(REG_STATUS, original_value);
        coverage.sample_reg_read(REG_STATUS);
        
        tb_top.u_apb_bfm.apb_write(REG_STATUS, 32'hFFFF_FFFF);
        ref_model.predict_apb_write(REG_STATUS, 32'hFFFF_FFFF);
        coverage.sample_reg_write(REG_STATUS);
        
        tb_top.u_apb_bfm.apb_read(REG_STATUS, rdata);
        coverage.sample_reg_read(REG_STATUS);
        check_register(ref_model, original_value, rdata, "STATUS RO");
        
        tb_top.u_apb_bfm.apb_read(REG_RX_DATA, original_value);
        coverage.sample_reg_read(REG_RX_DATA);
        
        tb_top.u_apb_bfm.apb_write(REG_RX_DATA, 32'hFFFF_FFFF);
        ref_model.predict_apb_write(REG_RX_DATA, 32'hFFFF_FFFF);
        
        tb_top.u_apb_bfm.apb_read(REG_RX_DATA, rdata);
        coverage.sample_reg_read(REG_RX_DATA);
        check_register(ref_model, original_value, rdata, "RX_DATA RO");
    endtask

    static task test_W1C(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rdata;
        bit [31:0] before_clear;
        
        $display("[INFO] Testing W1C register");
        
        tb_top.u_apb_bfm.apb_read(REG_INT_STAT, before_clear);
        $display("[INFO] INT_STAT before W1C = 0x%08X", before_clear);
        coverage.sample_interrupt_sources(before_clear[4:0], 5'b11111);
        
        coverage.sample_irq_w1c(5'b11111, 5'b11111);
        
        tb_top.u_apb_bfm.apb_write(REG_INT_STAT, 32'hFFFF_FFFF);
        ref_model.predict_apb_write(REG_INT_STAT, 32'hFFFF_FFFF);
        coverage.sample_reg_write(REG_INT_STAT);
        
        tb_top.u_apb_bfm.apb_read(REG_INT_STAT, rdata);
        coverage.sample_reg_read(REG_INT_STAT);
        coverage.sample_irq_w1c(rdata[4:0], 5'b11111);
        
        $display("[INFO] INT_STAT after W1C = 0x%08X", rdata);
        
        if (rdata[4:0] == 5'b00000) begin
            $display("[PASS] reg_access_test: INT_STAT W1C PASSED");
        end else begin
            $display("[SCOREBOARD_ERROR] reg_access_test: INT_STAT W1C FAILED, bits still set = 0x%05X", rdata[4:0]);
            ref_model.error_count++;
        end
    endtask

    static task run(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        reg_acc_txn t;
        int seed;
        
        t = new();
        
        if ($value$plusargs("SEED=%d", seed)) t.srandom(seed);
        
        if (!t.randomize()) begin
            $display("[SCOREBOARD_ERROR] reg_acc_txn randomization failed");
            ref_model.error_count++;
            return;
        end
        
        $display("[INFO] reg_access_test: %s", t.sprint());
        $display("[INFO] reg_access_test: starting");
        $display("[INFO] Asserting DUT reset");
        
        tb_top.PRESETn = 1'b0;                    // assert reset
        repeat(20) @(posedge tb_top.PCLK);       // hold for 20 cycles
        @(negedge tb_top.PCLK);                  // release cleanly on negedge
        tb_top.PRESETn = 1'b1;
        repeat(2) @(posedge tb_top.PCLK);        // let DUT settle
        $display("[INFO] DUT reset released");

        ref_model.reset();
        test_reset_values(ref_model, coverage);
        test_reset_values(ref_model, coverage);
        test_read_write_registers(ref_model, coverage,
            t.ctrl_test_val, t.clk_div, t.ss_ctrl,
            t.int_en, t.delay_cfg, t.tx_data);
        test_RO_registers(ref_model, coverage);
        test_W1C(ref_model, coverage);
        coverage.sample_clk_div(t.clk_div);
        coverage.sample_delay(t.delay_cfg);
        coverage.sample_ss_en(t.ss_ctrl[3:0]);
        coverage.sample_loopback(t.ctrl_test_val[5], t.ctrl_test_val[7:6]);
        $display("[INFO] reg_access_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif