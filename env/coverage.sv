`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    localparam int IRQ_COUNT = 5;
    localparam int FIFO_AW   = 3;

    bit [1:0]           cv_mode, cv_width;
    bit                 cv_lsb_first, cv_loopback, cv_busy, cv_transfer_done;
    bit [15:0]          cv_clk_div;
    bit [IRQ_COUNT-1:0] cv_int_stat, cv_int_en;
    bit [7:0]           cv_delay, cv_reg_addr_written, cv_reg_addr_read;
    bit [3:0]           cv_SS_n;
    bit [FIFO_AW:0]     cv_tx_count, cv_rx_count;

    covergroup cg_config;
        option.per_instance = 1;

        cp_mode  : coverpoint cv_mode       { bins modes[] = {[0:3]}; }
        cp_first : coverpoint cv_lsb_first { bins msb = {0}; bins lsb = {1}; }

        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        bins illegal_width = {2'b11};
        }

        cx_mode_width_order : cross cp_mode, cp_width, cp_first;
    endgroup

    covergroup cg_clk_div;
        option.per_instance = 1;

        cp_clk_div : coverpoint cv_clk_div {
            bins div_zero     = {0};
            bins div_one      = {1};
            bins div_small    = {[2:3]};
            bins div_typical  = {[4:15]};
            bins div_medium   = {[16:254]};
            bins div_255      = {255};
            bins div_large    = {[256:1023]};
            bins div_1024     = {1024};
            bins div_very_big = {[1025:16'hFFFE]};
            bins div_max      = {16'hFFFF};
        }
    endgroup

    covergroup cg_interrupt_sources;
        option.per_instance = 1;

        cp_tx_empty_irq : coverpoint cv_int_stat[0] { bins fired = {1}; }
        cp_rx_full_irq  : coverpoint cv_int_stat[1] { bins fired = {1}; }
        cp_tx_ovf_irq   : coverpoint cv_int_stat[2] { bins fired = {1}; }
        cp_rx_ovf_irq   : coverpoint cv_int_stat[3] { bins fired = {1}; }
        cp_done_irq     : coverpoint cv_int_stat[4] { bins fired = {1}; }
    endgroup

    covergroup cg_irq_w1c;
        option.per_instance = 1;

        cp_tx_empty_w1c : coverpoint cv_int_stat[0] { bins cleared = (1 => 0); }
        cp_rx_full_w1c  : coverpoint cv_int_stat[1] { bins cleared = (1 => 0); }
        cp_tx_ovf_w1c   : coverpoint cv_int_stat[2] { bins cleared = (1 => 0); }
        cp_rx_ovf_w1c   : coverpoint cv_int_stat[3] { bins cleared = (1 => 0); }
        cp_done_w1c     : coverpoint cv_int_stat[4] { bins cleared = (1 => 0); }
    endgroup

    covergroup cg_irq_masked;
        option.per_instance = 1;

        cp_tx_empty_masked : coverpoint {cv_int_stat[0],cv_int_en[0]} {
            bins fired_unmasked = {2'b11};
            bins fired_masked   = {2'b10};
        }

        cp_rx_full_masked : coverpoint {cv_int_stat[1],cv_int_en[1]} {
            bins fired_unmasked = {2'b11};
            bins fired_masked   = {2'b10};
        }

        cp_tx_ovf_masked : coverpoint {cv_int_stat[2],cv_int_en[2]} {
            bins fired_unmasked = {2'b11};
            bins fired_masked   = {2'b10};
        }

        cp_rx_ovf_masked : coverpoint {cv_int_stat[3],cv_int_en[3]} {
            bins fired_unmasked = {2'b11};
            bins fired_masked   = {2'b10};
        }

        cp_done_masked : coverpoint {cv_int_stat[4],cv_int_en[4]} {
            bins fired_unmasked = {2'b11};
            bins fired_masked   = {2'b10};
        }
    endgroup

    covergroup cg_delay;
        option.per_instance = 1;

        cp_delay : coverpoint cv_delay {
            bins delay_zero   = {0};
            bins delay_min    = {1};
            bins delay_small  = {[2:9]};
            bins delay_medium = {[10:127]};
            bins delay_large  = {[128:255]};
        }
    endgroup

    covergroup cg_ss_select;
        option.per_instance = 1;

        cp_ss_en : coverpoint cv_SS_n {
            bins slave0_only = {4'b1110};
            bins slave1_only = {4'b1101};
            bins slave2_only = {4'b1011};
            bins slave3_only = {4'b0111};
            bins no_slave    = {4'b1111};

            bins multi_slave[] = {
                4'b1100,4'b1010,4'b1001,
                4'b0110,4'b0101,4'b0011
            };
        }
    endgroup

    covergroup cg_loopback;
        option.per_instance = 1;

        cp_loopback : coverpoint cv_loopback {
            bins off = {0};
            bins on  = {1};
        }

        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        }

        cx_loopback_width : cross cp_loopback, cp_width;
    endgroup

    covergroup cg_tx_fifo;
        option.per_instance = 1;

        cp_tx_count : coverpoint cv_tx_count {
            bins tx_empty       = {0};
            bins tx_one_word    = {1};
            bins tx_partial     = {[2:3],[5:6]};
            bins tx_mid         = {4};
            bins tx_almost_full = {7};
            bins tx_full        = {8};
            bins empty_to_full  = (0 => 8);
            bins full_to_empty  = (8 => 0);
        }
    endgroup

    covergroup cg_rx_fifo;
        option.per_instance = 1;

        cp_rx_count : coverpoint cv_rx_count {
            bins rx_empty       = {0};
            bins rx_one_word    = {1};
            bins rx_partial     = {[2:6]};
            bins rx_almost_full = {7};
            bins rx_full        = {8};
            bins empty_to_full  = (0 => 8);
            bins full_to_empty  = (8 => 0);
        }
    endgroup

    covergroup cg_busy;
        option.per_instance = 1;

        cp_busy : coverpoint cv_busy {
            bins idle   = {0};
            bins active = {1};
        }
    endgroup

    covergroup cg_transfer_done;
        option.per_instance = 1;

        cp_done : coverpoint cv_transfer_done {
            bins done = {1};
        }
    endgroup

    covergroup cg_reg_written;
        option.per_instance = 1;

        cp_reg_written : coverpoint cv_reg_addr_written {
            bins ctrl      = {8'h00};
            bins tx_data   = {8'h08};
            bins clk_div   = {8'h10};
            bins ss_ctrl   = {8'h14};
            bins int_en    = {8'h18};
            bins int_stat  = {8'h1C};
            bins delay_reg = {8'h20};
        }
    endgroup

    covergroup cg_reg_read;
        option.per_instance = 1;

        cp_reg_read : coverpoint cv_reg_addr_read {
            bins ctrl      = {8'h00};
            bins status    = {8'h04};
            bins rx_data   = {8'h0C};
            bins clk_div   = {8'h10};
            bins ss_ctrl   = {8'h14};
            bins int_en    = {8'h18};
            bins int_stat  = {8'h1C};
            bins delay_reg = {8'h20};
        }
    endgroup

    covergroup cg_reset_values;
        option.per_instance = 1;

        cp_reset_read : coverpoint cv_reg_addr_read {
            bins ctrl_reset    = {8'h00};
            bins status_reset  = {8'h04};
            bins clkdiv_reset  = {8'h10};
            bins ssctrl_reset  = {8'h14};
            bins inten_reset   = {8'h18};
            bins intstat_reset = {8'h1C};
            bins delay_reset   = {8'h20};
        }
    endgroup

    function new();
        cg_config            = new();
        cg_clk_div           = new();
        cg_interrupt_sources = new();
        cg_irq_w1c           = new();
        cg_irq_masked        = new();
        cg_delay             = new();
        cg_ss_select         = new();
        cg_loopback          = new();
        cg_tx_fifo           = new();
        cg_rx_fifo           = new();
        cg_busy              = new();
        cg_transfer_done     = new();
        cg_reg_written       = new();
        cg_reg_read          = new();
        cg_reset_values      = new();
    endfunction

    task sample_config(input bit [1:0] mode,input bit lsb_first,input bit [1:0] width);
        cv_mode=mode; cv_lsb_first=lsb_first; cv_width=width; cg_config.sample();
    endtask

    task sample_clk_div(input bit [15:0] clk_div);
        cv_clk_div=clk_div; cg_clk_div.sample();
    endtask

    task sample_interrupt_sources(input bit [IRQ_COUNT-1:0] int_stat,input bit [IRQ_COUNT-1:0] int_en);
        cv_int_stat=int_stat; cv_int_en=int_en;
        cg_interrupt_sources.sample(); cg_irq_masked.sample();
    endtask

    task sample_irq_w1c(input bit [IRQ_COUNT-1:0] int_stat,input bit [IRQ_COUNT-1:0] int_en);
        cv_int_stat=int_stat; cv_int_en=int_en; cg_irq_w1c.sample();
    endtask

    task sample_delay(input bit [7:0] delay);
        cv_delay=delay; cg_delay.sample();
    endtask

    task sample_ss_en(input bit [3:0] SS_n);
        cv_SS_n=SS_n; cg_ss_select.sample();
    endtask

    task sample_loopback(input bit loopback,input bit [1:0] width);
        cv_loopback=loopback; cv_width=width; cg_loopback.sample();
    endtask

    task sample_tx_count(input bit [3:0] tx_count);
        cv_tx_count=tx_count; cg_tx_fifo.sample();
    endtask

    task sample_rx_count(input bit [3:0] rx_count);
        cv_rx_count=rx_count; cg_rx_fifo.sample();
    endtask

    task sample_busy(input bit busy);
        cv_busy=busy; cg_busy.sample();
    endtask

    task sample_transfer_done(input bit transfer_done);
        cv_transfer_done=transfer_done; cg_transfer_done.sample();
    endtask

    task sample_reg_write(input bit [7:0] addr);
        cv_reg_addr_written=addr; cg_reg_written.sample();
    endtask

    task sample_reg_read(input bit [7:0] addr);
        cv_reg_addr_read=addr;
        cg_reg_read.sample();
        cg_reset_values.sample();
    endtask

    task sample_reset_values();
        bit [31:0] rd;

        tb_top.u_apb_bfm.apb_read(8'h00, rd); cv_reg_addr_read=8'h00; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h04, rd); cv_reg_addr_read=8'h04; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h10, rd); cv_reg_addr_read=8'h10; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h14, rd); cv_reg_addr_read=8'h14; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h18, rd); cv_reg_addr_read=8'h18; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h1C, rd); cv_reg_addr_read=8'h1C; cg_reset_values.sample();
        tb_top.u_apb_bfm.apb_read(8'h20, rd); cv_reg_addr_read=8'h20; cg_reset_values.sample();
    endtask

endclass

`endif
