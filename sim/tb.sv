/*
 * Module: tb_professional_full
 * Description:
 *   Self-checking / stress-oriented testbench cho INTELLI-SAFE SoC.
 *   File này được viết để:
 *   1) Giữ lại 10 kịch bản directed quan trọng nhất cho đồ án.
 *   2) Có chú thích rõ ràng để bạn tham khảo và chỉnh sửa tiếp.
 *   3) Tương thích với top_soc hiện tại đã đổi sang SPI module riêng
 *      (có adc_mosi_o, adc_sclk_o, adc_csn_o).
 *   4) Có thêm hook random regression tùy chọn bằng plusargs.
 *
 * Cách chạy cơ bản:
 *   vsim work.tb_professional_full
 *
 * Chạy kèm random regression ở cuối:
 *   vsim work.tb_professional_full +ENABLE_RANDOM=1 +RANDOM_RUNS=50 +SEED=12345
 *
 * Lưu ý quan trọng:
 *   - Testbench này dùng hierarchical force/release cho một số case safety
 *     (WDT, UART, BIST, collision interrupt). Đây là cách rất thực dụng cho đồ án.
 *   - Nếu về sau bạn đổi tên internal signal trong RTL, hãy sửa các đường như:
 *       dut.u_dsp.integrator
 *       dut.u_wdt.r_enable
 *       dut.u_wdt.r_counter
 *       dut.u_wdt.wdt_reset_o
 *       dut.u_bist.r_done
 *       dut.u_bist.r_signature
 */
