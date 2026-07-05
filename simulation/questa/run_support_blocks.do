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
set sim_dir    [file join $proj_root sim]

if {[file exists rtl_work_support]} {
    vdel -lib rtl_work_support -all
}
vlib rtl_work_support
vmap work rtl_work_support

vlog -sv -work work [file join $rtl_lib pulp_clock_gating.sv]
vlog -sv -work work [file join $rtl_lib cluster_clock_gating.sv]
vlog -sv -work work [file join $rtl_lib generic_fifo.sv]
vlog -sv -work work [file join $rtl_lib rstgen.sv]
vlog -sv -work work [file join $sim_dir tb_support_blocks.sv]

vsim -t 1ps -L rtl_work_support -L work -voptargs="+acc" tb_support_blocks
if {[info procs codex_gui_post_vsim_setup] ne ""} {
    codex_gui_post_vsim_setup support
}

if {[info exists codex_gui_manual] && $codex_gui_manual} {
    puts {[GUI] Manual mode enabled. Design is compiled, loaded, and instrumented. Use run commands manually.}
} else {
    run -all
    if {[info procs codex_gui_post_run_complete] ne ""} {
        codex_gui_post_run_complete support
    }
}
