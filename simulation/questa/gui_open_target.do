proc codex_open_usage {} {
    puts ""
    puts "Codex GUI target loader"
    puts "Usage from Questa transcript:"
    puts "  do simulation/questa/gui_open_target.do full"
    puts "  do simulation/questa/gui_open_target.do dsp manual"
    puts "  do simulation/questa/gui_open_target.do periph"
    puts ""
    puts "Targets: full, dsp, support, periph"
    puts "Optional second argument: manual"
    puts ""
}

proc codex_open_find_proj_root {} {
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

proc codex_open_target {target manual_mode} {
    set proj_root [codex_open_find_proj_root]
    cd $proj_root

    set hooks [file join $proj_root simulation questa gui_hooks.do]
    do $hooks

    if {[catch {quit -sim} quit_err]} {
        if {[string trim $quit_err] ne ""} {
            puts [format {[INFO] quit -sim skipped: %s} $quit_err]
        }
    } else {
        puts {[INFO] Previous simulation context closed.}
    }

    set target_id [string tolower $target]
    switch -- $target_id {
        full    { set target_do [file join $proj_root simulation questa In_SOC_run_msim_rtl_verilog_codex.do] }
        dsp     { set target_do [file join $proj_root simulation questa run_dsp_upgrades_codex.do] }
        support { set target_do [file join $proj_root simulation questa run_support_blocks.do] }
        periph  { set target_do [file join $proj_root simulation questa run_apb_peripherals.do] }
        default {
            puts [format {[ERROR] Unknown target: %s} $target]
            codex_open_usage
            return -code error
        }
    }

    set ::codex_gui_target $target_id
    set ::codex_gui_manual $manual_mode

    puts ""
    puts "============================================================"
    puts [format {Codex GUI open target: %s} $target_id]
    puts [format {Manual mode          : %s} $manual_mode]
    puts [format {Project root         : %s} $proj_root]
    puts [format {DO file              : %s} $target_do]
    puts "============================================================"
    puts ""

    do $target_do
}

set codex_target_arg ""
set codex_flag_arg ""
set codex_manual_arg 0

catch {set codex_target_arg "$1"}
catch {set codex_flag_arg [string tolower "$2"]}

if {$codex_flag_arg eq "manual" || $codex_flag_arg eq "--manual"} {
    set codex_manual_arg 1
}

if {$codex_target_arg eq "" || $codex_target_arg eq "help" || $codex_target_arg eq "--help"} {
    codex_open_usage
} else {
    codex_open_target $codex_target_arg $codex_manual_arg
}
