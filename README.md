# In_SOC

`In_SOC` is a mini SoC FPGA project for electrical arc and glowing-contact detection. The design integrates an 8-bit CPU, an APB interconnect, an SPI ADC frontend, a DSP-based detection core, Watchdog, BIST, GPIO, UART, and Timer peripherals.

The repository is prepared so another user can:
- clone the project
- run simulation from the project root
- inspect the major IP blocks and their register maps
- open the Quartus project without editing machine-specific absolute paths

## 1. Repository Overview

Main blocks:
- `cpu_8bit`: simple 8-bit control CPU with APB master interface
- `dsp_arc_detect`: detection core with arc, thermal, quiet-zone, and telemetry features
- `apb_spi_adc_bridge`: SPI ADC frontend + APB status/sample bridge
- `safety_watchdog`: watchdog peripheral
- `logic_bist`: BIST peripheral
- `apb_node`: APB interconnect
- `top_soc`: top-level SoC integration

Key supporting documents:
- `docs/ip/README.md`
- `docs/ip/ip_scope_and_rtl_alignment.md`
- `docs/ip/dsp_arc_detect.md`
- `docs/ip/dsp_arc_detect_interface.md`
- `docs/ip/dsp_arc_detect_register_map.md`
- `ip/dsp_arc_detect/README.md`
- `docs/ip/safety_watchdog.md`
- `docs/ip/logic_bist.md`
- `docs/ip/apb_spi_adc_bridge.md`
- `system_architecture_drawio_guide.md`
- `firmware/README.md`

## 2. Directory Layout

- `rtl/`
  - synthesizable RTL
- `sim/`
  - simulation testbenches
- `firmware/`
  - external CPU program images loaded with `$readmemh`
- `simulation/questa/`
  - Questa/ModelSim do-files
- `docs/ip/`
  - block-level reusable-IP style specs
- `ip/dsp_arc_detect/`
  - standalone package for the primary DSP IP candidate
- `script/`
  - visualizer / analysis scripts

## 3. Tool Requirements

Simulation:
- Siemens Questa / ModelSim with `vsim` available in `PATH`
- Intel/Altera simulation libraries installed for the selected tool version

Quartus:
- Intel Quartus Prime with Cyclone V device support

Recommended environment:
- Windows
- Open the project from the repository root

## 4. Quick Start

### 4.1 Run Full Simulation

From Windows Explorer:
- double-click `run_modelsim_here.bat`

From terminal:

```bat
run_modelsim_here.bat
```

This launches the full regression using `tb_professional`.

Expected result:
- compile reports `Errors: 0`
- simulation reaches `$finish`
- summary similar to:

```text
EXTRA SCENARIOS 11-26 SUMMARY: PASS=16 FAIL=0 KNOWN_ISSUE=0
```

### 4.2 Run DSP-Focused Regression

```bat
run_modelsim_here.bat dsp
```

Expected result:

```text
[DSP-UPG] SUMMARY PASS=9 FAIL=0
```

### 4.3 Run Standalone DSP IP Regression

```bat
run_modelsim_here.bat ip_dsp
```

Expected result:

```text
[DSP-IP] SUMMARY PASS=4 FAIL=0
```

### 4.4 Open ModelSim / Questa GUI

Full SoC bench:

```bat
run_modelsim_gui_here.bat
```

DSP-focused bench:

```bat
run_modelsim_gui_here.bat dsp
```

## 5. Main Simulation Entry Files

- `run_modelsim_here.bat`
- `run_modelsim_gui_here.bat`
- `simulation/questa/In_SOC_run_msim_rtl_verilog_codex.do`
- `simulation/questa/run_dsp_upgrades_codex.do`
- `ip/dsp_arc_detect/scripts/run_questa.do`

These scripts resolve the project root dynamically, so they do not depend on a fixed absolute machine path.

## 6. Quartus Project

Open:
- `In_SOC.qpf`

Main project file:
- `In_SOC.qsf`

Top-level RTL:
- `rtl/top_soc.sv`

Notes:
- active source files have been cleaned to avoid hardcoded personal machine paths
- generated build artifacts are excluded through `.gitignore`

## 7. Main Testbenches

- `sim/tb_professional.sv`
  - full system verification
- `sim/tb_dsp_upgrades.sv`
  - DSP-focused upgrade verification
- `ip/dsp_arc_detect/tb/tb_dsp_arc_detect_ip.sv`
  - standalone DSP IP verification through the public APB wrapper

## 8. CPU Firmware Image

The control CPU program is no longer hardcoded in RTL.

- default image: `firmware/cpu_program.hex`
- load mechanism: `$readmemh`
- RTL location: `rtl/core/cpu_8bit.sv`

This makes it possible to change startup policy or ISR behavior without editing the CPU datapath.

## 9. Reusable-IP Documentation

The current scope decision is documented in:
- `docs/ip/ip_scope_and_rtl_alignment.md`

Reusable-IP style documentation is provided for the main blocks:
- `dsp_arc_detect`
- `safety_watchdog`
- `logic_bist`
- `apb_spi_adc_bridge`

These documents describe:
- purpose
- interface
- register map
- reset/default behavior
- integration notes
- test evidence
- current limitations

## 10. Notes for GitHub / Clone Users

What should work after cloning:
- opening the Quartus project
- running simulation from repository root
- reading block-level IP documentation

What a user still needs locally:
- a valid Questa/ModelSim installation
- proper Intel/Altera simulation libraries
- Quartus installation if synthesis/fit is required

If `vsim` is not found:
- open the vendor-provided ModelSim/Questa command shell
- or add the simulator `bin` directory to `PATH`

## 11. Known Scope

This repository is strong as a mini-system project and now includes reusable-IP style documentation for the major blocks. It is not yet a full commercial IP catalog, but the main blocks are documented and verified in a reusable form.

The intended IP-catalog direction is:
- `dsp_arc_detect` is the primary IP candidate and now has the first standalone package under `ip/dsp_arc_detect/`.
- `apb_spi_adc_bridge`, `safety_watchdog`, and `logic_bist` are secondary IP candidates.
- `top_soc` is a reference integration/demo system, not the reusable IP boundary.

## 12. Suggested First Checks After Cloning

1. Open `In_SOC.qpf` in Quartus.
2. Run `run_modelsim_here.bat`.
3. Confirm the full regression summary passes.
4. Run `run_modelsim_here.bat ip_dsp`.
5. Read `docs/ip/ip_scope_and_rtl_alignment.md` for the current IP scope decision.
6. Read `docs/ip/README.md` for the IP block documentation.
