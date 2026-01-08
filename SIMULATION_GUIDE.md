# Simulation Guide (ISE 14.7)

## Setup

1. Create ISE project (Spartan6, ISim simulator)
2. Add all files from `rtl/` folder
3. Add `sim/tb_qr_pipeline.v` as simulation source
4. Set `tb_qr_pipeline` as top module

## Run

Double-click **Simulate Behavioral Model** under ISim Simulator in Processes pane.

Runtime: ~2ms

## Signals to Watch

Main signals in `dut`:
- `uart_valid` - pulses when byte received
- `buf_committed` - goes high after commit button
- `encoder_done`, `rs_done`, `matrix_done` - pipeline stages completing
- `fb_wr_we` - framebuffer writes (expect ~290 pulses for data area)
- `led[0]` - encoding complete indicator

## Timeline

- 0-100ns: Reset
- 200ns-44us: UART sends "HELLO" (5 bytes @ 115200 baud)
- ~45us: Commit button pressed
- 45-200us: Encoding pipeline runs
- 200us+: VGA output active

## Troubleshooting

**X values everywhere:** Reset not applied properly or missing initialization

**"Undefined module" errors:** Missing RTL file, check all 12 modules are added

**Simulation hangs:** Set run time limit to 2ms in ISim properties

**No VGA output:** Check clock is 50MHz, verify reset releases

## Other Testbenches

Individual module tests available:
- `tb_vga_timing.v`
- `tb_qr_rs_encoder.v`
- `tb_qr_matrix_builder.v`
- `tb_qr_format_bch.v`

## Pass Criteria

- `matrix_done` goes high (~280us)
- `fb_wr_we` pulses ~290 times (data area only)
- Black pixels detected in VGA output (>6000 pixels)
- Console shows "PASS"
