module spi_adc_stream_rx #(
    parameter int unsigned SAMPLE_WIDTH   = 16,
    parameter int unsigned CMD_WIDTH      = 0,
    parameter int unsigned DUMMY_CYCLES   = 0,
    parameter int unsigned SCLK_DIV       = 2,
    parameter bit          CPOL           = 1'b0,
    parameter bit          CPHA           = 1'b0,
    parameter bit          MSB_FIRST      = 1'b1,
    parameter int unsigned PRE_CS_CYCLES  = 1,
    parameter int unsigned POST_CS_CYCLES = 1,
    parameter bit          CONTINUOUS     = 1'b1
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic enable_i,
    input  logic start_i,

    input  logic adc_miso_i,
    output logic adc_mosi_o,
    output logic adc_sclk_o,
    output logic adc_csn_o,

    input  logic [((CMD_WIDTH > 0) ? CMD_WIDTH : 1)-1:0] cmd_i,
    input  logic sample_ready_i,

    output logic [SAMPLE_WIDTH-1:0] sample_data_o,
    output logic                    sample_valid_o,
    output logic                    busy_o,
    output logic                    frame_active_o,
    output logic                    overrun_o
);

    localparam int unsigned TOTAL_BITS = CMD_WIDTH + DUMMY_CYCLES + SAMPLE_WIDTH;
    localparam int unsigned PRE_W      = (PRE_CS_CYCLES  > 1) ? $clog2(PRE_CS_CYCLES)  : 1;
    localparam int unsigned POST_W     = (POST_CS_CYCLES > 1) ? $clog2(POST_CS_CYCLES) : 1;
    localparam int unsigned DIV_W      = (SCLK_DIV       > 1) ? $clog2(SCLK_DIV)       : 1;
    localparam int unsigned BIT_W      = (TOTAL_BITS     > 1) ? $clog2(TOTAL_BITS)     : 1;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_PRE,
        ST_SHIFT,
        ST_POST
    } state_t;

    state_t state_q;

    logic [PRE_W-1:0]  pre_cnt_q;
    logic [POST_W-1:0] post_cnt_q;
    logic [DIV_W-1:0]  div_cnt_q;
    logic [BIT_W-1:0]  bit_pos_q;

    logic [SAMPLE_WIDTH-1:0] sample_shift_q;

    function automatic logic cmd_bit_at(input int unsigned pos);
        logic bit_value;
        begin
            bit_value = 1'b0;
            if ((CMD_WIDTH > 0) && (pos < CMD_WIDTH)) begin
                if (MSB_FIRST)
                    bit_value = cmd_i[CMD_WIDTH-1-pos];
                else
                    bit_value = cmd_i[pos];
            end
            return bit_value;
        end
    endfunction


    initial begin
        if (SAMPLE_WIDTH < 1) $error("spi_adc_stream_rx: SAMPLE_WIDTH must be >= 1");
        if (SCLK_DIV < 1)     $error("spi_adc_stream_rx: SCLK_DIV must be >= 1");
    end

    assign busy_o         = (state_q != ST_IDLE);
    assign frame_active_o = ~adc_csn_o;

    function automatic logic [SAMPLE_WIDTH-1:0] capture_sample_bit(
        input logic [SAMPLE_WIDTH-1:0] cur,
        input logic                    bit_in,
        input int unsigned             pos
    );
        logic [SAMPLE_WIDTH-1:0] tmp;
        int unsigned sample_pos;
        begin
            tmp = cur;
            if ((pos >= (CMD_WIDTH + DUMMY_CYCLES)) && (pos < TOTAL_BITS)) begin
                sample_pos = pos - CMD_WIDTH - DUMMY_CYCLES;
                if (MSB_FIRST)
                    tmp[SAMPLE_WIDTH-1-sample_pos] = bit_in;
                else
                    tmp[sample_pos] = bit_in;
            end
            return tmp;
        end
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        logic next_sclk;
        logic is_leading_edge;
        logic is_sample_edge;
        logic is_launch_edge;
        logic [SAMPLE_WIDTH-1:0] captured_word;
        logic frame_done;
        logic run_request;

        if (!rst_ni) begin
            state_q         <= ST_IDLE;
            pre_cnt_q       <= '0;
            post_cnt_q      <= '0;
            div_cnt_q       <= '0;
            bit_pos_q       <= '0;
            sample_shift_q  <= '0;
            sample_data_o   <= '0;
            sample_valid_o  <= 1'b0;
            overrun_o       <= 1'b0;
            adc_mosi_o      <= 1'b0;
            adc_sclk_o      <= CPOL;
            adc_csn_o       <= 1'b1;
        end else begin
            sample_valid_o  <= 1'b0;
            run_request     = enable_i && (CONTINUOUS || start_i);
            if (sample_ready_i) overrun_o <= 1'b0;
            case (state_q)
                ST_IDLE: begin
                    adc_csn_o      <= 1'b1;
                    adc_sclk_o     <= CPOL;
                    adc_mosi_o     <= cmd_bit_at(0);
                    div_cnt_q      <= '0;
                    bit_pos_q      <= '0;
                    sample_shift_q <= '0;
                    pre_cnt_q      <= '0;
                    post_cnt_q     <= '0;

                    if (run_request) begin
                        adc_csn_o <= 1'b0;
                        adc_mosi_o <= cmd_bit_at(0);
                        if (PRE_CS_CYCLES > 0) begin
                            state_q   <= ST_PRE;
                            pre_cnt_q <= '0;
                        end else begin
                            state_q   <= ST_SHIFT;
                        end
                    end
                end

                ST_PRE: begin
                    adc_csn_o     <= 1'b0;
                    adc_sclk_o    <= CPOL;
                    adc_mosi_o    <= cmd_bit_at(0);
                    div_cnt_q     <= '0;
                    bit_pos_q     <= '0;
                    sample_shift_q <= '0;

                    if (pre_cnt_q == PRE_CS_CYCLES-1) begin
                        pre_cnt_q <= '0;
                        state_q   <= ST_SHIFT;
                    end else begin
                        pre_cnt_q <= pre_cnt_q + 1'b1;
                    end
                end

                ST_SHIFT: begin
                    adc_csn_o <= 1'b0;

                    if (div_cnt_q == SCLK_DIV-1) begin
                        div_cnt_q   <= '0;
                        next_sclk   = ~adc_sclk_o;
                        adc_sclk_o  <= next_sclk;

                        is_leading_edge = (adc_sclk_o == CPOL);
                        is_sample_edge  = CPHA ? !is_leading_edge : is_leading_edge;
                        is_launch_edge  = !is_sample_edge;
                        captured_word   = sample_shift_q;
                        frame_done      = 1'b0;

                        if (is_sample_edge) begin
                            captured_word = capture_sample_bit(sample_shift_q, adc_miso_i, bit_pos_q);
                            sample_shift_q <= captured_word;

                            if (bit_pos_q == TOTAL_BITS-1) begin
                                frame_done = 1'b1;
                            end else begin
                                bit_pos_q <= bit_pos_q + 1'b1;
                            end
                        end

                        if (is_launch_edge) begin
                            if ((bit_pos_q + 1) < TOTAL_BITS)
                                adc_mosi_o <= cmd_bit_at(bit_pos_q + 1);
                            else
                                adc_mosi_o <= 1'b0;
                        end

                        if (frame_done) begin
                            sample_data_o  <= captured_word;
                            sample_valid_o <= sample_ready_i;
                            overrun_o      <= ~sample_ready_i;
                            adc_sclk_o     <= CPOL;
                            adc_csn_o      <= 1'b1;
                            bit_pos_q      <= '0;
                            div_cnt_q      <= '0;

                            if (POST_CS_CYCLES > 0) begin
                                post_cnt_q <= '0;
                                state_q    <= ST_POST;
                            end else if (enable_i && CONTINUOUS) begin
                                adc_csn_o      <= 1'b0;
                                adc_mosi_o     <= cmd_bit_at(0);
                                sample_shift_q <= '0;
                                state_q        <= (PRE_CS_CYCLES > 0) ? ST_PRE : ST_SHIFT;
                                pre_cnt_q      <= '0;
                            end else begin
                                state_q <= ST_IDLE;
                            end
                        end
                    end else begin
                        div_cnt_q <= div_cnt_q + 1'b1;
                    end
                end

                ST_POST: begin
                    adc_csn_o      <= 1'b1;
                    adc_sclk_o     <= CPOL;
                    adc_mosi_o     <= 1'b0;
                    sample_shift_q <= '0;

                    if (post_cnt_q == POST_CS_CYCLES-1) begin
                        post_cnt_q <= '0;
                        if (enable_i && CONTINUOUS) begin
                            adc_csn_o  <= 1'b0;
                            adc_mosi_o <= cmd_bit_at(0);
                            if (PRE_CS_CYCLES > 0) begin
                                pre_cnt_q <= '0;
                                state_q   <= ST_PRE;
                            end else begin
                                state_q   <= ST_SHIFT;
                            end
                        end else begin
                            state_q <= ST_IDLE;
                        end
                    end else begin
                        post_cnt_q <= post_cnt_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
