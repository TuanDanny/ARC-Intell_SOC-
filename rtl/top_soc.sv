// `include "D:/APP/Quatus_Workspace/In_SOC/rtl/include/apb_bus.sv"
// `include "D:/APP/Quatus_Workspace/In_SOC/rtl/include/config.sv"

`include "../include/config.sv"
`include "../include/apb_bus.sv"


module top_soc (
    // --- Clock & Reset Domain ---
    input  logic        clk_i,          // System Clock (50MHz)
    input  logic        rst_ni_async,   // External Reset (Active Low)

    // --- Analog Front-End Interface (SPI ADC) ---
    input  logic        adc_miso_i,    // Master In Slave Out
    output logic        adc_mosi_o, 
    output logic        adc_sclk_o,     // Serial Clock
    output logic        adc_csn_o,      // Chip Select

    // --- Communication Interface (UART) ---
    output logic        uart_tx_o,      // Transmit Data
    input  logic        uart_rx_i,      // Receive Data

    // --- Safety & Control I/O (GPIO) ---
    // [0]: Power Relay (Safety Critical)
    // [1]: Arc Fault Indicator (Red)
    // [2]: System Status (Green)
    // [3]: BIST Status (Yellow)
    inout wire [3:0] gpio_pin_io
);

    // =========================================================================
    // 1. SYSTEM INFRASTRUCTURE & SAFETY RESET
    // =========================================================================
    logic rst_no;           // Global Synchronized Reset
    logic wdt_reset_req;    // Request from Watchdog
    logic combined_rst_n;   // Combined Reset Source
    logic dsp_irq_raw_output; // Thêm dây này để kết nối trực tiếp với DSP IRQ, sau đó đưa vào BIST để kiểm tra phản hồi

    // Reset Multiplexer: External Button OR Watchdog Event
    assign combined_rst_n = rst_ni_async & ~wdt_reset_req;

    // Reset Synchronizer (Safe Startup)
    rstgen u_rstgen (
        .clk_i       (clk_i),
        .rst_ni      (combined_rst_n),
        .test_mode_i (1'b0),
        .rst_no      (rst_no),
        .init_no     ()
    );

    // =========================================================================
    // 2. BUS INTERCONNECT (AMBA APB v3.0)
    // =========================================================================
    // Slave Map:
    // [0] RAM   [1] DSP   [2] GPIO  [3] UART
    // [4] TIMER [5] WDT   [6] BIST
    localparam NB_SLAVE = 7;

    // Interconnect Signals
    logic [NB_SLAVE-1:0]        s_penable, s_pwrite, s_psel, s_pready, s_pslverr;
    logic [NB_SLAVE-1:0][31:0]  s_paddr, s_pwdata, s_prdata;
    logic [NB_SLAVE-1:0][31:0]  start_addr, end_addr;

    // Address Mapping (Aligned with cpu_8bit decoder)
    assign start_addr[0] = `RAM_BASE_ADDR;   assign end_addr[0] = `RAM_BASE_ADDR   + 32'h0FFF;
    assign start_addr[1] = `DSP_BASE_ADDR;   assign end_addr[1] = `DSP_BASE_ADDR   + 32'h0FFF;
    assign start_addr[2] = `GPIO_BASE_ADDR;  assign end_addr[2] = `GPIO_BASE_ADDR  + 32'h0FFF;
    assign start_addr[3] = `UART_BASE_ADDR;  assign end_addr[3] = `UART_BASE_ADDR  + 32'h0FFF;
    assign start_addr[4] = `TIMER_BASE_ADDR; assign end_addr[4] = `TIMER_BASE_ADDR + 32'h0FFF;
    assign start_addr[5] = `WATCHDOG_BASE_ADDR;    assign end_addr[5] = `WATCHDOG_BASE_ADDR + 32'h0FFF; // WDT
    assign start_addr[6] = `BIST_BASE_ADDR;    assign end_addr[6] = `BIST_BASE_ADDR + 32'h0FFF; // BIST

    // Master Interface from CPU
    APB_BUS apb_cpu_master();

    // Central Interconnect Node
    apb_node #(
        .NB_MASTER      (NB_SLAVE), // Library defined as output ports count
        .APB_ADDR_WIDTH (32),
        .APB_DATA_WIDTH (32)
    ) u_interconnect (
        // Master Side
        .paddr_i    (apb_cpu_master.paddr),
        .pwdata_i   (apb_cpu_master.pwdata),
        .pwrite_i   (apb_cpu_master.pwrite),
        .psel_i     (apb_cpu_master.psel),
        .penable_i  (apb_cpu_master.penable),
        .prdata_o   (apb_cpu_master.prdata),
        .pready_o   (apb_cpu_master.pready),
        .pslverr_o  (apb_cpu_master.pslverr),
        // Slave Side
        .paddr_o    (s_paddr),
        .pwdata_o   (s_pwdata),
        .pwrite_o   (s_pwrite),
        .psel_o     (s_psel),
        .penable_o  (s_penable),
        .prdata_i   (s_prdata),
        .pready_i   (s_pready),
        .pslverr_i  (s_pslverr),
        // Config
        .START_ADDR_i (start_addr),
        .END_ADDR_i   (end_addr)
    );

    // =========================================================================
    // 3. CENTRAL PROCESSING UNIT (CPU)
    // =========================================================================
    logic irq_arc_critical; // High Priority
    logic irq_timer_tick;   // Low Priority

    cpu_8bit #(
        .ROM_SIZE (256),
        .RAM_SIZE (128)
    ) u_cpu (
        .clk_i       (clk_i),
        .rst_ni      (rst_no),
        .irq_arc_i   (irq_arc_critical),
        .irq_timer_i (irq_timer_tick),
        .apb_mst     (apb_cpu_master)
    );

    // =========================================================================
    // 4. SIGNAL PROCESSING CHAIN (SPI + MUX + DSP)
    // =========================================================================
    
    // --- 4.1 SPI ADC Front-End (refactored) ---
    logic [15:0] spi_data_val;
    logic        spi_data_rdy;
    logic        spi_busy;
    logic        spi_frame_active;
    logic        spi_overrun;

    spi_adc_stream_rx #(
        .SAMPLE_WIDTH   (16),
        .CMD_WIDTH      (0),   // giữ giống luồng cũ: chỉ nhận data
        .DUMMY_CYCLES   (0),
        .SCLK_DIV       (2),   // gần nhất với clock divider cũ
        .CPOL           (1'b0),
        .CPHA           (1'b0),
        .MSB_FIRST      (1'b1),
        .PRE_CS_CYCLES  (1),
        .POST_CS_CYCLES (1),
        .CONTINUOUS     (1'b1)
    ) u_spi_adc_rx (
        .clk_i          (clk_i),
        .rst_ni         (rst_no),

        .enable_i       (1'b1),
        .start_i        (1'b0),

        .adc_miso_i     (adc_miso_i),
        .adc_mosi_o     (adc_mosi_o),
        .adc_sclk_o     (adc_sclk_o),
        .adc_csn_o      (adc_csn_o),

        .cmd_i          (1'b0),
        .sample_ready_i (1'b1),

        .sample_data_o  (spi_data_val),
        .sample_valid_o (spi_data_rdy),
        .busy_o         (spi_busy),
        .frame_active_o (spi_frame_active),
        .overrun_o      (spi_overrun)
    );

    // --- 4.2 BIST Multiplexer (Safety Injection) ---
    logic [15:0] dsp_data_in;
    logic        dsp_valid_in;
    logic [15:0] bist_data;
    logic        bist_valid;
    logic        bist_active_mode;

    // Nếu BIST đang chạy, ngắt kết nối ADC, đưa dữ liệu giả vào DSP
    assign dsp_data_in  = bist_active_mode ? bist_data  : spi_data_val;
    assign dsp_valid_in = bist_active_mode ? bist_valid : spi_data_rdy;


    // MUX CHE MẮT CPU (Bảo vệ CPU khi BIST chạy)
    assign irq_arc_critical = bist_active_mode ? 1'b0 : dsp_irq_raw_output;




    // --- 4.3 DSP Core (Arc Detection) ---
    // Wrapper: Wire -> APB Interface
    APB_BUS apb_dsp_if();
    assign apb_dsp_if.paddr   = s_paddr[1];
    assign apb_dsp_if.pwdata  = s_pwdata[1];
    assign apb_dsp_if.pwrite  = s_pwrite[1];
    assign apb_dsp_if.psel    = s_psel[1];
    assign apb_dsp_if.penable = s_penable[1];
    assign s_prdata[1]        = apb_dsp_if.prdata;
    assign s_pready[1]        = apb_dsp_if.pready;
    assign s_pslverr[1]       = apb_dsp_if.pslverr;

    dsp_arc_detect #(
        .DATA_WIDTH(16), .CNT_WIDTH(16)
    ) u_dsp (
        .clk_i       (clk_i),
        .rst_ni      (rst_no),
        .adc_data_i  (dsp_data_in),
        .adc_valid_i (dsp_valid_in), 
        .apb_slv     (apb_dsp_if),
        .irq_arc_o   (dsp_irq_raw_output) // NEW 
    );

    // =========================================================================
    // 5. PERIPHERALS INSTANTIATION
    // =========================================================================

    // --- SLAVE 0: INTERNAL SRAM ---
    logic [31:0] ram_mem [0:255];
    always_ff @(posedge clk_i) begin
        if (s_psel[0] && s_penable[0] && s_pwrite[0])
            ram_mem[s_paddr[0][9:2]] <= s_pwdata[0];
    end
    assign s_prdata[0] = ram_mem[s_paddr[0][9:2]];
    assign s_pready[0] = 1'b1;
    assign s_pslverr[0] = 1'b0;

    // --- SLAVE 2: GPIO (Relay Control) ---
    logic [31:0] gpio_out_wire, gpio_dir_wire;
    apb_gpio #(.APB_ADDR_WIDTH(12), .PAD_NUM(32)) u_gpio (
        .HCLK(clk_i), .HRESETn(rst_no),
        .PADDR(s_paddr[2][11:0]), .PWDATA(s_pwdata[2]), .PWRITE(s_pwrite[2]),
        .PSEL(s_psel[2]), .PENABLE(s_penable[2]), 
        .PRDATA(s_prdata[2]), .PREADY(s_pready[2]), .PSLVERR(s_pslverr[2]),
        .gpio_in(32'd0), .gpio_out(gpio_out_wire), .gpio_dir(gpio_dir_wire), .interrupt()
    );
    // Fail-Safe Output Logic
    assign gpio_pin_io[0]   = (!rst_no) ? 1'b0 : (gpio_dir_wire[0] ? gpio_out_wire[0] : 1'bz); // Relay
    assign gpio_pin_io[3:1] = gpio_dir_wire[3:1] ? gpio_out_wire[3:1] : 3'bz; // LEDs

    // --- SLAVE 3: UART (Debug) ---
    apb_uart_wrap u_uart (
        .clk_i(clk_i), .rst_ni(rst_no),
        .paddr_i(s_paddr[3]), .pwdata_i(s_pwdata[3]), .pwrite_i(s_pwrite[3]),
        .psel_i(s_psel[3]), .penable_i(s_penable[3]),
        .prdata_o(s_prdata[3]), .pready_o(s_pready[3]), .pslverr_o(s_pslverr[3]),
        .sout_o(uart_tx_o), .sin_i(uart_rx_i), .intr_o(), .cts_ni(1'b0)
    );



    logic [3:0] timer_events_wire;
    logic [3:0] timer_ch0_wire;
    logic [3:0] timer_ch1_wire;
    logic [3:0] timer_ch2_wire;
    logic [3:0] timer_ch3_wire;
    assign irq_timer_tick = timer_events_wire[3]; // Lấy bit cao nhất làm tín hiệu ngắt

    // --- SLAVE 4: TIMER ---
    apb_adv_timer #(.APB_ADDR_WIDTH(12)) u_timer (
        .HCLK      (clk_i),
        .HRESETn   (rst_no),
        .PADDR     (s_paddr[4][11:0]),
        .PWDATA    (s_pwdata[4]),
        .PWRITE    (s_pwrite[4]),
        .PSEL      (s_psel[4]),
        .PENABLE   (s_penable[4]),
        .PRDATA    (s_prdata[4]),
        .PREADY    (s_pready[4]),
        .PSLVERR   (s_pslverr[4]),
        .low_speed_clk_i (1'b0), 
        .dft_cg_enable_i (1'b0),
        .ext_sig_i       (32'd0),
        .events_o        (timer_events_wire),
        .ch_0_o         (timer_ch0_wire),
        .ch_1_o         (timer_ch1_wire),
        .ch_2_o         (timer_ch2_wire),
        .ch_3_o         (timer_ch3_wire)
    );

    // --- SLAVE 5: WATCHDOG TIMER (Safety) ---
    safety_watchdog #(.APB_ADDR_WIDTH(12)) u_wdt (
        .clk_i(clk_i), .rst_ni(rst_no),
        .paddr_i(s_paddr[5][11:0]), .pwdata_i(s_pwdata[5]), .pwrite_i(s_pwrite[5]),
        .psel_i(s_psel[5]), .penable_i(s_penable[5]),
        .prdata_o(s_prdata[5]), .pready_o(s_pready[5]), .pslverr_o(s_pslverr[5]),
        .wdt_reset_o(wdt_reset_req) // Connects back to Reset Generator
    );

    // --- SLAVE 6: LOGIC BIST (Self-Test) ---
    logic bist_done;
    logic [15:0] bist_sig_res; // Unused in top, readable via APB
    logic bist_dsp_irq_capture; 
    
    // Capture the DSP Interrupt for verification
    assign bist_dsp_irq_capture = dsp_irq_raw_output;

    logic_bist #(.APB_ADDR_WIDTH(12)) u_bist (
        .clk_i(clk_i), .rst_ni(rst_no),
        .paddr_i(s_paddr[6][11:0]), .pwdata_i(s_pwdata[6]), .pwrite_i(s_pwrite[6]),
        .psel_i(s_psel[6]), .penable_i(s_penable[6]),
        .prdata_o(s_prdata[6]), .pready_o(s_pready[6]), .pslverr_o(s_pslverr[6]),
        
        .bist_data_o(bist_data),
        .bist_valid_o(bist_valid),
        .bist_active_o(bist_active_mode),
        .dsp_irq_i(bist_dsp_irq_capture)
    );


endmodule
