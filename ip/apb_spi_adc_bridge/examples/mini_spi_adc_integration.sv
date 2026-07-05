`timescale 1ns/1ps

module mini_spi_adc_integration (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [11:0] paddr_i,
    input  logic [31:0] pwdata_i,
    input  logic        pwrite_i,
    input  logic        psel_i,
    input  logic        penable_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    output logic        pslverr_o,
    input  logic        adc_miso_i,
    output logic        adc_mosi_o,
    output logic        adc_sclk_o,
    output logic        adc_csn_o,
    output logic [15:0] sample_data_o,
    output logic        sample_valid_o
);

    apb_spi_adc_bridge #(
        .SAMPLE_WIDTH(16),
        .SCLK_DIV(2)
    ) u_spi_bridge (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .paddr_i        (paddr_i),
        .pwdata_i       (pwdata_i),
        .pwrite_i       (pwrite_i),
        .psel_i         (psel_i),
        .penable_i      (penable_i),
        .prdata_o       (prdata_o),
        .pready_o       (pready_o),
        .pslverr_o      (pslverr_o),
        .adc_miso_i     (adc_miso_i),
        .adc_mosi_o     (adc_mosi_o),
        .adc_sclk_o     (adc_sclk_o),
        .adc_csn_o      (adc_csn_o),
        .sample_data_o  (sample_data_o),
        .sample_valid_o (sample_valid_o),
        .busy_o         (),
        .frame_active_o (),
        .overrun_o      (),
        .stream_restart_o()
    );

endmodule
