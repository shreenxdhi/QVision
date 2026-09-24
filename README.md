# QVision

QR code encoder for FPGA. Takes UART input, renders an ISO 18004-compliant
QR code on VGA.

## Hardware Requirements

- FPGA board: Xilinx Zynq-7000 (RealDigital Blackboard), Spartan-6 or Spartan-3
- VGA monitor plus an external 3.3-V Pmod resistor-DAC/VGA adapter
  (640x480@60Hz, 25.000 MHz pixel clock; the Blackboard itself exposes HDMI,
  not a parallel-RGB VGA connector)
- UART interface (115200 baud, 8N1)
- 100 MHz system clock (Zynq) or 50 MHz (Spartan-6/3) - see `rtl/qvision_config.vh`

## Features

- **QR versions 1-40** (21x21 up to 177x177 modules), selected automatically
  per message as the smallest version that fits
- **All four EC levels** L/M/Q/H (compile-time `EC_LEVEL` parameter on
  `qvision_top`; the level is a build-time choice, default M)
- **All four encoding modes** with automatic selection:
  numeric, alphanumeric, byte, and kanji (raw Shift-JIS bytes over UART)
- Reed-Solomon error correction over GF(256) for every block layout in the
  ISO table, including the mixed data-block sizes used from V5 on, with
  ISO codeword interleaving
- BCH-protected format information (all versions) and version-information
  blocks for V7+
