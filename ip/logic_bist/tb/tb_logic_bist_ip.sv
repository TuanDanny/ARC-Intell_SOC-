`timescale 1ns/1ps

module tb_logic_bist_ip;

    localparam int CLK_PERIOD = 20;

    // Register offsets
    localparam logic [4:0] ADDR_CTRL      = 5'h00;
    localparam logic [4:0] ADDR_CONFIG    = 5'h04;
    localparam logic [4:0] ADDR_SEED      = 5'h08;
    localparam logic [4:0] ADDR_SIGNATURE = 5'h0C;
    localparam logic [4:0] ADDR_STATUS    = 5'h10;

    // DUT signals
    logic        clk_i;
    logic        rst_ni;
    logic [31:0] paddr_i;
    logic [31:0] pwdata_i;
    logic        psel_i;
    logic        penable_i;
    logic        pwrite_i;
    logic [31:0] prdata_o;
    logic        pready_o;
    logic        pslverr_o;
    logic [15:0] bist_data_o;
    logic        bist_valid_o;
    logic        bist_active_o;
    logic        dsp_irq_i;

    int pass_count;
    int fail_count;

    // =========================================================================
    // DUT
    // =========================================================================
    logic_bist #(
        .APB_ADDR_WIDTH(32),
        .APB_DATA_WIDTH(32)
    ) dut (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .paddr_i      (paddr_i),
        .pwdata_i     (pwdata_i),
        .psel_i       (psel_i),
        .penable_i    (penable_i),
        .pwrite_i     (pwrite_i),
        .prdata_o     (prdata_o),
        .pready_o     (pready_o),
        .pslverr_o    (pslverr_o),
        .bist_data_o  (bist_data_o),
        .bist_valid_o (bist_valid_o),
        .bist_active_o(bist_active_o),
        .dsp_irq_i    (dsp_irq_i)
    );

    // Clock
    initial begin
        clk_i = 1'b0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================================
    // Helpers
    // =========================================================================
    task automatic fail_now(input string label, input logic [31:0] actual, input logic [31:0] expected);
        begin
            fail_count++;
            $display("[BIST-IP][FAIL] %s expected=0x%08h actual=0x%08h", label, expected, actual);
            $display("[BIST-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
            $fatal(1, "[BIST-IP] stopping after first failure");
        end
    endtask

    task automatic expect32(input string label, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected) fail_now(label, actual, expected);
    endtask

    task automatic expect_bit(input string label, input logic actual, input logic expected);
        if (actual !== expected) fail_now(label, {31'd0, actual}, {31'd0, expected});
    endtask

    task automatic scenario_pass(input string label);
        begin pass_count++; $display("[BIST-IP][PASS] %s", label); end
    endtask

    task automatic reset_dut();
        begin
            rst_ni = 1'b0; paddr_i = 0; pwdata_i = 0; pwrite_i = 0;
            psel_i = 0; penable_i = 0; dsp_irq_i = 0;
            repeat (5) @(posedge clk_i);
            rst_ni = 1'b1;
            repeat (2) @(posedge clk_i);
        end
    endtask

    task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk_i); paddr_i = addr; pwdata_i = data;
            pwrite_i = 1; psel_i = 1; penable_i = 0;
            @(negedge clk_i); penable_i = 1;
            @(posedge clk_i); #1;
            @(negedge clk_i); psel_i = 0; penable_i = 0; pwrite_i = 0;
        end
    endtask

    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk_i); paddr_i = addr; pwrite_i = 0; psel_i = 1; penable_i = 0;
            @(negedge clk_i); penable_i = 1;
            @(posedge clk_i); #1; data = prdata_o;
            @(negedge clk_i); psel_i = 0; penable_i = 0;
        end
    endtask

    // =========================================================================
    // SC01: Reset defaults
    // =========================================================================
    task automatic sc01_reset_defaults();
        logic [31:0] rd;
        begin
            $display("[BIST-IP] SC01 reset defaults");
            reset_dut();

            apb_read({27'd0, ADDR_CONFIG}, rd);
            expect32("CONFIG reset", rd, 32'h0000_0064); // 100 cycles

            apb_read({27'd0, ADDR_SEED}, rd);
            expect32("SEED reset", rd, 32'h0000_ACE1);

            apb_read({27'd0, ADDR_STATUS}, rd);
            expect32("STATUS reset (idle)", rd, 32'h0000_0000); // not busy, not done

            expect_bit("bist_active_o low", bist_active_o, 1'b0);
            expect_bit("bist_valid_o low", bist_valid_o, 1'b0);

            scenario_pass("SC01 reset defaults");
        end
    endtask

    // =========================================================================
    // SC02: Run BIST, check active/valid, complete, signature
    // =========================================================================
    task automatic sc02_run_bist();
        logic [31:0] rd;
        int cycle_count;
        begin
            $display("[BIST-IP] SC02 run BIST cycle");
            reset_dut();

            // Configure short test
            apb_write({27'd0, ADDR_CONFIG}, 32'h0000_0010); // 16 cycles
            apb_write({27'd0, ADDR_SEED},   32'h0000_1234);

            // Provide fake dsp_irq_i toggling
            dsp_irq_i = 1'b0;

            // Start BIST
            apb_write({27'd0, ADDR_CTRL}, 32'h0000_0001);

            // Check busy/active
            @(posedge clk_i); @(posedge clk_i); #1;
            expect_bit("bist_active during run", bist_active_o, 1'b1);
            expect_bit("bist_valid during run", bist_valid_o, 1'b1);

            // bist_data_o should not be zero (LFSR output)
            if (bist_data_o === 16'd0) begin
                fail_now("LFSR output is zero during run", {16'd0, bist_data_o}, 32'h0000_0001);
            end

            // Toggle dsp_irq to create non-zero MISR
            repeat (8) begin
                @(posedge clk_i);
                dsp_irq_i = ~dsp_irq_i;
            end

            // Wait for completion
            cycle_count = 0;
            while (bist_active_o && cycle_count < 200) begin
                @(posedge clk_i);
                cycle_count++;
            end

            // Should be done now
            repeat (2) @(posedge clk_i);
            apb_read({27'd0, ADDR_STATUS}, rd);
            expect_bit("done flag", rd[1], 1'b1);
            expect_bit("not busy", rd[0], 1'b0);
            expect_bit("bist_active_o low after done", bist_active_o, 1'b0);

            // Read signature - should be non-zero since we toggled IRQ
            apb_read({27'd0, ADDR_SIGNATURE}, rd);
            if (rd[15:0] === 16'd0) begin
                fail_now("signature is zero with toggling IRQ", rd, 32'h0000_0001);
            end
            $display("[BIST-IP] Signature = 0x%04h", rd[15:0]);

            scenario_pass("SC02 run BIST cycle");
        end
    endtask

    // =========================================================================
    // SC03: BIST error detection (zero IRQ → zero signature)
    // =========================================================================
    task automatic sc03_zero_signature_error();
        logic [31:0] rd;
        int cycle_count;
        begin
            $display("[BIST-IP] SC03 zero signature error flag");
            reset_dut();

            apb_write({27'd0, ADDR_CONFIG}, 32'h0000_0010);
            dsp_irq_i = 1'b0; // Keep IRQ low → MISR stays 0

            // Start
            apb_write({27'd0, ADDR_CTRL}, 32'h0000_0001);

            // Wait for FSM to enter RUN first
            repeat (3) @(posedge clk_i);

            // Now wait for completion (bist_active goes low)
            cycle_count = 0;
            while (bist_active_o && cycle_count < 500) begin
                @(posedge clk_i);
                cycle_count++;
            end

            // If bist never went active, try just waiting a long time
            if (cycle_count == 0) begin
                repeat (50) @(posedge clk_i);
            end

            // Allow r_done_reg to settle (set in COMPLETE state)
            repeat (10) @(posedge clk_i);

            apb_read({27'd0, ADDR_STATUS}, rd);
            expect_bit("done flag", rd[1], 1'b1);
            expect_bit("error flag (zero sig)", rd[2], 1'b1);

            apb_read({27'd0, ADDR_SIGNATURE}, rd);
            expect32("signature is zero", rd, 32'h0000_0000);

            scenario_pass("SC03 zero signature error flag");
        end
    endtask

    // =========================================================================
    // SC04: Reset command clears state
    // =========================================================================
    task automatic sc04_reset_cmd();
        logic [31:0] rd;
        begin
            $display("[BIST-IP] SC04 reset command");
            reset_dut();

            apb_write({27'd0, ADDR_CONFIG}, 32'h0000_0010);
            apb_write({27'd0, ADDR_CTRL}, 32'h0000_0001); // start
            repeat (5) @(posedge clk_i);
            expect_bit("bist active mid-run", bist_active_o, 1'b1);

            // Send reset command
            apb_write({27'd0, ADDR_CTRL}, 32'h0000_0002);
            repeat (3) @(posedge clk_i);
            expect_bit("bist inactive after reset cmd", bist_active_o, 1'b0);

            apb_read({27'd0, ADDR_STATUS}, rd);
            expect_bit("not busy after reset", rd[0], 1'b0);
            expect_bit("not done after reset", rd[1], 1'b0);

            scenario_pass("SC04 reset command");
        end
    endtask

    // =========================================================================
    // SC05: Seed protection (zero seed → use default)
    // =========================================================================
    task automatic sc05_seed_protection();
        logic [31:0] rd;
        logic [15:0] data_capture;
        begin
            $display("[BIST-IP] SC05 seed protection");
            reset_dut();

            apb_write({27'd0, ADDR_SEED}, 32'h0000_0000); // zero seed
            apb_write({27'd0, ADDR_CONFIG}, 32'h0000_0004);
            apb_write({27'd0, ADDR_CTRL}, 32'h0000_0001); // start

            @(posedge clk_i); @(posedge clk_i); #1;
            data_capture = bist_data_o;

            // LFSR should NOT be zero (uses 0xACE1 as fallback)
            if (data_capture === 16'd0) begin
                fail_now("LFSR is zero with zero seed", {16'd0, data_capture}, 32'h0000_ACE1);
            end

            // Wait for done
            repeat (20) @(posedge clk_i);
            scenario_pass("SC05 seed protection");
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        sc01_reset_defaults();
        sc02_run_bist();
        sc03_zero_signature_error();
        sc04_reset_cmd();
        sc05_seed_protection();

        $display("[BIST-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) $finish;
        else $fatal(1, "[BIST-IP] regression failed");
    end

endmodule
