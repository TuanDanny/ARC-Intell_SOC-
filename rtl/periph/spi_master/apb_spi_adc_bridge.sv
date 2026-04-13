module apb_spi_adc_bridge #(
    parameter int APB_ADDR_WIDTH = 12,
    parameter int APB_DATA_WIDTH = 32,
    parameter int SAMPLE_WIDTH   = 16,
    parameter int CMD_WIDTH      = 0,
    parameter int DUMMY_CYCLES   = 0,
    parameter int SCLK_DIV       = 2,
    parameter bit CPOL           = 1'b0,
    parameter bit CPHA           = 1'b0,
    parameter bit MSB_FIRST      = 1'b1,
    parameter int PRE_CS_CYCLES  = 1,
    parameter int POST_CS_CYCLES = 1
) (
    input  logic                      clk_i,
    input  logic                      rst_ni,

    input  logic [APB_ADDR_WIDTH-1:0] paddr_i,
    input  logic [APB_DATA_WIDTH-1:0] pwdata_i,
    input  logic                      pwrite_i,
    input  logic                      psel_i,
    input  logic                      penable_i,
    output logic [APB_DATA_WIDTH-1:0] prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,

    input  logic                      adc_miso_i,
    output logic                      adc_mosi_o,
    output logic                      adc_sclk_o,
    output logic                      adc_csn_o,

    output logic [SAMPLE_WIDTH-1:0]   sample_data_o,
    output logic                      sample_valid_o,
    output logic                      busy_o,
    output logic                      frame_active_o,
    output logic                      overrun_o,
    output logic                      stream_restart_o
);

    localparam int CMD_REG_WIDTH = (CMD_WIDTH > 0) ? CMD_WIDTH : 1;

    localparam logic [4:0] ADDR_CTRL   = 5'h00;
    localparam logic [4:0] ADDR_STATUS = 5'h04;
    localparam logic [4:0] ADDR_CMD    = 5'h08;
    localparam logic [4:0] ADDR_SAMPLE = 5'h0C;
    localparam logic [4:0] ADDR_COUNT  = 5'h10;
    localparam logic [4:0] ADDR_INFO   = 5'h14;

    logic [CMD_REG_WIDTH-1:0] r_cmd;
    logic                     r_enable;
    logic                     r_continuous;
    logic                     s_start_cmd;
    logic                     s_clear_status;

    logic [SAMPLE_WIDTH-1:0]  r_last_sample;
    logic                     r_sample_valid_sticky;
    logic                     r_sample_overwrite_sticky;
    logic                     r_frontend_overrun_sticky;
    logic [15:0]              r_frame_count;
    logic [15:0]              r_overwrite_count;

    logic [SAMPLE_WIDTH-1:0]  frontend_sample_data;
    logic                     frontend_sample_valid;
    logic                     frontend_busy;
    logic                     frontend_frame_active;
    logic                     frontend_overrun;
    logic                     overrun_pulse_q;
    logic                     stream_restart_pulse_q;
    logic                     stream_request_comb;
    logic                     stream_request_q;

    assign pready_o  = 1'b1;
    assign pslverr_o = 1'b0;

    // The bridge keeps the ADC frontend in a known-good fire-and-forget mode
    // by default, while still exposing APB control for debug and future
    // firmware. Because the downstream DSP path has no ready/backpressure
    // handshake today, frontend overrun remains a bridge/software telemetry
    // event rather than a detector-side fault source.
    spi_adc_stream_rx #(
        .SAMPLE_WIDTH   (SAMPLE_WIDTH),
        .CMD_WIDTH      (CMD_WIDTH),
        .DUMMY_CYCLES   (DUMMY_CYCLES),
        .SCLK_DIV       (SCLK_DIV),
        .CPOL           (CPOL),
        .CPHA           (CPHA),
        .MSB_FIRST      (MSB_FIRST),
        .PRE_CS_CYCLES  (PRE_CS_CYCLES),
        .POST_CS_CYCLES (POST_CS_CYCLES),
        .CONTINUOUS     (1'b0)
    ) u_spi_adc_rx (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .enable_i       (r_enable),
        .start_i        (stream_request_comb),
        .adc_miso_i     (adc_miso_i),
        .adc_mosi_o     (adc_mosi_o),
        .adc_sclk_o     (adc_sclk_o),
        .adc_csn_o      (adc_csn_o),
        .cmd_i          (r_cmd),
        .sample_ready_i (1'b1),
        .sample_data_o  (frontend_sample_data),
        .sample_valid_o (frontend_sample_valid),
        .busy_o         (frontend_busy),
        .frame_active_o (frontend_frame_active),
        .overrun_o      (frontend_overrun)
    );

    assign sample_data_o  = frontend_sample_data;
    assign sample_valid_o = frontend_sample_valid;
    assign busy_o         = frontend_busy;
    assign frame_active_o = frontend_frame_active;
    assign overrun_o      = overrun_pulse_q;
    assign stream_restart_o = stream_restart_pulse_q;
    assign stream_request_comb = r_enable && (r_continuous || s_start_cmd);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_enable                   <= 1'b1;
            r_continuous               <= 1'b1;
            s_start_cmd                <= 1'b0;
            s_clear_status             <= 1'b0;
            r_cmd                      <= '0;
            r_last_sample              <= '0;
            r_sample_valid_sticky      <= 1'b0;
            r_sample_overwrite_sticky  <= 1'b0;
            r_frontend_overrun_sticky  <= 1'b0;
            r_frame_count              <= 16'd0;
            r_overwrite_count          <= 16'd0;
            overrun_pulse_q            <= 1'b0;
            stream_restart_pulse_q     <= 1'b0;
            stream_request_q           <= 1'b0;
        end else begin
            s_start_cmd    <= 1'b0;
            s_clear_status <= 1'b0;
            overrun_pulse_q        <= 1'b0;
            stream_restart_pulse_q <= 1'b0;

            if (psel_i && penable_i && pwrite_i) begin
                case (paddr_i[4:0])
                    ADDR_CTRL: begin
                        r_enable       <= pwdata_i[0];
                        r_continuous   <= pwdata_i[1];
                        s_start_cmd    <= pwdata_i[2];
                        s_clear_status <= pwdata_i[3];
                    end
                    ADDR_CMD: begin
                        r_cmd <= pwdata_i[CMD_REG_WIDTH-1:0];
                    end
                    default: ;
                endcase
            end

            if (frontend_sample_valid) begin
                r_last_sample <= frontend_sample_data;
                r_frame_count <= r_frame_count + 16'd1;

                if (r_sample_valid_sticky) begin
                    // This is an APB-side overwrite event: software has not
                    // consumed the shadow sample register quickly enough.
                    // The live sample stream toward the DSP is still valid, so
                    // do not forward this as a DSP data-fault pulse.
                    r_sample_overwrite_sticky <= 1'b1;
                    r_overwrite_count         <= r_overwrite_count + 16'd1;
                end

                r_sample_valid_sticky <= 1'b1;
            end

            if (frontend_overrun) begin
                r_frontend_overrun_sticky <= 1'b1;
                overrun_pulse_q           <= 1'b1;
            end

            if (!stream_request_q && stream_request_comb) begin
                stream_restart_pulse_q <= 1'b1;
            end
            stream_request_q <= stream_request_comb;

            if (s_clear_status) begin
                r_sample_valid_sticky     <= 1'b0;
                r_sample_overwrite_sticky <= 1'b0;
                r_frontend_overrun_sticky <= 1'b0;
                r_frame_count             <= 16'd0;
                r_overwrite_count         <= 16'd0;
            end else if (psel_i && penable_i && !pwrite_i && (paddr_i[4:0] == ADDR_SAMPLE)) begin
                // Reading the sample register acknowledges that software has
                // consumed the latest buffered sample.
                r_sample_valid_sticky <= 1'b0;
            end
        end
    end

    always_comb begin
        prdata_o = '0;

        if (psel_i && !pwrite_i) begin
            case (paddr_i[4:0])
                ADDR_CTRL: begin
                    prdata_o[0] = r_enable;
                    prdata_o[1] = r_continuous;
                end

                ADDR_STATUS: begin
                    prdata_o[0] = r_enable;
                    prdata_o[1] = r_continuous;
                    prdata_o[2] = frontend_busy;
                    prdata_o[3] = frontend_frame_active;
                    prdata_o[4] = r_sample_valid_sticky;
                    prdata_o[5] = r_sample_overwrite_sticky;
                    prdata_o[6] = r_frontend_overrun_sticky;
                end

                ADDR_CMD: begin
                    prdata_o[CMD_REG_WIDTH-1:0] = r_cmd;
                end

                ADDR_SAMPLE: begin
                    prdata_o[SAMPLE_WIDTH-1:0] = r_last_sample;
                end

                ADDR_COUNT: begin
                    prdata_o[15:0]  = r_frame_count;
                    prdata_o[31:16] = r_overwrite_count;
                end

                ADDR_INFO: begin
                    prdata_o[7:0]   = SCLK_DIV[7:0];
                    prdata_o[15:8]  = PRE_CS_CYCLES[7:0];
                    prdata_o[23:16] = POST_CS_CYCLES[7:0];
                    prdata_o[24]    = CPOL;
                    prdata_o[25]    = CPHA;
                    prdata_o[26]    = MSB_FIRST;
                end

                default: ;
            endcase
        end
    end

endmodule
