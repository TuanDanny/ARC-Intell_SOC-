# `logic_bist` IP Specification

## 1. Purpose

`logic_bist` is the project’s built-in self-test support block for stimulating the DSP path and compressing its response into a signature.

In its current form, this is best described as a **functional BIST helper IP** for the DSP subsystem, not a full scan-based LBIST solution.

## 2. Top-Level Interface

Source RTL: `rtl/periph/logic_bist.sv`

### Clock / Reset

- `clk_i`
- `rst_ni`

### APB-Lite Style Programming Interface

- `paddr_i[4:0]`
- `pwdata_i[31:0]`
- `psel_i`
- `penable_i`
- `pwrite_i`
- `prdata_o[31:0]`
- `pready_o`
- `pslverr_o`

### DSP Stimulation Outputs

- `bist_data_o[15:0]`
- `bist_valid_o`
- `bist_active_o`

### DSP Observation Input

- `dsp_irq_i`

## 3. Functional Model

The block contains three main ideas:

1. A pseudo-random pattern generator (`LFSR`)
2. A run controller (`IDLE / RUN / COMPLETE`)
3. A response compactor (`MISR`)

Operationally:

- software writes `CTRL.start`
- BIST enters `RUN`
- pseudo-random data is driven toward DSP
- DSP response bit `dsp_irq_i` is compressed into a 16-bit signature
- on completion, software reads the signature and status

## 4. Register Map

All offsets are relative to `BIST_BASE_ADDR = 0x0000_6000`.

| Offset | Access | Name | Description |
| --- | --- | --- | --- |
| `0x00` | RW | `CTRL` | bit0=`start` (self-clearing), bit1=`reset logic` |
| `0x04` | RW | `CONFIG` | test length in cycles |
| `0x08` | RW | `SEED` | initial LFSR seed |
| `0x0C` | RO | `SIGNATURE` | final MISR signature |
| `0x10` | RO | `STATUS` | bit0=`busy`, bit1=`done`, bit2=`mismatch/placeholder error` |

## 5. Output Contract

During active test:

- `bist_active_o = 1`
- `bist_valid_o = 1`
- `bist_data_o = current LFSR value`

This contract is used by `top_soc` to mux DSP input away from the live SPI stream and toward the BIST stimulus stream.

## 6. Reset / Default Behavior

After reset:

- state returns to `IDLE`
- default seed is `16'hACE1`
- done/busy flags clear
- signature clears

The block also protects against a zero LFSR seed by replacing it with the default non-zero seed.

## 7. System Integration in `top_soc`

`logic_bist` is wired as follows in the current SoC:

- BIST data can replace normal SPI sample input to DSP
- BIST valid can replace normal stream valid to DSP
- while BIST is active, DSP trip interrupt is masked away from the main protection path

This is an important integration assumption:

- BIST is a lab / diagnostic operating mode
- BIST is not intended to trip the real protection output path during self-test

## 8. Verification Evidence

Current regressions validate that:

- BIST can drive DSP input path
- BIST control and status can be accessed through APB
- signature path works end-to-end inside the SoC context

The system bench also includes BIST-related scenarios as part of the extra scenario collection.

## 9. Reuse Notes

What is reusable already:

- clean APB-programmable control model
- compact functional-BIST style stimulus path
- response compaction via MISR
- explicit `active` and `valid` outputs for downstream muxing

What still limits full standalone IP maturity:

- no on-chip golden signature compare
- “mismatch” is still a simplified placeholder rule
- only a 1-bit DSP response is observed
- no autonomous startup / scheduled self-test policy
- no packaged BIST result-handling policy beyond software polling

## 10. Honest Positioning

The most defensible description today is:

“`logic_bist` is a reusable APB-configurable functional BIST block for the DSP path, suitable for lab validation and architectural demonstration. It is not yet a complete production LBIST subsystem.”

That wording is both strong and honest.
