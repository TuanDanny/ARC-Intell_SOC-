`timescale 1ns/1ps

module mini_apb_integration (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [15:0] adc_sample_i,
    input  logic        adc_valid_i,
    input  logic        stream_restart_i,

    input  logic [31:0] paddr_i,
    input  logic [31:0] pwdata_i,
    input  logic        pwrite_i,
    input  logic        psel_i,
    input  logic        penable_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    output logic        pslverr_o,
    output logic        irq_arc_o
);

    dsp_arc_detect_apb_wrapper u_arc_detector (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .adc_data_i       (adc_sample_i),
        .adc_valid_i      (adc_valid_i),
        .stream_restart_i (stream_restart_i),
        .paddr_i          (paddr_i),
        .pwdata_i         (pwdata_i),
        .pwrite_i         (pwrite_i),
        .psel_i           (psel_i),
        .penable_i        (penable_i),
        .prdata_o         (prdata_o),
        .pready_o         (pready_o),
        .pslverr_o        (pslverr_o),
        .irq_arc_o        (irq_arc_o)
    );

endmodule
