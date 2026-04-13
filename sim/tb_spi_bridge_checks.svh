// ============================================================================
// tb_spi_bridge_checks.svh
//
// Muc dich:
//   - Chua cac helper/task de kiem tra rieng khoi SPI bridge moi.
//   - File nay duoc include BEN TRONG module tb_professional.
//   - Khong compile rieng bang vlog.
// ============================================================================

logic [11:0] tb_spi_force_addr;
logic [31:0] tb_spi_force_data;

task automatic spi_bridge_apb_write(input [11:0] addr, input [31:0] data);
    begin
        tb_spi_force_addr = addr;
        tb_spi_force_data = data;

        force dut.u_spi_bridge.paddr_i   = tb_spi_force_addr;
        force dut.u_spi_bridge.pwdata_i  = tb_spi_force_data;
        force dut.u_spi_bridge.pwrite_i  = 1'b1;
        force dut.u_spi_bridge.psel_i    = 1'b1;
        force dut.u_spi_bridge.penable_i = 1'b0;
        @(posedge clk);
        force dut.u_spi_bridge.penable_i = 1'b1;
        @(posedge clk);
        force dut.u_spi_bridge.psel_i    = 1'b0;
        force dut.u_spi_bridge.penable_i = 1'b0;

        release dut.u_spi_bridge.paddr_i;
        release dut.u_spi_bridge.pwdata_i;
        release dut.u_spi_bridge.pwrite_i;
        release dut.u_spi_bridge.psel_i;
        release dut.u_spi_bridge.penable_i;
    end
endtask

task automatic spi_bridge_apb_read(input [11:0] addr, output [31:0] data);
    begin
        tb_spi_force_addr = addr;

        force dut.u_spi_bridge.paddr_i   = tb_spi_force_addr;
        force dut.u_spi_bridge.pwrite_i  = 1'b0;
        force dut.u_spi_bridge.psel_i    = 1'b1;
        force dut.u_spi_bridge.penable_i = 1'b0;
        @(posedge clk);
        force dut.u_spi_bridge.penable_i = 1'b1;
        @(posedge clk);

        data = dut.u_spi_bridge.prdata_o;

        force dut.u_spi_bridge.psel_i    = 1'b0;
        force dut.u_spi_bridge.penable_i = 1'b0;
        release dut.u_spi_bridge.paddr_i;
        release dut.u_spi_bridge.pwrite_i;
        release dut.u_spi_bridge.psel_i;
        release dut.u_spi_bridge.penable_i;
    end
endtask

