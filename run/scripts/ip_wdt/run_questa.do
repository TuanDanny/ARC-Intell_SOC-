transcript on

proc find_ip_root {} {
    set dir [file normalize [pwd]]
    while {1} {
        if {[file exists [file join $dir rtl safety_watchdog.sv]] &&
            [file exists [file join $dir scripts run_questa.do]]} {
            return $dir
        }
        if {[file exists [file join $dir ip safety_watchdog rtl safety_watchdog.sv]]} {
            return [file normalize [file join $dir ip safety_watchdog]]
        }
        set parent [file dirname $dir]
        if {$parent eq $dir} {
            error "Unable to locate safety_watchdog IP root from [pwd]"
        }
        set dir $parent
    }
}

set ip_root [find_ip_root]
set rtl_dir [file join $ip_root rtl]
set tb_dir  [file join $ip_root tb]
set work_dir [file join $ip_root work_questa]

if {![file exists $work_dir]} {
    vlib $work_dir
}
vmap work $work_dir

vlog -sv -work work [file join $rtl_dir safety_watchdog.sv]
vlog -sv -work work [file join $tb_dir  tb_safety_watchdog_ip.sv]

vsim -t 1ps -L work -voptargs="+acc" tb_safety_watchdog_ip
run -all
