`timescale 1ns/1ps

module tb_safety_watchdog_ip;

    localparam int CLK_PERIOD = 20; // 50MHz

    // Register offsets
    localparam logic [3:0] ADDR_CTRL    = 4'h0;
    localparam logic [3:0] ADDR_TIMEOUT = 4'h4;
    localparam logic [3:0] ADDR_FEED    = 4'h8;
    localparam logic [3:0] ADDR_COUNT   = 4'hC;

    // Magic feed pattern
    localparam logic [31:0] FEED_PATTERN = 32'h0D09_F00D;

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
    logic        wdt_reset_o;

    int pass_count;
    int fail_count;

    // =========================================================================
    // DUT
    // =========================================================================
    safety_watchdog #(
        .APB_ADDR_WIDTH (32),
        .APB_DATA_WIDTH (32),
        .DEFAULT_TIMEOUT(32'h0000_00FF) // Short timeout for simulation
    ) dut (
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

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk_i = 1'b0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // =========================================================================
    // Helper tasks
    // =========================================================================
    task automatic fail_now(input string label, input logic [31:0] actual, input logic [31:0] expected);
        begin
            fail_count++;
            $display("[WDT-IP][FAIL] %s expected=0x%08h actual=0x%08h", label, expected, actual);
            $display("[WDT-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
            $fatal(1, "[WDT-IP] stopping after first failure");
        end
    endtask

    task automatic expect32(input string label, input logic [31:0] actual, input logic [31:0] expected);
        begin
            if (actual !== expected) fail_now(label, actual, expected);
        end
    endtask

    task automatic expect_bit(input string label, input logic actual, input logic expected);
        begin
            if (actual !== expected) fail_now(label, {31'd0, actual}, {31'd0, expected});
        end
    endtask

    task automatic scenario_pass(input string label);
        begin
            pass_count++;
            $display("[WDT-IP][PASS] %s", label);
        end
    endtask

    task automatic reset_dut();
        begin
            rst_ni    = 1'b0;
            paddr_i   = 32'd0;
            pwdata_i  = 32'd0;
            pwrite_i  = 1'b0;
            psel_i    = 1'b0;
            penable_i = 1'b0;
            repeat (5) @(posedge clk_i);
            rst_ni = 1'b1;
            repeat (2) @(posedge clk_i);
        end
    endtask

    task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk_i);
            paddr_i   = addr;
            pwdata_i  = data;
            pwrite_i  = 1'b1;
            psel_i    = 1'b1;
            penable_i = 1'b0;
            @(negedge clk_i);
            penable_i = 1'b1;
            @(posedge clk_i); #1;
            expect_bit("APB write pready", pready_o, 1'b1);
            @(negedge clk_i);
            psel_i = 1'b0; penable_i = 1'b0; pwrite_i = 1'b0;
        end
    endtask

    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk_i);
            paddr_i   = addr;
            pwrite_i  = 1'b0;
            psel_i    = 1'b1;
            penable_i = 1'b0;
            @(negedge clk_i);
            penable_i = 1'b1;
            @(posedge clk_i); #1;
            expect_bit("APB read pready", pready_o, 1'b1);
            data = prdata_o;
            @(negedge clk_i);
            psel_i = 1'b0; penable_i = 1'b0;
        end
    endtask

    // =========================================================================
    // SC01: Reset defaults
    // =========================================================================
    task automatic sc01_reset_defaults();
        logic [31:0] rd;
        begin
            $display("[WDT-IP] SC01 reset defaults");
            reset_dut();

            apb_read({28'd0, ADDR_CTRL}, rd);
            expect32("CTRL reset", rd, 32'h0000_0000); // enable=0, lock=0

            apb_read({28'd0, ADDR_TIMEOUT}, rd);
            expect32("TIMEOUT reset", rd, 32'h0000_00FF); // DEFAULT_TIMEOUT

            apb_read({28'd0, ADDR_COUNT}, rd);
            expect32("COUNT reset", rd, 32'h0000_00FF); // = timeout

            expect_bit("wdt_reset_o low", wdt_reset_o, 1'b0);

            scenario_pass("SC01 reset defaults");
        end
    endtask

    // =========================================================================
    // SC02: Enable, feed, counter decrements
    // =========================================================================
    task automatic sc02_enable_and_feed();
        logic [31:0] rd, rd2;
        begin
            $display("[WDT-IP] SC02 enable, feed, counter");
            reset_dut();

            // Set short timeout
            apb_write({28'd0, ADDR_TIMEOUT}, 32'h0000_0020);
            apb_read({28'd0, ADDR_TIMEOUT}, rd);
            expect32("TIMEOUT written", rd, 32'h0000_0020);

            // Counter should be updated since not enabled yet
            apb_read({28'd0, ADDR_COUNT}, rd);
            expect32("COUNT after timeout write", rd, 32'h0000_0020);

            // Enable WDT
            apb_write({28'd0, ADDR_CTRL}, 32'h0000_0001);
            apb_read({28'd0, ADDR_CTRL}, rd);
            expect32("CTRL enabled", rd, 32'h0000_0001);

            // Wait a few cycles, counter should decrement
            repeat (10) @(posedge clk_i);
            apb_read({28'd0, ADDR_COUNT}, rd);
            // Counter should be less than 0x20 by approx 10-12 cycles
            if (rd >= 32'h0000_0020) begin
                fail_now("counter did not decrement", rd, 32'h0000_0010);
            end

            // Feed with correct pattern
            apb_write({28'd0, ADDR_FEED}, FEED_PATTERN);

            // Counter should reload
            apb_read({28'd0, ADDR_COUNT}, rd);
            // Should be close to timeout value (allow 2 cycles for APB)
            if (rd < 32'h0000_001C) begin
                fail_now("counter not reloaded after feed", rd, 32'h0000_0020);
            end

            // Feed with wrong pattern → should NOT reload
            repeat (10) @(posedge clk_i);
            apb_read({28'd0, ADDR_COUNT}, rd);
            apb_write({28'd0, ADDR_FEED}, 32'hDEAD_BEEF);
            repeat (3) @(posedge clk_i);
            apb_read({28'd0, ADDR_COUNT}, rd2);
            if (rd2 >= rd) begin
                fail_now("wrong feed pattern reloaded counter", rd2, rd);
            end

            expect_bit("no reset yet", wdt_reset_o, 1'b0);
            scenario_pass("SC02 enable, feed, counter");
        end
    endtask

    // =========================================================================
    // SC03: Lock mechanism
    // =========================================================================
    task automatic sc03_lock();
        logic [31:0] rd;
        begin
            $display("[WDT-IP] SC03 lock mechanism");
            reset_dut();

            // Enable + Lock
            apb_write({28'd0, ADDR_CTRL}, 32'h0000_0003); // enable=1, lock=1
            apb_read({28'd0, ADDR_CTRL}, rd);
            expect32("CTRL locked", rd, 32'h0000_0003);

            // Try to disable → should fail (lock protects)
            apb_write({28'd0, ADDR_CTRL}, 32'h0000_0000);
            apb_read({28'd0, ADDR_CTRL}, rd);
            expect32("CTRL still locked+enabled", rd, 32'h0000_0003);

            // Try to change timeout while locked → should fail
            apb_write({28'd0, ADDR_TIMEOUT}, 32'h0000_FFFF);
            apb_read({28'd0, ADDR_TIMEOUT}, rd);
            expect32("TIMEOUT unchanged after lock", rd, 32'h0000_00FF);

            scenario_pass("SC03 lock mechanism");
        end
    endtask

    // =========================================================================
    // SC04: Watchdog timeout → reset output
    // =========================================================================
    task automatic sc04_timeout_reset();
        logic [31:0] rd;
        int timeout_cycles;
        begin
            $display("[WDT-IP] SC04 timeout → wdt_reset_o");
            reset_dut();

            // Very short timeout
            apb_write({28'd0, ADDR_TIMEOUT}, 32'h0000_0010);
            // Enable
            apb_write({28'd0, ADDR_CTRL}, 32'h0000_0001);

            // Wait for timeout + some margin
            timeout_cycles = 0;
            while (!wdt_reset_o && timeout_cycles < 200) begin
                @(posedge clk_i);
                timeout_cycles++;
            end

            expect_bit("wdt_reset_o asserted", wdt_reset_o, 1'b1);

            if (timeout_cycles > 50) begin
                fail_now("timeout took too long", timeout_cycles, 32);
            end

            // Reset pulse should stay for multiple cycles
            repeat (5) @(posedge clk_i);
            expect_bit("wdt_reset_o still high", wdt_reset_o, 1'b1);

            scenario_pass("SC04 timeout → wdt_reset_o");
        end
    endtask

    // =========================================================================
    // SC05: Disabled WDT holds counter
    // =========================================================================
    task automatic sc05_disabled_holds();
        logic [31:0] rd1, rd2;
        begin
            $display("[WDT-IP] SC05 disabled WDT holds counter");
            reset_dut();

            // Don't enable — counter should stay at timeout
            repeat (20) @(posedge clk_i);
            apb_read({28'd0, ADDR_COUNT}, rd1);
            repeat (20) @(posedge clk_i);
            apb_read({28'd0, ADDR_COUNT}, rd2);

            expect32("counter stable when disabled", rd1, rd2);
            expect_bit("no reset when disabled", wdt_reset_o, 1'b0);

            scenario_pass("SC05 disabled WDT holds counter");
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        sc01_reset_defaults();
        sc02_enable_and_feed();
        sc03_lock();
        sc04_timeout_reset();
        sc05_disabled_holds();

        $display("[WDT-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) $finish;
        else $fatal(1, "[WDT-IP] regression failed");
    end

endmodule
