# QVision on RealDigital / CoreEL Blackboard Zynq Board

This guide provides instructions for building, simulating, and deploying the **QVision QR Code Generator** on the **RealDigital / CoreEL Blackboard Rev D** FPGA board featuring the **Xilinx XC7007S Zynq-7000 SoC**.

---

## 1. Hardware Architecture Overview

```text
UART RX (Pin Y11) ──► Buffer ──► QR Encoder ──► RS Encoder ──► Matrix Builder ──► Dual-Port Framebuffer ──► Pixel Mapper ──► VGA Output (640x480@60Hz)
                          │                                                                ▲
                     Format BCH ───────────────────────────────────────────────────────────┘
```

- **Target Board**: RealDigital Blackboard Rev D (XC7Z007S-1CLG400C)
- **Input Clock**: 100 MHz System Clock (Pin `H16`)
- **Pixel Clock**: 25 MHz generated via 7-Series MMCM (`MMCME2_BASE`)
- **Control Inputs**: Active-low Reset `SW0` (Pin `N15`), Commit Button `BTN0` (Pin `R18`), Clear Button `BTN1` (Pin `P16`)
- **UART Input**: 115,200 Baud 8N1 (Pin `Y11` / PMODA)
- **Outputs**: 4-bit per color VGA (`vga_r`, `vga_g`, `vga_b`, `vga_hs`, `vga_vs`) + 4 Status LEDs (`led[3:0]`)

---

## 2. Quick-Start Commands

### Run Full Pipeline Simulation (Icarus Verilog)
```bash
tclsh scripts/run_simulation.tcl
```

### Synthesize & Generate Bitstream (Vivado Batch Mode)
```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

---

## 3. Step-by-Step Vivado GUI Flow

1. Open Vivado and create a new project `qvision_blackboard`.
2. Target Part: **`xc7z007sclg400-1`**.
3. Add all Verilog sources from `./rtl/*.v`.
4. Add constraints file `./xdc/blackboard_qvision.xdc`.
5. Set `qvision_top` as top-level module.
6. Click **Generate Bitstream** in the Flow Navigator.
7. Bitstream file will be written to:
   `./vivado_qvision/qvision_blackboard.runs/impl_1/qvision_top.bit`

---

## 4. Hardware Testing & Usage

1. Connect the Blackboard board via USB programming cable.
2. Program the board using Vivado Hardware Manager with `qvision_top.bit`.
3. Connect a VGA display to the VGA output.
4. Connect a USB-to-UART adapter to PMODA Pin 1 (Baud rate: **115200 8N1**).
5. Type text (up to 17 bytes) into your terminal program (e.g. Minicom / PuTTY / TeraTerm).
6. Press **BTN0 (Commit)** to generate and render the QR code on the VGA monitor.
7. Press **BTN1 (Clear)** to reset the buffer for a new text payload.

### LED Status Indicators:
- **`LED[0]`**: Encoding Done / Framebuffer Ready
- **`LED[1]`**: UART RX Activity
- **`LED[2]`**: Buffer Committed
- **`LED[3]`**: Buffer Overflow / Error
