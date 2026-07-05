# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`In_SOC` is a mini-SoC FPGA prototype (SystemVerilog, Intel/Altera Cyclone V target) for electrical arc and glowing-contact detection. It integrates an 8-bit control CPU, an APB3 interconnect, an SPI ADC frontend, a DSP-based arc/thermal detection core, a watchdog, a functional BIST block, and GPIO/UART/Timer peripherals.

The project is explicitly positioned as **a verified mini-SoC prototype with reusable-IP candidates**, not a finished commercial IP catalog. See `docs/ip/ip_scope_and_rtl_alignment.md` before writing or editing any documentation/report claims — it defines exactly which wording is safe per block (e.g. "basic APB watchdog" not "windowed safety watchdog"; "functional BIST" not "scan LBIST"). Read it whenever asked to describe capabilities, write docs, or update the README.

## Commands

All simulation is Questa/ModelSim-based; `vsim` must be on `PATH`. Run from the repository root.

**Note:** the top-level `README.md` describes `run_modelsim_here.bat` as living at the repo root — it does not. The real, current entry points are under `run/scripts/`, documented authoritatively in `run/README.md`. Prefer `run/README.md` over the root README for exact invocation paths.

```bat
cd /d D:\APP\Quatus_Workspace\In_SOC

REM Full SoC regression (tb_professional) — expect "EXTRA SCENARIOS 11-26 SUMMARY: PASS=16 FAIL=0 KNOWN_ISSUE=0"
run\scripts\run_modelsim_here.bat full --no-pause

REM DSP-focused regression (tb_dsp_upgrades) — expect "[DSP-UPG] SUMMARY PASS=9 FAIL=0"
run\scripts\run_modelsim_here.bat dsp --no-pause

REM Standalone dsp_arc_detect IP regression — expect "[DSP-IP] SUMMARY PASS=4 FAIL=0"
run\scripts\run_modelsim_here.bat ip_dsp --no-pause

REM Support blocks smoke test (tb_support_blocks) — expect "[SUPPORT] SUMMARY PASS=3 FAIL=0"
run\scripts\run_modelsim_here.bat support --no-pause

REM APB peripherals smoke test (tb_apb_peripherals) — expect "[PERIPH] SUMMARY PASS=3 FAIL=0"
run\scripts\run_modelsim_here.bat periph --no-pause

REM list all targets / usage
run\scripts\run_modelsim_here.bat list
```

Standalone IP regressions (each IP package is independently runnable and has its own `scripts/run_regression.bat` inside `ip/<block>/`, or via the `run/scripts/ip_*/` wrappers which point back at the `ip/` source):

```bat
run\scripts\ip_wdt\run_regression.bat --no-pause
run\scripts\ip_bist\run_regression.bat --no-pause
run\scripts\ip_spi\run_regression.bat --no-pause
run\scripts\ip_dsp\run_regression.bat --no-pause
```

GUI (waveform) launch, same targets:

```bat
run\scripts\run_modelsim_gui_here.bat        REM full SoC bench
run\scripts\run_modelsim_gui_here.bat dsp    REM DSP-focused bench
run\scripts\run_full_gui.bat
run\scripts\run_dsp_gui.bat
run\scripts\run_periph_gui.bat
run\scripts\run_support_gui.bat
```

Regression pass/fail is determined by grepping the `transcript` file for a `Cannot open macro file` failure marker and the expected summary token above (see `run/scripts/run_modelsim_here.bat`'s `:register_targets` — that's also where to add a new regression target: ID, title, `.do` file, summary token).

Evidence logs from prior passing runs live in `run/logs/transcript_*.txt` for reference/comparison.

Quartus synthesis: open `In_SOC.qpf` in Quartus Prime (Cyclone V device support required). Main project file is `In_SOC.qsf`; top-level RTL is `rtl/top_soc.sv`.

There is no software build/lint toolchain (no npm/pytest/etc.) — this is a hardware RTL project; "testing" means running the Questa regressions above and checking the transcript summary.

## Architecture

### Top-level integration (`rtl/top_soc.sv`)

`top_soc` wires together an APB3 interconnect (`apb_node`, 8 slaves) with one APB master (the CPU). Slave map (also defined in `rtl/include/config.sv` as base addresses):

```
[0] RAM (internal, 0x0000_0000)   [1] DSP (0x0000_1000)  [2] GPIO (0x0000_2000)  [3] UART (0x0000_3000)
[4] TIMER (0x0000_4000)           [5] Watchdog (0x0000_5000)  [6] BIST (0x0000_6000)  [7] SPI ADC bridge (0x0000_7000)
```

