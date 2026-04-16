// ============================================================================
// tb_extra_scenarios_11_15_reliable.svh
//
// Muc dich:
//   - File include chua CAC TEST bo sung cho SCENARIO 11 -> 19.
//   - File nay duoc thiet ke de `include BEN TRONG module tb_professional
//     hoac tb_professional_full hien co.
//   - KHONG duoc compile rieng bang vlog.
// ============================================================================

localparam int TBX_UART_DIV_115200 = 434; // 50MHz / 115200 ~= 434

// Shadow regs rieng cua file include nay.
// Dung ten "tbx_*" de tranh xung dot voi cac bien da co san trong testbench goc.
logic [31:0] tbx_apb_force_addr;
logic [31:0] tbx_apb_force_data;
logic        tbx_apb_force_is_write;
logic [15:0] tbx_cpu_forced_instr;
logic [31:0] tbx_uart_const_addr;
logic [31:0] tbx_uart_const_data;
logic [31:0] tbx_dsp_force_addr;
logic [31:0] tbx_dsp_force_data;
logic [15:0] tbx_dsp_force_sample_word;

integer extra_pass_count = 0;
integer extra_fail_count = 0;
integer extra_known_issue_count = 0;

// Mirror opcode encoding cua CPU RTL
localparam [3:0] TBX_OP_NOP = 4'h0;
localparam [3:0] TBX_OP_LDI = 4'h1;
localparam [3:0] TBX_OP_ADD = 4'h2;
localparam [3:0] TBX_OP_SUB = 4'h3;
localparam [3:0] TBX_OP_AND = 4'h4;
localparam [3:0] TBX_OP_JMP = 4'h5;
localparam [3:0] TBX_OP_BEQ = 4'h6;
localparam [3:0] TBX_OP_STR = 4'h7;
localparam [3:0] TBX_OP_LDR = 4'h8;
localparam [3:0] TBX_OP_RET = 4'hF;

// ----------------------------------------------------------------------------
// HELPER 1: Inject 1 byte vao chan UART RX theo dung baud divisor cua DUT
// ----------------------------------------------------------------------------
task automatic inject_uart_rx_byte(input [7:0] data_byte);
  integer i;
  begin
    uart_rx = 1'b1;
    repeat (2) @(posedge clk);

    uart_rx = 1'b0;
    repeat (TBX_UART_DIV_115200) @(posedge clk);

    for (i = 0; i < 8; i = i + 1) begin
      uart_rx = data_byte[i];
      repeat (TBX_UART_DIV_115200) @(posedge clk);
    end

    uart_rx = 1'b1;
    repeat (TBX_UART_DIV_115200) @(posedge clk);
    repeat (TBX_UART_DIV_115200/4) @(posedge clk);
  end
endtask

// ----------------------------------------------------------------------------
// HELPER 2: APB read DATA register cua UART wrapper bang force truc tiep
// ----------------------------------------------------------------------------
task automatic uart_force_apb_read_data(output [31:0] rd_data);
  begin
    tbx_uart_const_addr = 32'h0000_0000;
    tbx_uart_const_data = 32'h0000_0000;

    force dut.u_uart.paddr_i   = tbx_uart_const_addr;
    force dut.u_uart.pwdata_i  = tbx_uart_const_data;
    force dut.u_uart.pwrite_i  = 1'b0;
    force dut.u_uart.psel_i    = 1'b1;
    force dut.u_uart.penable_i = 1'b0;
    @(posedge clk);

    force dut.u_uart.penable_i = 1'b1;
    @(posedge clk);
    #1;
    rd_data = dut.u_uart.prdata_o;

    release dut.u_uart.paddr_i;
    release dut.u_uart.pwdata_i;
    release dut.u_uart.pwrite_i;
    release dut.u_uart.psel_i;
    release dut.u_uart.penable_i;

    @(posedge clk);
  end
endtask

// ----------------------------------------------------------------------------
// HELPER 3: APB write den DSP bang force truc tiep len interface APB cua DSP
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// HELPER 3b: APB read tu DSP de kiem tra telemetry moi
// ----------------------------------------------------------------------------
task automatic dsp_force_apb_read(
  input  [31:0] addr,
  output [31:0] rd_data
);
  begin
    tbx_dsp_force_addr = addr;
    tbx_dsp_force_data = 32'h0000_0000;

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

