# FPGA Real-Time Data Acquisition System

## Overview

This system integrates five independent data acquisition modules operating at different sampling rates (0.5-10 Hz), managed through a custom AXI4-Stream round-robin arbiter. Data is transmitted via UART (115200 baud) in human-readable ASCII format to a Python terminal interface for real-time visualization.

**Features:**
* XADC dual-channel operation for concurrent voltage (0-1V) and FPGA die temperature monitoring
* Debounced button press counter
* AXI4-Stream transaction counter
* System runtime tracker (seconds since reset)
* Custom AXI4-Stream interconnect with round-robin arbiter
* Two-stage pipelined UART formatter achieving 100 MHz timing closure

[![Demo Video](https://img.youtube.com/vi/g9YRMXwytmA/hqdefault.jpg)](https://www.youtube.com/watch?v=g9YRMXwytmA)

## Installation

### Prerequisites
* Xilinx Vivado 2024.2 or compatible
* Basys3 FPGA board
* Python with `pyserial` library

### Setup
1. Clone the repository
2. Install Python dependencies: `pip install pyserial`
3. Open project in Vivado and generate bitstream
4. Program the Basys3 FPGA
5. Connect analog voltage source (0-3.3V) to VAUXP15/VAUXN15 (JXADC header) as shown below
<img width="424" height="246" alt="image" src="https://github.com/user-attachments/assets/93037c2c-7c71-4bb7-9f46-09333fce8630" />

6. Run terminal monitor with your computer's COM port: `python terminal_monitor.py COM#`

### Hardware Controls
* **BTNC (Center)**: System reset
* **BTNU/BTND/BTNL/BTNR**: Trigger button press events
* **Potentiometer**: Increase/decrease voltage reading

## Project Structure

**monitor_top.sv**  
Top-level integration connecting all subsystems. Instantiates XADC wrapper, five monitor modules, AXI arbiter, UART formatter, and UART transmitter.

**xadc_wrapper.sv**  
XADC wrapper managing dual-channel operation. Alternates between reading temperature (Channel 0) and voltage (Channel 15).

**voltage_monitor.sv**  
Processes XADC voltage data with 256-sample moving-average filter and scales to millivolts. Outputs via AXI4-Stream at 10 Hz sampling rate.

**temperature_monitor.sv**  
Converts XADC raw temperature to Celsius using fixed-point arithmetic. Samples at 1 Hz.

**Button monitor.sv**  
Three-stage synchronizer for metastability prevention. Tracks total presses and outputs on button events.

**axi_monitor.sv**  
Counts completed AXI4-Stream transactions (valid && ready handshakes). Samples at 0.5 Hz.

**runtime_monitor.sv**  
Counts seconds since reset using clock divider. Samples at 2 Hz.

**axi_stream.sv**  
Round-robin arbiter managing 5 slave interfaces with fair scheduling. Prevents starvation and includes source identification via TID field.

**uart_formatter.sv**  
Converts 32-bit sensor data to ASCII format. Features two-stage pipelined digit extraction for timing optimization.

**uart_transmitter.sv**  
UART transmitter implementing 8N1 protocol at 115200 baud (868 clocks/bit at 100 MHz).

**terminal_monitor.py**  
Python serial terminal with auto-detection, live display, and data parsing.

## Design Decisions

### AXI4-Stream Protocol Choice
Rather than implementing custom arbitration, I chose AXI4-Stream for three key reasons: built-in flow control via valid/ready handshaking prevents data loss when UART is busy, modular interfaces allow easy addition of new sensors, and it demonstrates understanding of industry-standard protocols. The round-robin scheduling ensures fair access so that faster sensors don't starve slower ones.

### Two-Stage Pipelined Digit Conversion
Initial timing analysis showed -5ns worst negative slack due to division operations in binary-to-decimal conversion. The solution splits digit extraction across two clock cycles: Stage 1 extracts ten-thousands and thousands digits via cascaded comparisons, Stage 2 processes hundreds, tens, and ones from stored remainder. This replaces division with comparison trees and simple subtractors, cutting the combinational critical path down and achieving positive slack at 100 MHz.

### XADC Dual-Channel via DRP
Instead of instantiating two separate XADC cores, I configured DRP mode to alternate between temperature and voltage channels. A state machine sequences: read temperature → read voltage → repeat. This maximizes hardware efficiency while providing concurrent monitoring.
