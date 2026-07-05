transcript on

proc find_ip_root {} {
    set dir [file normalize [pwd]]
    while {1} {
        if {[file exists [file join $dir rtl dsp_arc_detect.sv]] &&
            [file exists [file join $dir scripts run_questa.do]]} {
            return $dir
        }
        if {[file exists [file join $dir ip dsp_arc_detect rtl dsp_arc_detect.sv]]} {
            return [file normalize [file join $dir ip dsp_arc_detect]]
        }
        set parent [file dirname $dir]
        if {$parent eq $dir} {
            error "Unable to locate dsp_arc_detect IP root from [pwd]"
        }
        set dir $parent
    }
}

set ip_root [find_ip_root]
set rtl_dir [file join $ip_root rtl]
set rtl_inc [file join $rtl_dir include]
set tb_dir  [file join $ip_root tb]
set work_dir [file join $ip_root work_questa]

if {![file exists $work_dir]} {
    vlib $work_dir
}
vmap work $work_dir

vlog -sv -work work +incdir+$rtl_inc [file join $rtl_inc config.sv]
vlog -sv -work work +incdir+$rtl_inc [file join $rtl_inc apb_bus.sv]
vlog -sv -work work +incdir+$rtl_inc +incdir+$rtl_dir [file join $rtl_dir dsp_arc_detect.sv]
vlog -sv -work work +incdir+$rtl_inc +incdir+$rtl_dir [file join $rtl_dir dsp_arc_detect_apb_wrapper.sv]
vlog -sv -work work [file join $tb_dir dsp_arc_detect_ip_assertions.sv]
vlog -sv -work work [file join $tb_dir tb_dsp_arc_detect_ip.sv]

vsim -t 1ps -L work -voptargs="+acc" tb_dsp_arc_detect_ip
run -all
