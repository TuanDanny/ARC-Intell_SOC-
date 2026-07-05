`timescale 1ns/1ps

module tb_cdc_async_fifo;

    localparam int DATA_WIDTH = 16;
    localparam int ADDR_WIDTH = 3;
    localparam int DEPTH      = (1 << ADDR_WIDTH);

    logic                  wr_clk;
    logic                  rd_clk;
    logic                  wr_rst_n;
    logic                  rd_rst_n;
    logic                  wr_valid;
    logic                  wr_ready;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  rd_valid;
    logic                  rd_ready;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  full;
    logic                  empty;
    logic                  overflow;
    logic                  underflow;

    int pass_count;
    int fail_count;

    async_fifo_gray #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .wr_clk_i    (wr_clk),
        .wr_rst_ni   (wr_rst_n),
        .wr_valid_i  (wr_valid),
        .wr_ready_o  (wr_ready),
        .wr_data_i   (wr_data),
        .rd_clk_i    (rd_clk),
        .rd_rst_ni   (rd_rst_n),
        .rd_valid_o  (rd_valid),
        .rd_ready_i  (rd_ready),
        .rd_data_o   (rd_data),
        .full_o      (full),
        .empty_o     (empty),
        .overflow_o  (overflow),
        .underflow_o (underflow)
    );

    initial begin
        wr_clk = 1'b0;
        forever #7 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #10 rd_clk = ~rd_clk;
    end

    task automatic pass_note(input string msg);
        begin
            pass_count++;
            $display("[CDC-FIFO] PASS: %s", msg);
        end
    endtask

    task automatic fail_note(input string msg);
        begin
            fail_count++;
            $display("[CDC-FIFO] FAIL: %s", msg);
        end
    endtask

    task automatic reset_fifo();
        begin
            wr_rst_n = 1'b0;
            rd_rst_n = 1'b0;
            wr_valid = 1'b0;
            wr_data  = '0;
            rd_ready = 1'b0;
            repeat (5) @(posedge wr_clk);
            repeat (5) @(posedge rd_clk);
            wr_rst_n = 1'b1;
            rd_rst_n = 1'b1;
            repeat (6) @(posedge rd_clk);
        end
    endtask

    task automatic push_word(input logic [DATA_WIDTH-1:0] data);
        int guard;
        begin
            guard = 0;
            @(posedge wr_clk);
            while (!wr_ready && guard < 100) begin
                guard++;
                @(posedge wr_clk);
            end
            if (!wr_ready) begin
                fail_note("push timeout waiting for wr_ready");
            end else begin
                wr_data  <= data;
                wr_valid <= 1'b1;
                @(posedge wr_clk);
                wr_valid <= 1'b0;
                wr_data  <= '0;
            end
        end
    endtask

    task automatic pop_word(output logic [DATA_WIDTH-1:0] data);
        int guard;
        begin
            guard = 0;
            @(posedge rd_clk);
            while (!rd_valid && guard < 200) begin
                guard++;
                @(posedge rd_clk);
            end
            if (!rd_valid) begin
                fail_note("pop timeout waiting for rd_valid");
                data = 'x;
            end else begin
                data = rd_data;
                rd_ready <= 1'b1;
                @(posedge rd_clk);
                rd_ready <= 1'b0;
            end
        end
    endtask

    task automatic scenario_order_preserved();
        logic [DATA_WIDTH-1:0] got;
        begin
            reset_fifo();
            for (int i = 0; i < 8; i++) begin
                push_word(16'h1000 + i[15:0]);
            end
            for (int i = 0; i < 8; i++) begin
                pop_word(got);
                if (got !== (16'h1000 + i[15:0]))
                    fail_note($sformatf("order mismatch got=0x%04h exp=0x%04h", got, 16'h1000 + i[15:0]));
            end
            pass_note("sample order preserved across unrelated clocks");
        end
    endtask

    task automatic scenario_full_overflow();
        begin
            reset_fifo();
            for (int i = 0; i < DEPTH; i++) begin
                push_word(16'h2000 + i[15:0]);
            end
            repeat (8) @(posedge wr_clk);
            if (!full || wr_ready) fail_note("full/wr_ready wrong after filling FIFO");
            wr_data  <= 16'hDEAD;
            wr_valid <= 1'b1;
            @(posedge wr_clk);
            wr_valid <= 1'b0;
            repeat (2) @(posedge wr_clk);
            if (!overflow) fail_note("overflow flag did not assert on write while full");
            else pass_note("full and overflow behavior correct");
        end
    endtask

    task automatic scenario_empty_underflow();
        begin
            reset_fifo();
            if (!empty || rd_valid) fail_note("empty/rd_valid wrong after reset");
            rd_ready <= 1'b1;
            @(posedge rd_clk);
            rd_ready <= 1'b0;
            repeat (2) @(posedge rd_clk);
            if (!underflow) fail_note("underflow flag did not assert on read while empty");
            else pass_note("empty and underflow behavior correct");
        end
    endtask

    task automatic scenario_reset_domains();
        logic [DATA_WIDTH-1:0] got;
        begin
            reset_fifo();
            push_word(16'hA5A5);
            repeat (2) @(posedge wr_clk);
            wr_rst_n = 1'b0;
            repeat (3) @(posedge wr_clk);
            wr_rst_n = 1'b1;
            repeat (5) @(posedge rd_clk);
            rd_rst_n = 1'b0;
            repeat (3) @(posedge rd_clk);
            rd_rst_n = 1'b1;
            repeat (6) @(posedge rd_clk);
            push_word(16'h5A5A);
            pop_word(got);
            if (got !== 16'h5A5A) fail_note("domain reset recovery data mismatch");
            else pass_note("independent domain reset recovery");
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        reset_fifo();
        pass_note("reset behavior");
        scenario_order_preserved();
        scenario_full_overflow();
        scenario_empty_underflow();
        scenario_reset_domains();
        $display("[CDC-FIFO] SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("[CDC-FIFO] RESULT: PASS");
        else                 $display("[CDC-FIFO] RESULT: FAIL");
        $finish;
    end

endmodule
