# `logic_bist` IP Package

Date: 2026-05-03

Standalone package for the Logic BIST (Built-In Self-Test) functional helper.

## Directory Layout

| Directory | Contents |
| --- | --- |
| `rtl/` | BIST RTL source (LFSR/MISR) |
| `tb/` | Standalone IP testbench (5 scenarios) |
| `scripts/` | Questa regression script and source file list |
| `docs/` | Documentation |
| `examples/` | Minimal integration example |

## Public Top Level

```systemverilog
logic_bist #(
    .DATA_WIDTH(16),
    .LFSR_POLY(16'hB400)
) u_bist ( ... );
```

## Register Map

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| 0x00 | CTRL | RW | [0] Start (self-clearing), [1] Reset |
| 0x04 | CONFIG | RW | [15:0] Test length (cycles) |
| 0x08 | SEED | RW | [15:0] LFSR initial seed |
| 0x0C | SIGNATURE | RO | [15:0] MISR result |
| 0x10 | STATUS | RO | [0] Busy, [1] Done, [2] Error (zero sig) |

## Run Regression

```bat
scripts\run_regression.bat
```

Expected: `[BIST-IP] SUMMARY PASS=5 FAIL=0`

## Test Scenarios

| ID | Test | Validates |
| --- | --- | --- |
| SC01 | Reset defaults | Default test length=100, seed=0xACE1 |
| SC02 | Run BIST cycle | LFSR generates patterns, MISR compresses IRQ, non-zero signature |
| SC03 | Zero signature error | All-zero IRQ → signature=0 → error flag set |
| SC04 | Reset command | Mid-run reset clears busy/done |
| SC05 | Seed protection | Zero seed → falls back to 0xACE1 |
