# `dsp_arc_detect` Interface Standardization

Date: 2026-04-26

This document completes task T3 for the primary IP candidate. It defines a cleaner integration boundary for `dsp_arc_detect` without changing the existing SoC integration.

## 1. Interface Decision

The RTL core remains:

- `rtl/periph/dsp_arc_detect.sv`

It still uses the project-local `APB_BUS` interface internally because that is how `top_soc` and the existing regressions are already wired.

The external reusable-IP entry point is now:

- `rtl/periph/dsp_arc_detect_apb_wrapper.sv`

Use this wrapper when integrating the detector outside `top_soc`.

## 2. Why The Wrapper Exists

The original core is convenient inside this project, but an external integrator should not be forced to instantiate the project-specific `APB_BUS` interface directly. The wrapper exposes plain APB-style ports:

- `paddr_i`
- `pwdata_i`
- `pwrite_i`
- `psel_i`
- `penable_i`
- `prdata_o`
- `pready_o`
- `pslverr_o`

This makes the IP easier to package, lint, document, and connect to another SoC.

## 3. Recommended Integration Boundary

Use `dsp_arc_detect_apb_wrapper` as the public top-level module for the IP package.

Keep `dsp_arc_detect` as the implementation core.

Do not use `top_soc` as the IP boundary. `top_soc` is a reference integration that shows how the detector is connected to SPI, BIST, CPU, GPIO, and reset policy.

## 4. Public Wrapper Ports

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk_i` | Input | 1 | Detector/APB clock |
| `rst_ni` | Input | 1 | Active-low reset |
| `adc_data_i` | Input | `DATA_WIDTH` | Signed ADC sample |
| `adc_valid_i` | Input | 1 | One-cycle sample-valid pulse |
| `stream_restart_i` | Input | 1 | One-cycle upstream stream restart pulse |
| `paddr_i` | Input | 32 | APB byte address; low byte selects detector register |
| `pwdata_i` | Input | 32 | APB write data |
| `pwrite_i` | Input | 1 | APB write control |
| `psel_i` | Input | 1 | APB select |
| `penable_i` | Input | 1 | APB access phase |
| `prdata_o` | Output | 32 | APB read data |
| `pready_o` | Output | 1 | APB ready response |
| `pslverr_o` | Output | 1 | APB error response |
| `irq_arc_o` | Output | 1 | Detector trip interrupt |

## 5. Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `DATA_WIDTH` | 16 | ADC sample width |
| `CNT_WIDTH` | 16 | Integrator/counter datapath width |

The APB data and address widths are intentionally fixed at 32 bits in the public wrapper. That matches the current register map and avoids ambiguous partial-width integration.

## 6. APB Contract

- APB accesses are accepted when `psel_i && penable_i`.
- Register offsets are decoded from `paddr_i[7:0]`.
- Reads are non-destructive unless a register is explicitly documented otherwise.
- Writes to read-only offsets are ignored.
- Reads from unmapped offsets return zero.
- `pslverr_o` is currently always zero.
- `pready_o` pulses high for a selected access in the detector access phase.

## 7. Stream Contract

- The detector updates from the sample stream only when `adc_valid_i == 1`.
- `adc_data_i` must be stable for the active edge where `adc_valid_i` is sampled.
- The stream has no ready/backpressure signal.
- `stream_restart_i` is a trusted pulse from upstream logic. It clears sample-pair history and restarts holdoff-sensitive state.

## 8. Source Files For Standalone Compile

Minimum source set:

1. `rtl/include/config.sv`
2. `rtl/include/apb_bus.sv`
3. `rtl/periph/dsp_arc_detect.sv`
4. `rtl/periph/dsp_arc_detect_apb_wrapper.sv`

Compile the wrapper after the core in tool flows that require declaration-before-use.

## 9. Current Limitation

This wrapper standardizes the public port boundary, but it is not yet a full vendor IP package. Remaining work for a complete IP package includes standalone filelists, assertions, synthesis reports, timing reports, version metadata, and example integration tests.

