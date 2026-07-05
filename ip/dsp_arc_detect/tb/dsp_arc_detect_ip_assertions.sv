`timescale 1ns/1ps

module dsp_arc_detect_ip_assertions (
    input logic        clk_i,
    input logic        rst_ni,

    input logic        adc_valid_i,
    input logic [15:0] adc_data_i,
    input logic        stream_restart_i,

    input logic        psel_i,
    input logic        penable_i,
    input logic        pwrite_i,
    input logic [31:0] paddr_i,
    input logic [31:0] pwdata_i,
    input logic [31:0] prdata_o,
    input logic        pready_o,
    input logic        pslverr_o
);

    logic        apb_access_q;
    logic        history_valid_q;
    logic [31:0] paddr_q;
    logic [31:0] pwdata_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            apb_access_q   <= 1'b0;
            history_valid_q <= 1'b0;
            paddr_q        <= 32'd0;
            pwdata_q       <= 32'd0;
        end else begin
            assert (!$isunknown({adc_valid_i, stream_restart_i, psel_i, penable_i, pwrite_i}))
                else $fatal(1, "[DSP-IP][ASSERT] control input has X/Z");

            if (adc_valid_i) begin
                assert (!$isunknown(adc_data_i))
                    else $fatal(1, "[DSP-IP][ASSERT] adc_data_i has X/Z while valid");
            end

            if (psel_i) begin
                assert (!$isunknown({paddr_i, pwdata_i}))
                    else $fatal(1, "[DSP-IP][ASSERT] APB address/write data has X/Z during select");
            end

            if (history_valid_q) begin
                assert (pready_o === apb_access_q)
                    else $fatal(1, "[DSP-IP][ASSERT] pready_o does not match previous APB access phase");

                assert (pslverr_o === 1'b0)
                    else $fatal(1, "[DSP-IP][ASSERT] pslverr_o asserted unexpectedly");

                assert (!$isunknown(prdata_o))
                    else $fatal(1, "[DSP-IP][ASSERT] prdata_o has X/Z");
            end

            if (psel_i && !penable_i) begin
                paddr_q  <= paddr_i;
                pwdata_q <= pwdata_i;
            end

            if (psel_i && penable_i) begin
                assert (paddr_i === paddr_q)
                    else $fatal(1, "[DSP-IP][ASSERT] APB address changed between setup and access");

                if (pwrite_i) begin
                    assert (pwdata_i === pwdata_q)
                        else $fatal(1, "[DSP-IP][ASSERT] APB write data changed between setup and access");
                end
            end

            apb_access_q   <= psel_i && penable_i;
            history_valid_q <= 1'b1;
        end
    end

endmodule
