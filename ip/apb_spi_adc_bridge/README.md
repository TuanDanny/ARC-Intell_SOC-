# `apb_spi_adc_bridge` IP Package

Date: 2026-05-03

Standalone package for the APB SPI ADC acquisition bridge.

## Directory Layout

| Directory | Contents |
| --- | --- |
| `rtl/` | Bridge + SPI stream receiver RTL |
| `tb/` | Standalone IP testbench with fake ADC model (5 scenarios) |
| `scripts/` | Questa regression script and source file list |
| `docs/` | Documentation |
| `examples/` | Minimal integration example |

## Public Top Level

```systemverilog
apb_spi_adc_bridge #(
    .SAMPLE_WIDTH(16),
    .SCLK_DIV(2),
    .CPOL(1'b0), .CPHA(1'b0),
    .MSB_FIRST(1'b1)
) u_spi ( ... );
```

## Register Map

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| 0x00 | CTRL | RW | [0]enable [1]continuous [2]start [3]clear_status |
| 0x04 | STATUS | RO | enable/cont/busy/frame/valid/overwrite/overrun |
| 0x08 | CMD | RW | Command word (if CMD_WIDTH>0) |
| 0x0C | SAMPLE | RO | Last captured sample (read clears valid) |
| 0x10 | COUNT | RO | [15:0]frame_count [31:16]overwrite_count |
| 0x14 | INFO | RO | Hardcoded SPI configuration readback |

## Run Regression

```bat
scripts\run_regression.bat
```

Expected: `[SPI-IP] SUMMARY PASS=5 FAIL=0`

## Test Scenarios

| ID | Test | Validates |
| --- | --- | --- |
| SC01 | Reset defaults | enable=1, continuous=1, INFO readback |
| SC02 | Capture sample | Fake ADC 0xBEEF → sample_data_o match |
| SC03 | Disable/re-enable | Stop→clear→restart with new ADC value |
| SC04 | SPI signal integrity | CS low during frame, SCLK toggling, CS high after |
| SC05 | Stream restart | Disable→enable edge generates restart pulse |
