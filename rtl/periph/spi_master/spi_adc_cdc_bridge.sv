module spi_adc_cdc_bridge #(
    parameter int SAMPLE_WIDTH    = 16,
    parameter int FIFO_ADDR_WIDTH = 4
) (
    input  logic                    spi_clk_i,
    input  logic                    spi_rst_ni,
    input  logic                    spi_csn_i,
    input  logic                    spi_miso_i,

    input  logic                    sys_clk_i,
    input  logic                    sys_rst_ni,
    output logic [SAMPLE_WIDTH-1:0] sys_sample_data_o,
    output logic                    sys_sample_valid_o,
    input  logic                    sys_sample_ready_i,

    output logic                    fifo_full_o,
    output logic                    fifo_empty_o,
    output logic                    fifo_overflow_o,
    output logic                    fifo_underflow_o
);

    logic [SAMPLE_WIDTH-1:0] spi_sample_data;
    logic                    spi_sample_valid;
    logic                    fifo_wr_ready;

    spi_adc_sclk_capture_rx #(
        .SAMPLE_WIDTH (SAMPLE_WIDTH),
        .CPOL         (1'b0),
        .CPHA         (1'b0),
        .MSB_FIRST    (1'b1)
    ) u_capture (
        .spi_clk_i      (spi_clk_i),
        .spi_rst_ni     (spi_rst_ni),
        .spi_csn_i      (spi_csn_i),
        .spi_miso_i     (spi_miso_i),
        .sample_data_o  (spi_sample_data),
        .sample_valid_o (spi_sample_valid)
    );

    async_fifo_gray #(
        .DATA_WIDTH (SAMPLE_WIDTH),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_async_fifo (
        .wr_clk_i    (spi_clk_i),
        .wr_rst_ni   (spi_rst_ni),
        .wr_valid_i  (spi_sample_valid),
        .wr_ready_o  (fifo_wr_ready),
        .wr_data_i   (spi_sample_data),
        .rd_clk_i    (sys_clk_i),
        .rd_rst_ni   (sys_rst_ni),
        .rd_valid_o  (sys_sample_valid_o),
        .rd_ready_i  (sys_sample_ready_i),
        .rd_data_o   (sys_sample_data_o),
        .full_o      (fifo_full_o),
        .empty_o     (fifo_empty_o),
        .overflow_o  (fifo_overflow_o),
        .underflow_o (fifo_underflow_o)
    );

endmodule