- **ISO 18004 mask optimisation**: all 8 mask patterns are applied and scored
  with the four standard penalty rules; the best-scoring mask is chosen for
  every message (penalties bit-match the reference library's `lost_point`)
- Alignment-pattern grids, timing patterns, remainder bits
- UART receiver with a 4096-byte input buffer
- Dual-port framebuffer with a dedicated commit pass
- Per-size pixel/module rendering (8x for small versions down to 2x for
  V40) with a 4-module quiet zone, centred on screen

## Architecture

```
UART RX → Buffer → Controller → Packer → RS Encoder → Matrix Builder ─┬→ Framebuffer → Pixel Mapper → VGA Out
                      (scan: mode+      ↓          ↓            ↑        │
                       version fit)  (bit     (per-block    (function patterns,
                                      packing)  LFSR +       zigzag, 8-mask optimiser,
                                                interleave)   format+version BCH)
```

The controller scans the committed payload once to classify the mode
(numeric / alphanumeric / kanji / byte) and to pick the smallest fitting
version, then configures the packer, RS encoder and matrix builder with the
ISO block layout for that (version, EC) and starts them together. The packer
bit-packs `[mode][count][payload][terminator][pad EC/11]`, the RS encoder
computes per-block parity and emits the interleaved codeword sequence, and
the builder draws the function patterns, places the data bits along the
zigzag, evaluates all 8 masks and commits the winning matrix.

All ISO version tables (block layouts, alignment centres, remainder bits,
count-field widths, version-info BCH codes, RS generator polynomials) are
**generated** into `rtl/qr_tables.vh` / `rtl/qr_rs_gen_rom.vh` by
`scripts/gen_tables.py` from the golden model - nothing is hand-typed.

## Build

**Vivado (Zynq Blackboard):**
```bash
vivado -mode batch -source scripts/build_vivado.tcl
```
Bitstream: `vivado_qvision/qvision_blackboard.runs/impl_1/qvision_top.bit`

The latest clean implementation from the current RTL meets both setup and hold
at 100 MHz (WNS +0.181 ns, WHS +0.015 ns), has zero routing/DRC errors, and
uses 4,903 LUTs, 2,142 registers, seven RAMB36 blocks and eight DSP48s on the
XC7Z007S. The batch
script fails instead of accepting a build if timing or implementation fails.

**ISE 14.7 (Spartan-3/6):**
1. Create a project, add all `rtl/*.v` files
2. Select the board family in `rtl/qvision_config.vh` (and set `CLK_IN_HZ`)
3. Copy `ucf/spartan6_generic.ucf` or `spartan3_generic.ucf`, update pins
4. Synthesize → Implement → Generate bitstream

## Pin Configuration

The supplied Blackboard constraints use SW0, BTN0/BTN1, LD0-LD3, Pmod C pin
1 for external UART RX, and Pmod A/B for the external VGA adapter. The mapping
was checked against RealDigital's official Rev-D master XDC. For another board,
update these ports:
- `clk_in` - System clock
- `rst_n` - Reset (active low)
- `uart_rx` - UART receive
- `btn_commit` - Commit buffer
- `btn_clear` - Clear buffer
- `vga_hs/vs` - VGA sync
- `vga_r/g/b[3:0]` - VGA RGB outputs
- `led[3:0]` - Status LEDs

## Usage

For exact CP2102 wiring, Vivado Hardware Manager programming, Windows COM-port
setup, and troubleshooting, see the "Windows + CP2102 quick start" section of
`ZYNQ_BUILD_GUIDE.md`.

1. Program the FPGA
2. Connect a 3.3-V USB-UART adapter to Pmod C pin 1 (RX), with common ground,
   and open a terminal at 115200 8N1. The Blackboard's PROG/UART USB serial
   channel is wired to the Zynq processing system, not directly to this PL pin.
3. Type a message (any length up to the capacity of the built-in EC level at
   V40 - e.g. 2334 bytes at M, 2956 at L, 1276 at H), then press the commit
   button. Longer input is clamped to the largest payload that fits V40 and
   flagged on LED[2].
4. The QR code appears on the VGA display connected through the external Pmod
   resistor-DAC adapter; the buffer clears automatically,
   so you can type the next message immediately
5. Kanji input: send raw Shift-JIS bytes (the encoder does not convert
   UTF-8); a message qualifies for kanji mode only when every byte pair is a
   valid Shift-JIS character

**EC level choice** (`EC_LEVEL` parameter, `qvision_top.v`):
0 = L (largest capacity), 1 = M (default, balanced), 2 = Q, 3 = H (most
robust, smallest capacity). E.g. V40 capacity: L 2956 B / M 2334 B /
Q 1666 B / H 1276 B.

**LEDs:**
- `LED[0]` - QR committed to the display (encoding done)
- `LED[1]` - UART activity (toggles per byte)
- `LED[2]` - Error: buffer overflow, or payload clamped to fit V40
- `LED[3]` - UART framing error

## Simulation

```bash
# python venv for the verification tools (once)
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --requirement requirements.txt

tclsh scripts/run_simulation.tcl  # self-checking end-to-end simulation
python scripts/regression.py      # full regression against the golden model
python scripts/gen_tables.py      # regenerate the RTL tables
```

`scripts/regression.py` compares every pipeline stage against
`scripts/golden_model.py`, which is itself cross-checked against the
`qrcode` reference library (forced-mask grid across versions 1-40) and
decoded from rendered images with zxing-cpp / OpenCV. See
`SIMULATION_GUIDE.md`. Rendered examples of simulated output:
`docs/simulated_qr_hello.png` (V1, scans as "HELLO") and
`docs/simulated_qr_v40.png` (V40-M, 2334 bytes).

## File Structure

```
rtl/
  qvision_top.v           top level
  qvision_config.vh       board / clock / QR capacity constants
  qr_tables.vh            GENERATED: ISO tables for V1-40 (layouts,
                          alignment centres, remainders, count widths,
                          version-info BCH)
  qr_rs_gen_rom.vh        GENERATED: RS generator polynomials (parity 7-30)
  uart_rx.v               115200 8N1 receiver
  qr_buf.v                4096-byte input buffer
  qr_controller.v         payload scan, mode + version selection, pipeline
                          start/sequencing
  qr_encoder.v            ISO bit packing: numeric / alnum / byte / kanji
  qr_rs_encoder.v         Reed-Solomon ECC, GF(256), multi-block with mixed
                          data sizes, ISO interleaved output
  qr_format_bch.v         BCH(15,5) format information
  qr_matrix_builder.v     function patterns + alignment grid + version info,
                          zigzag placement, 8-mask penalty optimisation,
                          framebuffer commit
  qr_framebuffer.v        31329-bit dual-port BRAM
  qr_pixel_mapper.v       per-size module scaling + quiet zone
  vga_timing.v            640x480@60 Hz timing generator
  rgb_dac_out.v           1-bit -> RGB output
  reset_sync.v            reset synchroniser
  pix_clk_gen.v           25 MHz pixel clock from the board clock
  qvision_sram.v          inferred memories for simulation and FPGA builds
sim/
  tb_qr_pipeline.v        end-to-end testbench (self-checking; +PRELOAD for
                          large payloads)
  tb_qr_packer.v          packer unit test (all modes)
  tb_qr_matrix_builder.v  matrix builder unit test (any version)
  tb_qr_rs_multiblock.v   RS unit test (any block layout)
  tb_qr_format_bch.v      format BCH unit test
  tb_vga_timing.v         VGA timing measurement
scripts/
  build_vivado.tcl        Vivado batch build (Blackboard)
  run_simulation.tcl      self-checking simulation
  regression.py           full regression vs golden model
  golden_model.py         Python golden model of the whole encoder (V1-40)
  gen_tables.py           regenerates rtl/qr_tables.vh + qr_rs_gen_rom.vh
  send_qr_uart.py         sends a payload to the board over a COM port
xdc/
  blackboard_qvision.xdc  RealDigital Blackboard constraints
ucf/                      Spartan-3 / Spartan-6 constraint templates
docs/
  simulated_qr_hello.png  simulated V1-M output (scans as "HELLO")
  simulated_qr_v40.png    simulated V40-M output (2334 bytes)
ZYNQ_BUILD_GUIDE.md      board wiring, programming, and usage walkthrough
```

## Limitations

- Single-segment encoding only (no mixed-mode segment optimisation; a
  message is either all-numeric, all-alphanumeric, all-kanji or byte)
- No ECI / structured-append / FNC1 headers (parity with the reference
  library, which does not support them either)
- Generator, not decoder (reading QR codes is a separate project)
- Kanji input is raw Shift-JIS bytes over UART (no on-chip UTF-8 → SJIS
  conversion)
- The input buffer holds 4096 bytes; payloads beyond the selected EC level's
  V40 capacity are clamped (LED[2])

## License

MIT
