# `safety_watchdog` IP Package

Date: 2026-05-03

Standalone package for the APB Safety Watchdog peripheral.

## Directory Layout

| Directory | Contents |
| --- | --- |
| `rtl/` | Watchdog RTL source |
| `tb/` | Standalone IP testbench (5 scenarios) |
| `scripts/` | Questa regression script and source file list |
| `docs/` | Documentation |
| `examples/` | Minimal integration example |

## Public Top Level

```systemverilog
safety_watchdog #(
    .DEFAULT_TIMEOUT(32'h00FF_FFFF) // ~335ms @ 50MHz
) u_wdt ( ... );
```

## Register Map

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| 0x0 | CTRL | RW | [0] Enable, [1] Lock (one-way set) |
| 0x4 | TIMEOUT | RW | Reload value (locked after CTRL.lock=1) |
| 0x8 | FEED | WO | Write 0x0D09_F00D to reload counter |
| 0xC | COUNT | RO | Current down-counter value |

## Run Regression

```bat
scripts\run_regression.bat
```

Expected: `[WDT-IP] SUMMARY PASS=5 FAIL=0`

## Test Scenarios

| ID | Test | Validates |
| --- | --- | --- |
| SC01 | Reset defaults | All registers at reset value, no reset output |
| SC02 | Enable/feed/counter | Counter decrements, magic feed reloads, wrong pattern rejected |
| SC03 | Lock mechanism | Lock prevents disable and timeout change |
| SC04 | Timeout reset | Counter=0 → wdt_reset_o asserted for 15+ cycles |
| SC05 | Disabled holds | Counter stays at timeout when disabled |
