`timescale 1ns/1ps

module tb_dsp_upgrades;

    logic clk;
    logic rst_ni;
    logic adc_miso;
    wire  adc_mosi;
    wire  adc_sclk;
    wire  adc_csn;
    wire  uart_tx;
    logic uart_rx;
    wire [3:0] gpio_io;
    logic [31:0] tbx_dsp_force_addr;
    logic [31:0] tbx_dsp_force_data;
    logic [15:0] tbx_dsp_force_sample_word;

    integer pass_count = 0;
    integer fail_count = 0;

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

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        adc_miso = 1'b0;
        uart_rx  = 1'b1;
    end

    task automatic dsp_force_apb_write(
      input [31:0] addr,
      input [31:0] data
    );
      begin
        tbx_dsp_force_addr = addr;
        tbx_dsp_force_data = data;
        force dut.apb_dsp_if.paddr   = tbx_dsp_force_addr;
        force dut.apb_dsp_if.pwdata  = tbx_dsp_force_data;
        force dut.apb_dsp_if.pwrite  = 1'b1;
        force dut.apb_dsp_if.psel    = 1'b1;
        force dut.apb_dsp_if.penable = 1'b0;
        @(posedge clk);

        force dut.apb_dsp_if.penable = 1'b1;
        @(posedge clk);

        release dut.apb_dsp_if.paddr;
        release dut.apb_dsp_if.pwdata;
        release dut.apb_dsp_if.pwrite;
        release dut.apb_dsp_if.psel;
        release dut.apb_dsp_if.penable;

        @(posedge clk);
      end
    endtask

    task automatic dsp_force_apb_read(
      input  [31:0] addr,
      output [31:0] rd_data
    );
      begin
        tbx_dsp_force_addr = addr;
        tbx_dsp_force_data = 32'h0;
        force dut.apb_dsp_if.paddr   = tbx_dsp_force_addr;
        force dut.apb_dsp_if.pwdata  = tbx_dsp_force_data;
        force dut.apb_dsp_if.pwrite  = 1'b0;
        force dut.apb_dsp_if.psel    = 1'b1;
        force dut.apb_dsp_if.penable = 1'b0;
        @(posedge clk);

        force dut.apb_dsp_if.penable = 1'b1;
        @(posedge clk);
        #1;
        rd_data = dut.apb_dsp_if.prdata;

        release dut.apb_dsp_if.paddr;
        release dut.apb_dsp_if.pwdata;
        release dut.apb_dsp_if.pwrite;
        release dut.apb_dsp_if.psel;
        release dut.apb_dsp_if.penable;

        @(posedge clk);
      end
    endtask

    task automatic dsp_force_sample(input [15:0] sample_word);
      begin
        tbx_dsp_force_sample_word = sample_word;
        force dut.dsp_data_in  = tbx_dsp_force_sample_word;
        force dut.dsp_valid_in = 1'b1;
        @(posedge clk);
        force dut.dsp_valid_in = 1'b0;
        @(posedge clk);
      end
    endtask

    task automatic reset_dsp_focus();
      begin
        rst_ni = 1'b0;
        force dut.dsp_data_in        = 16'd0;
        force dut.dsp_valid_in       = 1'b0;
        force dut.spi_stream_restart = 1'b0;
        force dut.spi_overrun        = 1'b0;
        #500;
        rst_ni = 1'b1;
        #3000;
      end
    endtask

    task automatic reset_dsp_focus_safe();
      begin
        reset_dsp_focus();
        dsp_force_apb_write(32'h0000_10A4, 32'h0000_0000);
      end
    endtask

    task automatic release_dsp_focus_forces();
      begin
        release dut.dsp_data_in;
        release dut.dsp_valid_in;
        release dut.spi_stream_restart;
        release dut.spi_overrun;
      end
    endtask

    task automatic scenario16_weighted_attack();
      reg [31:0] rd_status;
      reg [31:0] rd_diff;
      reg [31:0] rd_int;
      reg [31:0] rd_peak_diff;
      reg [31:0] rd_peak_int;
      reg [31:0] rd_event_cnt;
      reg [31:0] rd_attack;
      begin
        $display("\n[DSP-UPG] SC16 weighted attack");
        reset_dsp_focus_safe();

        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);

        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_status[4:0] !== 5'b0_0000) begin
          $display("[SC16][FAIL] STATUS sau reset = 0x%08h", rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd100);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_status[4] !== 1'b1) begin
          $display("[SC16][FAIL] sample dau: diff=%0d int=%0d status=0x%08h", rd_diff[15:0], rd_int[15:0], rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd140);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_101C, rd_peak_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        if (rd_diff[15:0] !== 16'd40 || rd_peak_diff[15:0] !== 16'd40 || rd_int[15:0] !== 16'd0 || rd_attack[15:0] !== 16'd0) begin
          $display("[SC16][FAIL] sample hai: diff=%0d peak=%0d int=%0d attack=%0d", rd_diff[15:0], rd_peak_diff[15:0], rd_int[15:0], rd_attack[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd220);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1020, rd_peak_int);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        if (rd_diff[15:0] !== 16'd80 || rd_int[15:0] !== 16'd11 || rd_peak_int[15:0] !== 16'd11 || rd_attack[15:0] !== 16'd11) begin
          $display("[SC16][FAIL] sample ba: diff=%0d int=%0d peak_int=%0d attack=%0d", rd_diff[15:0], rd_int[15:0], rd_peak_int[15:0], rd_attack[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_apb_write(32'h0000_1008, 32'h0000_0014);
        dsp_force_sample(16'd0);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1024, rd_event_cnt);
        dsp_force_apb_read(32'h0000_1020, rd_peak_int);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        if ((rd_status[3] !== 1'b1) || (rd_status[2] !== 1'b1) || (rd_status[1:0] !== 2'b11) ||
            (rd_event_cnt[15:0] !== 16'd1) || (rd_peak_int[15:0] !== 16'd20) || (rd_attack[15:0] !== 16'd20)) begin
          $display("[SC16][FAIL] fire: status=0x%08h event=%0d peak_int=%0d attack=%0d", rd_status, rd_event_cnt[15:0], rd_peak_int[15:0], rd_attack[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC16][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario17_spike_window();
      reg [31:0] rd_status;
      reg [31:0] rd_int;
      reg [31:0] rd_event_cnt;
      reg [31:0] rd_spike_sum;
      reg [31:0] rd_peak_spike_sum;
      reg [31:0] rd_peak_diff;
      begin
        $display("\n[DSP-UPG] SC17 spike window");
        reset_dsp_focus_safe();

        dsp_force_apb_write(32'h0000_1004, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_03E8);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0000);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0000);
        dsp_force_apb_write(32'h0000_104C, 32'h0000_001E);

        dsp_force_sample(16'd100);
        dsp_force_sample(16'd130);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        if (rd_spike_sum[6:0] !== 7'd1) begin
          $display("[SC17][FAIL] step1 sum=%0d", rd_spike_sum[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd135);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        if (rd_spike_sum[6:0] !== 7'd1) begin
          $display("[SC17][FAIL] step2 sum=%0d", rd_spike_sum[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd170);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        if (rd_spike_sum[6:0] !== 7'd2) begin
          $display("[SC17][FAIL] step3 sum=%0d", rd_spike_sum[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd190);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
        if (rd_spike_sum[6:0] !== 7'd3 || rd_peak_spike_sum[6:0] !== 7'd3) begin
          $display("[SC17][FAIL] step4 cur=%0d peak=%0d", rd_spike_sum[6:0], rd_peak_spike_sum[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd195);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_spike_sum[6:0] !== 7'd2 || rd_peak_spike_sum[6:0] !== 7'd3 || rd_status[2] !== 1'b0) begin
          $display("[SC17][FAIL] step5 cur=%0d peak=%0d irq=%0b", rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_status[2]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_003C);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0002);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0003);
        dsp_force_apb_write(32'h0000_104C, 32'h0000_0028);

        dsp_force_sample(16'd100);
        dsp_force_sample(16'd130);
        dsp_force_sample(16'd135);
        dsp_force_sample(16'd170);
        dsp_force_sample(16'd190);

        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1024, rd_event_cnt);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
        dsp_force_apb_read(32'h0000_101C, rd_peak_diff);
        if ((rd_status[2] !== 1'b0) || (rd_event_cnt[15:0] !== 16'd0) ||
            (rd_spike_sum[6:0] !== 7'd3) || (rd_peak_spike_sum[6:0] !== 7'd3) ||
            (rd_peak_diff[15:0] !== 16'd35)) begin
          $display("[SC17][FAIL] peak gate status=0x%08h event=%0d cur=%0d peak=%0d peak_diff=%0d",
                   rd_status, rd_event_cnt[15:0], rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_peak_diff[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_003C);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0002);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0003);
        dsp_force_apb_write(32'h0000_104C, 32'h0000_001E);

        dsp_force_sample(16'd100);
        dsp_force_sample(16'd130);
        dsp_force_sample(16'd135);
        dsp_force_sample(16'd170);
        dsp_force_sample(16'd190);

        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1024, rd_event_cnt);
        dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
        dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
        dsp_force_apb_read(32'h0000_101C, rd_peak_diff);
        if ((rd_status[3] !== 1'b1) || (rd_status[2] !== 1'b1) || (rd_status[1:0] !== 2'b11) ||
            (rd_int[15:0] >= 16'd60) || (rd_event_cnt[15:0] !== 16'd1) ||
            (rd_spike_sum[6:0] !== 7'd3) || (rd_peak_spike_sum[6:0] !== 7'd3) ||
            (rd_peak_diff[15:0] !== 16'd35)) begin
          $display("[SC17][FAIL] density fire status=0x%08h int=%0d event=%0d cur=%0d peak=%0d peak_diff=%0d",
                   rd_status, rd_int[15:0], rd_event_cnt[15:0], rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_peak_diff[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC17][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario18_noise_floor();
      reg [31:0] rd_noise;
      reg [31:0] rd_effective;
      reg [31:0] rd_diff;
      reg [31:0] rd_attack;
      reg [31:0] rd_status;
      begin
        $display("\n[DSP-UPG] SC18 adaptive noise floor");
        reset_dsp_focus();

        dsp_force_apb_write(32'h0000_1004, 32'h0000_0014);
        dsp_force_apb_write(32'h0000_1050, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_1054, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0000);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0000);

        dsp_force_apb_read(32'h0000_1058, rd_noise);
        dsp_force_apb_read(32'h0000_105C, rd_effective);
        if (rd_noise[15:0] !== 16'd0 || rd_effective[15:0] !== 16'd20) begin
          $display("[SC18][FAIL] init noise=%0d eff=%0d", rd_noise[15:0], rd_effective[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd100);
        dsp_force_apb_read(32'h0000_1058, rd_noise);
        dsp_force_apb_read(32'h0000_105C, rd_effective);
        if (rd_noise[15:0] !== 16'd0 || rd_effective[15:0] !== 16'd20) begin
          $display("[SC18][FAIL] sample1 noise=%0d eff=%0d", rd_noise[15:0], rd_effective[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd180);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1058, rd_noise);
        dsp_force_apb_read(32'h0000_105C, rd_effective);
        if (rd_diff[15:0] !== 16'd80 || rd_noise[15:0] !== 16'd40 || rd_effective[15:0] !== 16'd40) begin
          $display("[SC18][FAIL] sample2 diff=%0d noise=%0d eff=%0d", rd_diff[15:0], rd_noise[15:0], rd_effective[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd215);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        dsp_force_apb_read(32'h0000_1058, rd_noise);
        dsp_force_apb_read(32'h0000_105C, rd_effective);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_diff[15:0] !== 16'd35 || rd_attack[15:0] !== 16'd0 || rd_noise[15:0] !== 16'd37 ||
            rd_effective[15:0] !== 16'd38 || rd_status[2] !== 1'b0) begin
          $display("[SC18][FAIL] sample3 diff=%0d attack=%0d noise=%0d eff=%0d irq=%0b",
                   rd_diff[15:0], rd_attack[15:0], rd_noise[15:0], rd_effective[15:0], rd_status[2]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd217);
        dsp_force_apb_read(32'h0000_1058, rd_noise);
        dsp_force_apb_read(32'h0000_105C, rd_effective);
        if (rd_noise[15:0] !== 16'd19 || rd_effective[15:0] !== 16'd29) begin
          $display("[SC18][FAIL] sample4 noise=%0d eff=%0d", rd_noise[15:0], rd_effective[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC18][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario19_stream_awareness();
      reg [31:0] rd_status;
      reg [31:0] rd_diff;
      reg [31:0] rd_int;
      reg [31:0] rd_attack;
      reg [31:0] rd_restart_count;
      begin
        $display("\n[DSP-UPG] SC19 stream awareness");
        reset_dsp_focus();

        dsp_force_apb_write(32'h0000_1004, 32'h0000_0014);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1054, 32'h0000_0010);

        dsp_force_sample(16'd100);
        dsp_force_sample(16'd160);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_status[4] !== 1'b1) begin
          $display("[SC19][FAIL] partA initial pair status=0x%08h", rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        force dut.spi_stream_restart = 1'b1;
        @(posedge clk);
        force dut.spi_stream_restart = 1'b0;
        @(posedge clk);

        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1064, rd_restart_count);
        if (rd_status[4] !== 1'b0 || rd_restart_count[15:0] !== 16'd1) begin
          $display("[SC19][FAIL] partA restart status=0x%08h restart=%0d", rd_status, rd_restart_count[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd200);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_status[4] !== 1'b1) begin
          $display("[SC19][FAIL] partA sample1 diff=%0d int=%0d status=0x%08h", rd_diff[15:0], rd_int[15:0], rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd260);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_attack[15:0] !== 16'd0) begin
          $display("[SC19][FAIL] partA holdoff diff=%0d int=%0d attack=%0d", rd_diff[15:0], rd_int[15:0], rd_attack[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd340);
        dsp_force_apb_read(32'h0000_1014, rd_diff);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_1034, rd_attack);
        if (rd_diff[15:0] !== 16'd80 || rd_int[15:0] === 16'd0 || rd_attack[15:0] === 16'd0) begin
          $display("[SC19][FAIL] partB recovery diff=%0d int=%0d attack=%0d", rd_diff[15:0], rd_int[15:0], rd_attack[15:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC19][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario20_thermal_path();
      reg [31:0] rd_status;
      reg [31:0] rd_int;
      reg [31:0] rd_env;
      reg [31:0] rd_hotspot;
      integer k;
      begin
        $display("\n[DSP-UPG] SC20 thermal path");
        reset_dsp_focus();

        // Tat duong arc bang threshold rat cao, chi de nhanh thermal lam viec.
        dsp_force_apb_write(32'h0000_1004, 32'h0000_03E8); // base_thresh = 1000
        dsp_force_apb_write(32'h0000_1068, 32'h0000_00C8); // hot_base = 200
        dsp_force_apb_write(32'h0000_106C, 32'h0000_0014); // hot_attack = 20
        dsp_force_apb_write(32'h0000_1070, 32'h0000_0001); // hot_decay = 1
        dsp_force_apb_write(32'h0000_1074, 32'h0000_0064); // hot_limit = 100
        dsp_force_apb_write(32'h0000_1078, 32'h0000_0002); // env_shift = 2

        for (k = 0; k < 20; k = k + 1)
          dsp_force_sample(16'd500);

        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_107C, rd_env);
        dsp_force_apb_read(32'h0000_1080, rd_hotspot);

        if ((rd_status[2] !== 1'b1) || (rd_status[1:0] !== 2'b11) ||
            (rd_int[15:0] !== 16'd0) || (rd_env[15:0] <= 16'd200) || (rd_hotspot[15:0] < 16'd100)) begin
          $display("[SC20][FAIL] status=0x%08h int=%0d env=%0d hotspot=%0d", rd_status, rd_int[15:0], rd_env[15:0], rd_hotspot[15:0]);
          $display("[SC20][FAIL] Mong doi thermal path trip trong khi arc integrator van bang 0.");
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC20][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario21_default_glowing_contact();
      reg [31:0] rd_status;
      reg [31:0] rd_env;
      reg [31:0] rd_hotspot;
      reg [31:0] rd_events;
      integer base_heat;
      integer noise;
      integer sample_hi;
      integer sample_lo;
      integer idx;
      begin
        $display("\n[DSP-UPG] SC21 default glowing-contact tuning");
        reset_dsp_focus();

        base_heat = 0;
        for (idx = 0; idx < 150; idx = idx + 1) begin
          base_heat = base_heat + 20;
          if (base_heat > 2000)
            base_heat = 2000;

          noise = ((idx * 37) + 13) % 101;
          sample_hi = base_heat + noise;
          sample_lo = base_heat - noise;

          dsp_force_sample(sample_hi[15:0]);
          dsp_force_sample(sample_lo[15:0]);

          dsp_force_apb_read(32'h0000_1000, rd_status);
          if (rd_status[2]) begin
            dsp_force_apb_read(32'h0000_107C, rd_env);
            dsp_force_apb_read(32'h0000_1080, rd_hotspot);
            dsp_force_apb_read(32'h0000_1024, rd_events);

            if ((rd_hotspot[15:0] == 16'd0) || (rd_env[15:0] <= 16'd300) || (rd_events[15:0] == 16'd0)) begin
              $display("[SC21][FAIL] Trip xay ra nhung telemetry thermal khong hop ly: env=%0d hotspot=%0d event=%0d",
                       rd_env[15:0], rd_hotspot[15:0], rd_events[15:0]);
              fail_count = fail_count + 1;
              release_dsp_focus_forces();
              $stop;
            end

            release_dsp_focus_forces();
            $display("[SC21][PASS] fire tai cap mau thu %0d, env=%0d hotspot=%0d",
                     (idx + 1) * 2, rd_env[15:0], rd_hotspot[15:0]);
            pass_count = pass_count + 1;
            return;
          end
        end

        dsp_force_apb_read(32'h0000_107C, rd_env);
        dsp_force_apb_read(32'h0000_1080, rd_hotspot);
        $display("[SC21][FAIL] Khong trip voi default glowing-contact. env=%0d hotspot=%0d",
                 rd_env[15:0], rd_hotspot[15:0]);
        fail_count = fail_count + 1;
        release_dsp_focus_forces();
        $stop;
      end
    endtask

    task automatic scenario22_zero_cross_quiet_zone();
      reg [31:0] rd_status;
      reg [31:0] rd_int;
      reg [31:0] rd_peak_diff;
      reg [31:0] rd_quiet_len;
      reg [31:0] rd_last_gap;
      begin
        $display("\n[DSP-UPG] SC22 zero-cross / quiet-zone");
        reset_dsp_focus_safe();

        // Giữ detector thường khá "lì" để nếu trip xảy ra thì đến từ quiet-zone branch.
        dsp_force_apb_write(32'h0000_1004, 32'h0000_0064); // base_thresh = 100
        dsp_force_apb_write(32'h0000_1008, 32'h0000_03E8); // int_limit = 1000
        dsp_force_apb_write(32'h0000_1010, 32'h0000_0001); // base_attack = 1
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0006); // excess_shift = 6
        dsp_force_apb_write(32'h0000_1030, 32'h0000_0002); // attack_clamp = 2
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0008); // win_len = 8
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0001); // spike_sum_warn = 1
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0000); // density fire disabled
        dsp_force_apb_write(32'h0000_104C, 32'h0000_0096); // peak_diff_fire_thresh = 150
        dsp_force_apb_write(32'h0000_1084, 32'h0000_000A); // zero_band = 10
        dsp_force_apb_write(32'h0000_1088, 32'h0000_0002); // quiet_min = 2
        dsp_force_apb_write(32'h0000_108C, 32'h0000_0002); // quiet_max = 2

        // Evidence 1: spike lon -> vao vung zero-band -> doi dau gan zero.
        dsp_force_sample(16'd200);
        dsp_force_sample(16'd20);
        dsp_force_sample(16'd5);
        dsp_force_sample(16'hFFFB); // -5

        dsp_force_apb_read(32'h0000_1090, rd_quiet_len);
        dsp_force_apb_read(32'h0000_1094, rd_last_gap);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_quiet_len[7:0] !== 8'd2 || rd_last_gap[7:0] !== 8'd2 || rd_status[2] !== 1'b0) begin
          $display("[SC22][FAIL] evidence1 quiet_len=%0d last_gap=%0d status=0x%08h",
                   rd_quiet_len[7:0], rd_last_gap[7:0], rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        // Evidence 2: tao mot peak cuc bo moi roi moi zero-cross,
        // de quiet-zone branch dung "peak gan nhat" thay vi an theo peak cu toan cuc.
        dsp_force_sample(16'hFF38); // -200
        dsp_force_sample(16'hFFEC); // -20
        dsp_force_sample(16'hFFFB); // -5
        dsp_force_sample(16'd5);    // +5

        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1018, rd_int);
        dsp_force_apb_read(32'h0000_101C, rd_peak_diff);
        dsp_force_apb_read(32'h0000_1090, rd_quiet_len);
        dsp_force_apb_read(32'h0000_1094, rd_last_gap);
        if ((rd_status[2] !== 1'b1) || (rd_status[1:0] !== 2'b11) ||
            (rd_int[15:0] > 16'd4) || (rd_peak_diff[15:0] !== 16'd195) ||
            (rd_quiet_len[7:0] !== 8'd2) || (rd_last_gap[7:0] !== 8'd2)) begin
          $display("[SC22][FAIL] fire status=0x%08h int=%0d peak_diff=%0d quiet_len=%0d last_gap=%0d",
                   rd_status, rd_int[15:0], rd_peak_diff[15:0], rd_quiet_len[7:0], rd_last_gap[7:0]);
          $display("[SC22][FAIL] Mong doi trip do zero-cross / quiet-zone, khong phai do integrator thong thuong.");
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC22][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario23_trip_telemetry();
      reg [31:0] rd_status;
      reg [31:0] rd_last_diff;
      reg [31:0] rd_last_int;
      reg [31:0] rd_last_cause;
      integer k;
      begin
        $display("\n[DSP-UPG] SC23 trip telemetry");

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_0014);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0000);
        dsp_force_apb_write(32'h0000_1084, 32'h0000_0000);
        dsp_force_sample(16'd100);
        dsp_force_sample(16'd160);
        dsp_force_sample(16'd220);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1098, rd_last_diff);
        dsp_force_apb_read(32'h0000_109C, rd_last_int);
        dsp_force_apb_read(32'h0000_10A0, rd_last_cause);
        if ((rd_status[2] !== 1'b1) || (rd_last_cause[3:0] !== 4'd2) ||
            (rd_last_diff[15:0] !== 16'd60) || (rd_last_int[15:0] !== 16'd20)) begin
          $display("[SC23][FAIL] standard_arc status=0x%08h last_diff=%0d last_int=%0d cause=%0d",
                   rd_status, rd_last_diff[15:0], rd_last_int[15:0], rd_last_cause[3:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_003C);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0008);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0003);
        dsp_force_apb_write(32'h0000_104C, 32'h0000_001E);
        dsp_force_apb_write(32'h0000_1084, 32'h0000_0000);
        dsp_force_sample(16'd100);
        dsp_force_sample(16'd130);
        dsp_force_sample(16'd135);
        dsp_force_sample(16'd160);
        dsp_force_sample(16'd195);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1098, rd_last_diff);
        dsp_force_apb_read(32'h0000_109C, rd_last_int);
        dsp_force_apb_read(32'h0000_10A0, rd_last_cause);
        if ((rd_status[2] !== 1'b1) || (rd_last_cause[3:0] !== 4'd1) ||
            (rd_last_diff[15:0] !== 16'd35) || (rd_last_int[15:0] !== 16'd31)) begin
          $display("[SC23][FAIL] density_arc status=0x%08h last_diff=%0d last_int=%0d cause=%0d",
                   rd_status, rd_last_diff[15:0], rd_last_int[15:0], rd_last_cause[3:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_03E8);
        dsp_force_apb_write(32'h0000_1068, 32'h0000_00C8);
        dsp_force_apb_write(32'h0000_106C, 32'h0000_0014);
        dsp_force_apb_write(32'h0000_1070, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_1074, 32'h0000_0064);
        dsp_force_apb_write(32'h0000_1078, 32'h0000_0002);
        for (k = 0; k < 20; k = k + 1)
          dsp_force_sample(16'd500);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1098, rd_last_diff);
        dsp_force_apb_read(32'h0000_109C, rd_last_int);
        dsp_force_apb_read(32'h0000_10A0, rd_last_cause);
        if ((rd_status[2] !== 1'b1) || (rd_last_cause[3:0] !== 4'd3) ||
            (rd_last_diff[15:0] !== 16'd0) || (rd_last_int[15:0] !== 16'd0)) begin
          $display("[SC23][FAIL] thermal status=0x%08h last_diff=%0d last_int=%0d cause=%0d",
                   rd_status, rd_last_diff[15:0], rd_last_int[15:0], rd_last_cause[3:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        reset_dsp_focus_safe();
        dsp_force_apb_write(32'h0000_1004, 32'h0000_0064);
        dsp_force_apb_write(32'h0000_1008, 32'h0000_03E8);
        dsp_force_apb_write(32'h0000_1010, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_102C, 32'h0000_0006);
        dsp_force_apb_write(32'h0000_1030, 32'h0000_0002);
        dsp_force_apb_write(32'h0000_1038, 32'h0000_0008);
        dsp_force_apb_write(32'h0000_103C, 32'h0000_0001);
        dsp_force_apb_write(32'h0000_1040, 32'h0000_0000);
        dsp_force_apb_write(32'h0000_104C, 32'h0000_0096);
        dsp_force_apb_write(32'h0000_1084, 32'h0000_000A);
        dsp_force_apb_write(32'h0000_1088, 32'h0000_0002);
        dsp_force_apb_write(32'h0000_108C, 32'h0000_0002);
        dsp_force_sample(16'd200);
        dsp_force_sample(16'd20);
        dsp_force_sample(16'd5);
        dsp_force_sample(16'hFFFB);
        dsp_force_sample(16'hFF38);
        dsp_force_sample(16'hFFEC);
        dsp_force_sample(16'hFFFB);
        dsp_force_sample(16'd5);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        dsp_force_apb_read(32'h0000_1098, rd_last_diff);
        dsp_force_apb_read(32'h0000_109C, rd_last_int);
        dsp_force_apb_read(32'h0000_10A0, rd_last_cause);
        if ((rd_status[2] !== 1'b1) || (rd_last_cause[3:0] !== 4'd5) ||
            (rd_last_diff[15:0] !== 16'd10) || (rd_last_int[15:0] > 16'd4)) begin
          $display("[SC23][FAIL] quiet_zone status=0x%08h last_diff=%0d last_int=%0d cause=%0d",
                   rd_status, rd_last_diff[15:0], rd_last_int[15:0], rd_last_cause[3:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC23][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    task automatic scenario25_profile_boot_and_load();
      reg [31:0] rd_profile;
      reg [31:0] rd_gain;
      reg [31:0] rd_zero_band;
      reg [31:0] rd_spike_warn;
      reg [31:0] rd_spike_fire;
      reg [31:0] rd_status;
      begin
        $display("\n[DSP-UPG] SC25 boot profile / profile load");
        reset_dsp_focus();

        dsp_force_apb_read(32'h0000_10A4, rd_profile);
        dsp_force_apb_read(32'h0000_1054, rd_gain);
        dsp_force_apb_read(32'h0000_1084, rd_zero_band);
        dsp_force_apb_read(32'h0000_103C, rd_spike_warn);
        dsp_force_apb_read(32'h0000_1040, rd_spike_fire);
        if ((rd_profile[3:0] !== 4'd1) || (rd_profile[7:4] !== 4'd1) ||
            (rd_gain[4:0] !== 5'd3) || (rd_zero_band[15:0] !== 16'd6) ||
            (rd_spike_warn[6:0] !== 7'd3) || (rd_spike_fire[6:0] !== 7'd20)) begin
          $display("[SC25][FAIL] boot profile sai. profile=0x%08h gain=%0d zero=%0d warn=%0d fire=%0d",
                   rd_profile, rd_gain[4:0], rd_zero_band[15:0], rd_spike_warn[6:0], rd_spike_fire[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_sample(16'd100);
        dsp_force_sample(16'd160);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if (rd_status[4] !== 1'b1) begin
          $display("[SC25][FAIL] boot profile khong cho detector vao pair-valid. status=0x%08h", rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_apb_write(32'h0000_10A4, 32'h0000_0000);
        dsp_force_apb_read(32'h0000_10A4, rd_profile);
        dsp_force_apb_read(32'h0000_1054, rd_gain);
        dsp_force_apb_read(32'h0000_1084, rd_zero_band);
        dsp_force_apb_read(32'h0000_103C, rd_spike_warn);
        dsp_force_apb_read(32'h0000_1040, rd_spike_fire);
        dsp_force_apb_read(32'h0000_1000, rd_status);
        if ((rd_profile[3:0] !== 4'd0) || (rd_gain[4:0] !== 5'd16) ||
            (rd_zero_band[15:0] !== 16'd0) || (rd_spike_warn[6:0] !== 7'd0) ||
            (rd_spike_fire[6:0] !== 7'd0) || (rd_status[4] !== 1'b0)) begin
          $display("[SC25][FAIL] safe profile sai. profile=0x%08h gain=%0d zero=%0d warn=%0d fire=%0d status=0x%08h",
                   rd_profile, rd_gain[4:0], rd_zero_band[15:0], rd_spike_warn[6:0], rd_spike_fire[6:0], rd_status);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        dsp_force_apb_write(32'h0000_10A4, 32'h0000_0003);
        dsp_force_apb_read(32'h0000_10A4, rd_profile);
        dsp_force_apb_read(32'h0000_1054, rd_gain);
        dsp_force_apb_read(32'h0000_1084, rd_zero_band);
        dsp_force_apb_read(32'h0000_1040, rd_spike_fire);
        if ((rd_profile[3:0] !== 4'd3) || (rd_gain[4:0] !== 5'd4) ||
            (rd_zero_band[15:0] !== 16'd10) || (rd_spike_fire[6:0] !== 7'd6)) begin
          $display("[SC25][FAIL] lab profile sai. profile=0x%08h gain=%0d zero=%0d fire=%0d",
                   rd_profile, rd_gain[4:0], rd_zero_band[15:0], rd_spike_fire[6:0]);
          fail_count = fail_count + 1;
          release_dsp_focus_forces();
          $stop;
        end

        release_dsp_focus_forces();
        $display("[SC25][PASS]");
        pass_count = pass_count + 1;
      end
    endtask

    initial begin
        #100;
        scenario16_weighted_attack();
        scenario17_spike_window();
        scenario18_noise_floor();
        scenario19_stream_awareness();
        scenario20_thermal_path();
        scenario21_default_glowing_contact();
        scenario22_zero_cross_quiet_zone();
        scenario23_trip_telemetry();
        scenario25_profile_boot_and_load();
        $display("\n[DSP-UPG] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end

    initial begin
        #2000000;
        $display("[DSP-UPG][FATAL] Timeout.");
        $stop;
    end

endmodule
