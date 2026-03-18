+ Project Overview

INTELLI-SAFE SoC is a custom hardware architecture written in SystemVerilog. It is designed to process analog signals from sensors, detect dangerous electrical arc faults, and trigger immediate safety responses (e.g., cutting off power relays).




+ Key Features & Architecture

Processing Core: 8-bit CPU for system control and decision making.

Bus Protocol: AMBA APB v3.0 (32-bit) Interconnect.

DSP Module: Hardware accelerator for Arc Fault Detection.

Safety Mechanisms: Safety Watchdog Timer.

Logic BIST for self-diagnostic.

Fail-safe I/O for Relay control.

Peripherals: SPI (ADC Driver), UART, Hardware Timer, and GPIOs.




+ Tools & Environment

Hardware Description Language: SystemVerilog

Synthesis: Intel (Altera) Quartus Prime

Simulation: Questa Altera Starter FPGA Edition / ModelSim

Waveform Viewer: GTKWave




+ How to Run the Simulation

Open Questa/ModelSim.

Create a new project and add tb_professional.sv files.

Compile all files.


