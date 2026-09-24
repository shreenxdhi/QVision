# QVision on the RealDigital / CoreEL Blackboard (Zynq)

Building, simulating and deploying QVision on the RealDigital Blackboard
(Xilinx XC7Z007S Zynq-7000 SoC).

## Hardware overview

```text
UART RX ──► Buffer ──► Controller ──► Packer ──► RS Encoder ──► Matrix Builder ──► Framebuffer ──► Pixel Mapper ──► VGA (640x480@60Hz)
                          │              │           │                ▲
                    (mode + version  (numeric/   (per-block LFSR,  (function patterns, zigzag,
                     selection)       alnum/byte/ mixed block      8-mask penalty optimisation,
                                      kanji)     sizes, interleave) format + version BCH)
```

- Target board: RealDigital Blackboard (XC7Z007S-1CLG400C)
- Input clock: 100 MHz system clock (pin `H16`)
- Pixel clock: 25 MHz from a 7-Series MMCM (`MMCME2_BASE`)
- Controls: active-low reset `SW0` (`R17`), commit `BTN0` (`W14`),
  clear `BTN1` (`W13`)
- UART input: 115200 baud 8N1 on Pmod C pin 1 (`V15`) from an external
  3.3-V USB-UART adapter
- Outputs: 4-bit-per-colour VGA on Pmod A/B through an external resistor-
  DAC adapter, plus LD0-LD3 (`N20`, `P20`, `R19`, `T20`)

Note: the Blackboard exposes HDMI, not an onboard parallel-RGB VGA
connector, and its PROG/UART serial path is connected to the processing
system. QVision is a PL-only design, so the supplied pinout intentionally uses
external Pmod VGA-DAC and USB-UART adapters. Do not wire FPGA pins directly to
the analogue VGA colour inputs; use the adapter's resistor ladder.

## Quick-start commands

### Full simulation (self-checking)
```bash
tclsh scripts/run_simulation.tcl          # single end-to-end sim
python3 scripts/regression.py             # full regression vs golden model
```

### Synthesize and generate bitstream (Vivado batch mode)
```bash
vivado -mode batch -source scripts/build_vivado.tcl
```

## Vivado GUI flow

1. Open Vivado and create a new project `qvision_blackboard`.
2. Target part: `xc7z007sclg400-1`.
3. Add all Verilog sources from `./rtl/*.v`.
4. Add the constraints file `./xdc/blackboard_qvision.xdc`.
5. Set `qvision_top` as the top-level module.
6. Click **Generate Bitstream** in the Flow Navigator.
7. Bitstream file: `./vivado_qvision/qvision_blackboard.runs/impl_1/qvision_top.bit`

After implementation, confirm the timing report is clean.
The RS update and mask evaluation are registered around the SRAM read paths.
The checked XC7Z007S-1 build meets 100 MHz with WNS +0.181 ns and WHS
+0.015 ns. The batch script also rejects negative setup or hold slack; see
`vivado_qvision/qvision_top_timing_signoff.rpt` for the final report.

## Hardware testing and usage

1. Connect the Blackboard board via USB programming cable.
2. Program the board using Vivado Hardware Manager with `qvision_top.bit`.
3. Connect a VGA display to the VGA output.
4. Connect a 3.3-V USB-to-UART adapter to Pmod C pin 1 (`V15`) and board
   ground (115200 8N1).
5. Type text into a terminal program (Minicom / PuTTY / TeraTerm). Any
   length up to the V40 capacity of the built-in EC level is accepted
   (2334 bytes at the default M; 2956 at L, 1666 at Q, 1276 at H) - the
   version (21x21 .. 177x177 modules) and the encoding mode (numeric /
   alphanumeric / byte / kanji) are chosen automatically per message.
   Kanji input is raw Shift-JIS bytes; longer input is clamped to V40 and
   flagged on LED[2].
6. Press BTN0 (commit) to generate and render the QR code. The encoder
   evaluates all 8 ISO mask patterns and renders the message with the
   best-scoring one.
7. The buffer clears automatically after rendering - type the next message
   and commit again. Use BTN1 (clear) only to discard a half-typed
   message before committing.

### LEDs

- `LED[0]` - QR committed to the display (encoding done)
- `LED[1]` - UART RX activity (toggles per byte)
- `LED[2]` - Error: buffer overflow or payload clamped to fit V40
- `LED[3]` - UART framing error

