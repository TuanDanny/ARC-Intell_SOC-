# Firmware Images

This folder contains external instruction images for the `cpu_8bit` control CPU.

## Default image

- `cpu_program.hex`

The CPU now loads its program through `$readmemh` instead of hardcoding instructions inside RTL. That means:

- policy changes can be made without editing the CPU datapath
- different firmware profiles can be prepared later
- simulation and maintenance become easier

## Current memory map

The default image preserves the same behavior as the previous hardcoded ROM:

- `0x00` : jump to main program
- `0x01..0x03` : arc-fault ISR
- `0x04..0x07` : main startup program
- `0x08` : idle loop
- `0x09` : timer ISR

## File format

- one 16-bit instruction per line
- hexadecimal text, compatible with `$readmemh`
- `//` comments are allowed

Example:

```text
5004
7020
F000
```
