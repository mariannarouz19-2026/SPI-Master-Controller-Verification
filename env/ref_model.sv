`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    localparam [7:0] OFF_CTRL     = 8'h00;
    localparam [7:0] OFF_STATUS   = 8'h04;
    localparam [7:0] OFF_TX_DATA  = 8'h08;
    localparam [7:0] OFF_RX_DATA  = 8'h0C;
    localparam [7:0] OFF_CLK_DIV  = 8'h10;
    localparam [7:0] OFF_SS_CTRL  = 8'h14;
    localparam [7:0] OFF_INT_EN   = 8'h18;
    localparam [7:0] OFF_INT_STAT = 8'h1C;
    localparam [7:0] OFF_DELAY    = 8'h20;

    localparam int IRQ_TX_EMPTY      = 0;
    localparam int IRQ_RX_FULL       = 1;
    localparam int IRQ_TX_OVF        = 2;
    localparam int IRQ_RX_OVF        = 3;
    localparam int IRQ_TRANSFER_DONE = 4;
    localparam int IRQ_COUNT         = 5;

    localparam int FIFO_DEPTH = 8;

    int error_count = 0;

    bit        pred_ctrl_en;
    bit        pred_ctrl_mstr;
    bit [1:0]  pred_ctrl_mode;
    bit        pred_ctrl_lsb_first;
    bit        pred_ctrl_loopback;
    bit [1:0]  pred_ctrl_width;

    bit [15:0] pred_clk_div;
    bit [3:0]  pred_ss_en;
    bit [3:0]  pred_ss_val;
    bit [IRQ_COUNT-1:0] pred_int_en;
    bit [IRQ_COUNT-1:0] pred_int_stat;
    bit [7:0]  pred_delay_cfg;

    bit [31:0] tx_fifo [$];
    bit [31:0] rx_fifo [$];

    bit [3:0]  pred_ss_n;
    bit        pred_irq;

    bit [31:0] pred_tx_word;
    bit [31:0] pred_rx_word;
    
    bit        pred_busy;
    bit        transfer_done_pending;
    bit        transfer_in_progress;

    task reset();
        error_count         = 0;
        pred_ctrl_en        = 1'b0;
        pred_ctrl_mstr      = 1'b0;
        pred_ctrl_mode      = 2'b00;
        pred_ctrl_lsb_first = 1'b0;
        pred_ctrl_loopback  = 1'b0;
        pred_ctrl_width     = 2'b00;
        pred_clk_div        = 16'h0;
        pred_ss_en          = 4'h0;
        pred_ss_val         = 4'h0;
        pred_int_en         = '0;
        pred_int_stat       = '0;
        pred_delay_cfg      = 8'h0;
        tx_fifo             = '{};
        rx_fifo             = '{};
        pred_ss_n           = 4'hF;
        pred_irq            = 1'b0;
        pred_tx_word        = 32'h0;
        pred_rx_word        = 32'h0;
        pred_busy           = 1'b0;
        transfer_done_pending = 1'b0;
        transfer_in_progress = 1'b0;
    endtask

    function int get_width_bits(input bit [1:0] width);
        case (width)
            2'b00: return 8;
            2'b01: return 16;
            default: return 32;
        endcase
    endfunction

    function bit [31:0] align_rx(input bit [31:0] sh, input int total_bits);
        if (total_bits == 32)
            align_rx = sh;
        else
            align_rx = sh & ((32'h1 << total_bits) - 32'h1);
    endfunction

    function bit [31:0] build_tx_word(input bit [31:0] data, input bit [1:0] width);
        case (width)
            2'b00: return {24'b0, data[7:0]};
            2'b01: return {16'b0, data[15:0]};
            default: return data;
        endcase
    endfunction

    task predict_cycle();
        if (transfer_done_pending) begin
            pred_int_stat[IRQ_TRANSFER_DONE] = 1'b0;
            transfer_done_pending = 1'b0;
            _update_irq();
        end
    endtask

    task predict_apb_write(input bit [7:0] addr, input bit [31:0] wdata);
        case (addr)
            OFF_CTRL: begin
                pred_ctrl_width     = wdata[7:6];
                pred_ctrl_loopback  = wdata[5];
                pred_ctrl_lsb_first = wdata[4];
                pred_ctrl_mode      = wdata[3:2];
                pred_ctrl_mstr      = wdata[1];
                pred_ctrl_en        = wdata[0];

                if (!wdata[0]) begin
                    tx_fifo = '{};
                    rx_fifo = '{};
                    pred_busy = 1'b0;
                    pred_int_stat = '0;
                    transfer_done_pending = 1'b0;
                    transfer_in_progress = 1'b0;
                end
            end

            OFF_CLK_DIV: pred_clk_div = wdata[15:0];
            OFF_SS_CTRL: begin
                pred_ss_val = wdata[7:4];
                pred_ss_en  = wdata[3:0];
            end
            OFF_INT_EN: pred_int_en = wdata[IRQ_COUNT-1:0];
            OFF_DELAY: pred_delay_cfg = wdata[7:0];

            OFF_TX_DATA: begin
                if (pred_ctrl_en) begin
                    if (tx_fifo.size() < FIFO_DEPTH) begin
                        bit [31:0] push_data = build_tx_word(wdata, pred_ctrl_width);
                        tx_fifo.push_back(push_data);
                        pred_int_stat[IRQ_TX_EMPTY] = 1'b0;
                    end else begin
                        pred_int_stat[IRQ_TX_OVF] = 1'b1;
                    end
                end
            end

            OFF_INT_STAT: begin
                pred_int_stat = pred_int_stat & ~wdata[IRQ_COUNT-1:0];
                _update_irq();
            end
            default: ;
        endcase
        _update_ss_n();
        _update_irq();
    endtask

    function automatic bit [31:0] predict_apb_read(input bit [7:0] addr);
        bit [31:0] rdata;
        case (addr)
            OFF_CTRL: begin
                rdata = 32'h0;
                rdata[7:6] = pred_ctrl_width;
                rdata[5]   = pred_ctrl_loopback;
                rdata[4]   = pred_ctrl_lsb_first;
                rdata[3:2] = pred_ctrl_mode;
                rdata[1]   = pred_ctrl_mstr;
                rdata[0]   = pred_ctrl_en;
            end
            OFF_STATUS: begin
                rdata = 32'h0;
                rdata[6] = pred_int_stat[IRQ_RX_OVF];
                rdata[5] = pred_int_stat[IRQ_TX_OVF];
                rdata[4] = (rx_fifo.size() == 0);
                rdata[3] = (rx_fifo.size() == FIFO_DEPTH);
                rdata[2] = (tx_fifo.size() == 0);
                rdata[1] = (tx_fifo.size() == FIFO_DEPTH);
                rdata[0] = pred_busy;
            end
            OFF_TX_DATA: rdata = 32'h0;
            OFF_RX_DATA: rdata = (rx_fifo.size() > 0) ? rx_fifo[0] : 32'h0;
            OFF_CLK_DIV: rdata = {16'h0, pred_clk_div};
            OFF_SS_CTRL: rdata = {24'h0, pred_ss_val, pred_ss_en};
            OFF_INT_EN: rdata = {{(32-IRQ_COUNT){1'b0}}, pred_int_en};
            OFF_INT_STAT: rdata = {{(32-IRQ_COUNT){1'b0}}, pred_int_stat};
            OFF_DELAY: rdata = {24'h0, pred_delay_cfg};
            default: rdata = 32'h0;
        endcase
        return rdata;
    endfunction

    task predict_rx_pop();
        if (rx_fifo.size() > 0) begin
            void'(rx_fifo.pop_front());
        end
    endtask

    task predict_tx_pop();
        if (tx_fifo.size() > 0) begin
            pred_tx_word = tx_fifo[0];
            void'(tx_fifo.pop_front());
            transfer_in_progress = 1'b1;
            pred_busy = 1'b1;
            _update_irq();
        end
    endtask

    task predict_transfer_complete(input bit [31:0] rx_data);
        if (rx_fifo.size() < FIFO_DEPTH) begin
            rx_fifo.push_back(rx_data);
            if (rx_fifo.size() == FIFO_DEPTH) begin
                pred_int_stat[IRQ_RX_FULL] = 1'b1;
            end
        end else begin
            pred_int_stat[IRQ_RX_OVF] = 1'b1;
        end

        if (tx_fifo.size() == 0) begin
            pred_int_stat[IRQ_TX_EMPTY] = 1'b1;
        end

        pred_int_stat[IRQ_TRANSFER_DONE] = 1'b1;
        transfer_done_pending = 1'b1;
        
        if (pred_delay_cfg == 0 || tx_fifo.size() == 0) begin
            pred_busy = 1'b0;
            transfer_in_progress = 1'b0;
        end
        
        _update_irq();
    endtask

    task predict_transfer_done(input bit [31:0] rx_data);
        predict_transfer_complete(rx_data);
    endtask

    task predict_transfer(
        input bit [31:0] tx_data,
        input bit [31:0] miso_pattern,
        input bit        loopback
    );
        int width_bits = get_width_bits(pred_ctrl_width);
        bit [31:0] aligned_tx = build_tx_word(tx_data, pred_ctrl_width);
        
        case (pred_ctrl_width)
            2'b00: pred_rx_word = {24'b0, loopback ? aligned_tx[7:0] : miso_pattern[7:0]};
            2'b01: pred_rx_word = {16'b0, loopback ? aligned_tx[15:0] : miso_pattern[15:0]};
            default: pred_rx_word = loopback ? aligned_tx : miso_pattern;
        endcase
        pred_rx_word = align_rx(pred_rx_word, width_bits);
    endtask

    task check_rx(input bit [31:0] observed);
        if (observed !== pred_rx_word) begin
            $display("[SCOREBOARD_ERROR] RX mismatch: predicted=0x%08h observed=0x%08h", pred_rx_word, observed);
            error_count++;
        end
    endtask

    task check_reg(input string name, input bit [31:0] expected, input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h", name, expected, observed);
            error_count++;
        end
    endtask

    task check_status(input bit [31:0] observed);
        bit [31:0] exp = predict_apb_read(OFF_STATUS);
        if (observed !== exp) begin
            $display("[SCOREBOARD_ERROR] STATUS mismatch: expected=0x%08h observed=0x%08h", exp, observed);
            error_count++;
        end
    endtask

    task check_int_stat(input bit [31:0] observed);
        bit [31:0] exp = {{(32-IRQ_COUNT){1'b0}}, pred_int_stat};
        if (observed !== exp) begin
            $display("[SCOREBOARD_ERROR] INT_STAT mismatch: expected=0x%08h observed=0x%08h", exp, observed);
            error_count++;
        end
    endtask

    task check_ss_n(input bit [3:0] observed);
        if (observed !== pred_ss_n) begin
            $display("[SCOREBOARD_ERROR] SS_n mismatch: expected=0x%01h observed=0x%01h", pred_ss_n, observed);
            error_count++;
        end
    endtask

    task check_irq(input bit observed);
        if (observed !== pred_irq) begin
            $display("[SCOREBOARD_ERROR] IRQ mismatch: expected=%0b observed=%0b", pred_irq, observed);
            error_count++;
        end
    endtask

    task check_ctrl(input bit [31:0] observed);
        check_reg("CTRL", predict_apb_read(OFF_CTRL), observed);
    endtask

    task check_clk_div(input bit [31:0] observed);
        check_reg("CLK_DIV", {16'h0, pred_clk_div}, observed);
    endtask

    task check_delay(input bit [31:0] observed);
        check_reg("DELAY", {24'h0, pred_delay_cfg}, observed);
    endtask

    task check_int_en(input bit [31:0] observed);
        check_reg("INT_EN", {{(32-IRQ_COUNT){1'b0}}, pred_int_en}, observed);
    endtask

    task check_ss_ctrl(input bit [31:0] observed);
        check_reg("SS_CTRL", {24'h0, pred_ss_val, pred_ss_en}, observed);
    endtask

    local function void _update_ss_n();
        pred_ss_n = ~pred_ss_en | pred_ss_val;
    endfunction

    local function void _update_irq();
        pred_irq = |(pred_int_stat & pred_int_en);
    endfunction

endclass

`endif 
