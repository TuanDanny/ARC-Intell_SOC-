# `dsp_arc_detect` IP Specification

## 1. Purpose

`dsp_arc_detect` is the main detection IP in the project. It receives a signed ADC sample stream and produces a high-priority protection interrupt `irq_arc_o` when the evidence supports one of the supported fault classes:

- standard arc event
- dense spike / burst event
- thermal / glowing-contact style event
- quiet-zone / zero-cross assisted event

The block is implemented as an APB-configurable detector with rich telemetry. In the current project, this is the strongest IP candidate because it already exposes:

- a stable slave interface
- a detailed register map
- runtime tuning hooks
- explicit trip cause telemetry
- directed verification scenarios

## 2. Top-Level Interface

Source RTL: `rtl/periph/dsp_arc_detect.sv`

### Clock / Reset

- `clk_i`: detector clock
- `rst_ni`: active-low reset

### Stream Input

- `adc_data_i[15:0]`: signed ADC sample stream
- `adc_valid_i`: sample valid pulse
- `stream_restart_i`: one-cycle pulse indicating stream restart; detector clears pair-history and internal holdoff-sensitive state

### APB Control

- `APB_BUS apb_slv`: APB slave interface for configuration, status and telemetry

### Output

- `irq_arc_o`: high-priority protection interrupt

## 3. Functional Architecture

The detector is intentionally structured in two processing stages.

### Stage A: Feature Extraction

Stage A derives low-level features from the raw sample stream:

- absolute sample-to-sample difference
- adaptive noise-floor estimate
- effective threshold
- zero-cross / quiet-zone evidence
- thermal envelope

Representative signals:

- `diff_raw_comb`
- `diff_abs_comb`
- `noise_floor_next_comb`
- `effective_thresh_comb`
- `quiet_len_next_comb`
- `quiet_recent_peak_next_comb`
- `env_lp_next_comb`

### Stage B: Decision Logic

Stage B uses Stage A features to decide whether the detector should warn, accumulate, or trip:

- `is_spike_detected`
- `attack_step_comb`
- `integrator_next_comb`
- `spike_sum_next_comb`
- `density_fire_comb`
- `quiet_fire_comb`
- `thermal_fire_comb`
- `trip_cause_code_comb`

This split is important for timing closure and future IP reuse:

- shorter critical path
- cleaner state ownership
- easier formal/property reasoning
- easier register-level debug

## 4. Register Map

All offsets are relative to `DSP_BASE_ADDR = 0x0000_1000`.

| Offset | Access | Name | Description |
| --- | --- | --- | --- |
| `0x00` | RO | `STATUS` | detector live status bits |
| `0x04` | RW | `BASE_THRESH` | base threshold before adaptive noise contribution |
| `0x08` | RW | `INT_LIMIT` | integrator trip limit |
| `0x0C` | RW | `DECAY_RATE` | leaky integrator decay rate |
| `0x10` | RW | `BASE_ATTACK` | base attack added when spike is detected |
| `0x14` | RO | `CURRENT_DIFF_ABS` | current absolute difference |
| `0x18` | RO | `CURRENT_INTEGRATOR` | current integrator value |
| `0x1C` | RO | `PEAK_DIFF_ABS` | peak difference observed |
| `0x20` | RO | `PEAK_INTEGRATOR` | peak integrator observed |
| `0x24` | RO | `EVENT_COUNT` | trip/event counter |
| `0x28` | WO | `CLEAR` | clears latched status/telemetry state |
| `0x2C` | RW | `EXCESS_SHIFT` | weighted-attack right shift |
| `0x30` | RW | `ATTACK_CLAMP` | weighted-attack clamp |
| `0x34` | RO | `CURRENT_ATTACK_STEP` | current weighted attack step |
| `0x38` | RW | `WIN_LEN` | sliding spike window length |
| `0x3C` | RW | `SPIKE_SUM_WARN` | warning density threshold |
| `0x40` | RW | `SPIKE_SUM_FIRE` | density-fire threshold |
| `0x44` | RO | `CURRENT_SPIKE_SUM` | current spike count in window |
| `0x48` | RO | `PEAK_SPIKE_SUM` | peak spike count in window |
| `0x4C` | RW | `PEAK_DIFF_FIRE_THRESH` | peak-diff gate for density fire |
| `0x50` | RW | `ALPHA_SHIFT` | adaptive noise-floor smoothing |
| `0x54` | RW | `GAIN_SHIFT` | adaptive threshold gain shift |
| `0x58` | RO | `CURRENT_NOISE_FLOOR` | current noise-floor estimate |
| `0x5C` | RO | `EFFECTIVE_THRESH` | actual threshold used by detector |
| `0x60` | RO | `STREAM_STATUS` | stream-restart / holdoff live status |
| `0x64` | RO | `STREAM_RESTART_COUNT` | observed restart counter |
| `0x68` | RW | `HOT_BASE` | thermal path base envelope threshold |
| `0x6C` | RW | `HOT_ATTACK` | hotspot accumulation step |
| `0x70` | RW | `HOT_DECAY` | hotspot decay rate |
| `0x74` | RW | `HOT_LIMIT` | thermal trip limit |
| `0x78` | RW | `ENV_SHIFT` | thermal envelope low-pass factor |
| `0x7C` | RO | `CURRENT_ENV_LP` | current thermal envelope |
| `0x80` | RO | `CURRENT_HOTSPOT_SCORE` | current thermal score |
| `0x84` | RW | `ZERO_BAND` | near-zero band for quiet-zone logic |
| `0x88` | RW | `QUIET_MIN` | minimum valid quiet-zone length |
| `0x8C` | RW | `QUIET_MAX` | maximum valid quiet-zone length |
| `0x90` | RO | `CURRENT_QUIET_LEN` | live quiet-zone length |
| `0x94` | RO | `LAST_ZERO_GAP` | last valid quiet-zone width |
| `0x98` | RO | `LAST_FIRE_DIFF` | diff value at last trip cause |
| `0x9C` | RO | `LAST_FIRE_INT` | integrator value at last trip cause |
| `0xA0` | RO | `LAST_CAUSE_CODE` | last trip cause code |
| `0xA4` | RW | `PROFILE_CTRL` | detector profile select / current profile report |