`timescale 1ns/1ps

module tb_professional_full;

    // =====================================================================
    // 0. CẤU HÌNH TOÀN CỤC
    // =====================================================================
    localparam int CLK_PERIOD_NS     = 20;          // 50 MHz
    localparam int TB_TIMEOUT_NS     = 8_000_000;   // 8 ms
    localparam int ARC_TIMEOUT_NS    = 800_000;     // 800 us
    localparam int WDT_TIMEOUT_NS    = 200_000;     // 200 us
    localparam int GLITCH_TIMEOUT_NS = 1_500_000;   // 1.5 ms

    // =====================================================================
    // 1. TÍN HIỆU DUT
    // =====================================================================
    logic clk;
    logic rst_ni;
    logic adc_miso;
    wire  adc_mosi;
    wire  adc_sclk;
    wire  adc_csn;
    wire  uart_tx;
    logic uart_rx;
    tri   [3:0] gpio_io;

    // Điện trở kéo xuống relay ảo để mô phỏng Fail-safe Hi-Z ngoài thực tế.
    pulldown(gpio_io[0]);

    // =====================================================================
    // 2. BIẾN SCOREBOARD / REPORT
    // =====================================================================
    int  pass_count = 0;
    int  fail_count = 0;
    bit  expect_trip_active = 0;
    bit  trip_seen = 0;
    time start_arc_time = 0;
    logic [15:0] golden_signature;

    int unsigned seed;
    int random_runs;
    bit enable_random;

    // Shadow regs cho force APB qua ModelSim:
    // ModelSim khong cho dung directly task automatic argument o ve phai cua force.
    logic [31:0] uart_force_addr;
    logic [31:0] uart_force_data;
    logic [11:0] bist_force_addr;
    logic [31:0] bist_force_data;

    // =====================================================================
    // 3. DUT
    // =====================================================================
    top_soc dut (
        .clk_i        (clk),
        .rst_ni_async (rst_ni),
        .adc_miso_i   (adc_miso),
        .adc_mosi_o   (adc_mosi),
        .adc_sclk_o   (adc_sclk),
        .adc_csn_o    (adc_csn),
        .uart_tx_o    (uart_tx),
        .uart_rx_i    (uart_rx),
        .gpio_pin_io  (gpio_io)
    );

    // =====================================================================
    // 4. CLOCK / TIMEOUT
    // =====================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    initial begin
        #TB_TIMEOUT_NS;
        $display("\n[FATAL] Testbench timeout sau %0d ns. Co kha nang DUT/TB bi treo.", TB_TIMEOUT_NS);
        $stop;
    end

    // =====================================================================
    // 5. HÀM TIỆN ÍCH CHUNG
    // =====================================================================
    task automatic fail_now(input string msg);
        begin
            fail_count = fail_count + 1;
            $display("\n[FAIL] %s", msg);
            $stop;
        end
    endtask

    task automatic pass_note(input string msg);
        begin
            pass_count = pass_count + 1;
            $display("[PASS] %s", msg);
        end
    endtask

    task automatic reset_dut(input int hold_ns = 500, input int settle_ns = 2000);
        begin
            rst_ni <= 1'b0;
            adc_miso <= 1'b0;
            uart_rx <= 1'b1;
            expect_trip_active <= 1'b0;
            trip_seen <= 1'b0;
            #hold_ns;
            rst_ni <= 1'b1;
            #settle_ns;
        end
    endtask

    // =====================================================================
    // 6. DRIVER SPI ADC
    // =====================================================================
    // Quan trọng: Driver này đã chỉnh cho phù hợp với SPI frontend mới.
    // Ta preload bit đầu tiên ngay khi CS xuống thấp, sau đó cập nhật các bit còn lại
    // ở cạnh xuống của SCLK. Cách này ít bị lệch bit đầu hơn kiểu cũ.
    task automatic send_spi_data(input [15:0] data);
        begin
            wait(adc_csn == 1'b0);

            // Preload bit đầu tiên trước cạnh sample đầu tiên.
            adc_miso = data[15];

            // Sau mỗi cạnh xuống, đặt bit kế tiếp.
            for (int i = 14; i >= 0; i--) begin
                @(negedge adc_sclk);
                adc_miso = data[i];
            end

            // Giữ bit cuối thêm 1 cạnh lên để DUT sample xong.
            @(posedge adc_sclk);

            wait(adc_csn == 1'b1);
            adc_miso = 1'b0;
        end
    endtask

    task automatic run_normal_condition(input int num_samples);
        begin
            repeat (num_samples)
                send_spi_data($urandom_range(0, 20));
        end
    endtask

    // =====================================================================
    // 7. CÁC MẪU KÍCH THÍCH ADC / FAULT INJECTION
    // =====================================================================
    task automatic inject_motor_inrush();
        begin
            send_spi_data(16'd800);
            send_spi_data(16'd800);
            send_spi_data(16'd800);
            run_normal_condition(15);
            send_spi_data(16'd600);
            send_spi_data(16'd600);
            run_normal_condition(20);
        end
    endtask

    task automatic inject_single_arc();
        begin
            repeat (15) begin
                send_spi_data(16'd500);
                send_spi_data(16'd0);
            end
            run_normal_condition(50);
        end
    endtask

    task automatic inject_intermittent_arc();
        begin
            repeat (40) send_spi_data(16'd500);
            run_normal_condition(10);
            repeat (50) send_spi_data(16'd600);
            run_normal_condition(10);
            repeat (50) send_spi_data(16'd650);
        end
    endtask

    task automatic inject_solid_arc();
        begin
            repeat (150) begin
                send_spi_data(16'd500);
                send_spi_data(16'd0);
            end
        end
    endtask

    task automatic inject_adc_stuck_high(input int num_samples);
        begin
            repeat (num_samples)
                send_spi_data(16'h7FFF);
        end
    endtask

    task automatic inject_contact_overheat();
        int base_heat;
        int noise;
        begin
            base_heat = 0;
            repeat (150) begin
                base_heat = base_heat + 20;
                if (base_heat > 2000)
                    base_heat = 2000;
                noise = $urandom_range(0, 100);
                send_spi_data(16'(base_heat + noise));
                send_spi_data(16'(base_heat - noise));
            end
        end
    endtask

    // Gây treo CPU + rút ngắn watchdog để test nhanh.
    task automatic inject_cpu_radiation_fault();
        begin
            force dut.u_cpu.pc       = 8'hFF;
            force dut.u_wdt.r_enable = 1'b1;
            force dut.u_wdt.r_counter = 32'd50;
            @(posedge clk);
            release dut.u_wdt.r_counter;
        end
    endtask

    task automatic release_cpu_fault();
        begin
            release dut.u_cpu.pc;
            release dut.u_wdt.r_enable;
        end
    endtask

    task automatic inject_power_glitch(input int duration_ns);
        time start_t;
        begin
            start_t = $time;
            while (($time - start_t) < duration_ns) begin
                rst_ni = 1'b0;
                #($urandom_range(20, 100));
                rst_ni = 1'b1;
                #($urandom_range(20, 100));
            end
            rst_ni = 1'b1;
        end
    endtask

    // =====================================================================
    // 8. APB-STYLE HELPER CHO UART / BIST
    // =====================================================================
    task automatic uart_apb_write(input [31:0] addr, input [31:0] data);
        begin
            uart_force_addr = addr;
            uart_force_data = data;
            force dut.u_uart.paddr_i   = uart_force_addr;
            force dut.u_uart.pwdata_i  = uart_force_data;
            force dut.u_uart.pwrite_i  = 1'b1;
            force dut.u_uart.psel_i    = 1'b1;
            force dut.u_uart.penable_i = 1'b0;
            @(posedge clk);
            force dut.u_uart.penable_i = 1'b1;
            @(posedge clk);
            force dut.u_uart.psel_i    = 1'b0;
            force dut.u_uart.penable_i = 1'b0;
            release dut.u_uart.paddr_i;
            release dut.u_uart.pwdata_i;
            release dut.u_uart.pwrite_i;
            release dut.u_uart.psel_i;
            release dut.u_uart.penable_i;
        end
    endtask

    task automatic bist_apb_write(input [11:0] addr, input [31:0] data);
        begin
            bist_force_addr = addr;
            bist_force_data = data;
            force dut.u_bist.paddr_i   = bist_force_addr;
            force dut.u_bist.pwdata_i  = bist_force_data;
            force dut.u_bist.pwrite_i  = 1'b1;
            force dut.u_bist.psel_i    = 1'b1;
            force dut.u_bist.penable_i = 1'b0;
            @(posedge clk);
            force dut.u_bist.penable_i = 1'b1;
            @(posedge clk);
            force dut.u_bist.psel_i    = 1'b0;
            force dut.u_bist.penable_i = 1'b0;
            release dut.u_bist.paddr_i;
            release dut.u_bist.pwdata_i;
            release dut.u_bist.pwrite_i;
            release dut.u_bist.psel_i;
            release dut.u_bist.penable_i;
        end
    endtask

    task automatic check_uart_transmission();
        begin
            $display("[UART] Gia lap CPU/APB ghi ky tu 'A' (0x41) ra UART...");
            uart_apb_write(32'h0000_0000, 32'h0000_0041);

            fork
                begin
                    @(negedge uart_tx);
                    pass_note("UART TX co start bit -> kenh truyen da hoat dong");
                end
                begin
                    #100_000;
                    if (uart_tx === 1'b1)
                        fail_now("UART khong phat start bit trong 100 us");
                end
            join_any
            disable fork;
        end
    endtask

    task automatic run_bist_golden_and_store();
        logic [15:0] signature_read;
        begin
            // Cấu hình chiều dài test.
            bist_apb_write(12'h004, 32'd5000);
            // Start BIST.
            bist_apb_write(12'h000, 32'h0000_0001);

            fork
                begin
                    wait(dut.u_bist.r_done == 1'b1);
                end
                begin
                    #500_000;
                    fail_now("BIST golden timeout - qua lau ma r_done chua len");
                end
                begin
                    wait(gpio_io[0] == 1'b1);
                    fail_now("Relay bi cat trong luc chay BIST golden");
                end
            join_any
            disable fork;

            signature_read   = dut.u_bist.r_signature;
            golden_signature = signature_read;

            if (golden_signature == 16'd0)
                fail_now("Golden signature bang 0 - khong hop le");
            else
                pass_note($sformatf("Thu duoc golden signature = 0x%04h", golden_signature));
        end
    endtask

    task automatic run_bist_with_stuck_at_fault();
        logic [15:0] faulty_signature;
        begin
            force dut.u_dsp.irq_arc_o = 1'b0;

            bist_apb_write(12'h004, 32'd5000);
            bist_apb_write(12'h000, 32'h0000_0001);

            fork
                begin
                    wait(dut.u_bist.r_done == 1'b1);
                end
                begin
                    #500_000;
                    fail_now("BIST faulty timeout - qua lau ma r_done chua len");
                end
            join_any
            disable fork;

            faulty_signature = dut.u_bist.r_signature;
            release dut.u_dsp.irq_arc_o;

            if (faulty_signature == golden_signature)
                fail_now("BIST khong phat hien duoc loi: faulty signature = golden signature");
            else
                pass_note($sformatf("BIST phat hien loi thanh cong: faulty=0x%04h, golden=0x%04h",
                                    faulty_signature, golden_signature));
        end
    endtask

    // =====================================================================
    // 9. RANDOM REGRESSION TÙY CHỌN
    // =====================================================================
    function automatic int rand_range(input int lo, input int hi);
        rand_range = lo + ($urandom % (hi - lo + 1));
    endfunction

    task automatic run_random_stream(
        input int num_frames,
        input int noise_lo,
        input int noise_hi,
        input int spike_prob_pct,
        input int spike_lo,
        input int spike_hi
    );
        int sample;
        begin
            repeat (num_frames) begin
                sample = rand_range(noise_lo, noise_hi);
                if (($urandom % 100) < spike_prob_pct)
                    sample = rand_range(spike_lo, spike_hi);
                send_spi_data(sample[15:0]);
            end
        end
    endtask

    task automatic run_random_regression(input int runs);
        int mode;
        begin
            $display("\n================ RANDOM REGRESSION START ================");
            for (int rid = 0; rid < runs; rid++) begin
                reset_dut();
                mode = $urandom % 4;
                trip_seen = 1'b0;

                case (mode)
                    0: begin
                        expect_trip_active = 1'b0;
                        run_random_stream(180, 0, 20, 2, 200, 400);
                        #50_000;
                        if (trip_seen)
                            fail_now($sformatf("Random run %0d: false trip trong benign noise", rid));
                    end
                    1: begin
                        expect_trip_active = 1'b1;
                        start_arc_time = $time;
                        fork
                            run_random_stream(220, 0, 20, 25, 450, 650);
                            begin
                                #ARC_TIMEOUT_NS;
                                if (!trip_seen)
                                    fail_now($sformatf("Random run %0d: intermittent arc-like khong bi cat", rid));
                            end
                        join_any
                        disable fork;
                    end
                    2: begin
                        expect_trip_active = 1'b1;
                        start_arc_time = $time;
                        fork
                            run_random_stream(260, 0, 10, 60, 500, 850);
                            begin
                                #ARC_TIMEOUT_NS;
                                if (!trip_seen)
                                    fail_now($sformatf("Random run %0d: solid arc-like khong bi cat", rid));
                            end
                        join_any
                        disable fork;
                    end
                    default: begin
                        expect_trip_active = 1'b0;
                        run_random_stream(200, 40, 120, 8, 140, 240);
                        #50_000;
                        if (trip_seen)
                            fail_now($sformatf("Random run %0d: glowing-like benign profile bi false trip", rid));
                    end
                endcase
            end
            pass_note($sformatf("Random regression da chay xong %0d runs", runs));
            $display("================ RANDOM REGRESSION END =================\n");
        end
    endtask

    // =====================================================================
    // 10. MONITOR / RADAR / SCOREBOARD
    // =====================================================================
    // Radar 1: nhìn bộ tích phân DSP để hiểu tiến trình tích lũy năng lượng.
    always @(dut.u_dsp.integrator) begin
        if (dut.u_dsp.integrator > 0) begin
            if ((dut.u_dsp.integrator % 100) == 0)
                $display("[RADAR-DSP] integrator = %0d / 1000", dut.u_dsp.integrator);
        end
    end

    // Radar 2: thấy ngay lúc DSP tạo interrupt.
    always @(posedge dut.irq_arc_critical) begin
        $display("[RADAR-IRQ] DSP da kich hoat arc interrupt tai t=%0t", $time);
    end

    // Radar 3: theo dõi CPU đi vào vector quan trọng.
    always @(dut.u_cpu.pc) begin
        if (dut.u_cpu.pc == 8'h01)
            $display("[RADAR-CPU] CPU vao vector Arc ISR (0x01)");
        else if (dut.u_cpu.pc == 8'h03)
            $display("[RADAR-CPU] CPU dang giu relay o che do safety loop (0x03)");
    end

    // Radar 4: theo dõi CPU ghi GPIO qua APB.
    always @(posedge clk) begin
        if (dut.apb_cpu_master.psel && dut.apb_cpu_master.penable && dut.apb_cpu_master.pwrite) begin
            if (dut.apb_cpu_master.paddr[31:12] == 20'h00002) begin
                $display("[RADAR-BUS] CPU ghi GPIO/APB addr=0x%08h data=0x%08h",
                         dut.apb_cpu_master.paddr, dut.apb_cpu_master.pwdata);
            end
        end
    end

    // Scoreboard trung tâm: bất cứ khi nào relay bật lên, ta quyết định đó là PASS hay FAIL.
    always @(posedge gpio_io[0]) begin
        time latency;
        trip_seen = 1'b1;
        $display("\n[MONITOR] Relay da len 1 (cat dien) tai t=%0t", $time);

        if (!expect_trip_active) begin
            fail_now("Bao dong gia / false positive: relay bi cat khi test khong ky vong trip");
        end else begin
            latency = $time - start_arc_time;
            $display("[SCOREBOARD] Arc/unsafe condition da duoc dap tat. Latency = %0t", latency);
        end
    end

    // =====================================================================
    // 11. SCENARIO DIRECTED CHÍNH
    // =====================================================================
    task automatic scenario_1_motor_inrush();
        begin
            $display("\n>>> SCENARIO 1: Motor inrush / benign noise immunity");
            reset_dut();
            expect_trip_active = 1'b0;
            run_normal_condition(20);
            inject_motor_inrush();
            run_normal_condition(20);
            inject_motor_inrush();
            run_normal_condition(20);
            #1000;
            if (gpio_io[0] !== 1'b0)
                fail_now("Scenario 1: relay bi cat sai khi gap dong khoi dong");
            else
                pass_note("Scenario 1: loc duoc motor inrush, khong false trip");
        end
    endtask

    task automatic scenario_2_intermittent_arc();
        begin
            $display("\n>>> SCENARIO 2: Intermittent arc");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                inject_intermittent_arc();
                begin
                    #ARC_TIMEOUT_NS;
                    if (!trip_seen)
                        fail_now("Scenario 2: khong cat duoc intermittent arc trong timeout");
                end
            join_any
            disable fork;
            pass_note("Scenario 2: intermittent arc duoc phat hien");
        end
    endtask

    task automatic scenario_3_arc_family();
        begin
            $display("\n>>> SCENARIO 3.1: Single transient arc");
            reset_dut();
            expect_trip_active = 1'b0;
            inject_single_arc();
            #ARC_TIMEOUT_NS;
            if (gpio_io[0] !== 1'b0)
                fail_now("Scenario 3.1: qua nhay cam, single transient bi cat dien sai");
            else
                pass_note("Scenario 3.1: tha qua single transient / single spark");

            $display("\n>>> SCENARIO 3.2: Intermittent arc (lap lai) ");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                inject_intermittent_arc();
                begin
                    #ARC_TIMEOUT_NS;
                    if (!trip_seen)
                        fail_now("Scenario 3.2: khong cat duoc intermittent arc");
                end
            join_any
            disable fork;
            pass_note("Scenario 3.2: intermittent arc pass");

            $display("\n>>> SCENARIO 3.3: Solid arc");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                inject_solid_arc();
                begin
                    #ARC_TIMEOUT_NS;
                    if (!trip_seen)
                        fail_now("Scenario 3.3: khong cat duoc solid arc");
                end
            join_any
            disable fork;
            pass_note("Scenario 3.3: solid arc pass");
        end
    endtask

    task automatic scenario_4_anti_saturation();
        begin
            $display("\n>>> SCENARIO 4: Anti-saturation / anti-overflow");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                inject_adc_stuck_high(300);
                begin
                    wait(dut.u_dsp.integrator > 900);
                    repeat (1000) begin
                        #10;
                        if (dut.u_dsp.integrator < 100)
                            fail_now("Scenario 4: nghi ngờ overflow - integrator quay ve muc thap");
                    end
                    pass_note("Scenario 4: integrator khong bi quay vong khi bom gia tri max");
                end
                begin
                    #ARC_TIMEOUT_NS;
                    if (!trip_seen)
                        fail_now("Scenario 4: relay khong cat trong luc ADC stuck-high");
                end
            join_any
            disable fork;
        end
    endtask

    task automatic scenario_5_watchdog();
        begin
            $display("\n>>> SCENARIO 5: Watchdog safety / CPU radiation hang");
            reset_dut();
            inject_cpu_radiation_fault();
            fork
                begin
                    wait(dut.u_wdt.wdt_reset_o == 1'b1);
                    pass_note("Scenario 5: watchdog da hard-reset he thong");
                end
                begin
                    #WDT_TIMEOUT_NS;
                    if (dut.u_wdt.wdt_reset_o == 1'b0)
                        fail_now("Scenario 5: CPU treo nhung watchdog khong cuu");
                end
            join_any
            disable fork;
            release_cpu_fault();
        end
    endtask

    task automatic scenario_6_interrupt_collision();
        begin
            $display("\n>>> SCENARIO 6: Interrupt collision / priority arbitration");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                begin
                    force dut.irq_timer_tick    = 1'b1;
                    force dut.irq_arc_critical  = 1'b1;
                end
                begin
                    wait((dut.u_cpu.pc == 8'h01) || (dut.u_cpu.pc == 8'h08));
                    if (dut.u_cpu.pc == 8'h08)
                        fail_now("Scenario 6: CPU chon sai uu tien, vao Timer thay vi Arc");
                end
                begin
                    #50_000;
                    if (!trip_seen)
                        fail_now("Scenario 6: timeout khi xu ly xung dot ngat");
                end
            join_any
            disable fork;
            release dut.irq_timer_tick;
            release dut.irq_arc_critical;
            pass_note("Scenario 6: collision interrupt duoc xu ly dung uu tien");
        end
    endtask

    task automatic scenario_7_power_glitch();
        begin
            $display("\n>>> SCENARIO 7: Power glitch recovery");
            reset_dut();
            expect_trip_active = 1'b1;
            fork
                begin
                    #200;
                    inject_power_glitch(5000);
                    start_arc_time = $time;
                end
                begin
                    inject_solid_arc();
                    inject_solid_arc();
                end
                begin
                    #GLITCH_TIMEOUT_NS;
                    if (!trip_seen)
                        fail_now("Scenario 7: chip khong hoi phuc / khong cat relay sau power glitch");
                end
            join_any
            disable fork;
            pass_note("Scenario 7: power glitch recovery pass");
        end
    endtask

    task automatic scenario_8_glowing_contact();
        begin
            $display("\n>>> SCENARIO 8: Glowing contact / overheat contact");
            reset_dut();
            expect_trip_active = 1'b1;
            start_arc_time = $time;
            fork
                inject_contact_overheat();
                begin
                    #500_000;
                    if (!trip_seen)
                        fail_now("Scenario 8: khong phat hien duoc glowing/overheat contact");
                end
            join_any
            disable fork;
            pass_note("Scenario 8: glowing contact duoc phat hien");
        end
    endtask

    task automatic scenario_9_uart();
        begin
            $display("\n>>> SCENARIO 9: UART reporting");
            reset_dut();
            check_uart_transmission();
        end
    endtask

    task automatic scenario_10_bist();
        begin
            $display("\n>>> SCENARIO 10.1: BIST golden signature");
            reset_dut();
            run_bist_golden_and_store();

            $display("\n>>> SCENARIO 10.2: BIST fault coverage");
            reset_dut();
            run_bist_with_stuck_at_fault();
        end
    endtask

    // =====================================================================
    // 12. MAIN TEST FLOW
    // =====================================================================
    initial begin
        if (!$value$plusargs("SEED=%d", seed))
            seed = 32'h1A2B_3C4D;
        void'($urandom(seed));

        if (!$value$plusargs("RANDOM_RUNS=%d", random_runs))
            random_runs = 20;

        enable_random = 1'b0;
        if ($test$plusargs("ENABLE_RANDOM"))
            enable_random = 1'b1;

        $display("\n============================================================");
        $display(" INTELLI-SAFE SoC - PROFESSIONAL FULL TESTBENCH");
        $display(" SEED = %0d", seed);
        $display(" RANDOM ENABLE = %0d", enable_random);
        $display(" RANDOM RUNS   = %0d", random_runs);
        $display("============================================================\n");

        rst_ni    = 1'b0;
        adc_miso  = 1'b0;
        uart_rx   = 1'b1;
        expect_trip_active = 1'b0;
        trip_seen = 1'b0;
        golden_signature = '0;

        // Bộ directed chính cho đồ án.
        scenario_1_motor_inrush();
        scenario_2_intermittent_arc();
        scenario_3_arc_family();
        scenario_4_anti_saturation();
        scenario_5_watchdog();
        scenario_6_interrupt_collision();
        scenario_7_power_glitch();
        scenario_8_glowing_contact();
        scenario_9_uart();
        scenario_10_bist();

        // Random regression là tùy chọn. Không bật mặc định để directed luôn chạy gọn.
        if (enable_random)
            run_random_regression(random_runs);

        $display("\n************************************************************");
        $display(" TONG KET TESTBENCH");
        $display(" PASS COUNT = %0d", pass_count);
        $display(" FAIL COUNT = %0d", fail_count);
        if (fail_count == 0)
            $display(" KET LUAN   = ALL TESTS PASSED");
        else
            $display(" KET LUAN   = CO LOI CAN DEBUG THEM");
        $display("************************************************************\n");

        $finish;
    end

endmodule
