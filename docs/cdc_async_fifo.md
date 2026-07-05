# CDC Async FIFO Implementation Notes

## Status

This project now has standalone CDC RTL deliverables for the SPI ADC to DSP path:

- `rtl/lib/async_fifo_gray.sv`
- `rtl/periph/spi_adc_sclk_capture_rx.sv`
- `rtl/periph/spi_master/spi_adc_cdc_bridge.sv`
- `sim/tb_cdc_async_fifo.sv`
- `sim/tb_spi_cdc_bridge.sv`
- `simulation/questa/run_cdc_fifo.do`
- `simulation/questa/run_spi_cdc_bridge.do`
- `run/scripts/run_cdc_regression.bat`

## Architecture

```text
SPI clock domain                              System clock domain
----------------                              -------------------
spi_clk_i                                     sys_clk_i / 50 MHz
spi_adc_sclk_capture_rx                       DSP-facing sample stream
sample_data + sample_valid                    sys_sample_data + sys_sample_valid
        │                                             ▲
        ▼                                             │
async_fifo_gray write side ── Gray pointer CDC ── async_fifo_gray read side
```

## CDC method

- Sample data is written into FIFO memory in `spi_clk_i` domain.
- Sample data is read in `sys_clk_i` domain.
- Write and read pointers are converted to Gray code.
- Gray pointers cross clock domains through 2-flop synchronizers.
- `full_o` is generated in write clock domain.
- `empty_o` is generated in read clock domain.
- Multi-bit sample data bus does not cross clock domains directly.

## Verification targets

Expected outputs:

```text
[CDC-FIFO] RESULT: PASS
[SPI-CDC] RESULT: PASS
```

Run:

```bat
run\scripts\run_cdc_regression.bat
```

Or run individual Questa scripts:

```bat
vsim -c -do simulation/questa/run_cdc_fifo.do
vsim -c -do simulation/questa/run_spi_cdc_bridge.do
```

## Defense wording

Correct statement after these standalone modules are used/integrated:

> Dữ liệu ADC được chốt trong miền SPI clock và chỉ đi sang miền system clock qua async FIFO. FIFO dùng write/read pointer mã Gray, mỗi pointer được đồng bộ qua 2 flip-flop trước khi tính full/empty. DSP chỉ nhận `sample_valid` ở miền 50 MHz sau khi FIFO xác nhận có đủ một mẫu 16-bit hoàn chỉnh.

Important limitation:

- Existing `top_soc.sv` still uses the legacy system-clocked SPI master path unless explicitly refactored to instantiate `spi_adc_cdc_bridge` and expose independent `adc_sclk_i/adc_csn_i` pins.
- Therefore, the CDC claim is valid for the new CDC bridge deliverable and becomes full top-level claim only after top-level integration.