## 5. Cause Codes

`LAST_CAUSE_CODE` uses the following values:

| Code | Meaning |
| --- | --- |
| `0` | none |
| `1` | `arc_by_density` |
| `2` | `arc_by_standard` |
| `3` | `thermal` |
| `4` | reserved legacy slot |
| `5` | `quiet_zone` |

Important note: `LAST_CAUSE_CODE` answers “which detector branch last caused a trip-related decision,” not “which waveform feature was largest overall.”

## 6. Reset and Boot Profile

This IP no longer boots into a nearly-disabled advanced feature set.

Current behavior:

- reset applies `DEFAULT_BOOT_PROFILE`
- current default boot profile is `PROFILE_ARC_BALANCED`
- firmware can later switch profile through `PROFILE_CTRL`

Supported profiles:

- `0`: `SAFE_RESET`
- `1`: `ARC_BALANCED`
- `2`: `THERMAL_BAL`
- `3`: `LAB_FULL`

Design intent:

- `SAFE_RESET`: conservative baseline for debug
- `ARC_BALANCED`: practical system default
- `THERMAL_BAL`: biases toward glowing-contact / thermal path
- `LAB_FULL`: aggressive feature enablement for lab characterization

This profile mechanism is the recommended answer when a reviewer asks how the IP balances “safe reset defaults” versus “fully enabled feature set.”

## 7. Handshake and Timing Assumptions

### Stream Contract

- one detector update happens only when `adc_valid_i == 1`
- the sample stream is fire-and-forget; there is no downstream backpressure from DSP to the SPI bridge
- `stream_restart_i` is a trusted pulse from the upstream stream controller

### Detector Holdoff

After `stream_restart_i`, the detector invalidates sample pairing and briefly blocks decision updates until pair-history is re-established. This prevents false spike detection when a fresh stream resumes.

### APB Contract

- APB is single-cycle from the software point of view
- configuration writes take effect on subsequent detector updates
- telemetry reads are non-destructive except where explicitly documented by the source

## 8. System Integration in `top_soc`

In the current SoC:

- `dsp_data_in = bist_active_mode ? bist_data : spi_data_val`
- `dsp_valid_in = bist_active_mode ? bist_valid : spi_data_rdy`
- `irq_arc_critical = bist_active_mode ? 1'b0 : dsp_irq_raw_output`

This means:

- in normal mode, DSP sees live samples from `apb_spi_adc_bridge`
- in BIST mode, DSP is stimulated by `logic_bist`
- DSP interrupt is suppressed during BIST to avoid tripping normal protection logic

## 9. Verification Evidence

System-level and DSP-focused tests already cover the advanced features.

### Full-System Bench

Source: `sim/tb_professional.sv`

- `SC16`: weighted attack
- `SC17`: sliding-window spike density
- `SC18`: adaptive noise floor + effective threshold
- `SC19`: stream restart awareness
- `SC24`: CPU paged MMIO + 16-bit DSP access
- `SC25`: boot profile / profile load

### DSP-Focused Bench

Source: `sim/tb_dsp_upgrades.sv`

- `SC16`: weighted attack
- `SC17`: spike window
- `SC18`: adaptive noise floor
- `SC19`: stream awareness
- `SC20`: thermal path
- `SC21`: default glowing-contact tuning
- `SC22`: zero-cross / quiet-zone
- `SC23`: trip telemetry
- `SC25`: boot profile / profile load

Current project regressions pass with these scenarios enabled.

## 10. Reuse Notes

What makes this block reusable already:

- stable APB slave abstraction
- parameterized data and counter widths
- explicit register map
- profile-based reset strategy
- telemetry strong enough for FPGA bring-up and tuning

What still limits “drop-in catalog IP” maturity:

- APB interface is tied to the project’s `APB_BUS` abstraction rather than an externally packaged bus wrapper
- formal interface timing assumptions are not yet documented as assertions
- no standalone synthesis timing report is packaged with the IP
- no separate versioned programmer’s model document exists outside the repo

## 11. Known Current Scope

This detector is intentionally richer than a simple demo, but it is still tuned to this project’s protection problem. It should currently be described as:

“A configurable APB-based arc / thermal detection IP with telemetry and profile support, validated inside the `In_SOC` mini-system.”

That phrasing is strong, honest, and defensible in a committee setting.
