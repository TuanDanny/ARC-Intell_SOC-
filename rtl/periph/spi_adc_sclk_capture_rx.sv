module spi_adc_sclk_capture_rx #(
    parameter int SAMPLE_WIDTH = 16,
    parameter bit CPOL         = 1'b0,
    parameter bit CPHA         = 1'b0,
    parameter bit MSB_FIRST    = 1'b1
) (
    input  logic                    spi_clk_i,
    input  logic                    spi_rst_ni,
    input  logic                    spi_csn_i,
    input  logic                    spi_miso_i,
    output logic [SAMPLE_WIDTH-1:0] sample_data_o,
    output logic                    sample_valid_o
);

    localparam int BIT_W = (SAMPLE_WIDTH > 1) ? $clog2(SAMPLE_WIDTH) : 1;

    logic [SAMPLE_WIDTH-1:0] shift_q;
    logic [BIT_W-1:0]        bit_cnt_q;
    logic                    sample_edge_en;

    assign sample_edge_en = (CPHA == 1'b0);

    always_ff @(posedge spi_clk_i or negedge spi_rst_ni) begin
        if (!spi_rst_ni) begin
            shift_q        <= '0;
            bit_cnt_q      <= '0;
            sample_data_o  <= '0;
            sample_valid_o <= 1'b0;
        end else begin
            sample_valid_o <= 1'b0;

            if (spi_csn_i) begin
                shift_q   <= '0;
                bit_cnt_q <= '0;
            end else if (sample_edge_en) begin
                if (MSB_FIRST)
                    shift_q <= {shift_q[SAMPLE_WIDTH-2:0], spi_miso_i};
                else
                    shift_q <= {spi_miso_i, shift_q[SAMPLE_WIDTH-1:1]};

                if (bit_cnt_q == SAMPLE_WIDTH-1) begin
                    sample_valid_o <= 1'b1;
                    if (MSB_FIRST)
                        sample_data_o <= {shift_q[SAMPLE_WIDTH-2:0], spi_miso_i};
                    else
                        sample_data_o <= {spi_miso_i, shift_q[SAMPLE_WIDTH-1:1]};
                    bit_cnt_q <= '0;
                end else begin
                    bit_cnt_q <= bit_cnt_q + 1'b1;
                end
            end
        end
    end

endmodule
