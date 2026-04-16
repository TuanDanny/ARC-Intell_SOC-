`include "../include/apb_bus.sv"
`include "../include/config.sv"

module cpu_8bit #(
    parameter ROM_SIZE = 256,
    parameter RAM_SIZE = 128,
    parameter ROM_INIT_FILE = "firmware/cpu_program.hex"
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       irq_arc_i,
    input  logic       irq_timer_i,
    APB_BUS            apb_mst
);

    localparam OP_NOP = 4'h0;
    localparam OP_LDI = 4'h1;
    localparam OP_ADD = 4'h2;
    localparam OP_SUB = 4'h3;
    localparam OP_AND = 4'h4;
    localparam OP_JMP = 4'h5;
    localparam OP_BEQ = 4'h6;
    localparam OP_STR = 4'h7;
    localparam OP_LDR = 4'h8;
    localparam OP_RET = 4'hF;

    logic [7:0]  reg_file [0:7];
    logic [7:0]  pc;
    logic [1:0]  flags;
    logic [7:0]  shadow_pc;
    logic [1:0]  shadow_flags;
    logic [7:0]  nested_shadow_pc;
    logic [1:0]  nested_shadow_flags;
    logic        in_timer_isr;
    logic        in_arc_isr;
    logic        arc_preempted_timer;
    logic        is_in_isr;
    logic [3:0]  dsp_page_sel;

    logic        apb_rd_pending;
    logic        apb_rd_wide_pending;
    logic [2:0]  apb_rd_dest;
    logic [2:0]  apb_rd_dest_hi;
    logic        apb_rd_dest_hi_valid;

    logic [15:0] instr;
    logic [15:0] instr_mem [0:ROM_SIZE-1];
    logic [3:0]  opcode;
    logic [2:0]  rd;
    logic [2:0]  rs;
    logic [2:0]  rt;
    logic [7:0]  imm8;

    typedef enum logic [2:0] {
        S_FETCH,
        S_DECODE,
        S_APB_ACCESS,
        S_FAULT_RECOVERY
    } state_t;
    state_t state;

    initial begin : init_instr_mem
        for (int rom_idx = 0; rom_idx < ROM_SIZE; rom_idx++) begin
            instr_mem[rom_idx] = {OP_NOP, 12'd0};
        end
        $readmemh(ROM_INIT_FILE, instr_mem);
    end

    logic [31:0] computed_paddr;
    logic        instr_wide;
    logic        is_dsp_access;
    logic        is_cpu_ctrl_access;
    logic [2:0]  rd_pair_hi_idx;
    logic [31:0] computed_pwdata;

    localparam logic [3:0] DEV_RAM      = 4'h0;
    localparam logic [3:0] DEV_DSP      = 4'h1;
    localparam logic [3:0] DEV_GPIO     = 4'h2;
    localparam logic [3:0] DEV_UART     = 4'h3;
    localparam logic [3:0] DEV_TIMER    = 4'h4;
    localparam logic [3:0] DEV_WATCHDOG = 4'h5;
    localparam logic [3:0] DEV_BIST     = 4'h6;
    localparam logic [3:0] DEV_SPI      = 4'h7;
    localparam logic [3:0] DEV_CPU_CTRL = 4'hF;

    localparam logic [3:0] CPU_CTRL_DSP_PAGE = 4'h0;

    always_comb begin
        case (imm8[7:4])
            DEV_RAM:      computed_paddr = `RAM_BASE_ADDR      + {24'd0, imm8[3:0], 4'h0};
            DEV_DSP:      computed_paddr = `DSP_BASE_ADDR      + {22'd0, dsp_page_sel, imm8[3:0], 2'b00};
            DEV_GPIO:     computed_paddr = `GPIO_BASE_ADDR     + {28'd0, imm8[3:0]};
            DEV_UART:     computed_paddr = `UART_BASE_ADDR     + {28'd0, imm8[3:0]};
            DEV_TIMER:    computed_paddr = `TIMER_BASE_ADDR    + {28'd0, imm8[3:0]};
            DEV_WATCHDOG: computed_paddr = `WATCHDOG_BASE_ADDR + {28'd0, imm8[3:0]};
            DEV_BIST:     computed_paddr = `BIST_BASE_ADDR     + {28'd0, imm8[3:0]};
            DEV_SPI:      computed_paddr = `SPI_BASE_ADDR      + {28'd0, imm8[3:0]};
            default: computed_paddr = 32'h0;
        endcase
    end

    assign opcode = instr[15:12];
    assign rd     = instr[11:9];
    assign rs     = instr[8:6];
    assign rt     = instr[5:3];
    assign imm8   = instr[7:0];
    assign instr_wide = instr[8];
    assign is_dsp_access = (imm8[7:4] == DEV_DSP);
    assign is_cpu_ctrl_access = (imm8[7:4] == DEV_CPU_CTRL);
    assign is_in_isr = in_timer_isr | in_arc_isr;
    assign instr = (pc < ROM_SIZE) ? instr_mem[pc] : {OP_NOP, 12'd0};

    always_comb begin
        if (rd == 3'd7) begin
            rd_pair_hi_idx = 3'd7;
            computed_pwdata = {24'd0, reg_file[rd]};
        end else if (instr_wide && is_dsp_access) begin
            rd_pair_hi_idx = rd + 3'd1;
            computed_pwdata = {16'd0, reg_file[rd + 3'd1], reg_file[rd]};
        end else begin
            rd_pair_hi_idx = rd + 3'd1;
            computed_pwdata = {24'd0, reg_file[rd]};
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state           <= S_FETCH;
            pc              <= 8'd0;
            flags           <= 2'b00;
            shadow_pc       <= 8'd0;
            shadow_flags    <= 2'b00;
            nested_shadow_pc    <= 8'd0;
            nested_shadow_flags <= 2'b00;
            in_timer_isr    <= 1'b0;
            in_arc_isr      <= 1'b0;
            arc_preempted_timer <= 1'b0;
            dsp_page_sel    <= 4'd0;
            apb_rd_pending  <= 1'b0;
            apb_rd_wide_pending <= 1'b0;
            apb_rd_dest     <= 3'd0;
            apb_rd_dest_hi  <= 3'd0;
            apb_rd_dest_hi_valid <= 1'b0;

            for (int i = 0; i < 8; i++) begin
                reg_file[i] <= 8'd0;
            end

            apb_mst.paddr   <= 32'd0;
            apb_mst.pwdata  <= 32'd0;
            apb_mst.pwrite  <= 1'b0;
            apb_mst.psel    <= 1'b0;
            apb_mst.penable <= 1'b0;
        end else begin
            if (irq_arc_i && !in_arc_isr) begin
                if (in_timer_isr) begin
                    nested_shadow_pc    <= pc;
                    nested_shadow_flags <= flags;
                    arc_preempted_timer <= 1'b1;
                end else begin
                    shadow_pc       <= pc;
                    shadow_flags    <= flags;
                    arc_preempted_timer <= 1'b0;
                end
                in_arc_isr       <= 1'b1;
                reg_file[0]     <= 8'd1;
                pc              <= 8'h01;
                state           <= S_FETCH;
                apb_mst.pwrite  <= 1'b0;
                apb_mst.psel    <= 1'b0;
                apb_mst.penable <= 1'b0;
                apb_rd_pending  <= 1'b0;
                apb_rd_wide_pending <= 1'b0;
                apb_rd_dest_hi_valid <= 1'b0;
            end else if (irq_timer_i && !in_timer_isr && !in_arc_isr) begin
                shadow_pc       <= pc;
                shadow_flags    <= flags;
                in_timer_isr    <= 1'b1;
                pc              <= 8'h09;
                state           <= S_FETCH;
                apb_mst.pwrite  <= 1'b0;
                apb_mst.psel    <= 1'b0;
                apb_mst.penable <= 1'b0;
                apb_rd_pending  <= 1'b0;
                apb_rd_wide_pending <= 1'b0;
                apb_rd_dest_hi_valid <= 1'b0;
            end else begin
                case (state)
                    S_FETCH: begin
                        state <= S_DECODE;
                    end

                    S_DECODE: begin
                        pc    <= pc + 1'b1;
                        state <= S_FETCH;

                        case (opcode)
                            OP_NOP: ;

                            OP_LDI: reg_file[rd] <= imm8;

                            OP_ADD: begin
                                reg_file[rd] <= reg_file[rs] + reg_file[rt];
                                flags[1]     <= ((reg_file[rs] + reg_file[rt]) == 8'd0);
                            end

                            OP_SUB: begin
                                reg_file[rd] <= reg_file[rs] - reg_file[rt];
                                flags[1]     <= ((reg_file[rs] - reg_file[rt]) == 8'd0);
                            end

                            OP_AND: begin
                                reg_file[rd] <= reg_file[rs] & reg_file[rt];
                                flags[1]     <= ((reg_file[rs] & reg_file[rt]) == 8'd0);
                            end

                            OP_JMP: pc <= imm8;

                            OP_BEQ: begin
                                if (flags[1]) begin
                                    pc <= imm8;
                                end
                            end

                            OP_STR: begin
                                if (is_cpu_ctrl_access) begin
                                    case (imm8[3:0])
                                        CPU_CTRL_DSP_PAGE: dsp_page_sel <= reg_file[rd][3:0];
                                        default: ;
                                    endcase
                                end else begin
                                    apb_mst.paddr   <= computed_paddr;
                                    apb_mst.pwdata  <= computed_pwdata;
                                    apb_mst.pwrite  <= 1'b1;
                                    apb_mst.psel    <= 1'b1;
                                    apb_mst.penable <= 1'b0;
                                    apb_rd_pending  <= 1'b0;
                                    apb_rd_wide_pending <= 1'b0;
                                    apb_rd_dest_hi_valid <= 1'b0;
                                    state           <= S_APB_ACCESS;
                                end
                            end

                            OP_LDR: begin
                                if (is_cpu_ctrl_access) begin
                                    case (imm8[3:0])
                                        CPU_CTRL_DSP_PAGE: reg_file[rd] <= {4'd0, dsp_page_sel};
                                        default: reg_file[rd] <= 8'd0;
                                    endcase
                                end else begin
                                    apb_mst.paddr   <= computed_paddr;
                                    apb_mst.pwrite  <= 1'b0;
                                    apb_mst.psel    <= 1'b1;
                                    apb_mst.penable <= 1'b0;
                                    apb_rd_pending  <= 1'b1;
                                    apb_rd_wide_pending <= instr_wide && is_dsp_access;
                                    apb_rd_dest     <= rd;
                                    apb_rd_dest_hi  <= rd_pair_hi_idx;
                                    apb_rd_dest_hi_valid <= (instr_wide && is_dsp_access && (rd != 3'd7));
                                    state           <= S_APB_ACCESS;
                                end
                            end

                            OP_RET: begin
                                if (in_arc_isr) begin
                                    if (arc_preempted_timer) begin
                                        pc                  <= nested_shadow_pc;
                                        flags               <= nested_shadow_flags;
                                        in_arc_isr          <= 1'b0;
                                        arc_preempted_timer <= 1'b0;
                                    end else begin
                                        pc         <= shadow_pc;
                                        flags      <= shadow_flags;
                                        in_arc_isr <= 1'b0;
                                    end
                                end else if (in_timer_isr) begin
                                    pc          <= shadow_pc;
                                    flags       <= shadow_flags;
                                    in_timer_isr <= 1'b0;
                                end else begin
                                    state <= S_FAULT_RECOVERY;
                                end
                            end

                            default: state <= S_FAULT_RECOVERY;
                        endcase
                    end

                    S_APB_ACCESS: begin
                        apb_mst.penable <= 1'b1;

                        if (apb_mst.penable && apb_mst.pready) begin
                            apb_mst.psel    <= 1'b0;
                            apb_mst.penable <= 1'b0;

                            if (apb_rd_pending) begin
                                reg_file[apb_rd_dest] <= apb_mst.prdata[7:0];
                                if (apb_rd_wide_pending && apb_rd_dest_hi_valid) begin
                                    reg_file[apb_rd_dest_hi] <= apb_mst.prdata[15:8];
                                end
                            end

                            apb_mst.pwrite <= 1'b0;
                            apb_rd_pending <= 1'b0;
                            apb_rd_wide_pending <= 1'b0;
                            apb_rd_dest_hi_valid <= 1'b0;
                            state          <= S_FETCH;
                        end
                    end

                    S_FAULT_RECOVERY: begin
                        pc              <= 8'h00;
                        flags           <= 2'b00;
                        shadow_pc       <= 8'd0;
                        shadow_flags    <= 2'b00;
                        nested_shadow_pc    <= 8'd0;
                        nested_shadow_flags <= 2'b00;
                        in_timer_isr    <= 1'b0;
                        in_arc_isr      <= 1'b0;
                        arc_preempted_timer <= 1'b0;
                        apb_mst.pwrite  <= 1'b0;
                        apb_mst.psel    <= 1'b0;
                        apb_mst.penable <= 1'b0;
                        apb_rd_pending  <= 1'b0;
                        apb_rd_wide_pending <= 1'b0;
                        apb_rd_dest_hi_valid <= 1'b0;
                        state           <= S_FETCH;
                    end

                    default: state <= S_FETCH;
                endcase
            end
        end
    end

endmodule
