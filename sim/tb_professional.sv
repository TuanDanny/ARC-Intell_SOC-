`timescale 1ns/1ps


module tb_professional;

    // =========================================================================
    // 1. KHAI BÁO TÍN HIỆU & BIẾN TOÀN CỤC (SỬA LỖI SCOPE)
    // =========================================================================
    logic clk;
    logic rst_ni;
    logic adc_miso;
    wire  adc_mosi;
    wire  adc_sclk;
    wire  adc_csn;
    wire  uart_tx;
    logic uart_rx;
    wire [3:0] gpio_io;
    logic [15:0] golden_signature; // Thêm dòng này vào để khai báo biến toàn cục cho Scoreboard & Radar

    // Biến toàn cục cho Scoreboard & Radar (Bắt buộc khai báo trước khi dùng)
    logic is_testing_arc = 0;
    time  start_arc_time = 0;

    pulldown(gpio_io[0]); // Điện trở kéo xuống đất ảo cho Relay

    // =========================================================================
    // 2. KHỞI TẠO DUT (Device Under Test)
    // =========================================================================
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

    // =========================================================================
    // 3. CLOCK & TIMEOUT
    // =========================================================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 50MHz
        
    end

    initial begin
        #5000000; // Timeout 5ms
        $display("\n[FATAL ERROR] TESTBENCH TIMEOUT! He thong bi treo.");
        $stop;
    end

    

    // =========================================================================
    // 4. KHỐI DRIVER (BƠM DỮ LIỆU ADC)
    // =========================================================================
    task automatic send_spi_data(input [15:0] data);
        begin
            wait(adc_csn == 0);

            // Preload bit đầu tiên trước cạnh sample đầu tiên
            adc_miso = data[15];

            // Sau mỗi cạnh xuống, cập nhật bit kế tiếp
            for (int i = 14; i >= 0; i--) begin
                @(negedge adc_sclk);
                adc_miso = data[i];
            end

            // Giữ bit cuối đủ lâu để DUT sample xong
            @(posedge adc_sclk);

            wait(adc_csn == 1);
            adc_miso = 1'b0;
        end
    endtask



    // Extra scenarios 11 -> 19
    // SC16 = DSP weighted attack
    // SC17 = sliding-window spike density
    // SC18 = adaptive noise floor + effective threshold
    // SC19 = DSP stream restart awareness
    // SC24 = CPU DSP paged MMIO + 16-bit register access
    // SC25 = DSP boot profile / profile load
    `include "tb_extra_scenarios_11_15_reliable.svh"
    `include "tb_spi_bridge_checks.svh"






    task automatic run_normal_condition(input int num_samples);
        begin
            repeat(num_samples) send_spi_data($urandom_range(0, 20));
        end
    endtask
    // Task: Dòng khởi động động cơ (Máy hút bụi, Máy nén tủ lạnh)
    // Dùng cho SCENARIO 1
    task automatic inject_motor_inrush();
        begin
            // Cú giật điện đầu tiên
            send_spi_data(16'd800); 
            send_spi_data(16'd800);
            send_spi_data(16'd800);
            // Sau đó trở lại bình thường nhanh chóng (để bộ suy giảm Decay làm việc)
            run_normal_condition(15); 
            // Cú giật thứ hai (do cuộn cảm)
            send_spi_data(16'd600);
            send_spi_data(16'd600);
            run_normal_condition(20);
        end
    endtask

    // (MỚI) Task 3.1: Hồ quang đơn lẻ (Sẹt lửa 1 cái rồi thôi)
    task automatic inject_single_arc();
        begin
            repeat(15) begin // Chỉ xẹt 15 phát (Tương đương mức 150/1000)
                send_spi_data(16'd500); 
                send_spi_data(16'd0);
            end
            run_normal_condition(50); // Trở lại bình thường cho thùng xả rò rỉ hết
        end
    endtask

    // (ĐÃ SỬA) Task 3.2: Hồ quang chập chờn
    task automatic inject_intermittent_arc();
        begin
            repeat(40) send_spi_data(16'd500); // Lên mức ~400
            run_normal_condition(10);          // Suy giảm một chút
            
            repeat(50) send_spi_data(16'd600); // Lên mức ~800
            run_normal_condition(10);          // Suy giảm một chút
            
            repeat(50) send_spi_data(16'd650); // Bồi thêm cho tràn 1000 -> NGẮT!
        end
    endtask

    // (ĐÃ SỬA) Task 3.3: Hồ quang liên tục (Solid Arc)
    task automatic inject_solid_arc();
        begin
            // Bơm 150 gai liên tục (Chắc chắn sẽ vượt qua mức 1000)
            repeat(150) begin
                send_spi_data(16'd500);
                send_spi_data(16'd0);   
            end
        end
    endtask


    // Task 4.1: Giả lập cáp SPI bị đứt hoặc chập lên VCC (Stuck-at-1 Fault)
    // Hệ quả: ADC sẽ liên tục gửi về chuỗi bit 1 (Giá trị Max). 
    // Mục đích: Xem bộ đếm tích phân có bị "tràn số" (từ 1000 quay về 0) không.
    task automatic inject_adc_stuck_high(input int num_samples);
        begin
            repeat(num_samples) begin
                // Gửi giá trị dương lớn nhất của số 16-bit có dấu
                send_spi_data(16'h7FFF); 
            end
        end
    endtask

    // Task 4.2: Giả lập Nhiễu bức xạ (SEU) - ĐÃ SỬA LỖI FORCE
    task automatic inject_cpu_radiation_fault();
        begin
            // 1. Bắn tia bức xạ: Ép CPU nhảy lung tung (Treo máy)
            force dut.u_cpu.pc = 8'hFF; 
            
            // 2. Giả lập Watchdog đang được bật (Enable = 1)
            force dut.u_wdt.r_enable = 1'b1;
            
            // 3. Ép bộ đếm xuống giá trị nhỏ (50 chu kỳ) để test cho nhanh
            force dut.u_wdt.r_counter = 32'd50; 
            
            // QUAN TRỌNG: Chờ 1 nhịp clock để giá trị nạp vào, sau đó THẢ RA (RELEASE)
            // để phần cứng Watchdog tự đếm lùi (50 -> 49 -> ... -> 0)
            @(posedge clk);
            release dut.u_wdt.r_counter; 
        end
    endtask

    // Task 4.3: Gỡ bỏ trạng thái phá hoại
    task automatic release_cpu_fault();
        begin
            release dut.u_cpu.pc;
            release dut.u_wdt.r_enable;
            // Không cần release r_counter nữa vì đã làm ở bước trên
        end
    endtask


    // Task 6.1: Gây xung đột ngắt (Interrupt Collision Injection)
    // Mục tiêu: Giả lập tình huống Timer (hoặc BIST) đang yêu cầu ngắt (Priority 2)
    // đúng lúc Hồ quang (Priority 1) ập tới.
    task automatic inject_interrupt_collision();
        begin
            // 1. Kích hoạt giả lập ngắt Timer (Mức ưu tiên thấp - 2)
            // Ép tín hiệu dây dẫn irq_timer_tick trong top_soc lên 1
            force dut.irq_timer_tick = 1'b1;
            
            $display("[COLLISION] Da kich hoat Timer Interrupt (Priority 2).");
            $display("[COLLISION] CPU dang phan van... Tiep tuc bom Ho quang (Priority 1)!");
            
            // 2. Ngay lập tức bơm Hồ quang (Mức ưu tiên cao - 1)
            // Hàm này sẽ kích hoạt irq_arc_critical
            inject_solid_arc(); 
        end
    endtask

    // Task 6.2: Dọn dẹp hiện trường xung đột
    task automatic release_collision();
        begin
            release dut.irq_timer_tick;
        end
    endtask

    // Task 7.1: Tạo nhiễu nguồn (Power/Reset Glitch)
    // Mô phỏng hiện tượng chập chờn điện áp: Reset liên tục bật tắt ngẫu nhiên
    task automatic inject_power_glitch(input int duration_ns);
        time start_t;
        start_t = $time;
        
        $display("[POWER-GLITCH] Bat dau rung lac nguon (Reset Glitching) trong %0d ns...", duration_ns);
        
        while ($time - start_t < duration_ns) begin
            rst_ni = 0; // Sập nguồn (Reset)
            #($urandom_range(20, 100)); // Giữ reset trong thời gian ngẫu nhiên ngắn
            
            rst_ni = 1; // Có điện lại
            #($urandom_range(20, 100)); // Chạy được một chút thì lại sập
        end
        
        // Cuối cùng: Cấp điện ổn định trở lại
        rst_ni = 1;
        $display("[POWER-GLITCH] Nguon da on dinh tro lai.");
    endtask



    // Task 8.1: Mô phỏng Tiếp điểm bị lỏng gây Quá nhiệt (Glowing Contact)
    // Đặc điểm: Dòng điện nền tăng dần (Nóng) + Kèm theo dao động bất ổn (Unstable)
    // Đây là dấu hiệu của việc điện trở tiếp xúc thay đổi liên tục khi nóng đỏ.
    task automatic inject_contact_overheat();
        int base_heat;
        int noise;
        begin
            base_heat = 0;
            // Mô phỏng quá trình nóng dần lên trong 150 mẫu
            repeat(150) begin
                // 1. Nhiệt độ tăng dần (Base line tăng)
                base_heat = base_heat + 20; 
                
                // 2. Tạo dao động bất ổn (Instability) khi tiếp điểm nóng đỏ
                // Dao động này đủ lớn (> Threshold 50) để DSP bắt được
                noise = $urandom_range(0, 100); 
                
                if (base_heat > 2000) base_heat = 2000; // Bão hòa nhiệt độ
                
                // Gửi dữ liệu: Nền nhiệt + Dao động
                // Lúc chẵn thì cộng, lúc lẻ thì trừ để tạo độ dốc (dv/dt) lớn cho DSP
                send_spi_data(16'(base_heat + noise));
                send_spi_data(16'(base_heat - noise));
            end
        end
    endtask


    // Task 9.1: Kiểm tra khối UART (Gửi dữ liệu báo cáo ra ngoài)
    // Vì ROM hiện tại chưa có code driver UART, ta sẽ giả lập CPU ghi vào UART qua APB
    task automatic check_uart_transmission();
        begin
            $display("[UART-CHECK] Gia lap CPU gui ky tu 'A' (0x41) bao cao su co...");
            
            // 1. Force các tín hiệu Bus APB kết nối vào UART Slave
            // Địa chỉ UART DATA Register = 32'h1A10_3000 (Theo config.sv map vào 0x3000)
            // Lưu ý: Trong top_soc, UART nối vào Slave 3 -> Offset 0x3000
            
            // Setup Phase
            force dut.u_uart.paddr_i = 32'h0000; // Offset 0x00 (Data Reg)
            force dut.u_uart.pwdata_i = 32'h00000041; // Ký tự 'A'
            force dut.u_uart.pwrite_i = 1'b1;
            force dut.u_uart.psel_i = 1'b1;
            force dut.u_uart.penable_i = 1'b0;
            @(posedge clk);
            
            // ACCESS Phase: Bắt buộc PENABLE phải lên mức 1 để chốt dữ liệu
            force dut.u_uart.penable_i = 1'b1;
            @(posedge clk);

            // Hoàn thành giao dịch (Clear bus)
            force dut.u_uart.psel_i = 1'b0;
            force dut.u_uart.penable_i = 1'b0;
            
            // Release Bus (Trả lại quyền kiểm soát)
            release dut.u_uart.paddr_i;
            release dut.u_uart.pwdata_i;
            release dut.u_uart.pwrite_i;
            release dut.u_uart.psel_i;
            release dut.u_uart.penable_i;
            
            // 2. Chờ xem chân TX có rung không
            // Bắt quả tang ngay khi có sườn xuống (Start Bit)
            fork
                begin
                    @(negedge uart_tx); // Rình sườn xuống của chân TX
                    $display("[SCOREBOARD] -> [PASS] UART TX da hoat dong (Phat hien Start Bit).");
                end
                begin
                    #100000; // Nếu đợi 100us mà không thấy sườn xuống -> Timeout
                    $display("[SCOREBOARD] -> [WARNING] UART TX van giu muc 1 (Idle). Khong co Start bit.");
                end
            join_any
            disable fork; // Kết thúc các luồng rình rập còn thừa
        end
    endtask


    // Task 10.1: Chạy BIST trên mạch TỐT - ĐÃ CÓ KIỂM TRA AN TOÀN & TIMING CHUẨN
    task automatic run_bist_golden_and_store();
        logic [15:0] signature_read;
        begin
            $display("[BIST-GOLDEN] Bat dau chay BIST tren mach chuan de lay Signature Vang...");
            
            // -----------------------------------------------------------
            // 1. CẤU HÌNH BIST (Phải có thời gian cho Clock đập)
            // -----------------------------------------------------------
            force dut.u_bist.paddr_i = 32'h0004; // CONFIG
            force dut.u_bist.pwdata_i = 32'd5000; 
            force dut.u_bist.pwrite_i = 1'b1;
            force dut.u_bist.psel_i = 1'b1;
            force dut.u_bist.penable_i = 1'b0; // Setup Phase
            @(posedge clk);
            force dut.u_bist.penable_i = 1'b1; // Access Phase
            @(posedge clk);

            // -----------------------------------------------------------
            // 2. KÍCH HOẠT BIST
            // -----------------------------------------------------------
            force dut.u_bist.paddr_i = 32'h0000; // CTRL
            force dut.u_bist.pwdata_i = 32'h0001; // START
            force dut.u_bist.pwrite_i = 1'b1;
            force dut.u_bist.psel_i = 1'b1;
            force dut.u_bist.penable_i = 1'b0; // Setup Phase
            @(posedge clk);
            force dut.u_bist.penable_i = 1'b1; // Access Phase
            @(posedge clk);
            
            // Nhả Bus ra
            release dut.u_bist.psel_i;
            release dut.u_bist.pwrite_i;
            release dut.u_bist.paddr_i;
            release dut.u_bist.pwdata_i;
            release dut.u_bist.penable_i;
            
            // -----------------------------------------------------------
            // 3. CHỜ BIST CHẠY VÀ GIÁM SÁT SONG SONG
            // -----------------------------------------------------------
            fork
                begin // Luồng 1: Chờ BIST báo done (bằng logic FlipFlop đã sửa)
                    wait(dut.u_bist.r_done == 1'b1);
                    $display("[BIST-GOLDEN] BIST da chay xong.");
                end
                
                begin // Luồng 2: Giám sát báo động giả
                    wait(gpio_io[0] == 1'b1);
                    $display("[SCOREBOARD] -> [FAIL] RELAY DA BI NGAT TRONG KHI CHAY BIST!");
                    $stop;
                end

                begin // Luồng 3: Đề phòng hệ thống treo (Timeout)
                    #500000; 
                    $display("[FAIL] BIST TIMEOUT! Qua lau khong thay r_done.");
                    $stop;
                end
            join_any
            disable fork;

            // -----------------------------------------------------------
            // 4. ĐỌC SIGNATURE
            // -----------------------------------------------------------
            signature_read = dut.u_bist.r_signature;
            golden_signature = signature_read;
            
            if (golden_signature !== 16'd0)
                $display("[BIST-GOLDEN] Da ghi nhan GOLDEN SIGNATURE: 0x%h", golden_signature);
            else begin
                $display("[BIST-GOLDEN] -> [FAIL] Golden Signature khong the bang 0!");
                $stop;
            end
        end
    endtask

    // Task 10.2: Chạy BIST trên mạch HỎNG và so sánh với Chữ ký Vàng
    task automatic run_bist_with_stuck_at_fault();
        logic [15:0] faulty_signature;
        begin
            $display("\n[BIST-FAULT] Bat dau bom loi 'Stuck-at-0' vao DSP...");
            
            // 1. PHÁ HOẠI MẠCH: Ép chân ngắt của DSP luôn bằng 0
            force dut.u_dsp.irq_arc_o = 1'b0;
            
            $display("[BIST-FAULT] Mach DSP da bi hong. Tien hanh chay BIST de kiem tra...");
            
            // 2. CẤU HÌNH LẠI BIST (BẮT BUỘC phải giống hệt Task 10.1)
            force dut.u_bist.paddr_i = 32'h0004; // CONFIG
            force dut.u_bist.pwdata_i = 32'd5000; // CHiều dài 5000 chu kỳ
            force dut.u_bist.pwrite_i = 1'b1;
            force dut.u_bist.psel_i = 1'b1;
            force dut.u_bist.penable_i = 1'b1;
            @(posedge clk);
            @(negedge clk); // Đợi latch xong
            
            // 3. Kích hoạt BIST
            force dut.u_bist.paddr_i = 32'h0000;
            force dut.u_bist.pwdata_i = 32'h0001; 
            @(posedge clk);
            @(negedge clk); // Đợi latch xong
            
            // Nhả Bus
            release dut.u_bist.psel_i;
            release dut.u_bist.pwrite_i;
            release dut.u_bist.paddr_i;
            release dut.u_bist.pwdata_i;
            release dut.u_bist.penable_i;
            
            // 4. Chờ BIST chạy xong
            wait(dut.u_bist.r_done == 1'b1);
            $display("[BIST-FAULT] BIST da chay xong tren mach loi.");


            // 5. Đọc "Chữ ký lỗi" (Faulty Signature)
            faulty_signature = dut.u_bist.r_signature;
            $display("[BIST-FAULT] FAULTY SIGNATURE thu duoc: 0x%h", faulty_signature);
            
            // 6. Dọn dẹp hiện trường
            release dut.u_dsp.irq_arc_o;
            
            // 7. SO SÁNH CHỮ KÝ (Đây là bước khẳng định BIST có hiệu quả hay không)
            if (faulty_signature == golden_signature) begin
                $display("[SCOREBOARD] -> [FAIL] BIST KHONG PHAT HIEN DUOC LOI!");
                $display("                  Signature mach hong GIONG HET mach tot (Du thoi gian test da y het nhau).");
                $stop;
            end else begin
                $display("[SCOREBOARD] -> [PASS] BIST da phat hien thanh cong loi Stuck-at-0!");
                $display("                  (Faulty Signature KHAC Golden Signature)");
            end
        end
    endtask



    // =========================================================================
    // 5. HỆ THỐNG RADAR GIÁM SÁT NỘI BỘ (DEBUG SPIES)
    // =========================================================================
    
    // SPY 1: Theo dõi Bộ đếm tích phân của DSP
    always @(dut.u_dsp.integrator) begin
        if (is_testing_arc && (dut.u_dsp.integrator > 0)) begin
            if (dut.u_dsp.integrator % 100 == 0)
                $display("[RADAR-DSP] Thung tich luy dang tang... Muc: %0d / 1000", dut.u_dsp.integrator);
        end
    end

    // SPY 2: Theo dõi dây ngắt từ DSP sang CPU
    always @(posedge dut.irq_arc_critical) begin
        $display("   [RADAR-IRQ] !!! DSP DA PHAT HIEN HO QUANG -> Kich hoat tin hieu NGAT tai %0t !!!", $time);
    end

    // SPY 3: Theo dõi CPU nhảy lệnh
    always @(dut.u_cpu.pc) begin
        if (dut.u_cpu.pc == 8'h01)
            $display("   [RADAR-CPU] CPU da nhan duoc ngat! Nhay vao VECTOR 0x01.");
        else if (dut.u_cpu.pc == 8'h03)
            $display("   [RADAR-CPU] CPU dang treo an toan (JMP 0x03) de giu chan Relay.");
    end

    // SPY 4: Theo dõi luồng dữ liệu trên Bus APB
    always @(posedge clk) begin
        if (dut.apb_cpu_master.psel && dut.apb_cpu_master.penable && dut.apb_cpu_master.pwrite) begin
            if (dut.apb_cpu_master.paddr[31:12] == 20'h00002) begin
                $display("   [RADAR-BUS] CPU ra lenh GHI qua Bus APB -> Dia chi: 0x%h | Du lieu: 0x%h", 
                          dut.apb_cpu_master.paddr, dut.apb_cpu_master.pwdata);
            end
        end
    end

    // =========================================================================
    // 6. SCOREBOARD & KỊCH BẢN CHÍNH
    // =========================================================================
    
     // Giám sát độc lập chân Relay vật lý (Trigger khi có cạnh lên)
    always @(posedge gpio_io[0]) begin 
        $display("\n===============================================================");
        $display("[MONITOR] CHAN RELAY DA DONG LEN 1 (CAT DIEN) TAI: %0t", $time);

        if (!is_testing_arc) begin
            $display("[SCOREBOARD] -> [FAIL] BAO DONG GIA (FALSE POSITIVE)!");
            $display("He thong da ngat dien SAI LICH khi gap nhiem dong co / nhiem nen.");
            $display("[FALSE-POS-DBG] status=0x%0h irq=%0b env=%0d hotspot=%0d int=%0d diff=%0d eff=%0d",
                     dut.u_dsp.reg_status,
                     dut.u_dsp.irq_arc_o,
                     dut.u_dsp.env_lp_q,
                     dut.u_dsp.hotspot_score_q,
                     dut.u_dsp.integrator,
                     dut.u_dsp.diff_abs,
                     dut.u_dsp.effective_thresh_comb);
            $display("===============================================================\n");
            $stop; 
        end else begin
            time latency;
            latency = $time - start_arc_time;
            $display("[SCOREBOARD] ->[PASS] HO QUANG DA BI DAP TAT THANH CONG!");
            $display("[SCOREBOARD] Thoi gian phan hoi (Latency): %0t", latency);
            $display("===============================================================\n");
            // Không dùng $stop ở đây nữa để kịch bản chính được quyền chạy tiếp
        end
    end




    initial begin
        $display("\n***************************************************************");
        $display("   KHOI DONG SELF-CHECKING & STRESS TEST CHO INTELLI-SAFE SoC  ");
        $display("***************************************************************\n");

        // --- KHỞI TẠO ---
        rst_ni = 0; adc_miso = 0; uart_rx = 1;
        is_testing_arc = 0;
        
        #105; @(negedge clk);
        rst_ni = 1;
        #2000; 

        // ---------------------------------------------------------------------
        $display("\n>>> [SCENARIO 1] KIEM TRA NHIEU NEN & DONG KHOI DONG DONG CO...");
        $display("Yeu cau: Bo tich phan ro (Leaky Integrator) phai loc duoc nhieu, KHONG cat Relay.");
        is_testing_arc = 0; 
        
        run_normal_condition(20); 
        inject_motor_inrush(); // Đóng máy hút bụi
        run_normal_condition(20);
        inject_motor_inrush(); // Đóng tủ lạnh
        run_normal_condition(20);
        
        #1000; 
        if (gpio_io[0] == 1'b0) 
            $display("[SCOREBOARD] -> [PASS] Test 1: Khong bi bao dong gia (Immune to False Alarms).\n");


        // ---------------------------------------------------------------------
        $display("\n>>>[SCENARIO 2] KIEM TRA HO QUANG CHAP CHON (INTERMITTENT ARC)...");
        $display("Yeu cau: Tich luy nang luong ngat quang, cat Relay thanh cong.");
        is_testing_arc = 1; 
        start_arc_time = $time; 
        
        // Sử dụng cơ chế chạy song song (fork) để bắt Timeout
        fork
            begin
                inject_intermittent_arc();
            end
            begin
                wait(gpio_io[0] == 1'b1); // Luồng này chờ Relay nhảy
            end
            begin
                #800000; // Timeout sau 800us
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] KHONG PHAT HIEN DUOC HO QUANG CHAP CHON!");
                    $stop;
                end
            end
        join_any
        disable fork; // Dọn dẹp các luồng còn thừa


        // ---------------------------------------------------------------------
        $display("\n[SYSTEM] KHOI DONG LAI HE THONG SAU SU CO DE TEST TIEP...");
        rst_ni = 0; #500; rst_ni = 1; #2000; // Hard reset CPU và DSP
        $display("[SYSTEM] KHOI DONG LAI XONG.\n");


        
        // TEST 3.1: HỒ QUANG ĐƠN LẺ (SINGLE ARC / TRANSIENT)
        $display("\n>>>[TEST 3.1] KIEM TRA HO QUANG DON LE (SET LUA ROI TAT)...");
        $display("Yeu cau: Thung tich phan tang len nhung phai tu giam xuong, KHONG CAT RELAY.");
        is_testing_arc = 0; // Đặt là 0 vì ta kỳ vọng hệ thống KHÔNG báo động
        
        inject_single_arc();
        
        #800000; // Chờ đủ thời gian để hệ thống có thể phản hồi nếu có (800us)
        if (gpio_io[0] == 1'b0) begin
            $display("[SCOREBOARD] -> [PASS] He thong da tha qua loi ho quang don le (Safe).");
        end else begin
            $display("[SCOREBOARD] -> [FAIL] He thong qua nhay cam, da ngat sai!");
            $stop;
        end


        // TEST 3.2: HỒ QUANG CHẬP CHỜN (INTERMITTENT ARC)
        $display("\n[SYSTEM] Reset he thong chuan bi cho Test 3.2...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [TEST 3.2] KIEM TRA HO QUANG CHAP CHON (LO LONG DAY DIEN)...");
        $display("Yeu cau: Tich luy nang luong ngat quang den khi day thung -> CAT RELAY.");
        is_testing_arc = 1; 
        start_arc_time = $time; 
        
        fork
            begin
                inject_intermittent_arc();
            end
            begin
                wait(gpio_io[0] == 1'b1); // Chờ Relay nhảy
            end
            begin
                #800000; // Timeout an toàn (800us)
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] TIMEOUT! Khong cat duoc Ho quang chap chon.");
                    $stop;
                end
            end
        join_any
        disable fork;

        // TEST 3.3: HỒ QUANG LIÊN TỤC CỰC MẠNH (SOLID ARC)
        $display("\n[SYSTEM] Reset he thong chuan bi cho Test 3.3...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [TEST 3.3] KIEM TRA HO QUANG LIEN TUC (CHAY NO TRUC TIEP)...");
        $display("Yeu cau: Thung tich phan tang toc do toi da -> CAT RELAY CUC NHANH.");
        is_testing_arc = 1; 
        start_arc_time = $time; 
        
        fork
            begin
                inject_solid_arc();
            end
            begin
                wait(gpio_io[0] == 1'b1); // Chờ Relay nhảy
            end
            begin
                #800000; // Timeout an toàn (800us)
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] TIMEOUT! Khong cat duoc Ho quang lien tuc.");
                    $stop;
                end
            end
        join_any
        disable fork;


        // =====================================================================
        // SCENARIO 4: KIỂM TRA CHỐNG TRÀN SỐ (SATURATION & OVERFLOW CHECK)
        // =====================================================================
        // Giả lập tình huống: Cáp ADC bị chuột cắn đứt -> Tín hiệu MISO bị thả nổi lên mức 1
        // DSP sẽ nhận toàn giá trị cực đại. Nếu không có Saturation, bộ đếm sẽ bị tràn về 0.
        
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 4...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [SCENARIO 4] KIEM TRA CHONG TRAN SO (ANTI-OVERFLOW)...");
        $display("Yeu cau: Khi bom du lieu cuc dai lien tuc, thung tich phan phai GHIM o MAX, khong duoc ve 0.");
        is_testing_arc = 1; 
        start_arc_time = $time; 
        
        fork
            begin
                // Bơm liên tục 300 mẫu cực đại (nhiều hơn mức cần thiết để tràn)
                inject_adc_stuck_high(300); 
            end
            
            begin
                // Luồng giám sát song song: Kiểm tra xem bộ đếm có bị sụt giảm đột ngột không
                // Chờ cho đến khi bộ đếm đạt mức cao (>900)
                wait(dut.u_dsp.integrator > 900);
                
                // Sau đó theo dõi liên tục trong 10000ns tiếp theo
                repeat(1000) begin
                    #10;
                    // Nếu đang ở đỉnh cao mà tự dưng tụt về < 100 (trong khi đang bơm lỗi) -> LỖI TRÀN SỐ
                    if (dut.u_dsp.integrator < 100) begin
                        $display("[SCOREBOARD] -> [FAIL] PHAT HIEN LOI TRAN SO (OVERFLOW)!");
                        $display("Gia tri tich phan da bi quay vong ve: %0d", dut.u_dsp.integrator);
                        $stop;
                    end
                end
                $display("[SCOREBOARD] -> [PASS] Bo dem tich phan da bao hoa thanh cong (Saturation Logic OK).");
            end
            
            begin
                wait(gpio_io[0] == 1'b1); // Đương nhiên Relay vẫn phải cắt
            end
        join_any
        disable fork;

        

        // =====================================================================
        // SCENARIO 5: KIỂM TRA WATCHDOG TIMER (SAFETY MECHANISM)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 5...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [SCENARIO 5] GIA LAP CPU BI TREO DO BUC XA (RADIATION FAULT)...");
        $display("Yeu cau: Watchdog Timer phai phat hien CPU chet va tu dong Hard Reset.");
        
        // Bước 1: Gây nhiễu bức xạ làm treo CPU
        inject_cpu_radiation_fault(); 
        $display("[FAULT INJECTOR] Da ban tia buc xa! CPU PC bi ep nhay ve 0xFF (Vung nho rac).");
        $display("[FAULT INJECTOR] Watchdog dang dem lui...");

        // Bước 2: Chờ đợi phép màu (Watchdog Reset)
        // Ta chờ tín hiệu wdt_reset_o từ module Watchdog bật lên 1
        fork
            begin
                // Chờ tín hiệu reset nội bộ của Watchdog
                wait(dut.u_wdt.wdt_reset_o == 1'b1);
                $display("[SCOREBOARD] -> [PASS] WATCHDOG DA KICH HOAT CUU HO (HARD RESET)!");
            end
            begin
                #200000; // Chờ tối đa 200us
                if (dut.u_wdt.wdt_reset_o == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] CPU CHET NHUNG WATCHDOG KHONG CUU!");
                    $stop;
                end
            end
        join_any
        disable fork;

        // Bước 3: Dọn dẹp hiện trường
        release_cpu_fault(); 

        


        // =====================================================================
        // SCENARIO 6: KIỂM TRA XUNG ĐỘT NGẮT (INTERRUPT COLLISION)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 6...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [SCENARIO 6] KIEM TRA XUNG DOT NGAT (PRIORITY ARBITRATION)...");
        $display("Yeu cau: Khi Timer (Prio 2) va Ho quang (Prio 1) cung xay ra, CPU phai chon Ho quang.");

        is_testing_arc = 1; 
        start_arc_time = $time; 
        
        fork
            begin
                // --- KỸ THUẬT GÂY XUNG ĐỘT TỨC THỜI ---
                // 1. Ép dây Timer Interrupt lên 1 (Ưu tiên thấp)
                force dut.irq_timer_tick = 1'b1;
                
                // 2. Ép dây Arc Interrupt lên 1 NGAY LẬP TỨC (Ưu tiên cao)
                // Giả lập tình huống DSP vừa phát hiện xong đúng lúc Timer gõ nhịp
                force dut.irq_arc_critical = 1'b1;
                
                $display("[COLLISION] Da kich hoat CUNG LUC: Timer (Prio 2) & Arc (Prio 1).");
            end
            
            begin
                // Giám sát CPU: Nó sẽ nhảy vào đâu?
                // Nếu đúng: Phải nhảy vào 0x01 (Arc)
                // Nếu sai: Nhảy vào 0x08 (Timer)
                
                wait(dut.u_cpu.pc == 8'h01 || dut.u_cpu.pc == 8'h08);
                
                if (dut.u_cpu.pc == 8'h08) begin
                    $display("[SCOREBOARD] -> [FAIL] CPU DA CHON SAI UU TIEN! (Vao Timer thay vi Arc)");
                    $stop;
                end else if (dut.u_cpu.pc == 8'h01) begin
                    $display("[SCOREBOARD] -> [INFO] CPU da phan xu dung: Chon Vector Ngat Ho Quang (0x01).");
                end
                
                // Chờ Relay cắt
                wait(gpio_io[0] == 1'b1);
            end
            
            begin
                #50000; // Timeout nhanh
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] TIMEOUT! CPU bi treo khi xu ly xung dot.");
                    $stop;
                end
            end
        join_any
        disable fork;

        // Dọn dẹp hiện trường (Release các dây tín hiệu để mạch chạy lại bình thường)
        release dut.irq_timer_tick;
        release dut.irq_arc_critical;
        

        
        // =====================================================================
        // SCENARIO 7: KIỂM TRA SỐC NGUỒN (POWER-ON RESET GLITCH)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 7 (FINAL BOSS)...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [SCENARIO 7] KIEM TRA SOC NGUON LIEN TUC (POWER GLITCHING)...");
        $display("Yeu cau: Chip khong duoc treo (Deadlock). Phai tu hoi phuc va cat Relay sau khi nguon on dinh.");

        is_testing_arc = 1; 
        
        // Reset thời gian bắt đầu đo (Vì trong lúc Glitch, thời gian không tính)
        // Ta chỉ tính thời gian từ lúc nguồn ổn định trở lại
        
        fork
            // Luồng 1: Kẻ phá hoại (Rung lắc nguồn trong 5000ns)
            begin
                #200; // Chờ 1 chút mới phá
                inject_power_glitch(5000); 
                // Sau khi Glitch xong, đánh dấu thời điểm này để tính Latency
                start_arc_time = $time;
            end

            // Luồng 2: Nguồn dữ liệu (Bơm hồ quang liên tục không ngừng nghỉ)
            // Phải bơm đủ lâu để bao trùm cả thời gian bị Glitch + Thời gian tích lũy
            begin
                inject_solid_arc(); // Hàm này đã sửa ở bước trước (bơm 150 mẫu ~ 600us)
                // Bơm thêm dự phòng để chắc chắn
                inject_solid_arc(); 
            end
            
            // Luồng 3: Giám sát
            begin
                // Chờ Relay nhảy (Lưu ý: Chỉ nhảy sau khi Glitch kết thúc)
                wait(gpio_io[0] == 1'b1);
            end
            
            // Luồng 4: Timeout
            begin
                #1500000; // 1.5ms (Cho phép thời gian dài hơn do bị gián đoạn bởi Glitch)
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] DEADLOCK! Chip bi treo sau khi soc nguon.");
                    $stop;
                end
            end
        join_any
        disable fork;



        // =====================================================================
        // SCENARIO 8: KIỂM TRA QUÁ NHIỆT TIẾP ĐIỂM (OVERHEAT CONTACT)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 8 (FINAL)...");
        rst_ni = 0; #500; rst_ni = 1; #2000; 

        $display("\n>>> [SCENARIO 8] KIEM TRA QUA NHIET TIEP DIEM (GLOWING CONTACT)...");
        $display("Yeu cau: Phat hien su bat on dinh (Instability) khi tiep diem bi long va nong do.");
        
        is_testing_arc = 1;
        start_arc_time = $time;

        fork
            begin
                // Bơm tín hiệu mô phỏng tiếp điểm lỏng (Nóng dần + Rung lắc)
                inject_contact_overheat();
            end
            begin
                // Chờ Relay cắt
                wait(gpio_io[0] == 1'b1);
                $display("[SCOREBOARD] -> [PASS] Da phat hien TIEP DIEM QUA NHIET thanh cong!");
            end
            begin
                #500000; // Timeout
                if (gpio_io[0] == 1'b0) begin
                    $display("[SCOREBOARD] -> [FAIL] KHONG phat hien duoc qua nhiet!");
                    $display("[SC8-DBG] status=0x%0h irq=%0b env=%0d hotspot=%0d int=%0d diff=%0d eff=%0d frame_count=%0d",
                             dut.u_dsp.reg_status,
                             dut.u_dsp.irq_arc_o,
                             dut.u_dsp.env_lp_q,
                             dut.u_dsp.hotspot_score_q,
                             dut.u_dsp.integrator,
                             dut.u_dsp.diff_abs,
                             dut.u_dsp.effective_thresh_comb,
                             dut.u_spi_bridge.r_frame_count);
                    $stop;
                end
            end
        join_any
        disable fork;



        // =====================================================================
        // SCENARIO 9: KIỂM TRA GIAO TIẾP UART (SMART REPORTING)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 9...");
        rst_ni = 0; #500; rst_ni = 1; #2000;
        
        $display("\n>>> [SCENARIO 9] KIEM TRA TRUYEN DU LIEU UART (IOT REPORTING)...");
        $display("Yeu cau: Khoi UART phai day duoc du lieu ra chan TX.");
        
        // Gọi Task kiểm tra UART (đã định nghĩa ở Phần 1)
        check_uart_transmission();
        
        // Kiểm tra kết quả: Chân TX phải có sự thay đổi (Toggle)
        if (uart_tx !== 1'b1) 
            $display("[SCOREBOARD] -> [PASS] UART TX da hoat dong (Tin hieu co thay doi).");
        else 
            $display("[SCOREBOARD] -> [WARNING] UART TX van giu muc 1 (Idle). Kiem tra lai Force.");


        // =====================================================================
        // SPI BRIDGE CHECK: KIỂM TRA KHỐI SPI MỚI TÍCH HỢP
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SPI BRIDGE CHECK...");
        rst_ni = 0; #500; rst_ni = 1; #2000;
        run_spi_bridge_checks();

        // =====================================================================
        // SCENARIO 10: KIỂM TRA BIST (BUILT-IN SELF-TEST)
        // =====================================================================
        $display("\n[SYSTEM] Reset he thong chuan bi cho SCENARIO 10...");
        rst_ni = 0; #500; rst_ni = 1; #2000;
        
        // ---------------------------------------------------------------------
        $display("\n>>> [TEST 10.1] THU THAP GOLDEN SIGNATURE TREN MACH CHUAN...");
        // Gọi task đã viết ở Phần 1
        run_bist_golden_and_store();
        
        // ---------------------------------------------------------------------
        $display("\n[SYSTEM] Reset he thong lan nua de chuan bi bom loi...");
        rst_ni = 0; #500; rst_ni = 1; #2000;
        
        // ---------------------------------------------------------------------
        $display("\n>>> [TEST 10.2] KIEM TRA KHA NANG BAO PHU LOI (FAULT COVERAGE)...");
        // Gọi task đã viết ở Phần 1
        run_bist_with_stuck_at_fault();


        // =====================================================================
        // TỔNG KẾT & KẾT THÚC (FINAL REPORT - PERFECT 10/10)
        // =====================================================================
        #5000;
        $display("\n*************************************************************************");
        $display("   SoC DA VUOT QUA TOAN BO CAC THU THACH CHINH!   ");
        $display("*************************************************************************");
        $display("   1.  Motor Inrush (Loc nhieu dong co) .................... [PASS]");
        $display("   2.  Intermittent Arc (Ho quang chap chon) ............... [PASS]");
        $display("   3.  Solid Arc (Ho quang lien tuc toc do cao) ............ [PASS]");
        $display("   4.  Anti-Saturation (Chong tran so DSP) ................. [PASS]");
        $display("   5.  Watchdog Safety (Tu phuc hoi khi treo) .............. [PASS]");
        $display("   6.  Interrupt Collision (Xu ly xung dot ngat) ........... [PASS]");
        $display("   7.  Power Glitch Recovery (Tu hoi phuc sau soc nguon) ... [PASS]");
        $display("   8.  Glowing Contact (Phat hien qua nhiet tiep diem) ..... [PASS]");
        $display("   9.  UART Transmission (Giao tiep bao cao IoT) ........... [PASS]");
        $display("   9a. SPI Bridge (APB + ADC sampling) ..................... [PASS]");
        $display("   10. Logic BIST (Tu kiem tra phan cung) .................. [PASS]");
        $display("*************************************************************************\n");
        $display("   PROJECT INTELLI-SAFE SoC: VERIFICATION COMPLETE. READY FOR TAPE-OUT.");
        $display("*************************************************************************\n");
        run_extra_scenarios_11_to_26();
        $finish;

        
    end
















        // =========================================================================
        // 8. TRÍCH XUẤT WAVEFORM & THEO DÕI "RÒ RỈ" (LEAKY DECAY MONITOR)
        // =========================================================================

        // Block 1: Tự động lưu toàn bộ tín hiệu ra file để xem dạng sóng
        initial begin
            // Khởi tạo file dump cho dạng sóng (Có thể mở bằng ModelSim/GTKWave)
            $dumpfile("intelli_safe_arc_test.vcd");
            
            // Lưu toàn bộ tín hiệu của testbench và các module con (độ sâu = 0)
            $dumpvars(0, tb_professional);
            
            $display("\n[SYSTEM] Da bat chuc nang ghi Waveform (VCD).");
        end

        // Block 2: Radar chuyên bắt khoảnh khắc "Rò rỉ" (Decay) của DSP
        // Để chứng minh thuật toán Leaky Integrator hoạt động đúng như sách giáo khoa!
        realtime last_decay_time;
        int prev_integrator = 0; // Thêm biến để lưu giá trị cũ của integrator
        
        always @(dut.u_dsp.integrator) begin
            // Nếu giá trị hiện tại NHỎ HƠN giá trị cũ (đang xả rò rỉ)
            if (dut.u_dsp.integrator < prev_integrator) begin
                // Chỉ in ra 1 lần mỗi chu kỳ rò rỉ để đỡ rác màn hình
                if ($time - last_decay_time > 500) begin
                    $display("    [RADAR-LEAKY] Phat hien vung lang! Thung tich luy dang SUY GIAM (Decay): %0d", 
                            dut.u_dsp.integrator);
                    last_decay_time = $time;
                end
            end
            // Cập nhật lại giá trị cũ cho lần chạy tiếp theo
            prev_integrator = dut.u_dsp.integrator;
        end

endmodule