Signal flow: SPI ADC (`apb_spi_adc_bridge`) → sample stream → BIST-injection mux (`logic_bist` can substitute its own LFSR stimulus for the live SPI stream via `bist_active_mode`) → `dsp_arc_detect` core → `irq_arc_o` (masked to 0 while BIST is driving) → CPU high-priority IRQ. The watchdog can force a system reset (`wdt_reset_req` held for `WDT_RESET_HOLD_CYCLES` cycles) independent of the external async reset; both feed `rstgen` for a synchronized `rst_no` used everywhere downstream.

`top_soc` is the reference/demo integration only — **not** the reusable-IP packaging boundary (see IP scope doc above).

### IP packaging model — two copies of each block, kept in sync manually

Each reusable block exists in two places and there is **no automated sync** between them:

- `rtl/periph/*.sv` (and `rtl/include/`) — the copy integrated into `top_soc` for the full-SoC regression.
- `ip/<block_name>/` — a standalone, self-contained package (own `rtl/`, `rtl/include/`, `tb/`, `docs/`, `scripts/`, `examples/README.md`) that can be regressed independently of `top_soc`, intended as the "drop-in" reusable form.

Blocks packaged this way: `dsp_arc_detect` (primary IP candidate — richest register map, telemetry, has an APB wrapper `dsp_arc_detect_apb_wrapper.sv` as its public entry point, not the core `dsp_arc_detect.sv` directly), `apb_spi_adc_bridge`, `safety_watchdog`, `logic_bist`. When fixing a bug or changing behavior in one of these blocks, **check whether the fix needs to be applied in both `rtl/periph/...` and `ip/<block>/rtl/...`** — they are expected to be equivalent implementations, not different versions.

`cpu_8bit`, `apb_node`, `apb_gpio`, `apb_uart_wrap`, `apb_adv_timer` are project-specific/support blocks, not packaged as standalone IP.

### CPU (`rtl/core/cpu_8bit.sv`)

Simple 8-bit control CPU, APB master, ISA opcodes: `NOP LDI ADD SUB AND JMP BEQ STR LDR ... RET`. Program image is loaded externally via `$readmemh(ROM_INIT_FILE, instr_mem)` from `firmware/cpu_program.hex` (default `ROM_INIT_FILE` parameter) — the program is **not** hardcoded in RTL. Firmware memory layout convention: `0x00` reset vector, `0x01..0x03` arc-fault ISR, `0x04..0x07` main startup, `0x08` idle loop, `0x09` timer ISR. Supports nested IRQ shadow state (arc IRQ can preempt an in-flight timer ISR).

### Documentation map

- `docs/ip/ip_scope_and_rtl_alignment.md` — **read first** for any claim about what's implemented vs. planned; defines safe vs. unsafe wording per block.
- `docs/ip/README.md` — index/reading order for the per-block IP specs (interface, register map, reset behavior, test evidence, limitations) for `dsp_arc_detect`, `safety_watchdog`, `logic_bist`, `apb_spi_adc_bridge`.
- `ip/dsp_arc_detect/docs/verification.md`, `ip/dsp_arc_detect/README.md` — standalone DSP IP package docs.
- `plan/*.md` (`dsp_plan.md`, `watchdog_plan.md`, `bist_plan.md`, `cdc_async_fifo_plan.md`) — future-work plans; features described here are **not yet implemented** unless cross-checked against RTL. Never describe a `plan/` item as done.
- `run/README.md` (Vietnamese) — authoritative, current instructions for the `run/` folder layout and script invocation; more current than the root `README.md`'s quick-start section.
- `firmware/README.md` — firmware image format and memory map.
- `script/` + `docs/script_readme.md` (Vietnamese) — standalone VCD-based "flow visualizer" tool (v1/v2/v3, Node.js, run via `.cmd` launchers) for visualizing waveform/architecture; unrelated to the Questa regressions and not required for simulation.

### Verification structure

- `sim/tb_professional.sv` — full-system testbench (the `full` regression target).
- `sim/tb_dsp_upgrades.sv` — DSP-focused upgrade verification (`dsp` target).
- `sim/tb_support_blocks.sv`, `sim/tb_apb_peripherals.sv` — smaller smoke regressions (`support`, `periph` targets).
- `ip/<block>/tb/tb_<block>_ip.sv` (+ `*_assertions.sv` for `dsp_arc_detect`) — standalone per-IP testbenches, run through the public wrapper only.
- Regression pass/fail is transcript-grep based (see Commands section), not a SystemVerilog/UVM scoreboard exit code — always check the printed SUMMARY line, not just simulator exit status.
