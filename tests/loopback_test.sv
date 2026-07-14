`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV
`include "ref_model.sv"    
`include "coverage.sv"

`ifndef LB_APB_ADDRS
`define LB_APB_ADDRS
localparam [7:0] LB_CTRL_ADD    = 8'h00;
localparam [7:0] LB_STATUS_ADD  = 8'h04;
localparam [7:0] LB_TX_DATA_ADD = 8'h08;
localparam [7:0] LB_RX_DATA_ADD = 8'h0C;
localparam [7:0] LB_CLK_DIV_ADD = 8'h10;
localparam [7:0] LB_SS_CTRL_ADD = 8'h14;
localparam [7:0] LB_INT_EN_ADD  = 8'h18;
localparam [7:0] LB_INT_STAT_ADD = 8'h1C;
localparam [7:0] LB_DELAY_ADD    = 8'h20;
`endif

class loopback_test;

    static task do_transfer(
        ref spi_ref_model    ref_model,
        ref spi_coverage_col coverage,
        input bit [1:0]  width,
        input bit        loopback,
        input bit [31:0] tx_data,
        input bit [31:0] miso_pat
    );

        bit [31:0] rd;
        bit [31:0] ctrl_word = 32'h0;
        bit [31:0] status_rd;
        bit [31:0] ctrl_rd;
        bit [31:0] expected_rx;

        $display("[DBG] Setting BFM signals...");
        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_pattern   = miso_pat;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_width     = width;

        coverage.sample_config   (2'b00, 1'b0, width);
        coverage.sample_loopback (loopback, width);
        coverage.sample_clk_div  (16'd4);
        coverage.sample_delay    (8'd0);
        coverage.sample_ss_en    (4'b1110);

        coverage.sample_tx_count (4'd0);
        coverage.sample_rx_count (4'd0);
        
        ctrl_word[0]   = 1'b1;
        ctrl_word[1]   = 1'b1;
        ctrl_word[3:2] = 2'b00;
        ctrl_word[4]   = 1'b0;
        ctrl_word[5]   = loopback;
        ctrl_word[7:6] = width;

        $display("[DBG] Writing CTRL=0x%08H", ctrl_word);
        tb_top.u_apb_bfm.apb_write(LB_CTRL_ADD, ctrl_word);
        ref_model.predict_apb_write(LB_CTRL_ADD, ctrl_word);
        tb_top.u_apb_bfm.apb_read(LB_CTRL_ADD, ctrl_rd);
        ref_model.check_ctrl(ctrl_rd);
        coverage.sample_reg_write(LB_CTRL_ADD);

        $display("[DBG] Writing CLK_DIV");
        tb_top.u_apb_bfm.apb_write(LB_CLK_DIV_ADD, 32'h0000_0004);
        ref_model.predict_apb_write(LB_CLK_DIV_ADD, 32'h0000_0004);   
        coverage.sample_reg_write(LB_CLK_DIV_ADD);

        $display("[DBG] Writing DELAY");
        tb_top.u_apb_bfm.apb_write(LB_DELAY_ADD, 32'h0000_0000);
        ref_model.predict_apb_write(LB_DELAY_ADD, 32'h0000_0000);
        coverage.sample_reg_write(LB_DELAY_ADD);

        $display("[DBG] Writing INT_EN");
        tb_top.u_apb_bfm.apb_write(LB_INT_EN_ADD, 32'h0000_001F);
        ref_model.predict_apb_write(LB_INT_EN_ADD, 32'h0000_001F);
        coverage.sample_reg_write(LB_INT_EN_ADD);

        ref_model.predict_transfer(tx_data, miso_pat, loopback);
        expected_rx = ref_model.pred_rx_word;

        $display("[DBG] Writing TX_DATA=0x%08H", tx_data);
        tb_top.u_apb_bfm.apb_write(LB_TX_DATA_ADD, tx_data);
        ref_model.predict_apb_write(LB_TX_DATA_ADD, tx_data);
        coverage.sample_reg_write(LB_TX_DATA_ADD);
        coverage.sample_tx_count(4'd1);

        $display("[DBG] Writing SS_CTRL=1 (assert SS)");
        tb_top.u_apb_bfm.apb_write(LB_SS_CTRL_ADD, 32'h0000_0001);
        ref_model.predict_apb_write(LB_SS_CTRL_ADD, 32'h0000_0001);
        coverage.sample_reg_write(LB_SS_CTRL_ADD);
        coverage.sample_busy(1'b1);

        $display("[DBG] Waiting for transfer_done...");

        repeat (2000) begin
            tb_top.u_apb_bfm.apb_read(LB_STATUS_ADD, rd);
            if (rd[0] == 1'b0) begin
                $display("[DBG] transfer_done received!");
                break;
            end
        end
        if (rd[0] == 1'b1) begin
                $display("timeout loopback");
            end

        ref_model.predict_tx_pop();
        ref_model.predict_transfer_complete(expected_rx);
    
    
        tb_top.u_apb_bfm.apb_write(LB_SS_CTRL_ADD, 32'h0000_0000);
        ref_model.predict_apb_write(LB_SS_CTRL_ADD, 32'h0000_0000);
        coverage.sample_reg_write(LB_SS_CTRL_ADD);
        coverage.sample_busy         (1'b0);
        coverage.sample_transfer_done(1'b1);
        coverage.sample_rx_count(4'd1);
        
        tb_top.u_apb_bfm.apb_read(LB_INT_STAT_ADD, status_rd);
        ref_model.check_int_stat(status_rd);

        tb_top.u_apb_bfm.apb_write(LB_INT_STAT_ADD, status_rd);
        ref_model.predict_apb_write(LB_INT_STAT_ADD, status_rd);

        tb_top.u_apb_bfm.apb_read(LB_RX_DATA_ADD, rd);
        coverage.sample_reg_read(LB_RX_DATA_ADD);
        
        
        ref_model.check_rx(rd);
        ref_model.predict_rx_pop();

        tb_top.u_apb_bfm.apb_read(LB_STATUS_ADD, status_rd);
        ref_model.check_status(status_rd);

        $display("[LOOPBACK] LOOPBACK=%0d WIDTH=%0d TX=0x%08H RX=0x%08H MISO=0x%08H", 
                 loopback, width, tx_data, rd, miso_pat);

    endtask

    static task run(ref spi_ref_model u_ref, ref spi_coverage_col u_cov);
        
        $display("[INFO] loopback_test: starting");
        
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b00),
            .loopback  (1'b0),
            .tx_data   (32'h0000_0078),
            .miso_pat  (32'h0000_00BE)
        );
           
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b00),
            .loopback  (1'b1),
            .tx_data   (32'h0000_0078),
            .miso_pat  (32'h0000_00BE)
        );
            
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b01),
            .loopback  (1'b0),
            .tx_data   (32'h0000_5678),
            .miso_pat  (32'h0000_BEBE)
        );
           
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b01),
            .loopback  (1'b1),
            .tx_data   (32'h0000_5678),
            .miso_pat  (32'h0000_BEBE)
        );
            
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b10),
            .loopback  (1'b0),
            .tx_data   (32'h1234_5678),
            .miso_pat  (32'hBEBE_BEBE)
        );
            
        do_transfer(
            .ref_model (u_ref),
            .coverage  (u_cov),
            .width     (2'b10),
            .loopback  (1'b1),
            .tx_data   (32'h1234_5678),
            .miso_pat  (32'hBEBE_BEBE)
        );

        $display("[INFO] loopback_test: finished, errors=%0d", u_ref.error_count);

    endtask

endclass

`endif