# `dsp_arc_detect` Register Map

Date: 2026-04-26

This document completes task T4 for the primary IP candidate. It is the programmer-facing register map for `dsp_arc_detect`.

## 1. Addressing

All offsets are local to the detector IP.

In the current `top_soc` reference integration:

- DSP base address is `0x0000_1000`
- absolute system address = `0x0000_1000 + offset`

In the public wrapper:

- the wrapper forwards `paddr_i[31:0]`
- the core decodes `paddr_i[7:0]`
- the integrator may place the IP at any aligned base address as long as the low offset byte is preserved

## 2. Access Types

| Type | Meaning |
| --- | --- |
| `RO` | Read-only |
| `RW` | Read/write |
| `WO` | Write-only command register |

Writes to unsupported or read-only offsets are ignored. Reads from unsupported offsets return zero. Reserved bits read as zero unless documented otherwise.

## 3. Reset Profile

The reset values below assume the current boot profile:

- `DEFAULT_BOOT_PROFILE = PROFILE_ARC_BALANCED`

The profile mechanism means several configuration reset values are not the raw `DEFAULT_*` constants. They are the values loaded by the `ARC_BALANCED` profile at reset.

## 4. Register Summary

| Offset | Name | Access | Reset Value | Description |
| --- | --- | --- | --- | --- |
| `0x00` | `STATUS` | RO | `0x0000_0000` | Detector live status |
| `0x04` | `BASE_THRESH` | RW | `0x0000_0050` | Base threshold before adaptive contribution |
| `0x08` | `INT_LIMIT` | RW | `0x0000_03E8` | Integrator trip limit |
| `0x0C` | `DECAY_RATE` | RW | `0x0000_0001` | Integrator decay rate |
| `0x10` | `BASE_ATTACK` | RW | `0x0000_000A` | Base attack step for spike events |
| `0x14` | `CURRENT_DIFF_ABS` | RO | `0x0000_0000` | Current committed absolute sample difference |
| `0x18` | `CURRENT_INTEGRATOR` | RO | `0x0000_0000` | Current arc integrator value |
| `0x1C` | `PEAK_DIFF_ABS` | RO | `0x0000_0000` | Peak committed diff observed |
| `0x20` | `PEAK_INTEGRATOR` | RO | `0x0000_0000` | Peak integrator observed |
| `0x24` | `EVENT_COUNT` | RO | `0x0000_0000` | Trip/event counter |
| `0x28` | `CLEAR` | WO | N/A | Write command to clear sticky/telemetry state |
| `0x2C` | `EXCESS_SHIFT` | RW | `0x0000_0004` | Right shift for weighted excess attack |
| `0x30` | `ATTACK_CLAMP` | RW | `0x0000_000F` | Maximum weighted excess attack term |
| `0x34` | `CURRENT_ATTACK_STEP` | RO | `0x0000_0000` | Last committed attack step |
| `0x38` | `WIN_LEN` | RW | `0x0000_0020` | Sliding spike window length |
| `0x3C` | `SPIKE_SUM_WARN` | RW | `0x0000_0003` | Spike density threshold for WARN gating |
| `0x40` | `SPIKE_SUM_FIRE` | RW | `0x0000_0014` | Spike density threshold for density FIRE |
| `0x44` | `CURRENT_SPIKE_SUM` | RO | `0x0000_0000` | Current spike count inside window |
| `0x48` | `PEAK_SPIKE_SUM` | RO | `0x0000_0000` | Peak spike-window count |
| `0x4C` | `PEAK_DIFF_FIRE_THRESH` | RW | `0x0000_00DC` | Peak-diff gate for density/quiet decisions |
| `0x50` | `ALPHA_SHIFT` | RW | `0x0000_0002` | Noise-floor smoothing shift |
| `0x54` | `GAIN_SHIFT` | RW | `0x0000_0003` | Noise-floor gain contribution shift |
| `0x58` | `CURRENT_NOISE_FLOOR` | RO | `0x0000_0000` | Current adaptive noise estimate |
| `0x5C` | `EFFECTIVE_THRESH` | RO | `0x0000_0050` | Base threshold plus adaptive contribution |
| `0x60` | `STREAM_STATUS` | RO | `0x0000_0000` | Stream restart and holdoff status |
| `0x64` | `STREAM_RESTART_COUNT` | RO | `0x0000_0000` | Count of observed stream restarts |
| `0x68` | `HOT_BASE` | RW | `0x0000_01F4` | Thermal envelope threshold |
| `0x6C` | `HOT_ATTACK` | RW | `0x0000_0020` | Thermal hotspot attack step |
| `0x70` | `HOT_DECAY` | RW | `0x0000_0004` | Thermal hotspot decay rate |
| `0x74` | `HOT_LIMIT` | RW | `0x0000_0060` | Thermal trip limit |
| `0x78` | `ENV_SHIFT` | RW | `0x0000_0004` | Thermal envelope low-pass shift |
| `0x7C` | `CURRENT_ENV_LP` | RO | `0x0000_0000` | Current thermal envelope |
| `0x80` | `CURRENT_HOTSPOT_SCORE` | RO | `0x0000_0000` | Current thermal score |
| `0x84` | `ZERO_BAND` | RW | `0x0000_0006` | Near-zero band for quiet-zone logic |
| `0x88` | `QUIET_MIN` | RW | `0x0000_0002` | Minimum valid zero-cross quiet length |
| `0x8C` | `QUIET_MAX` | RW | `0x0000_0004` | Maximum valid zero-cross quiet length |
| `0x90` | `CURRENT_QUIET_LEN` | RO | `0x0000_0000` | Current quiet-zone length |
| `0x94` | `LAST_ZERO_GAP` | RO | `0x0000_0000` | Last captured zero-cross quiet gap |
| `0x98` | `LAST_FIRE_DIFF` | RO | `0x0000_0000` | Diff value captured at last trip |
| `0x9C` | `LAST_FIRE_INT` | RO | `0x0000_0000` | Integrator value captured at last trip |
| `0xA0` | `LAST_CAUSE_CODE` | RO | `0x0000_0000` | Last trip cause code |
| `0xA4` | `PROFILE_CTRL` | RW | `0x0000_0011` | Active profile and boot profile report |

