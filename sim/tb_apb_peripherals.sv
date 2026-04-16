`timescale 1ns/1ps

module tb_apb_peripherals;

    logic clk;
    logic low_speed_clk;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial low_speed_clk = 1'b0;
    always #13 low_speed_clk = ~low_speed_clk;

    integer pass_count;
    integer fail_count;

    task automatic pass_note(input string msg);
        begin
            pass_count = pass_count + 1;
            $display("[PERIPH][PASS] %s", msg);
        end
    endtask

    task automatic fail_now(input string msg);
        begin
            fail_count = fail_count + 1;
            $display("[PERIPH][FAIL] %s", msg);
            $stop;
        end
    endtask

    // ------------------------------------------------------------------
    // GPIO DUT
    // ------------------------------------------------------------------
    logic        gpio_rst_n;
    logic [11:0] gpio_paddr;
    logic [31:0] gpio_pwdata;
    logic        gpio_pwrite;
    logic        gpio_psel;
    logic        gpio_penable;
    logic [31:0] gpio_prdata;
    logic        gpio_pready;
    logic        gpio_pslverr;
    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_dir;
    logic        gpio_interrupt;

    apb_gpio #(
        .APB_ADDR_WIDTH (12),
        .PAD_NUM        (8)
    ) u_gpio (
        .HCLK      (clk),
        .HRESETn   (gpio_rst_n),
        .PADDR     (gpio_paddr),
        .PWDATA    (gpio_pwdata),
        .PWRITE    (gpio_pwrite),
        .PSEL      (gpio_psel),
        .PENABLE   (gpio_penable),
        .PRDATA    (gpio_prdata),
        .PREADY    (gpio_pready),
        .PSLVERR   (gpio_pslverr),
        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_dir  (gpio_dir),
        .interrupt (gpio_interrupt)
    );

    // ------------------------------------------------------------------
    // UART DUT
    // ------------------------------------------------------------------
    logic        uart_rst_n;
    logic [31:0] uart_paddr;
    logic [31:0] uart_pwdata;
    logic        uart_pwrite;
    logic        uart_psel;
    logic        uart_penable;
    logic [31:0] uart_prdata;
    logic        uart_pready;
    logic        uart_pslverr;
    logic        uart_tx;
    logic        uart_rx;
    logic        uart_intr;

    apb_uart_wrap u_uart (
        .clk_i     (clk),
        .rst_ni    (uart_rst_n),
        .paddr_i   (uart_paddr),
        .pwdata_i  (uart_pwdata),
        .pwrite_i  (uart_pwrite),
        .psel_i    (uart_psel),
        .penable_i (uart_penable),
        .prdata_o  (uart_prdata),
        .pready_o  (uart_pready),
        .pslverr_o (uart_pslverr),
        .sout_o    (uart_tx),
        .sin_i     (uart_rx),
        .intr_o    (uart_intr),
        .cts_ni    (1'b0)
    );

    // ------------------------------------------------------------------
    // TIMER DUT
    // ------------------------------------------------------------------
    logic        timer_rst_n;
    logic [11:0] timer_paddr;
    logic [31:0] timer_pwdata;
    logic        timer_pwrite;
    logic        timer_psel;
    logic        timer_penable;
    logic [31:0] timer_prdata;
    logic        timer_pready;
    logic        timer_pslverr;
    logic [31:0] timer_ext_sig;
    logic [3:0]  timer_events;
    logic [3:0]  timer_ch0;
    logic [3:0]  timer_ch1;
    logic [3:0]  timer_ch2;
    logic [3:0]  timer_ch3;
    logic        timer_event0_seen;

    apb_adv_timer #(
        .APB_ADDR_WIDTH (12),
        .EXTSIG_NUM     (32),
        .TIMER_NBITS    (16)
    ) u_timer (
        .HCLK            (clk),
        .HRESETn         (timer_rst_n),
        .PADDR           (timer_paddr),
        .PWDATA          (timer_pwdata),
        .PWRITE          (timer_pwrite),
        .PSEL            (timer_psel),
        .PENABLE         (timer_penable),
        .PRDATA          (timer_prdata),
        .PREADY          (timer_pready),
        .PSLVERR         (timer_pslverr),
        .dft_cg_enable_i (1'b0),
        .low_speed_clk_i (low_speed_clk),
        .ext_sig_i       (timer_ext_sig),
        .events_o        (timer_events),
        .ch_0_o          (timer_ch0),
        .ch_1_o          (timer_ch1),
        .ch_2_o          (timer_ch2),
        .ch_3_o          (timer_ch3)
    );

    always_ff @(posedge clk or negedge timer_rst_n) begin
        if (!timer_rst_n) begin
            timer_event0_seen <= 1'b0;
        end else if (timer_events[0]) begin
            timer_event0_seen <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Generic APB helpers
    // ------------------------------------------------------------------
    task automatic gpio_apb_write(input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            gpio_paddr   = addr;
            gpio_pwdata  = data;
            gpio_pwrite  = 1'b1;
            gpio_psel    = 1'b1;
            gpio_penable = 1'b0;
            @(posedge clk);
            #1;
            gpio_penable = 1'b1;
            @(posedge clk);
            #1;
            gpio_psel    = 1'b0;
            gpio_penable = 1'b0;
            gpio_pwrite  = 1'b0;
            gpio_pwdata  = 32'd0;
        end
    endtask

    task automatic gpio_apb_read(input [11:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            gpio_paddr   = addr;
            gpio_pwrite  = 1'b0;
            gpio_psel    = 1'b1;
            gpio_penable = 1'b0;
            @(posedge clk);
            #1;
            gpio_penable = 1'b1;
            #1;
            data = gpio_prdata;
            @(posedge clk);
            #1;
            gpio_psel    = 1'b0;
            gpio_penable = 1'b0;
        end
    endtask

    task automatic uart_apb_write(input [31:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            uart_paddr   = addr;
            uart_pwdata  = data;
            uart_pwrite  = 1'b1;
            uart_psel    = 1'b1;
            uart_penable = 1'b0;
            @(posedge clk);
            #1;
            uart_penable = 1'b1;
            @(posedge clk);
            #1;
            uart_psel    = 1'b0;
            uart_penable = 1'b0;
            uart_pwrite  = 1'b0;
            uart_pwdata  = 32'd0;
        end
    endtask

    task automatic uart_apb_read(input [31:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            uart_paddr   = addr;
            uart_pwrite  = 1'b0;
            uart_psel    = 1'b1;
            uart_penable = 1'b0;
            @(posedge clk);
            #1;
            uart_penable = 1'b1;
            #1;
            data = uart_prdata;
            @(posedge clk);
            #1;
            uart_psel    = 1'b0;
            uart_penable = 1'b0;
        end
    endtask

    task automatic timer_apb_write(input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            timer_paddr   = addr;
            timer_pwdata  = data;
            timer_pwrite  = 1'b1;
            timer_psel    = 1'b1;
            timer_penable = 1'b0;
            @(posedge clk);
            #1;
            timer_penable = 1'b1;
            @(posedge clk);
            #1;
            timer_psel    = 1'b0;
            timer_penable = 1'b0;
            timer_pwrite  = 1'b0;
            timer_pwdata  = 32'd0;
        end
    endtask

    task automatic timer_apb_read(input [11:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            timer_paddr   = addr;
            timer_pwrite  = 1'b0;
            timer_psel    = 1'b1;
            timer_penable = 1'b0;
            @(posedge clk);
            #1;
            timer_penable = 1'b1;
            #1;
            data = timer_prdata;
            @(posedge clk);
            #1;
            timer_psel    = 1'b0;
            timer_penable = 1'b0;
        end
    endtask

    task automatic uart_drive_rx_byte(input [7:0] data_byte, input integer bit_ticks);
        begin
            uart_rx = 1'b1;
            repeat (bit_ticks) @(posedge clk);
            uart_rx = 1'b0; // start bit
            repeat (bit_ticks) @(posedge clk);
            for (int bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data_byte[bit_idx];
                repeat (bit_ticks) @(posedge clk);
            end
            uart_rx = 1'b1; // stop bit
            repeat (bit_ticks) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Scenarios
    // ------------------------------------------------------------------
    task automatic scenario_gpio_smoke();
        logic [31:0] read_data;
        begin
            gpio_rst_n   = 1'b0;
            gpio_in      = 8'h00;
            gpio_paddr   = '0;
            gpio_pwdata  = '0;
            gpio_pwrite  = 1'b0;
            gpio_psel    = 1'b0;
            gpio_penable = 1'b0;
            repeat (2) @(posedge clk);
            gpio_rst_n = 1'b1;
            repeat (2) @(posedge clk);

            gpio_apb_read(12'h000, read_data);
            if (read_data[7:0] !== 8'h00) begin
                fail_now($sformatf("GPIO PADDIR reset sai: 0x%02h", read_data[7:0]));
            end

            gpio_apb_write(12'h000, 32'h0000_0001);
            gpio_apb_write(12'h008, 32'h0000_0001);
            #1;
            if ((gpio_dir !== 8'h01) || (gpio_out !== 8'h01)) begin
                fail_now($sformatf("GPIO dir/out sai. dir=0x%02h out=0x%02h", gpio_dir, gpio_out));
            end

            gpio_in = 8'hA4;
            repeat (3) @(posedge clk);
            gpio_apb_read(12'h004, read_data);
            if (read_data[7:0] !== 8'hA4) begin
                fail_now($sformatf("GPIO DATAIN readback sai: 0x%02h", read_data[7:0]));
            end

            gpio_apb_write(12'h00C, 32'h0000_0002);
            gpio_in[1] = 1'b0;
            repeat (3) @(posedge clk);
            gpio_in[1] = 1'b1;
            repeat (3) @(posedge clk);
            if (gpio_interrupt !== 1'b1) begin
                fail_now("GPIO interrupt khong len khi input bit1 co canh len va INTEN bat.");
            end

            pass_note("apb_gpio read/write, sync input va interrupt hoat dong dung.");
        end
    endtask

    task automatic scenario_uart_smoke();
        logic [31:0] status_data;
        logic [31:0] rx_data;
        begin
            uart_rst_n   = 1'b0;
            uart_rx      = 1'b1;
            uart_paddr   = '0;
            uart_pwdata  = '0;
            uart_pwrite  = 1'b0;
            uart_psel    = 1'b0;
            uart_penable = 1'b0;
            repeat (2) @(posedge clk);
            uart_rst_n = 1'b1;
            repeat (2) @(posedge clk);

            uart_apb_write(32'h0000_0008, 32'd8);
            uart_apb_write(32'h0000_0000, 32'h0000_005A);

            fork
                begin
                    wait (uart_tx == 1'b0);
                end
                begin
                    repeat (40) @(posedge clk);
                    fail_now("UART TX khong phat start bit sau khi ghi TXDATA.");
                end
            join_any
            disable fork;

            uart_apb_read(32'h0000_0004, status_data);
            if (status_data[0] !== 1'b1) begin
                fail_now("UART status khong bao TX busy trong luc dang truyen.");
            end

            fork
                begin
                    wait (uart_tx == 1'b1);
                    repeat (12) @(posedge clk);
                end
                begin
                    repeat (200) @(posedge clk);
                    fail_now("UART TX khong quay ve idle sau khi truyen.");
                end
            join_any
            disable fork;

            uart_drive_rx_byte(8'h3C, 8);
            fork
                begin
                    wait (uart_intr == 1'b1);
                end
                begin
                    repeat (160) @(posedge clk);
                    fail_now("UART RX khong bao intr_o sau khi nhan byte hop le.");
                end
            join_any
            disable fork;

            uart_apb_read(32'h0000_0004, status_data);
            if (status_data[1] !== 1'b1) begin
                fail_now("UART status khong bao RX valid sau khi nhan byte.");
            end

            uart_apb_read(32'h0000_0000, rx_data);
            if (rx_data[7:0] !== 8'h3C) begin
                fail_now($sformatf("UART RX data sai. read=0x%02h", rx_data[7:0]));
            end

            uart_apb_read(32'h0000_0004, status_data);
            if (status_data[1] !== 1'b0) begin
                fail_now("UART RX valid khong duoc clear sau khi doc DATA.");
            end

            pass_note("apb_uart_wrap TX/RX, status va interrupt hoat dong dung.");
        end
    endtask

    task automatic scenario_timer_smoke();
        logic [31:0] read_data;
        begin
            timer_rst_n   = 1'b0;
            timer_ext_sig = 32'd0;
            timer_event0_seen = 1'b0;
            timer_paddr   = '0;
            timer_pwdata  = '0;
            timer_pwrite  = 1'b0;
            timer_psel    = 1'b0;
            timer_penable = 1'b0;
            repeat (2) @(posedge clk);
            timer_rst_n = 1'b1;
            repeat (2) @(posedge clk);

            // Enable timer0 gated clock.
            timer_apb_write(12'h104, 32'h0000_0001);
            // Timer0 CFG: prescaler=0, saw=1, in_clk=0, mode=000(always), in_sel=0.
            timer_apb_write(12'h004, 32'h0000_1000);
            // Timer0 TH: end=3, start=0.
            timer_apb_write(12'h008, 32'h0003_0000);
            // Timer0 CH0_TH: comparator threshold=2, op=SET.
            timer_apb_write(12'h00C, 32'h0000_0002);
            // Route ch0 rising edge to event0 and enable event0.
            timer_apb_write(12'h100, 32'h0001_0000);
            // Start timer0.
            timer_apb_write(12'h000, 32'h0000_0001);

            repeat (10) @(posedge clk);
            timer_apb_read(12'h02C, read_data);
            if (read_data[15:0] == 16'h0000) begin
                fail_now("Timer0 counter khong tang sau khi config/start qua APB.");
            end

            fork
                begin
                    wait (timer_ch0[0] == 1'b1);
                end
                begin
                    repeat (40) @(posedge clk);
                    fail_now("Timer0 comparator channel 0 khong len muc 1 sau khi counter dat threshold.");
                end
            join_any
            disable fork;

            fork
                begin
                    repeat (40) @(posedge clk);
                    if (timer_event0_seen !== 1'b1) begin
                        fail_now("Timer0 event0 khong pulse sau khi route ch0 rising edge.");
                    end
                end
            join_any
            disable fork;

            pass_note("apb_adv_timer config/start/counter/event duong co ban hoat dong dung.");
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        scenario_gpio_smoke();
        scenario_uart_smoke();
        scenario_timer_smoke();

        $display("[PERIPH] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end

endmodule
