`include "../include/apb_bus.sv"

module dsp_arc_detect #(
    parameter DATA_WIDTH = 16,
    parameter CNT_WIDTH  = 16
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [DATA_WIDTH-1:0]  adc_data_i,
    input  logic                   adc_valid_i,
    input  logic                   stream_restart_i,
    APB_BUS                        apb_slv,
    output logic                   irq_arc_o
);

    // =====================================================================
    // 1. REGISTER MAP
    // =====================================================================
    // 0x00 (RO): STATUS
    //      [1:0] reg_status         00=SAFE, 01=WARN, 11=FIRE
    //      [2]   irq_arc_o          live alarm output
    //      [3]   fire_latched       sticky event flag
    //      [4]   sample_pair_valid  DSP has seen at least 2 samples
    // 0x04 (RW): BASE_THRESH (compat with old DIFF_THRESH address)
    // 0x08 (RW): INT_LIMIT
    // 0x0C (RW): DECAY_RATE
    // 0x10 (RW): BASE_ATTACK
    // 0x14 (RO): CURRENT_DIFF_ABS
    // 0x18 (RO): CURRENT_INTEGRATOR
    // 0x1C (RO): PEAK_DIFF_ABS
    // 0x20 (RO): PEAK_INTEGRATOR
    // 0x24 (RO): EVENT_COUNT
    // 0x28 (WO): CLEAR
    //      [0] clear fire_latched
    //      [1] clear diff / peak telemetry
    //      [2] clear event_count
    //      [3] reserved
    //      [4] clear stream_restart_count
    // 0x2C (RW): EXCESS_SHIFT
    // 0x30 (RW): ATTACK_CLAMP
    // 0x34 (RO): CURRENT_ATTACK_STEP
    // 0x38 (RW): WIN_LEN
    // 0x3C (RW): SPIKE_SUM_WARN
    //      0 disables density gating for WARN
    // 0x40 (RW): SPIKE_SUM_FIRE
    //      0 disables density-based FIRE
    // 0x44 (RO): CURRENT_SPIKE_SUM
    // 0x48 (RO): PEAK_SPIKE_SUM
    // 0x4C (RW): PEAK_DIFF_FIRE_THRESH
    // 0x50 (RW): ALPHA_SHIFT
    // 0x54 (RW): GAIN_SHIFT
    // 0x58 (RO): CURRENT_NOISE_FLOOR
    // 0x5C (RO): EFFECTIVE_THRESH
    // 0x60 (RO): STREAM_STATUS
    //      [0] stream_restart_i (live)
    //      [1] detector_holdoff_active
    //      [31:2] reserved
    // 0x64 (RO): STREAM_RESTART_COUNT
    // 0x68 (RW): HOT_BASE
    // 0x6C (RW): HOT_ATTACK
    // 0x70 (RW): HOT_DECAY
    // 0x74 (RW): HOT_LIMIT
    // 0x78 (RW): ENV_SHIFT
    // 0x7C (RO): CURRENT_ENV_LP
    // 0x80 (RO): CURRENT_HOTSPOT_SCORE
    // 0x84 (RW): ZERO_BAND
    // 0x88 (RW): QUIET_MIN
    // 0x8C (RW): QUIET_MAX
    // 0x90 (RO): CURRENT_QUIET_LEN
    // 0x94 (RO): LAST_ZERO_GAP
    // 0x98 (RO): LAST_FIRE_DIFF
    // 0x9C (RO): LAST_FIRE_INT
    // 0xA0 (RO): LAST_CAUSE_CODE
    //      0 = none
    //      1 = arc_by_density
    //      2 = arc_by_standard
    //      3 = thermal
    //      4 = reserved (legacy data_fault slot)
    //      5 = quiet_zone
    // 0xA4 (RW): PROFILE_CTRL
    //      [3:0] active profile id (write low nibble to apply)
    //      [7:4] boot profile id




    // có chưa định nghĩa địa chỉ thanh ghi APB
    localparam logic [7:0] ADDR_STATUS        = 8'h00;
    localparam logic [7:0] ADDR_DIFF_THRESH   = 8'h04;
    localparam logic [7:0] ADDR_INT_LIMIT     = 8'h08;
    localparam logic [7:0] ADDR_DECAY_RATE    = 8'h0C;
    localparam logic [7:0] ADDR_BASE_ATTACK   = 8'h10;
    localparam logic [7:0] ADDR_CUR_DIFF      = 8'h14;
    localparam logic [7:0] ADDR_CUR_INT       = 8'h18;
    localparam logic [7:0] ADDR_PEAK_DIFF     = 8'h1C;
    localparam logic [7:0] ADDR_PEAK_INT      = 8'h20;
    localparam logic [7:0] ADDR_EVENT_COUNT   = 8'h24;
    localparam logic [7:0] ADDR_CLEAR         = 8'h28;
    localparam logic [7:0] ADDR_EXCESS_SHIFT  = 8'h2C;
    localparam logic [7:0] ADDR_ATTACK_CLAMP  = 8'h30;
    localparam logic [7:0] ADDR_CUR_ATTACK    = 8'h34;
    localparam logic [7:0] ADDR_WIN_LEN       = 8'h38;
    localparam logic [7:0] ADDR_SPIKE_WARN    = 8'h3C;
    localparam logic [7:0] ADDR_SPIKE_FIRE    = 8'h40;
    localparam logic [7:0] ADDR_CUR_SPIKE_SUM = 8'h44;
    localparam logic [7:0] ADDR_PEAK_SPIKE_SUM = 8'h48;
    localparam logic [7:0] ADDR_PEAK_DIFF_FIRE = 8'h4C;
    localparam logic [7:0] ADDR_ALPHA_SHIFT   = 8'h50;
    localparam logic [7:0] ADDR_GAIN_SHIFT    = 8'h54;
    localparam logic [7:0] ADDR_CUR_NOISE     = 8'h58;
    localparam logic [7:0] ADDR_EFFECTIVE_THRESH = 8'h5C;
    localparam logic [7:0] ADDR_STREAM_STATUS = 8'h60;
    localparam logic [7:0] ADDR_STREAM_RESTART_COUNT = 8'h64;
    localparam logic [7:0] ADDR_HOT_BASE      = 8'h68;
    localparam logic [7:0] ADDR_HOT_ATTACK    = 8'h6C;
    localparam logic [7:0] ADDR_HOT_DECAY     = 8'h70;
    localparam logic [7:0] ADDR_HOT_LIMIT     = 8'h74;
    localparam logic [7:0] ADDR_ENV_SHIFT     = 8'h78;
    localparam logic [7:0] ADDR_CUR_ENV_LP    = 8'h7C;
    localparam logic [7:0] ADDR_CUR_HOTSPOT   = 8'h80;
    localparam logic [7:0] ADDR_ZERO_BAND     = 8'h84;
    localparam logic [7:0] ADDR_QUIET_MIN     = 8'h88;
    localparam logic [7:0] ADDR_QUIET_MAX     = 8'h8C;
    localparam logic [7:0] ADDR_CUR_QUIET_LEN = 8'h90;
    localparam logic [7:0] ADDR_LAST_ZERO_GAP = 8'h94;
    localparam logic [7:0] ADDR_LAST_FIRE_DIFF = 8'h98;
    localparam logic [7:0] ADDR_LAST_FIRE_INT  = 8'h9C;
    localparam logic [7:0] ADDR_LAST_CAUSE     = 8'hA0;
    localparam logic [7:0] ADDR_PROFILE_CTRL   = 8'hA4;

    localparam logic [3:0] CAUSE_NONE         = 4'd0;//
    localparam logic [3:0] CAUSE_ARC_DENSITY  = 4'd1;//
    localparam logic [3:0] CAUSE_ARC_STANDARD = 4'd2;//khi debug bạn không chỉ biết “có lỗi”, mà còn biết lỗi đến từ: arc thường arc theo mật độ spike thermal/glowingquiet-zone lỗi dữ liệu
    localparam logic [3:0] CAUSE_THERMAL      = 4'd3;//
    localparam logic [3:0] CAUSE_QUIET_ZONE   = 4'd5;//
    localparam logic [3:0] PROFILE_SAFE_RESET   = 4'd0;
    localparam logic [3:0] PROFILE_ARC_BALANCED = 4'd1;
    localparam logic [3:0] PROFILE_THERMAL_BAL  = 4'd2;
    localparam logic [3:0] PROFILE_LAB_FULL     = 4'd3;
    localparam logic [3:0] DEFAULT_BOOT_PROFILE = PROFILE_ARC_BALANCED;

    localparam [15:0] DEFAULT_BASE_THRESH   = 16'd50;
    localparam [15:0] DEFAULT_LIMIT         = 16'd1000;
    localparam [7:0]  DEFAULT_DECAY         = 8'd1;
    localparam [15:0] DEFAULT_BASE_ATTACK   = 16'd10;
    localparam [4:0]  DEFAULT_EXCESS_SHIFT  = 5'd4;
    localparam [15:0] DEFAULT_ATTACK_CLAMP  = 16'd15;
    localparam logic [6:0] DEFAULT_WIN_LEN  = 7'd32;
    localparam logic [6:0] DEFAULT_SPIKE_SUM_WARN = 7'd0;
    localparam logic [6:0] DEFAULT_SPIKE_SUM_FIRE = 7'd0;
    localparam logic [15:0] DEFAULT_PEAK_DIFF_FIRE_THRESH = 16'd75;
    localparam logic [4:0] DEFAULT_ALPHA_SHIFT = 5'd2;
    localparam logic [4:0] DEFAULT_GAIN_SHIFT  = 5'd16;
    localparam logic [15:0] DEFAULT_HOT_BASE   = 16'd500;
    localparam logic [15:0] DEFAULT_HOT_ATTACK = 16'd32;
    localparam logic [15:0] DEFAULT_HOT_DECAY  = 16'd4;
    localparam logic [15:0] DEFAULT_HOT_LIMIT  = 16'd96;
    localparam logic [4:0]  DEFAULT_ENV_SHIFT  = 5'd4;
    localparam logic [15:0] DEFAULT_ZERO_BAND  = 16'd0;
    localparam logic [7:0]  DEFAULT_QUIET_MIN  = 8'd2;
    localparam logic [7:0]  DEFAULT_QUIET_MAX  = 8'd6;
    localparam logic [6:0] MAX_WIN_LEN_CFG  = 7'd64;

    localparam int unsigned ACC_W = CNT_WIDTH + 1;
    localparam int unsigned MAX_WIN_LEN = 64;
    localparam int unsigned SPIKE_SUM_W = $clog2(MAX_WIN_LEN + 1);
    localparam int unsigned QUIET_W = 8;
    localparam int unsigned QUIET_CONF_W = 2;
    localparam logic [QUIET_CONF_W-1:0] QUIET_CONF_FIRE_LEVEL = 2'd2;
    localparam int unsigned RESTART_HOLDOFF_SAMPLES = 1;
    localparam int unsigned RESTART_HOLDOFF_W = (RESTART_HOLDOFF_SAMPLES > 0) ? $clog2(RESTART_HOLDOFF_SAMPLES + 1) : 1;

    logic [15:0] reg_base_thresh;
    logic [15:0] reg_diff_threshold; // Backward-compatible alias for legacy TB/debug
    logic [15:0] reg_int_limit;
    logic [7:0]  reg_decay_rate;
    logic [15:0] reg_base_attack;
    logic [4:0]  reg_excess_shift;
    logic [15:0] reg_attack_clamp;
    logic [6:0]  reg_win_len;
    logic [SPIKE_SUM_W-1:0] reg_spike_sum_warn;
    logic [SPIKE_SUM_W-1:0] reg_spike_sum_fire;
    logic [15:0] reg_peak_diff_fire_thresh;
    logic [4:0]  reg_alpha_shift;
    logic [4:0]  reg_gain_shift;
    logic [15:0] reg_hot_base;
    logic [15:0] reg_hot_attack;
    logic [15:0] reg_hot_decay;
    logic [15:0] reg_hot_limit;
    logic [4:0]  reg_env_shift;
    logic [15:0] reg_zero_band;
    logic [QUIET_W-1:0] reg_quiet_min;
    logic [QUIET_W-1:0] reg_quiet_max;
    logic [1:0]  reg_status;
    logic [3:0]  current_profile_q;

    // =====================================================================
    // 2. DSP CORE STATE / TELEMETRY
    // =====================================================================
    logic signed [DATA_WIDTH-1:0] sample_prev_q;
    logic                         sample_pair_valid;

    logic signed [DATA_WIDTH:0]   diff_raw_comb;
    logic [DATA_WIDTH-1:0]        diff_abs_comb;
    logic [DATA_WIDTH-1:0]        diff_abs;
    logic [DATA_WIDTH-1:0]        diff_excess_comb;
    logic                         is_spike_detected;

    logic [CNT_WIDTH-1:0]         integrator;
    logic [CNT_WIDTH-1:0]         peak_integrator;
    logic [DATA_WIDTH-1:0]        peak_diff;
    logic                         fire_latched;
    logic [15:0]                  event_count;
    logic [15:0]                  stream_restart_count;
    logic [CNT_WIDTH-1:0]         attack_step_q;
    logic [MAX_WIN_LEN-1:0]       spike_hist_q;
    logic [SPIKE_SUM_W-1:0]       spike_sum_q;
    logic [SPIKE_SUM_W-1:0]       peak_spike_sum;
    logic [RESTART_HOLDOFF_W-1:0] restart_holdoff_q;

    logic [CNT_WIDTH-1:0]         diff_excess_ext;
    logic [CNT_WIDTH-1:0]         excess_shifted_comb;
    logic [CNT_WIDTH-1:0]         excess_attack_term;
    logic [ACC_W-1:0]             attack_step_acc;
    logic [CNT_WIDTH-1:0]         attack_step_comb;
    logic [ACC_W-1:0]             attack_candidate;
    logic [CNT_WIDTH-1:0]         integrator_after_attack;
    logic [CNT_WIDTH-1:0]         integrator_after_decay;
    logic [CNT_WIDTH-1:0]         integrator_next_comb;
    logic [CNT_WIDTH-1:0]         warn_threshold;
    logic                         outgoing_spike_bit;
    logic [SPIKE_SUM_W-1:0]       spike_sum_next_comb;
    logic [DATA_WIDTH-1:0]        peak_diff_next_comb;
    logic                         warn_condition_comb;
    logic                         fire_condition_comb;
    logic                         detector_holdoff_active;
    logic                         detector_sample_blocked;
    logic [DATA_WIDTH-1:0]        noise_floor_q;
    logic [DATA_WIDTH-1:0]        abs_sample_comb;
    logic [DATA_WIDTH-1:0]        env_lp_q;
    logic signed [DATA_WIDTH:0]   noise_floor_error_comb;
    logic signed [DATA_WIDTH:0]   noise_floor_adjust_comb;
    logic signed [DATA_WIDTH:0]   noise_floor_acc_comb;
    logic [DATA_WIDTH-1:0]        noise_floor_next_comb;
    logic signed [DATA_WIDTH:0]   env_error_comb;
    logic signed [DATA_WIDTH:0]   env_adjust_comb;
    logic signed [DATA_WIDTH:0]   env_acc_comb;
    logic [DATA_WIDTH-1:0]        env_lp_next_comb;
    logic [DATA_WIDTH-1:0]        noise_floor_gain_term;
    logic [DATA_WIDTH:0]          effective_thresh_acc;
    logic [DATA_WIDTH-1:0]        effective_thresh_comb;
    logic                         thermal_hot_comb;
    logic [ACC_W-1:0]             hotspot_attack_candidate;
    logic [CNT_WIDTH-1:0]         hotspot_after_attack;
    logic [CNT_WIDTH-1:0]         hotspot_after_decay;
    logic [CNT_WIDTH-1:0]         hotspot_score_q;
    logic [CNT_WIDTH-1:0]         hotspot_score_next_comb;
    logic                         thermal_fire_comb;
    logic [QUIET_W-1:0]           quiet_len_q;
    logic [QUIET_W-1:0]           last_zero_gap_q;
    logic [QUIET_CONF_W-1:0]      quiet_confidence_q;
    logic [DATA_WIDTH-1:0]        quiet_recent_peak_q;
    logic [DATA_WIDTH-1:0]        abs_prev_sample_comb;
    logic                         prev_near_zero_comb;
    logic                         near_zero_comb;
    logic                         sign_change_comb;
    logic [QUIET_W-1:0]           quiet_len_next_comb;
    logic [QUIET_W-1:0]           quiet_gap_capture_comb;
    logic [DATA_WIDTH-1:0]        quiet_recent_peak_next_comb;
    logic                         quiet_zone_match_comb;
    logic [QUIET_CONF_W-1:0]      quiet_confidence_next_comb;
    logic                         quiet_fire_comb;
    logic                         density_fire_comb;
    logic                         standard_arc_fire_comb;
    logic [3:0]                   trip_cause_code_comb;
    logic [DATA_WIDTH-1:0]        last_fire_diff_q;
    logic [CNT_WIDTH-1:0]         last_fire_int_q;
    logic [3:0]                   last_cause_code_q;
    logic                         stage_a_sample_valid_q;
    logic                         stage_a_pair_valid_q;
    logic [DATA_WIDTH-1:0]        stage_a_diff_abs_q;
    logic [DATA_WIDTH-1:0]        stage_a_noise_floor_next_q;
    logic [DATA_WIDTH-1:0]        stage_a_effective_thresh_q;
    logic [QUIET_W-1:0]           stage_a_quiet_len_next_q;
    logic [QUIET_W-1:0]           stage_a_quiet_gap_capture_q;
    logic [DATA_WIDTH-1:0]        stage_a_quiet_recent_peak_next_q;
    logic [DATA_WIDTH-1:0]        stage_a_env_lp_next_q;
    logic                         stage_a_sign_change_q;

    // =====================================================================
    // 3. APB COMMAND DECODE
    // =====================================================================
    logic       apb_access;
    logic       apb_write;
    logic [7:0] apb_addr;
    logic       clear_latched_cmd;
    logic       clear_peaks_cmd;
    logic       clear_events_cmd;
    logic       clear_restart_count_cmd;

    assign apb_access = apb_slv.psel && apb_slv.penable;
    assign apb_write  = apb_access && apb_slv.pwrite;
    assign apb_addr   = apb_slv.paddr[7:0];

    assign clear_latched_cmd = apb_write && (apb_addr == ADDR_CLEAR) && apb_slv.pwdata[0];
    assign clear_peaks_cmd   = apb_write && (apb_addr == ADDR_CLEAR) && apb_slv.pwdata[1];
    assign clear_events_cmd  = apb_write && (apb_addr == ADDR_CLEAR) && apb_slv.pwdata[2];
    assign clear_restart_count_cmd = apb_write && (apb_addr == ADDR_CLEAR) && apb_slv.pwdata[4];

    // =====================================================================
    // 4. STAGE A - FRONT-END FEATURE EXTRACTION
    // =====================================================================
    function automatic logic [DATA_WIDTH-1:0] abs_diff(
        input logic signed [DATA_WIDTH:0] value
    );
        logic signed [DATA_WIDTH:0] magnitude;
        begin
            magnitude = (value < 0) ? -value : value;
            abs_diff  = magnitude[DATA_WIDTH-1:0];
        end
    endfunction

    function automatic logic [6:0] clamp_win_len(input logic [31:0] raw_value);
        logic [6:0] raw_small;
        begin
            raw_small = raw_value[6:0];
            if (raw_small == 7'd0)
                clamp_win_len = 7'd1;
            else if (raw_small > MAX_WIN_LEN_CFG)
                clamp_win_len = MAX_WIN_LEN_CFG;
            else
                clamp_win_len = raw_small;
        end
    endfunction

    function automatic logic [SPIKE_SUM_W-1:0] clamp_spike_level(
        input logic [31:0] raw_value,
        input logic [6:0]  limit_value
    );
        logic [SPIKE_SUM_W-1:0] raw_small;
        logic [SPIKE_SUM_W-1:0] limit_small;
        begin
            raw_small   = raw_value[SPIKE_SUM_W-1:0];
            limit_small = limit_value[SPIKE_SUM_W-1:0];

            if (raw_small > limit_small)
                clamp_spike_level = limit_small;
            else
                clamp_spike_level = raw_small;
        end
    endfunction

    function automatic logic [3:0] sanitize_profile_id(input logic [3:0] raw_profile);
        begin
            case (raw_profile)
                PROFILE_SAFE_RESET,
                PROFILE_ARC_BALANCED,
                PROFILE_THERMAL_BAL,
                PROFILE_LAB_FULL: sanitize_profile_id = raw_profile;
                default: sanitize_profile_id = PROFILE_SAFE_RESET;
            endcase
        end
    endfunction

    task automatic clear_detector_runtime_state(input logic clear_events_i);
        begin
            sample_prev_q         <= '0;
            sample_pair_valid     <= 1'b0;
            diff_abs              <= '0;
            peak_diff             <= '0;
            integrator            <= '0;
            peak_integrator       <= '0;
            attack_step_q         <= '0;
            spike_hist_q          <= '0;
            spike_sum_q           <= '0;
            peak_spike_sum        <= '0;
            noise_floor_q         <= '0;
            env_lp_q              <= '0;
            hotspot_score_q       <= '0;
            quiet_len_q           <= '0;
            last_zero_gap_q       <= '0;
            quiet_confidence_q    <= '0;
            quiet_recent_peak_q   <= '0;
            fire_latched          <= 1'b0;
            last_fire_diff_q      <= '0;
            last_fire_int_q       <= '0;
            last_cause_code_q     <= CAUSE_NONE;
            stage_a_sample_valid_q <= 1'b0;
            stage_a_pair_valid_q   <= 1'b0;
            stage_a_diff_abs_q     <= '0;
            stage_a_noise_floor_next_q <= '0;
            stage_a_effective_thresh_q <= '0;
            stage_a_quiet_len_next_q <= '0;
            stage_a_quiet_gap_capture_q <= '0;
            stage_a_quiet_recent_peak_next_q <= '0;
            stage_a_env_lp_next_q  <= '0;
            stage_a_sign_change_q  <= 1'b0;
            reg_status             <= 2'b00;
            irq_arc_o              <= 1'b0;
            restart_holdoff_q      <= '0;
            if (clear_events_i)
                event_count <= 16'd0;
        end
    endtask

    task automatic apply_profile(input logic [3:0] raw_profile_id, input logic clear_events_i);
        logic [3:0] profile_id;
        begin
            profile_id = sanitize_profile_id(raw_profile_id);
            current_profile_q <= profile_id;

            unique case (profile_id)
                PROFILE_ARC_BALANCED: begin
                    reg_base_thresh           <= 16'd80;
                    reg_int_limit             <= DEFAULT_LIMIT;
                    reg_decay_rate            <= DEFAULT_DECAY;
                    reg_base_attack           <= DEFAULT_BASE_ATTACK;
                    reg_excess_shift          <= DEFAULT_EXCESS_SHIFT;
                    reg_attack_clamp          <= DEFAULT_ATTACK_CLAMP;
                    reg_win_len               <= 7'd32;
                    reg_spike_sum_warn        <= SPIKE_SUM_W'(3);
                    reg_spike_sum_fire        <= SPIKE_SUM_W'(20);
                    reg_peak_diff_fire_thresh <= 16'd220;
                    reg_alpha_shift           <= DEFAULT_ALPHA_SHIFT;
                    reg_gain_shift            <= 5'd3;
                    reg_hot_base              <= DEFAULT_HOT_BASE;
                    reg_hot_attack            <= DEFAULT_HOT_ATTACK;
                    reg_hot_decay             <= DEFAULT_HOT_DECAY;
                    reg_hot_limit             <= DEFAULT_HOT_LIMIT;
                    reg_env_shift             <= DEFAULT_ENV_SHIFT;
                    reg_zero_band             <= 16'd6;
                    reg_quiet_min             <= 8'd2;
                    reg_quiet_max             <= 8'd4;
                end
                PROFILE_THERMAL_BAL: begin
                    reg_base_thresh           <= 16'd60;
                    reg_int_limit             <= DEFAULT_LIMIT;
                    reg_decay_rate            <= DEFAULT_DECAY;
                    reg_base_attack           <= DEFAULT_BASE_ATTACK;
                    reg_excess_shift          <= DEFAULT_EXCESS_SHIFT;
                    reg_attack_clamp          <= DEFAULT_ATTACK_CLAMP;
                    reg_win_len               <= 7'd32;
                    reg_spike_sum_warn        <= SPIKE_SUM_W'(2);
                    reg_spike_sum_fire        <= SPIKE_SUM_W'(14);
                    reg_peak_diff_fire_thresh <= 16'd180;
                    reg_alpha_shift           <= DEFAULT_ALPHA_SHIFT;
                    reg_gain_shift            <= 5'd5;
                    reg_hot_base              <= 16'd420;
                    reg_hot_attack            <= 16'd32;
                    reg_hot_decay             <= 16'd4;
                    reg_hot_limit             <= 16'd80;
                    reg_env_shift             <= DEFAULT_ENV_SHIFT;
                    reg_zero_band             <= 16'd6;
                    reg_quiet_min             <= 8'd2;
                    reg_quiet_max             <= 8'd4;
                end
                PROFILE_LAB_FULL: begin
                    reg_base_thresh           <= 16'd45;
                    reg_int_limit             <= DEFAULT_LIMIT;
                    reg_decay_rate            <= DEFAULT_DECAY;
                    reg_base_attack           <= DEFAULT_BASE_ATTACK;
                    reg_excess_shift          <= DEFAULT_EXCESS_SHIFT;
                    reg_attack_clamp          <= DEFAULT_ATTACK_CLAMP;
                    reg_win_len               <= 7'd32;
                    reg_spike_sum_warn        <= SPIKE_SUM_W'(2);
                    reg_spike_sum_fire        <= SPIKE_SUM_W'(6);
                    reg_peak_diff_fire_thresh <= 16'd120;
                    reg_alpha_shift           <= DEFAULT_ALPHA_SHIFT;
                    reg_gain_shift            <= 5'd4;
                    reg_hot_base              <= 16'd360;
                    reg_hot_attack            <= 16'd40;
                    reg_hot_decay             <= 16'd4;
                    reg_hot_limit             <= 16'd72;
                    reg_env_shift             <= DEFAULT_ENV_SHIFT;
                    reg_zero_band             <= 16'd10;
                    reg_quiet_min             <= 8'd2;
                    reg_quiet_max             <= 8'd5;
                end
                default: begin
                    reg_base_thresh           <= DEFAULT_BASE_THRESH;
                    reg_int_limit             <= DEFAULT_LIMIT;
                    reg_decay_rate            <= DEFAULT_DECAY;
                    reg_base_attack           <= DEFAULT_BASE_ATTACK;
                    reg_excess_shift          <= DEFAULT_EXCESS_SHIFT;
                    reg_attack_clamp          <= DEFAULT_ATTACK_CLAMP;
                    reg_win_len               <= DEFAULT_WIN_LEN;
                    reg_spike_sum_warn        <= DEFAULT_SPIKE_SUM_WARN[SPIKE_SUM_W-1:0];
                    reg_spike_sum_fire        <= DEFAULT_SPIKE_SUM_FIRE[SPIKE_SUM_W-1:0];
                    reg_peak_diff_fire_thresh <= DEFAULT_PEAK_DIFF_FIRE_THRESH;
                    reg_alpha_shift           <= DEFAULT_ALPHA_SHIFT;
                    reg_gain_shift            <= DEFAULT_GAIN_SHIFT;
                    reg_hot_base              <= DEFAULT_HOT_BASE;
                    reg_hot_attack            <= DEFAULT_HOT_ATTACK;
                    reg_hot_decay             <= DEFAULT_HOT_DECAY;
                    reg_hot_limit             <= DEFAULT_HOT_LIMIT;
                    reg_env_shift             <= DEFAULT_ENV_SHIFT;
                    reg_zero_band             <= DEFAULT_ZERO_BAND;
                    reg_quiet_min             <= DEFAULT_QUIET_MIN;
                    reg_quiet_max             <= DEFAULT_QUIET_MAX;
                end
            endcase

            clear_detector_runtime_state(clear_events_i);
        end
    endtask

    assign diff_raw_comb = $signed({adc_data_i[DATA_WIDTH-1], adc_data_i}) -
                           $signed({sample_prev_q[DATA_WIDTH-1], sample_prev_q});
    assign diff_abs_comb = abs_diff(diff_raw_comb);
    assign abs_sample_comb = abs_diff($signed({adc_data_i[DATA_WIDTH-1], adc_data_i}));
    assign abs_prev_sample_comb = abs_diff($signed({sample_prev_q[DATA_WIDTH-1], sample_prev_q}));
    assign near_zero_comb = (reg_zero_band != '0) && adc_valid_i && (abs_sample_comb < reg_zero_band);
    assign prev_near_zero_comb = (reg_zero_band != '0) && sample_pair_valid && (abs_prev_sample_comb < reg_zero_band);
    assign sign_change_comb = sample_pair_valid && adc_valid_i &&
                              (adc_data_i[DATA_WIDTH-1] != sample_prev_q[DATA_WIDTH-1]);

    assign noise_floor_error_comb  = $signed({1'b0, diff_abs_comb}) - $signed({1'b0, noise_floor_q});
    assign noise_floor_adjust_comb = noise_floor_error_comb >>> reg_alpha_shift;
    assign noise_floor_acc_comb    = $signed({1'b0, noise_floor_q}) + noise_floor_adjust_comb;
    assign env_error_comb          = $signed({1'b0, abs_sample_comb}) - $signed({1'b0, env_lp_q});
    assign env_adjust_comb         = env_error_comb >>> reg_env_shift;
    assign env_acc_comb            = $signed({1'b0, env_lp_q}) + env_adjust_comb;

    always_comb begin
        if (!sample_pair_valid || !adc_valid_i) begin
            noise_floor_next_comb = noise_floor_q;
        end else if (noise_floor_acc_comb < 0) begin
            noise_floor_next_comb = '0;
        end else if (noise_floor_acc_comb > $signed({1'b0, {DATA_WIDTH{1'b1}}})) begin
            noise_floor_next_comb = {DATA_WIDTH{1'b1}};
        end else begin
            noise_floor_next_comb = noise_floor_acc_comb[DATA_WIDTH-1:0];
        end
    end

    always_comb begin
        if (!adc_valid_i) begin
            env_lp_next_comb = env_lp_q;
        end else if (env_acc_comb < 0) begin
            env_lp_next_comb = '0;
        end else if (env_acc_comb > $signed({1'b0, {DATA_WIDTH{1'b1}}})) begin
            env_lp_next_comb = {DATA_WIDTH{1'b1}};
        end else begin
            env_lp_next_comb = env_acc_comb[DATA_WIDTH-1:0];
        end
    end

    assign noise_floor_gain_term = (reg_gain_shift >= DATA_WIDTH) ? '0 : (noise_floor_q >> reg_gain_shift);
    assign effective_thresh_acc  = {1'b0, reg_base_thresh} + {1'b0, noise_floor_gain_term};
    assign effective_thresh_comb = effective_thresh_acc[DATA_WIDTH] ? {DATA_WIDTH{1'b1}}
                                                                    : effective_thresh_acc[DATA_WIDTH-1:0];

    always_comb begin
        quiet_len_next_comb = quiet_len_q;
        if (adc_valid_i) begin
            if (near_zero_comb) begin
                if (quiet_len_q == {QUIET_W{1'b1}})
                    quiet_len_next_comb = quiet_len_q;
                else
                    quiet_len_next_comb = quiet_len_q + QUIET_W'(1);
            end else begin
                quiet_len_next_comb = '0;
            end
        end
    end

    assign quiet_gap_capture_comb = near_zero_comb ? quiet_len_next_comb : quiet_len_q;
    assign quiet_recent_peak_next_comb =
        (sample_pair_valid && adc_valid_i && (diff_abs_comb > quiet_recent_peak_q))
            ? diff_abs_comb
            : quiet_recent_peak_q;

    // =====================================================================
    // 5. STAGE B - DECISION / SCORING
    // =====================================================================
    // Phase 1 fix remains intact, but now spike evaluation is fed by
    // registered Stage A features for a shorter critical path.
    assign is_spike_detected = stage_a_pair_valid_q && (stage_a_diff_abs_q > stage_a_effective_thresh_q);

    // Weighted attack upgrade:
    // excess = max(0, diff_abs - threshold)
    // attack = base_attack + min(attack_clamp, excess >> excess_shift)
    assign diff_excess_comb   = (stage_a_diff_abs_q > stage_a_effective_thresh_q)
                              ? (stage_a_diff_abs_q - stage_a_effective_thresh_q)
                              : '0;
    assign diff_excess_ext    = diff_excess_comb;
    assign excess_shifted_comb = (reg_excess_shift >= CNT_WIDTH) ? '0
                                                              : (diff_excess_ext >> reg_excess_shift);
    assign excess_attack_term = (excess_shifted_comb > reg_attack_clamp)
                              ? CNT_WIDTH'(reg_attack_clamp)
                              : excess_shifted_comb;
    assign attack_step_acc    = ACC_W'(reg_base_attack) + ACC_W'(excess_attack_term);
    assign attack_step_comb   = attack_step_acc[CNT_WIDTH-1:0];

    assign attack_candidate        = ACC_W'(integrator) + ACC_W'(attack_step_comb);
    assign integrator_after_attack = (attack_candidate >= ACC_W'(reg_int_limit))
                                   ? CNT_WIDTH'(reg_int_limit)
                                   : attack_candidate[CNT_WIDTH-1:0];
    assign integrator_after_decay  = (integrator <= CNT_WIDTH'(reg_decay_rate))
                                   ? '0
                                   : (integrator - CNT_WIDTH'(reg_decay_rate));
    assign integrator_next_comb    = is_spike_detected ? integrator_after_attack
                                                       : integrator_after_decay;
    assign warn_threshold          = CNT_WIDTH'(reg_int_limit >> 1);
    assign outgoing_spike_bit      = spike_hist_q[reg_win_len - 1];
    assign peak_diff_next_comb     = (stage_a_pair_valid_q && (stage_a_diff_abs_q > peak_diff))
                                   ? stage_a_diff_abs_q
                                   : peak_diff;

    always_comb begin
        spike_sum_next_comb = spike_sum_q;
        if (stage_a_sample_valid_q) begin
            if (is_spike_detected && !outgoing_spike_bit)
                spike_sum_next_comb = spike_sum_q + SPIKE_SUM_W'(1);
            else if (!is_spike_detected && outgoing_spike_bit)
                spike_sum_next_comb = spike_sum_q - SPIKE_SUM_W'(1);
        end
    end

    assign quiet_zone_match_comb =
        stage_a_sign_change_q &&
        (reg_zero_band != '0) &&
        (stage_a_quiet_gap_capture_q >= reg_quiet_min) &&
        (stage_a_quiet_gap_capture_q <= reg_quiet_max) &&
        (stage_a_quiet_recent_peak_next_q >= reg_peak_diff_fire_thresh) &&
        (spike_sum_next_comb >= ((reg_spike_sum_warn == '0) ? SPIKE_SUM_W'(1) : reg_spike_sum_warn));

    always_comb begin
        quiet_confidence_next_comb = quiet_confidence_q;
        if (quiet_zone_match_comb && (quiet_confidence_q != {QUIET_CONF_W{1'b1}}))
            quiet_confidence_next_comb = quiet_confidence_q + QUIET_CONF_W'(1);
    end

    assign quiet_fire_comb = (quiet_confidence_next_comb >= QUIET_CONF_FIRE_LEVEL);
    assign density_fire_comb = (reg_spike_sum_fire != '0) &&
                               (spike_sum_next_comb >= reg_spike_sum_fire) &&
                               (peak_diff_next_comb >= reg_peak_diff_fire_thresh);
    assign standard_arc_fire_comb = (integrator_next_comb >= CNT_WIDTH'(reg_int_limit));

    assign warn_condition_comb = ((integrator_next_comb > warn_threshold) &&
                                  ((reg_spike_sum_warn == '0) || (spike_sum_next_comb >= reg_spike_sum_warn))) ||
                                 quiet_zone_match_comb;
    assign fire_condition_comb = standard_arc_fire_comb ||
                                 density_fire_comb ||
                                 quiet_fire_comb;
    assign thermal_hot_comb      = (stage_a_env_lp_next_q > reg_hot_base);
    assign hotspot_attack_candidate = ACC_W'(hotspot_score_q) + ACC_W'(reg_hot_attack);
    assign hotspot_after_attack  = (hotspot_attack_candidate >= ACC_W'(reg_hot_limit))
                                 ? CNT_WIDTH'(reg_hot_limit)
                                 : hotspot_attack_candidate[CNT_WIDTH-1:0];
    assign hotspot_after_decay   = (hotspot_score_q <= CNT_WIDTH'(reg_hot_decay))
                                 ? '0
                                 : (hotspot_score_q - CNT_WIDTH'(reg_hot_decay));
    assign hotspot_score_next_comb = thermal_hot_comb ? hotspot_after_attack
                                                      : hotspot_after_decay;
    assign thermal_fire_comb = (hotspot_score_next_comb >= CNT_WIDTH'(reg_hot_limit));
    assign trip_cause_code_comb = thermal_fire_comb      ? CAUSE_THERMAL :
                                  quiet_fire_comb        ? CAUSE_QUIET_ZONE :
                                  density_fire_comb      ? CAUSE_ARC_DENSITY :
                                  standard_arc_fire_comb ? CAUSE_ARC_STANDARD :
                                                           CAUSE_NONE;
    assign reg_diff_threshold    = reg_base_thresh;
    assign detector_holdoff_active = (restart_holdoff_q != '0);
    assign detector_sample_blocked = detector_holdoff_active;

    // =====================================================================
    // 6. APB + PIPELINED DSP SEQUENTIAL LOGIC
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            apply_profile(DEFAULT_BOOT_PROFILE, 1'b1);
            stream_restart_count <= 16'd0;

            apb_slv.pready     <= 1'b0;
            apb_slv.prdata     <= 32'd0;
            apb_slv.pslverr    <= 1'b0;
        end else begin
            apb_slv.pready  <= 1'b0;
            apb_slv.prdata  <= 32'd0;
            apb_slv.pslverr <= 1'b0;

            if (apb_access) begin
                apb_slv.pready <= 1'b1;

                if (apb_write) begin
                    case (apb_addr)
                        ADDR_DIFF_THRESH:  reg_base_thresh    <= apb_slv.pwdata[15:0];
                        ADDR_INT_LIMIT:    reg_int_limit      <= apb_slv.pwdata[15:0];
                        ADDR_DECAY_RATE:   reg_decay_rate     <= apb_slv.pwdata[7:0];
                        ADDR_BASE_ATTACK:  reg_base_attack    <= apb_slv.pwdata[15:0];
                        ADDR_EXCESS_SHIFT: reg_excess_shift   <= apb_slv.pwdata[4:0];
                        ADDR_ATTACK_CLAMP: reg_attack_clamp   <= apb_slv.pwdata[15:0];
                        ADDR_WIN_LEN: begin
                            reg_win_len        <= clamp_win_len(apb_slv.pwdata);
                            reg_spike_sum_warn <= (reg_spike_sum_warn > clamp_win_len(apb_slv.pwdata)) ? clamp_win_len(apb_slv.pwdata)[SPIKE_SUM_W-1:0] : reg_spike_sum_warn;
                            reg_spike_sum_fire <= (reg_spike_sum_fire > clamp_win_len(apb_slv.pwdata)) ? clamp_win_len(apb_slv.pwdata)[SPIKE_SUM_W-1:0] : reg_spike_sum_fire;
                            spike_hist_q       <= '0;
                            spike_sum_q        <= '0;
                            peak_spike_sum     <= '0;
                        end
                        ADDR_SPIKE_WARN:    reg_spike_sum_warn <= clamp_spike_level(apb_slv.pwdata, reg_win_len);
                        ADDR_SPIKE_FIRE:    reg_spike_sum_fire <= clamp_spike_level(apb_slv.pwdata, reg_win_len);
                        ADDR_PEAK_DIFF_FIRE: reg_peak_diff_fire_thresh <= apb_slv.pwdata[15:0];
                        ADDR_ALPHA_SHIFT:    reg_alpha_shift <= apb_slv.pwdata[4:0];
                        ADDR_GAIN_SHIFT:     reg_gain_shift  <= apb_slv.pwdata[4:0];
                        ADDR_HOT_BASE:       reg_hot_base    <= apb_slv.pwdata[15:0];
                        ADDR_HOT_ATTACK:     reg_hot_attack  <= apb_slv.pwdata[15:0];
                        ADDR_HOT_DECAY:      reg_hot_decay   <= apb_slv.pwdata[15:0];
                        ADDR_HOT_LIMIT:      reg_hot_limit   <= apb_slv.pwdata[15:0];
                        ADDR_ENV_SHIFT:      reg_env_shift   <= apb_slv.pwdata[4:0];
                        ADDR_ZERO_BAND:      reg_zero_band   <= apb_slv.pwdata[15:0];
                        ADDR_QUIET_MIN:      reg_quiet_min   <= apb_slv.pwdata[QUIET_W-1:0];
                        ADDR_QUIET_MAX:      reg_quiet_max   <= apb_slv.pwdata[QUIET_W-1:0];
                        ADDR_PROFILE_CTRL:   apply_profile(apb_slv.pwdata[3:0], 1'b0);
                        default: ;
                    endcase
                end else begin
                    case (apb_addr)
                        ADDR_STATUS:       apb_slv.prdata <= {27'd0, sample_pair_valid, fire_latched, irq_arc_o, reg_status};
                        ADDR_DIFF_THRESH:  apb_slv.prdata <= {16'd0, reg_base_thresh};
                        ADDR_INT_LIMIT:    apb_slv.prdata <= {16'd0, reg_int_limit};
                        ADDR_DECAY_RATE:   apb_slv.prdata <= {24'd0, reg_decay_rate};
                        ADDR_BASE_ATTACK:  apb_slv.prdata <= {16'd0, reg_base_attack};
                        ADDR_CUR_DIFF:     apb_slv.prdata <= {16'd0, diff_abs};
                        ADDR_CUR_INT:      apb_slv.prdata <= {16'd0, integrator};
                        ADDR_PEAK_DIFF:    apb_slv.prdata <= {16'd0, peak_diff};
                        ADDR_PEAK_INT:     apb_slv.prdata <= {16'd0, peak_integrator};
                        ADDR_EVENT_COUNT:  apb_slv.prdata <= {16'd0, event_count};
                        ADDR_EXCESS_SHIFT: apb_slv.prdata <= {27'd0, reg_excess_shift};
                        ADDR_ATTACK_CLAMP: apb_slv.prdata <= {16'd0, reg_attack_clamp};
                        ADDR_CUR_ATTACK:   apb_slv.prdata <= {16'd0, attack_step_q};
                        ADDR_WIN_LEN:      apb_slv.prdata <= {25'd0, reg_win_len};
                        ADDR_SPIKE_WARN:   apb_slv.prdata <= {25'd0, reg_spike_sum_warn};
                        ADDR_SPIKE_FIRE:   apb_slv.prdata <= {25'd0, reg_spike_sum_fire};
                        ADDR_CUR_SPIKE_SUM: apb_slv.prdata <= {25'd0, spike_sum_q};
                        ADDR_PEAK_SPIKE_SUM: apb_slv.prdata <= {25'd0, peak_spike_sum};
                        ADDR_PEAK_DIFF_FIRE: apb_slv.prdata <= {16'd0, reg_peak_diff_fire_thresh};
                        ADDR_ALPHA_SHIFT:   apb_slv.prdata <= {27'd0, reg_alpha_shift};
                        ADDR_GAIN_SHIFT:    apb_slv.prdata <= {27'd0, reg_gain_shift};
                        ADDR_CUR_NOISE:     apb_slv.prdata <= {16'd0, noise_floor_q};
                        ADDR_EFFECTIVE_THRESH: apb_slv.prdata <= {16'd0, effective_thresh_comb};
                        ADDR_STREAM_STATUS: apb_slv.prdata <= {30'd0, detector_holdoff_active, stream_restart_i};
                        ADDR_STREAM_RESTART_COUNT: apb_slv.prdata <= {16'd0, stream_restart_count};
                        ADDR_HOT_BASE:      apb_slv.prdata <= {16'd0, reg_hot_base};
                        ADDR_HOT_ATTACK:    apb_slv.prdata <= {16'd0, reg_hot_attack};
                        ADDR_HOT_DECAY:     apb_slv.prdata <= {16'd0, reg_hot_decay};
                        ADDR_HOT_LIMIT:     apb_slv.prdata <= {16'd0, reg_hot_limit};
                        ADDR_ENV_SHIFT:     apb_slv.prdata <= {27'd0, reg_env_shift};
                        ADDR_CUR_ENV_LP:    apb_slv.prdata <= {16'd0, env_lp_q};
                        ADDR_CUR_HOTSPOT:   apb_slv.prdata <= {16'd0, hotspot_score_q};
                        ADDR_ZERO_BAND:     apb_slv.prdata <= {16'd0, reg_zero_band};
                        ADDR_QUIET_MIN:     apb_slv.prdata <= {24'd0, reg_quiet_min};
                        ADDR_QUIET_MAX:     apb_slv.prdata <= {24'd0, reg_quiet_max};
                        ADDR_CUR_QUIET_LEN: apb_slv.prdata <= {24'd0, quiet_len_q};
                        ADDR_LAST_ZERO_GAP: apb_slv.prdata <= {24'd0, last_zero_gap_q};
                        ADDR_LAST_FIRE_DIFF: apb_slv.prdata <= {16'd0, last_fire_diff_q};
                        ADDR_LAST_FIRE_INT:  apb_slv.prdata <= {16'd0, last_fire_int_q};
                        ADDR_LAST_CAUSE:     apb_slv.prdata <= {28'd0, last_cause_code_q};
                        ADDR_PROFILE_CTRL:   apb_slv.prdata <= {24'd0, DEFAULT_BOOT_PROFILE, current_profile_q};
                        default:           apb_slv.prdata <= 32'd0;
                    endcase
                end
            end

            if (clear_latched_cmd) begin
                fire_latched <= 1'b0;
            end

            if (clear_peaks_cmd) begin
                diff_abs        <= '0;
                peak_diff       <= '0;
                peak_integrator <= '0;
                attack_step_q   <= '0;
                peak_spike_sum  <= '0;
                quiet_len_q     <= '0;
                last_zero_gap_q <= '0;
                quiet_confidence_q <= '0;
                quiet_recent_peak_q <= '0;
            end

            if (clear_events_cmd) begin
                event_count <= 16'd0;
                last_fire_diff_q  <= '0;
                last_fire_int_q   <= '0;
                last_cause_code_q <= CAUSE_NONE;
            end

            if (clear_restart_count_cmd) begin
                stream_restart_count <= 16'd0;
            end

            if (stream_restart_i) begin
                sample_prev_q         <= '0;
                sample_pair_valid     <= 1'b0;
                diff_abs              <= '0;
                peak_diff             <= '0;
                integrator            <= '0;
                peak_integrator       <= '0;
                attack_step_q         <= '0;
                spike_hist_q          <= '0;
                spike_sum_q           <= '0;
                peak_spike_sum        <= '0;
                noise_floor_q         <= '0;
                env_lp_q              <= '0;
                hotspot_score_q       <= '0;
                quiet_len_q           <= '0;
                last_zero_gap_q       <= '0;
                quiet_confidence_q    <= '0;
                quiet_recent_peak_q   <= '0;
                last_fire_diff_q      <= '0;
                last_fire_int_q       <= '0;
                last_cause_code_q     <= CAUSE_NONE;
                stage_a_sample_valid_q <= 1'b0;
                stage_a_pair_valid_q   <= 1'b0;
                stage_a_diff_abs_q     <= '0;
                stage_a_noise_floor_next_q <= '0;
                stage_a_effective_thresh_q <= '0;
                stage_a_quiet_len_next_q <= '0;
                stage_a_quiet_gap_capture_q <= '0;
                stage_a_quiet_recent_peak_next_q <= '0;
                stage_a_env_lp_next_q  <= '0;
                stage_a_sign_change_q  <= 1'b0;
                reg_status            <= 2'b00;
                irq_arc_o             <= 1'b0;
                restart_holdoff_q     <= RESTART_HOLDOFF_SAMPLES[RESTART_HOLDOFF_W-1:0];
                stream_restart_count  <= stream_restart_count + 16'd1;
            end else begin
                if (adc_valid_i) begin
                    stage_a_sample_valid_q <= 1'b1;
                    stage_a_pair_valid_q   <= sample_pair_valid;
                    stage_a_diff_abs_q     <= diff_abs_comb;
                    stage_a_noise_floor_next_q <= noise_floor_next_comb;
                    stage_a_effective_thresh_q <= effective_thresh_comb;
                    stage_a_quiet_len_next_q <= quiet_len_next_comb;
                    stage_a_quiet_gap_capture_q <= quiet_gap_capture_comb;
                    stage_a_quiet_recent_peak_next_q <= quiet_recent_peak_next_comb;
                    stage_a_env_lp_next_q  <= env_lp_next_comb;
                    stage_a_sign_change_q  <= sign_change_comb;

                    sample_prev_q     <= adc_data_i;
                    sample_pair_valid <= 1'b1;
                end else begin
                    stage_a_sample_valid_q <= 1'b0;
                    stage_a_pair_valid_q   <= 1'b0;
                    stage_a_sign_change_q  <= 1'b0;
                end

                if (stage_a_sample_valid_q) begin
                    attack_step_q <= '0;
                    env_lp_q        <= stage_a_env_lp_next_q;
                    hotspot_score_q <= hotspot_score_next_comb;
                    spike_hist_q    <= {spike_hist_q[MAX_WIN_LEN-2:0], is_spike_detected};
                    spike_sum_q     <= spike_sum_next_comb;

                    if (spike_sum_next_comb > peak_spike_sum)
                        peak_spike_sum <= spike_sum_next_comb;

                    quiet_len_q        <= stage_a_quiet_len_next_q;
                    quiet_confidence_q <= quiet_confidence_next_comb;
                    if (stage_a_sign_change_q)
                        last_zero_gap_q <= stage_a_quiet_gap_capture_q;

                    if (stage_a_pair_valid_q) begin
                        if (stage_a_sign_change_q)
                            quiet_recent_peak_q <= '0;
                        else
                            quiet_recent_peak_q <= stage_a_quiet_recent_peak_next_q;
                    end

                    if (stage_a_pair_valid_q && !detector_sample_blocked) begin
                        diff_abs      <= stage_a_diff_abs_q;
                        noise_floor_q <= stage_a_noise_floor_next_q;
                        if (stage_a_diff_abs_q > peak_diff)
                            peak_diff <= stage_a_diff_abs_q;

                        if (is_spike_detected)
                            attack_step_q <= attack_step_comb;

                        integrator <= integrator_next_comb;
                        if (integrator_next_comb > peak_integrator)
                            peak_integrator <= integrator_next_comb;

                        if (fire_condition_comb || thermal_fire_comb) begin
                            irq_arc_o        <= 1'b1;
                            fire_latched     <= 1'b1;
                            reg_status       <= 2'b11;
                            last_fire_diff_q <= stage_a_diff_abs_q;
                            last_fire_int_q  <= integrator_next_comb;
                            last_cause_code_q <= trip_cause_code_comb;

                            if (!irq_arc_o)
                                event_count <= event_count + 16'd1;
                        end else if (irq_arc_o && ((integrator_next_comb != '0) || (hotspot_score_next_comb != '0))) begin
                            // Keep FIRE state while arc/thermal energy is still discharging.
                            reg_status <= 2'b11;
                        end else begin
                            if (warn_condition_comb)
                                reg_status <= 2'b01;
                            else
                                reg_status <= 2'b00;

                            if (integrator_next_comb == '0)
                                irq_arc_o <= 1'b0;
                        end
                    end else if (stage_a_pair_valid_q && detector_sample_blocked) begin
                        if (detector_holdoff_active)
                            restart_holdoff_q <= restart_holdoff_q - 1'b1;
                    end
                end
            end
        end
    end

endmodule
