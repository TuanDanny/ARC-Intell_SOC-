# IP Scope And RTL Alignment

Date: 2026-04-26

This document closes two review tasks for the current `In_SOC` project:

- T1: define which blocks are reusable IP candidates and which blocks are reference/demo integration only
- T2: align project documentation claims with the behavior that is actually implemented in RTL today

The intent is to keep the project defensible in a design review. Future plans are still useful, but they must be labeled as future work rather than described as completed RTL.

## 1. Current Project Position

`In_SOC` should currently be described as:

> A mini-SoC FPGA prototype for arc and glowing-contact detection, with several reusable-IP candidates documented and verified inside a reference SoC integration.

It should not yet be described as:

> A complete commercial IP catalog ready for drop-in third-party integration.

The top-level SoC proves system behavior. The reusable IP work should be packaged block by block.

## 2. IP Scope Decision

| Block | Current Classification | Role | Reason |
| --- | --- | --- | --- |
| `dsp_arc_detect` | Primary IP candidate | Main detection IP | Richest register map, telemetry, profile support, directed DSP tests |
| `apb_spi_adc_bridge` | Secondary IP candidate | ADC SPI-to-stream bridge | APB control/status plus live sample stream for DSP |
| `safety_watchdog` | Secondary/basic IP candidate | Basic watchdog peripheral | Reusable as a simple APB watchdog, but not yet independent/windowed safety watchdog |
| `logic_bist` | Secondary/diagnostic IP candidate | Functional BIST helper | Useful LFSR/MISR stimulus path, but not full production scan LBIST |
| `cpu_8bit` | Project-specific control core | Control-plane CPU | Useful for this SoC, but not packaged as a standalone CPU IP yet |
| `apb_node` | Project support block | APB interconnect | Small reusable support block, but currently tied to this address map/integration style |
| `apb_gpio`, `apb_uart_wrap`, `apb_adv_timer` | Integrated peripherals | Peripheral support | Useful blocks, but not the main IP value of the project |
| `top_soc` | Reference design only | Integration/demo system | Demonstrates how the IP candidates work together; should not be sold as one monolithic IP core |

## 3. Recommended IP Catalog Shape

The project should evolve into a small IP set:

1. `dsp_arc_detect`
   - main catalog IP
   - first block to package and harden

2. `apb_spi_adc_bridge`
   - optional companion IP for acquisition
   - useful when the DSP is used with an external SPI ADC

3. `safety_watchdog`
   - basic watchdog IP today
   - can become safety-watchdog v2 after independent/windowed features are implemented

4. `logic_bist`
   - functional diagnostic helper today
   - can become stronger after on-chip golden signature compare and pass/fail status are added

5. `top_soc`
   - reference integration
   - should remain a demo and regression target, not the IP package boundary

## 4. RTL-Aligned Claim Matrix

| Topic | RTL Status Today | Safe Documentation Wording | Avoid Claiming Until Implemented |
| --- | --- | --- | --- |
| SoC scope | Full mini-system RTL exists in `top_soc` | Mini-SoC FPGA prototype/reference design | Complete commercial IP catalog |
| DSP arc detection | Implemented with diff, adaptive threshold support, spike window, thermal path, quiet-zone path, telemetry | Configurable APB-based arc/thermal detection IP candidate | Fully certified detector or guaranteed field accuracy |
| DSP latency | Tests show functional response; no packaged timing/latency report yet | Low-latency hardware detector; latency should be measured per configuration | Guaranteed sub-10 us response for every profile/waveform |
| SPI frontend | SPI receiver plus APB bridge and live stream are implemented | APB-configurable SPI acquisition bridge with software shadow sample and stream output | True FIFO/CDC/backpressure architecture |
| Watchdog | Basic APB watchdog with magic feed, lock, timeout, reset pulse | Basic APB-configurable watchdog peripheral | Independent-clock, windowed, retention-grade safety watchdog |
| BIST | LFSR/MISR functional stimulus path exists | Functional BIST helper for DSP-path validation | Full scan LBIST, on-chip golden compare, production DFT coverage |
| PMU/power modes | Clock-gating support cells exist; no integrated PMU policy RTL | Support cells exist for clock gating; PMU is future system work | Complete PMU, sleep/active policy, independent power domains |
| CPU firmware | External ROM image loads through `$readmemh`; simple ISR/startup behavior | Simple project control firmware image | Complete production firmware or full toolchain release |
| Verification | Directed full-system and DSP regressions pass | Directed regression evidence exists | UVM-grade coverage closure, formal proof, production qualification |
| Synthesis/timing | Quartus Analysis & Elaboration passes; full fit/timing package not yet documented | Quartus project is prepared and A&E has passed | Timing-closed FPGA/ASIC implementation package |

## 5. Documentation Alignment Rules

When updating the report, slides, README, or IP docs, use these rules:

- Use "implemented" only for behavior visible in current RTL.
- Use "planned", "future work", or "next version" for features listed in `plan/dsp_plan.md`, `plan/watchdog_plan.md`, or `plan/bist_plan.md` but not yet implemented.
- Describe `top_soc` as a reference integration, not a reusable IP boundary.
- Describe `dsp_arc_detect` as the main IP candidate.
- Keep safety language precise. Do not imply ISO 26262 or UL 1699 certification. It is acceptable to say the design is inspired by safety requirements or targets fast detection.
- Keep BIST language precise. The current block is functional BIST, not scan LBIST.
- Keep Watchdog language precise. The current block is basic APB watchdog, not independent-windowed safety watchdog.
- Keep SPI language precise. The current bridge is fire-and-forget streaming with APB telemetry, not a FIFO/backpressure fabric.

## 6. Minimum Definition Of Done For A Complete IP Core

A block should only be called a complete reusable IP core after it has:

- standalone RTL package
- clean top-level wrapper with stable ports
- documented interface contract
- stable register map with access type, reset value, and bit fields
- standalone testbench and regression script
- protocol/behavior assertions for the critical contracts
- synthesis report
- timing report or at least timing assumptions
- integration guide
- known limitations
- version and changelog

## 7. First IP To Complete

The first block to package as a complete IP core should be `dsp_arc_detect`.

Reason:

- it is the academic and product heart of the project
- it already has the richest register map
- it already exposes telemetry useful for bring-up
- it already has DSP-focused tests
- it is the block most directly connected to the project thesis

Recommended next packaging tasks for `dsp_arc_detect`:

1. Create a standalone `ip/dsp_arc_detect/` package layout.
2. Provide an APB wrapper option that does not require the project-specific `APB_BUS` interface.
3. Add a programmer's model with reset values for every register.
4. Add latency measurement tests and document the measured cycle counts.
5. Add assertions for APB access, clear behavior, event counter behavior, and cause-code behavior.
6. Run and archive synthesis/timing evidence.

## 8. Review-Safe Summary

Use this short wording in review:

> The current project is a verified mini-SoC FPGA prototype. The DSP, SPI bridge, Watchdog, and BIST blocks are documented as reusable-IP candidates, with `dsp_arc_detect` selected as the primary IP to package first. The design is not yet a complete commercial IP catalog; remaining work includes standalone packaging, stronger verification, timing/resource evidence, and strict alignment between report claims and implemented RTL.

