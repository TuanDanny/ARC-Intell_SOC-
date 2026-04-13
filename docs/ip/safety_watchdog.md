# `safety_watchdog` IP Specification

## 1. Purpose

`safety_watchdog` is the system watchdog peripheral. It provides a software-fed timeout monitor and raises a reset request pulse when software fails to feed it correctly.

In the current project, this is a **basic watchdog IP**, not yet a full independent-windowed safety watchdog. That distinction is important and should be stated clearly in review discussions.

## 2. Top-Level Interface

Source RTL: `rtl/periph/safety_watchdog.sv`

### Clock / Reset

- `clk_i`
- `rst_ni`

### APB-Lite Style Slave Signals

- `paddr_i[3:0]`
- `pwdata_i[31:0]`
- `psel_i`
- `penable_i`
- `pwrite_i`
- `prdata_o[31:0]`
- `pready_o`
- `pslverr_o`

### Output

- `wdt_reset_o`: active-high reset request pulse

## 3. Register Map

All offsets are relative to `WATCHDOG_BASE_ADDR = 0x0000_5000`.

| Offset | Access | Name | Description |
| --- | --- | --- | --- |
| `0x0` | RW | `CTRL` | bit0=`enable`, bit1=`lock` |
| `0x4` | RW | `TIMEOUT` | reload value; writable only while unlocked |
| `0x8` | WO | `FEED` | reload counter when magic pattern matches |
| `0xC` | RO | `COUNT` | current counter value |

## 4. Feed Contract

The watchdog is intentionally protected by a magic feed pattern:

- `FEED_PATTERN = 32'hD09_F00D`

Behavior:

- any other feed value is ignored
- exact magic value reloads the counter from `TIMEOUT`

This is a simple but valid mitigation against accidental feeding by runaway software.

## 5. Reset / Default Behavior

Default timeout parameter:

- `DEFAULT_TIMEOUT = 32'h00FF_FFFF`

After reset:

- watchdog starts disabled
- timeout register is loaded with default
- counter mirrors timeout value
- lock bit is cleared

When enabled:

- counter decrements every `clk_i`
- when the counter reaches zero, internal expiry is asserted
- `wdt_reset_o` is pulsed high for a short fixed duration

The RTL currently implements a reset pulse width of roughly 16 cycles using `r_rst_pulse_cnt`.

## 6. Handshake and Timing Assumptions

- APB accesses complete in a single cycle from the software point of view
- `pready_o` is always ready
- `pslverr_o` is always zero

This means the IP is easy to integrate, but it also means there is no wait-state or fault-reporting refinement yet.

## 7. Lock Behavior

The lock mechanism is one-way until reset:

- once `CTRL.lock` is set, timeout/config writes are blocked
- reset clears the lock

This is a useful “configuration freeze” feature, but it is not yet a full safety state-retention mechanism.

## 8. System Integration in `top_soc`

The watchdog is instantiated as a normal APB slave in `top_soc` and contributes `wdt_reset_o` into the system reset strategy.

Important system-level note:

- `safety_watchdog` generates the reset request
- `top_soc` stretches / holds system reset behavior around that request

So the effective safety behavior is the combination of:

- local watchdog pulse generation
- top-level reset hold logic

When describing the design to reviewers, it is better to say:

“The watchdog IP raises a reset request, while the SoC top-level defines the final system reset policy.”

## 9. Verification Evidence

Current project regression covers watchdog integration at the system level through `tb_professional.sv`.

What has been validated already:

- configuration through APB
- timeout expiration
- reset pulse generation
- overall SoC response path

What is not yet a standalone documented IP test plan:

- wrong feed values across many corner cases
- lock-after-config programming strategy
- exhaustive pulse-width checks as a block-level regression

## 10. Reuse Notes

What is reusable already:

- small APB-compatible watchdog peripheral
- explicit programming model
- lockable timeout register
- magic-pattern feed protection

What still limits “full reusable safety IP” maturity:

- no independent watchdog clock
- no windowed watchdog behavior
- no retained cause/status register
- no pre-timeout interrupt
- no explicit post-reset recovery policy inside the IP

## 11. Honest Positioning

The strongest honest description today is:

“`safety_watchdog` is a basic APB-configurable watchdog IP with lockable timeout and reset-request generation. It is reusable as a simple watchdog peripheral, but not yet a full independent-windowed safety watchdog IP.”

That wording is technically accurate and defensible.
