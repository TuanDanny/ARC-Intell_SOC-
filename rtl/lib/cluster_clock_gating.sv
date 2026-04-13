module cluster_clock_gating
(
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

    // Compatibility wrapper for older PULP-style IP blocks such as
    // generic_fifo that still instantiate cluster_clock_gating.
    pulp_clock_gating u_cg (
        .clk_i     (clk_i),
        .en_i      (en_i),
        .test_en_i (test_en_i),
        .clk_o     (clk_o)
    );

endmodule
