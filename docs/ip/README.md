# IP Specification Set

This folder contains implementation-oriented specifications for the four main reusable blocks in the current `In_SOC` project:

- `dsp_arc_detect`
- `safety_watchdog`
- `logic_bist`
- `apb_spi_adc_bridge`

The documents are intentionally written from the current RTL, not from an idealized future plan. Each spec answers the questions that usually appear in a design review or committee defense:

- What is the purpose of the block?
- What interface contract does it expose?
- What is the stable register map?
- What reset/default behavior should other blocks assume?
- What latency/handshake assumptions exist?
- What tests currently prove the block works?
- What limitations still remain before the block can be called a fully reusable standalone IP?

Suggested reading order for a system-level review:

1. `apb_spi_adc_bridge.md`
2. `dsp_arc_detect.md`
3. `safety_watchdog.md`
4. `logic_bist.md`

Suggested reading order for a committee / IP-catalog discussion:

1. `dsp_arc_detect.md`
2. `safety_watchdog.md`
3. `logic_bist.md`
4. `apb_spi_adc_bridge.md`
