`timescale 1ns/1ps

module tb_support_blocks;

    logic clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer pass_count;
    integer fail_count;
    integer cg_pulse_count;

    task automatic pass_note(input string msg);
        begin
            pass_count = pass_count + 1;
            $display("[SUPPORT][PASS] %s", msg);
        end
    endtask

    task automatic fail_now(input string msg);
        begin
            fail_count = fail_count + 1;
            $display("[SUPPORT][FAIL] %s", msg);
            $stop;
        end
    endtask

    // ------------------------------------------------------------------
    // rstgen DUT
    // ------------------------------------------------------------------
    logic rstgen_rst_ni;
    logic rstgen_test_mode_i;
    logic rstgen_rst_no;
    logic rstgen_init_no;

    rstgen u_rstgen (
        .clk_i       (clk),
        .rst_ni      (rstgen_rst_ni),
        .test_mode_i (rstgen_test_mode_i),
        .rst_no      (rstgen_rst_no),
        .init_no     (rstgen_init_no)
    );

    // ------------------------------------------------------------------
    // cluster_clock_gating DUT
    // ------------------------------------------------------------------
    logic cg_en_i;
    logic cg_test_en_i;
    logic cg_clk_o;

    cluster_clock_gating u_cluster_clock_gating (
        .clk_i     (clk),
        .en_i      (cg_en_i),
        .test_en_i (cg_test_en_i),
        .clk_o     (cg_clk_o)
    );

    always @(posedge cg_clk_o) begin
        cg_pulse_count = cg_pulse_count + 1;
    end

    // ------------------------------------------------------------------
    // generic_fifo DUT
    // ------------------------------------------------------------------
    logic        fifo_rst_n;
    logic [7:0]  fifo_data_i;
    logic        fifo_valid_i;
    logic        fifo_grant_o;
    logic [7:0]  fifo_data_o;
    logic        fifo_valid_o;
    logic        fifo_grant_i;
    logic        fifo_test_mode_i;

    generic_fifo #(
        .DATA_WIDTH (8),
        .DATA_DEPTH (4)
    ) u_generic_fifo (
        .clk         (clk),
        .rst_n       (fifo_rst_n),
        .data_i      (fifo_data_i),
        .valid_i     (fifo_valid_i),
        .grant_o     (fifo_grant_o),
        .data_o      (fifo_data_o),
        .valid_o     (fifo_valid_o),
        .grant_i     (fifo_grant_i),
        .test_mode_i (fifo_test_mode_i)
    );

    task automatic fifo_push(input [7:0] data_byte);
        begin
            @(negedge clk);
            if (fifo_grant_o !== 1'b1) begin
                fail_now($sformatf("generic_fifo khong grant push cho data 0x%02h", data_byte));
            end
            fifo_data_i  = data_byte;
            fifo_valid_i = 1'b1;
            @(posedge clk);
            #1;
            fifo_valid_i = 1'b0;
            fifo_data_i  = 8'h00;
        end
    endtask

    task automatic fifo_expect_and_pop(input [7:0] expected_byte);
        begin
            @(negedge clk);
            if (fifo_valid_o !== 1'b1) begin
                fail_now($sformatf("generic_fifo khong valid truoc khi pop 0x%02h", expected_byte));
            end
            if (fifo_data_o !== expected_byte) begin
                fail_now($sformatf("generic_fifo sai thu tu. data_o=0x%02h, mong doi 0x%02h", fifo_data_o, expected_byte));
            end
            fifo_grant_i = 1'b1;
            @(posedge clk);
            #1;
            fifo_grant_i = 1'b0;
        end
    endtask

    task automatic scenario_rstgen_smoke();
        integer cycle_idx;
        begin
            rstgen_rst_ni      = 1'b0;
            rstgen_test_mode_i = 1'b0;
            repeat (2) @(posedge clk);
            #1;
            if ((rstgen_rst_no !== 1'b0) || (rstgen_init_no !== 1'b0)) begin
                fail_now("rstgen khong giu reset/init low khi rst_ni dang low.");
            end

            rstgen_rst_ni = 1'b1;
            for (cycle_idx = 0; cycle_idx < 4; cycle_idx = cycle_idx + 1) begin
                @(posedge clk);
                #1;
                if ((rstgen_rst_no !== 1'b0) || (rstgen_init_no !== 1'b0)) begin
                    fail_now("rstgen nha reset qua som truoc chu ky dong bo du kien.");
                end
            end

            @(posedge clk);
            #1;
            if ((rstgen_rst_no !== 1'b1) || (rstgen_init_no !== 1'b1)) begin
                fail_now("rstgen khong nha reset sau chuoi dong bo 5 FF.");
            end

            rstgen_test_mode_i = 1'b1;
            rstgen_rst_ni      = 1'b0;
            #1;
            if ((rstgen_rst_no !== 1'b0) || (rstgen_init_no !== 1'b1)) begin
                fail_now("rstgen test_mode bypass sai (rst_no/init_no).");
            end

            rstgen_rst_ni = 1'b1;
            #1;
            if ((rstgen_rst_no !== 1'b1) || (rstgen_init_no !== 1'b1)) begin
                fail_now("rstgen test_mode khong de outputs len 1 ngay.");
            end

            pass_note("rstgen reset sequence va test-mode bypass dung.");
        end
    endtask

    task automatic scenario_clock_gating_smoke();
        integer pulse_snapshot;
        begin
            cg_en_i       = 1'b0;
            cg_test_en_i  = 1'b0;
            cg_pulse_count = 0;

            repeat (4) @(posedge clk);
            #1;
            if (cg_pulse_count !== 0) begin
                fail_now("cluster_clock_gating phat xung du enable/test_en deu tat.");
            end

            @(negedge clk);
            cg_en_i = 1'b1;
            repeat (4) @(posedge clk);
            #1;
            if (cg_pulse_count < 3) begin
                fail_now("cluster_clock_gating khong mo clock khi enable = 1.");
            end

            pulse_snapshot = cg_pulse_count;
            @(negedge clk);
            cg_en_i = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            if (cg_pulse_count !== pulse_snapshot) begin
                fail_now("cluster_clock_gating khong chan clock sau khi tat enable.");
            end

            @(negedge clk);
            cg_test_en_i = 1'b1;
            repeat (3) @(posedge clk);
            #1;
            if (cg_pulse_count == pulse_snapshot) begin
                fail_now("cluster_clock_gating khong mo clock khi test_en = 1.");
            end

            cg_test_en_i = 1'b0;
            pass_note("cluster_clock_gating/pulp_clock_gating wrapper hoat dong dung.");
        end
    endtask

    task automatic scenario_generic_fifo_smoke();
        begin
            fifo_rst_n       = 1'b0;
            fifo_data_i      = 8'h00;
            fifo_valid_i     = 1'b0;
            fifo_grant_i     = 1'b0;
            fifo_test_mode_i = 1'b1;
            repeat (2) @(posedge clk);
            fifo_rst_n = 1'b1;
            @(posedge clk);
            #1;

            if ((fifo_valid_o !== 1'b0) || (fifo_grant_o !== 1'b1)) begin
                fail_now("generic_fifo khong vao trang thai EMPTY sau reset.");
            end

            fifo_push(8'h11);
            fifo_push(8'h22);
            fifo_push(8'h33);
            @(posedge clk);
            #1;
            if ((fifo_valid_o !== 1'b1) || (fifo_data_o !== 8'h11)) begin
                fail_now("generic_fifo khong dua du lieu dau tien ra front dung cach.");
            end

            fifo_expect_and_pop(8'h11);
            fifo_expect_and_pop(8'h22);

            fifo_push(8'h44);
            fifo_push(8'h55);
            fifo_expect_and_pop(8'h33);
            fifo_expect_and_pop(8'h44);
            fifo_expect_and_pop(8'h55);

            @(posedge clk);
            #1;
            if (fifo_valid_o !== 1'b0) begin
                fail_now("generic_fifo khong quay lai EMPTY sau khi pop het du lieu.");
            end

            fifo_push(8'hA1);
            fifo_push(8'hB2);
            fifo_push(8'hC3);
            fifo_push(8'hD4);
            @(posedge clk);
            #1;
            if (fifo_grant_o !== 1'b0) begin
                fail_now("generic_fifo khong bao FULL sau khi du 4 phan tu.");
            end

            fifo_expect_and_pop(8'hA1);
            @(posedge clk);
            #1;
            if (fifo_grant_o !== 1'b1) begin
                fail_now("generic_fifo khong nha FULL sau khi pop 1 phan tu.");
            end

            fifo_expect_and_pop(8'hB2);
            fifo_expect_and_pop(8'hC3);
            fifo_expect_and_pop(8'hD4);
            pass_note("generic_fifo push/pop/full-empty smoke test dung.");
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        rstgen_rst_ni      = 1'b0;
        rstgen_test_mode_i = 1'b0;
        cg_en_i            = 1'b0;
        cg_test_en_i       = 1'b0;
        fifo_rst_n         = 1'b0;
        fifo_data_i        = 8'h00;
        fifo_valid_i       = 1'b0;
        fifo_grant_i       = 1'b0;
        fifo_test_mode_i   = 1'b1;

        $display("\n============================================================");
        $display(" SUPPORT BLOCK SMOKE TEST");
        $display("============================================================");

        scenario_rstgen_smoke();
        scenario_clock_gating_smoke();
        scenario_generic_fifo_smoke();

        $display("------------------------------------------------------------");
        $display("[SUPPORT] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("------------------------------------------------------------");

        if (fail_count != 0) begin
            $fatal(1, "[SUPPORT] Co smoke test support block bi fail.");
        end
        $finish;
    end

endmodule
