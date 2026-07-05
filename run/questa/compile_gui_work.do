transcript on

proc find_proj_root {} {
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

set proj_root      [find_proj_root]
set rtl_dir        [file join $proj_root rtl]
set rtl_bus        [file join $rtl_dir bus]
set rtl_core       [file join $rtl_dir core]
set rtl_inc        [file join $rtl_dir include]
set rtl_lib        [file join $rtl_dir lib]
set rtl_periph     [file join $rtl_dir periph]
set rtl_timer      [file join $rtl_periph timer]
set spi_master_dir [file join $rtl_periph spi_master]
set sim_dir        [file join $proj_root sim]
set work_dir       [file join $proj_root work]

if {![file exists $work_dir]} {
    vlib $work_dir
}
vmap work $work_dir

set common_inc "+incdir+$rtl_inc+incdir+$rtl_dir+incdir+$rtl_periph+incdir+$rtl_lib+incdir+$rtl_bus+incdir+$rtl_core+incdir+$rtl_timer+incdir+$spi_master_dir+incdir+$sim_dir"

# RTL / support blocks used by old GUI testbenches
vlog -sv -work work $common_inc [file join $rtl_inc config.sv]
vlog -sv -work work $common_inc [file join $rtl_inc apb_bus.sv]
vlog -sv -work work $common_inc [file join $rtl_lib pulp_clock_gating.sv]
vlog -sv -work work $common_inc [file join $rtl_lib cluster_clock_gating.sv]
vlog -sv -work work $common_inc [file join $rtl_lib generic_fifo.sv]
vlog -sv -work work $common_inc [file join $rtl_lib rstgen.sv]
vlog -sv -work work $common_inc [file join $rtl_lib async_fifo_gray.sv]
vlog -sv -work work $common_inc [file join $rtl_timer comparator.sv]
vlog -sv -work work $common_inc [file join $rtl_timer input_stage.sv]
vlog -sv -work work $common_inc [file join $rtl_timer prescaler.sv]
vlog -sv -work work $common_inc [file join $rtl_timer timer_cntrl.sv]
vlog -sv -work work $common_inc [file join $rtl_timer up_down_counter.sv]
vlog -sv -work work $common_inc [file join $rtl_timer timer_module.sv]
vlog -sv -work work $common_inc [file join $rtl_timer adv_timer_apb_if.sv]
vlog -sv -work work $common_inc [file join $rtl_timer apb_adv_timer.sv]
vlog -sv -work work $common_inc [file join $rtl_periph apb_gpio.sv]
vlog -sv -work work $common_inc [file join $rtl_periph apb_uart_wrap.sv]
vlog -sv -work work $common_inc [file join $rtl_periph logic_bist.sv]
vlog -sv -work work $common_inc [file join $rtl_periph safety_watchdog.sv]
vlog -sv -work work $common_inc [file join $rtl_periph dsp_arc_detect.sv]
vlog -sv -work work $common_inc [file join $rtl_periph dsp_arc_detect_apb_wrapper.sv]
vlog -sv -work work $common_inc [file join $rtl_periph spi_adc_stream_rx.sv]
vlog -sv -work work $common_inc [file join $rtl_periph spi_adc_sclk_capture_rx.sv]
vlog -sv -work work $common_inc [file join $spi_master_dir apb_spi_adc_bridge.sv]
vlog -sv -work work $common_inc [file join $spi_master_dir spi_adc_cdc_bridge.sv]
vlog -sv -work work $common_inc [file join $rtl_bus apb_node.sv]
vlog -sv -work work $common_inc [file join $rtl_core cpu_8bit.sv]
vlog -sv -work work $common_inc [file join $rtl_dir top_soc.sv]

# Old GUI testbenches shown in sim/ folder
vlog -sv -work work $common_inc [file join $sim_dir tb.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_apb_peripherals.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_dsp_upgrades.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_professional.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_support_blocks.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_cdc_async_fifo.sv]
vlog -sv -work work $common_inc [file join $sim_dir tb_spi_cdc_bridge.sv]

puts "GUI work library compile complete: $work_dir"
puts "Refresh/reopen Start Simulation. Top modules should include tb_professional_full, tb_apb_peripherals, tb_dsp_upgrades, tb_professional, tb_support_blocks, tb_cdc_async_fifo, tb_spi_cdc_bridge."