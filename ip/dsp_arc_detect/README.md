# `dsp_arc_detect` IP Package

Date: 2026-04-26

This directory is the standalone package for the primary IP candidate in the
`In_SOC` project.

## Directory Layout

| Directory | Contents |
| --- | --- |
| `rtl/` | Packaged RTL source for the detector core and APB wrapper |
| `rtl/include/` | Local APB/config include files required by the packaged RTL |
| `tb/` | Standalone IP testbench and assertion monitor |
| `docs/` | Interface, register map, design, and verification notes |
| `scripts/` | Questa regression script and source file list |
| `examples/` | Minimal integration example using the public APB wrapper |

## Public Top Level

Use this module as the package entry point:

```systemverilog
dsp_arc_detect_apb_wrapper
```

The implementation core is:

```systemverilog
dsp_arc_detect
```

Do not use `top_soc` as the reusable IP boundary. `top_soc` remains the project
reference integration.

## Run Regression

From this directory:

```bat
scripts\run_regression.bat
```

Expected result:

```text
[DSP-IP] SUMMARY PASS=4 FAIL=0
```

## Source Order

For tools that need explicit order:

1. `rtl/include/config.sv`
2. `rtl/include/apb_bus.sv`
3. `rtl/dsp_arc_detect.sv`
4. `rtl/dsp_arc_detect_apb_wrapper.sv`
5. `tb/dsp_arc_detect_ip_assertions.sv`
6. `tb/tb_dsp_arc_detect_ip.sv`

## Current Release Status

This package completes the first standalone directory structure and IP-level
regression for `dsp_arc_detect`. It is closer to a reusable IP core, but it is
not yet a final vendor-ready release because timing reports, coverage closure,
version metadata, and broader assertion/latency evidence still need to be added.
