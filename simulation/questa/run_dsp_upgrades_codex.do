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
set proj_root  [find_proj_root]
set rtl_dir    [file join $proj_root rtl]
set sim_dir    [file join $proj_root sim]
set rtl_periph [file join $rtl_dir periph]
set rtl_lib    [file join $rtl_dir lib]
set rtl_timer  [file join $rtl_periph timer]
set rtl_bus    [file join $rtl_dir bus]
set rtl_core   [file join $rtl_dir core]
set rtl_inc    [file join $rtl_dir include]
set spi_master_dir [file join $rtl_periph spi_master]
if {[file exists rtl_work_codex_dsp]} {
	vdel -lib rtl_work_codex_dsp -all
}
vlib rtl_work_codex_dsp
vmap work rtl_work_codex_dsp

vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph logic_bist.sv]
vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph safety_watchdog.sv]
vlog -sv -work work +incdir+$rtl_lib [file join $rtl_lib pulp_clock_gating.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer up_down_counter.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer timer_module.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer timer_cntrl.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer prescaler.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer input_stage.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer comparator.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer apb_adv_timer.sv]
vlog -sv -work work +incdir+$rtl_timer [file join $rtl_timer adv_timer_apb_if.sv]
vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph apb_uart_wrap.sv]
vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph apb_gpio.sv]
vlog -sv -work work +incdir+$rtl_periph +incdir+$spi_master_dir [file join $spi_master_dir apb_spi_adc_bridge.sv]
vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph spi_adc_stream_rx.sv]
vlog -sv -work work +incdir+$rtl_bus [file join $rtl_bus apb_node.sv]
vlog -sv -work work +incdir+$rtl_lib [file join $rtl_lib rstgen.sv]
vlog -sv -work work +incdir+$rtl_dir +incdir+$rtl_inc [file join $rtl_dir top_soc.sv]
vlog -sv -work work +incdir+$rtl_periph [file join $rtl_periph dsp_arc_detect.sv]
vlog -sv -work work +incdir+$rtl_core [file join $rtl_core cpu_8bit.sv]
vlog -sv -work work +incdir+$rtl_inc [file join $rtl_inc config.sv]
vlog -sv -work work +incdir+$rtl_inc [file join $rtl_inc apb_bus.sv]

vlog -sv -work work [file join $sim_dir tb_dsp_upgrades.sv]

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work_codex_dsp -L work -voptargs="+acc" tb_dsp_upgrades

run -all
