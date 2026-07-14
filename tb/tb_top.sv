`timescale 1ns/1ps
`include "ref_model.sv"
`include "coverage.sv"
`include "stim_lib.sv"
`include "sanity_test.sv"
`include "width_coverage_test.sv"
`include "loopback_test.sv"
`include "mode_coverage_test.sv"
`include "clk_div_corner_test.sv"
`include "fifo_stress_test.sv"
`include "interrupt_test.sv"
`include "reg_access_test.sv"
`include "error_injection_test.sv"
`include "delay_transfer_test.sv"

module tb_top;

    bit PCLK = 0;
    always #5 PCLK = ~PCLK;

    bit PRESETn;

    apb_if apb (.pclk(PCLK), .presetn(PRESETn));
    spi_if spi (.pclk(PCLK));

    logic [1:0]  bfm_mode         = 2'b00;
    logic [31:0] bfm_pattern      = 32'hA5A5A5A5;
    logic        bfm_lsb_first    = 1'b0;
    logic [1:0]  bfm_width        = 2'b00;
    logic        bfm_transfer_done;

    dut_wrapper u_wrap (.apb(apb), .spi(spi));

    apb_master_bfm u_apb_bfm (.apb(apb.master));

    spi_slave_bfm  u_spi_bfm (
        .spi           (spi.slave),
        .mode          (bfm_mode),
        .miso_word     (bfm_pattern),
        .lsb_first     (bfm_lsb_first),
        .width         (bfm_width)
        
    );

    spi_ref_model    u_ref = new();
    spi_coverage_col u_cov = new();

    string testname;

    initial begin
        PRESETn = 0;
        #50;
        PRESETn = 1;

        if (!$value$plusargs("TESTNAME=%s", testname) &&
            !$value$plusargs("UVM_TESTNAME=%s", testname))
            testname = "sanity_test";

        $display("[INFO] Starting test: %s", testname);

        case (testname)

            "sanity_test":
                sanity_test::run(u_ref, u_cov);

            "loopback_test":
                loopback_test::run(u_ref, u_cov);

            "width_coverage_test":
                width_coverage_test::run(u_ref, u_cov);

            "mode_coverage_test":
                mode_coverage_test::run(u_ref, u_cov);

            "clk_div_corner_test":
                clk_div_corner_test::run(u_ref, u_cov);

            "fifo_stress_test":
                fifo_stress_test::run(u_ref, u_cov);

            "interrupt_test":
                interrupt_test::run(u_ref, u_cov);

            "reg_access_test":
                reg_access_test::run(u_ref, u_cov);

            "error_injection_test":
                error_injection_test::run(u_ref, u_cov);

            "delay_transfer_test":
                delay_transfer_test::run(u_ref, u_cov);

            "all": begin
               automatic string tests[10] = '{
                    "sanity_test",
                    "loopback_test",
                    "width_coverage_test",
                    "interrupt_test",
                    "mode_coverage_test",
                    "clk_div_corner_test",
                    "fifo_stress_test",
                    "reg_access_test",
                    "error_injection_test",
                    "delay_transfer_test"
                };
                foreach (tests[i]) begin
                    u_ref.reset();
                    case (tests[i])
                        "sanity_test": begin
                            sanity_test::run(u_ref, u_cov);
                            $display("SANITY IS COMPLETED");
                        end
                        "loopback_test": begin
                            loopback_test::run(u_ref, u_cov);
                            $display("LOOPBACK IS COMPLETED");
                        end
                        "width_coverage_test": begin
                            width_coverage_test::run(u_ref, u_cov);
                            $display("WIDTH COV IS COMPLETED");
                        end 
                        "interrupt_test": begin
                            interrupt_test::run(u_ref, u_cov);
                            $display("INTERRUPT TEST IS COMPLETED");
                        end 
                        "mode_coverage_test": begin
                            mode_coverage_test::run(u_ref, u_cov);
                            $display("MODE COV IS COMPLETED");
                        end
                        "clk_div_corner_test": begin
                            clk_div_corner_test::run(u_ref, u_cov);
                            $display("CLK DIV CORNER IS COMPLETED");
                        end
                        "fifo_stress_test": begin
                            fifo_stress_test::run(u_ref, u_cov);
                            $display("FIFO STRESS IS COMPLETED");
                        end
                        "reg_access_test": begin
                            reg_access_test::run(u_ref, u_cov);
                            $display("REG ACCESS IS COMPLETED");
                        end
                        "error_injection_test": begin
                            error_injection_test::run(u_ref, u_cov);
                            $display("ERROR INJECTION IS COMPLETED");
                        end
                        "delay_transfer_test": begin
                            delay_transfer_test::run(u_ref, u_cov);
                            $display("DELAY TRANSFER IS COMPLETED");
                        end
                        default: ;
                    endcase
                    if (u_ref.error_count == 0)
                        $display("[TEST_PASSED] %s", tests[i]);
                    else
                        $display("[TEST_FAILED] %s errors=%0d",
                                 tests[i], u_ref.error_count);
                end
            end

            default: begin
                $display("[TEST_FAILED] %s errors=1 (unknown test name)", testname);
                $finish;
            end

        endcase

        if (testname != "all") begin
            if (u_ref.error_count == 0)
                $display("[TEST_PASSED] %s", testname);
            else
                $display("[TEST_FAILED] %s errors=%0d",
                         testname, u_ref.error_count);
        end

        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("[TEST_FAILED] %s errors=1 (timeout)", testname);
        $finish;
    end

endmodule

bind tb_top.u_wrap.u_dut.u_regfile spi_regfile_sva u_regfile_sva (.*);
bind tb_top.u_wrap.u_dut.u_core    spi_core_sva    u_core_sva    (.*);
