# `apb_spi_adc_bridge` IP Specification

## 1. Purpose

`apb_spi_adc_bridge` is the SPI acquisition bridge that connects the ADC-facing SPI frontend to:

- the SoC APB control/status space
- the DSP sample stream input

It is the block that turns raw SPI sample capture into a software-visible and DSP-visible stream source.

## 2. Top-Level Interface

Source RTL: `rtl/periph/spi_master/apb_spi_adc_bridge.sv`

### Clock / Reset

- `clk_i`
- `rst_ni`

### APB Slave Interface

- `paddr_i[4:0]`
- `pwdata_i[31:0]`
- `psel_i`
- `penable_i`
- `pwrite_i`
- `prdata_o[31:0]`
- `pready_o`
- `pslverr_o`

### ADC SPI Pins

- `adc_miso_i`
- `adc_mosi_o`
- `adc_sclk_o`
- `adc_csn_o`

### Stream / Status Outputs

- `sample_data_o[15:0]`
- `sample_valid_o`
- `busy_o`
- `frame_active_o`
- `overrun_o`
- `stream_restart_o`

## 3. Functional Role

The bridge wraps the low-level SPI receiver and provides three useful views of the same activity:

1. **Live sample stream** for DSP
2. **Buffered shadow sample** for software reads
3. **Control/status plane** for software management

This is why the block is called a “bridge” rather than just an SPI master.

## 4. Register Map

All offsets are relative to `SPI_BASE_ADDR = 0x0000_7000`.

| Offset | Access | Name | Description |
| --- | --- | --- | --- |
| `0x00` | RW | `CTRL` | enable, continuous mode, start pulse, clear status |
| `0x04` | RO | `STATUS` | mode and sticky status bits |
| `0x08` | RW | `CMD` | optional command payload toward frontend |
| `0x0C` | RO | `SAMPLE` | latest shadowed sample for software |
| `0x10` | RO | `COUNT` | frame count and overwrite count |
| `0x14` | RO | `INFO` | implementation/build information |

### `STATUS` bits

Current implementation exposes:

- bit0: `enable`
- bit1: `continuous`
- bit2: `busy`
- bit3: `frame_active`
- bit4: `sample_valid_sticky`
- bit5: `sample_overwrite_sticky`
- bit6: `frontend_overrun_sticky`

## 5. Reset / Default Behavior

After reset:

- bridge is enabled
- continuous streaming is enabled
- command register clears
- sample/status counters clear

This default makes sense for the current demo SoC because DSP is expected to see a live sample stream soon after boot.

## 6. Stream Contract

### Toward DSP

- `sample_data_o` and `sample_valid_o` are the live frontend outputs
- DSP sees samples immediately; there is no downstream ready/backpressure contract

### Toward Software

- a shadow sample register stores the latest captured sample
- `sample_valid_sticky` tells software that unread data exists
- reading `SAMPLE` clears the sticky valid flag
- if a new sample arrives before software reads the previous one, `sample_overwrite_sticky` is raised

This “dual view” is a strong practical design choice:

- DSP gets low-latency live data
- software gets a readable shadow copy

## 7. Stream Restart Semantics

The block emits `stream_restart_o` when acquisition restarts. In the current SoC, this signal is consumed by the DSP so the detector can:

- clear sample-pair history
- avoid false first-difference artifacts
- re-enter its stream holdoff behavior cleanly

This is one of the key integration contracts between bridge and detector.

## 8. Overrun Semantics

Current implementation exposes:

- `overrun_o` as a bridge/frontend-side telemetry pulse
- `frontend_overrun_sticky` for software visibility

Important architectural clarification:

- this is **not** currently a detector-side backpressure fault source
- DSP does not consume a true downstream-overrun handshake from this bridge

That design choice is deliberate in the current project because the DSP path is fire-and-forget.

## 9. System Integration in `top_soc`

`apb_spi_adc_bridge` is the normal live sample source for the DSP path.

Inside `top_soc`:

- `sample_data_o` becomes the normal DSP sample input unless BIST is active
- `sample_valid_o` becomes the normal DSP sample valid unless BIST is active
- `stream_restart_o` is passed into `dsp_arc_detect`

This makes the bridge part of the detector contract, not only a peripheral.

## 10. Verification Evidence

Current regressions validate:

- SPI capture integration
- sticky sample behavior
- sample overwrite sticky behavior
- continuous stream behavior
- stream restart interaction with DSP

This block is also exercised indirectly through DSP and full-system scenarios because it is the default live source for the detector.

## 11. Reuse Notes

What is reusable already:

- APB-programmable SPI-to-stream bridge
- explicit status/telemetry model
- restart signaling for downstream consumers
- software-readable shadow sample behavior

What still limits standalone IP maturity:

- no true downstream ready/backpressure protocol
- no integrated FIFO buffering between SPI capture and downstream consumer
- command path is simple and project-shaped
- current integration is tuned for one ADC-style source rather than a generic streaming fabric

## 12. Honest Positioning

The strongest accurate description today is:

“`apb_spi_adc_bridge` is a reusable APB-configurable SPI acquisition bridge that serves both software telemetry and low-latency DSP streaming in the current SoC.”

That is a solid and defensible IP-style description.
