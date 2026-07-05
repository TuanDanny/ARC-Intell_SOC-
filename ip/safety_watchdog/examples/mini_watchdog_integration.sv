`timescale 1ns/1ps

module mini_watchdog_integration (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [31:0] paddr_i,
    input  logic [31:0] pwdata_i,
    input  logic        pwrite_i,
    input  logic        psel_i,
    input  logic        penable_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    output logic        pslverr_o,
    output logic        wdt_reset_o
);

    safety_watchdog #(
        .DEFAULT_TIMEOUT(32'h00FF_FFFF)
    ) u_wdt (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .paddr_i    (paddr_i),
        .pwdata_i   (pwdata_i),
        .psel_i     (psel_i),
        .penable_i  (penable_i),
        .pwrite_i   (pwrite_i),
        .prdata_o   (prdata_o),
        .pready_o   (pready_o),
        .pslverr_o  (pslverr_o),
        .wdt_reset_o(wdt_reset_o)
    );

endmodule
