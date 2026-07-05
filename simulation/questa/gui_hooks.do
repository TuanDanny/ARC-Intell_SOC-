proc codex_gui_find_proj_root {} {
    set dir [file normalize [pwd]]
    while {1} {
        if {[file exists [file join $dir In_SOC.qsf]] && [file exists [file join $dir rtl top_soc.sv]]} {
            return $dir
        }
        set parent [file dirname $dir]
        if {$parent eq $dir} {
            error "Unable to locate In_SOC project root from [pwd]"
        }
        set dir $parent
    }
}

proc codex_gui_safe_eval {script} {
    catch {uplevel #0 $script}
}

proc codex_gui_add_signal_group {group_name signal_list {radix ""}} {
    foreach sig $signal_list {
        if {$radix eq ""} {
            codex_gui_safe_eval [list add wave -noupdate -group $group_name $sig]
        } else {
            codex_gui_safe_eval [list add wave -noupdate -group $group_name -radix $radix $sig]
        }
        codex_gui_safe_eval [list log $sig]
        codex_gui_safe_eval [list vcd add $sig]
    }
}

proc codex_gui_add_divider {label} {
    codex_gui_safe_eval [list add wave -noupdate -divider $label]
}

proc codex_gui_setup_vcd {target} {
    upvar #0 proj_root proj_root
    set out_dir [file join $proj_root sim gui_exports]
    file mkdir $out_dir
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set vcd_path [file join $out_dir "${target}_${timestamp}.vcd"]
    codex_gui_safe_eval [list vcd flush]
    codex_gui_safe_eval [list vcd file $vcd_path]
    set ::codex_gui_vcd_path $vcd_path
}

proc codex_gui_common_view_setup {} {
    set wave_ok 1
    if {[catch {view wave}]} {
        set wave_ok 0
    }
    codex_gui_safe_eval {view structure}
    codex_gui_safe_eval {view signals}
    codex_gui_safe_eval {view transcript}
    codex_gui_safe_eval {view objects}
    if {$wave_ok} {
        codex_gui_safe_eval {configure wave -namecolwidth 260}
        codex_gui_safe_eval {configure wave -valuecolwidth 120}
        codex_gui_safe_eval {configure wave -timelineunits ns}
        codex_gui_safe_eval {configure wave -signalnamewidth 1}
        codex_gui_safe_eval {configure wave -justifyvalue left}
        codex_gui_safe_eval {configure wave -gridperiod 50}
        codex_gui_safe_eval {configure wave -griddelta 10}
        codex_gui_safe_eval {WaveActivateNextPane {} 0}
    }
}

proc codex_gui_setup_full {} {
    codex_gui_add_divider "Bench I/O"
    codex_gui_add_signal_group "bench_io" {
        /tb_professional/clk
        /tb_professional/rst_ni
        /tb_professional/adc_miso
        /tb_professional/adc_mosi
        /tb_professional/adc_sclk
        /tb_professional/adc_csn
        /tb_professional/uart_rx
        /tb_professional/uart_tx
        /tb_professional/gpio_io
    }

    codex_gui_add_divider "Top Control"
    codex_gui_add_signal_group "top_ctrl" {
        /tb_professional/dut/dsp_data_in
        /tb_professional/dut/dsp_valid_in
        /tb_professional/dut/spi_stream_restart
        /tb_professional/dut/irq_arc_critical
        /tb_professional/dut/irq_timer_tick
    }

    codex_gui_add_divider "CPU"
    codex_gui_add_signal_group "cpu_hex" {
        /tb_professional/dut/u_cpu/pc
        /tb_professional/dut/u_cpu/instr
        /tb_professional/dut/u_cpu/flags
        /tb_professional/dut/u_cpu/state
        /tb_professional/dut/u_cpu/shadow_pc
        /tb_professional/dut/u_cpu/nested_shadow_pc
        /tb_professional/dut/u_cpu/dsp_page_sel
    } hex
    codex_gui_add_signal_group "cpu_ctrl" {
        /tb_professional/dut/u_cpu/in_arc_isr
        /tb_professional/dut/u_cpu/in_timer_isr
        /tb_professional/dut/u_cpu/is_in_isr
        /tb_professional/dut/u_cpu/arc_preempted_timer
        /tb_professional/dut/apb_cpu_master/psel
        /tb_professional/dut/apb_cpu_master/penable
        /tb_professional/dut/apb_cpu_master/pwrite
    }
    codex_gui_add_signal_group "cpu_apb_hex" {
        /tb_professional/dut/apb_cpu_master/paddr
        /tb_professional/dut/apb_cpu_master/pwdata
        /tb_professional/dut/apb_cpu_master/prdata
    } hex
    codex_gui_add_signal_group "cpu_apb_resp" {
        /tb_professional/dut/apb_cpu_master/pready
        /tb_professional/dut/apb_cpu_master/pslverr
    }

    codex_gui_add_divider "GPIO / Relay"
    codex_gui_add_signal_group "gpio_ports" {
        /tb_professional/gpio_io
        /tb_professional/dut/gpio_out_wire
        /tb_professional/dut/gpio_dir_wire
        /tb_professional/dut/gpio_irq_wire
    } hex
    codex_gui_add_signal_group "gpio_apb" {
        /tb_professional/dut/u_gpio/PWRITE
        /tb_professional/dut/u_gpio/PSEL
        /tb_professional/dut/u_gpio/PENABLE
        /tb_professional/dut/u_gpio/PREADY
        /tb_professional/dut/u_gpio/PSLVERR
        /tb_professional/dut/u_gpio/interrupt
    }
    codex_gui_add_signal_group "gpio_apb_hex" {
        /tb_professional/dut/u_gpio/PADDR
        /tb_professional/dut/u_gpio/PWDATA
        /tb_professional/dut/u_gpio/PRDATA
        /tb_professional/dut/u_gpio/gpio_in
        /tb_professional/dut/u_gpio/gpio_out
        /tb_professional/dut/u_gpio/gpio_dir
    } hex

    codex_gui_add_divider "SPI Bridge"
    codex_gui_add_signal_group "spi_bridge" {
        /tb_professional/dut/u_spi_bridge/sample_valid_o
        /tb_professional/dut/u_spi_bridge/busy_o
        /tb_professional/dut/u_spi_bridge/frame_active_o
        /tb_professional/dut/u_spi_bridge/overrun_o
    }
    codex_gui_add_signal_group "spi_bridge_hex" {
        /tb_professional/dut/u_spi_bridge/sample_data_o
        /tb_professional/dut/u_spi_bridge/r_frame_count
        /tb_professional/dut/u_spi_bridge/r_latest_sample
    } hex

    codex_gui_add_divider "DSP"
    codex_gui_add_signal_group "dsp_ctrl" {
        /tb_professional/dut/u_dsp/irq_arc_o
        /tb_professional/dut/u_dsp/fire_latched
        /tb_professional/dut/u_dsp/sample_pair_valid
        /tb_professional/dut/u_dsp/reg_status
    }
    codex_gui_add_signal_group "dsp_hex" {
        /tb_professional/dut/u_dsp/diff_abs
        /tb_professional/dut/u_dsp/effective_thresh_comb
        /tb_professional/dut/u_dsp/integrator
        /tb_professional/dut/u_dsp/spike_sum_q
        /tb_professional/dut/u_dsp/noise_floor_q
        /tb_professional/dut/u_dsp/env_lp_q
        /tb_professional/dut/u_dsp/hotspot_score_q
        /tb_professional/dut/u_dsp/quiet_len_q
        /tb_professional/dut/u_dsp/last_zero_gap_q
        /tb_professional/dut/u_dsp/last_cause_code_q
        /tb_professional/dut/u_dsp/current_profile_q
    } hex

    codex_gui_add_divider "Safety / Service"
    codex_gui_add_signal_group "safety" {
        /tb_professional/dut/u_wdt/wdt_reset_o
        /tb_professional/dut/u_bist/r_done
    }
    codex_gui_add_signal_group "safety_hex" {
        /tb_professional/dut/u_bist/r_signature
        /tb_professional/dut/u_wdt/r_counter
    } hex
}

proc codex_gui_setup_dsp {} {
    codex_gui_add_divider "Bench Control"
    codex_gui_add_signal_group "bench_ctrl" {
        /tb_dsp_upgrades/clk
        /tb_dsp_upgrades/rst_ni
        /tb_dsp_upgrades/adc_miso
        /tb_dsp_upgrades/spi_stream_restart
        /tb_dsp_upgrades/tbx_dsp_force_addr
        /tb_dsp_upgrades/tbx_dsp_force_data
    } hex

    codex_gui_add_divider "DSP APB"
    codex_gui_add_signal_group "dsp_apb" {
        /tb_dsp_upgrades/dut/apb_dsp_if/psel
        /tb_dsp_upgrades/dut/apb_dsp_if/penable
        /tb_dsp_upgrades/dut/apb_dsp_if/pwrite
        /tb_dsp_upgrades/dut/apb_dsp_if/pready
        /tb_dsp_upgrades/dut/apb_dsp_if/pslverr
    }
    codex_gui_add_signal_group "dsp_apb_hex" {
        /tb_dsp_upgrades/dut/apb_dsp_if/paddr
        /tb_dsp_upgrades/dut/apb_dsp_if/pwdata
        /tb_dsp_upgrades/dut/apb_dsp_if/prdata
    } hex

    codex_gui_add_divider "DSP Core"
    codex_gui_add_signal_group "dsp_core" {
        /tb_dsp_upgrades/dut/dsp_valid_in
        /tb_dsp_upgrades/dut/u_dsp/irq_arc_o
        /tb_dsp_upgrades/dut/u_dsp/fire_latched
        /tb_dsp_upgrades/dut/u_dsp/sample_pair_valid
        /tb_dsp_upgrades/dut/u_dsp/reg_status
    }
    codex_gui_add_signal_group "dsp_core_hex" {
        /tb_dsp_upgrades/dut/dsp_data_in
        /tb_dsp_upgrades/dut/u_dsp/diff_abs
        /tb_dsp_upgrades/dut/u_dsp/effective_thresh_comb
        /tb_dsp_upgrades/dut/u_dsp/integrator
        /tb_dsp_upgrades/dut/u_dsp/attack_step_q
        /tb_dsp_upgrades/dut/u_dsp/spike_sum_q
        /tb_dsp_upgrades/dut/u_dsp/noise_floor_q
        /tb_dsp_upgrades/dut/u_dsp/env_lp_q
        /tb_dsp_upgrades/dut/u_dsp/hotspot_score_q
        /tb_dsp_upgrades/dut/u_dsp/quiet_len_q
        /tb_dsp_upgrades/dut/u_dsp/last_zero_gap_q
        /tb_dsp_upgrades/dut/u_dsp/last_fire_diff_q
        /tb_dsp_upgrades/dut/u_dsp/last_fire_int_q
        /tb_dsp_upgrades/dut/u_dsp/last_cause_code_q
        /tb_dsp_upgrades/dut/u_dsp/current_profile_q
    } hex
}

proc codex_gui_setup_support {} {
    codex_gui_add_divider "Reset Gen"
    codex_gui_add_signal_group "rstgen" {
        /tb_support_blocks/clk
        /tb_support_blocks/rstgen_rst_ni
        /tb_support_blocks/rstgen_test_mode_i
        /tb_support_blocks/rstgen_rst_no
        /tb_support_blocks/rstgen_init_no
    }

    codex_gui_add_divider "Clock Gating"
    codex_gui_add_signal_group "clock_gating" {
        /tb_support_blocks/cg_clk_i
        /tb_support_blocks/cg_en_i
        /tb_support_blocks/cg_test_en_i
        /tb_support_blocks/cg_clk_o
    }

    codex_gui_add_divider "Generic FIFO"
    codex_gui_add_signal_group "fifo_ctrl" {
        /tb_support_blocks/fifo_clk_i
        /tb_support_blocks/fifo_rst_ni
        /tb_support_blocks/fifo_push_i
        /tb_support_blocks/fifo_pop_i
        /tb_support_blocks/fifo_full_o
        /tb_support_blocks/fifo_empty_o
        /tb_support_blocks/fifo_valid_o
    }
    codex_gui_add_signal_group "fifo_hex" {
        /tb_support_blocks/fifo_data_i
        /tb_support_blocks/fifo_data_o
        /tb_support_blocks/fifo_usage_o
    } hex
}

proc codex_gui_setup_periph {} {
    codex_gui_add_divider "Bench APB"
    codex_gui_add_signal_group "bench_apb" {
        /tb_apb_peripherals/HCLK
        /tb_apb_peripherals/HRESETn
        /tb_apb_peripherals/PSEL
        /tb_apb_peripherals/PENABLE
        /tb_apb_peripherals/PWRITE
        /tb_apb_peripherals/PREADY
        /tb_apb_peripherals/PSLVERR
    }
    codex_gui_add_signal_group "bench_apb_hex" {
        /tb_apb_peripherals/PADDR
        /tb_apb_peripherals/PWDATA
        /tb_apb_peripherals/PRDATA
    } hex

    codex_gui_add_divider "GPIO"
    codex_gui_add_signal_group "gpio" {
        /tb_apb_peripherals/gpio_pins
        /tb_apb_peripherals/gpio_irq
        /tb_apb_peripherals/u_gpio/interrupt
    }
    codex_gui_add_signal_group "gpio_hex" {
        /tb_apb_peripherals/u_gpio/gpio_out
        /tb_apb_peripherals/u_gpio/gpio_dir
        /tb_apb_peripherals/u_gpio/PRDATA
    } hex

    codex_gui_add_divider "UART"
    codex_gui_add_signal_group "uart" {
        /tb_apb_peripherals/uart_sin
        /tb_apb_peripherals/uart_sout
        /tb_apb_peripherals/uart_intr
        /tb_apb_peripherals/u_uart/r_rx_valid
        /tb_apb_peripherals/u_uart/r_tx_busy
    }
    codex_gui_add_signal_group "uart_hex" {
        /tb_apb_peripherals/u_uart/r_divisor
        /tb_apb_peripherals/u_uart/r_rx_data
        /tb_apb_peripherals/u_uart/r_tx_data
    } hex

    codex_gui_add_divider "Timer"
    codex_gui_add_signal_group "timer" {
        /tb_apb_peripherals/timer_events
        /tb_apb_peripherals/timer_ch0
        /tb_apb_peripherals/timer_event0_seen
    }
    codex_gui_add_signal_group "timer_hex" {
        /tb_apb_peripherals/u_timer/s_timer0_count
        /tb_apb_peripherals/u_timer/PRDATA
    } hex
}

proc codex_gui_post_vsim_setup {target} {
    codex_gui_common_view_setup
    codex_gui_setup_vcd $target
    switch -- $target {
        full    { codex_gui_setup_full }
        dsp     { codex_gui_setup_dsp }
        support { codex_gui_setup_support }
        periph  { codex_gui_setup_periph }
        default { }
    }
    codex_gui_safe_eval {TreeUpdate [SetDefaultTree]}
    codex_gui_safe_eval {update}
    puts ""
    puts "============================================================"
    puts " Codex GUI setup ready"
    puts " Target : $target"
    if {[info exists ::codex_gui_vcd_path]} {
        puts " VCD    : $::codex_gui_vcd_path"
    }
    puts "============================================================"
    puts ""
}

proc codex_gui_post_run_complete {target} {
    codex_gui_safe_eval {wave zoom full}
    codex_gui_safe_eval {vcd flush}
    puts ""
    puts "============================================================"
    puts " Codex GUI run complete"
    puts " Target : $target"
    if {[info exists ::codex_gui_vcd_path]} {
        puts " VCD    : $::codex_gui_vcd_path"
    }
    puts " Tip    : Zoom Full was applied automatically."
    puts "============================================================"
    puts ""
}

proc codex_gui_open_usage {} {
    puts ""
    puts "Codex Questa transcript helpers"
    puts "  full"
    puts "  dsp"
    puts "  support"
    puts "  periph"
    puts "  full manual"
    puts "  codex_open <target> ?manual?"
    puts "  codex_targets"
    puts ""
    puts "These commands reload the selected target in the current GUI session."
    puts ""
}

proc codex_open {target {mode ""}} {
    if {$target eq ""} {
        codex_gui_open_usage
        return
    }

    set manual_mode [string tolower $mode]
    set proj_root [codex_gui_find_proj_root]
    set loader [file join $proj_root simulation questa gui_open_target.do]

    if {$manual_mode eq "manual" || $manual_mode eq "--manual"} {
        uplevel #0 [list do $loader $target manual]
    } else {
        uplevel #0 [list do $loader $target]
    }
}

proc codex_targets {} {
    codex_gui_open_usage
}

proc full {{mode ""}} {
    codex_open full $mode
}

proc dsp {{mode ""}} {
    codex_open dsp $mode
}

proc support {{mode ""}} {
    codex_open support $mode
}

proc periph {{mode ""}} {
    codex_open periph $mode
}
