`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave  spi,
    input logic [1:0]  mode,
    input logic        lsb_first,
    input logic [1:0]  width,
    input logic [31:0] miso_word
    
);
    logic sclk_q;
    logic prev_ss_act;
    int   bit_idx;
    logic mosi_queue[$];
    logic [31:0] mosi_captured;

    wire cpol   = mode[1];
    wire cpha   = mode[0];
    wire ss_act = (spi.ss_n != 4'hF);

    wire rising_edge   = (sclk_q === 1'b0) && (spi.sclk === 1'b1);
    wire falling_edge  = (sclk_q === 1'b1) && (spi.sclk === 1'b0);
    wire leading_edge  = cpol ? falling_edge : rising_edge;
    wire trailing_edge = cpol ? rising_edge  : falling_edge;
    wire sample_edge   = cpha ? trailing_edge : leading_edge;
    wire launch_edge   = cpha ? leading_edge  : trailing_edge;

    logic [31:0] reversed_word;
always_comb begin
    int n_bits;
    case (width)
        2'b00:   n_bits = 8;
        2'b01:   n_bits = 16;
        2'b10:   n_bits = 32;
        default: n_bits = 32;
    endcase
    reversed_word = 32'h0;
    for (int i = 0; i < n_bits; i++)
        reversed_word[n_bits - 1 - i] = miso_word[i];
end


    wire [31:0] tx_word = lsb_first ? reversed_word : miso_word;

    function automatic int start_bit();
        case (width)
            2'b00: return 7;
            2'b01: return 15;
            2'b10: return 31;
            default: return 31;
        endcase
    endfunction

    initial begin
        sclk_q        = 1'b0;
        prev_ss_act   = 1'b0;
        bit_idx       = 31;
        mosi_captured = 32'h0;
        spi.cb_slave.miso <= 1'b0;
    end

    always @(posedge spi.pclk) begin

        prev_ss_act <= ss_act;
        sclk_q      <= spi.sclk;


        if (prev_ss_act && !ss_act) begin
            mosi_captured = 32'h0;
            if (!lsb_first) begin
                foreach (mosi_queue[i]) begin
                    mosi_captured = (mosi_captured << 1) | mosi_queue[i];
                end
            end
            else begin
                foreach (mosi_queue[i]) begin
                    mosi_captured = mosi_captured | (mosi_queue[i] << i);
                end
            end
        end

        if (!ss_act) begin
            mosi_queue.delete();
            bit_idx       <= start_bit();

            
            if (!cpha) begin
                spi.cb_slave.miso <= tx_word[start_bit()];  
                bit_idx           <=  (start_bit() - 1);
            end
        end
        else begin

            if (sample_edge) begin
                mosi_queue.push_back(spi.mosi);
            end

            if (launch_edge) begin
                
                    spi.cb_slave.miso <= tx_word[bit_idx];
                    bit_idx           <= bit_idx - 1; 
            end

        end
    end

endmodule
`endif