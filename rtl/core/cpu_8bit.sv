`include "../include/apb_bus.sv"
`include "../include/config.sv"

// `include "D:/APP/Quatus_Workspace/In_SOC/rtl/include/apb_bus.sv"
// `include "D:/APP/Quatus_Workspace/In_SOC/rtl/include/config.sv"

// `include "config.sv"
// `include "apb_bus.sv"

module cpu_8bit #(
    parameter ROM_SIZE = 256, // Kích thước ROM (Instructions)
    parameter RAM_SIZE = 128  // Kích thước RAM nội bộ (Words)
) (
    input  logic       clk_i,
    input  logic       rst_ni,     // Reset Active Low
    
    // Tín hiệu Ngắt (Interrupts) - Level Sensitive
    input  logic       irq_arc_i,   // Priority 1: Hồ quang điện (Critical)
    input  logic       irq_timer_i, // Priority 2: Watchdog/Timer (System)
    
    // Giao diện Bus (APB Master)
    APB_BUS            apb_mst
);

    // =========================================================================
    // 1. ĐỊNH NGHĨA TẬP LỆNH (INSTRUCTION SET ARCHITECTURE)
    // =========================================================================
    localparam OP_NOP = 4'h0; // No Operation
    localparam OP_LDI = 4'h1; // Load Immediate: Rd = Imm8
    localparam OP_ADD = 4'h2; // Add: Rd = Rs + Rt
    localparam OP_SUB = 4'h3; // Sub: Rd = Rs - Rt
    localparam OP_AND = 4'h4; // And: Rd = Rs & Rt
    localparam OP_JMP = 4'h5; // Jump Absolute: PC = Imm8
    localparam OP_BEQ = 4'h6; // Branch Equal: If (Z) PC = Imm8
    localparam OP_STR = 4'h7; // Store: APB[Map(Imm8)] = Rd
    localparam OP_LDR = 4'h8; // Load:  Rd = APB[Map(Imm8)]
    localparam OP_RET = 4'hF; // Return: PC = ShadowPC

    // =========================================================================
    // 2. KHAI BÁO TÀI NGUYÊN PHẦN CỨNG (RESOURCES)
    // =========================================================================
    
    // Thanh ghi đa năng (Register File): R0-R7
    logic [7:0]  reg_file [0:7];
    
    // Thanh ghi chức năng đặc biệt
    logic [7:0]  pc;           // Program Counter
    logic [1:0]  flags;        // [1]: Zero Flag (Z), [0]: Carry Flag (C)
    
    // Thanh ghi Sao lưu ngữ cảnh (Context Backup for ISR)
    logic [7:0]  shadow_pc;
    logic [1:0]  shadow_flags;
    logic        is_in_isr;    // Cờ báo hiệu đang trong ngắt

    // Tín hiệu Giải mã lệnh (Decode Signals)
    logic [15:0] instr;
    logic [3:0]  opcode;
    logic [2:0]  rd, rs, rt;
    logic [7:0]  imm8;

    // Máy trạng thái điều khiển (Control FSM)
    typedef enum logic [2:0] {
        S_FETCH,        // Lấy lệnh
        S_DECODE,       // Giải mã & Thực thi ALU & Setup Phase APB
        S_APB_ACCESS,   // Access Phase APB (Wait for PREADY)
        S_FAULT_RECOVERY // Trạng thái an toàn khi gặp lỗi
    } state_t;
    state_t state;

    // =========================================================================
    // 3. HARDENED ROM LOGIC (FIRMWARE & DRIVER)
    // =========================================================================
    // Sử dụng logic tổ hợp (Combinational Logic) thay vì mảng nhớ để đảm bảo
    // Quartus Synthesis luôn nhận diện được Driver cho ROM (Tránh lỗi 10030).
    always_comb begin
        case (pc)
            8'h00: instr = {OP_JMP, 4'd0, 8'h04}; // Nh?y xu?ng Main Program ? 0x04
        
            // --- ISR Vector (0x01): X? lý H? Quang ---
            8'h01: instr = {OP_STR, 3'd0, 1'b0, 8'h20}; // STR R0,[0x20] (Ép PADDIR = 1)
            8'h02: instr = {OP_STR, 3'd0, 1'b0, 8'h28}; // STR R0, [0x28] (C?t Relay!)
            8'h03: instr = {OP_JMP, 4'd0, 8'h03}; // TREO AN TOÀN (Infinite Loop t?i 0x03)
            
            // --- Main Program (0x04) ---
            8'h04: instr = {OP_LDI, 3'd0, 8'd1}; // R0 = 1
            8'h05: instr = {OP_STR, 3'd0, 1'b0, 8'h20}; // Set GPIO PADDIR = Output
            8'h06: instr = {OP_LDI, 3'd0, 8'd0}; // R0 = 0
            8'h07: instr = {OP_STR, 3'd0, 1'b0, 8'h28}; // T?t Relay ban đ?u cho an toàn
            
            // --- Idle Loop (0x08) ---
            8'h08: instr = {OP_JMP, 4'd0, 8'h08}; // Vòng l?p ch? s? c?
            
            default: instr = {OP_NOP, 12'd0};
            
        endcase
    end

    // =========================================================================
    // 4. LOGIC TÍNH TOÁN ĐỊA CHỈ (MEMORY MAPPING)
    // =========================================================================
    // Ánh xạ Immediate 8-bit (imm8) sang không gian địa chỉ 32-bit của SoC
    logic [31:0] computed_paddr;

    always_comb begin
        case (imm8[7:4]) // Dùng 4 bit cao để chọn Chip Select
            4'h0: computed_paddr = `RAM_BASE_ADDR   + {24'd0, imm8[3:0], 4'h0}; 
            4'h1: computed_paddr = `DSP_BASE_ADDR   + {24'd0, imm8[3:0], 4'h0};
            
            // Chú ý: Ở đây ta dùng trực tiếp imm8 làm offset luôn cho dễ map với Firmware
            // Ghi 0x20 -> Map thẳng vào 0x2000. 
            // Ghi 0x28 -> Map thẳng vào 0x2008.
            4'h2: computed_paddr = `GPIO_BASE_ADDR  + {28'd0, imm8[3:0]}; 
            
            4'h3: computed_paddr = `UART_BASE_ADDR  + {28'd0, imm8[3:0]};
            4'h4: computed_paddr = `TIMER_BASE_ADDR + {28'd0, imm8[3:0]};
            // --- THÊM 2 DÒNG NÀY ĐỂ CPU NHÌN THẤY WDT VÀ BIST ---
            4'h5: computed_paddr = 32'h0000_5000    + {28'd0, imm8[3:0]}; // WDT
            4'h6: computed_paddr = 32'h0000_6000    + {28'd0, imm8[3:0]}; // BIST
            default: computed_paddr = 32'h0;
        endcase
    end

    // =========================================================================
    // 5. FETCH & DECODE SIGNALS
    // =========================================================================
    assign opcode = instr[15:12];
    assign rd     = instr[11:9];
    assign rs     = instr[8:6];
    assign rt     = instr[5:3];
    assign imm8   = instr[7:0];

    // =========================================================================
    // 6. MAIN CONTROLLER & DATAPATH (SEQUENTIAL LOGIC)
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // --- SYSTEM RESET ---
            state           <= S_FETCH;
            pc              <= 8'd0;
            flags           <= 2'b00;
            is_in_isr       <= 1'b0;
            shadow_pc       <= 8'd0;
            shadow_flags    <= 2'b00;
            
            // Reset toàn bộ Register File để tránh "Stuck pins" warning
            for (int i=0; i<8; i++) reg_file[i] <= 8'd0;

            // Reset tín hiệu Bus APB
            apb_mst.paddr   <= 32'd0;
            apb_mst.pwdata  <= 32'd0;
            apb_mst.pwrite  <= 1'b0;
            apb_mst.psel    <= 1'b0;
            apb_mst.penable <= 1'b0;

        end else begin
            
            // --- PRIORITY INTERRUPT CONTROLLER ---
            // Ưu tiên 1: Ngắt Hồ Quang (Arc Fault)
            if (irq_arc_i && !is_in_isr) begin
                shadow_pc    <= pc;
                shadow_flags <= flags;
                is_in_isr    <= 1'b1;
                
                // SAFETY: Nạp cứng R0 = 1 để đảm bảo lệnh ISR cắt được Relay
                reg_file[0]  <= 8'd1; 
                
                pc           <= 8'h01; // Vector ngắt (0x01)
                state        <= S_FETCH;
                
                // Hủy các giao dịch Bus đang dang dở (nếu có)
                apb_mst.psel    <= 1'b0;
                apb_mst.penable <= 1'b0;
            end
            // Ưu tiên 2: Ngắt Timer (System Tick)
            else if (irq_timer_i && !is_in_isr) begin
                shadow_pc    <= pc;
                shadow_flags <= flags;
                is_in_isr    <= 1'b1;
                pc           <= 8'h08; // Vector ngắt Timer (Giả định)
                state        <= S_FETCH;
            end 
            else begin
                
                // --- MAIN FSM ---
                case (state)
                    // ---------------------------------------------------------
                    // GIAI ĐOẠN 1: FETCH
                    // ---------------------------------------------------------
                    S_FETCH: begin
                        // Lệnh đã được lấy từ logic always_comb ROM
                        state <= S_DECODE;
                    end

                    // ---------------------------------------------------------
                    // GIAI ĐOẠN 2: DECODE & EXECUTE & BUS SETUP
                    // ---------------------------------------------------------
                    S_DECODE: begin
                        // Mặc định tăng PC (Next Instruction)
                        pc <= pc + 1'b1;
                        state <= S_FETCH; // Mặc định quay về Fetch

                        case (opcode)
                            OP_NOP: ; // Do nothing

                            OP_LDI: reg_file[rd] <= imm8;

                            OP_ADD: begin
                                reg_file[rd] <= reg_file[rs] + reg_file[rt];
                                flags[1] <= ((reg_file[rs] + reg_file[rt]) == 8'd0);
                            end

                            OP_SUB: begin
                                reg_file[rd] <= reg_file[rs] - reg_file[rt];
                                flags[1] <= ((reg_file[rs] - reg_file[rt]) == 8'd0);
                            end

                            OP_AND: begin
                                reg_file[rd] <= reg_file[rs] & reg_file[rt];
                                flags[1] <= ((reg_file[rs] & reg_file[rt]) == 8'd0);
                            end

                            OP_JMP: pc <= imm8;

                            OP_BEQ: if (flags[1]) pc <= imm8;

                            // --- APB STORE (Ghi) ---
                            // Tận dụng chu kỳ này làm SETUP PHASE
                            OP_STR: begin
                                apb_mst.paddr   <= computed_paddr;
                                apb_mst.pwdata  <= {24'd0, reg_file[rd]};
                                apb_mst.pwrite  <= 1'b1; // Write
                                apb_mst.psel    <= 1'b1; // Select
                                apb_mst.penable <= 1'b0; // Enable = 0 (Setup)
                                
                                state <= S_APB_ACCESS;   // Next -> Access Phase
                            end

                            // --- APB LOAD (Đọc) ---
                            // Tận dụng chu kỳ này làm SETUP PHASE
                            OP_LDR: begin
                                apb_mst.paddr   <= computed_paddr;
                                apb_mst.pwrite  <= 1'b0; // Read
                                apb_mst.psel    <= 1'b1; // Select
                                apb_mst.penable <= 1'b0; // Enable = 0 (Setup)
                                
                                state <= S_APB_ACCESS;   // Next -> Access Phase
                            end

                            OP_RET: begin
                                pc <= shadow_pc;
                                flags <= shadow_flags;
                                is_in_isr <= 1'b0;
                            end

                            default: state <= S_FAULT_RECOVERY;
                        endcase
                    end

                    // ---------------------------------------------------------
                    // GIAI ĐOẠN 3: BUS ACCESS (HANDSHAKE)
                    // ---------------------------------------------------------
                    S_APB_ACCESS: begin
                            // Mặc định luôn kích hoạt Enable khi đã vào trạng thái này
                            apb_mst.penable <= 1'b1; 

                            // Kiểm tra phản hồi từ Slave (GPIO)
                            if (apb_mst.penable && apb_mst.pready) begin
                                // Slave đã nhận xong -> Kết thúc giao dịch
                                apb_mst.psel    <= 1'b0;
                                apb_mst.penable <= 1'b0; // Kéo xuống 0 để chuẩn bị cho lệnh sau
                                
                                // Nếu là lệnh ĐỌC (LDR), lấy dữ liệu về
                                if (!apb_mst.pwrite) begin
                                    reg_file[rd] <= apb_mst.prdata[7:0];
                                end
                                
                                state <= S_FETCH; // Xong việc, quay về lấy lệnh tiếp
                            end
                        
                        // Nếu PREADY = 0, giữ nguyên trạng thái và chờ
                    end

                    // ---------------------------------------------------------
                    // GIAI ĐOẠN 4: FAULT RECOVERY
                    // ---------------------------------------------------------
                    S_FAULT_RECOVERY: begin
                        // Tự động Reset mềm về địa chỉ 0
                        pc <= 8'h00;
                        flags <= 2'b00;
                        state <= S_FETCH;
                    end
                    
                    default: state <= S_FETCH;
                endcase
            end
        end
    end

endmodule