module logic_bist #(
    parameter APB_ADDR_WIDTH = 32,
    parameter APB_DATA_WIDTH = 32,
    parameter DATA_WIDTH     = 16,
    parameter LFSR_POLY      = 16'hB400 // x^16 + x^14 + x^13 + x^11 + 1
) (
    // --- Clock & Reset ---
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // --- APB Slave Interface ---
    input  logic [APB_ADDR_WIDTH-1:0] paddr_i,
    input  logic [APB_DATA_WIDTH-1:0] pwdata_i,
    input  logic                      psel_i,
    input  logic                      penable_i,
    input  logic                      pwrite_i,
    output logic [APB_DATA_WIDTH-1:0] prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,

    // --- Interface to DSP (Stimuli Injection) ---
    output logic [DATA_WIDTH-1:0]     bist_data_o,    // Inject to DSP
    output logic                      bist_valid_o,   // Inject valid
    output logic                      bist_active_o,  // Mux selector (1: BIST, 0: ADC)

    // --- Interface from DSP (Response Capture) ---
    input  logic                      dsp_irq_i       // DSP Critical Output to be verified
);

    // =========================================================================
    // 1. REGISTER MAP & CONSTANTS
    // =========================================================================
    /*
     * 0x00 (RW): CTRL       [0]: Start (Self-clearing), [1]: Reset Logic
     * 0x04 (RW): CONFIG     [15:0] Test Length (Cycles)
     * 0x08 (RW): SEED       [15:0] LFSR Initial Seed
     * 0x0C (RO): SIGNATURE  [15:0] MISR Result (To be compared with Golden)
     * 0x10 (RO): STATUS     [0]: Busy, [1]: Done, [2]: Mismatch (Optional SW check)
     */
    localparam ADDR_CTRL      = 5'h0;
    localparam ADDR_CONFIG    = 5'h4;
    localparam ADDR_SEED      = 5'h8;
    localparam ADDR_SIGNATURE = 5'hC;
    localparam ADDR_STATUS    = 5'h10;

    // =========================================================================
    // 2. INTERNAL SIGNALS
    // =========================================================================
    // Registers
    logic [15:0] r_test_len;
    logic [15:0] r_seed;
    logic [15:0] r_signature;
    logic        r_busy;
    logic        r_done;
    
    // Datapath
    logic [15:0] lfsr_reg;
    logic [15:0] misr_reg;
    logic [15:0] cycle_cnt;
    logic        s_start_cmd;
    logic        s_reset_cmd;
    // Thêm tín hiệu cờ báo lỗi BIST
    logic s_bist_error;

    // FSM States
    typedef enum logic [1:0] {
        IDLE,
        RUN,
        COMPLETE
    } bist_state_t;
    bist_state_t state, next_state;

    // =========================================================================
    // 3. APB INTERFACE LOGIC
    // =========================================================================
    assign pready_o  = 1'b1;
    assign pslverr_o = 1'b0;

    // Write Logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_test_len  <= 16'd100;    // Default 100 cycles
            r_seed      <= 16'hACE1;   // Default Non-zero seed
            s_start_cmd <= 1'b0;
            s_reset_cmd <= 1'b0;
        end else begin
            s_start_cmd <= 1'b0; // Auto-clear
            s_reset_cmd <= 1'b0; // Auto-clear

            if (psel_i && penable_i && pwrite_i) begin
                case (paddr_i[3:0])
                    ADDR_CTRL: begin
                        s_start_cmd <= pwdata_i[0];
                        s_reset_cmd <= pwdata_i[1];
                    end
                    ADDR_CONFIG: r_test_len <= pwdata_i[15:0];
                    ADDR_SEED:   r_seed     <= pwdata_i[15:0];
                    default: ;
                endcase
            end
        end
    end

    // Read Logic
    always_comb begin
        prdata_o = 32'd0;
        if (psel_i && !pwrite_i) begin
            case (paddr_i[4:0])
                ADDR_CTRL:      prdata_o = 32'd0;
                ADDR_CONFIG:    prdata_o = {16'd0, r_test_len};
                ADDR_SEED:      prdata_o = {16'd0, r_seed};
                ADDR_SIGNATURE: prdata_o = {16'd0, r_signature}; // Result
                ADDR_STATUS:    prdata_o = {29'd0, s_bist_error, r_done, r_busy};
                
                default:        prdata_o = 32'd0;
            endcase
        end
    end

    // =========================================================================
    // 4. BIST CONTROLLER FSM
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state <= IDLE;
        else         state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (s_start_cmd) next_state = RUN;
            end
            RUN: begin
                if (r_test_len == 16'd0)
                    next_state = COMPLETE;
                else if (cycle_cnt == r_test_len - 1'b1)
                    next_state = COMPLETE;
                if (s_reset_cmd) next_state = IDLE;
            end
            COMPLETE: begin
                if (s_reset_cmd || s_start_cmd) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Output Status Logic
    assign r_busy        = (state == RUN);
    // assign r_done        = (state == COMPLETE);
    assign bist_active_o = r_busy; // Mux control: 1=BIST Data, 0=ADC Data

    // =========================================================================
    // 5. PRPG (Pattern Generator) - Galois LFSR
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lfsr_reg  <= 16'hACE1;
            cycle_cnt <= 16'd0;
        end else begin
            if (state == IDLE) begin
                lfsr_reg  <= (r_seed == 16'd0) ? 16'hACE1 : r_seed; // Protect against 0 seed
                cycle_cnt <= 16'd0;
            end else if (state == RUN) begin
                // LFSR Feedback: x^16 + x^14 + x^13 + x^11 + 1
                // Implemented as Galois for timing efficiency
                lfsr_reg <= {lfsr_reg[14:0], 1'b0} ^ (lfsr_reg[15] ? LFSR_POLY : 16'd0);
                cycle_cnt <= cycle_cnt + 1'b1;
            end
        end
    end

    // Output stimuli
    assign bist_data_o  = lfsr_reg;
    assign bist_valid_o = r_busy; // Valid active during RUN

    // =========================================================================
    // 6. MISR (Signature Analyzer) - Response Compression
    // =========================================================================
    // Compress the 1-bit dsp_irq_i stream into a 16-bit signature
    // Polynomial: Same as LFSR for hardware reuse simplicity

    logic r_done_reg; // Tạo một Flip-Flop để lưu trạng thái Done
    assign r_done = r_done_reg; // Cập nhật lại ngõ ra r_done
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            misr_reg <= 16'd0;
            r_signature <= 16'd0;
            r_done_reg <= 1'b0; // Reset cờ Done
        end else begin
            if (state == IDLE) begin
                misr_reg <= 16'd0;
                r_done_reg <= 1'b0; // Xóa cờ Done khi bắt đầu vòng mới
            end else if (state == RUN) begin
                // MISR Logic: Shift, XOR feedback, XOR input
                misr_reg <= {misr_reg[14:0], dsp_irq_i} ^ (misr_reg[15] ? LFSR_POLY : 16'd0);
                r_done_reg <= 1'b0; // Đảm bảo cờ Done chỉ được set khi hoàn thành
            end else if (state == COMPLETE) begin
                r_signature <= misr_reg; // Latch final result
                r_done_reg <= 1'b1; // Set cờ Done khi hoàn thành
            end
        end
    end

    // Logic tự chẩn đoán: Nếu BIST đã chạy xong (COMPLETE) 
    // mà chữ ký vẫn bằng 0 (khả năng cao là lỗi vật lý), báo lỗi ngay.
    assign s_bist_error = (state == COMPLETE && r_signature == 16'h0000);

endmodule