### Scanning the output
Point any phone QR reader at the monitor. The rendered symbol is a fully
compliant QR code (versions 1-40): correct finder/timing/alignment/format
patterns, version information for V7+, standard zigzag data placement,
Reed-Solomon ECC at the built-in level and an optimally chosen mask.
Verified end-to-end in simulation: the framebuffer contents decode back to
the original payload (see `docs/simulated_qr_hello.png` and
`docs/simulated_qr_v40.png`).

## Windows + CP2102 quick start

### What must be connected

The CP2102 is input only for this design; it does not return a QR bitmap to
Windows. The QR image leaves the FPGA through the Pmod A/B VGA signals. To see
it, use a compatible 3.3-V Pmod resistor-DAC/VGA adapter and a VGA monitor (or
a USB VGA-capture device). A normal laptop HDMI socket is an output and cannot
be used as a display input.

With both devices powered off, wire:

```text
CP2102 TXD  -> Blackboard Pmod C pin 1 (FPGA V15 / qvision uart_rx)
CP2102 GND  -> Blackboard GND (use the connector's labelled GND)
CP2102 RXD  -> leave disconnected
CP2102 5V   -> leave disconnected
```

The board must be powered through its normal Blackboard power/programming
connection, not from the CP2102. Use only a CP2102 module whose UART TXD logic
level is 3.3 V; check the module documentation because clone boards differ.
Connect the VGA adapter to Pmod A/B exactly as its manual specifies, then attach
the VGA display. Do not connect digital FPGA pins directly to analogue VGA RGB.

### Driver, programming, and first QR

1. Install Silicon Labs' [CP210x Universal Windows
   Driver](https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers),
   plug in the CP2102, and note its `COM` number under **Device Manager ->
   Ports (COM & LPT)**.
2. Connect the Blackboard programming USB cable, power on the board, and select
   JTAG boot/programming if your board revision has a boot-mode jumper.
3. In Vivado: Open Hardware Manager -> Open Target -> Auto Connect. Right
   click the detected `xc7z007s`, choose Program Device, and select:

   ```text
   vivado_qvision\qvision_blackboard.runs\impl_1\qvision_top.bit
   ```

4. Leave reset released: `SW0=1`. To force a reset, move SW0 to `0` briefly,
   then back to `1`. `LD0` should be off until a QR has completed.
5. Open PuTTY or Tera Term on the CP2102 COM port with 115200 baud, 8 data
   bits, no parity, 1 stop bit, and no flow control. Send/type the payload
   without an unwanted Enter key: CR/LF bytes are valid data and would become
   part of the QR message.
6. Press BTN0 once. Wait for `LD0`; the centred black/white QR appears on
   the VGA display. Scan it with a phone. `LD1` toggles as bytes arrive; `LD2`
   means overflow/clamping and `LD3` means a UART framing error.
7. The input clears automatically after a completed render. BTN1 discards a
   partially typed payload before commit.

For exact transfers, especially spaces, binary bytes, or Japanese text, use
the included Python sender instead of terminal local-echo/input translation:

```powershell
py -m pip install pyserial
py scripts\send_qr_uart.py --port COM5 --text "HELLO FROM QVISION"
py scripts\send_qr_uart.py --port COM5 --encoding shift_jis --text "日本語"
py scripts\send_qr_uart.py --port COM5 --file payload.bin
```

Replace `COM5` with Device Manager's value, then press BTN0. Shift-JIS is
required to select the hardware's QR Kanji mode; UTF-8 text is encoded in byte
mode because the design intentionally does not emit an ECI header.

### Fast fault isolation

- No `LD1` change: swap/check CP2102 TXD (not RXD), common ground, COM port,
  115200 8N1, and confirm TXD is connected to Pmod C pin 1/V15.
- `LD3` lights: wrong baud/format, noisy wiring, missing ground, or wrong logic
  voltage. Reset and retry after correcting it.
- `LD0` lights but the screen is blank: UART worked; check Pmod A/B adapter
  orientation, VGA cable/input selection, and 640x480 support.
- QR is visible but will not scan: verify the complete quiet zone is visible,
  disable monitor scaling/sharpening, avoid glare, and start with `HELLO`.
