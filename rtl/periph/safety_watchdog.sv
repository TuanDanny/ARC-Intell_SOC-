/*
 * Module: safety_watchdog
 * Description: Advanced Safety Watchdog Timer for INTELLI-SAFE SoC.
 *              - APB v3.0 Slave Interface.
 *              - 32-bit Down-Counter with Programmable Timeout.
 *              - "Magic Pattern" Feed Mechanism (Prevention of accidental feeds).
 *              - "Lock" Capability (Prevents disabling WDT after system boot).
 *              - Robust Reset Pulse Generation.
 * Author: SIU-IC Design Team
 * Standards: ISO 26262 Safety Mechanisms compliant.
 */

module safety_watchdog #(
    parameter APB_ADDR_WIDTH = 32,
    parameter APB_DATA_WIDTH = 32,
    parameter DEFAULT_TIMEOUT = 32'h00FF_FFFF // ~335ms @ 50MHz
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

    // --- Critical Output ---
    output logic                      wdt_reset_o // Active High System Reset Request
);

    // =========================================================================
    // 1. CONSTANTS & MAGIC NUMBERS
    // =========================================================================
    // Register Offsets
    localparam ADDR_CTRL    = 4'h0; // [RW] Control: [0]=Enable, [1]=Lock
    localparam ADDR_TIMEOUT = 4'h4; // [RW] Reload Value (only writable if unlocked)
    localparam ADDR_FEED    = 4'h8; // [WO] Feed Dog (Write Only)
    localparam ADDR_COUNT   = 4'hC; // [RO] Current Counter Value

    // Safety Magic Pattern (To prevent runaway code from feeding WDT)
    localparam [31:0] FEED_PATTERN = 32'hD09_F00D; // "Dog Food"

    // =========================================================================
    // 2. INTERNAL REGISTERS
    // =========================================================================
    logic [31:0] r_counter;
    logic [31:0] r_timeout_val;
    logic        r_enable;
    logic        r_lock;      // Once set to 1, cannot be cleared until Hard Reset
    logic        s_wdt_expired;
    logic [3:0]  r_rst_pulse_cnt; // To ensure reset pulse width > 1 clock

    // =========================================================================
    // 3. APB INTERFACE LOGIC
    // =========================================================================
    // Default APB responses
    assign pready_o  = 1'b1; // Single cycle access
    assign pslverr_o = 1'b0; // No error logic implemented

    // Register Read Logic
    always_comb begin
        prdata_o = 32'd0;
        if (psel_i && !pwrite_i) begin
            case (paddr_i[3:0])
                ADDR_CTRL:    prdata_o = {30'd0, r_lock, r_enable};
                ADDR_TIMEOUT: prdata_o = r_timeout_val;
                ADDR_FEED:    prdata_o = 32'd0; // Write-only
                ADDR_COUNT:   prdata_o = r_counter;
                default:      prdata_o = 32'd0;
            endcase
        end
    end

    // Register Write Logic & Watchdog Core
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_enable       <= 1'b0;
            r_lock         <= 1'b0;
            r_timeout_val  <= DEFAULT_TIMEOUT;
            r_counter      <= DEFAULT_TIMEOUT;
            s_wdt_expired  <= 1'b0;
        end else begin
            // --- COUNTER DECREMENT LOGIC ---
            if (r_enable) begin
                if (r_counter == 0) begin
                    s_wdt_expired <= 1'b1; // Trigger Reset
                end else begin
                    r_counter <= r_counter - 1;
                end
            end else begin
                // If disabled, hold counter at reset value
                r_counter <= r_timeout_val;
            end

            // --- APB WRITE HANDLER ---
            if (psel_i && penable_i && pwrite_i) begin
                case (paddr_i[3:0])
                    ADDR_CTRL: begin
                        // Bit 1: LOCK - One way set only (0->1)
                        if (!r_lock) begin
                            r_lock   <= pwdata_i[1];
                            r_enable <= pwdata_i[0];
                        end else begin
                            // If locked, can only WRITE 1 to lock (redundant) 
                            // Can NOT disable (r_enable stays 1 if it was 1)
                            // Safety: Lock bit protects enable bit clearing
                        end
                    end

                    ADDR_TIMEOUT: begin
                        // Only update timeout if NOT locked
                        if (!r_lock) begin
                            r_timeout_val <= pwdata_i;
                            // Update current counter immediately if not enabled yet
                            if (!r_enable) r_counter <= pwdata_i;
                        end
                    end

                    ADDR_FEED: begin
                        // Only reload if pattern matches exactly
                        if (pwdata_i == FEED_PATTERN) begin
                            r_counter <= r_timeout_val;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 4. OUTPUT RESET GENERATION (ROBUST PULSE)
    // =========================================================================
    // Ensures reset signal is asserted for at least 8 clock cycles
    // to guarantee the whole system (Reset Controller) catches it.
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_rst_pulse_cnt <= 4'd0;
            wdt_reset_o     <= 1'b0;
        end else begin
            if (s_wdt_expired) begin
                wdt_reset_o     <= 1'b1;
                r_rst_pulse_cnt <= 4'd15; // Load pulse width counter
            end else if (r_rst_pulse_cnt > 0) begin
                wdt_reset_o     <= 1'b1;
                r_rst_pulse_cnt <= r_rst_pulse_cnt - 4'd1;
            end else begin
                wdt_reset_o     <= 1'b0;
            end
        end
    end

endmodule