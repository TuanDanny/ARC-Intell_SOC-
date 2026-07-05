# `dsp_arc_detect` IP Verification

Date: 2026-04-26

This document records the standalone verification added for task T6.

## Regression Entry Point

From the IP package root:

```bat
scripts\run_regression.bat
```

From the repository root:

```bat
run_modelsim_here.bat ip_dsp --no-pause
```

The expected summary is:

```text
[DSP-IP] SUMMARY PASS=4 FAIL=0
```

## Standalone Testbench

The standalone testbench is:

- `tb/tb_dsp_arc_detect_ip.sv`

It instantiates `dsp_arc_detect_apb_wrapper` directly. It does not instantiate
`top_soc`, the CPU, SPI bridge, GPIO, UART, timer, Watchdog, or BIST blocks.

## Covered Checks

The current standalone regression covers:

- reset register values for the `ARC_BALANCED` boot profile
- APB read/write handshakes through the public wrapper
- unmapped read returning zero
- read-only write ignored by omission from the write decode
- `WIN_LEN` and spike threshold clamp behavior
- invalid profile sanitization to `SAFE_RESET`
- profile reload back to `ARC_BALANCED`
- stream restart state clear and restart counter clear
- standard arc FIRE event, telemetry capture, event counter, cause code
- `CLEAR` command behavior for event, peak, cause, and latch state

## Assertions

The assertion monitor is:

- `tb/dsp_arc_detect_ip_assertions.sv`

It checks the public IP boundary:

- control inputs are not X/Z in active operation
- ADC data is not X/Z while `adc_valid_i` is high
- APB address/write data are not X/Z during select
- `pready_o` follows the previous APB access phase
- `pslverr_o` remains deasserted
- APB address and write data stay stable from setup to access phase
- `prdata_o` is not X/Z during active operation

## Remaining Verification Work

This is a focused IP-level regression, not final verification closure. Remaining
work before production IP release:

- add coverage points for every register and profile
- add negative tests for illegal APB timing
- add latency measurement tests and archive cycle counts
- add long randomized sample-stream tests
- add formal or protocol-checker coverage for APB timing
- run the same package with multiple simulators if required by the release flow
