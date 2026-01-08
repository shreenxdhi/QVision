# QVision

QR code encoder for FPGA. Takes UART input, outputs QR code on VGA.

## Hardware Requirements

- Spartan-3 or Spartan-6 FPGA
- VGA monitor (640x480@60Hz)
- UART interface (115200 baud)
- 50MHz system clock

## Features

- QR Version 1-M (21x21, up to 17 bytes)
- Reed-Solomon error correction (10 ECC bytes)
- BCH format encoding
- Mask pattern 0
- UART receiver with buffer
- Dual-port framebuffer
- VGA timing generator

## Architecture

```
UART RX → Buffer → QR Encoder → RS Encoder → Matrix Builder → Framebuffer → VGA Out
                      ↓
                  Format BCH
```

Circular buffer collects UART bytes until commit button pressed. Encoder adds mode/length/padding to 26 codewords. RS encoder generates 10 parity bytes in GF(256). Matrix builder draws finders, timing patterns, then data bits. Framebuffer is 441-bit dual-port memory. Pixel mapper scales 21x21 modules to 6x6 pixels each.

Note: RS encoder uses pre-calculated generator polynomial for V1-M.

## Build

**ISE 14.7:**
1. Create project, add all `rtl/*.v` files
2. Edit `rtl/qvision_config.vh` for your clock frequency
3. Copy `ucf/spartan6_generic.ucf`, update pin assignments
4. Synthesize → Implement → Generate bitstream

**Clock:** 50MHz default. Change `CLK_IN_HZ` in config if different.

## Pin Configuration

Update UCF file with your board pins:
- `clk_in` - System clock
- `rst_n` - Reset button (active low)
- `uart_rx` - UART receive
- `btn_commit` - Commit buffer
- `btn_clear` - Clear buffer
- `vga_hs/vs` - VGA sync
- `vga_r/g/b[3:0]` - VGA RGB outputs
- `led[3:0]` - Status LEDs

## Usage

1. Program FPGA
2. Connect UART terminal (115200 8N1)
3. Type data bytes
4. Press commit button
5. QR code displays on VGA

LEDs: [0]=encoding done [1]=uart activity [2]=buffer committed

## Simulation

See `SIMULATION_GUIDE.md`. Run `tb_qr_pipeline` in ISim to test full pipeline with "HELLO" test data.

## File Structure

```
rtl/
  qvision_top.v
  qvision_config.vh
  uart_rx.v
  qr_buf.v
  qr_encoder.v
  qr_rs_encoder.v
  qr_format_bch.v
  qr_matrix_builder.v
  qr_framebuffer.v
  qr_pixel_mapper.v
  vga_timing.v
  rgb_dac_out.v
  reset_sync.v
sim/
  tb_qr_pipeline.v
  tb_qr_rs_encoder.v
  tb_qr_matrix_builder.v
  tb_vga_timing.v
  tb_qr_format_bch.v
ucf/
  spartan3_generic.ucf
  spartan6_generic.ucf
scripts/
  build_ise.tcl
```

## Limitations

- V1-M only (21x21 modules)
- Max 17 bytes input
- Single mask pattern (mask 0)
- No alphanumeric/kanji modes (byte mode only)

## License

MIT
