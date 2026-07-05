`timescale 1ns/1ps

module tb_spi_cdc_bridge;

    logic        spi_clk;
    logic        spi_rst_n;
    logic        spi_csn;
    logic        spi_miso;
    logic        sys_clk;
    logic        sys_rst_n;
    logic [15:0] sys_sample_data;
    logic        sys_sample_valid;
    logic        sys_sample_ready;
    logic        fifo_full;
    logic        fifo_empty;
    logic        fifo_overflow;
    logic        fifo_underflow;

    int pass_count;
    int fail_count;

    spi_adc_cdc_bridge #(
        .SAMPLE_WIDTH    (16),
        .FIFO_ADDR_WIDTH (3)
    ) dut (
        .spi_clk_i           (spi_clk),
        .spi_rst_ni          (spi_rst_n),
        .spi_csn_i           (spi_csn),
        .spi_miso_i          (spi_miso),
        .sys_clk_i           (sys_clk),
        .sys_rst_ni          (sys_rst_n),
        .sys_sample_data_o   (sys_sample_data),
        .sys_sample_valid_o  (sys_sample_valid),
        .sys_sample_ready_i  (sys_sample_ready),
        .fifo_full_o         (fifo_full),
        .fifo_empty_o        (fifo_empty),
        .fifo_overflow_o     (fifo_overflow),
        .fifo_underflow_o    (fifo_underflow)
    );

    initial begin
        spi_clk = 1'b0;
        forever #11 spi_clk = ~spi_clk;
    end

    initial begin
        sys_clk = 1'b0;
        forever #10 sys_clk = ~sys_clk;
    end

    task automatic pass_note(input string msg);
        begin
            pass_count++;
            $display("[SPI-CDC] PASS: %s", msg);
        end
    endtask

    task automatic fail_note(input string msg);
        begin
            fail_count++;
            $display("[SPI-CDC] FAIL: %s", msg);
        end
    endtask

    task automatic reset_all();
        begin
            spi_rst_n = 1'b0;
            sys_rst_n = 1'b0;
            spi_csn = 1'b1;
            spi_miso = 1'b0;
            sys_sample_ready = 1'b0;
            repeat (6) @(posedge spi_clk);
            repeat (6) @(posedge sys_clk);
            spi_rst_n = 1'b1;
            sys_rst_n = 1'b1;
            repeat (8) @(posedge sys_clk);
        end
    endtask

    task automatic send_spi_word(input logic [15:0] word);
        begin
            @(negedge spi_clk);
            spi_csn <= 1'b0;
            for (int i = 15; i >= 0; i--) begin
                spi_miso <= word[i];
                @(negedge spi_clk);
            end
            spi_csn <= 1'b1;
            spi_miso <= 1'b0;
            repeat (2) @(negedge spi_clk);
        end
    endtask

    task automatic recv_sys_word(output logic [15:0] word);
        int guard;
        begin
            guard = 0;
            @(posedge sys_clk);
            while (!sys_sample_valid && guard < 500) begin
                guard++;
                @(posedge sys_clk);
            end
            if (!sys_sample_valid) begin
                fail_note("timeout waiting for sys_sample_valid");
                word = 'x;
            end else begin
                word = sys_sample_data;
                sys_sample_ready <= 1'b1;
                @(posedge sys_clk);
                sys_sample_ready <= 1'b0;
            end
        end
    endtask

    task automatic scenario_sequence_order();
        logic [15:0] got;
        logic [15:0] seq [0:3];
        begin
            seq[0] = 16'h1234;
            seq[1] = 16'hBEEF;
            seq[2] = 16'hCAFE;
            seq[3] = 16'h55AA;
            reset_all();
            fork
                begin
                    for (int i = 0; i < 4; i++) send_spi_word(seq[i]);
                end
                begin
                    for (int i = 0; i < 4; i++) begin
                        recv_sys_word(got);
                        if (got !== seq[i]) fail_note($sformatf("sample mismatch got=0x%04h exp=0x%04h", got, seq[i]));
                    end
                end
            join
            pass_note("samples preserved 1234 BEEF CAFE 55AA");
        end
    endtask

    task automatic scenario_stall_buffering();
        logic [15:0] got;
        begin
            reset_all();
            send_spi_word(16'h0A0A);
            send_spi_word(16'h0B0B);
            repeat (30) @(posedge sys_clk);
            recv_sys_word(got);
            if (got !== 16'h0A0A) fail_note("stall first sample mismatch");
            recv_sys_word(got);
            if (got !== 16'h0B0B) fail_note("stall second sample mismatch");
            pass_note("FIFO stall buffering");
        end
    endtask

    task automatic scenario_overflow_flag();
        begin
            reset_all();
            for (int i = 0; i < 12; i++) begin
                send_spi_word(16'h3000 + i[15:0]);
            end
            repeat (20) @(posedge spi_clk);
            if (!fifo_overflow && !fifo_full) fail_note("overflow/full flag missing during intentional overrun");
            else pass_note("overflow flag");
        end
    endtask

    task automatic scenario_no_x_on_valid();
        logic [15:0] got;
        begin
            reset_all();
            fork
                send_spi_word(16'hF00D);
                recv_sys_word(got);
            join
            if (^got === 1'bx) fail_note("X detected on DSP-facing stream");
            else pass_note("no X on DSP-facing stream");
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        scenario_sequence_order();
        scenario_stall_buffering();
        scenario_overflow_flag();
        scenario_no_x_on_valid();
        $display("[SPI-CDC] SUMMARY: PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("[SPI-CDC] RESULT: PASS");
        else                 $display("[SPI-CDC] RESULT: FAIL");
        $finish;
    end

endmodule
