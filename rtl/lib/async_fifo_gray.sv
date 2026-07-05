module async_fifo_gray #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wr_clk_i,
    input  logic                  wr_rst_ni,
    input  logic                  wr_valid_i,
    output logic                  wr_ready_o,
    input  logic [DATA_WIDTH-1:0] wr_data_i,

    input  logic                  rd_clk_i,
    input  logic                  rd_rst_ni,
    output logic                  rd_valid_o,
    input  logic                  rd_ready_i,
    output logic [DATA_WIDTH-1:0] rd_data_o,

    output logic                  full_o,
    output logic                  empty_o,
    output logic                  overflow_o,
    output logic                  underflow_o
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH:0] wr_bin_q, wr_bin_d;
    logic [ADDR_WIDTH:0] rd_bin_q, rd_bin_d;
    logic [ADDR_WIDTH:0] wr_gray_q, wr_gray_d;
    logic [ADDR_WIDTH:0] rd_gray_q, rd_gray_d;

    logic [ADDR_WIDTH:0] rd_gray_wrclk_q1, rd_gray_wrclk_q2;
    logic [ADDR_WIDTH:0] wr_gray_rdclk_q1, wr_gray_rdclk_q2;

    logic wr_fire;
    logic rd_fire;
    logic full_next;
    logic empty_next;

    function automatic logic [ADDR_WIDTH:0] bin2gray(input logic [ADDR_WIDTH:0] bin);
        return (bin >> 1) ^ bin;
    endfunction

    assign wr_fire    = wr_valid_i && !full_o;
    assign rd_fire    = rd_ready_i && !empty_o;
    assign wr_ready_o = !full_o;
    assign rd_valid_o = !empty_o;

    assign wr_bin_d  = wr_bin_q + {{ADDR_WIDTH{1'b0}}, wr_fire};
    assign rd_bin_d  = rd_bin_q + {{ADDR_WIDTH{1'b0}}, rd_fire};
    assign wr_gray_d = bin2gray(wr_bin_d);
    assign rd_gray_d = bin2gray(rd_bin_d);

    assign full_next  = (wr_gray_d == {~rd_gray_wrclk_q2[ADDR_WIDTH:ADDR_WIDTH-1], rd_gray_wrclk_q2[ADDR_WIDTH-2:0]});
    assign empty_next = (rd_gray_d == wr_gray_rdclk_q2);

    assign rd_data_o = mem[rd_bin_q[ADDR_WIDTH-1:0]];

    always_ff @(posedge wr_clk_i or negedge wr_rst_ni) begin
        if (!wr_rst_ni) begin
            wr_bin_q         <= '0;
            wr_gray_q        <= '0;
            rd_gray_wrclk_q1 <= '0;
            rd_gray_wrclk_q2 <= '0;
            full_o           <= 1'b0;
            overflow_o       <= 1'b0;
        end else begin
            rd_gray_wrclk_q1 <= rd_gray_q;
            rd_gray_wrclk_q2 <= rd_gray_wrclk_q1;
            if (wr_valid_i && full_o)
                overflow_o <= 1'b1;

            if (wr_fire) begin
                mem[wr_bin_q[ADDR_WIDTH-1:0]] <= wr_data_i;
                wr_bin_q  <= wr_bin_d;
                wr_gray_q <= wr_gray_d;
            end

            full_o <= full_next;
        end
    end

    always_ff @(posedge rd_clk_i or negedge rd_rst_ni) begin
        if (!rd_rst_ni) begin
            rd_bin_q         <= '0;
            rd_gray_q        <= '0;
            wr_gray_rdclk_q1 <= '0;
            wr_gray_rdclk_q2 <= '0;
            empty_o          <= 1'b1;
            underflow_o      <= 1'b0;
        end else begin
            wr_gray_rdclk_q1 <= wr_gray_q;
            wr_gray_rdclk_q2 <= wr_gray_rdclk_q1;
            if (rd_ready_i && empty_o)
                underflow_o <= 1'b1;

            if (rd_fire) begin
                rd_bin_q  <= rd_bin_d;
                rd_gray_q <= rd_gray_d;
            end

            empty_o <= empty_next;
        end
    end

endmodule
