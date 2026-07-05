transcript on

proc find_ip_root {} {
    set dir [file normalize [pwd]]
    while {1} {
        if {[file exists [file join $dir rtl apb_spi_adc_bridge.sv]] &&
            [file exists [file join $dir scripts run_questa.do]]} {
            return $dir
        }
        if {[file exists [file join $dir ip apb_spi_adc_bridge rtl apb_spi_adc_bridge.sv]]} {
            return [file normalize [file join $dir ip apb_spi_adc_bridge]]
        }
        set parent [file dirname $dir]
        if {$parent eq $dir} {
            error "Unable to locate apb_spi_adc_bridge IP root from [pwd]"
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

vlog -sv -work work [file join $rtl_dir spi_adc_stream_rx.sv]
vlog -sv -work work [file join $rtl_dir apb_spi_adc_bridge.sv]
vlog -sv -work work [file join $tb_dir  tb_apb_spi_adc_bridge_ip.sv]

vsim -t 1ps -L work -voptargs="+acc" tb_apb_spi_adc_bridge_ip
run -all
