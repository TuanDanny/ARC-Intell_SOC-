/*
 * Module: apb_uart_wrap
 * Description: Bộ điều khiển UART (Universal Asynchronous Receiver/Transmitter) hiệu năng cao.
 *              - Thiết kế hoàn toàn bằng SystemVerilog, không phụ thuộc thư viện ngoài.
 *              - Tích hợp giao diện APB Slave v3.0 chuẩn công nghiệp.
 *              - Cơ chế tạo Baudrate chính xác dựa trên bộ chia tần số (Frequency Divider).
 *              - Bộ thu (RX) có cơ chế đồng bộ hóa (Synchronizer) chống Metastability.
 *              - Bộ phát (TX) và thu (RX) hoạt động song song (Full Duplex).
 *
 * Register Map (32-bit aligned):
 *   0x00: DATA REGISTER (RW)
 *         - Write [7:0]: Gửi dữ liệu vào bộ đệm TX.
 *         - Read  [7:0]: Đọc dữ liệu từ bộ đệm RX.
 *   0x04: STATUS REGISTER (RO)
 *         - Bit [0]: TX Busy (1 = Đang gửi, 0 = Rảnh).
 *         - Bit [1]: RX Valid (1 = Có dữ liệu mới, 0 = Rỗng).
 *   0x08: DIVISOR REGISTER (RW)
 *         - Giá trị chia xung nhịp: Divisor = System_Clock / Baudrate.
 *         - Ví dụ: 50MHz / 115200 ≈ 434.
 */

