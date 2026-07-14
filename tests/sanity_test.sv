`ifndef SANITY_TEST_SV
`define SANITY_TEST_SV
`include "ref_model.sv"
`include "stim_lib.sv"
`include "coverage.sv"


localparam [7:0] APBB_CTRL     = 8'h00;
localparam [7:0] APBB_STATUS   = 8'h04;
localparam [7:0] APBB_TX_DATA  = 8'h08;
localparam [7:0] APBB_RX_DATA  = 8'h0C;
localparam [7:0] APBB_CLK_DIV  = 8'h10;
localparam [7:0] APBB_SS_CTRL  = 8'h14;
localparam [7:0] APBB_INT_EN   = 8'h18;
localparam [7:0] APBB_INT_STAT = 8'h1C;
localparam [7:0] APBB_DELAY    = 8'h20;

class sanity_test;

    static task run(ref spi_ref_model    ref_model,
                    ref spi_coverage_col coverage
                    );

        bit [31:0] rd;
        bit [31:0] expected_rx;

        $display("[INFO] sanity_test: starting");

        tb_top.bfm_mode    = 2'b00;
        tb_top.bfm_pattern = 8'hA5;

        ref_model.predict_apb_write(APBB_CTRL,    32'h0000_0003);
        tb_top.u_apb_bfm.apb_write(APBB_CTRL,    32'h0000_0003);

        ref_model.predict_apb_write(APBB_CLK_DIV, 32'h0000_0004);
        tb_top.u_apb_bfm.apb_write(APBB_CLK_DIV, 32'h0000_0004);

        ref_model.predict_apb_write(APBB_INT_EN,  32'h0000_001F);
        tb_top.u_apb_bfm.apb_write(APBB_INT_EN,  32'h0000_001F);

        tb_top.u_apb_bfm.apb_read(APBB_STATUS, rd);
        ref_model.check_status(rd);
        $display("[INFO] sanity_test: pre-TX STATUS=0x%08h", rd);

        ref_model.predict_transfer(
            .tx_data     (32'h0000_005A),
            .miso_pattern({4{tb_top.bfm_pattern}}),
            .loopback    (1'b0)
        );
        
        expected_rx = ref_model.pred_rx_word;

        coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));

        ref_model.predict_apb_write(APBB_TX_DATA, 32'h0000_005A);
        tb_top.u_apb_bfm.apb_write(APBB_TX_DATA, 32'h0000_005A);

        ref_model.predict_tx_pop();

        ref_model.predict_apb_write(APBB_SS_CTRL, 32'h0000_0001);
        tb_top.u_apb_bfm.apb_write(APBB_SS_CTRL, 32'h0000_0001);

        repeat (500) begin
            tb_top.u_apb_bfm.apb_read(APBB_STATUS, rd);
            if (rd[0] == 1'b0) break;
        end

        tb_top.u_apb_bfm.apb_read(APBB_RX_DATA, rd);
        ref_model.check_rx(rd);
        $display("[INFO] sanity_test: RX_DATA=0x%08h", rd);

        ref_model.predict_transfer_complete(expected_rx);

        @(posedge tb_top.PCLK);
        #1;

        tb_top.u_apb_bfm.apb_read(APBB_INT_STAT, rd);
        ref_model.check_int_stat(rd);
        $display("[INFO] sanity_test: INT_STAT=0x%08h", rd);

        ref_model.predict_cycle();

        if (!rd[4])
            $display("[SCOREBOARD_ERROR] INT_STAT[4] TRANSFER_DONE not set");
        if (!rd[0])
            $display("[SCOREBOARD_ERROR] INT_STAT[0] TX_EMPTY not set");

        @(posedge tb_top.PCLK);
        ref_model.check_irq(tb_top.spi.irq);
        $display("[INFO] sanity_test: IRQ=%0b", tb_top.spi.irq);

        ref_model.predict_apb_write(APBB_INT_STAT, 32'h0000_001F);
        tb_top.u_apb_bfm.apb_write(APBB_INT_STAT, 32'h0000_001F);

        tb_top.u_apb_bfm.apb_read(APBB_INT_STAT, rd);
        ref_model.check_reg("INT_STAT_after_W1C", 32'h0, rd);

        @(posedge tb_top.PCLK);
        if (tb_top.spi.irq !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] IRQ still asserted after W1C clear");
            ref_model.error_count++;
        end

        ref_model.predict_apb_write(APBB_SS_CTRL, 32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(APBB_SS_CTRL, 32'h0000_0000);

        $display("[INFO] sanity_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // SANITY_TEST_SV
