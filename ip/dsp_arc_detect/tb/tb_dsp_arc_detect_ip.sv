`timescale 1ns/1ps

module tb_dsp_arc_detect_ip;

    localparam int DATA_WIDTH = 16;
    localparam int CNT_WIDTH  = 16;

    localparam logic [31:0] ADDR_STATUS               = 32'h00;
    localparam logic [31:0] ADDR_BASE_THRESH          = 32'h04;
    localparam logic [31:0] ADDR_INT_LIMIT            = 32'h08;
    localparam logic [31:0] ADDR_DECAY_RATE           = 32'h0C;
    localparam logic [31:0] ADDR_BASE_ATTACK          = 32'h10;
    localparam logic [31:0] ADDR_CUR_DIFF             = 32'h14;
    localparam logic [31:0] ADDR_CUR_INT              = 32'h18;
    localparam logic [31:0] ADDR_PEAK_DIFF            = 32'h1C;
    localparam logic [31:0] ADDR_EVENT_COUNT          = 32'h24;
    localparam logic [31:0] ADDR_CLEAR                = 32'h28;
    localparam logic [31:0] ADDR_EXCESS_SHIFT         = 32'h2C;
    localparam logic [31:0] ADDR_ATTACK_CLAMP         = 32'h30;
    localparam logic [31:0] ADDR_CUR_ATTACK           = 32'h34;
    localparam logic [31:0] ADDR_WIN_LEN              = 32'h38;
    localparam logic [31:0] ADDR_SPIKE_SUM_WARN       = 32'h3C;
    localparam logic [31:0] ADDR_SPIKE_SUM_FIRE       = 32'h40;
    localparam logic [31:0] ADDR_PEAK_DIFF_FIRE       = 32'h4C;
    localparam logic [31:0] ADDR_ALPHA_SHIFT          = 32'h50;
    localparam logic [31:0] ADDR_GAIN_SHIFT           = 32'h54;
    localparam logic [31:0] ADDR_EFFECTIVE_THRESH     = 32'h5C;
    localparam logic [31:0] ADDR_STREAM_STATUS        = 32'h60;
    localparam logic [31:0] ADDR_STREAM_RESTART_COUNT = 32'h64;
    localparam logic [31:0] ADDR_HOT_BASE             = 32'h68;
    localparam logic [31:0] ADDR_HOT_ATTACK           = 32'h6C;
    localparam logic [31:0] ADDR_HOT_DECAY            = 32'h70;
    localparam logic [31:0] ADDR_HOT_LIMIT            = 32'h74;
    localparam logic [31:0] ADDR_ENV_SHIFT            = 32'h78;
    localparam logic [31:0] ADDR_ZERO_BAND            = 32'h84;
    localparam logic [31:0] ADDR_QUIET_MIN            = 32'h88;
    localparam logic [31:0] ADDR_QUIET_MAX            = 32'h8C;
    localparam logic [31:0] ADDR_LAST_FIRE_DIFF       = 32'h98;
    localparam logic [31:0] ADDR_LAST_FIRE_INT        = 32'h9C;
    localparam logic [31:0] ADDR_LAST_CAUSE           = 32'hA0;
    localparam logic [31:0] ADDR_PROFILE_CTRL         = 32'hA4;

    logic                  clk_i;
    logic                  rst_ni;
    logic [DATA_WIDTH-1:0] adc_data_i;
    logic                  adc_valid_i;
    logic                  stream_restart_i;
    logic [31:0]           paddr_i;
    logic [31:0]           pwdata_i;
    logic                  pwrite_i;
    logic                  psel_i;
    logic                  penable_i;
    logic [31:0]           prdata_o;
    logic                  pready_o;
    logic                  pslverr_o;
    logic                  irq_arc_o;

    int pass_count;
    int fail_count;

    dsp_arc_detect_apb_wrapper #(
        .DATA_WIDTH(DATA_WIDTH),
        .CNT_WIDTH (CNT_WIDTH)
    ) dut (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .adc_data_i       (adc_data_i),
        .adc_valid_i      (adc_valid_i),
        .stream_restart_i (stream_restart_i),
        .paddr_i          (paddr_i),
        .pwdata_i         (pwdata_i),
        .pwrite_i         (pwrite_i),
        .psel_i           (psel_i),
        .penable_i        (penable_i),
        .prdata_o         (prdata_o),
        .pready_o         (pready_o),
        .pslverr_o        (pslverr_o),
        .irq_arc_o        (irq_arc_o)
    );

    dsp_arc_detect_ip_assertions u_assertions (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .adc_valid_i      (adc_valid_i),
        .adc_data_i       (adc_data_i),
        .stream_restart_i (stream_restart_i),
        .psel_i           (psel_i),
        .penable_i        (penable_i),
        .pwrite_i         (pwrite_i),
        .paddr_i          (paddr_i),
        .pwdata_i         (pwdata_i),
        .prdata_o         (prdata_o),
        .pready_o         (pready_o),
        .pslverr_o        (pslverr_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #10 clk_i = ~clk_i;
    end

    task automatic fail_now(input string label, input logic [31:0] actual, input logic [31:0] expected);
        begin
            fail_count++;
            $display("[DSP-IP][FAIL] %s expected=0x%08h actual=0x%08h", label, expected, actual);
            $display("[DSP-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
            $fatal(1, "[DSP-IP] stopping after first failure");
        end
    endtask

    task automatic expect32(input string label, input logic [31:0] actual, input logic [31:0] expected);
        begin
            if (actual !== expected) begin
                fail_now(label, actual, expected);
            end
        end
    endtask

    task automatic expect_bit(input string label, input logic actual, input logic expected);
        begin
            if (actual !== expected) begin
                fail_now(label, {31'd0, actual}, {31'd0, expected});
            end
        end
    endtask

    task automatic scenario_pass(input string label);
        begin
            pass_count++;
            $display("[DSP-IP][PASS] %s", label);
        end
    endtask

    task automatic reset_ip();
        begin
            rst_ni           = 1'b0;
            adc_data_i       = '0;
            adc_valid_i      = 1'b0;
            stream_restart_i = 1'b0;
            paddr_i          = 32'd0;
            pwdata_i         = 32'd0;
            pwrite_i         = 1'b0;
            psel_i           = 1'b0;
            penable_i        = 1'b0;

            repeat (5) @(posedge clk_i);
            rst_ni = 1'b1;
            repeat (4) @(posedge clk_i);
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

            @(posedge clk_i);
            #1;
            expect_bit("APB write pready", pready_o, 1'b1);
            expect_bit("APB write pslverr", pslverr_o, 1'b0);

            @(negedge clk_i);
            paddr_i   = 32'd0;
            pwdata_i  = 32'd0;
            pwrite_i  = 1'b0;
            psel_i    = 1'b0;
            penable_i = 1'b0;
        end
    endtask

    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk_i);
            paddr_i   = addr;
            pwdata_i  = 32'd0;
            pwrite_i  = 1'b0;
            psel_i    = 1'b1;
            penable_i = 1'b0;

            @(negedge clk_i);
            penable_i = 1'b1;

            @(posedge clk_i);
            #1;
            expect_bit("APB read pready", pready_o, 1'b1);
            expect_bit("APB read pslverr", pslverr_o, 1'b0);
            data = prdata_o;

            @(negedge clk_i);
            paddr_i   = 32'd0;
            pwrite_i  = 1'b0;
            psel_i    = 1'b0;
            penable_i = 1'b0;
        end
    endtask

    task automatic send_sample(input logic [15:0] sample_word);
        begin
            @(negedge clk_i);
            adc_data_i  = sample_word;
            adc_valid_i = 1'b1;

            @(negedge clk_i);
            adc_valid_i = 1'b0;
        end
    endtask

    task automatic pulse_stream_restart();
        begin
            @(negedge clk_i);
            stream_restart_i = 1'b1;
            @(negedge clk_i);
            stream_restart_i = 1'b0;
        end
    endtask

    task automatic scenario_reset_register_map();
        logic [31:0] rd;
        begin
            $display("[DSP-IP] SC01 reset register map");
            reset_ip();

            apb_read(ADDR_STATUS, rd);               expect32("STATUS reset", rd, 32'h0000_0000);
            apb_read(ADDR_BASE_THRESH, rd);          expect32("BASE_THRESH reset", rd, 32'h0000_0050);
            apb_read(ADDR_INT_LIMIT, rd);            expect32("INT_LIMIT reset", rd, 32'h0000_03E8);
            apb_read(ADDR_DECAY_RATE, rd);           expect32("DECAY_RATE reset", rd, 32'h0000_0001);
            apb_read(ADDR_BASE_ATTACK, rd);          expect32("BASE_ATTACK reset", rd, 32'h0000_000A);
            apb_read(ADDR_EXCESS_SHIFT, rd);         expect32("EXCESS_SHIFT reset", rd, 32'h0000_0004);
            apb_read(ADDR_ATTACK_CLAMP, rd);         expect32("ATTACK_CLAMP reset", rd, 32'h0000_000F);
            apb_read(ADDR_WIN_LEN, rd);              expect32("WIN_LEN reset", rd, 32'h0000_0020);
            apb_read(ADDR_SPIKE_SUM_WARN, rd);       expect32("SPIKE_SUM_WARN reset", rd, 32'h0000_0003);
            apb_read(ADDR_SPIKE_SUM_FIRE, rd);       expect32("SPIKE_SUM_FIRE reset", rd, 32'h0000_0014);
            apb_read(ADDR_PEAK_DIFF_FIRE, rd);       expect32("PEAK_DIFF_FIRE reset", rd, 32'h0000_00DC);
            apb_read(ADDR_ALPHA_SHIFT, rd);          expect32("ALPHA_SHIFT reset", rd, 32'h0000_0002);
            apb_read(ADDR_GAIN_SHIFT, rd);           expect32("GAIN_SHIFT reset", rd, 32'h0000_0003);
            apb_read(ADDR_EFFECTIVE_THRESH, rd);     expect32("EFFECTIVE_THRESH reset", rd, 32'h0000_0050);
            apb_read(ADDR_STREAM_STATUS, rd);        expect32("STREAM_STATUS reset", rd, 32'h0000_0000);
            apb_read(ADDR_STREAM_RESTART_COUNT, rd); expect32("STREAM_RESTART_COUNT reset", rd, 32'h0000_0000);
            apb_read(ADDR_HOT_BASE, rd);             expect32("HOT_BASE reset", rd, 32'h0000_01F4);
            apb_read(ADDR_HOT_ATTACK, rd);           expect32("HOT_ATTACK reset", rd, 32'h0000_0020);
            apb_read(ADDR_HOT_DECAY, rd);            expect32("HOT_DECAY reset", rd, 32'h0000_0004);
            apb_read(ADDR_HOT_LIMIT, rd);            expect32("HOT_LIMIT reset", rd, 32'h0000_0060);
            apb_read(ADDR_ENV_SHIFT, rd);            expect32("ENV_SHIFT reset", rd, 32'h0000_0004);
            apb_read(ADDR_ZERO_BAND, rd);            expect32("ZERO_BAND reset", rd, 32'h0000_0006);
            apb_read(ADDR_QUIET_MIN, rd);            expect32("QUIET_MIN reset", rd, 32'h0000_0002);
            apb_read(ADDR_QUIET_MAX, rd);            expect32("QUIET_MAX reset", rd, 32'h0000_0004);
            apb_read(ADDR_PROFILE_CTRL, rd);         expect32("PROFILE_CTRL reset", rd, 32'h0000_0011);
            apb_read(32'h0000_00FC, rd);             expect32("unmapped read", rd, 32'h0000_0000);

            scenario_pass("SC01 reset register map");
        end
    endtask

    task automatic scenario_apb_write_clamp_profile();
        logic [31:0] rd;
        begin
            $display("[DSP-IP] SC02 APB writes, clamps, profile sanitize");
            reset_ip();

            apb_write(ADDR_BASE_THRESH, 32'h0000_0012);
            apb_read(ADDR_BASE_THRESH, rd); expect32("BASE_THRESH write/read", rd, 32'h0000_0012);

            apb_write(ADDR_WIN_LEN, 32'h0000_0000);
            apb_read(ADDR_WIN_LEN, rd); expect32("WIN_LEN clamps low", rd, 32'h0000_0001);

            apb_write(ADDR_SPIKE_SUM_FIRE, 32'h0000_0063);
            apb_read(ADDR_SPIKE_SUM_FIRE, rd); expect32("SPIKE_SUM_FIRE clamps to window", rd, 32'h0000_0001);

            apb_write(ADDR_WIN_LEN, 32'h0000_0004);
            apb_read(ADDR_WIN_LEN, rd); expect32("WIN_LEN write/read", rd, 32'h0000_0004);

            apb_write(ADDR_SPIKE_SUM_WARN, 32'h0000_0009);
            apb_read(ADDR_SPIKE_SUM_WARN, rd); expect32("SPIKE_SUM_WARN clamps to window", rd, 32'h0000_0004);

            apb_write(ADDR_PROFILE_CTRL, 32'h0000_000F);
            apb_read(ADDR_PROFILE_CTRL, rd); expect32("invalid profile sanitized", rd, 32'h0000_0010);
            apb_read(ADDR_BASE_THRESH, rd);  expect32("SAFE_RESET base threshold", rd, 32'h0000_0032);

            apb_write(ADDR_PROFILE_CTRL, 32'h0000_0001);
            apb_read(ADDR_PROFILE_CTRL, rd); expect32("ARC_BALANCED profile restored", rd, 32'h0000_0011);
            apb_read(ADDR_BASE_THRESH, rd);  expect32("ARC_BALANCED base threshold", rd, 32'h0000_0050);

            scenario_pass("SC02 APB writes, clamps, profile sanitize");
        end
    endtask

    task automatic scenario_stream_restart();
        logic [31:0] rd;
        begin
            $display("[DSP-IP] SC03 stream restart state");
            reset_ip();

            send_sample(16'd100);
            send_sample(16'd160);
            repeat (2) @(posedge clk_i);
            apb_read(ADDR_STATUS, rd); expect_bit("sample pair valid before restart", rd[4], 1'b1);

            pulse_stream_restart();
            repeat (2) @(posedge clk_i);
            apb_read(ADDR_STATUS, rd); expect_bit("sample pair cleared by restart", rd[4], 1'b0);
            apb_read(ADDR_STREAM_RESTART_COUNT, rd); expect32("restart count increment", rd, 32'h0000_0001);

            apb_write(ADDR_CLEAR, 32'h0000_0010);
            apb_read(ADDR_STREAM_RESTART_COUNT, rd); expect32("restart count clear", rd, 32'h0000_0000);

            scenario_pass("SC03 stream restart state");
        end
    endtask

    task automatic scenario_standard_fire_and_clear();
        logic [31:0] rd;
        begin
            $display("[DSP-IP] SC04 standard fire and clear commands");
            reset_ip();

            apb_write(ADDR_PROFILE_CTRL, 32'h0000_0000);
            apb_write(ADDR_BASE_ATTACK, 32'h0000_000A);
            apb_write(ADDR_EXCESS_SHIFT, 32'h0000_0004);
            apb_write(ADDR_ATTACK_CLAMP, 32'h0000_000F);

            send_sample(16'd100);
            repeat (2) @(posedge clk_i);
            apb_read(ADDR_STATUS, rd); expect_bit("first sample creates pair history", rd[4], 1'b1);

            send_sample(16'd140);
            repeat (2) @(posedge clk_i);
            apb_read(ADDR_CUR_DIFF, rd); expect32("below-threshold diff", rd, 32'h0000_0028);
            apb_read(ADDR_CUR_INT, rd);  expect32("below-threshold integrator", rd, 32'h0000_0000);

            send_sample(16'd220);
            repeat (2) @(posedge clk_i);
            apb_read(ADDR_CUR_DIFF, rd);   expect32("weighted diff", rd, 32'h0000_0050);
            apb_read(ADDR_CUR_INT, rd);    expect32("weighted integrator", rd, 32'h0000_000B);
            apb_read(ADDR_CUR_ATTACK, rd); expect32("weighted attack", rd, 32'h0000_000B);

            apb_write(ADDR_INT_LIMIT, 32'h0000_0014);
            send_sample(16'd0);
            repeat (2) @(posedge clk_i);

            apb_read(ADDR_STATUS, rd);
            expect_bit("fire status bit0", rd[0], 1'b1);
            expect_bit("fire status bit1", rd[1], 1'b1);
            expect_bit("fire irq", rd[2], 1'b1);
            expect_bit("fire latched", rd[3], 1'b1);

            apb_read(ADDR_EVENT_COUNT, rd);    expect32("event count after fire", rd, 32'h0000_0001);
            apb_read(ADDR_LAST_CAUSE, rd);     expect32("standard fire cause", rd, 32'h0000_0002);
            apb_read(ADDR_LAST_FIRE_DIFF, rd); expect32("last fire diff", rd, 32'h0000_00DC);
            apb_read(ADDR_LAST_FIRE_INT, rd);  expect32("last fire integrator", rd, 32'h0000_0014);

            apb_write(ADDR_CLEAR, 32'h0000_0007);
            apb_read(ADDR_EVENT_COUNT, rd); expect32("event count clear", rd, 32'h0000_0000);
            apb_read(ADDR_PEAK_DIFF, rd);   expect32("peak diff clear", rd, 32'h0000_0000);
            apb_read(ADDR_LAST_CAUSE, rd);  expect32("last cause clear", rd, 32'h0000_0000);
            apb_read(ADDR_STATUS, rd);      expect_bit("fire latch clear", rd[3], 1'b0);

            scenario_pass("SC04 standard fire and clear commands");
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        scenario_reset_register_map();
        scenario_apb_write_clamp_profile();
        scenario_stream_restart();
        scenario_standard_fire_and_clear();

        $display("[DSP-IP] SUMMARY PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $finish;
        end else begin
            $fatal(1, "[DSP-IP] regression failed");
        end
    end

endmodule
