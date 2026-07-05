# IP Specification Set

This folder contains implementation-oriented specifications for the four main reusable blocks in the current `In_SOC` project:

- `dsp_arc_detect`
- `safety_watchdog`
- `logic_bist`
- `apb_spi_adc_bridge`

Primary DSP IP support documents:

- `dsp_arc_detect_interface.md`
- `dsp_arc_detect_register_map.md`
- `../../ip/dsp_arc_detect/README.md`
- `../../ip/dsp_arc_detect/docs/verification.md`

Start with `ip_scope_and_rtl_alignment.md` when the goal is to answer whether the project is already a complete IP catalog or still a mini-SoC with reusable-IP candidates. That file records the current scope decision and the documentation claims that are safe relative to the RTL.

The documents are intentionally written from the current RTL, not from an idealized future plan. Each spec answers the questions that usually appear in a design review or committee defense:

- What is the purpose of the block?
- What interface contract does it expose?
- What is the stable register map?
- What reset/default behavior should other blocks assume?
- What latency/handshake assumptions exist?
- What tests currently prove the block works?
- What limitations still remain before the block can be called a fully reusable standalone IP?

Suggested reading order for a system-level review:

1. `ip_scope_and_rtl_alignment.md`
2. `apb_spi_adc_bridge.md`
3. `dsp_arc_detect.md`
4. `safety_watchdog.md`
5. `logic_bist.md`

Suggested reading order for a committee / IP-catalog discussion:

1. `ip_scope_and_rtl_alignment.md`
2. `dsp_arc_detect.md`
3. `dsp_arc_detect_interface.md`
4. `dsp_arc_detect_register_map.md`
5. `../../ip/dsp_arc_detect/README.md`
6. `../../ip/dsp_arc_detect/docs/verification.md`
7. `safety_watchdog.md`
8. `logic_bist.md`
9. `apb_spi_adc_bridge.md`
