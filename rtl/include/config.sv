`ifndef _CONFIG_SV_
`define _CONFIG_SV_

    // --- SYSTEM PARAMETERS ---
    localparam SYS_CLK_FREQ = 50_000_000;
    localparam UART_BAUD    = 115200;

    // --- BUS PARAMETERS (APB) ---
    localparam APB_ADDR_WIDTH = 32;
    localparam APB_DATA_WIDTH = 32;

    // --- MEMORY MAP (Mapping lại cho CPU 8-bit) ---
    // Trick: CPU 8-bit dùng Immediate 8-bit (0x00 - 0xFF).
    // Ta dùng 4 bit cao của Immediate để chọn thiết bị (Chip Select).
    
    `define RAM_BASE_ADDR   32'h0000_0000
    `define DSP_BASE_ADDR   32'h0000_1000
    `define GPIO_BASE_ADDR  32'h0000_2000
    `define UART_BASE_ADDR  32'h0000_3000
    `define TIMER_BASE_ADDR 32'h0000_4000
    `define WATCHDOG_BASE_ADDR 32'h0000_5000
    `define BIST_BASE_ADDR 32'h0000_6000
    `define SPI_BASE_ADDR  32'h0000_7000
    
`endif
