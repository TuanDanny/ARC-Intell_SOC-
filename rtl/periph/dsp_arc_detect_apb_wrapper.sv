`include "../include/apb_bus.sv"

module dsp_arc_detect_apb_wrapper #(
    parameter int DATA_WIDTH = 16,
    parameter int CNT_WIDTH  = 16
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic [DATA_WIDTH-1:0] adc_data_i,
    input  logic                  adc_valid_i,
    input  logic                  stream_restart_i,

    input  logic [31:0]           paddr_i,
    input  logic [31:0]           pwdata_i,
    input  logic                  pwrite_i,
    input  logic                  psel_i,
    input  logic                  penable_i,
    output logic [31:0]           prdata_o,
    output logic                  pready_o,
    output logic                  pslverr_o,

    output logic                  irq_arc_o
);

    APB_BUS apb_slv();

    assign apb_slv.paddr   = paddr_i;
    assign apb_slv.pwdata  = pwdata_i;
    assign apb_slv.pwrite  = pwrite_i;
    assign apb_slv.psel    = psel_i;
    assign apb_slv.penable = penable_i;

    assign prdata_o  = apb_slv.prdata;
    assign pready_o  = apb_slv.pready;
    assign pslverr_o = apb_slv.pslverr;

    dsp_arc_detect #(
        .DATA_WIDTH (DATA_WIDTH),
        .CNT_WIDTH  (CNT_WIDTH)
    ) u_core (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .adc_data_i       (adc_data_i),
        .adc_valid_i      (adc_valid_i),
        .stream_restart_i (stream_restart_i),
        .apb_slv          (apb_slv),
        .irq_arc_o        (irq_arc_o)
    );

endmodule
