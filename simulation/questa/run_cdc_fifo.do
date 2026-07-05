if {![file exists work]} { vlib work }
vmap work work
vlog -work work -sv rtl/lib/async_fifo_gray.sv
vlog -work work -sv sim/tb_cdc_async_fifo.sv
vsim -c work.tb_cdc_async_fifo -do "run -all; quit"
