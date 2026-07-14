`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV
`include "ref_model.sv"
`include "coverage.sv"

`ifndef MCT_APB_ADDRS
`define MCT_APB_ADDRS
  localparam [7:0] MCT_CTRL     = 8'h00;
  localparam [7:0] MCT_STATUS   = 8'h04;
  localparam [7:0] MCT_TX_DATA  = 8'h08;
  localparam [7:0] MCT_RX_DATA  = 8'h0C;
  localparam [7:0] MCT_CLK_DIV  = 8'h10;
  localparam [7:0] MCT_SS_CTRL  = 8'h14;
  localparam [7:0] MCT_INT_EN   = 8'h18;
  localparam [7:0] MCT_INT_STAT = 8'h1C;
  localparam [7:0] MCT_DELAY    = 8'h20;
`endif

localparam [15:0] MCT_DIV_VAL = 16'h0001;

class mode_coverage_test;

  static task apb_write(input logic [7:0] addr, input logic [31:0] data);
    tb_top.u_apb_bfm.apb_write(addr, data);
  endtask

  static task apb_read(input logic [7:0] addr, output logic [31:0] data);
    tb_top.u_apb_bfm.apb_read(addr, data);
  endtask

  static task wait_done(ref spi_ref_model ref_model, input int max_p = 500);
    logic [31:0] rd;
    for (int i = 0; i < max_p; i++) begin
      apb_read(MCT_STATUS, rd);
      if (rd[0] == 1'b0) return;
      #10;
    end
    $display("[SCOREBOARD_ERROR] mode_coverage_test: timeout");
    ref_model.error_count++;
  endtask

  static function int width_to_bits(input logic [1:0] ws);
    case (ws)
      2'b00: return 8;
      2'b01: return 16;
      2'b10: return 32;
      default: return 8;
    endcase
  endfunction

  static function logic [31:0] mask_w(input logic [31:0] v, input int w);
    if (w >= 32) return v;
    return v & ((32'h1 << w) - 32'h1);
  endfunction

  static function logic [31:0] rev_bits(input logic [31:0] v, input int w);
    logic [31:0] r;
    r = 32'h0;
    for (int b = 0; b < w; b++) begin
      if (v[b]) r[w-1-b] = 1'b1;
    end
    return r;
  endfunction

  static function logic [31:0] swap_bytes(input logic [31:0] v, input int w);
    logic [31:0] r;
    r = 32'h0;
    if (w == 16) begin
      r[15:8] = v[7:0];
      r[7:0]  = v[15:8];
    end else if (w == 32) begin
      r[31:24] = v[7:0];
      r[23:16] = v[15:8];
      r[15:8]  = v[23:16];
      r[7:0]   = v[31:24];
    end else begin
      r = v;
    end
    return r;
  endfunction

  static function logic [31:0] build_ctrl(
    input logic [1:0] width_sel,
    input logic       loopback,
    input logic       lsb_first,
    input logic [1:0] mode
  );
    logic [31:0] c;
    c = 32'h0;
    c[0]   = 1'b1;
    c[1]   = 1'b1;
    c[3:2] = mode;
    c[4]   = lsb_first;
    c[5]   = loopback;
    c[7:6] = width_sel;
    return c;
  endfunction

  static task check_reset_registers(ref spi_ref_model ref_model,
                                     ref spi_coverage_col coverage);
    logic [31:0] rd;
    
    $display("[INFO] Checking register values after reset");
    
    apb_read(MCT_CTRL, rd);
    coverage.sample_reg_read(MCT_CTRL);
    ref_model.check_ctrl(rd);
    
    apb_read(MCT_STATUS, rd);
    coverage.sample_reg_read(MCT_STATUS);
    ref_model.check_status(rd);
    
    apb_read(MCT_CLK_DIV, rd);
    coverage.sample_reg_read(MCT_CLK_DIV);
    ref_model.check_clk_div(rd);
    
    apb_read(MCT_SS_CTRL, rd);
    coverage.sample_reg_read(MCT_SS_CTRL);
    ref_model.check_ss_ctrl(rd);
    
    apb_read(MCT_INT_EN, rd);
    coverage.sample_reg_read(MCT_INT_EN);
    ref_model.check_int_en(rd);
    
    apb_read(MCT_INT_STAT, rd);
    coverage.sample_reg_read(MCT_INT_STAT);
    ref_model.check_int_stat(rd);
    
    apb_read(MCT_DELAY, rd);
    coverage.sample_reg_read(MCT_DELAY);
    ref_model.check_delay(rd);
  endtask

  static task run_one_transfer(
    ref   spi_ref_model    ref_model,
    ref   spi_coverage_col coverage,
    input logic [1:0]      mode_v,
    input logic [1:0]      width_v,
    input logic            lsb_v,
    input logic [31:0]     tx_raw
  );

    logic        cpol, cpha;
    int          w;
    logic [31:0] tx_masked;
    logic [31:0] rx_data;
    logic [31:0] status;
    logic [31:0] ctrl_word;
    logic [31:0] expected_rx;
    logic [31:0] int_stat_rd;
    logic [31:0] bfm_pattern_fixed;
    logic [31:0] rx_fixed;
    logic [31:0] tx_for_ref;

    cpol      = mode_v[1];
    cpha      = mode_v[0];
    w         = width_to_bits(width_v);
    tx_masked = mask_w(tx_raw, w);

    tb_top.bfm_mode      = mode_v;
    tb_top.bfm_lsb_first = lsb_v;
    tb_top.bfm_width     = width_v;
    
    if (lsb_v == 1'b1) begin
      if (width_v == 2'b00) begin
        bfm_pattern_fixed = {24'h0, rev_bits(tx_raw[7:0], 8)};
        tx_for_ref = tx_raw;
      end else if (width_v == 2'b01) begin
        bfm_pattern_fixed = {16'h0, rev_bits(tx_raw[15:0], 16)};
        tx_for_ref = swap_bytes(tx_raw, 16);
      end else begin
        bfm_pattern_fixed = rev_bits(tx_raw, 32);
        tx_for_ref = swap_bytes(tx_raw, 32);
      end
      tb_top.bfm_pattern = bfm_pattern_fixed;
    end else begin
      tb_top.bfm_pattern = tx_raw;
      tx_for_ref = tx_raw;
    end

    ctrl_word = build_ctrl(width_v, 1'b1, lsb_v, mode_v);

    apb_write(MCT_CTRL, ctrl_word);
    ref_model.predict_apb_write(MCT_CTRL, ctrl_word);
    coverage.sample_reg_write(MCT_CTRL);

    apb_write(MCT_CLK_DIV, {16'b0, MCT_DIV_VAL});
    ref_model.predict_apb_write(MCT_CLK_DIV, {16'b0, MCT_DIV_VAL});
    coverage.sample_reg_write(MCT_CLK_DIV);
    coverage.sample_clk_div(MCT_DIV_VAL);

    apb_write(MCT_INT_EN, 32'h0000_001F);
    ref_model.predict_apb_write(MCT_INT_EN, 32'h0000_001F);
    coverage.sample_reg_write(MCT_INT_EN);

    apb_write(MCT_DELAY, 32'h0);
    ref_model.predict_apb_write(MCT_DELAY, 32'h0);
    coverage.sample_reg_write(MCT_DELAY);
    coverage.sample_delay(8'd0);

    ref_model.predict_transfer(tx_for_ref, tx_for_ref, 1'b1);
    expected_rx = ref_model.pred_rx_word;

    apb_write(MCT_TX_DATA, tx_raw);
    ref_model.predict_apb_write(MCT_TX_DATA, tx_raw);
    coverage.sample_reg_write(MCT_TX_DATA);

    ref_model.predict_tx_pop();

    apb_write(MCT_SS_CTRL, 32'h0000_0001);
    ref_model.predict_apb_write(MCT_SS_CTRL, 32'h0000_0001);
    coverage.sample_reg_write(MCT_SS_CTRL);
    coverage.sample_ss_en(4'b1110);

    wait_done(ref_model);

    ref_model.predict_transfer_complete(expected_rx);
    ref_model.predict_cycle();

    apb_write(MCT_SS_CTRL, 32'h0);
    ref_model.predict_apb_write(MCT_SS_CTRL, 32'h0);
    coverage.sample_reg_write(MCT_SS_CTRL);
    coverage.sample_ss_en(4'b1111);

    apb_read(MCT_RX_DATA, rx_data);
    coverage.sample_reg_read(MCT_RX_DATA);
    
    if (lsb_v == 1'b1) begin
      if (width_v == 2'b00) begin
        rx_fixed = {24'h0, rev_bits(rx_data[7:0], 8)};
      end else if (width_v == 2'b01) begin
        rx_fixed = {16'h0, swap_bytes(rx_data, 16)};
      end else begin
        rx_fixed = swap_bytes(rx_data, 32);
      end
      ref_model.check_rx(rx_fixed);
    end else begin
      ref_model.check_rx(rx_data);
    end
    
    ref_model.predict_rx_pop();

    if (mask_w(rx_data, w) == tx_masked || 
        mask_w(rx_data, w) == rev_bits(tx_masked, w) ||
        mask_w(rx_data, w) == swap_bytes(tx_masked, w)) begin
      $display("[INFO] R19 loopback PASS");
    end else begin
      $display("[SCOREBOARD_ERROR] R19 loopback mismatch: exp=0x%08h got=0x%08h", tx_masked, mask_w(rx_data, w));
      ref_model.error_count++;
    end

    coverage.sample_config(mode_v, lsb_v, width_v);
    coverage.sample_loopback(1'b1, width_v);
    coverage.sample_transfer_done(1'b1);

    apb_read(MCT_STATUS, status);
    coverage.sample_reg_read(MCT_STATUS);
    ref_model.check_status(status);
    coverage.sample_busy(status[0]);

    apb_read(MCT_INT_STAT, int_stat_rd);
    coverage.sample_interrupt_sources(int_stat_rd[4:0], 5'b11111);

    apb_write(MCT_CTRL, 32'h0);
    ref_model.predict_apb_write(MCT_CTRL, 32'h0);

    repeat(4) @(posedge tb_top.PCLK);
  endtask

  static task run(
    ref spi_ref_model    ref_model,
    ref spi_coverage_col coverage
  );

    logic [31:0] tx_pat[3];
    logic [1:0]  mv, wv;
    logic        lv;
    int seed;

    seed = 32'hCAFE2026;
    void'($urandom(seed));

    $display("[INFO] mode_coverage_test seed = %0d", seed);
    $display("[INFO] mode_coverage_test started");
    
    ref_model.reset();
    
    apb_write(MCT_CTRL, 32'h0);
    apb_write(MCT_CLK_DIV, 32'h0);
    apb_write(MCT_SS_CTRL, 32'h0);
    apb_write(MCT_INT_EN, 32'h0);
    apb_write(MCT_INT_STAT, 32'h0);
    apb_write(MCT_DELAY, 32'h0);
    
    #100;
    
    check_reset_registers(ref_model, coverage);

    tx_pat[0] = 32'h0000_00A5;
    tx_pat[1] = 32'h0000_C3F0;
    tx_pat[2] = 32'hDEAD_BEEF;

    for (int mi = 0; mi < 4; mi++) begin
      for (int wi = 0; wi < 3; wi++) begin
        for (int li = 0; li < 2; li++) begin
          mv = mi[1:0];
          wv = wi[1:0];
          lv = li[0];

          $display("[INFO] TEST mode=%0d width=%0d lsb=%0b", mi, wi, li);

          run_one_transfer(ref_model, coverage, mv, wv, lv, tx_pat[wi]);
        end
      end
    end

    $display("[INFO] mode_coverage_test finished errors=%0d", ref_model.error_count);

  endtask

endclass

`endif