## 5. Bit Fields

### `STATUS` - `0x00` - RO

| Bits | Reset | Name | Description |
| --- | --- | --- | --- |
| `[1:0]` | `0` | `status` | `0`: SAFE, `1`: WARN, `3`: FIRE |
| `[2]` | `0` | `irq_arc` | Live detector IRQ output |
| `[3]` | `0` | `fire_latched` | Sticky fire/event indication |
| `[4]` | `0` | `sample_pair_valid` | Detector has seen enough samples for pair-wise diff |
| `[31:5]` | `0` | Reserved | Read as zero |

### `CLEAR` - `0x28` - WO

| Bits | Name | Write Behavior |
| --- | --- | --- |
| `[0]` | `clear_fire_latched` | Clears `fire_latched` |
| `[1]` | `clear_peaks` | Clears diff/integrator peaks, attack telemetry, spike peak, quiet telemetry |
| `[2]` | `clear_events` | Clears `EVENT_COUNT`, `LAST_FIRE_DIFF`, `LAST_FIRE_INT`, and `LAST_CAUSE_CODE` |
| `[3]` | Reserved | Ignored |
| `[4]` | `clear_restart_count` | Clears `STREAM_RESTART_COUNT` |
| `[31:5]` | Reserved | Ignored |

### `STREAM_STATUS` - `0x60` - RO

| Bits | Reset | Name | Description |
| --- | --- | --- | --- |
| `[0]` | input-dependent | `stream_restart_live` | Live value of `stream_restart_i` |
| `[1]` | `0` | `detector_holdoff_active` | Restart holdoff is currently active |
| `[31:2]` | `0` | Reserved | Read as zero |

### `LAST_CAUSE_CODE` - `0xA0` - RO

| Code | Meaning |
| --- | --- |
| `0` | None |
| `1` | Arc by spike density |
| `2` | Standard arc integrator trip |
| `3` | Thermal/glowing-contact trip |
| `4` | Reserved legacy slot |
| `5` | Quiet-zone trip |

### `PROFILE_CTRL` - `0xA4` - RW

| Bits | Reset | Name | Description |
| --- | --- | --- | --- |
| `[3:0]` | `1` | `active_profile` | Current active profile |
| `[7:4]` | `1` | `boot_profile` | Compile-time boot profile report |
| `[31:8]` | `0` | Reserved | Read as zero |

Writes use only `pwdata[3:0]`. Invalid profile IDs are sanitized to `SAFE_RESET`.

## 6. Profile IDs

| ID | Name | Description |
| --- | --- | --- |
| `0` | `SAFE_RESET` | Conservative/debug profile |
| `1` | `ARC_BALANCED` | Current boot profile |
| `2` | `THERMAL_BAL` | Thermal/glowing-contact biased profile |
| `3` | `LAB_FULL` | Aggressive lab characterization profile |

Writing `PROFILE_CTRL` applies the selected profile and clears runtime detector state. It does not clear `EVENT_COUNT` unless the reset path or `CLEAR.clear_events` is used.

## 7. Write Side Effects

- Writing `WIN_LEN` clamps the value to `1..64` and clears spike-window history, current spike sum, and peak spike sum.
- Writing `SPIKE_SUM_WARN` or `SPIKE_SUM_FIRE` clamps the value to the current `WIN_LEN`.
- Writing `PROFILE_CTRL` reloads profile configuration and clears runtime detector state.
- Writing `CLEAR` performs command-style clears according to the written bit mask.

## 8. Reset Notes

Reset applies the boot profile, clears runtime detector state, clears event counters, and clears APB response registers.

The `EFFECTIVE_THRESH` reset value is shown as `0x50` because the `ARC_BALANCED` profile loads `BASE_THRESH = 80` and the reset noise floor is zero.

