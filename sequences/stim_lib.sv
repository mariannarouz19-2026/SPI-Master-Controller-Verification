// =============================================================================
// stim_lib.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Reusable randomisable transaction classes. Tests `new` these, call
// `randomize()`, and drive the resulting fields through the APB master BFM.
//
// NOTE: The scaffold only defines a single spi_txn class; students should
// add per-test variants as their coverage goals require.
// =============================================================================

`ifndef SPI_STIM_LIB_SV
`define SPI_STIM_LIB_SV

class spi_txn;
    rand bit [1:0]  mode;       // {CPOL, CPHA}
    rand bit        lsb_first;
    rand bit [1:0]  width;      // 00=8, 01=16, 10=32
    rand bit [15:0] clk_div;
    rand bit [7:0]  delay_cfg;
    rand bit [31:0] tx_data;
    rand bit        loopback;

    constraint c_width_legal  { width inside {[0:2]}; }
    constraint c_clk_div_sane { clk_div inside {[0:2048]}; }
    constraint c_delay_sane   { delay_cfg inside {[0:31]}; }

    function string sprint();
        return $sformatf("mode=%0d lsb=%0b width=%0d div=%0d delay=%0d tx=0x%08h lb=%0b",
                         mode, lsb_first, width, clk_div, delay_cfg, tx_data, loopback);
    endfunction
endclass

class reg_acc_txn;
    // Randomizable register values for comprehensive coverage
    rand bit [15:0] clk_div;        // CLK_DIV register value
    rand bit [7:0]  delay_cfg;      // DELAY register value
    rand bit [7:0]  ss_ctrl;        // SS_CTRL register value (4-bit select)
    rand bit [4:0]  int_en;         // INT_EN register value (5 interrupt bits)
    rand bit [7:0]  ctrl_test_val;  // CTRL register test value
    rand bit [31:0] tx_data;

    constraint c_clk_div_sane    { clk_div inside {[16'd1:16'd1024]}; }
    constraint c_delay_sane      { delay_cfg inside {[8'd0:8'd31]}; }
    constraint c_ss_ctrl_valid   { ss_ctrl inside {[8'd0:8'd15]}; }  // 4-bit slave select
    constraint c_int_en_valid    { int_en inside {[5'h0:5'h1F]}; }
    constraint c_ctrl_valid      { ctrl_test_val inside {[8'h0:8'hFF]}; }

    function string sprint();
        return $sformatf("clk_div=%0d delay=%0d ss_ctrl=0x%02h int_en=0x%02h ctrl=0x%02h",
                         clk_div, delay_cfg, ss_ctrl, int_en, ctrl_test_val);
    endfunction
endclass

class irq_txn;
    rand bit [3:0]  clk_div;
    rand bit [7:0]  tx_data;
    rand bit [7:0]  fill_data;

    constraint c_clk_div_sane { clk_div inside {[1:16]}; }

    function string sprint();
        return $sformatf("clk_div=%0d tx_data=0x%02h fill_data=0x%02h",
                         clk_div, tx_data, fill_data);
    endfunction
endclass

class error_txn;
    // Randomizable register values for error injection test coverage
    rand bit [15:0] clk_div;        // CLK_DIV register value
    rand bit [7:0]  delay_cfg;      // DELAY register value
    rand bit [7:0]  ss_ctrl;        // SS_CTRL register value (4-bit select)
    rand bit [7:0] tx_data;

    constraint c_clk_div_sane    { clk_div inside {[16'd1:16'd1024]}; }
    constraint c_delay_sane      { delay_cfg inside {[8'd0:8'd31]}; }
    constraint c_ss_ctrl_valid   { ss_ctrl inside {[8'd0:8'd15]}; }

    function string sprint();
        return $sformatf("clk_div=%0d delay=%0d ss_ctrl=0x%02h",
                         clk_div, delay_cfg, ss_ctrl);
    endfunction
endclass

// Subclass for fifo_stress_test 
class fifo_stress_txn extends spi_txn;

    rand int unsigned burst_count;

    constraint c_fifo_config {
        mode      == 2'b00;   // Mode 0
        width     == 2'b00;   // 8-bit
        lsb_first == 1'b0;    // MSB-first
        loopback  == 1'b1;   
    }

    constraint c_burst {
        burst_count inside {[1:8]};
    }

    constraint c_burst_bias {
        burst_count dist {
            [1:3] := 20,
            [4:6] := 35,
            [7:8] := 45
        };
    }

    // Keep divider small so simulation does not take too long
    constraint c_fifo_clk_div {
        clk_div inside {[1:8]};
    }

    // No delay in this FIFO test so that debugging is easier
    constraint c_fifo_delay {
        delay_cfg == 0;
    }

endclass


// Subclass for clk_div_corner_test
class clk_div_corner_txn extends spi_txn;

  // Override parent's sane constraint by disabling it
  constraint c_clk_div_sane { clk_div dist {
    0           := 25,   // minimum — SCLK = PCLK/2
    1           := 25,   // next step
    [2:10]      := 25,   // small values
    [1024:2048] := 25    // large values — slow SCLK
  };}
endclass


// Subclass for delay_transfer_test
class delay_txn extends spi_txn;

  // Override parent's delay constraint
  constraint c_delay_sane { delay_cfg dist {
    0          := 10,   // no delay baseline
    1          := 10,   // smallest non-zero delay
    [2:31]     := 25,   // small/medium delays
    [32:127]   := 20,   // larger delays
    [128:254]  := 25,   // large delays
    255        := 10    // maximum delay
  };}

endclass

`endif // SPI_STIM_LIB_SV

