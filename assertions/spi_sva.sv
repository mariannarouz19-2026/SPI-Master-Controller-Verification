`timescale 1ns/1ps

module spi_regfile_sva (
    input logic        PCLK,
    input logic        PRESETn,
    input logic        PSEL,
    input logic        PENABLE,
    input logic        PWRITE,
    input logic [7:0]  PADDR,
    input logic [31:0] PWDATA,
    input logic [31:0] PRDATA,
    input logic        PREADY,
    input logic        PSLVERR,
    input logic        IRQ,
    input logic [4:0]  int_stat,
    input logic [4:0]  int_en,
    input logic        tx_push_dropped,
    input logic        rx_push_valid,
    input logic        rx_full_w,
    input logic [3:0]  rx_count
);

    localparam integer IDX_TX_OVF = 2;
    localparam integer IDX_RX_OVF = 3;
    localparam [7:0] OFF_INT_STAT = 8'h1C;

    property p_setup_then_access;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE) |=> (PSEL && PENABLE);
    endproperty
    APB_1_SETUP_THEN_ACCESS:
    assert property (p_setup_then_access)
    else $display("[ASSERTION_ERROR] APB_1: SETUP not followed by ACCESS @%0t", $time);

    property p_apb_penable_requires_psel;
        @(posedge PCLK) disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty
    APB_2_PENABLE_NEEDS_PSEL:
    assert property (p_apb_penable_requires_psel)
    else $display("[ASSERTION_ERROR] APB_2: PENABLE=1 while PSEL=0 @%0t", $time);

    property p_apb_addr_ctrl_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE) |=> ($stable(PADDR) && $stable(PWRITE));
    endproperty
    APB_3a_ADDR_CTRL_STABLE:
    assert property (p_apb_addr_ctrl_stable)
    else $display("[ASSERTION_ERROR] APB_3a: PADDR or PWRITE changed @%0t", $time);

    property p_apb_wdata_stable_on_write;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE && PWRITE) |=> $stable(PWDATA);
    endproperty
    APB_3b_WDATA_STABLE_ON_WRITE:
    assert property (p_apb_wdata_stable_on_write)
    else $display("[ASSERTION_ERROR] APB_3b: PWDATA changed on write @%0t", $time);

    property p_prdata_reserved_is_zero;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY && !PWRITE && (PADDR >= 8'h24))
        |-> (PRDATA == 32'h0);
    endproperty
    APB_4a_PRDATA_RESERVED_ZERO:
    assert property (p_prdata_reserved_is_zero)
    else $display("[ASSERTION_ERROR] APB_4a: Reserved address read non-zero @%0t", $time);

    property p_prdata_wo_reg_is_zero;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY && !PWRITE && (PADDR == 8'h08))
        |-> (PRDATA == 32'h0);
    endproperty
    APB_4b_PRDATA_WO_REG_ZERO:
    assert property (p_prdata_wo_reg_is_zero)
    else $display("[ASSERTION_ERROR] APB_4b: TX_DATA read returned non-zero @%0t", $time);

    property p_pready_always_1;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE) |-> PREADY;
    endproperty
    APB_5_PREADY_ALWAYS_1:
    assert property (p_pready_always_1)
    else $display("[ASSERTION_ERROR] APB_5: PREADY=0 during ACCESS @%0t", $time);

    property p_pslverr_always_0;
        @(posedge PCLK) disable iff (!PRESETn)
        !PSLVERR;
    endproperty
    APB_6_PSLVERR_ALWAYS_0:
    assert property (p_pslverr_always_0)
    else $display("[ASSERTION_ERROR] APB_6: PSLVERR asserted @%0t", $time);

    property p_tx_ovf_flag_sets_after_drop;
        @(posedge PCLK) disable iff (!PRESETn)
        tx_push_dropped |=> int_stat[IDX_TX_OVF];
    endproperty
    IRQ_1_TX_OVF_SET_ON_OVERFLOW:
    assert property (p_tx_ovf_flag_sets_after_drop)
    else $display("[ASSERTION_ERROR] IRQ_1: TX_OVF not set after overflow @%0t", $time);

    property p_irq_equation;
        @(posedge PCLK) disable iff (!PRESETn)
        IRQ == |(int_stat & int_en);
    endproperty
    IRQ_2_IRQ_EQUATION:
    assert property (p_irq_equation)
    else $display("[ASSERTION_ERROR] IRQ_2: IRQ equation mismatch @%0t", $time);

    property p_int_stat_sticky_0;
        @(posedge PCLK) disable iff (!PRESETn)
        (int_stat[0] && !(PSEL && PENABLE && PWRITE && PADDR == OFF_INT_STAT && PWDATA[0]))
        |=> int_stat[0];
    endproperty
    IRQ_3a_TX_EMPTY_STICKY:
    assert property (p_int_stat_sticky_0)
    else $display("[ASSERTION_ERROR] IRQ_3a: TX_EMPTY cleared without W1C @%0t", $time);

    property p_int_stat_sticky_1;
        @(posedge PCLK) disable iff (!PRESETn)
        (int_stat[1] && !(PSEL && PENABLE && PWRITE && PADDR == OFF_INT_STAT && PWDATA[1]))
        |=> int_stat[1];
    endproperty
    IRQ_3b_RX_FULL_STICKY:
    assert property (p_int_stat_sticky_1)
    else $display("[ASSERTION_ERROR] IRQ_3b: RX_FULL cleared without W1C @%0t", $time);

    property p_int_stat_sticky_2;
        @(posedge PCLK) disable iff (!PRESETn)
        (int_stat[2] && !(PSEL && PENABLE && PWRITE && PADDR == OFF_INT_STAT && PWDATA[2]))
        |=> int_stat[2];
    endproperty
    IRQ_3c_TX_OVF_STICKY:
    assert property (p_int_stat_sticky_2)
    else $display("[ASSERTION_ERROR] IRQ_3c: TX_OVF cleared without W1C @%0t", $time);

    property p_int_stat_sticky_3;
        @(posedge PCLK) disable iff (!PRESETn)
        (int_stat[3] && !(PSEL && PENABLE && PWRITE && PADDR == OFF_INT_STAT && PWDATA[3]))
        |=> int_stat[3];
    endproperty
    IRQ_3d_RX_OVF_STICKY:
    assert property (p_int_stat_sticky_3)
    else $display("[ASSERTION_ERROR] IRQ_3d: RX_OVF cleared without W1C @%0t", $time);

    property p_int_stat_sticky_4;
        @(posedge PCLK) disable iff (!PRESETn)
        (int_stat[4] && !(PSEL && PENABLE && PWRITE && PADDR == OFF_INT_STAT && PWDATA[4]))
        |=> int_stat[4];
    endproperty
    IRQ_3e_DONE_STICKY:
    assert property (p_int_stat_sticky_4)
    else $display("[ASSERTION_ERROR] IRQ_3e: TRANSFER_DONE cleared without W1C @%0t", $time);

    property p_int_stat_zero_after_reset;
        @(posedge PCLK) disable iff (!PRESETn)
        $rose(PRESETn) |-> (int_stat == 5'b0);
    endproperty
    IRQ_4_INT_STAT_ZERO_AFTER_RESET:
    assert property (p_int_stat_zero_after_reset)
    else $display("[ASSERTION_ERROR] IRQ_4: INT_STAT non-zero after reset @%0t", $time);

    property p_rx_count_bounded;
        @(posedge PCLK) disable iff (!PRESETn)
        rx_count <= 4'd8;
    endproperty
    FIFO_2_RX_COUNT_BOUNDED:
    assert property (p_rx_count_bounded)
    else $display("[ASSERTION_ERROR] FIFO_2: RX count=%0d exceeds 8 @%0t", rx_count, $time);

    property p_rx_ovf_flag_sets_on_full_push;
        @(posedge PCLK) disable iff (!PRESETn)
        (rx_push_valid && rx_full_w) |=> int_stat[IDX_RX_OVF];
    endproperty
    FIFO_3_RX_OVF_SET_ON_OVERFLOW:
    assert property (p_rx_ovf_flag_sets_on_full_push)
    else $display("[ASSERTION_ERROR] FIFO_3: RX_OVF not set on overflow @%0t", $time);

endmodule


module spi_core_sva (
    input logic        PCLK,
    input logic        PRESETn,
    input logic [1:0]  cfg_mode,
    input logic [3:0]  ss_n_drive,
    input logic        tx_pop,
    input logic        transfer_done_pulse,
    input logic        busy,
    input logic        SCLK,
    input logic        MOSI,
    input logic [1:0]  xfer_mode,
    input logic [1:0]  state
);

    localparam logic [1:0] S_IDLE = 2'd0;

    property p_sclk_idle_polarity;
        @(posedge PCLK) disable iff (!PRESETn)
        (!busy && $past(!busy) && $stable(cfg_mode[1])) |-> (SCLK == cfg_mode[1]);
    endproperty
    SPI_1_SCLK_IDLE_POLARITY:
    assert property (p_sclk_idle_polarity)
    else $display("[ASSERTION_ERROR] SPI_1: SCLK idle polarity mismatch @%0t", $time);

    property p_mosi_stable_on_rising_sample;
        @(posedge PCLK) disable iff (!PRESETn)
        (busy && $rose(SCLK) && (xfer_mode[1] == xfer_mode[0])) |-> $stable(MOSI);
    endproperty
    SPI_2A_MOSI_STABLE_RISING_SAMPLE:
    assert property (p_mosi_stable_on_rising_sample)
    else $display("[ASSERTION_ERROR] SPI_2A: MOSI changed on rising sample edge @%0t", $time);

    property p_mosi_stable_on_falling_sample;
        @(posedge PCLK) disable iff (!PRESETn)
        (busy && $fell(SCLK) && (xfer_mode[1] != xfer_mode[0])) |-> $stable(MOSI);
    endproperty
    SPI_2B_MOSI_STABLE_FALLING_SAMPLE:
    assert property (p_mosi_stable_on_falling_sample)
    else $display("[ASSERTION_ERROR] SPI_2B: MOSI changed on falling sample edge @%0t", $time);

    property p_transfer_starts_with_ss_asserted;
        @(posedge PCLK) disable iff (!PRESETn)
        $rose(busy) |-> (ss_n_drive != 4'hF);
    endproperty
    SPI_3_START_REQUIRES_SS_ASSERTED:
    assert property (p_transfer_starts_with_ss_asserted)
    else $display("[ASSERTION_ERROR] SPI_3: Transfer started with SS_n deasserted @%0t", $time);

    property p_tx_pop_is_one_cycle_pulse;
        @(posedge PCLK) disable iff (!PRESETn)
        tx_pop |=> !tx_pop;
    endproperty
    SPI_5_TX_POP_ONE_CYCLE_PULSE:
    assert property (p_tx_pop_is_one_cycle_pulse)
    else $display("[ASSERTION_ERROR] SPI_5: tx_pop held high >1 cycle @%0t", $time);

    property p_done_pulse_one_cycle;
        @(posedge PCLK) disable iff (!PRESETn)
        transfer_done_pulse |=> !transfer_done_pulse;
    endproperty
    SPI_6_DONE_PULSE_ONE_CYCLE:
    assert property (p_done_pulse_one_cycle)
    else $display("[ASSERTION_ERROR] SPI_6: transfer_done_pulse held high >1 cycle @%0t", $time);

endmodule
