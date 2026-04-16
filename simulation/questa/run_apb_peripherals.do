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
set rtl_lib    [file join $proj_root rtl lib]
set rtl_periph [file join $proj_root rtl periph]
set rtl_timer  [file join $rtl_periph timer]
set sim_dir    [file join $proj_root sim]

if {[file exists rtl_work_periph]} {
    vdel -lib rtl_work_periph -all
}
vlib rtl_work_periph
vmap work rtl_work_periph

vlog -sv -work work [file join $rtl_periph apb_gpio.sv]
vlog -sv -work work [file join $rtl_periph apb_uart_wrap.sv]
vlog -sv -work work [file join $rtl_lib pulp_clock_gating.sv]
vlog -sv -work work [file join $rtl_timer comparator.sv]
vlog -sv -work work [file join $rtl_timer input_stage.sv]
vlog -sv -work work [file join $rtl_timer prescaler.sv]
vlog -sv -work work [file join $rtl_timer timer_cntrl.sv]
vlog -sv -work work [file join $rtl_timer up_down_counter.sv]
vlog -sv -work work [file join $rtl_timer timer_module.sv]
vlog -sv -work work [file join $rtl_timer adv_timer_apb_if.sv]
vlog -sv -work work [file join $rtl_timer apb_adv_timer.sv]
vlog -sv -work work [file join $sim_dir tb_apb_peripherals.sv]

vsim -t 1ps -L rtl_work_periph -L work -voptargs="+acc" tb_apb_peripherals
run -all
