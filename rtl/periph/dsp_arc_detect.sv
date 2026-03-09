/*
 * Module: dsp_arc_detect
 * Description: Bộ xử lý tín hiệu số (DSP) chuyên dụng phát hiện hồ quang điện.
 *              - Thiết kế cấp độ công nghiệp (Production Grade).
 *              - Tối ưu hóa RTL không có Latch, không báo động giả (Glitch-free).
 *              - Xử lý toán học chính xác: Chống tràn số (Anti-overflow/Saturation).
 * Author: SIU-IC Design Team
 * Standards: APB v3.0 Slave, UL 1699 Algorithm.
 */

`include "../include/apb_bus.sv"

module dsp_arc_detect #(
    parameter DATA_WIDTH = 16,    // Độ rộng dữ liệu ADC (16-bit Signed)
    parameter CNT_WIDTH  = 16     // Độ rộng bộ đếm tích phân (16-bit Unsigned)
) (
    // --- Global Signals ---
    input  logic                   clk_i,
    input  logic                   rst_ni,    // Reset Active Low
    
    // --- Data Streaming Interface (From ADC Wrapper) ---
    input  logic [DATA_WIDTH-1:0]  adc_data_i,   // Dữ liệu mẫu (2's complement)
    input  logic                   adc_valid_i,  // Valid pulse (1 chu kỳ clock)
    
    // --- Control Plane (APB Slave) ---
    APB_BUS                        apb_slv,      // Interface kết nối CPU
    
    // --- Critical Output ---
    output logic                   irq_arc_o     // Tín hiệu ngắt báo cháy (Level High)
);

    // =========================================================================
    // 1. REGISTER FILE DEFINITION (MEMORY MAP)
    // =========================================================================
    /*
     * 0x00 (RO): STATUS        [1:0] 00:Safe, 01:Warn, 11:Fire
     * 0x04 (RW): DIFF_THRESH   [15:0] Ngưỡng biên độ vi phân
     * 0x08 (RW): INT_LIMIT     [15:0] Giới hạn tích lũy báo động
     * 0x0C (RW): DECAY_RATE    [7:0]  Tốc độ suy giảm (Leak)
     * 0x10 (RW): ATTACK_RATE   [7:0]  Tốc độ tích lũy lỗi
     */

    // Registers
    logic [15:0] reg_diff_threshold;
    logic [15:0] reg_int_limit;
    logic [7:0]  reg_decay_rate;
    logic [7:0]  reg_attack_rate;
    logic [1:0]  reg_status;

    // Reset Defaults (Safe defaults)
    localparam [15:0] DEFAULT_THRESH = 16'd50;
    localparam [15:0] DEFAULT_LIMIT  = 16'd1000;
    localparam [7:0]  DEFAULT_DECAY  = 8'd1;
    localparam [7:0]  DEFAULT_ATTACK = 8'd10;

    // =========================================================================
    // 2. APB SLAVE INTERFACE LOGIC (Robust & Latch-free)
    // =========================================================================
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset toàn bộ thanh ghi cấu hình
            reg_diff_threshold <= DEFAULT_THRESH;
            reg_int_limit      <= DEFAULT_LIMIT;
            reg_decay_rate     <= DEFAULT_DECAY;
            reg_attack_rate    <= DEFAULT_ATTACK;
            
            // Reset tín hiệu phản hồi Bus
            apb_slv.pready     <= 1'b0;
            apb_slv.prdata     <= 32'd0;
            apb_slv.pslverr    <= 1'b0;
        end else begin
            // Default responses (Tránh Latch)
            apb_slv.pready  <= 1'b0;
            apb_slv.pslverr <= 1'b0;
            apb_slv.prdata  <= 32'd0; // Clear data bus

            // Handshake Logic
            if (apb_slv.psel && apb_slv.penable) begin
                apb_slv.pready <= 1'b1; // Acknowledge transaction
                
                if (apb_slv.pwrite) begin
                    // --- WRITE OPERATION ---
                    case (apb_slv.paddr[4:0]) // Decode address offset
                        5'h04: reg_diff_threshold <= apb_slv.pwdata[15:0];
                        5'h08: reg_int_limit      <= apb_slv.pwdata[15:0];
                        5'h0C: reg_decay_rate     <= apb_slv.pwdata[7:0];
                        5'h10: reg_attack_rate    <= apb_slv.pwdata[7:0];
                        default: ; // Write to RO or invalid addr -> Ignore
                    endcase
                end else begin
                    // --- READ OPERATION ---
                    case (apb_slv.paddr[4:0])
                        5'h00: apb_slv.prdata <= {30'd0, reg_status};
                        5'h04: apb_slv.prdata <= {16'd0, reg_diff_threshold};
                        5'h08: apb_slv.prdata <= {16'd0, reg_int_limit};
                        5'h0C: apb_slv.prdata <= {24'd0, reg_decay_rate};
                        5'h10: apb_slv.prdata <= {24'd0, reg_attack_rate};
                        default: apb_slv.prdata <= 32'd0;
                    endcase
                end
            end
        end
    end

    // =========================================================================
    // 3. DSP DATAPATH (PIPELINED & SATURATED)
    // =========================================================================

    // --- Signals for Stage 1 (Differential) ---
    logic signed [DATA_WIDTH-1:0] s_curr, s_prev;
    logic signed [DATA_WIDTH:0]   diff_raw; // 17-bit for overflow protection
    logic [DATA_WIDTH-1:0]        diff_abs;
    
    // --- Signals for Stage 2 (Threshold & Integrator) ---
    logic [CNT_WIDTH-1:0] integrator;
    logic                 is_spike_detected;
    
    // Internal calculations for saturation/underflow check
    // Mở rộng bit để tính toán không bị tràn
    logic [CNT_WIDTH:0]   calc_add; 
    logic signed [CNT_WIDTH+1:0] calc_sub; 

    // -----------------------------------------------------------
    // STAGE 1: High-Pass Filter (Differentiator)
    // -----------------------------------------------------------

    // Thêm biến cờ khởi động để chặn báo động giả khi mới Reset
    logic is_startup;

    // --- STAGE 1: High-Pass Filter (Differentiator) ---
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_curr     <= '0;
            s_prev     <= '0;
            is_startup <= 1'b1; // Đang ở trạng thái khởi động
        end else if (adc_valid_i) begin
            s_prev     <= s_curr;
            s_curr     <= adc_data_i;
            is_startup <= 1'b0; // Sau mẫu đầu tiên, cờ startup về 0
        end
    end

    // Combinational Math for Speed
    assign diff_raw = s_curr - s_prev;
    
    
    assign diff_abs = is_startup ? '0 : ((diff_raw < 0) ? -diff_raw[DATA_WIDTH-1:0] : diff_raw[DATA_WIDTH-1:0]);

    // -----------------------------------------------------------
    // STAGE 2: Leaky Integrator with Saturation Logic
    // -----------------------------------------------------------
    assign is_spike_detected = (diff_abs > reg_diff_threshold);

    // Tính toán trước (Look-ahead) để kiểm tra tràn số
    assign calc_add = integrator + 17'(reg_attack_rate);
    assign calc_sub = {1'b0, integrator} - {9'd0, reg_decay_rate};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            integrator <= '0;
            irq_arc_o  <= 1'b0;
            reg_status <= 2'b00;
        end else if (adc_valid_i) begin
            
            if (is_spike_detected) begin
                // --- ATTACK PHASE (Tích lũy lỗi) ---
                
                // Kiểm tra bão hòa trên (Saturation): Không cho vượt quá reg_int_limit
                if (calc_add >= {1'b0, reg_int_limit}) begin
                    integrator <= reg_int_limit; // Clamping at Max
                    
                    // Trigger Alarm
                    irq_arc_o  <= 1'b1;
                    reg_status <= 2'b11; // DANGER STATE
                end else begin
                    integrator <= calc_add[CNT_WIDTH-1:0]; // Safe cast
                    
                    // Early Warning Logic
                    if (calc_add > {1'b0, (reg_int_limit >> 1)})
                        reg_status <= 2'b01; // WARNING STATE
                    else if (reg_status != 2'b11) // Giữ trạng thái Danger nếu đã bị
                        reg_status <= 2'b00;
                end
                
            end else begin
                // --- DECAY PHASE (Tự phục hồi) ---
                
                // Kiểm tra bão hòa dưới (Underflow): Không cho âm
                if (calc_sub <= 0) begin // Nếu kết quả <= 0
                    integrator <= '0; // Clamping at 0
                    
                    // Clear Alarm (Auto-reset functionality)
                    irq_arc_o  <= 1'b0;
                    reg_status <= 2'b00; // SAFE STATE
                end else begin
                    integrator <= calc_sub[CNT_WIDTH-1:0];
                    // Giữ nguyên status hoặc clear alarm nếu giảm sâu (tùy policy)
                end
            end
        end
    end

endmodule