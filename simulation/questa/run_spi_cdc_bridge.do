if {![file exists work]} { vlib work }
vmap work work
vlog -work work -sv rtl/lib/async_fifo_gray.sv
vlog -work work -sv rtl/periph/spi_adc_sclk_capture_rx.sv
vlog -work work -sv rtl/periph/spi_master/spi_adc_cdc_bridge.sv
vlog -work work -sv sim/tb_spi_cdc_bridge.sv
vsim -c work.tb_spi_cdc_bridge -do "run -all; quit"
