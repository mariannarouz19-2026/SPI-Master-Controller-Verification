`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV
`include "ref_model.sv"
`include "coverage.sv"

`ifndef CDT_APB_ADDRS
`define CDT_APB_ADDRS
  localparam [7:0] CDT_CTRL     = 8'h00;
  localparam [7:0] CDT_STATUS   = 8'h04;
  localparam [7:0] CDT_TX_DATA  = 8'h08;
  localparam [7:0] CDT_RX_DATA  = 8'h0C;
  localparam [7:0] CDT_CLK_DIV  = 8'h10;
  localparam [7:0] CDT_SS_CTRL  = 8'h14;
  localparam [7:0] CDT_INT_EN   = 8'h18;
  localparam [7:0] CDT_INT_STAT = 8'h1C;
  localparam [7:0] CDT_DELAY    = 8'h20;
`endif

localparam int CDT_PCLK_NS = 10;

class clk_div_corner_test;

  static task apb_write(input logic [7:0] addr, input logic [31:0] data);
    tb_top.u_apb_bfm.apb_write(addr, data);
  endtask

  static task apb_read(input logic [7:0] addr, output logic [31:0] data);
    tb_top.u_apb_bfm.apb_read(addr, data);
  endtask

  static task poll_until_not_busy(ref spi_ref_model ref_model,
                                   input int max_polls = 10000000);
    logic [31:0] s;
    int i;
    for (i = 0; i < max_polls; i++) begin
      apb_read(CDT_STATUS, s);
      if (s[0] == 1'b0) return;
    end
    $display("[SCOREBOARD_ERROR] clk_div_corner_test: timeout BUSY never cleared");
    ref_model.error_count++;
  endtask

  static task poll_until_busy(ref spi_ref_model ref_model,
                               input int max_polls = 10000000);
    logic [31:0] s;
    int i;
    for (i = 0; i < max_polls; i++) begin
      apb_read(CDT_STATUS, s);
      if (s[0] == 1'b1) return;
    end
    $display("[SCOREBOARD_ERROR] clk_div_corner_test: timeout BUSY never asserted");
    ref_model.error_count++;
  endtask

  static task check_sclk_idle(ref spi_ref_model ref_model,
                               input logic cpol, input string ctx);
    @(posedge tb_top.PCLK); #1;
    if (tb_top.spi.sclk !== cpol) begin
      $display("[SCOREBOARD_ERROR] R4 SCLK idle @%s: expected=%0b got=%0b",
               ctx, cpol, tb_top.spi.sclk);
      ref_model.error_count++;
    end else
      $display("[INFO] R4 SCLK idle OK @%s = %0b", ctx, cpol);
  endtask

  static task measure_consecutive_posedges(
    input  int div_val,
    output int period_ns_out
  );
    longint t1, t2;
    period_ns_out = -1;
    @(posedge tb_top.spi.sclk);
    t1 = $time;
    @(posedge tb_top.spi.sclk);
    t2 = $time;
    period_ns_out = int'(t2 - t1);
  endtask

  static task check_sclk_freq(ref spi_ref_model ref_model,
                               input int div_val, input int period_ns_val);
    int exp_ns;
    exp_ns = 2*(div_val+1) * CDT_PCLK_NS;
    if (period_ns_val < 0) begin
      $display("[SCOREBOARD_ERROR] R8 DIV=%0d: could not measure SCLK period",
               div_val);
      ref_model.error_count++;
    end else if (period_ns_val < exp_ns - CDT_PCLK_NS ||
                 period_ns_val > exp_ns + CDT_PCLK_NS) begin
      $display("[SCOREBOARD_ERROR] R8/R24 DIV=%0d: expected=%0dns got=%0dns",
               div_val, exp_ns, period_ns_val);
      ref_model.error_count++;
    end else
      $display("[INFO] R8/R24 OK DIV=%0d: period=%0dns (expected %0dns)",
               div_val, period_ns_val, exp_ns);
  endtask

  static task run_one_div(
    ref   spi_ref_model    ref_model,
    ref   spi_coverage_col coverage,
    input logic [15:0]     div_val,
    input string           label
  );
    logic [31:0] rx_data;
    logic [31:0] status;
    logic [31:0] ctrl_word;
    logic [31:0] expected_rx;
    logic [31:0] tx_value;
    int          period_ns_val;
    int          busy_timeout;

    busy_timeout = 64 * 2*(int'(div_val)+1) + 256;
    tx_value = 32'h0000_00A5;

    $display("[INFO] clk_div_corner_test: DIV=%0d ('%0s')", div_val, label);

    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_pattern   = tx_value;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b00;

    ctrl_word = 32'h0000_0023;

    apb_write(CDT_CLK_DIV,  {16'b0, div_val});
    ref_model.predict_apb_write(CDT_CLK_DIV, {16'b0, div_val});
    
    apb_write(CDT_INT_EN,   32'h0000_001F);
    ref_model.predict_apb_write(CDT_INT_EN, 32'h0000_001F);
    
    apb_write(CDT_DELAY,    32'h0);
    ref_model.predict_apb_write(CDT_DELAY, 32'h0);
    
    apb_write(CDT_CTRL,     ctrl_word);
    ref_model.predict_apb_write(CDT_CTRL, ctrl_word);
    
    apb_write(CDT_SS_CTRL,  32'h0000_0001);
    ref_model.predict_apb_write(CDT_SS_CTRL, 32'h0000_0001);

    coverage.sample_config(2'b00, 1'b0, 2'b00);
    coverage.sample_clk_div(div_val);
    coverage.sample_delay(8'd0);
    coverage.sample_ss_en(4'b1110);
    coverage.sample_loopback(1'b1, 2'b00);
    coverage.sample_reg_write(CDT_CTRL);
    coverage.sample_reg_write(CDT_CLK_DIV);
    coverage.sample_reg_write(CDT_INT_EN);
    coverage.sample_reg_write(CDT_DELAY);
    coverage.sample_reg_write(CDT_SS_CTRL);

    check_sclk_idle(ref_model, 1'b0, $sformatf("pre DIV=%0d", div_val));

    ref_model.predict_transfer(tx_value, tx_value, 1'b1);
    expected_rx = ref_model.pred_rx_word;

    apb_write(CDT_TX_DATA, tx_value);
    ref_model.predict_apb_write(CDT_TX_DATA, tx_value);
    coverage.sample_reg_write(CDT_TX_DATA);

    ref_model.predict_tx_pop();
    coverage.sample_busy(1'b1);

    poll_until_busy(ref_model, busy_timeout);
    
    measure_consecutive_posedges(int'(div_val), period_ns_val);
    check_sclk_freq(ref_model, int'(div_val), period_ns_val);
    
    poll_until_not_busy(ref_model, busy_timeout * 4);

    ref_model.predict_transfer_complete(expected_rx);
    ref_model.predict_cycle();

    $display("[INFO] R7 liveness OK DIV=%0d: transfer completed", div_val);

    apb_write(CDT_SS_CTRL, 32'h0);
    ref_model.predict_apb_write(CDT_SS_CTRL, 32'h0);
    coverage.sample_reg_write(CDT_SS_CTRL);
    coverage.sample_ss_en(4'b1111);
    coverage.sample_busy(1'b0);
    coverage.sample_transfer_done(1'b1);

    check_sclk_idle(ref_model, 1'b0, $sformatf("post DIV=%0d", div_val));

    apb_read(CDT_RX_DATA, rx_data);
    coverage.sample_reg_read(CDT_RX_DATA);

    ref_model.check_rx(rx_data);
    ref_model.predict_rx_pop();

    if (rx_data[7:0] !== 8'hA5) begin
      $display("[SCOREBOARD_ERROR] loopback sanity DIV=%0d: tx=0xA5 rx=0x%02h",
               div_val, rx_data[7:0]);
      ref_model.error_count++;
    end else
      $display("[INFO] loopback sanity OK DIV=%0d: rx=0xA5", div_val);

    apb_read(CDT_STATUS, status);
    ref_model.check_status(status);
    coverage.sample_busy(status[0]);
    coverage.sample_reg_read(CDT_STATUS);

    apb_write(CDT_CTRL, 32'h0);
    ref_model.predict_apb_write(CDT_CTRL, 32'h0);
    repeat(4) @(posedge tb_top.PCLK);
  endtask

  static task run_r25_div_latch(
    ref   spi_ref_model    ref_model,
    ref   spi_coverage_col coverage,
    input logic [15:0]     div_a,
    input logic [15:0]     div_b
  );
    int period_before;
    int period_after;
    int exp_ns;
    logic [31:0] expected_rx;
    logic [31:0] tx_value;

    tx_value = 32'hDEAD_BEEF;
    exp_ns = 2*(int'(div_a)+1) * CDT_PCLK_NS;

    $display("[INFO] clk_div_corner_test: R25 DIV latch (a=%0d b=%0d)",
             div_a, div_b);

    tb_top.bfm_mode      = 2'b00;
    tb_top.bfm_pattern   = tx_value;
    tb_top.bfm_lsb_first = 1'b0;
    tb_top.bfm_width     = 2'b10;

    apb_write(CDT_CLK_DIV, {16'b0, div_a});
    ref_model.predict_apb_write(CDT_CLK_DIV, {16'b0, div_a});
    
    apb_write(CDT_INT_EN,  32'h0000_001F);
    ref_model.predict_apb_write(CDT_INT_EN, 32'h0000_001F);
    
    apb_write(CDT_DELAY,   32'h0);
    ref_model.predict_apb_write(CDT_DELAY, 32'h0);
    
    apb_write(CDT_CTRL,    32'h0000_00A3);
    ref_model.predict_apb_write(CDT_CTRL, 32'h0000_00A3);
    
    apb_write(CDT_SS_CTRL, 32'h0000_0001);
    ref_model.predict_apb_write(CDT_SS_CTRL, 32'h0000_0001);

    ref_model.predict_transfer(tx_value, tx_value, 1'b1);
    expected_rx = ref_model.pred_rx_word;

    apb_write(CDT_TX_DATA, tx_value);
    ref_model.predict_apb_write(CDT_TX_DATA, tx_value);

    ref_model.predict_tx_pop();

    poll_until_busy(ref_model);
    
    measure_consecutive_posedges(int'(div_a), period_before);
    
    apb_write(CDT_CLK_DIV, {16'b0, div_b});
    ref_model.predict_apb_write(CDT_CLK_DIV, {16'b0, div_b});
    
    measure_consecutive_posedges(int'(div_a), period_after);

    if (period_after < 0) begin
      $display("[SCOREBOARD_ERROR] R25: could not measure period after inject");
      ref_model.error_count++;
    end else if (period_after < exp_ns - CDT_PCLK_NS ||
                 period_after > exp_ns + CDT_PCLK_NS) begin
      $display("[SCOREBOARD_ERROR] R25 DIV latch: period=%0dns expected=%0dns",
               period_after, exp_ns);
      ref_model.error_count++;
    end else
      $display("[INFO] R25 DIV latch OK: period=%0dns matches div_a=%0d",
               period_after, div_a);

    poll_until_not_busy(ref_model);

    ref_model.predict_transfer_complete(expected_rx);
    ref_model.predict_cycle();

    apb_write(CDT_SS_CTRL, 32'h0);
    ref_model.predict_apb_write(CDT_SS_CTRL, 32'h0);
    apb_write(CDT_CTRL,    32'h0);
    ref_model.predict_apb_write(CDT_CTRL, 32'h0);
    
    coverage.sample_clk_div(div_a);
    repeat(4) @(posedge tb_top.PCLK);
  endtask

  static task run(ref spi_ref_model    ref_model,
                  ref spi_coverage_col coverage);

    $display("[INFO] clk_div_corner_test: starting");
    ref_model.reset();

    run_one_div(ref_model, coverage, 16'd0,    "div_zero");
    run_one_div(ref_model, coverage, 16'd1,    "div_one");
    run_one_div(ref_model, coverage, 16'd2,    "div_small_2");
    run_one_div(ref_model, coverage, 16'd3,    "div_small_3");
    run_one_div(ref_model, coverage, 16'd4,    "div_typical");
    run_one_div(ref_model, coverage, 16'd255,  "div_medium");
    run_one_div(ref_model, coverage, 16'd512,  "div_large");

    run_one_div(ref_model, coverage, 16'd1024, "div_very_big");
    run_one_div(ref_model, coverage, 16'd2000, "div_very_big_actual");

    run_r25_div_latch(ref_model, coverage, 16'd10, 16'd0);

    $display("[INFO] clk_div_corner_test: sampling div_max coverage bin (DIV=65535)");
    coverage.sample_clk_div(16'hFFFF);

    $display("[INFO] clk_div_corner_test: finished, errors=%0d",
             ref_model.error_count);
  endtask

endclass

`endif