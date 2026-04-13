module apb_gpio #(
    parameter APB_ADDR_WIDTH = 12,
    parameter PAD_NUM        = 32
) (
    // --- APB Bus Interface ---
    input  logic                      HCLK,
    input  logic                      HRESETn,
    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic [31:0]               PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic [31:0]               PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,

    // --- Physical Pad Interface ---
    input  logic [PAD_NUM-1:0]        gpio_in,
    output logic [PAD_NUM-1:0]        gpio_out,
    output logic [PAD_NUM-1:0]        gpio_dir,   // 1: Output, 0: Input
    output logic                      interrupt
);

    // =========================================================================
    // 1. ĐỊNH NGHĨA THANH GHI (REGISTER MAP)
    // =========================================================================
    // Offset địa chỉ:
    localparam ADDR_GPIO_PADDIR   = 4'h0; // [RW] Hướng dữ liệu
    localparam ADDR_GPIO_DATAIN   = 4'h4; // [RO] Dữ liệu vào (đã đồng bộ)
    localparam ADDR_GPIO_DATAOUT  = 4'h8; // [RW] Dữ liệu ra
    localparam ADDR_GPIO_INTEN    = 4'hC; // [RW] Cho phép ngắt

    // Internal Registers
    logic [PAD_NUM-1:0] r_gpio_dir;
    logic [PAD_NUM-1:0] r_gpio_out;
    logic [PAD_NUM-1:0] r_gpio_inten;
    
    // Tín hiệu đồng bộ đầu vào
    logic [PAD_NUM-1:0] r_sync0, r_sync1;
    logic [PAD_NUM-1:0] r_in_old;

    // =========================================================================
    // 2. LOGIC ĐỒNG BỘ HÓA ĐẦU VÀO (INPUT SYNCHRONIZATION)
    // =========================================================================
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_sync0  <= '0;
            r_sync1  <= '0;
            r_in_old <= '0;
        end else begin
            r_sync0  <= gpio_in;
            r_sync1  <= r_sync0;  // Chống Metastability
            r_in_old <= r_sync1;  // Dùng để phát hiện cạnh
        end
    end

    // =========================================================================
    // 3. LOGIC GIẢI MÃ BUS APB (BUS DECODING & REG ACCESS)
    // =========================================================================
    assign PREADY  = 1'b1; // Slave phản hồi ngay lập tức
    assign PSLVERR = 1'b0; // Không báo lỗi bus

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_gpio_dir   <= '0; // Mặc định là Input (An toàn)
            r_gpio_out   <= '0;
            r_gpio_inten <= '0;
            PRDATA       <= '0;
        end else begin
            // --- XỬ LÝ LỆNH GHI (WRITE) ---
            if (PSEL && PENABLE && PWRITE) begin
                case (PADDR[3:0])
                    ADDR_GPIO_PADDIR:  r_gpio_dir   <= PWDATA[PAD_NUM-1:0];
                    ADDR_GPIO_DATAOUT: r_gpio_out   <= PWDATA[PAD_NUM-1:0];
                    ADDR_GPIO_INTEN:   r_gpio_inten <= PWDATA[PAD_NUM-1:0];
                    default: ;
                endcase
            end

            // --- XỬ LÝ LỆNH ĐỌC (READ) ---
            if (PSEL && !PWRITE) begin
                case (PADDR[3:0])
                    ADDR_GPIO_PADDIR:  PRDATA <= { {(32-PAD_NUM){1'b0}}, r_gpio_dir };
                    ADDR_GPIO_DATAIN:  PRDATA <= { {(32-PAD_NUM){1'b0}}, r_sync1 };
                    ADDR_GPIO_DATAOUT: PRDATA <= { {(32-PAD_NUM){1'b0}}, r_gpio_out };
                    ADDR_GPIO_INTEN:   PRDATA <= { {(32-PAD_NUM){1'b0}}, r_gpio_inten };
                    default:           PRDATA <= 32'd0;
                endcase
            end
        end
    end

    // =========================================================================
    // 4. LOGIC NGẮT (INTERRUPT GENERATION)
    // =========================================================================
    logic [PAD_NUM-1:0] s_intr_event;

    // Phát hiện cạnh lên (Rising Edge) cho tất cả các chân Input
    always_comb begin
        for (int i = 0; i < PAD_NUM; i++) begin : gen_intr_logic
            // Sự kiện xảy ra khi: Chân là Input & Có cạnh lên & Ngắt được bật
            s_intr_event[i] = (!r_gpio_dir[i]) && (r_sync1[i] && !r_in_old[i]) && r_gpio_inten[i];
        end
    end

    // Tổng hợp tất cả các nguồn ngắt
    assign interrupt = |s_intr_event;

    // =========================================================================
    // 5. GÁN ĐẦU RA VẬT LÝ (OUTPUT DRIVE)
    // =========================================================================
    assign gpio_out = r_gpio_out;
    assign gpio_dir = r_gpio_dir;

endmodule