task automatic spi_bridge_wait_for_idle(input time timeout_ns = 200000);
    time start_t;
    begin
        start_t = $time;
        while ((adc_csn !== 1'b1) ||
               (dut.u_spi_bridge.frontend_busy !== 1'b0) ||
               (dut.u_spi_bridge.frontend_frame_active !== 1'b0)) begin
            @(posedge clk);
            if (($time - start_t) > timeout_ns) begin
                $display("[SPI-CHECK] -> [FAIL] Timeout khi cho SPI bridge ve idle!");
                $stop;
            end
        end
    end
endtask

task automatic spi_bridge_wait_for_sample_valid(input time timeout_ns = 200000);
    time start_t;
    begin
        start_t = $time;
        while (dut.u_spi_bridge.r_sample_valid_sticky !== 1'b1) begin
            @(posedge clk);
            if (($time - start_t) > timeout_ns) begin
                $display("[SPI-CHECK] -> [FAIL] Timeout khi cho sample_valid sticky len!");
                $stop;
            end
        end
    end
endtask

task automatic spi_bridge_disable_and_clear();
    begin
        spi_bridge_apb_write(12'h000, 32'h0000_0000); // disable
        spi_bridge_wait_for_idle();
        spi_bridge_apb_write(12'h000, 32'h0000_0008); // clear sticky/count while keep disable
        @(posedge clk);
    end
endtask

task automatic spi_bridge_send_frame(input [15:0] data);
    begin
        wait (adc_csn == 1'b0);

        // Dat san bit MSB truoc sample edge dau tien.
        adc_miso = data[15];

        // Moi lan DUT tao canh xuong SCLK, ta dua ra bit ke tiep.
        for (int i = 14; i >= 0; i--) begin
            @(negedge adc_sclk or posedge adc_csn);
            if (adc_csn == 1'b1) begin
                $display("[SPI-CHECK] -> [FAIL] Frame SPI ket thuc som khi dang dua bit!");
                $stop;
            end
            adc_miso = data[i];
        end

        wait (adc_csn == 1'b1);
        adc_miso = 1'b0;
    end
endtask

task automatic spi_bridge_run_one_shot(input [15:0] sample_word);
    bit transfer_done;
    begin
        transfer_done = 1'b0;

        spi_bridge_apb_write(12'h000, 32'h0000_0001); // enable=1, continuous=0
        @(posedge clk);

        fork
            begin
                fork
                    begin
                        spi_bridge_send_frame(sample_word);
                    end
                    begin
                        spi_bridge_apb_write(12'h000, 32'h0000_0005); // start pulse
                    end
                join
                transfer_done = 1'b1;
            end
            begin
                #200000;
                if (!transfer_done) begin
                    $display("[SPI-CHECK] -> [FAIL] Timeout trong luc chay one-shot SPI!");
                    $display("[SPI-CHECK]    DBG: enable=%0b continuous=%0b start_cmd=%0b busy=%0b frame_active=%0b csn=%0b sclk=%0b state=%0d frame_count=%0d",
                             dut.u_spi_bridge.r_enable,
                             dut.u_spi_bridge.r_continuous,
                             dut.u_spi_bridge.s_start_cmd,
                             dut.u_spi_bridge.frontend_busy,
                             dut.u_spi_bridge.frontend_frame_active,
                             adc_csn,
                             adc_sclk,
                             dut.u_spi_bridge.u_spi_adc_rx.state_q,
                             dut.u_spi_bridge.r_frame_count);
                    $stop;
                end
            end
        join_any
        disable fork;

        spi_bridge_wait_for_sample_valid();
        spi_bridge_wait_for_idle();
    end
endtask

task automatic run_spi_bridge_checks();
    logic [31:0] rd_data;
    logic [31:0] count_before_disable;
    logic [31:0] count_after_disable;
    begin
        $display("\n>>> [SPI-CHECK] KIEM TRA APB SPI BRIDGE & LUONG LAY MAU ADC...");

        // -----------------------------------------------------------
        // 1. Dat bridge ve trang thai sach, sau do chay one-shot co kiem soat.
        // -----------------------------------------------------------
        spi_bridge_disable_and_clear();

        spi_bridge_apb_read(12'h010, rd_data); // COUNT
        if (rd_data !== 32'h0000_0000) begin
            $display("[SPI-CHECK] -> [FAIL] COUNT khong duoc clear sach truoc khi test! Gia tri = 0x%h", rd_data);
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] Bridge duoc dua ve trang thai sach truoc khi do.");
        end

        spi_bridge_run_one_shot(16'h1234);

        spi_bridge_apb_read(12'h004, rd_data); // STATUS
        if (rd_data[4] !== 1'b1) begin
            $display("[SPI-CHECK] -> [FAIL] STATUS.sample_valid sticky khong len sau one-shot!");
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] STATUS.sample_valid sticky len dung sau one-shot.");
        end

        spi_bridge_apb_read(12'h00C, rd_data); // SAMPLE
        if (rd_data[15:0] !== 16'h1234) begin
            $display("[SPI-CHECK] -> [FAIL] SAMPLE register sai. Expected 0x1234, got 0x%h", rd_data[15:0]);
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] SAMPLE register latch dung gia tri ADC (0x1234).");
        end

        spi_bridge_apb_read(12'h004, rd_data); // STATUS lai sau khi doc sample
        if (rd_data[4] !== 1'b0) begin
            $display("[SPI-CHECK] -> [FAIL] Doc SAMPLE khong clear sample_valid sticky!");
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] Doc SAMPLE clear sample_valid sticky dung nhu thiet ke.");
        end

        spi_bridge_apb_read(12'h010, rd_data); // COUNT
        if ((rd_data[15:0] !== 16'd1) || (rd_data[31:16] !== 16'd0)) begin
            $display("[SPI-CHECK] -> [FAIL] COUNT sai sau one-shot. frame_count=%0d overwrite_count=%0d",
                     rd_data[15:0], rd_data[31:16]);
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] COUNT dung sau one-shot (1 frame, 0 overwrite).");
        end

        // -----------------------------------------------------------
        // 2. Tat bridge va dam bao no khong tu phat frame moi nua.
        // -----------------------------------------------------------
        spi_bridge_apb_read(12'h010, count_before_disable);
        spi_bridge_apb_write(12'h000, 32'h0000_0000); // disable
        spi_bridge_wait_for_idle();
        #3000;

        spi_bridge_apb_read(12'h004, rd_data); // STATUS
        spi_bridge_apb_read(12'h010, count_after_disable);

        if ((adc_csn !== 1'b1) || (rd_data[2] !== 1'b0) || (rd_data[3] !== 1'b0)) begin
            $display("[SPI-CHECK] -> [FAIL] Disable SPI bridge nhung giao dien van khong ve idle!");
            $stop;
        end else if (count_after_disable[15:0] !== count_before_disable[15:0]) begin
            $display("[SPI-CHECK] -> [FAIL] Disable SPI bridge nhung frame counter van tiep tuc tang!");
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] Disable SPI bridge dung: CS idle, busy=0, frame count dung yen.");
        end

        // -----------------------------------------------------------
        // 3. Bat continuous mode va kiem tra dem frame tang that su.
        // -----------------------------------------------------------
        spi_bridge_disable_and_clear();

        fork
            begin
                spi_bridge_send_frame(16'hBEEF);
                spi_bridge_send_frame(16'hCAFE);
            end
            begin
                spi_bridge_apb_write(12'h000, 32'h0000_0003); // enable=1, continuous=1
                wait (dut.u_spi_bridge.r_frame_count >= 16'd2);
                spi_bridge_apb_write(12'h000, 32'h0000_0000); // stop ngay sau khi da co it nhat 2 frame
            end
        join

        spi_bridge_wait_for_idle();

        spi_bridge_apb_read(12'h010, rd_data); // COUNT
        if (rd_data[15:0] < 16'd2) begin
            $display("[SPI-CHECK] -> [FAIL] Frame counter khong tang dung sau cac lan lay mau!");
            $stop;
        end else begin
            $display("[SPI-CHECK] -> [PASS] Continuous mode hoat dong, frame counter tang (count=%0d).", rd_data[15:0]);
        end

        // Bat lai continuous mode de nhung scenario sau khong bi anh huong.
        spi_bridge_apb_write(12'h000, 32'h0000_0003); // enable=1, continuous=1
    end
endtask