module apb_uart_wrap #(
    parameter APB_ADDR_WIDTH = 32,
    parameter APB_DATA_WIDTH = 32
) (
    // --- Global Signals ---
    input  logic                      clk_i,      // System Clock
    input  logic                      rst_ni,     // Async Active-Low Reset

    // --- APB Slave Interface ---
    input  logic [APB_ADDR_WIDTH-1:0] paddr_i,
    input  logic [APB_DATA_WIDTH-1:0] pwdata_i,
    input  logic                      pwrite_i,
    input  logic                      psel_i,
    input  logic                      penable_i,
    output logic [APB_DATA_WIDTH-1:0] prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,

    // --- Physical UART Interface ---
    output logic                      sout_o,     // Serial Output (TX)
    input  logic                      sin_i,      // Serial Input  (RX)
    
    // --- Interrupts & Flow Control (Optional) ---
    output logic                      intr_o,     // Interrupt Output (Active High)
    input  logic                      cts_ni      // Clear To Send (Active Low) - Flow control
);

    // =========================================================================
    // 1. CONSTANTS & PARAMETERS
    // =========================================================================
    // Default Baudrate: 115200 @ 50MHz Clock => 434
    localparam [15:0] DEFAULT_DIVISOR = 16'd434;

    // States
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} uart_state_t;

    // =========================================================================
    // 2. INTERNAL REGISTERS & SIGNALS
    // =========================================================================
    // Configuration Registers
    logic [15:0] r_divisor;
    
    // Data Buffers
    logic [7:0]  r_tx_data;
    logic [7:0]  r_rx_data;
    
    // Status Flags
    logic        r_tx_busy;
    logic        r_rx_valid;
    logic        s_tx_start; // Pulse start signal
    
    // APB Decoding Signals
    logic        apb_write;
    logic        apb_read;
    logic [7:0]  addr_offset;

    // RX Synchronization
    logic        rx_sync_0, rx_sync_1;
	 logic 		  rx_done;

    // =========================================================================
    // 3. APB BUS INTERFACE LOGIC (Đã sửa lỗi rx_done)
    // =========================================================================
    assign addr_offset = paddr_i[7:0];
    assign apb_write   = psel_i & penable_i & pwrite_i;
    assign apb_read    = psel_i & !pwrite_i;

    assign pready_o    = 1'b1; 
    assign pslverr_o   = 1'b0; 
    assign intr_o      = r_rx_valid; 

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_divisor   <= DEFAULT_DIVISOR;
            r_tx_data   <= 8'd0;
            s_tx_start  <= 1'b0;
            r_rx_valid  <= 1'b0; 
            prdata_o    <= 32'd0;
        end else begin
            s_tx_start <= 1'b0; // Tự động xóa xung start

            // --- LOGIC QUAN TRỌNG MỚI THÊM ---
            // Nếu bộ thu báo xong (rx_done), lập tức bật cờ Valid
            if (rx_done) begin
                r_rx_valid <= 1'b1;
            end
            // Nếu CPU đọc thanh ghi Data (Offset 0x00), xóa cờ Valid
            else if (apb_read && (addr_offset == 8'h00)) begin
                r_rx_valid <= 1'b0; 
            end
            // ----------------------------------

            // Xử lý Ghi (Write)
            if (apb_write) begin
                case (addr_offset)
                    8'h00: begin 
                        r_tx_data  <= pwdata_i[7:0];
                        s_tx_start <= 1'b1; 
                    end
                    8'h08: r_divisor <= pwdata_i[15:0];
                    default: ;
                endcase
            end

            // Xử lý Đọc (Read)
            if (apb_read) begin
                case (addr_offset)
                    8'h00: prdata_o <= {24'd0, r_rx_data};
                    8'h04: prdata_o <= {30'd0, r_rx_valid, r_tx_busy};
                    8'h08: prdata_o <= {16'd0, r_divisor};
                    default: prdata_o <= 32'd0;
                endcase
            end
        end
    end
    // =========================================================================
    // 4. UART TRANSMITTER (TX) CORE
    // =========================================================================
    uart_state_t tx_state;
    logic [15:0] tx_clk_cnt;
    logic [2:0]  tx_bit_idx;
    logic [7:0]  tx_shifter;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_state   <= IDLE;
            r_tx_busy  <= 1'b0;
            sout_o     <= 1'b1; // Idle High
            tx_clk_cnt <= 16'd0;
            tx_bit_idx <= 3'd0;
            tx_shifter <= 8'd0;
        end else begin
            case (tx_state)
                IDLE: begin
                    sout_o    <= 1'b1;
                    r_tx_busy <= 1'b0;
                    if (s_tx_start) begin
                        tx_state   <= START;
                        tx_clk_cnt <= 16'd0;
                        tx_shifter <= r_tx_data; // Load Data
                        r_tx_busy  <= 1'b1;
                    end
                end

                START: begin
                    sout_o <= 1'b0; // Start Bit (Low)
                    if (tx_clk_cnt == r_divisor - 1) begin
                        tx_clk_cnt <= 16'd0;
                        tx_state   <= DATA;
                        tx_bit_idx <= 3'd0;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    sout_o <= tx_shifter[tx_bit_idx]; // LSB First
                    if (tx_clk_cnt == r_divisor - 1) begin
                        tx_clk_cnt <= 16'd0;
                        if (tx_bit_idx == 3'd7) begin
                            tx_state <= STOP;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1'b1;
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    sout_o <= 1'b1; // Stop Bit (High)
                    if (tx_clk_cnt == r_divisor - 1) begin
                        tx_state   <= IDLE;
                        r_tx_busy  <= 1'b0;
								tx_clk_cnt <= 16'd0;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1'b1;
                    end
                end
                
                default: tx_state <= IDLE;
            endcase
        end
    end

    // =========================================================================
    // 5. UART RECEIVER (RX) CORE
    // =========================================================================
    uart_state_t rx_state;
    logic [15:0] rx_clk_cnt;
    logic [2:0]  rx_bit_idx;
    logic [7:0]  rx_shifter;
    
    // RX Input Synchronizer (Double Flop - Chống nhiễu Metastability)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= sin_i;
            rx_sync_1 <= rx_sync_0;
        end
    end

    // Logic xử lý thu nhận tín hiệu Serial
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_state    <= IDLE;
            rx_clk_cnt  <= 16'd0;
            rx_bit_idx  <= 3'd0;
            rx_shifter  <= 8'd0;
            r_rx_data   <= 8'd0;
            rx_done     <= 1'b0; // Pulse tín hiệu báo nhận xong
        end else begin
            // Mặc định rx_done về 0 (tạo thành một nhịp xung 1-cycle)
            rx_done <= 1'b0;

            case (rx_state)
                IDLE: begin
                    // Phát hiện Start Bit (đường truyền chuyển từ High sang Low)
                    if (rx_sync_1 == 1'b0) begin
                        rx_state   <= START;
                        rx_clk_cnt <= 16'd0;
                    end
                end

                START: begin
                    // Đợi đến chính giữa Start bit để xác minh không phải nhiễu (Glitches)
                    if (rx_clk_cnt == (r_divisor >> 1)) begin
                        if (rx_sync_1 == 1'b0) begin
                            rx_clk_cnt <= 16'd0;
                            rx_state   <= DATA;
                            rx_bit_idx <= 3'd0;
                        end else begin
                            rx_state   <= IDLE; // Nếu là nhiễu, quay về Idle
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    // Đợi đủ thời gian một Baudrate để lấy mẫu từng bit
                    if (rx_clk_cnt == r_divisor - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_shifter[rx_bit_idx] <= rx_sync_1; // Lấy mẫu data
                        
                        if (rx_bit_idx == 3'd7) begin
                            rx_state <= STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 1'b1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    // Đợi chu kỳ Stop bit kết thúc
                    if (rx_clk_cnt == r_divisor - 1) begin
                        rx_state    <= IDLE;
                        r_rx_data   <= rx_shifter; // Nạp dữ liệu hoàn chỉnh vào đệm
                        rx_done     <= 1'b1;       // Phát xung kích hoạt Section 2 cập nhật cờ Valid
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                
                default: rx_state <= IDLE;
            endcase
            
        end
    end

endmodule