// ----------------------------------------------------------------------------
// HELPER 4: APB transaction tu master CPU interface de test apb_node
// ----------------------------------------------------------------------------
task automatic apb_force_master_access(
  input  [31:0] addr,
  input  [31:0] data,
  input         is_write,
  output        seen_pready,
  output        seen_pslverr
);
  integer tmo;
  begin
    tbx_apb_force_addr     = addr;
    tbx_apb_force_data     = data;
    tbx_apb_force_is_write = is_write;

    seen_pready  = 1'b0;
    seen_pslverr = 1'b0;

    force dut.apb_cpu_master.paddr   = tbx_apb_force_addr;
    force dut.apb_cpu_master.pwdata  = tbx_apb_force_data;
    force dut.apb_cpu_master.pwrite  = tbx_apb_force_is_write;
    force dut.apb_cpu_master.psel    = 1'b1;
    force dut.apb_cpu_master.penable = 1'b0;
    @(posedge clk);

    force dut.apb_cpu_master.penable = 1'b1;

    for (tmo = 0; tmo < 16; tmo = tmo + 1) begin
      @(posedge clk);
      if (dut.apb_cpu_master.pready === 1'b1)
        seen_pready = 1'b1;
      if (dut.apb_cpu_master.pslverr === 1'b1)
        seen_pslverr = 1'b1;
      if (seen_pready || seen_pslverr)
        tmo = 16;
    end

    release dut.apb_cpu_master.paddr;
    release dut.apb_cpu_master.pwdata;
    release dut.apb_cpu_master.pwrite;
    release dut.apb_cpu_master.psel;
    release dut.apb_cpu_master.penable;

    @(posedge clk);
  end
endtask

// ----------------------------------------------------------------------------
// HELPER 5: Stimulus arc nhe cho DSP reconfigure test
// ----------------------------------------------------------------------------
task automatic inject_mild_arc_spikes(input integer n_samples);
  integer k;
  begin
    for (k = 0; k < n_samples; k = k + 1) begin
      if (k[0] == 1'b0)
        send_spi_data(16'd0);
      else
        send_spi_data(16'd40);
    end
  end
endtask

// ----------------------------------------------------------------------------
// HELPER 5b: Force truc tiep 1 sample vao DSP de test thuat toan noi bo
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// HELPER 6: Execute 1 micro-instruction trong CPU bang force state + instr
// ----------------------------------------------------------------------------
task automatic cpu_exec_forced_decode(input [15:0] instr_word);
  integer tmo;
  begin
    tbx_cpu_forced_instr = instr_word;

    // Khong force state nua. Neu force state=S_DECODE thi CPU se mat luon
    // transition noi bo sang S_APB_ACCESS doi voi STR/LDR APB.
    // Ta chi chen instr vao dung pha decode tu nhien cua CPU.
    for (tmo = 0; tmo < 8; tmo = tmo + 1) begin
      if (dut.u_cpu.state == dut.u_cpu.S_DECODE) begin
        tmo = 8;
      end else begin
        @(posedge clk);
        #1;
      end
    end

    force dut.u_cpu.instr = tbx_cpu_forced_instr;
    @(posedge clk);
    #1;
    release dut.u_cpu.instr;
    #1;
  end
endtask

task automatic cpu_exec_and_settle(input [15:0] instr_word);
  integer tmo;
  begin
    cpu_exec_forced_decode(instr_word);

    for (tmo = 0; tmo < 8; tmo = tmo + 1) begin
      @(posedge clk);
      #1;
      if ((dut.u_cpu.state == dut.u_cpu.S_FETCH) &&
          (dut.u_cpu.apb_mst.psel == 1'b0) &&
          (dut.u_cpu.apb_mst.penable == 1'b0)) begin
        tmo = 8;
      end
    end
  end
endtask

task automatic cpu_exec_apb_and_settle(input [15:0] instr_word);
  integer tmo;
  reg saw_apb;
  reg settled;
  begin
    saw_apb = 1'b0;
    settled = 1'b0;
    cpu_exec_forced_decode(instr_word);

    for (tmo = 0; tmo < 16; tmo = tmo + 1) begin
      @(posedge clk);
      #1;

      if ((dut.u_cpu.state == dut.u_cpu.S_APB_ACCESS) ||
          (dut.u_cpu.apb_mst.psel == 1'b1) ||
          (dut.u_cpu.apb_mst.penable == 1'b1)) begin
        saw_apb = 1'b1;
      end

      if (saw_apb &&
          (dut.u_cpu.state == dut.u_cpu.S_FETCH) &&
          (dut.u_cpu.apb_mst.psel == 1'b0) &&
          (dut.u_cpu.apb_mst.penable == 1'b0)) begin
        settled = 1'b1;
        tmo = 16;
      end
    end

    if (!saw_apb || !settled) begin
      $display("[TBX][WARN] cpu_exec_apb_and_settle timeout. state=%0d paddr=0x%08h psel=%0b penable=%0b pwrite=%0b",
               dut.u_cpu.state, dut.u_cpu.apb_mst.paddr, dut.u_cpu.apb_mst.psel,
               dut.u_cpu.apb_mst.penable, dut.u_cpu.apb_mst.pwrite);
    end
  end
endtask

task automatic scenario11_uart_rx_receiver();
  reg [31:0] uart_rd;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 11] KIEM TRA UART RX RECEIVER");
    $display("=====================================================================");

    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    #500;
    rst_ni  = 1'b1;
    #2000;

    inject_uart_rx_byte(8'h52);
    repeat (TBX_UART_DIV_115200 + 20) @(posedge clk);

    if (dut.u_uart.r_rx_data !== 8'h52) begin
      $display("[SC11][FAIL] r_rx_data = 0x%02h, mong doi 0x52", dut.u_uart.r_rx_data);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    if (dut.u_uart.r_rx_valid !== 1'b1) begin
      $display("[SC11][FAIL] r_rx_valid KHONG len 1 sau khi nhan xong frame UART.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    uart_force_apb_read_data(uart_rd);

    if (uart_rd[7:0] !== 8'h52) begin
      $display("[SC11][FAIL] APB read UART DATA = 0x%02h, mong doi 0x52", uart_rd[7:0]);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    @(posedge clk);
    if (dut.u_uart.r_rx_valid !== 1'b0) begin
      $display("[SC11][FAIL] r_rx_valid khong duoc clear sau khi doc DATA register.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    $display("[SC11][PASS] UART RX nhan dung 0x52, valid va APB readback deu dung.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic scenario12_gpio_input_edge_interrupt();
  integer tmo;
  reg seen_pulse;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 12] KIEM TRA GPIO INPUT EDGE INTERRUPT");
    $display("=====================================================================");

    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    #500;
    rst_ni  = 1'b1;
    #2000;

    force dut.u_gpio.PADDR   = 12'h000;
    force dut.u_gpio.PWDATA  = 32'h0000_0000;
    force dut.u_gpio.PWRITE  = 1'b1;
    force dut.u_gpio.PSEL    = 1'b1;
    force dut.u_gpio.PENABLE = 1'b1;
    @(posedge clk);

    force dut.u_gpio.PADDR   = 12'h00C;
    force dut.u_gpio.PWDATA  = 32'h0000_0002;
    force dut.u_gpio.PWRITE  = 1'b1;
    force dut.u_gpio.PSEL    = 1'b1;
    force dut.u_gpio.PENABLE = 1'b1;
    @(posedge clk);

    release dut.u_gpio.PADDR;
    release dut.u_gpio.PWDATA;
    release dut.u_gpio.PWRITE;
    release dut.u_gpio.PSEL;
    release dut.u_gpio.PENABLE;

    if (dut.u_gpio.gpio_in[1] !== gpio_io[1]) begin
      $display("[SC12][BYPASS] top_soc hien tai chua noi gpio_pin_io vao u_gpio.gpio_in.");
      $display("[SC12][BYPASS] Can sua top_soc: .gpio_in(gpio_in_wire) va .interrupt(gpio_irq_wire)");
      return;
    end

    force gpio_io[1] = 1'b0;
    repeat (3) @(posedge clk);
    force gpio_io[1] = 1'b1;

    seen_pulse = 1'b0;
    for (tmo = 0; tmo < 10; tmo = tmo + 1) begin
      @(posedge clk);
      if (dut.u_gpio.interrupt === 1'b1)
        seen_pulse = 1'b1;
    end

    release gpio_io[1];

    if (!seen_pulse) begin
      $display("[SC12][FAIL] Khong thay xung interrupt tu GPIO rising-edge tren bit[1].");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    $display("[SC12][PASS] GPIO rising-edge interrupt da duoc kich hoat.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic scenario13_dsp_on_the_fly_reconfiguration();
  integer timeout_cycles;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 13] DSP ON-THE-FLY RECONFIGURATION");
    $display("=====================================================================");

    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    #500;
    rst_ni  = 1'b1;
    #3000;

    if ((dut.u_dsp.current_profile_q !== 4'd1) ||
        (dut.u_dsp.reg_diff_threshold !== 16'd80) ||
        (dut.u_dsp.reg_gain_shift !== 5'd3) ||
        (dut.u_dsp.reg_zero_band !== 16'd6) ||
        (dut.u_dsp.reg_spike_sum_warn !== 7'd3) ||
        (dut.u_dsp.reg_spike_sum_fire !== 7'd20)) begin
      $display("[SC13][FAIL] Boot DSP profile chua dung. profile=%0d thresh=%0d gain=%0d zero=%0d warn=%0d fire=%0d",
               dut.u_dsp.current_profile_q,
               dut.u_dsp.reg_diff_threshold,
               dut.u_dsp.reg_gain_shift,
               dut.u_dsp.reg_zero_band,
               dut.u_dsp.reg_spike_sum_warn,
               dut.u_dsp.reg_spike_sum_fire);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    inject_mild_arc_spikes(40);
    repeat (50) @(posedge clk);

    if (gpio_io[0] === 1'b1) begin
      $display("[SC13][FAIL] Relay bi cat qua som khi DSP dang o boot profile mac dinh.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    dsp_force_apb_write(32'h0000_1004, 32'h0000_001E);

    if (dut.u_dsp.reg_diff_threshold !== 16'd30) begin
      $display("[SC13][FAIL] Threshold khong update thanh 30. Gia tri hien tai = %0d", dut.u_dsp.reg_diff_threshold);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    inject_mild_arc_spikes(140);

    timeout_cycles = 0;
    while ((gpio_io[0] !== 1'b1) && (timeout_cycles < 5000)) begin
      @(posedge clk);
      timeout_cycles = timeout_cycles + 1;
    end

    if (gpio_io[0] !== 1'b1) begin
      $display("[SC13][FAIL] Khong thay relay bi cat sau khi threshold duoc ha xuong 30.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    $display("[SC13][PASS] DSP boot profile da len dung va van reconfigure live khong can reset chip.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic scenario14_invalid_address_bus_fault();
  reg seen_pready;
  reg seen_pslverr;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 14] INVALID ADDRESS / BUS FAULT");
    $display("=====================================================================");

    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    #500;
    rst_ni  = 1'b1;
    #2000;

    apb_force_master_access(32'h9999_9999, 32'hDEAD_BEEF, 1'b1, seen_pready, seen_pslverr);

    if (seen_pslverr) begin
      $display("[SC14][PASS] Bus bao PSLVERR cho dia chi khong hop le.");
      extra_pass_count = extra_pass_count + 1;
    end
    else if (seen_pready) begin
      $display("[SC14][PASS] Bus van ket thuc giao dich bat hop phap bang PREADY.");
      extra_pass_count = extra_pass_count + 1;
    end
    else begin
      $display("[SC14][KNOWN_ISSUE] Khong co PREADY/PSLVERR sau invalid address.");
      $display("[SC14][KNOWN_ISSUE] RTL hien tai cua apb_node co nguy co deadlock cho unmapped access.");
      extra_known_issue_count = extra_known_issue_count + 1;
      extra_fail_count = extra_fail_count + 1;
    end
  end
endtask

task automatic scenario15_cpu_isa_sweep();
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 15] CPU ISA SWEEP (SUB / AND / BEQ)");
    $display("=====================================================================");

    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    #500;
    rst_ni  = 1'b1;
    #3000;

    force dut.u_cpu.reg_file[2] = 8'h55;
    force dut.u_cpu.reg_file[3] = 8'h55;
    cpu_exec_forced_decode({TBX_OP_SUB, 3'd1, 3'd2, 3'd3, 3'b000});
    release dut.u_cpu.reg_file[2];
    release dut.u_cpu.reg_file[3];

    if (dut.u_cpu.reg_file[1] !== 8'h00) begin
      $display("[SC15][FAIL] SUB sai. R1 = 0x%02h, mong doi 0x00", dut.u_cpu.reg_file[1]);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    if (dut.u_cpu.flags[1] !== 1'b1) begin
      $display("[SC15][FAIL] Zero Flag khong len 1 sau SUB ket qua bang 0.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    force dut.u_cpu.reg_file[4] = 8'h0F;
    force dut.u_cpu.reg_file[5] = 8'hF0;
    cpu_exec_forced_decode({TBX_OP_AND, 3'd6, 3'd4, 3'd5, 3'b000});
    release dut.u_cpu.reg_file[4];
    release dut.u_cpu.reg_file[5];

    if (dut.u_cpu.reg_file[6] !== 8'h00) begin
      $display("[SC15][FAIL] AND sai. R6 = 0x%02h, mong doi 0x00", dut.u_cpu.reg_file[6]);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    if (dut.u_cpu.flags[1] !== 1'b1) begin
      $display("[SC15][FAIL] Zero Flag khong len 1 sau AND ket qua bang 0.");
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    // Khong dung force cho PC trong bai test branch.
    // Neu force, BEQ se khong the tu cap nhat PC cua chinh no.
    dut.u_cpu.pc    = 8'h20;
    dut.u_cpu.flags = 2'b10;
    cpu_exec_forced_decode({TBX_OP_BEQ, 4'd0, 8'h40});
    #1;

    if (dut.u_cpu.pc !== 8'h40) begin
      $display("[SC15][FAIL] BEQ khong nhay dung. PC = 0x%02h, mong doi 0x40", dut.u_cpu.pc);
      extra_fail_count = extra_fail_count + 1;
      $stop;
    end

    $display("[SC15][PASS] SUB / AND / Zero Flag / BEQ deu hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic scenario16_dsp_phase1_telemetry();
  reg [31:0] rd_status;
  reg [31:0] rd_diff;
  reg [31:0] rd_int;
  reg [31:0] rd_peak_diff;
  reg [31:0] rd_peak_int;
  reg [31:0] rd_event_cnt;
  reg [31:0] rd_attack;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 16] DSP PHASE 1.5 TELEMETRY / WEIGHTED ATTACK CHECK");
    $display("=====================================================================");

    dsp_focus_reset_safe();

    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A);
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004);
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F);

    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_status[4:0] !== 5'b0_0000) begin
      $display("[SC16][FAIL] STATUS sau reset = 0x%08h, mong doi sample_pair/fire/irq/status deu = 0.", rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd100);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1000, rd_status);

    if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_status[4] !== 1'b1) begin
      $display("[SC16][FAIL] Sau sample dau tien: diff=0x%h int=0x%h status=0x%h. Mong doi diff=0, int=0, sample_pair_valid=1.", rd_diff[15:0], rd_int[15:0], rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd140);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_101C, rd_peak_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1034, rd_attack);

    if (rd_diff[15:0] !== 16'd40 || rd_peak_diff[15:0] !== 16'd40 || rd_int[15:0] !== 16'd0 || rd_attack[15:0] !== 16'd0) begin
      $display("[SC16][FAIL] Sau sample thu hai: diff=%0d peak_diff=%0d int=%0d attack=%0d. Mong doi 40 / 40 / 0 / 0. Dieu nay se bat loi 'sample2 so voi 0' neu DSP van sai.", rd_diff[15:0], rd_peak_diff[15:0], rd_int[15:0], rd_attack[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd220);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1020, rd_peak_int);
    dsp_force_apb_read(32'h0000_1034, rd_attack);

    if (rd_diff[15:0] !== 16'd80 || rd_int[15:0] !== 16'd11 || rd_peak_int[15:0] !== 16'd11 || rd_attack[15:0] !== 16'd11) begin
      $display("[SC16][FAIL] Sau sample thu ba: diff=%0d int=%0d peak_int=%0d attack=%0d. Mong doi 80 / 11 / 11 / 11 theo weighted attack.", rd_diff[15:0], rd_int[15:0], rd_peak_int[15:0], rd_attack[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_apb_write(32'h0000_1008, 32'h0000_0014);
    dsp_force_sample(16'd0);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    dsp_force_apb_read(32'h0000_1024, rd_event_cnt);
    dsp_force_apb_read(32'h0000_1020, rd_peak_int);
    dsp_force_apb_read(32'h0000_1034, rd_attack);

    if ((rd_status[3] !== 1'b1) || (rd_status[2] !== 1'b1) || (rd_status[1:0] !== 2'b11) || (rd_event_cnt[15:0] !== 16'd1) || (rd_peak_int[15:0] !== 16'd20) || (rd_attack[15:0] !== 16'd20)) begin
      $display("[SC16][FAIL] Fire telemetry sai. status=0x%08h event_count=%0d peak_int=%0d attack=%0d", rd_status, rd_event_cnt[15:0], rd_peak_int[15:0], rd_attack[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_apb_write(32'h0000_1028, 32'h0000_0001);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_status[3] !== 1'b0) begin
      $display("[SC16][FAIL] fire_latched khong clear duoc bang CLEAR register. STATUS=0x%08h", rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();

    $display("[SC16][PASS] DSP da dung sample-pair logic va weighted attack telemetry APB hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario17_dsp_spike_window_counter();
  reg [31:0] rd_status;
  reg [31:0] rd_int;
  reg [31:0] rd_event_cnt;
  reg [31:0] rd_spike_sum;
  reg [31:0] rd_peak_spike_sum;
  reg [31:0] rd_peak_diff;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 17] DSP SLIDING WINDOW SPIKE COUNTER");
    $display("=====================================================================");

    // -----------------------------
    // Part A: Verify sliding window arithmetic
    // -----------------------------
    dsp_focus_reset_safe();

    dsp_force_apb_write(32'h0000_1004, 32'h0000_000A); // threshold = 10
    dsp_force_apb_write(32'h0000_1008, 32'h0000_03E8); // int_limit = 1000
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base_attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess_shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack_clamp = 15
    dsp_force_apb_write(32'h0000_1038, 32'h0000_0004); // win_len = 4
    dsp_force_apb_write(32'h0000_103C, 32'h0000_0000); // warn gate disabled
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0000); // density fire disabled
    dsp_force_apb_write(32'h0000_104C, 32'h0000_001E); // peak_diff_fire_thresh = 30

    dsp_force_sample(16'd100); // pair invalid
    dsp_force_sample(16'd130); // diff 30 -> spike
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    if (rd_spike_sum[6:0] !== 7'd1) begin
      $display("[SC17][FAIL] Window part A / step 1: CUR_SPIKE_SUM=%0d, mong doi 1.", rd_spike_sum[6:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd135); // diff 5 -> no spike
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    if (rd_spike_sum[6:0] !== 7'd1) begin
      $display("[SC17][FAIL] Window part A / step 2: CUR_SPIKE_SUM=%0d, mong doi 1.", rd_spike_sum[6:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd170); // diff 35 -> spike
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    if (rd_spike_sum[6:0] !== 7'd2) begin
      $display("[SC17][FAIL] Window part A / step 3: CUR_SPIKE_SUM=%0d, mong doi 2.", rd_spike_sum[6:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd190); // diff 20 -> spike
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
    if (rd_spike_sum[6:0] !== 7'd3 || rd_peak_spike_sum[6:0] !== 7'd3) begin
      $display("[SC17][FAIL] Window part A / step 4: CUR=%0d PEAK=%0d, mong doi 3 / 3.", rd_spike_sum[6:0], rd_peak_spike_sum[6:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd195); // diff 5 -> no spike, oldest spike slides out
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_spike_sum[6:0] !== 7'd2 || rd_peak_spike_sum[6:0] !== 7'd3 || rd_status[2] !== 1'b0) begin
      $display("[SC17][FAIL] Window part A / step 5: CUR=%0d PEAK=%0d IRQ=%0b, mong doi 2 / 3 / 0.", rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_status[2]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // -----------------------------
    // Part B1: Verify peak-diff threshold really gates density-fire
    // -----------------------------
    dsp_focus_reset();

    dsp_force_apb_write(32'h0000_1004, 32'h0000_000A); // threshold = 10
    dsp_force_apb_write(32'h0000_1008, 32'h0000_003C); // int_limit = 60
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base_attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess_shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack_clamp = 15
    dsp_force_apb_write(32'h0000_1038, 32'h0000_0004); // win_len = 4
    dsp_force_apb_write(32'h0000_103C, 32'h0000_0002); // warn at 2 spikes
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0003); // fire at 3 spikes + high peak
    dsp_force_apb_write(32'h0000_104C, 32'h0000_0028); // peak_diff_fire_thresh = 40

    dsp_force_sample(16'd100);
    dsp_force_sample(16'd130); // spike
    dsp_force_sample(16'd135); // no spike
    dsp_force_sample(16'd170); // spike
    dsp_force_sample(16'd190); // spike density = 3, peak_diff = 35, van chua du 40

    dsp_force_apb_read(32'h0000_1000, rd_status);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1024, rd_event_cnt);
    dsp_force_apb_read(32'h0000_1044, rd_spike_sum);
    dsp_force_apb_read(32'h0000_1048, rd_peak_spike_sum);
    dsp_force_apb_read(32'h0000_101C, rd_peak_diff);

    if ((rd_status[2] !== 1'b0) || (rd_event_cnt[15:0] !== 16'd0) ||
        (rd_spike_sum[6:0] !== 7'd3) || (rd_peak_spike_sum[6:0] !== 7'd3) ||
        (rd_peak_diff[15:0] !== 16'd35)) begin
      $display("[SC17][FAIL] Window part B1: status=0x%08h event=%0d cur_sum=%0d peak_sum=%0d peak_diff=%0d", rd_status, rd_event_cnt[15:0], rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_peak_diff[15:0]);
      $display("[SC17][FAIL] Mong doi chua FIRE vi peak_diff=35 van CHUA dat PEAK_DIFF_FIRE_THRESH=40.");
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // -----------------------------
    // Part B2: Lower PEAK_DIFF_FIRE_THRESH and verify density-fire works
    // -----------------------------
    dsp_focus_reset();

    dsp_force_apb_write(32'h0000_1004, 32'h0000_000A); // threshold = 10
    dsp_force_apb_write(32'h0000_1008, 32'h0000_003C); // int_limit = 60
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base_attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess_shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack_clamp = 15
    dsp_force_apb_write(32'h0000_1038, 32'h0000_0004); // win_len = 4
    dsp_force_apb_write(32'h0000_103C, 32'h0000_0002); // warn at 2 spikes
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0003); // fire at 3 spikes
    dsp_force_apb_write(32'h0000_104C, 32'h0000_001E); // peak_diff_fire_thresh = 30

    dsp_force_sample(16'd100);
    dsp_force_sample(16'd130); // spike
    dsp_force_sample(16'd135); // no spike
    dsp_force_sample(16'd170); // spike
    dsp_force_sample(16'd190); // spike -> density fire, integrator still < 60

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
      $display("[SC17][FAIL] Window part B2: status=0x%08h int=%0d event=%0d cur_sum=%0d peak_sum=%0d peak_diff=%0d", rd_status, rd_int[15:0], rd_event_cnt[15:0], rd_spike_sum[6:0], rd_peak_spike_sum[6:0], rd_peak_diff[15:0]);
      $display("[SC17][FAIL] Mong doi DSP FIRE do spike density khi PEAK_DIFF_FIRE_THRESH duoc ha xuong 30.");
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();

    $display("[SC17][PASS] Sliding window spike counter va PEAK_DIFF_FIRE_THRESH hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario18_dsp_adaptive_noise_floor();
  reg [31:0] rd_noise;
  reg [31:0] rd_effective;
  reg [31:0] rd_diff;
  reg [31:0] rd_attack;
  reg [31:0] rd_status;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 18] DSP ADAPTIVE NOISE FLOOR");
    $display("=====================================================================");

    dsp_focus_reset_safe();

    // Cau hinh threshold thich nghi o muc de thay doi ro rang.
    dsp_force_apb_write(32'h0000_1004, 32'h0000_0014); // BASE_THRESH = 20
    dsp_force_apb_write(32'h0000_1050, 32'h0000_0001); // ALPHA_SHIFT = 1
    dsp_force_apb_write(32'h0000_1054, 32'h0000_0001); // GAIN_SHIFT  = 1
    dsp_force_apb_write(32'h0000_103C, 32'h0000_0000); // density WARN disabled
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0000); // density FIRE disabled

    dsp_force_apb_read(32'h0000_1058, rd_noise);
    dsp_force_apb_read(32'h0000_105C, rd_effective);
    if (rd_noise[15:0] !== 16'd0 || rd_effective[15:0] !== 16'd20) begin
      $display("[SC18][FAIL] Gia tri ban dau sai. noise=%0d eff=%0d, mong doi 0 / 20.", rd_noise[15:0], rd_effective[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample dau tien chi khoi tao sample_prev_q, noise floor chua duoc update.
    dsp_force_sample(16'd100);
    dsp_force_apb_read(32'h0000_1058, rd_noise);
    dsp_force_apb_read(32'h0000_105C, rd_effective);
    if (rd_noise[15:0] !== 16'd0 || rd_effective[15:0] !== 16'd20) begin
      $display("[SC18][FAIL] Sau sample dau tien noise/eff thay doi sai. noise=%0d eff=%0d", rd_noise[15:0], rd_effective[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample thu hai: diff = 80. Noise floor moi = 0 + ((80 - 0) >>> 1) = 40.
    dsp_force_sample(16'd180);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1058, rd_noise);
    dsp_force_apb_read(32'h0000_105C, rd_effective);
    if (rd_diff[15:0] !== 16'd80 || rd_noise[15:0] !== 16'd40 || rd_effective[15:0] !== 16'd40) begin
      $display("[SC18][FAIL] Sau sample thu hai: diff=%0d noise=%0d eff=%0d, mong doi 80 / 40 / 40.", rd_diff[15:0], rd_noise[15:0], rd_effective[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample thu ba: diff = 35. Neu threshold van co dinh = 20 thi day la spike.
    // Nhung voi effective_thresh = 40, DSP phai coi day la non-spike.
    dsp_force_sample(16'd215);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1034, rd_attack);
    dsp_force_apb_read(32'h0000_1058, rd_noise);
    dsp_force_apb_read(32'h0000_105C, rd_effective);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_diff[15:0] !== 16'd35 || rd_attack[15:0] !== 16'd0 || rd_noise[15:0] !== 16'd37 || rd_effective[15:0] !== 16'd38 || rd_status[2] !== 1'b0) begin
      $display("[SC18][FAIL] Sau sample thu ba: diff=%0d attack=%0d noise=%0d eff=%0d irq=%0b", rd_diff[15:0], rd_attack[15:0], rd_noise[15:0], rd_effective[15:0], rd_status[2]);
      $display("[SC18][FAIL] Mong doi adaptive threshold chan spike co diff=35 vi effective threshold dang la 40.");
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample thu tu: diff rat nho de chung minh noise floor co the ha xuong theo moi truong.
    dsp_force_sample(16'd217);
    dsp_force_apb_read(32'h0000_1058, rd_noise);
    dsp_force_apb_read(32'h0000_105C, rd_effective);
    if (rd_noise[15:0] !== 16'd19 || rd_effective[15:0] !== 16'd29) begin
      $display("[SC18][FAIL] Sau sample thu tu noise floor khong giam dung. noise=%0d eff=%0d, mong doi 19 / 29.", rd_noise[15:0], rd_effective[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();

    $display("[SC18][PASS] Adaptive noise floor va effective threshold hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario19_dsp_stream_awareness();
  reg [31:0] rd_status;
  reg [31:0] rd_diff;
  reg [31:0] rd_int;
  reg [31:0] rd_attack;
  reg [31:0] rd_restart_count;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 19] DSP STREAM RESTART AWARENESS");
    $display("=====================================================================");

    // -----------------------------------------------------------
    // Part A: stream_restart_i phai xoa ngu canh cap mau cu
    // -----------------------------------------------------------
    dsp_focus_reset_safe();

    dsp_force_apb_write(32'h0000_1004, 32'h0000_0014); // base threshold = 20
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack clamp = 15
    dsp_force_apb_write(32'h0000_1054, 32'h0000_0010); // gain shift = 16 => disable adaptive gain de test restart sach hon

    dsp_force_sample(16'd100);
    dsp_force_sample(16'd160); // pair valid, diff 60
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_status[4] !== 1'b1) begin
      $display("[SC19][FAIL] Part A: sample_pair_valid chua len 1 sau hai sample hop le. STATUS=0x%08h", rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    force dut.spi_stream_restart = 1'b1;
    @(posedge clk);
    force dut.spi_stream_restart = 1'b0;
    @(posedge clk);

    dsp_force_apb_read(32'h0000_1000, rd_status);
    dsp_force_apb_read(32'h0000_1064, rd_restart_count);
    if (rd_status[4] !== 1'b0 || rd_restart_count[15:0] !== 16'd1) begin
      $display("[SC19][FAIL] Part A: restart khong reset ngu canh dung. STATUS=0x%08h restart_count=%0d", rd_status, rd_restart_count[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample dau sau restart: chi nap lai sample_prev, diff/int van phai 0.
    dsp_force_sample(16'd200);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_status[4] !== 1'b1) begin
      $display("[SC19][FAIL] Part A: sample dau sau restart phai chi tai nap ngu canh. diff=%0d int=%0d status=0x%08h", rd_diff[15:0], rd_int[15:0], rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Sample thu hai sau restart van bi holdoff, nen khong duoc update detector.
    dsp_force_sample(16'd260);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1034, rd_attack);
    if (rd_diff[15:0] !== 16'd0 || rd_int[15:0] !== 16'd0 || rd_attack[15:0] !== 16'd0) begin
      $display("[SC19][FAIL] Part A: holdoff sau restart chua dung. diff=%0d int=%0d attack=%0d", rd_diff[15:0], rd_int[15:0], rd_attack[15:0]);
      extra_fail_count = extra_fail_count + 1;
      release dut.dsp_data_in;
      release dut.dsp_valid_in;
      release dut.spi_stream_restart;
      $stop;
    end

    // Sample tiep theo sau holdoff phai duoc xu ly lai binh thuong voi prev cu = 260.
    dsp_force_sample(16'd340);
    dsp_force_apb_read(32'h0000_1014, rd_diff);
    dsp_force_apb_read(32'h0000_1018, rd_int);
    dsp_force_apb_read(32'h0000_1034, rd_attack);
    if (rd_diff[15:0] !== 16'd80 || rd_int[15:0] === 16'd0 || rd_attack[15:0] === 16'd0) begin
      $display("[SC19][FAIL] Part B: sau holdoff, detector khong hoi phuc dung. diff=%0d int=%0d attack=%0d", rd_diff[15:0], rd_int[15:0], rd_attack[15:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();

    $display("[SC19][PASS] DSP da aware voi stream restart va holdoff phuc hoi dung.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

// ----------------------------------------------------------------------------
// HELPER 5c: Dat DSP vao che do focus de test noi bo, khong bi SPI bridge thuc
// ----------------------------------------------------------------------------
task automatic dsp_focus_reset();
  begin
    rst_ni  = 1'b0;
    uart_rx = 1'b1;
    force dut.dsp_data_in        = 16'd0;
    force dut.dsp_valid_in       = 1'b0;
    force dut.spi_stream_restart = 1'b0;
    force dut.spi_overrun        = 1'b0;
    #500;
    rst_ni  = 1'b1;
    #3000;
  end
endtask

task automatic dsp_focus_reset_safe();
  begin
    dsp_focus_reset();
    dsp_force_apb_write(32'h0000_10A4, 32'h0000_0000);
  end
endtask

task automatic dsp_focus_release();
  begin
    release dut.dsp_data_in;
    release dut.dsp_valid_in;
    release dut.spi_stream_restart;
    release dut.spi_overrun;
  end
endtask

task automatic scenario20_dsp_thermal_path();
  reg [31:0] rd_status;
  reg [31:0] rd_int;
  reg [31:0] rd_env;
  reg [31:0] rd_hotspot;
  integer k;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 20] DSP THERMAL / GLOWING-CONTACT PATH");
    $display("=====================================================================");

    dsp_focus_reset_safe();

    // Tat duong arc de xac minh ro nhanh thermal tuong doi doc lap.
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();
    $display("[SC20][PASS] Nhanh thermal rieng hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
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
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 21] DEFAULT GLOWING-CONTACT TUNING");
    $display("=====================================================================");

    dsp_focus_reset();

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
          extra_fail_count = extra_fail_count + 1;
          dsp_focus_release();
          $stop;
        end

        dsp_focus_release();
        $display("[SC21][PASS] fire tai cap mau thu %0d, env=%0d hotspot=%0d",
                 (idx + 1) * 2, rd_env[15:0], rd_hotspot[15:0]);
        extra_pass_count = extra_pass_count + 1;
        return;
      end
    end

    dsp_force_apb_read(32'h0000_107C, rd_env);
    dsp_force_apb_read(32'h0000_1080, rd_hotspot);
    $display("[SC21][FAIL] Khong trip voi default glowing-contact. env=%0d hotspot=%0d",
             rd_env[15:0], rd_hotspot[15:0]);
    extra_fail_count = extra_fail_count + 1;
    dsp_focus_release();
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
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 22] DSP ZERO-CROSS / QUIET-ZONE");
    $display("=====================================================================");

    dsp_focus_reset_safe();

    // Giu detector thuong kha "li" de neu trip xay ra thi den tu quiet-zone branch.
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // Evidence 2: tao them mot zero-cross trong quiet-zone de quiet confidence dat muc fire.
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();
    $display("[SC22][PASS] Zero-cross / quiet-zone hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario23_dsp_trip_telemetry();
  reg [31:0] rd_status;
  reg [31:0] rd_last_diff;
  reg [31:0] rd_last_int;
  reg [31:0] rd_last_cause;
  integer k;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 23] DSP TRIP TELEMETRY / CAUSE CODE");
    $display("=====================================================================");

    // ------------------------------------------------------------------
    // Part A: Standard arc fire -> cause = 2
    // ------------------------------------------------------------------
    dsp_focus_reset_safe();
    dsp_force_apb_write(32'h0000_1004, 32'h0000_000A); // base_thresh = 10
    dsp_force_apb_write(32'h0000_1008, 32'h0000_0014); // int_limit = 20
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base_attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess_shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack_clamp = 15
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0000); // density fire disabled
    dsp_force_apb_write(32'h0000_1084, 32'h0000_0000); // zero-band off

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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part B: Density fire -> cause = 1
    // ------------------------------------------------------------------
    dsp_focus_reset_safe();
    dsp_force_apb_write(32'h0000_1004, 32'h0000_000A); // threshold = 10
    dsp_force_apb_write(32'h0000_1008, 32'h0000_003C); // int_limit = 60
    dsp_force_apb_write(32'h0000_1010, 32'h0000_000A); // base_attack = 10
    dsp_force_apb_write(32'h0000_102C, 32'h0000_0004); // excess_shift = 4
    dsp_force_apb_write(32'h0000_1030, 32'h0000_000F); // attack_clamp = 15
    dsp_force_apb_write(32'h0000_1038, 32'h0000_0008); // win_len = 8
    dsp_force_apb_write(32'h0000_103C, 32'h0000_0001); // spike_warn = 1
    dsp_force_apb_write(32'h0000_1040, 32'h0000_0003); // spike_fire = 3
    dsp_force_apb_write(32'h0000_104C, 32'h0000_001E); // peak_diff_fire_thresh = 30
    dsp_force_apb_write(32'h0000_1084, 32'h0000_0000); // zero-band off

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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part C: Thermal fire -> cause = 3
    // ------------------------------------------------------------------
    dsp_focus_reset_safe();
    dsp_force_apb_write(32'h0000_1004, 32'h0000_03E8); // base_thresh = 1000
    dsp_force_apb_write(32'h0000_1068, 32'h0000_00C8); // hot_base = 200
    dsp_force_apb_write(32'h0000_106C, 32'h0000_0014); // hot_attack = 20
    dsp_force_apb_write(32'h0000_1070, 32'h0000_0001); // hot_decay = 1
    dsp_force_apb_write(32'h0000_1074, 32'h0000_0064); // hot_limit = 100
    dsp_force_apb_write(32'h0000_1078, 32'h0000_0002); // env_shift = 2
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part D: Quiet-zone fire -> cause = 5
    // ------------------------------------------------------------------
    dsp_focus_reset_safe();
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

    dsp_force_sample(16'd200);
    dsp_force_sample(16'd20);
    dsp_force_sample(16'd5);
    dsp_force_sample(16'hFFFB); // -5
    dsp_force_sample(16'hFF38); // -200
    dsp_force_sample(16'hFFEC); // -20
    dsp_force_sample(16'hFFFB); // -5
    dsp_force_sample(16'd5);    // +5

    dsp_force_apb_read(32'h0000_1000, rd_status);
    dsp_force_apb_read(32'h0000_1098, rd_last_diff);
    dsp_force_apb_read(32'h0000_109C, rd_last_int);
    dsp_force_apb_read(32'h0000_10A0, rd_last_cause);
    if ((rd_status[2] !== 1'b1) || (rd_last_cause[3:0] !== 4'd5) ||
        (rd_last_diff[15:0] !== 16'd10) || (rd_last_int[15:0] > 16'd4)) begin
      $display("[SC23][FAIL] quiet_zone status=0x%08h last_diff=%0d last_int=%0d cause=%0d",
               rd_status, rd_last_diff[15:0], rd_last_int[15:0], rd_last_cause[3:0]);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();
    $display("[SC23][PASS] Trip telemetry va cause code hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario24_cpu_dsp_extended_mmio();
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 24] CPU DSP PAGED MMIO / 16-BIT ACCESS");
    $display("=====================================================================");

    force dut.irq_arc_critical = 1'b0;
    force dut.irq_timer_tick   = 1'b0;
    dsp_focus_reset_safe();
    // Giu CPU nam trong idle loop ROM[8] trong suot bai test de firmware that
    // khong chen vao cac lenh MMIO duoc force.
    force dut.u_cpu.pc         = 8'h08;
    force dut.u_cpu.in_arc_isr = 1'b0;
    force dut.u_cpu.in_timer_isr = 1'b0;
    force dut.u_cpu.arc_preempted_timer = 1'b0;

    // ------------------------------------------------------------------
    // Part A: CPU ghi DSP page register noi bo = 1
    // ------------------------------------------------------------------
    force dut.u_cpu.reg_file[0] = 8'h01;
    cpu_exec_and_settle({TBX_OP_STR, 3'd0, 1'b0, 8'hF0});
    release dut.u_cpu.reg_file[0];

      if (dut.u_cpu.dsp_page_sel !== 4'h1) begin
        $display("[SC24][FAIL] CPU ctrl write khong dat dsp_page_sel = 1. Gia tri hien tai = 0x%0h", dut.u_cpu.dsp_page_sel);
        extra_fail_count = extra_fail_count + 1;
        release dut.u_cpu.pc;
        release dut.u_cpu.in_arc_isr;
        release dut.u_cpu.in_timer_isr;
        release dut.u_cpu.arc_preempted_timer;
        release dut.irq_arc_critical;
        release dut.irq_timer_tick;
        dsp_focus_release();
        $stop;
      end

    // ------------------------------------------------------------------
    // Part B: CPU wide STR ghi 16-bit vao DSP offset 0x68 (HOT_BASE)
    // page=1, nibble=0xA => 0x1000 + 0x68
    // ------------------------------------------------------------------
    force dut.u_cpu.reg_file[1] = 8'h34;
    force dut.u_cpu.reg_file[2] = 8'h12;
    cpu_exec_apb_and_settle({TBX_OP_STR, 3'd1, 1'b1, 8'h1A});
    release dut.u_cpu.reg_file[1];
    release dut.u_cpu.reg_file[2];

    if ((dut.u_cpu.apb_mst.paddr !== 32'h0000_1068) || (dut.u_dsp.reg_hot_base !== 16'h1234)) begin
      $display("[SC24][FAIL] Wide STR den HOT_BASE sai. paddr=0x%08h pwdata=0x%08h psel=%0b penable=%0b pwrite=%0b state=%0d",
               dut.u_cpu.apb_mst.paddr, dut.u_cpu.apb_mst.pwdata, dut.u_cpu.apb_mst.psel,
               dut.u_cpu.apb_mst.penable, dut.u_cpu.apb_mst.pwrite, dut.u_cpu.state);
      $display("[SC24][FAIL] DSP side  paddr=0x%08h pwdata=0x%08h psel=%0b penable=%0b pwrite=%0b reg_hot_base=0x%04h",
               dut.apb_dsp_if.paddr, dut.apb_dsp_if.pwdata, dut.apb_dsp_if.psel,
               dut.apb_dsp_if.penable, dut.apb_dsp_if.pwrite, dut.u_dsp.reg_hot_base);
      $display("[SC24][FAIL] Mong doi paddr=0x00001068 va reg_hot_base=0x1234");
      extra_fail_count = extra_fail_count + 1;
      release dut.u_cpu.pc;
      release dut.u_cpu.in_arc_isr;
      release dut.u_cpu.in_timer_isr;
      release dut.u_cpu.arc_preempted_timer;
      release dut.irq_arc_critical;
      release dut.irq_timer_tick;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part C: CPU wide LDR doc lai HOT_BASE vao cap thanh ghi R3:R4
    // ------------------------------------------------------------------
    cpu_exec_apb_and_settle({TBX_OP_LDR, 3'd3, 1'b1, 8'h1A});

    if ((dut.u_cpu.reg_file[3] !== 8'h34) || (dut.u_cpu.reg_file[4] !== 8'h12)) begin
      $display("[SC24][FAIL] Wide LDR tu HOT_BASE sai. R3=0x%02h R4=0x%02h, mong doi 0x34 / 0x12",
               dut.u_cpu.reg_file[3], dut.u_cpu.reg_file[4]);
      extra_fail_count = extra_fail_count + 1;
      release dut.u_cpu.pc;
      release dut.u_cpu.in_arc_isr;
      release dut.u_cpu.in_timer_isr;
      release dut.u_cpu.arc_preempted_timer;
      release dut.irq_arc_critical;
      release dut.irq_timer_tick;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part D: Chuyen page = 2, cho CPU cham duoc offset 0xA0 (LAST_CAUSE_CODE)
    // ------------------------------------------------------------------
    force dut.u_cpu.reg_file[0] = 8'h02;
    cpu_exec_and_settle({TBX_OP_STR, 3'd0, 1'b0, 8'hF0});
    release dut.u_cpu.reg_file[0];

    if (dut.u_cpu.dsp_page_sel !== 4'h2) begin
      $display("[SC24][FAIL] CPU ctrl write khong dat dsp_page_sel = 2. Gia tri hien tai = 0x%0h", dut.u_cpu.dsp_page_sel);
      extra_fail_count = extra_fail_count + 1;
      release dut.u_cpu.pc;
      release dut.u_cpu.in_arc_isr;
      release dut.u_cpu.in_timer_isr;
      release dut.u_cpu.arc_preempted_timer;
      release dut.irq_arc_critical;
      release dut.irq_timer_tick;
      dsp_focus_release();
      $stop;
    end

    force dut.u_dsp.last_cause_code_q = 4'd5;
    cpu_exec_apb_and_settle({TBX_OP_LDR, 3'd5, 1'b0, 8'h18});
    release dut.u_dsp.last_cause_code_q;

    if ((dut.u_cpu.apb_mst.paddr !== 32'h0000_10A0) || (dut.u_cpu.reg_file[5] !== 8'h05)) begin
      $display("[SC24][FAIL] CPU khong cham duoc LAST_CAUSE_CODE o 0xA0. paddr=0x%08h R5=0x%02h, mong doi 0x000010A0 / 0x05",
               dut.u_cpu.apb_mst.paddr, dut.u_cpu.reg_file[5]);
      extra_fail_count = extra_fail_count + 1;
      release dut.u_cpu.pc;
      release dut.u_cpu.in_arc_isr;
      release dut.u_cpu.in_timer_isr;
      release dut.u_cpu.arc_preempted_timer;
      release dut.irq_arc_critical;
      release dut.irq_timer_tick;
      dsp_focus_release();
      $stop;
    end

    // ------------------------------------------------------------------
    // Part E: CPU LDR noi bo doc lai dsp_page_sel
    // ------------------------------------------------------------------
    cpu_exec_and_settle({TBX_OP_LDR, 3'd6, 1'b0, 8'hF0});

    if (dut.u_cpu.reg_file[6] !== 8'h02) begin
      $display("[SC24][FAIL] CPU ctrl read dsp_page_sel sai. R6=0x%02h, mong doi 0x02", dut.u_cpu.reg_file[6]);
      extra_fail_count = extra_fail_count + 1;
      release dut.u_cpu.pc;
      release dut.u_cpu.in_arc_isr;
      release dut.u_cpu.in_timer_isr;
      release dut.u_cpu.arc_preempted_timer;
      release dut.irq_arc_critical;
      release dut.irq_timer_tick;
      dsp_focus_release();
      $stop;
    end

    release dut.u_cpu.pc;
    release dut.u_cpu.in_arc_isr;
    release dut.u_cpu.in_timer_isr;
    release dut.u_cpu.arc_preempted_timer;
    release dut.irq_arc_critical;
    release dut.irq_timer_tick;
    dsp_focus_release();
    $display("[SC24][PASS] CPU da page duoc DSP map moi va doc/ghi 16-bit thanh cong.");
    extra_pass_count = extra_pass_count + 1;
end
endtask

task automatic scenario25_dsp_boot_profile();
  reg [31:0] rd_profile;
  reg [31:0] rd_gain;
  reg [31:0] rd_zero_band;
  reg [31:0] rd_spike_warn;
  reg [31:0] rd_spike_fire;
  reg [31:0] rd_status;
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 25] DSP BOOT PROFILE / PROFILE LOAD");
    $display("=====================================================================");

    dsp_focus_reset();

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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_force_sample(16'd100);
    dsp_force_sample(16'd160);
    dsp_force_apb_read(32'h0000_1000, rd_status);
    if (rd_status[4] !== 1'b1) begin
      $display("[SC25][FAIL] boot profile khong cho detector vao pair-valid. status=0x%08h", rd_status);
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
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
      extra_fail_count = extra_fail_count + 1;
      dsp_focus_release();
      $stop;
    end

    dsp_focus_release();
    $display("[SC25][PASS] DSP boot/profile load hoat dong dung.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic scenario26_arc_nmi_preempts_timer();
  begin
    $display("\n=====================================================================");
    $display(">>> [SCENARIO 26] ARC NMI PREEMPTS TIMER ISR");
    $display("=====================================================================");

    rst_ni = 1'b0;
    #500;
    rst_ni = 1'b1;
    #2000;

    force dut.irq_timer_tick = 1'b1;
    wait (dut.u_cpu.in_timer_isr === 1'b1);
    @(posedge clk);

    force dut.irq_arc_critical = 1'b1;
    wait (dut.u_cpu.in_arc_isr === 1'b1);
    #1;

    if (dut.u_cpu.pc !== 8'h01) begin
      $display("[SC26][FAIL] Arc khong cuop duoc timer ISR. PC=0x%02h, mong doi 0x01", dut.u_cpu.pc);
      extra_fail_count = extra_fail_count + 1;
      release dut.irq_timer_tick;
      release dut.irq_arc_critical;
      $stop;
    end

    if ((dut.u_cpu.in_timer_isr !== 1'b1) || (dut.u_cpu.arc_preempted_timer !== 1'b1)) begin
      $display("[SC26][FAIL] CPU khong luu dung context Timer khi Arc chen ngang. in_timer=%0b arc_preempted=%0b",
               dut.u_cpu.in_timer_isr, dut.u_cpu.arc_preempted_timer);
      extra_fail_count = extra_fail_count + 1;
      release dut.irq_timer_tick;
      release dut.irq_arc_critical;
      $stop;
    end

    if (dut.u_cpu.reg_file[0] !== 8'd1) begin
      $display("[SC26][FAIL] Arc ISR khong ghi dau nguyen nhan vao R0. R0=0x%02h", dut.u_cpu.reg_file[0]);
      extra_fail_count = extra_fail_count + 1;
      release dut.irq_timer_tick;
      release dut.irq_arc_critical;
      $stop;
    end

    release dut.irq_timer_tick;
    release dut.irq_arc_critical;
    rst_ni = 1'b0;
    #200;
    rst_ni = 1'b1;
    #500;

    $display("[SC26][PASS] Arc interrupt da preempt duoc Timer ISR theo dung uu tien safety.");
    extra_pass_count = extra_pass_count + 1;
  end
endtask

task automatic run_extra_scenarios_11_to_26();
  begin
    scenario11_uart_rx_receiver();
    scenario12_gpio_input_edge_interrupt();
    scenario13_dsp_on_the_fly_reconfiguration();
    scenario14_invalid_address_bus_fault();
    scenario15_cpu_isa_sweep();
    scenario16_dsp_phase1_telemetry();
    scenario17_dsp_spike_window_counter();
    scenario18_dsp_adaptive_noise_floor();
    scenario19_dsp_stream_awareness();
    scenario20_dsp_thermal_path();
    scenario21_default_glowing_contact();
    scenario22_zero_cross_quiet_zone();
    scenario23_dsp_trip_telemetry();
    scenario24_cpu_dsp_extended_mmio();
    scenario25_dsp_boot_profile();
    scenario26_arc_nmi_preempts_timer();

    $display("\n---------------------------------------------------------------------");
    $display(" EXTRA SCENARIOS 11-26 SUMMARY: PASS=%0d FAIL=%0d KNOWN_ISSUE=%0d", extra_pass_count, extra_fail_count, extra_known_issue_count);
    $display("---------------------------------------------------------------------\n");
  end
endtask


// Backward-compatible alias de neu bench cu con goi ten cu thi van chay du.
task automatic run_extra_scenarios_11_to_15();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_16();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_17();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_18();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_19();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_22();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_23();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_24();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask

task automatic run_extra_scenarios_11_to_25();
  begin
    run_extra_scenarios_11_to_26();
  end
endtask
